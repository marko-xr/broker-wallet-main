import 'dart:async';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import '../../common/localization/localization_delegate.dart';
import '../../common/enums/add_watchmen_mode.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

import '../../data/models/ScreensModel/watchmen_model.dart';
import '../../services/ScreenServices/watchmen_service.dart';
import '../../Views/Widgets/pickup_location_widget.dart';

class AddWatchmenViewModel extends ChangeNotifier
    implements LocationCapableViewModel {
  final WatchmenService _watchmenService = WatchmenService();

  // Mode and ID for edit functionality
  final AddWatchmenMode mode;
  final String? watchmenId;

  // Constructor
  AddWatchmenViewModel({
    this.mode = AddWatchmenMode.add,
    this.watchmenId,
    WatchmenModel? watchmenData,
  }) {
    if (mode == AddWatchmenMode.edit) {
      if (watchmenData != null) {
        // Use pre-loaded data for instant UI fill
        _prefillFormWithWatchmen(watchmenData);
      } else if (watchmenId != null) {
        // Fallback: load from network (with delayed spinner)
        _loadWatchmenForEdit();
      }
    }
  }

  // ========================= Edit Mode Functionality =========================

  // Load watchmen data for editing with delayed spinner pattern
  Future<void> _loadWatchmenForEdit() async {
    if (watchmenId == null) return;

    // Use delayed spinner pattern - only show loading if it takes > 500ms
    bool showSpinner = false;
    final delayTimer = Timer(const Duration(milliseconds: 500), () {
      showSpinner = true;
      _isLoading = true;
      notifyListeners();
    });

    try {
      final watchmen = await _watchmenService.getWatchmen(watchmenId!);
      delayTimer.cancel(); // Cancel timer since we're done

      if (watchmen != null) {
        _prefillFormWithWatchmen(watchmen);
      } else {
        _error = 'Watchmen not found';
      }
    } catch (e) {
      delayTimer.cancel();
      _error = 'Unable to load the watchman. Please try again.';
    } finally {
      if (showSpinner) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Prefill form with watchmen data
  void _prefillFormWithWatchmen(WatchmenModel watchmen) {
    name = watchmen.name;
    buildingName = watchmen.buildingName;
    notes = watchmen.notes;
    buildingLocation = watchmen.buildingLocation;
    countryCode = watchmen.countryCode;

    // Handle phone number formatting for display
    if (watchmen.phoneNumber.isNotEmpty) {
      _phone = _extractLocalPhoneNumber(watchmen.phoneNumber);
    }

    // Handle location data
    _pickUpLocation = watchmen.pickUpLocation;
    _pickUpLatitude = watchmen.pickUpLatitude;
    _pickUpLongitude = watchmen.pickUpLongitude;
    _pickUpAddress = watchmen.pickUpAddress;

    // Set selected location if coordinates are available
    if (_pickUpLatitude != null && _pickUpLongitude != null) {
      _selectedLocation = LatLng(_pickUpLatitude!, _pickUpLongitude!);
    }

    notifyListeners();
  }

  // Extract local phone number from international format
  String _extractLocalPhoneNumber(String internationalPhone) {
    if (internationalPhone.isEmpty) return '';

    // Remove all non-digit characters
    final digitsOnly = internationalPhone.replaceAll(RegExp(r'[^\d]'), '');

    // Check if it starts with UAE country code (971) and has correct length
    if (digitsOnly.startsWith('971') && digitsOnly.length == 12) {
      // Extract the local part (remove 971, add 0)
      final localPart = digitsOnly.substring(3); // Remove '971'
      return '0$localPart'; // Add '0' prefix for local format
    }

    // If it's already in local format or different format, return as is
    return internationalPhone;
  }

  // ========================= State Management =========================

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // ========================= Location Management =========================

  LatLng? _selectedLocation;
  bool _isLocationLoading = false;

  // LocationCapableViewModel interface implementation
  @override
  LatLng? get selectedLocation => _selectedLocation;

  @override
  bool get hasSelectedLocation => _selectedLocation != null;

  @override
  bool get isLocationLoading => _isLocationLoading;

  @override
  Future<void> setSelectedLocation(
      LatLng location, BuildContext context) async {
    _selectedLocation = location;
    _pickUpLatitude = location.latitude;
    _pickUpLongitude = location.longitude;
    await _updateLocationString(location);
    notifyListeners();
  }

  // Helper method to update location strings from coordinates
  Future<void> _updateLocationString(LatLng location) async {
    try {
      _isLocationLoading = true;
      notifyListeners();

      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = _formatAddress(placemark);
        _pickUpAddress = address;
        _pickUpLocation = address;
        setBuildingLocation(address); // Also update the building location field
      } else {
        // Fallback to coordinates if no address found
        final coordString =
            '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        _pickUpAddress = coordString;
        _pickUpLocation = coordString;
        setBuildingLocation(coordString);
      }
    } catch (e) {
      // Fallback to coordinates
      final coordString =
          '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
      _pickUpAddress = coordString;
      _pickUpLocation = coordString;
      setBuildingLocation(coordString);
    } finally {
      _isLocationLoading = false;
      notifyListeners();
    }
  }

  // Format address from placemark
  String _formatAddress(Placemark placemark) {
    List<String> addressParts = [];

    if (placemark.street != null && placemark.street!.isNotEmpty) {
      addressParts.add(placemark.street!);
    }
    if (placemark.subLocality != null && placemark.subLocality!.isNotEmpty) {
      addressParts.add(placemark.subLocality!);
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      addressParts.add(placemark.locality!);
    }
    if (placemark.administrativeArea != null &&
        placemark.administrativeArea!.isNotEmpty) {
      addressParts.add(placemark.administrativeArea!);
    }

    return addressParts.join(', ');
  }

  // ========================= Form Fields =========================

  String name = '';
  String buildingName = '';
  String notes = '';
  String buildingLocation = '';
  String countryCode = '+971';

  // Location fields to match the model
  String _pickUpLocation = '';
  double? _pickUpLatitude;
  double? _pickUpLongitude;
  String _pickUpAddress = '';

  // ========================= Phone Backend Validation =========================

  // Phone - Made private with setter and validation
  String _phone = '';
  String? _phoneError;

  // Phone getters
  String get phone => _phone;
  String? get phoneError => _phoneError;

  // Phone setter with validation
  void setPhone(String v) {
    _phone = v;
    _validatePhone(v);
    notifyListeners();
  }

  // Phone validation
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

  // Check if phone is valid (if provided)
  bool get isPhoneValid => _phone.isEmpty || _phoneError == null;

  // Get formatted phone for display (utility method)
  String get formattedPhone =>
      _phone.isNotEmpty ? PhoneInputService.formatPhoneNumber(_phone) : '';

  // Get international phone format (utility method)
  String get internationalPhone =>
      _phone.isNotEmpty ? PhoneInputService.toInternationalFormat(_phone) : '';

  // ========================= Field Setters =========================

  void setName(String v) {
    name = v;
    notifyListeners();
  }

  void setBuildingName(String v) {
    buildingName = v;
    notifyListeners();
  }

  void setNotes(String v) {
    notes = v;
    notifyListeners();
  }

  void setBuildingLocation(String v) {
    buildingLocation = v;
    notifyListeners();
  }

  // ========================= Location Helper Methods =========================

  // For compatibility with PickUpInputWidget
  String get pickUpLocation => _pickUpLocation;

  void setPickUpLocation(String v) {
    _pickUpLocation = v;
    // Also update building location for backward compatibility
    setBuildingLocation(v);
    notifyListeners();
  }

  // Location getters for the model
  double? get pickUpLatitude => _pickUpLatitude;
  double? get pickUpLongitude => _pickUpLongitude;
  String get pickUpAddress =>
      _pickUpAddress; // ========================= Form Validation & State Checks =========================

  // Check if any field has content
  bool get hasAnyContent =>
      name.isNotEmpty ||
      _phone.isNotEmpty ||
      buildingName.isNotEmpty ||
      notes.isNotEmpty ||
      buildingLocation.isNotEmpty ||
      _pickUpLocation.isNotEmpty;

  // Method to check if form is valid for UI feedback
  bool get isFormValid => hasAnyContent && isPhoneValid;

  // Validate all data
  bool _validateData() {
    // Check if phone number is valid (if provided)
    if (_phone.isNotEmpty && _phoneError != null) {
      return false;
    }

    // Since all fields are optional according to your requirements,
    // we just check if there's any content
    return hasAnyContent;
  }

  // ========================= Data Operations =========================

  // Create watchmen model from current state
  WatchmenModel _createWatchmenModel() {
    return WatchmenModel(
      name: name,
      countryCode: countryCode,
      phoneNumber: _phone,
      buildingName: buildingName,
      notes: notes,
      buildingLocation: buildingLocation,
      pickUpLocation: _pickUpLocation,
      pickUpLatitude: _pickUpLatitude,
      pickUpLongitude: _pickUpLongitude,
      pickUpAddress: _pickUpAddress,
    );
  }

  // Save method with enhanced validation and error handling
  Future<void> save(BuildContext context) async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      if (!_validateData()) {
        throw Exception('Please fill in at least one field');
      }

      // Check phone validation specifically
      if (_phone.isNotEmpty && !isPhoneValid) {
        throw Exception('Please enter a valid UAE phone number');
      }

      final watchmen = _createWatchmenModel();

      if (mode == AddWatchmenMode.edit && watchmenId != null) {
        // Update existing watchmen
        await _handleEditMode(watchmen);
      } else {
        // Create new watchmen
        await _handleAddMode(context, watchmen);
      }

      // Success - navigate back
      if (context.mounted) {
        context.go('/home');
      }
    } catch (e) {
      _error = CoreEntityErrorMessage.save(
        e,
        'watchman',
        isUpdate: mode == AddWatchmenMode.edit,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Handle add mode
  Future<void> _handleAddMode(
      BuildContext context, WatchmenModel watchmen) async {
    final canAdd = await CoreEntityQuotaBridge.canCreate(
      context: context,
      section: 'watchmen',
    );
    if (!canAdd) return;

    final watchmenId = await _watchmenService.saveWatchmen(watchmen);
    if (watchmenId == null) {
      throw Exception('Failed to save watchmen information');
    }
    await CoreEntityQuotaBridge.recordCreated(section: 'watchmen');
  }

  // Handle edit mode
  Future<void> _handleEditMode(WatchmenModel watchmen) async {
    await _watchmenService.updateWatchmen(watchmenId!, watchmen);
  }

  // ========================= UI Actions =========================

  // Cancel with confirmation if there's data
  void cancel(BuildContext context) {
    if (hasAnyContent) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Discard Changes?'),
            content: const Text(
                'You have unsaved changes. Are you sure you want to cancel?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/home');
                },
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

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Clear all fields (utility method)
  void clearForm() {
    name = '';
    _phone = '';
    _phoneError = null;
    buildingName = '';
    notes = '';
    buildingLocation = '';
    _pickUpLocation = '';
    _pickUpLatitude = null;
    _pickUpLongitude = null;
    _pickUpAddress = '';
    _selectedLocation = null;
    _error = null;
    notifyListeners();
  }
}
