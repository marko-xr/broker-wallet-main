import 'dart:async';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/views/Widgets/pickup_location_widget.dart';
import '../../common/localization/localization_delegate.dart';
import '../../common/enums/add_offices_mode.dart';
import '../../data/models/ScreensModel/offices_model.dart';
import '../../services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/common/routes/leave_form.dart';

class AddOfficesViewModel extends ChangeNotifier
    implements LocationCapableViewModel {
  final OfficeService _officeService = OfficeService();

  // Mode and editing state
  final AddOfficesMode mode;
  final String? officeId;
  bool _isEditMode = false;

  /// The record loaded for editing: its id, owner and creation date go back
  /// to the details screen with the edited fields.
  OfficeModel? _originalOffice;
  bool get isEditMode => _isEditMode;

  // Constructor
  AddOfficesViewModel({
    this.mode = AddOfficesMode.add,
    this.officeId,
    OfficeModel? officeData,
  }) {
    _isEditMode = mode == AddOfficesMode.edit;
    if (_isEditMode) {
      if (officeData != null) {
        // Use pre-loaded data for instant UI fill
        _prefillFormWithOffice(officeData);
      } else if (officeId != null) {
        // Fallback: load from network (with delayed spinner)
        _loadOfficeForEdit();
      }
    }
  }

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // A failure found while loading, as a localization key for the screen.
  String? _errorKey;
  String? get errorKey => _errorKey;

  // Form fields
  String officeName = '';
  String managerName = '';
  String countryCode = '+971';
  String _phone = '';
  String? _phoneError;
  String officeLocation = '';
  String notes = '';
  String _pickUpLocation = '';
  double? _pickUpLatitude;
  double? _pickUpLongitude;
  String _pickUpAddress = '';

  // Phone getters
  String get phone => _phone;
  String? get phoneError => _phoneError;

  // Location getters
  String get pickUpLocation => _pickUpLocation;
  double? get pickUpLatitude => _pickUpLatitude;
  double? get pickUpLongitude => _pickUpLongitude;
  String get pickUpAddress => _pickUpAddress;

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
      officeName.isNotEmpty ||
      managerName.isNotEmpty ||
      _phone.isNotEmpty ||
      officeLocation.isNotEmpty ||
      notes.isNotEmpty ||
      _pickUpLocation.isNotEmpty ||
      _pickUpAddress.isNotEmpty;

  // Method to check if form is valid for UI feedback
  bool get isFormValid => hasAnyContent && isPhoneValid;

  // Field Setters
  void setOfficeName(String v) {
    officeName = v;
    notifyListeners();
  }

  void setManagerName(String v) {
    managerName = v;
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

  void setOfficeLocation(String v) {
    officeLocation = v;
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

  void setPickUpLatitude(double? v) {
    _pickUpLatitude = v;
    notifyListeners();
  }

  void setPickUpLongitude(double? v) {
    _pickUpLongitude = v;
    notifyListeners();
  }

  void setPickUpAddress(String v) {
    _pickUpAddress = v;
    notifyListeners();
  }

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

  // Clear error
  void clearError() {
    _error = null;
    _errorKey = null;
    notifyListeners();
  }

  // Create office model from current state
  OfficeModel _createOfficeModel() {
    return OfficeModel(
      officeName: officeName,
      managerName: managerName,
      countryCode: countryCode,
      phoneNumber: _phone,
      officeLocation: officeLocation,
      notes: notes,
      pickUpLocation: _pickUpLocation,
      pickUpLatitude: _pickUpLatitude,
      pickUpLongitude: _pickUpLongitude,
      pickUpAddress: _pickUpAddress,
    );
  }

  // Save method with error handling
  Future<void> save(BuildContext context) async {
    _error = null;
    _errorKey = null;
    _isLoading = true;
    notifyListeners();

    try {
      if (!_validateData()) {
        throw Exception('Please fill in at least one field');
      }

      final office = _createOfficeModel();

      if (_isEditMode && officeId != null) {
        await _handleEditMode(office);
        // Back to the details screen it was opened from, with the record as
        // it now is (as the other sections do).
        if (context.mounted) {
          context.pop(office.copyWith(
            id: officeId,
            userId: _originalOffice?.userId,
            createdAt: _originalOffice?.createdAt,
            updatedAt: DateTime.now(),
          ));
        }
      } else {
        final saved = await _handleAddMode(context, office);
        // When adding was not allowed nothing was saved: stay on the form.
        if (saved && context.mounted) {
          leaveForm(GoRouter.of(context));
        }
      }
    } catch (e) {
      final translate =
          context.mounted ? AppLocalizations.of(context).translate : null;
      _error = CoreEntityErrorMessage.save(
        e,
        'office',
        isUpdate: isEditMode,
        translate: translate,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Handle add mode
  Future<bool> _handleAddMode(BuildContext context, OfficeModel office) async {
    final canAdd = await CoreEntityQuotaBridge.canCreate(
      context: context,
      section: 'offices',
    );
    if (!canAdd) return false;

    final newOfficeId = await _officeService.saveOffice(office);
    if (newOfficeId == null) {
      throw Exception('Failed to save office');
    }
    await CoreEntityQuotaBridge.recordCreated(section: 'offices');
    return true;
  }

  // Handle edit mode
  Future<void> _handleEditMode(OfficeModel office) async {
    await _officeService.updateOffice(officeId!, office);
  }

  // Basic validation
  bool _validateData() {
    // Check if phone number is valid (if provided)
    if (_phone.isNotEmpty && !isPhoneValid) {
      throw Exception('Please enter a valid UAE phone number');
    }

    return hasAnyContent;
  }

  // Load office data for editing with delayed spinner pattern
  Future<void> _loadOfficeForEdit() async {
    if (officeId == null) return;

    // Use delayed spinner pattern - only show loading if it takes > 500ms
    bool showSpinner = false;
    final delayTimer = Timer(const Duration(milliseconds: 500), () {
      showSpinner = true;
      _isLoading = true;
      notifyListeners();
    });

    try {
      final office = await _officeService.getOffice(officeId!);
      delayTimer.cancel(); // Cancel timer since we're done

      if (office != null) {
        _prefillFormWithOffice(office);
      }
    } catch (e) {
      delayTimer.cancel();
      _errorKey = 'recordLoadFailedOffice';
    } finally {
      if (showSpinner) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Prefill form with office data
  void _prefillFormWithOffice(OfficeModel office) {
    _originalOffice = office;
    officeName = office.officeName;
    managerName = office.managerName;
    countryCode = office.countryCode;
    _phone = _extractLocalPhoneNumber(office.phoneNumber);
    officeLocation = office.officeLocation;
    notes = office.notes;
    _pickUpLocation = office.pickUpLocation;
    _pickUpLatitude = office.pickUpLatitude;
    _pickUpLongitude = office.pickUpLongitude;
    _pickUpAddress = office.pickUpAddress;
    notifyListeners();
  }

  // Extract local phone number from international format
  String _extractLocalPhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return '';

    // Remove country code (+971) and return local format (05...)
    if (phoneNumber.startsWith('+971')) {
      String localNumber = phoneNumber.substring(4);
      if (localNumber.startsWith('5')) {
        return '0$localNumber';
      }
      return localNumber;
    }
    return phoneNumber;
  }

  // Cancel with confirmation if there's data
  void cancel(BuildContext context) {
    if (hasAnyContent) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          final loc = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(loc.translate('discardChanges')),
            content: Text(loc.translate('discardChangesCancelMessage')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(loc.translate('stay')),
              ),
              TextButton(
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  leaveForm(router);
                },
                child: Text(loc.translate('discard')),
              ),
            ],
          );
        },
      );
    } else {
      leaveForm(GoRouter.of(context));
    }
  }
}
