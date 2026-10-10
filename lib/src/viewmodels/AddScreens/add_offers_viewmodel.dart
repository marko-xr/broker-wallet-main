import 'dart:async';
import 'dart:io';
import 'package:broker_wallet/src/common/enums/add_offers_mode.dart';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:broker_wallet/src/Views/Widgets/pickup_location_widget.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/services/map_city_geography.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/media_pick_recovery.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_selection.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_source_sheet.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:uuid/uuid.dart';
import '../../common/localization/localization_delegate.dart';
import '../../data/models/ScreensModel/offers_model.dart';
import '../../services/ScreenServices/offer_service.dart';

enum OffersTab { rent, sell }

enum PropertyType { residential, commercial, furnished }

class AddOffersViewModel extends ChangeNotifier
    implements LocationCapableViewModel {
  final OfferService _offerService;

  /// The Offer's own pickers (system Photo Picker, camera) and attachment
  /// sheet. Owner and profile media keep their own pickers.
  final OfferMediaPicker _mediaPicker;
  final Future<OfferMediaSource?> Function(BuildContext context, int remaining)
      _chooseMediaSource;

  // Edit mode properties
  final AddOffersMode _mode;
  final String? _editOfferId;
  OfferModel? _originalOffer;

  // Constructor
  AddOffersViewModel({
    AddOffersMode mode = AddOffersMode.add,
    String? offerId,
    OfferModel? offerData,
    OfferService? offerService,
    bool? usesMediaQueue,
    OfferMediaPicker? mediaPicker,
    Future<OfferMediaSource?> Function(BuildContext context, int remaining)?
        chooseMediaSource,
  })  : _mode = mode,
        _editOfferId = offerId,
        _offerService = offerService ?? OfferService(),
        _mediaPicker = mediaPicker ?? OfferMediaPicker(),
        _chooseMediaSource = chooseMediaSource ??
            ((context, remaining) =>
                showOfferMediaSourceSheet(context, remaining: remaining)),
        _usesMediaQueue = usesMediaQueue ?? SupabaseConfig.useSupabaseAuth {
    if (_mode == AddOffersMode.edit) {
      if (offerData != null) {
        // Use pre-loaded data for instant UI fill
        _originalOffer = offerData;
        _prefillFormWithOffer(offerData);
      } else if (_editOfferId != null) {
        // Fallback: load from network (with delayed spinner)
        _loadOfferForEdit();
      }
    }
    if (_usesMediaQueue) _startOfferMedia();
  }

  // ---------------------------------------------------------------------------
  // Offer media (Supabase mode): identity-based, never URL-based.
  //
  // The form shows three kinds of item, in this order: media already on the
  // server, media in the upload queue, and files picked in this session.
  // Each is addressed by its `mediaObjectId`. Removing a server item or
  // cancelling a queued one takes effect on Save, where the outcome is
  // reported as it actually went; a picked file is simply dropped.
  // ---------------------------------------------------------------------------

  final bool _usesMediaQueue;
  List<OfferMediaRef> _existingMedia = const <OfferMediaRef>[];
  bool _existingMediaResolved = false;
  int _mediaRefreshGeneration = 0;
  final Set<String> _removedExistingIds = <String>{};
  final List<OfferMediaDraft> _drafts = <OfferMediaDraft>[];
  final Set<String> _cancelledUploadIds = <String>{};
  bool _mediaGridExpanded = false;
  String? _createdOfferId;
  StreamSubscription<OfferMediaUploadCompleted>? _uploadCompletions;
  bool _disposed = false;

  /// The Offer this form's media belongs to, once it has an id.
  String? get _mediaOfferId => _editOfferId ?? _offerId;

  /// This form while its Offer has no id yet (see [MediaPickOrigin]).
  final String _mediaPickSession = const Uuid().v4();

  /// Which form a picker opened here belongs to: this account, an Offer, and
  /// this Offer — or this form, until the Offer has an id.
  MediaPickOrigin? get _mediaPickOrigin => MediaPickOrigin.of(
        accountId: _offerService.currentOwnerId,
        parent: MediaParent.offer,
        recordId: _mediaOfferId,
        formSessionId: _mediaPickSession,
      );

  void _startOfferMedia() {
    _offerService.offerMediaUploadChanges.addListener(_onUploadsChanged);
    _uploadCompletions = _offerService.offerMediaUploadCompletions.listen(
      _onUploadCompleted,
      onError: (Object _) {},
    );
    unawaited(_offerService.loadOfferMediaUploads().then((_) {
      if (!_disposed) notifyListeners();
    }));
    final offerId = _editOfferId;
    if (isEditMode && offerId != null) {
      if (_existingMedia.isEmpty) {
        _existingMedia = _offerService.cachedOfferMedia(offerId);
      }
      unawaited(_refreshExistingMedia());
    }
    unawaited(_recoverLostSelection());
  }

  /// Picks Android handed back after it stopped the app while the picker was
  /// open on this same form — this account, this Offer: screened and added
  /// like any other selection, so nothing the user chose is silently lost —
  /// they appear in the form's grid. Another form's pick is never adopted.
  Future<void> _recoverLostSelection() async {
    try {
      final recovered =
          await _mediaPicker.recoverLostSelection(origin: _mediaPickOrigin);
      if (recovered.isEmpty || _disposed) return;
      await addPickedOfferMedia(recovered);
    } catch (_) {
      // Nothing to recover is the normal case; a failure changes nothing.
    }
  }

  void _onUploadsChanged() {
    if (!_disposed) notifyListeners();
  }

  void _onUploadCompleted(OfferMediaUploadCompleted event) {
    if (_disposed || event.offerId != _mediaOfferId) return;
    // The item left the queue: show it as the server item it now is — from
    // the copy this device just adopted — until the refresh confirms it.
    if (!_existingMedia
        .any((ref) => ref.mediaObjectId == event.mediaObjectId)) {
      final cacheKey = offerMediaCacheKey(
        ownerId: event.ownerId,
        mediaObjectId: event.mediaObjectId,
      );
      final offline = OfflineMediaService.instance;
      _existingMedia = [
        ..._existingMedia,
        OfferMediaRef(
          mediaObjectId: event.mediaObjectId,
          cacheKey: cacheKey,
          localFilePath: event.isVideo || cacheKey == null
              ? null
              : offline.getLocalFilePathForMediaId(cacheKey),
          isVideo: event.isVideo,
          posterPath: event.isVideo && cacheKey != null
              ? offline.getLocalFilePathForMediaId(
                  offerMediaPosterKey(cacheKey),
                )
              : null,
          durationMs: event.durationMs,
        ),
      ];
      notifyListeners();
    }
    unawaited(_refreshExistingMedia());
  }

  /// Replaces the server items with the authoritative list. Only the most
  /// recent refresh is applied, so an answer that predates an upload never
  /// hides it.
  Future<void> _refreshExistingMedia() async {
    final offerId = _mediaOfferId;
    final ownerId = _offerService.currentOwnerId;
    if (offerId == null || ownerId == null || ownerId.isEmpty) return;
    final generation = ++_mediaRefreshGeneration;
    try {
      final resolution = await _offerService.resolveOfferMedia(
        offerId: offerId,
        ownerId: ownerId,
      );
      if (_disposed ||
          resolution == null ||
          generation != _mediaRefreshGeneration) {
        return;
      }
      _existingMedia = resolution.items;
      _existingMediaResolved = true;
      notifyListeners();
    } catch (_) {
      // Keep what the Offer model and this device already gave the form.
    }
  }

  List<OfferMediaRef> get _pendingUploads {
    final offerId = _mediaOfferId;
    if (offerId == null) return const <OfferMediaRef>[];
    return _offerService.pendingOfferMedia(offerId);
  }

  OfferMediaRef _draftRef(OfferMediaDraft draft) => OfferMediaRef(
        mediaObjectId: draft.mediaObjectId,
        cacheKey: null,
        localFilePath: draft.kind == OfferMediaKind.image ? draft.path : null,
        isVideo: draft.kind == OfferMediaKind.video,
        posterPath: draft.posterPath,
        durationMs: draft.durationMs,
        displayName: draft.displayName,
        byteLength: draft.byteLength,
      );

  /// Offer media as the form shows it (Supabase mode); empty otherwise.
  List<OfferMediaRef> get offerMediaItems {
    if (!_usesMediaQueue) return const <OfferMediaRef>[];
    final shown = <String>{};
    return [
      for (final ref in _existingMedia)
        if (!_removedExistingIds.contains(ref.mediaObjectId) &&
            shown.add(ref.mediaObjectId))
          ref,
      for (final ref in _pendingUploads)
        if (!_cancelledUploadIds.contains(ref.mediaObjectId) &&
            shown.add(ref.mediaObjectId))
          ref,
      for (final draft in _drafts)
        if (shown.add(draft.mediaObjectId)) _draftRef(draft),
    ];
  }

  /// Whether the Offer media form uses [offerMediaItems].
  bool get usesOfferMediaItems => _usesMediaQueue;

  /// Whether all items are shown rather than the first few.
  bool get mediaGridExpanded => _mediaGridExpanded;

  /// How many items the media grid shows: the first three, or all of them
  /// once "+N more" was tapped.
  int get mediaDisplayCount {
    const collapsed = 3;
    if (!_mediaGridExpanded) return collapsed;
    final count = offerMediaItems.length;
    return count > collapsed ? count : collapsed;
  }

  void showAllMedia() {
    _mediaGridExpanded = true;
    notifyListeners();
  }

  /// Removes the item at [index] of [offerMediaItems]: a picked file at once;
  /// a server item or a queued upload when the Offer is saved.
  void removeOfferMediaAt(int index) {
    final items = offerMediaItems;
    if (index < 0 || index >= items.length) return;
    final ref = items[index];
    final draftIndex =
        _drafts.indexWhere((draft) => draft.mediaObjectId == ref.mediaObjectId);
    if (draftIndex >= 0) {
      _drafts.removeAt(draftIndex);
    } else if (ref.uploadPhase != null) {
      _cancelledUploadIds.add(ref.mediaObjectId);
    } else {
      _removedExistingIds.add(ref.mediaObjectId);
    }
    notifyListeners();
  }

  /// Retries the queued upload at [index] of [offerMediaItems].
  void retryOfferMediaAt(int index) {
    final items = offerMediaItems;
    if (index < 0 || index >= items.length) return;
    final ref = items[index];
    if (ref.uploadPhase != OfferMediaUploadPhase.retryableFailure &&
        ref.uploadPhase != OfferMediaUploadPhase.retrying) {
      return;
    }
    unawaited(_offerService.retryOfferMediaUpload(ref.mediaObjectId));
  }

  @override
  void dispose() {
    _disposed = true;
    if (_usesMediaQueue) {
      _offerService.offerMediaUploadChanges.removeListener(_onUploadsChanged);
      unawaited(_uploadCompletions?.cancel());
    }
    super.dispose();
  }

  // Getters for mode
  bool get isEditMode => _mode == AddOffersMode.edit;
  String? get editOfferId => _editOfferId;

  // Load offer data for editing with delayed spinner pattern
  Future<void> _loadOfferForEdit() async {
    if (_editOfferId == null) return;

    // Use delayed spinner pattern - only show loading if it takes > 500ms
    bool showSpinner = false;
    final delayTimer = Timer(const Duration(milliseconds: 500), () {
      showSpinner = true;
      _isLoading = true;
      notifyListeners();
    });

    try {
      _originalOffer = await _offerService.getOffer(_editOfferId);
      delayTimer.cancel(); // Cancel timer since we're done

      if (_originalOffer != null) {
        _prefillFormWithOffer(_originalOffer!);
      }
    } catch (e) {
      delayTimer.cancel();
      _error = 'Unable to load the offer. Please try again.';
    } finally {
      if (showSpinner) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Prefill form with existing offer data
  void _prefillFormWithOffer(OfferModel offer) {
    // Set basic fields
    tab = offer.offerType == 'rent' ? OffersTab.rent : OffersTab.sell;
    selectedCity = offer.selectedCity;
    selectedAreas = List.from(offer.selectedAreas);
    _location = offer.location;

    // Handle phone number: convert from international format to local format
    _phone = _extractLocalPhoneNumber(offer.phoneNumber);
    countryCode = offer.countryCode;

    _minPrice = offer.minPrice;
    _maxPrice = offer.maxPrice;
    _squareFootage = offer.squareFootage;
    _notes = offer.notes;

    // Property type
    if (offer.propertyType != null) {
      switch (offer.propertyType) {
        case 'residential':
          _propertyType = PropertyType.residential;
          break;
        case 'commercial':
          _propertyType = PropertyType.commercial;
          break;
        case 'furnished':
          _propertyType = PropertyType.furnished;
          break;
      }
    }

    _selectedSpecificPropertyType = offer.specificPropertyType;
    _rooms = offer.rooms;
    _baths = offer.bathrooms;

    // Location data
    _pickUpLocation = offer.pickUpLocation;
    _pickUpLatitude = offer.pickUpLatitude;
    _pickUpLongitude = offer.pickUpLongitude;
    _pickUpAddress = offer.pickUpAddress;

    if (_usesMediaQueue) {
      // Private media is addressed by its identity; a signed URL is only
      // how one item is fetched for a few minutes, never what the form edits.
      if (!_existingMediaResolved) _existingMedia = _initialOfferMedia(offer);
    } else {
      // Media URLs (existing uploaded files)
      _uploadedFileUrls = List.from(offer.mediaUrls);
    }

    notifyListeners();
  }

  /// The Offer's media as this form first shows it, before the Worker's own
  /// list arrives: the ids the Offer was read with, drawn from this device's
  /// copies (or a still-valid signed URL) where it has them.
  List<OfferMediaRef> _initialOfferMedia(OfferModel offer) {
    final offerId = offer.id ?? _editOfferId;
    final held = <String, OfferMediaRef>{
      if (offerId != null)
        for (final ref in _offerService.cachedOfferMedia(offerId))
          ref.mediaObjectId: ref,
    };
    final ids = offer.mediaObjectIds;
    if (ids.isEmpty) return held.values.toList();
    final ownerId = _offerService.currentOwnerId;
    final aligned = offer.mediaUrls.length == ids.length;
    return [
      for (var i = 0; i < ids.length; i++)
        held[ids[i]] ??
            OfferMediaRef(
              mediaObjectId: ids[i],
              cacheKey: ownerId == null
                  ? null
                  : offerMediaCacheKey(
                      ownerId: ownerId,
                      mediaObjectId: ids[i],
                    ),
              signedUrl: aligned ? offer.mediaUrls[i] : null,
            ),
    ];
  }

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Location getters
  String get pickUpLocation => _pickUpLocation;
  double? get pickUpLatitude => _pickUpLatitude;
  double? get pickUpLongitude => _pickUpLongitude;
  String get pickUpAddress => _pickUpAddress;

  // Document ID for proper storage structure
  String? _offerId;

  // Tabs
  OffersTab tab = OffersTab.rent;

  // Media files - replace single file with multiple files
  List<PlatformFile> _selectedFiles = [];
  List<String> _uploadedFileUrls = [];
  List<String> _removedMediaUrls = []; // Track removed existing media
  bool _isUploading = false;

  // Media getters
  List<PlatformFile> get selectedFiles => _selectedFiles;
  List<String> get uploadedFileUrls => _uploadedFileUrls;
  bool get isUploading => _isUploading;
  bool get hasMediaFiles => _usesMediaQueue
      ? offerMediaItems.isNotEmpty
      : _selectedFiles.isNotEmpty || _uploadedFileUrls.isNotEmpty;

  /// Everything that would be on the Offer if it were saved now: the media it
  /// already has (minus anything removed in this session) plus the files just
  /// picked — and, with the upload queue, every queued item that has not been
  /// refused. This is what the 10-item limit counts, exactly as the Media
  /// Worker counts it server-side.
  int get currentMediaCount {
    if (_usesMediaQueue) {
      return offerMediaItems
          .where((ref) =>
              ref.uploadPhase != OfferMediaUploadPhase.permanentFailure)
          .length;
    }
    return _uploadedFileUrls
            .where((url) => !_removedMediaUrls.contains(url))
            .length +
        _selectedFiles.length;
  }

  /// How many more photos or videos this Offer can still take.
  int get remainingMediaSlots =>
      OfferMediaPolicy.remainingSlots(currentMediaCount);

  // Remove the old uploadedFileName related code and replace with:
  @Deprecated('Use selectedFiles instead')
  String get uploadedFileName =>
      _selectedFiles.isNotEmpty ? _selectedFiles.first.name : "";

  // Cities
  final List<String> cities = [
    "Dubai",
    "Abu Dhabi",
    "Sharjah",
    "Ajman",
    "Ras Al Khaimah",
    "Fujairah",
    "Umm Al Quwain",
    "Al Ain",
    "Khor Fakkan"
  ];

  // Selected data
  String selectedCity = "";
  List<String> selectedAreas = [];
  String _location = "";
  String _phone = "";
  String? _phoneError;
  String countryCode = "+971";
  String _minPrice = "";
  String _maxPrice = "";
  String _squareFootage = "";
  String _notes = "";
  String _pickUpLocation = '';
  double? _pickUpLatitude;
  double? _pickUpLongitude;
  String _pickUpAddress = '';

  // Additional fields for offers
  String _uploadedFileName = "";

  // LocationCapableViewModel interface implementation
  @override
  bool get hasSelectedLocation =>
      _pickUpLatitude != null && _pickUpLongitude != null;

  @override
  bool get isLocationLoading => false;

  @override
  LatLng? get selectedLocation {
    if (_pickUpLatitude != null && _pickUpLongitude != null) {
      return LatLng(_pickUpLatitude!, _pickUpLongitude!);
    }
    return null;
  }

  // Helper method to extract local phone number from international format
  String _extractLocalPhoneNumber(String internationalPhone) {
    if (internationalPhone.isEmpty) return '';

    // Remove all non-digits
    final digitsOnly = internationalPhone.replaceAll(RegExp(r'[^\d]'), '');

    // If it starts with 971 (UAE country code), extract the local part
    if (digitsOnly.startsWith('971') && digitsOnly.length == 12) {
      // Convert 971501234567 to 0501234567
      return '0${digitsOnly.substring(3)}';
    }

    // If it's already in local format or doesn't match expected pattern, return as is
    return internationalPhone;
  }

  // Property type
  PropertyType? _propertyType;
  PropertyType? get propertyType => _propertyType;

  String _selectedSpecificPropertyType = "";
  String get selectedSpecificPropertyType => _selectedSpecificPropertyType;

  // Rooms and bathrooms
  int _rooms = 1;
  int get rooms => _rooms;

  int _baths = 1;
  int get baths => _baths;

  // Phone getters and validation
  String get phone => _phone;
  String? get phoneError => _phoneError;

  // Get formatted phone for display (utility method)
  String get formattedPhone =>
      _phone.isNotEmpty ? PhoneInputService.formatPhoneNumber(_phone) : '';

  // Get international phone format (utility method)
  String get internationalPhone =>
      _phone.isNotEmpty ? PhoneInputService.toInternationalFormat(_phone) : '';

  // Check if phone is valid (if provided)
  bool get isPhoneValid => _phone.isEmpty || _phoneError == null;

  // Getters and setters (for other fields)
  String get location => _location;
  set location(String value) {
    _location = value;
    notifyListeners();
  }

  // Updated phone setter with validation
  void setPhone(String value) {
    _phone = value;
    _validatePhone(value);
    notifyListeners();
  }

  // Phone validation method
  void validatePhone(String phone, AppLocalizations localization) {
    if (phone.isEmpty) {
      _phoneError = null;
      return;
    }

    _phoneError = PhoneInputService.getValidationError(
      phone,
      localization.translate,
    );
  }

  // Phone validation method (for internal use without localization)
  void _validatePhone(String phone) {
    if (phone.isEmpty) {
      _phoneError = null;
      return;
    }

    _phoneError = PhoneInputService.getValidationError(
      phone,
      (key) => key, // Fallback without localization
    );
  }

  String get minPrice => _minPrice;
  set minPrice(String value) {
    _minPrice = value;
    notifyListeners();
  }

  String get maxPrice => _maxPrice;
  set maxPrice(String value) {
    _maxPrice = value;
    notifyListeners();
  }

  String get squareFootage => _squareFootage;
  void setSquareFootage(String value) {
    _squareFootage = value;
    notifyListeners();
  }

  String get notes => _notes;
  set notes(String value) {
    _notes = value;
    notifyListeners();
  }

  set uploadedFileName(String value) {
    _uploadedFileName = value;
    notifyListeners();
  }

  // Methods
  void setTab(OffersTab newTab) {
    tab = newTab;
    notifyListeners();
  }

  void selectCity(String city) {
    selectedCity = city;
    selectedAreas.clear(); // Clear areas when city changes
    notifyListeners();
  }

  void selectArea(String area) {
    if (selectedAreas.contains(area)) {
      selectedAreas.remove(area);
    } else if (selectedAreas.length < 3) {
      selectedAreas.add(area);
    }
    notifyListeners();
  }

  void setPropertyType(PropertyType type) {
    _propertyType = type;
    _selectedSpecificPropertyType = ""; // Reset specific type
    notifyListeners();
  }

  void selectSpecificPropertyType(String type) {
    _selectedSpecificPropertyType = type;
    notifyListeners();
  }

  void selectRooms(int roomCount) {
    _rooms = roomCount;
    notifyListeners();
  }

  void selectBaths(int bathCount) {
    _baths = bathCount;
    notifyListeners();
  }

  // Location-related properties
  LatLng? _selectedLocation;
  String _selectedLocationAddress = "";
  bool _isLocationLoading = false;

  // Location-related methods for map picker
  @override
  Future<void> setSelectedLocation(
      LatLng location, BuildContext context) async {
    _pickUpLatitude = location.latitude;
    _pickUpLongitude = location.longitude;

    // Get address from coordinates using geocoding
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        _pickUpAddress = _formatAddress(place);
        _pickUpLocation = _pickUpAddress;
      } else {
        _pickUpAddress =
            '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        _pickUpLocation = _pickUpAddress;
      }
    } catch (e) {
      _pickUpAddress =
          '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
      _pickUpLocation = _pickUpAddress;
    }

    notifyListeners();
  }

  void setPickUpLocation(String v) {
    _pickUpLocation = v;
    notifyListeners();
  }

  /// Format address from placemark
  String _formatAddress(Placemark placemark) {
    List<String> addressParts = [];

    if (placemark.name != null && placemark.name!.isNotEmpty) {
      addressParts.add(placemark.name!);
    }
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      addressParts.add(placemark.street!);
    }
    if (placemark.subLocality != null && placemark.subLocality!.isNotEmpty) {
      addressParts.add(placemark.subLocality!);
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      addressParts.add(placemark.locality!);
    }

    return addressParts.take(3).join(', '); // Limit to first 3 parts
  }

  /// Get current location
  Future<LatLng?> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  /// The Offer media "+": the attachment sheet (Camera / Gallery /
  /// Documents), then the chosen picker, then the same screening as ever.
  ///
  /// Gallery is one native selection of photos and videos together, capped
  /// at the places left; no app-made permission dialog is shown before it
  /// (see [OfferMediaPicker]). Dismissing the sheet or cancelling a picker
  /// changes nothing.
  Future<void> selectMedia(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    // The Offer is already full: say so instead of opening a picker whose
    // every result would be discarded.
    final remaining = remainingMediaSlots;
    if (remaining == 0) {
      _showToast(loc.translate('offerMediaLimitReached'), Colors.red);
      return;
    }

    final List<File> picked;
    try {
      final source = await _chooseMediaSource(context, remaining);
      if (source == null || !context.mounted) return;
      final origin = _mediaPickOrigin;
      switch (source) {
        case OfferMediaSource.gallery:
          picked = await _mediaPicker.pickFromGallery(
            limit: remaining,
            origin: origin,
          );
        case OfferMediaSource.cameraPhoto:
          final photo = await _mediaPicker.capturePhoto(origin: origin);
          picked = [if (photo != null) photo];
        case OfferMediaSource.cameraVideo:
          final video = await _mediaPicker.recordVideo(
            maxDuration: OfferMediaPolicy.maxVideoDuration,
            origin: origin,
          );
          picked = [if (video != null) video];
      }
    } on OfferMediaPickerException catch (error) {
      if (context.mounted) _explainCameraRefusal(context, error.failure);
      return;
    } catch (_) {
      if (context.mounted) {
        _showToast(loc.translate('offerMediaPickerFailed'), Colors.red);
      }
      return;
    }
    if (picked.isEmpty) return; // Cancelled in the picker.

    final outcome = await addPickedOfferMedia(picked);
    if (!context.mounted) return;
    for (final rejection in outcome.rejections) {
      _showToast(loc.translate(rejection.messageKey), Colors.red);
    }
    if (outcome.trimmedByLimit) {
      _showToast(loc.translate('offerMediaLimitTrimmed'), Colors.red);
    }
    if (outcome.duplicates > 0) {
      _showToast(loc.translate('offerMediaAlreadyAdded'), Colors.orange);
    }
    if (outcome.added > 0) {
      Fluttertoast.showToast(
        msg: loc
            .translate('offerMediaAdded')
            .replaceAll('{count}', '${outcome.added}'),
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  /// The camera permission was refused: say so in words, and when only the
  /// system settings can change it, offer to open them.
  void _explainCameraRefusal(
    BuildContext context,
    OfferMediaPickerFailure failure,
  ) {
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (failure == OfferMediaPickerFailure.cameraPermanentlyDenied &&
        messenger != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(loc.translate('cameraPermissionPermanentlyDenied')),
        action: SnackBarAction(
          label: loc.translate('openSettings'),
          onPressed: () => unawaited(openAppSettings()),
        ),
      ));
      return;
    }
    _showToast(loc.translate('cameraPermissionDenied'), Colors.red);
  }

  /// Adds freshly picked files to the form: files already in it (same name
  /// and size as an item picked earlier and not yet uploaded) are skipped,
  /// and the rest are screened against the Offer media rules — the 10-item
  /// total, the size caps, the real type read from the bytes, the video
  /// length, HEIC converted to JPEG — before anything enters the form. Each
  /// accepted file keeps the `mediaObjectId` it was given here for good; the
  /// upload queue copies it into the app's own storage on Save.
  @visibleForTesting
  Future<OfferMediaPickOutcome> addPickedOfferMedia(List<File> picked) async {
    final seen = <String>{
      for (final key in [
        for (final draft in _drafts)
          _pickKey(draft.displayName, draft.byteLength),
        if (_usesMediaQueue)
          for (final ref in _pendingUploads)
            _pickKey(ref.displayName, ref.byteLength),
        for (final file in _selectedFiles) _pickKey(file.name, file.size),
      ])
        if (key != null) key,
    };
    final fresh = <File>[];
    var duplicates = 0;
    for (final file in picked) {
      int? length;
      try {
        length = await file.length();
      } catch (_) {
        length = null; // Unreadable: screening refuses it.
      }
      final key = _pickKey(_fileName(file.path), length);
      if (key != null && !seen.add(key)) {
        duplicates += 1;
        continue;
      }
      fresh.add(file);
    }

    final screened = fresh.isEmpty
        ? const OfferMediaSelectionResult(
            accepted: [], rejections: [], trimmedByLimit: false)
        : await screenOfferMediaSelection(
            candidates: fresh,
            itemsAlreadyOnOffer: currentMediaCount,
          );
    if (_disposed) {
      return OfferMediaPickOutcome(
        added: 0,
        duplicates: duplicates,
        rejections: screened.rejections,
        trimmedByLimit: screened.trimmedByLimit,
      );
    }
    if (_usesMediaQueue) {
      _drafts.addAll(screened.accepted);
    } else {
      // HEIC photos arrive converted, so each accepted file is taken as
      // screened rather than as picked.
      _selectedFiles.addAll([
        for (final draft in screened.accepted)
          PlatformFile(
            name: _fileName(draft.path),
            path: draft.path,
            size: draft.byteLength,
          ),
      ]);
    }
    if (screened.accepted.isNotEmpty) notifyListeners();
    return OfferMediaPickOutcome(
      added: screened.accepted.length,
      duplicates: duplicates,
      rejections: screened.rejections,
      trimmedByLimit: screened.trimmedByLimit,
    );
  }

  static String _fileName(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  static String? _pickKey(String? name, int? length) =>
      name == null || name.isEmpty || length == null ? null : '$name|$length';

  // Remove a selected file
  void removeFile(int index) {
    if (index >= 0 && index < _selectedFiles.length) {
      _selectedFiles.removeAt(index);
      notifyListeners();
    }
  }

  // Remove an uploaded file URL
  void removeUploadedFile(int index) {
    if (index >= 0 && index < _uploadedFileUrls.length) {
      final removedUrl = _uploadedFileUrls.removeAt(index);
      // Track this URL for deletion from Firestore
      _removedMediaUrls.add(removedUrl);
      notifyListeners();
    }
  }

  // Clear all selected files
  void clearAllFiles() {
    if (_usesMediaQueue) {
      // Like removing each item: picked files go now, the rest on Save.
      for (final ref in offerMediaItems) {
        if (ref.uploadPhase != null) {
          _cancelledUploadIds.add(ref.mediaObjectId);
        } else if (!_drafts.any((d) => d.mediaObjectId == ref.mediaObjectId)) {
          _removedExistingIds.add(ref.mediaObjectId);
        }
      }
      _drafts.clear();
      notifyListeners();
      return;
    }
    // Track all existing URLs for removal if we're in edit mode
    if (isEditMode) {
      _removedMediaUrls.addAll(_uploadedFileUrls);
    }
    _selectedFiles.clear();
    _uploadedFileUrls.clear();
    notifyListeners();
  }

  // Get file type for display
  String getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
      return 'image';
    } else if (['mp4', 'mov', 'avi', 'mkv'].contains(extension)) {
      return 'video';
    } else {
      return 'document';
    }
  }

  // Get file icon
  IconData getFileIcon(String fileName) {
    final type = getFileType(fileName);
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      default:
        return Icons.description;
    }
  }

  // Format file size
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Check if any content exists
  bool get hasAnyContent {
    return selectedCity.isNotEmpty ||
        selectedAreas.isNotEmpty ||
        _location.isNotEmpty ||
        _phone.isNotEmpty ||
        _minPrice.isNotEmpty ||
        _maxPrice.isNotEmpty ||
        _squareFootage.isNotEmpty ||
        _notes.isNotEmpty ||
        _pickUpLocation.isNotEmpty ||
        _pickUpAddress.isNotEmpty ||
        hasMediaFiles ||
        _propertyType != null ||
        _selectedSpecificPropertyType.isNotEmpty;
  }

  // the offer model creation
  OfferModel _createOfferModel() {
    final now = DateTime.now();

    // Compute merged media URLs for the final model
    // This will be the final state after all uploads complete
    final mergedMediaUrls = _computeMergedMediaUrls();

    return OfferModel(
      id: isEditMode ? _editOfferId : null,
      userId: '', // Will be set by the service
      offerType: tab == OffersTab.rent ? 'rent' : 'sell',
      selectedCity: selectedCity,
      selectedAreas: List<String>.from(selectedAreas),
      location: _location,
      phoneNumber: _phone,
      countryCode: countryCode,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      squareFootage: _squareFootage,
      notes: _notes,
      propertyType: _propertyTypeToString(_propertyType),
      specificPropertyType: _selectedSpecificPropertyType,
      rooms: _rooms,
      bathrooms: _baths,
      pickUpLocation: _pickUpLocation,
      pickUpLatitude: _pickUpLatitude,
      pickUpLongitude: _pickUpLongitude,
      pickUpAddress: _pickUpAddress,
      uploadedFileName: _usesMediaQueue
          ? _drafts
              .map((draft) => draft.displayName ?? '')
              .where((name) => name.isNotEmpty)
              .join(', ')
          : _selectedFiles
              .map((f) => f.name)
              .join(', '), // Keep for compatibility
      // Private media is never written through the Offer row.
      mediaUrls: _usesMediaQueue ? const <String>[] : mergedMediaUrls,
      createdAt: isEditMode && _originalOffer != null
          ? _originalOffer!.createdAt
          : now,
      updatedAt: now,
    );
  }

  /// Computes the merged media URLs (existing + new - removed)
  /// This represents the final state after all operations complete
  List<String> _computeMergedMediaUrls() {
    final Set<String> mergedUrls = <String>{};

    // Start with existing URLs (those not removed by user)
    final remainingExistingUrls = _uploadedFileUrls
        .where((url) => !_removedMediaUrls.contains(url))
        .toSet();
    mergedUrls.addAll(remainingExistingUrls);

    // Note: New upload URLs will be added by the service after upload completes
    // The service will update the document with the complete merged list

    return mergedUrls.toList();
  }

  // Test helper methods - only expose these in debug/test mode
  @visibleForTesting
  List<String> computeMergedMediaUrlsForTest() => _computeMergedMediaUrls();

  @visibleForTesting
  void setUploadedFileUrlsForTest(List<String> urls) {
    _uploadedFileUrls.clear();
    _uploadedFileUrls.addAll(urls);
  }

  @visibleForTesting
  void setRemovedMediaUrlsForTest(List<String> urls) {
    _removedMediaUrls.clear();
    _removedMediaUrls.addAll(urls);
  }

  @visibleForTesting
  List<String> getRemovedMediaUrlsForTest() => List.from(_removedMediaUrls);

  /// Adds screened picks as [selectMedia] does, without its picker dialog.
  @visibleForTesting
  void addOfferMediaDraftsForTest(List<OfferMediaDraft> drafts) {
    _drafts.addAll(drafts);
    notifyListeners();
  }

  // Get specific property types based on main property type
  List<String> getSpecificPropertyTypes(PropertyType? type) {
    switch (type) {
      case PropertyType.residential:
        return [
          'Apartment',
          'Villa',
          'Studio',
          'Townhouse',
          'Penthouse',
          'Compound',
          'Duplex',
          'Full Floor',
          'Half Floor',
          'Whole Building',
          'Land',
          'Bulk Rent Unit',
          'Bungalow',
          'Hotel & Hotel Apartment'
        ];
      case PropertyType.commercial:
        return [
          'Office Space',
          'Retail',
          'Warehouse',
          'Shop',
          'Villa',
          'Show Room',
          'Full Floor',
          'Half Floor',
          'Whole Building',
          'Land',
          'Bulk Rent Unit',
          'Bulk Sale Unit',
          'Hotel & Hotel Apartment',
          'Factory',
          'Labor Camp',
          'Staff Accommodation',
          'Business Centre',
          'Farm'
        ];
      case PropertyType.furnished:
        return ['Villa', 'Apartment', 'Studio', 'Offices'];
      case null:
        return [];
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Convert PropertyType enum to string
  String? _propertyTypeToString(PropertyType? type) {
    switch (type) {
      case PropertyType.residential:
        return 'residential';
      case PropertyType.commercial:
        return 'commercial';
      case PropertyType.furnished:
        return 'furnished';
      case null:
        return null;
    }
  }

  // Method to check if form is valid for UI feedback
  bool get isFormValid => hasAnyContent && isPhoneValid;

  // Save method with error handling - UPDATED to handle both add and edit modes
  Future<void> save(BuildContext context) async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      // Validate required data if needed
      if (!_validateData()) {
        _error = 'Please fill in the required fields';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // The city chosen and the pin placed are two separate fields. An Offer
      // saved as one city with its pin clearly in another is listed under the
      // wrong city on the map, so it is not saved until the two agree. The pin
      // is only judged when it is clearly in another listed city (see
      // MapCityGeography): a remote pin, or one on a border, saves as it did.
      final pinCity = _cityOfConflictingPin();
      if (pinCity != null) {
        final loc = AppLocalizations.of(context);
        _error = loc
            .translate('offerCityPinMismatch')
            .replaceAll(
              '{city}',
              loc.translate(UaeAreaCatalog.cityKey(selectedCity)),
            )
            .replaceAll(
              '{pinCity}',
              loc.translate(UaeAreaCatalog.cityKey(pinCity)),
            );
        _isLoading = false;
        notifyListeners();
        _showToast(_error!, Colors.red);
        return;
      }

      // Convert PlatformFiles to Files for upload
      final mediaFilesToUpload = <File>[];
      for (final platformFile in _selectedFiles) {
        if (platformFile.path != null) {
          mediaFilesToUpload.add(File(platformFile.path!));
        }
      }

      // Re-checked at save time, not only at selection: media may have been
      // added in another session or on another device since this form opened.
      // The Media Worker enforces the same limit authoritatively.
      if (currentMediaCount > OfferMediaPolicy.maxItemsPerOffer) {
        _error =
            AppLocalizations.of(context).translate('offerMediaLimitReached');
        _isLoading = false;
        notifyListeners();
        _showToast(_error!, Colors.red);
        return;
      }

      if (_usesMediaQueue) {
        await _saveWithUploadQueue(context);
        return;
      }

      if (isEditMode && _editOfferId != null) {
        // Edit mode - update existing offer with proper media merging
        await _handleEditMode(context, mediaFilesToUpload);
      } else {
        // Add mode - create new offer
        await _handleAddMode(context, mediaFilesToUpload);
      }
    } catch (e) {
      // Only obtained when the context is still valid; an unmounted context
      // falls back to CoreEntityErrorMessage's existing English text.
      final translate =
          context.mounted ? AppLocalizations.of(context).translate : null;
      _error = CoreEntityErrorMessage.save(
        e,
        'offer',
        isUpdate: isEditMode,
        translate: translate,
      );
      if (context.mounted) {
        _showToast(_error!, Colors.red);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Handle edit mode with proper media merging
  Future<void> _handleEditMode(
      BuildContext context, List<File> mediaFilesToUpload) async {
    final baseOffer = _createOfferModel();

    // Compute the final merged media URLs
    final Set<String> finalMediaUrls = <String>{};

    // Add existing URLs that weren't removed
    final remainingUrls = _uploadedFileUrls
        .where((url) => !_removedMediaUrls.contains(url))
        .toSet();
    finalMediaUrls.addAll(remainingUrls);

    if (mediaFilesToUpload.isNotEmpty) {
      // Upload new media and update document with merged URLs
      // The fast upload service will handle setting the final state correctly
      final savedOfferId = await _offerService.saveOfferWithMediaFast(
        offer: baseOffer.copyWith(mediaUrls: finalMediaUrls.toList()),
        mediaFiles: mediaFilesToUpload,
        offerId: _editOfferId,
      );

      if (context.mounted) {
        await _handleSuccessfulEditSave(context, savedOfferId,
            hasNewMedia: true);
      }
    } else {
      // No new media, just update the document with current media state
      final updatedOffer = baseOffer.copyWith(
        id: _editOfferId,
        mediaUrls: finalMediaUrls.toList(),
        createdAt: _originalOffer?.createdAt,
        updatedAt: DateTime.now(),
      );

      await _offerService.updateOffer(_editOfferId!, updatedOffer);

      if (context.mounted) {
        await _handleSuccessfulEditSave(context, _editOfferId,
            hasNewMedia: false);
      }
    }
  }

  /// Saves the Offer and hands its new media to the upload queue (Supabase).
  ///
  /// The Offer is saved without waiting for any upload, and what happened to
  /// its media is reported as it went: new items are uploading, never
  /// "uploaded". An item that could not be queued or removed stays in the
  /// form, which stays open, and Save retries exactly that — every item keeps
  /// its id, so nothing is ever duplicated.
  Future<void> _saveWithUploadQueue(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final editOfferId = isEditMode ? _editOfferId : null;
    final editing = editOfferId != null;
    final String offerId;
    if (editOfferId != null) {
      offerId = editOfferId;
    } else {
      // Once created, a retried Save updates the same Offer: no second
      // quota check and no second count.
      if (_createdOfferId == null) {
        final canAdd = await CoreEntityQuotaBridge.canCreate(
          context: context,
          section: 'offers',
        );
        if (!canAdd) return;
      }
      offerId = _offerId ??= _offerService.generateNewOfferId();
    }

    final drafts = List<OfferMediaDraft>.of(_drafts);
    final removed = List<String>.of(_removedExistingIds);
    final cancelled = List<String>.of(_cancelledUploadIds);
    final result = await _offerService.saveOfferWithMedia(
      offer: _createOfferModel(),
      offerId: offerId,
      newMedia: drafts,
      removedMediaIds: removed,
      cancelledUploadIds: cancelled,
    );

    if (!editing && _createdOfferId == null) {
      _createdOfferId = offerId;
      await CoreEntityQuotaBridge.recordCreated(section: 'offers');
    }

    // What went through leaves the form's own lists (queued items now show
    // from the queue); what did not stays for the next Save.
    final notQueued = result.failedToQueueIds.toSet();
    _drafts.removeWhere((draft) => !notQueued.contains(draft.mediaObjectId));
    final notRemoved = result.failedRemovalIds.toSet();
    final removedNow = {
      for (final id in removed)
        if (!notRemoved.contains(id)) id,
    };
    _existingMedia = [
      for (final ref in _existingMedia)
        if (!removedNow.contains(ref.mediaObjectId)) ref,
    ];
    _removedExistingIds.removeAll(removedNow);
    _cancelledUploadIds.removeAll(cancelled);

    if (!context.mounted) return;
    if (!result.isComplete) {
      if (notQueued.isNotEmpty) {
        _showToast(loc.translate('offerMediaPrepareFailed'), Colors.red);
      }
      if (notRemoved.isNotEmpty) {
        _showToast(loc.translate('offerMediaRemoveFailed'), Colors.red);
      }
      return;
    }

    final uploading = result.queuedCount > 0;
    if (editing) {
      await _handleSuccessfulEditSave(
        context,
        offerId,
        hasNewMedia: uploading,
        message: uploading ? loc.translate('offerUpdatedMediaUploading') : null,
      );
    } else {
      _showToast(
        uploading
            ? loc.translate('offerSavedMediaUploading')
            : 'Offer saved successfully!',
        Colors.green,
      );
      context.go('/home');
    }
  }

  /// Handle successful edit save and navigation
  Future<void> _handleSuccessfulEditSave(
      BuildContext context, String savedOfferId,
      {required bool hasNewMedia, String? message}) async {
    _showToast(
        message ??
            'Offer updated successfully! ${hasNewMedia ? 'Syncing new media...' : ''}',
        Colors.green);

    // Fetch the updated offer and return it to the details screen
    try {
      final updatedOfferFromDb = await _offerService.getOffer(savedOfferId);
      if (updatedOfferFromDb != null && context.mounted) {
        context
            .pop(updatedOfferFromDb); // Return updated model to details screen
      } else if (context.mounted) {
        context.pop(); // Fallback to normal pop if can't fetch
      }
    } catch (e) {
      // Debug log suppressed: Error fetching updated offer: $e
      if (context.mounted) {
        context.pop(); // Fallback to normal pop if error
      }
    }
  }

  /// Handle add mode with QUOTA CHECK
  Future<void> _handleAddMode(
      BuildContext context, List<File> mediaFilesToUpload) async {
    final canAdd = await CoreEntityQuotaBridge.canCreate(
      context: context,
      section: 'offers',
    );
    if (!canAdd) return;

    final offer = _createOfferModel();

    // Generate offer ID if not already set
    _offerId ??= _offerService.generateNewOfferId();

    final savedOfferId = await _offerService.saveOfferWithMediaFast(
      offer: offer,
      mediaFiles: mediaFilesToUpload,
      offerId: _offerId,
    );

    if (savedOfferId.isNotEmpty) {
      await CoreEntityQuotaBridge.recordCreated(section: 'offers');

      if (context.mounted) {
        _showToast(
            'Offer saved successfully! ${mediaFilesToUpload.isNotEmpty ? 'Syncing media...' : ''}',
            Colors.green);
        context.go('/home');
      }
    }
  }

  /// Increment quota count after successful save

  /// The listed city the pin is clearly in when that is not the city chosen,
  /// or null (no city or no pin chosen, or nothing clearly wrong).
  String? _cityOfConflictingPin() {
    final lat = _pickUpLatitude;
    final lng = _pickUpLongitude;
    if (selectedCity.isEmpty || lat == null || lng == null) return null;
    return MapCityGeography.otherCityAt(selectedCity, lat, lng);
  }

// Update the validation method
  bool _validateData() {
    // Check if phone number is valid (if provided)
    if (_phone.isNotEmpty && !isPhoneValid) {
      throw Exception('Please enter a valid UAE phone number');
    }

    // Since all fields are optional according to your requirements,
    // we just check if there's any content
    return hasAnyContent;
  }

  // Cancel with confirmation if there's data
  void cancel(BuildContext context) {
    if (hasAnyContent) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Discard Changes?'),
            content:
                const Text('Are you sure you want to discard your changes?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep Editing'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/home');
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Discard'),
              ),
            ],
          );
        },
      );
    } else {
      context.go('/home');
    }
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }
}

/// What one selection added to the Offer media form.
@immutable
class OfferMediaPickOutcome {
  const OfferMediaPickOutcome({
    required this.added,
    required this.duplicates,
    required this.rejections,
    required this.trimmedByLimit,
  });

  /// Files that entered the form.
  final int added;

  /// Files skipped because the form already had them.
  final int duplicates;

  /// Distinct reasons files were refused, one message each.
  final List<OfferMediaRejection> rejections;

  /// Valid files dropped because the Offer reached its 10-item limit.
  final bool trimmedByLimit;
}
