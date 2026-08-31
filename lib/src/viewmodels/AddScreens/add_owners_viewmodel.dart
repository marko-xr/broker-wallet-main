import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import 'package:broker_wallet/src/Views/Widgets/pickup_location_widget.dart';
import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../../services/ScreenServices/owner_service.dart';

class AddOwnersViewModel extends ChangeNotifier
    implements LocationCapableViewModel {
  final OwnerService _ownerService = OwnerService();
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
  })  : _mode = mode,
        _editOwnerId = ownerId {
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
  bool get hasMediaFiles =>
      _selectedFiles.isNotEmpty || _uploadedFileUrls.isNotEmpty;

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
    notifyListeners();
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
