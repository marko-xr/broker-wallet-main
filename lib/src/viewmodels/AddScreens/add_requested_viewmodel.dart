import 'dart:async';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/common/enums/add_requested_mode.dart';
import '../../common/localization/localization_delegate.dart';

import '../../data/models/ScreensModel/request_model.dart';
import '../../services/ScreenServices/request_service.dart';

enum RequestTab { rent, sell }

enum PropertyType { residential, commercial, furnished }

class AddRequestedViewModel extends ChangeNotifier {
  final RequestService _requestService = RequestService();

  // Edit mode properties
  final AddRequestedMode _mode;
  final String? _editRequestId;
  RequestModel? _originalRequest;

  // Constructor
  AddRequestedViewModel({
    AddRequestedMode mode = AddRequestedMode.add,
    String? requestId,
    RequestModel? requestData,
  })  : _mode = mode,
        _editRequestId = requestId {
    if (_mode == AddRequestedMode.edit) {
      if (requestData != null) {
        // Use pre-loaded data for instant UI fill
        _originalRequest = requestData;
        _prefillFormWithRequest(requestData);
      } else if (_editRequestId != null) {
        // Fallback: load from network (with delayed spinner)
        _loadRequestForEdit();
      }
    }
  }

  // Getters for mode
  bool get isEditMode => _mode == AddRequestedMode.edit;
  String? get editRequestId => _editRequestId;

  // Load request data for editing with delayed spinner pattern
  Future<void> _loadRequestForEdit() async {
    if (_editRequestId == null) return;

    // Use delayed spinner pattern - only show loading if it takes > 500ms
    bool showSpinner = false;
    final delayTimer = Timer(const Duration(milliseconds: 500), () {
      showSpinner = true;
      _isLoading = true;
      notifyListeners();
    });

    try {
      final request = await _requestService.getRequest(_editRequestId);
      delayTimer.cancel(); // Cancel timer since we're done

      if (request != null) {
        _originalRequest = request;
        _prefillFormWithRequest(request);
      }
    } catch (e) {
      delayTimer.cancel();
      _error = 'Unable to load the request. Please try again.';
    } finally {
      if (showSpinner) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Prefill form with existing request data
  void _prefillFormWithRequest(RequestModel request) {
    tab = request.requestType == 'rent' ? RequestTab.rent : RequestTab.sell;
    selectedCity = request.selectedCity;
    selectedAreas = List<String>.from(request.selectedAreas);
    _location = request.location;

    // Handle phone number: convert from international format to local format
    _phone = _extractLocalPhoneNumber(request.phoneNumber);

    _minPrice = request.minPrice;
    _maxPrice = request.maxPrice;
    _squareFootage = request.squareFootage;
    _notes = request.notes;

    // Handle property type
    if (request.propertyType != null) {
      switch (request.propertyType) {
        case 'residential':
          propertyType = PropertyType.residential;
          break;
        case 'commercial':
          propertyType = PropertyType.commercial;
          break;
        case 'furnished':
          propertyType = PropertyType.furnished;
          break;
      }
    }

    selectedSpecificPropertyType = request.specificPropertyType;
    rooms = request.rooms;
    baths = request.bathrooms;

    notifyListeners();
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

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Tabs
  RequestTab tab = RequestTab.rent;
  void setTab(RequestTab t) {
    tab = t;
    notifyListeners();
  }

  // City Selection
  List<String> cities = [
    "Dubai",
    "Abu Dhabi",
    "Khor Fakkan",
    "Al Ain",
    "Ras Al Khaimah",
    "Fujairah",
    "Sharjah",
    "Ajman",
    "Umm Al Quwain",
  ];
  String selectedCity = "";
  List<String> selectedAreas = []; // Changed to List for multiple selection

  void selectCity(String city) {
    selectedCity = city;
    selectedAreas.clear(); // Clear selected areas when city changes
    notifyListeners();
  }

  void selectArea(String area) {
    if (selectedAreas.contains(area)) {
      // If area is already selected, remove it
      selectedAreas.remove(area);
    } else if (selectedAreas.length < 3) {
      // If less than 3 areas selected, add the new area
      selectedAreas.add(area);
    }
    // If 3 areas are already selected, do nothing
    notifyListeners();
  }

  // Location - Made private with setter
  String _location = '';
  String get location => _location;
  set location(String value) {
    _location = value;
    notifyListeners();
  }

  // Phone - Made private with setter and validation
  String countryCode = '+971';
  String _phone = '';
  String? _phoneError;

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

  // Phone setter with validation
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

  // Price - Made private with setters
  String _minPrice = '';
  String get minPrice => _minPrice;
  set minPrice(String value) {
    _minPrice = value;
    notifyListeners();
  }

  String _maxPrice = '';
  String get maxPrice => _maxPrice;
  set maxPrice(String value) {
    _maxPrice = value;
    notifyListeners();
  }

  String _squareFootage = '';
  String get squareFootage => _squareFootage;
  void setSquareFootage(String value) {
    _squareFootage = value;
    notifyListeners();
  }

  // Notes - Made private with setter
  String _notes = '';
  String get notes => _notes;
  set notes(String value) {
    _notes = value;
    notifyListeners();
  }

  // Property Type
  PropertyType? propertyType;
  void setPropertyType(PropertyType type) {
    propertyType = type;
    selectedSpecificPropertyType =
        ''; // Clear specific type when main type changes
    notifyListeners();
  }

  // Specific Property Type
  String selectedSpecificPropertyType = '';
  void selectSpecificPropertyType(String type) {
    selectedSpecificPropertyType = type;
    notifyListeners();
  }

  // Rooms and Bathrooms
  int rooms = 1;
  int baths = 1;

  void selectRooms(int count) {
    rooms = count;
    notifyListeners();
  }

  void selectBaths(int count) {
    baths = count;
    notifyListeners();
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
        propertyType != null ||
        selectedSpecificPropertyType.isNotEmpty;
  }

  // Method to check if form is valid for UI feedback
  bool get isFormValid => hasAnyContent && isPhoneValid;

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
          'Hotel & Hotel Apartment',
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
          'Farm',
        ];
      case PropertyType.furnished:
        return [
          'Villa',
          'Apartment',
          'Studio',
          'Offices',
        ];
      case null:
        return [];
    }
  }

  void clearForm() {
    _location = '';
    _phone = '';
    _phoneError = null;
    _minPrice = '';
    _maxPrice = '';
    _squareFootage = '';
    _notes = '';
    propertyType = null;
    selectedSpecificPropertyType = '';
    rooms = 1;
    baths = 1;
    _error = null;
    notifyListeners();
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

  // Update the request model creation to use international format
  RequestModel _createRequestModel() {
    return RequestModel(
      userId: '', // Will be set by the service
      requestType: tab == RequestTab.rent ? 'rent' : 'sell',
      selectedCity: selectedCity,
      selectedAreas: List<String>.from(selectedAreas),
      location: _location,
      phoneNumber: _phone,
      countryCode: countryCode,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      squareFootage: _squareFootage,
      notes: _notes,
      propertyType: _propertyTypeToString(propertyType),
      specificPropertyType: selectedSpecificPropertyType,
      rooms: rooms,
      bathrooms: baths,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

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

      if (isEditMode && _editRequestId != null) {
        // Edit mode - update existing request
        await _handleEditMode(context);
      } else {
        // Add mode - create new request
        await _handleAddMode(context);
      }
    } catch (e) {
      _error = CoreEntityErrorMessage.save(
        e,
        'request',
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

  /// Handle edit mode
  Future<void> _handleEditMode(BuildContext context) async {
    final updatedRequest = _createRequestModel().copyWith(
      id: _editRequestId,
      createdAt: _originalRequest?.createdAt,
      updatedAt: DateTime.now(),
    );

    await _requestService.updateRequest(_editRequestId!, updatedRequest);

    if (context.mounted) {
      await _handleSuccessfulEditSave(context, updatedRequest);
    }
  }

  /// Handle successful edit save and navigation
  Future<void> _handleSuccessfulEditSave(
      BuildContext context, RequestModel updatedRequest) async {
    _showToast('Request updated successfully!', Colors.green);

    // Return updated model to details screen
    if (context.mounted) {
      context.pop(updatedRequest);
    }
  }

  /// Handle add mode
  Future<void> _handleAddMode(BuildContext context) async {
    final canAdd = await CoreEntityQuotaBridge.canCreate(
      context: context,
      section: 'requests',
    );
    if (!canAdd) return;

    final request = _createRequestModel();
    final requestId = await _requestService.saveRequest(request);

    if (requestId != null) {
      await CoreEntityQuotaBridge.recordCreated(section: 'requests');

      if (context.mounted) {
        _showToast('Request saved successfully!', Colors.green);
        context.go('/home');
      }
    }
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
