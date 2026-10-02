import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:broker_wallet/src/common/data/owner_location_codec.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/Views/Widgets/pickup_location_widget.dart';
import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import 'package:broker_wallet/src/viewmodels/private_media_form.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../../services/ScreenServices/owner_service.dart';

class AddOwnersViewModel extends ChangeNotifier
    implements LocationCapableViewModel {
  final OwnerService _ownerService;
  final CleanMediaService _cleanMediaService = CleanMediaService();

  // Edit mode properties
  final AddOwnersMode _mode;
  final String? _editOwnerId;
  OwnerModel? _originalOwner;

  // Constructor
  AddOwnersViewModel({
    AddOwnersMode mode = AddOwnersMode.add,
    String? ownerId,
    OwnerModel? ownerData,
    OwnerService? ownerService,
    bool? usesMediaQueue,
    OfferMediaPicker? mediaPicker,
    Future<OfferMediaSource?> Function(BuildContext context, int remaining)?
        chooseMediaSource,
    OwnerLocationCodec? locationCodec,
  })  : _mode = mode,
        _editOwnerId = ownerId,
        _ownerService = ownerService ?? OwnerService(),
        _locationCodec = locationCodec ?? OwnerLocationCodec(),
        _usesMediaQueue = usesMediaQueue ?? SupabaseConfig.useSupabaseAuth {
    if (_usesMediaQueue) {
      _media = PrivateMediaForm(
        store: _ownerService,
        onChanged: _onMediaChanged,
        picker: mediaPicker,
        chooseSource: chooseMediaSource,
      );
    }
    if (_mode == AddOwnersMode.edit) {
      if (ownerData != null) {
        // Use pre-loaded data for instant UI fill
        _originalOwner = ownerData;
        _prefillFormWithOwner(ownerData);
      } else if (_editOwnerId != null) {
        // Fallback: load from network (with delayed spinner)
        _loadOwnerForEdit();
      }
    }
    _media?.start(editRecordId: isEditMode ? _editOwnerId : null);
  }

  // ---------------------------------------------------------------------------
  // Owner private media (Supabase mode): the Offer media lifecycle for Owner
  // records — private R2 through the Media Worker's Owner routes, the shared
  // upload queue, local-first display — addressed by identity, never by URL.
  // The legacy Firebase mode keeps its own picker and upload below.
  // ---------------------------------------------------------------------------

  final bool _usesMediaQueue;
  PrivateMediaForm? _media;
  String? _createdOwnerId;
  bool _disposed = false;

  void _onMediaChanged() {
    if (!_disposed) notifyListeners();
  }

  /// Whether the Owner media form uses [ownerMediaItems].
  bool get usesOwnerMediaItems => _usesMediaQueue;

  /// Owner media as the form shows it (Supabase mode); empty otherwise.
  List<OfferMediaRef> get ownerMediaItems =>
      _media?.items ?? const <OfferMediaRef>[];

  /// How many items the media grid shows: the first three, or all of them
  /// once "+N more" was tapped.
  int get mediaDisplayCount => _media?.displayCount ?? 3;

  void showAllMedia() => _media?.showAll();

  /// Removes the item at [index] of [ownerMediaItems]: a picked file at once;
  /// a server item or a queued upload when the Owner is saved.
  void removeOwnerMediaAt(int index) => _media?.removeAt(index);

  /// Retries the queued upload at [index] of [ownerMediaItems].
  void retryOwnerMediaAt(int index) => _media?.retryAt(index);

  @visibleForTesting
  PrivateMediaForm? get mediaForm => _media;

  @override
  void dispose() {
    _disposed = true;
    _media?.dispose();
    super.dispose();
  }

  // Getters for mode
  bool get isEditMode => _mode == AddOwnersMode.edit;
  String? get editOwnerId => _editOwnerId;

  // Load owner data for editing with delayed spinner pattern
  Future<void> _loadOwnerForEdit() async {
    if (_editOwnerId == null) return;

    // Use delayed spinner pattern - only show loading if it takes > 500ms
    bool showSpinner = false;
    final delayTimer = Timer(const Duration(milliseconds: 500), () {
      showSpinner = true;
      _isLoading = true;
      notifyListeners();
    });

    try {
      final owner = await _ownerService.getOwner(_editOwnerId);
      delayTimer.cancel(); // Cancel timer since we're done

      if (owner != null) {
        _originalOwner = owner;
        _prefillFormWithOwner(owner);
      }
    } catch (e) {
      delayTimer.cancel();
      _error = 'Unable to load the owner. Please try again.';
    } finally {
      if (showSpinner) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Prefill form with owner data for editing
  void _prefillFormWithOwner(OwnerModel owner) {
    name = owner.name;
    _phone = _extractLocalPhoneNumber(owner.phoneNumber);
    countryCode = owner.countryCode;
    typeOfProperties = owner.typeOfProperties;
    propertyLocation = owner.propertyLocation;
    _restoreLocationChips();
    notes = owner.notes;
    _pickUpLocation = owner.pickUpLocation;
    _pickUpLatitude = owner.pickUpLatitude;
    _pickUpLongitude = owner.pickUpLongitude;
    _pickUpAddress = owner.pickUpAddress;
    _uploadedFileUrls = List<String>.from(owner.mediaUrls);
    _ownerId = owner.id;
    notifyListeners();
  }

  // Extract local phone number format (remove country code)
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

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Document ID for proper storage structure
  String? _ownerId;

  // Fields
  String name = '';
  String countryCode = '+971';
  String _phone = '';
  String? _phoneError;
  String typeOfProperties = '';
  String propertyLocation = '';
  String notes = '';
  String _pickUpLocation = '';
  double? _pickUpLatitude;
  double? _pickUpLongitude;
  String _pickUpAddress = '';

  // Media files
  List<PlatformFile> _selectedFiles = [];
  List<String> _uploadedFileUrls = [];
  List<String> _removedMediaUrls = []; // Track removed existing media
  bool _isUploading = false;

  // Media getters
  List<PlatformFile> get selectedFiles => _selectedFiles;
  List<String> get uploadedFileUrls => _uploadedFileUrls;
  bool get isUploading => _isUploading;
  bool get hasMediaFiles => _usesMediaQueue
      ? ownerMediaItems.isNotEmpty
      : _selectedFiles.isNotEmpty || _uploadedFileUrls.isNotEmpty;

  // Phone getters
  String get phone => _phone;
  String? get phoneError => _phoneError;

  // Location getters
  String get pickUpLocation => _pickUpLocation;
  double? get pickUpLatitude => _pickUpLatitude;
  double? get pickUpLongitude => _pickUpLongitude;
  String get pickUpAddress => _pickUpAddress;
  bool get hasSelectedLocation =>
      _pickUpLatitude != null && _pickUpLongitude != null;
  @override
  bool get isLocationLoading => false; // Add this for the interface

  // Get formatted phone for display (utility method)
  String get formattedPhone =>
      _phone.isNotEmpty ? PhoneInputService.formatPhoneNumber(_phone) : '';

  // Get international phone format (utility method)
  String get internationalPhone =>
      _phone.isNotEmpty ? PhoneInputService.toInternationalFormat(_phone) : '';

  // Check if phone is valid (if provided)
  bool get isPhoneValid => _phone.isEmpty || _phoneError == null;

  // Check if any field has content
  bool get hasAnyContent =>
      name.isNotEmpty ||
      _phone.isNotEmpty ||
      typeOfProperties.isNotEmpty ||
      propertyLocation.isNotEmpty ||
      notes.isNotEmpty ||
      _pickUpLocation.isNotEmpty ||
      hasMediaFiles;

  // Method to check if form is valid for UI feedback
  bool get isFormValid => hasAnyContent && isPhoneValid;

  // Field Setters
  void setName(String v) {
    name = v;
    notifyListeners();
  }

  void setPhone(String v) {
    _phone = v;
    _validatePhone(v);
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

  void setTypeOfProperties(String v) {
    typeOfProperties = v;
    notifyListeners();
  }

  void setPropertyLocation(String v) {
    propertyLocation = v;
    _dropStaleLocationChips();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Property location chips. An Owner has ONE location, stored as the plain text
  // in [propertyLocation]. A city and area chosen from the shared UAE catalog
  // are written into that text ("Dubai Marina, Dubai") and read back from it, so
  // no second value is stored and a location an owner typed long ago is left
  // exactly as it is. The chips only show what the text currently says: typing
  // never creates a choice, and it clears one once the text stops saying it.
  // ---------------------------------------------------------------------------

  final OwnerLocationCodec _locationCodec;
  String _locationCity = '';
  String _locationAreaKey = '';

  /// The cities the location chips offer: the shared UAE catalog's.
  List<String> get locationCities => UaeAreaCatalog.supportedCities;

  /// The chosen city's name; empty when no city is chosen.
  String get locationCity => _locationCity;

  /// The chosen area, as the shared area chips take it: none, or one — an Owner
  /// has a single location, however many areas a Request or Offer may hold.
  List<String> get locationAreaKeys =>
      _locationAreaKey.isEmpty ? const <String>[] : <String>[_locationAreaKey];

  /// Chooses [city] and writes it into the location text in [language] (the
  /// app's current language). An empty [city] clears the choice and keeps
  /// whatever the owner wrote after it. The area is always cleared: an area
  /// never outlives its city.
  void selectLocationCity(String city, String language) {
    if (city.isNotEmpty && !UaeAreaCatalog.supportedCities.contains(city)) {
      return;
    }
    // Nothing is chosen, so there is nothing to clear: the text is the
    // owner's own and is left alone.
    if (city.isEmpty && _locationCity.isEmpty) return;
    final detail = _locationDetail();
    _locationCity = city;
    _locationAreaKey = '';
    propertyLocation = city.isEmpty
        ? detail
        : _locationCodec.encode(city: city, language: language, detail: detail);
    notifyListeners();
  }

  /// Chooses [areaKey] within the chosen city, replacing any earlier area, or
  /// clears it when it is already chosen. The text is rewritten in [language];
  /// whatever the owner wrote after the choice stays.
  void toggleLocationArea(String areaKey, String language) {
    if (_locationCity.isEmpty ||
        !UaeAreaCatalog.isAreaOf(_locationCity, areaKey)) {
      return;
    }
    final detail = _locationDetail();
    _locationAreaKey = _locationAreaKey == areaKey ? '' : areaKey;
    propertyLocation = _locationCodec.encode(
      city: _locationCity,
      areaKey: _locationAreaKey,
      language: language,
      detail: detail,
    );
    notifyListeners();
  }

  /// What the owner wrote after the chosen city and area; empty when nothing is
  /// chosen or nothing follows.
  String _locationDetail() {
    if (_locationCity.isEmpty) return '';
    return _locationCodec.detailOf(
          propertyLocation,
          city: _locationCity,
          areaKey: _locationAreaKey,
        ) ??
        '';
  }

  /// Shows the city and area a saved location starts with, if it starts with
  /// any; any other text is the owner's own and shows no choice.
  void _restoreLocationChips() {
    final parts = _locationCodec.decode(propertyLocation);
    _locationCity = parts?.city ?? '';
    _locationAreaKey = parts?.areaKey ?? '';
  }

  /// Drops the chosen city and area once the text no longer starts with them.
  void _dropStaleLocationChips() {
    if (_locationCity.isEmpty) return;
    final stillSaid = _locationCodec.detailOf(
          propertyLocation,
          city: _locationCity,
          areaKey: _locationAreaKey,
        ) !=
        null;
    if (!stillSaid) {
      _locationCity = '';
      _locationAreaKey = '';
    }
  }

  void setNotes(String v) {
    notes = v;
    notifyListeners();
  }

  void setPickUpLocation(String v) {
    _pickUpLocation = v;
    notifyListeners();
  }

  // Location-related methods for map picker
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
        Placemark place = placemarks[0];
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

  String _formatAddress(Placemark place) {
    List<String> addressParts = [];

    if (place.street?.isNotEmpty == true) addressParts.add(place.street!);
    if (place.subLocality?.isNotEmpty == true)
      addressParts.add(place.subLocality!);
    if (place.locality?.isNotEmpty == true) addressParts.add(place.locality!);
    if (place.administrativeArea?.isNotEmpty == true)
      addressParts.add(place.administrativeArea!);
    if (place.country?.isNotEmpty == true) addressParts.add(place.country!);

    return addressParts.join(', ');
  }

  LatLng? get selectedLocation {
    if (_pickUpLatitude != null && _pickUpLongitude != null) {
      return LatLng(_pickUpLatitude!, _pickUpLongitude!);
    }
    return null;
  }

  // Media selection using clean permission system
  Future<void> selectMedia(BuildContext context) async {
    final media = _media;
    if (media != null) {
      // Supabase mode: the Offer media sheet and pickers (system camera,
      // one combined Gallery selection, no app-made permission dialog).
      await media.select(context);
      return;
    }
    // Debug log suppressed: selectMedia called - starting media selection with clean permissions
    try {
      // Show comprehensive media selection dialog
      final selectedFiles =
          await _cleanMediaService.showMediaSelectionDialog(context);

      if (selectedFiles != null && selectedFiles.isNotEmpty) {
        // Debug log suppressed: Adding ${selectedFiles.length} files to selection

        // Add all selected files
        _selectedFiles.addAll(selectedFiles);

        notifyListeners();

        // Show success message
        if (context.mounted) {
          Fluttertoast.showToast(
            msg: "Added ${selectedFiles.length} file(s) successfully",
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
          );
        }

        // Debug log suppressed: Files added successfully, total: ${_selectedFiles.length}
      } else {
        // Debug log suppressed: No files were selected
      }
    } catch (e) {
      // Debug log suppressed: Error in selectMedia: $e

      if (context.mounted) {
        Fluttertoast.showToast(
          msg: 'Unable to select media. Please try again.',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
        );
      }
    }
  }

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
    final media = _media;
    if (media != null) {
      media.clearAll();
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

  // Create owner model from current state
  OwnerModel _createOwnerModel() {
    // Filter out removed URLs for edit mode
    final finalMediaUrls = _uploadedFileUrls
        .where((url) => !_removedMediaUrls.contains(url))
        .toList();

    return OwnerModel(
      userId: '', // Will be set by the service
      name: name,
      phoneNumber: _phone,
      countryCode: countryCode,
      typeOfProperties: typeOfProperties,
      propertyLocation: propertyLocation,
      notes: notes,
      pickUpLocation: _pickUpLocation,
      pickUpLatitude: _pickUpLatitude,
      pickUpLongitude: _pickUpLongitude,
      pickUpAddress: _pickUpAddress,
      uploadedFileName: _selectedFiles.map((f) => f.name).join(', '),
      mediaUrl: finalMediaUrls.isNotEmpty ? finalMediaUrls.first : null,
      mediaUrls: finalMediaUrls,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Save method with fast upload - OPTIMIZED for fast save
  // Save method with mode-specific handling
  Future<void> save(BuildContext context) async {
    // Debug log suppressed: SAVE PROCESS STARTED (${isEditMode ? 'EDIT' : 'ADD'})
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      if (!_validateData()) {
        _error = 'Please fill in the required fields';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final media = _media;
      if (media != null) {
        // Re-checked at save time, not only at selection: media may have
        // been added on another device since this form opened. The Media
        // Worker enforces the same limit authoritatively.
        if (media.isOverLimit) {
          _error = AppLocalizations.of(context)
              .translate(media.parent.limitReachedKey);
          _showToast(_error!, Colors.red);
          return;
        }
        await _saveWithUploadQueue(context, media);
        return;
      }

      if (isEditMode) {
        await _handleEditMode(context);
      } else {
        await _handleAddMode(context);
      }
    } catch (e) {
      _error = CoreEntityErrorMessage.save(
        e,
        'owner',
        isUpdate: isEditMode,
      );
      // Debug log suppressed: SAVE ERROR
      // Debug log suppressed: Error: $_error
      if (context.mounted) {
        _showToast(_error!, Colors.red);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      // Debug log suppressed: SAVE PROCESS COMPLETED
    }
  }

  /// Saves the Owner and hands its new media to the upload queue (Supabase).
  ///
  /// The Owner is saved without waiting for any upload, and what happened to
  /// its media is reported as it went: new items are uploading, never
  /// "uploaded". An item that could not be queued or removed stays in the
  /// form, which stays open, and Save retries exactly that — every item keeps
  /// its id, so nothing is ever duplicated.
  Future<void> _saveWithUploadQueue(
    BuildContext context,
    PrivateMediaForm media,
  ) async {
    final loc = AppLocalizations.of(context);
    final editOwnerId = isEditMode ? _editOwnerId : null;
    final editing = editOwnerId != null;
    final String recordId;
    if (editOwnerId != null) {
      recordId = editOwnerId;
    } else {
      // Once created, a retried Save updates the same Owner: no second quota
      // check and no second count.
      if (_createdOwnerId == null) {
        final canAdd = await CoreEntityQuotaBridge.canCreate(
          context: context,
          section: 'owners',
        );
        if (!canAdd) return;
      }
      recordId = _ownerId ??= _ownerService.generateNewOwnerId();
    }
    media.recordId = recordId;

    final removed = media.removedIds;
    final cancelled = media.cancelledIds;
    final owner = _createOwnerModel();
    final result = await _ownerService.saveOwnerWithMedia(
      owner: owner,
      ownerRecordId: recordId,
      newMedia: media.drafts,
      removedMediaIds: removed,
      cancelledUploadIds: cancelled,
    );

    if (!editing && _createdOwnerId == null) {
      _createdOwnerId = recordId;
      await CoreEntityQuotaBridge.recordCreated(section: 'owners');
    }

    media.applySaveResult(
      removed: removed,
      cancelled: cancelled,
      failedRemovalIds: result.failedRemovalIds,
      failedToQueueIds: result.failedToQueueIds,
    );

    if (!context.mounted) return;
    if (!result.isComplete) {
      if (result.failedToQueueIds.isNotEmpty) {
        _showToast(loc.translate(media.parent.prepareFailedKey), Colors.red);
      }
      if (result.failedRemovalIds.isNotEmpty) {
        _showToast(loc.translate(media.parent.removeFailedKey), Colors.red);
      }
      return;
    }

    final uploading = result.queuedCount > 0;
    if (editing) {
      _showToast(
        uploading
            ? loc.translate(media.parent.updatedUploadingKey)
            : 'Owner updated successfully!',
        Colors.green,
      );
      // The saved row, read back, goes to Owner Details — with its id, so
      // Details can load the Owner's media again.
      OwnerModel returned = owner.copyWith(
        id: recordId,
        createdAt: _originalOwner?.createdAt,
      );
      try {
        returned = await _ownerService.getOwner(recordId) ?? returned;
      } catch (_) {
        // The locally built model, with its id, is still correct to show.
      }
      if (context.mounted) context.pop(returned);
    } else {
      _showToast(
        uploading
            ? loc.translate(media.parent.savedUploadingKey)
            : 'Owner saved successfully!',
        Colors.green,
      );
      context.go('/home');
    }
  }

  /// Handle edit mode - update existing owner
  Future<void> _handleEditMode(BuildContext context) async {
    if (_editOwnerId == null || _originalOwner == null) {
      throw Exception('Edit mode requires valid owner ID and original data');
    }

    final updatedOwner = _createOwnerModel();
    await _ownerService.updateOwner(_editOwnerId, updatedOwner);

    if (context.mounted) {
      await _handleSuccessfulEditSave(context, updatedOwner);
    }
  }

  /// Handle successful edit save and navigation
  Future<void> _handleSuccessfulEditSave(
      BuildContext context, OwnerModel updatedOwner) async {
    _showToast('Owner updated successfully!', Colors.green);

    // Return updated model to details screen
    if (context.mounted) {
      context.pop(updatedOwner);
    }
  }

  /// Handle add mode
  Future<void> _handleAddMode(BuildContext context) async {
    final canAdd = await CoreEntityQuotaBridge.canCreate(
      context: context,
      section: 'owners',
    );
    if (!canAdd) return;

    // Generate owner ID if not already exists
    _ownerId ??= _ownerService.generateNewOwnerId();
    // Debug log suppressed: Using Owner ID: $_ownerId

    final owner = _createOwnerModel();

    // Convert PlatformFiles to Files for upload
    final mediaFilesToUpload = <File>[];
    for (final platformFile in _selectedFiles) {
      if (platformFile.path != null) {
        mediaFilesToUpload.add(File(platformFile.path!));
      }
    }

    // Use fast save method - saves immediately and uploads in background
    final savedOwnerId = await _ownerService.saveOwnerWithMediaFast(
      owner: owner,
      mediaFiles: mediaFilesToUpload,
      ownerId: _ownerId,
    );

    if (savedOwnerId.isNotEmpty) {
      await CoreEntityQuotaBridge.recordCreated(section: 'owners');

      if (context.mounted) {
        // Show success message
        _showToast(
            'Owner saved successfully! ${mediaFilesToUpload.isNotEmpty ? 'Syncing media...' : ''}',
            Colors.green);

        // Navigate back immediately - no waiting for uploads
        // Debug log suppressed: Navigation to home...
        context.go('/home');
      }
    }
  }

  // Basic validation
  bool _validateData() {
    if (_phone.isNotEmpty && !isPhoneValid) {
      throw Exception('Please enter a valid UAE phone number');
    }
    return hasAnyContent;
  }

  // Cancel with confirmation if there's data
  void cancel(BuildContext context) {
    if (hasAnyContent) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Discard Changes?'),
            content: Text('Are you sure you want to discard your changes?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Keep Editing'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/home');
                },
                child: Text('Discard'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
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
