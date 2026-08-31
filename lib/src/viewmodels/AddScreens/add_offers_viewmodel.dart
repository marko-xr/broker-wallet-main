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
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import '../../common/localization/localization_delegate.dart';
import '../../data/models/ScreensModel/offers_model.dart';
import '../../services/ScreenServices/offer_service.dart';

enum OffersTab { rent, sell }

enum PropertyType { residential, commercial, furnished }

class AddOffersViewModel extends ChangeNotifier
    implements LocationCapableViewModel {
  final OfferService _offerService = OfferService();
  final CleanMediaService _cleanMediaService = CleanMediaService();

  // Edit mode properties
  final AddOffersMode _mode;
  final String? _editOfferId;
  OfferModel? _originalOffer;

  // Constructor
  AddOffersViewModel({
    AddOffersMode mode = AddOffersMode.add,
    String? offerId,
    OfferModel? offerData,
  })  : _mode = mode,
        _editOfferId = offerId {
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

    // Media URLs (existing uploaded files)
    _uploadedFileUrls = List.from(offer.mediaUrls);

    notifyListeners();
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
  bool get hasMediaFiles =>
      _selectedFiles.isNotEmpty || _uploadedFileUrls.isNotEmpty;

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

  // Media selection using clean permission system
  Future<void> selectMedia(BuildContext context) async {
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
      uploadedFileName: _selectedFiles
          .map((f) => f.name)
          .join(', '), // Keep for compatibility
      mediaUrls: mergedMediaUrls,
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

      // Convert PlatformFiles to Files for upload
      final mediaFilesToUpload = <File>[];
      for (final platformFile in _selectedFiles) {
        if (platformFile.path != null) {
          mediaFilesToUpload.add(File(platformFile.path!));
        }
      }

      if (isEditMode && _editOfferId != null) {
        // Edit mode - update existing offer with proper media merging
        await _handleEditMode(context, mediaFilesToUpload);
      } else {
        // Add mode - create new offer
        await _handleAddMode(context, mediaFilesToUpload);
      }
    } catch (e) {
      _error = CoreEntityErrorMessage.save(
        e,
        'offer',
        isUpdate: isEditMode,
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

  /// Handle successful edit save and navigation
  Future<void> _handleSuccessfulEditSave(
      BuildContext context, String savedOfferId,
      {required bool hasNewMedia}) async {
    _showToast(
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
