import 'dart:async';
import 'package:flutter/material.dart';
import '../../common/utils/core_entity_error_message.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import '../../common/localization/localization_delegate.dart';
import '../../common/enums/add_brokers_mode.dart';

import '../../data/models/ScreensModel/brokers_model.dart';
import '../../services/ScreenServices/broker_service.dart';

class AddBrokersViewModel extends ChangeNotifier {
  final BrokerService _brokerService = BrokerService();

  // Mode and ID for edit functionality
  final AddBrokersMode mode;
  final String? brokerId;

  // Constructor
  AddBrokersViewModel({
    this.mode = AddBrokersMode.add,
    this.brokerId,
    BrokerModel? brokerData,
  }) {
    if (mode == AddBrokersMode.edit) {
      if (brokerData != null) {
        // Use pre-loaded data for instant UI fill
        _prefillFormWithBroker(brokerData);
      } else if (brokerId != null) {
        // Fallback: load from network (with delayed spinner)
        _loadBrokerForEdit();
      }
    }
  }

  // Load broker data for editing with delayed spinner pattern
  Future<void> _loadBrokerForEdit() async {
    if (brokerId == null) return;

    // Use delayed spinner pattern - only show loading if it takes > 500ms
    bool showSpinner = false;
    final delayTimer = Timer(const Duration(milliseconds: 500), () {
      showSpinner = true;
      _isLoading = true;
      notifyListeners();
    });

    try {
      final broker = await _brokerService.getBroker(brokerId!);
      delayTimer.cancel(); // Cancel timer since we're done

      if (broker != null) {
        _prefillFormWithBroker(broker);
      }
    } catch (e) {
      delayTimer.cancel();
      _error = 'Unable to load the broker. Please try again.';
    } finally {
      if (showSpinner) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Prefill form with broker data
  void _prefillFormWithBroker(BrokerModel broker) {
    name = broker.name;
    countryCode = broker.countryCode;

    // Extract local phone number from international format
    if (broker.phoneNumber.isNotEmpty) {
      _phone = _extractLocalPhoneNumber(broker.phoneNumber);
    }

    notes = broker.notes;
    notifyListeners();
  }

  // Extract local phone number (05...) from international format (971...)
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

  // Form fields
  String name = '';
  String countryCode = '+971';
  String _phone = '';
  String? _phoneError;
  String notes = '';

  // Phone getters
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

  // Check if any field has content
  bool get hasAnyContent =>
      name.isNotEmpty || _phone.isNotEmpty || notes.isNotEmpty;

  // Method to check if form is valid for UI feedback
  bool get isFormValid => hasAnyContent && isPhoneValid;

  // Field Setters
  void setName(String v) {
    name = v;
    notifyListeners();
  }

  // Phone setter with validation
  void setPhone(String v) {
    _phone = v;
    _validatePhone(v);
    notifyListeners();
  }

  void setNotes(String v) {
    notes = v;
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

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Create broker model from current state
  BrokerModel _createBrokerModel() {
    return BrokerModel(
      name: name,
      countryCode: countryCode,
      phoneNumber: _phone,
      notes: notes,
    );
  }

  // Updated validation method
  bool _validateData() {
    // Check if phone number is valid (if provided)
    if (_phone.isNotEmpty && !isPhoneValid) {
      throw Exception('Please enter a valid UAE phone number');
    }

    // Since all fields are optional, just check if there's any content
    return hasAnyContent;
  }

  // Save method with error handling
  Future<void> save(BuildContext context) async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      if (!_validateData()) {
        throw Exception('Please fill in at least one field');
      }

      if (mode == AddBrokersMode.edit) {
        await _handleEditMode(context);
      } else {
        await _handleAddMode(context);
      }
    } catch (e) {
      _error = CoreEntityErrorMessage.save(
        e,
        'broker',
        isUpdate: mode == AddBrokersMode.edit,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Handle add mode
  Future<void> _handleAddMode(BuildContext context) async {
    final canAdd = await CoreEntityQuotaBridge.canCreate(
      context: context,
      section: 'brokers',
    );
    if (!canAdd) return;

    final broker = _createBrokerModel();
    final savedBrokerId = await _brokerService.saveBroker(broker);

    if (savedBrokerId != null) {
      await CoreEntityQuotaBridge.recordCreated(section: 'brokers');

      // Success - navigate back
      if (context.mounted) {
        context.go('/home');
      }
    } else {
      throw Exception('Failed to save broker');
    }
  }

  // Handle edit mode
  Future<void> _handleEditMode(BuildContext context) async {
    if (brokerId == null) {
      throw Exception('Broker ID is required for editing');
    }

    final updatedBroker = BrokerModel(
      id: brokerId,
      name: name,
      countryCode: countryCode,
      phoneNumber: _phone,
      notes: notes,
    );

    await _brokerService.updateBroker(brokerId!, updatedBroker);

    // Success - pop with the updated broker
    if (context.mounted) {
      context.pop(updatedBroker);
    }
  }

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
}
