// lib/src/viewmodels/AddScreens/add_quotation_viewmodel.dart
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/pdf_generation_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';

/// Lightweight row model used only by the ViewModel/UI.
class DownpaymentRowVM {
  String method; // 'cash' | 'cheque' | 'bankTransfer' | 'other'
  String number; // "1", "2", ...
  String date; // "YYYY-MM-DD" (free form allowed)
  String amount; // "1500.00"

  DownpaymentRowVM({
    this.method = '', // No default, let user choose
    this.number = '',
    this.date = '',
    this.amount = '',
  });
}

/// Administrative fee row model used only by the ViewModel/UI.
class AdministrativeFeeRowVM {
  String title; // "Commission", "Office Payment", "Processing Fee", etc.
  String amount; // "500.00"

  AdministrativeFeeRowVM({
    this.title = '',
    this.amount = '',
  });
}

class AddQuotationViewModel extends ChangeNotifier {
  final QuotationService _quotationService = QuotationService();

  bool _disposed = false;

  // ===== Header / General =====
  String propertyTitle = '';
  String propertyType = '';
  bool parking = false;
  String date = '';
  String startDate = '';
  String endDate = '';
  String customNote = '';

  // ===== Welcome Message =====
  WelcomeMessageMode welcomeMessageMode = WelcomeMessageMode.auto;
  String customWelcomeMessage = '';

  // ===== Money & Terms =====
  String currencyCode = 'AED';
  String totalAmount = '';
  String numberOfInstallments = '';
  String paymentType = ''; // No default, let user choose
  String insuranceAmount = '';
  bool insuranceReturnable = false;

  // ===== Downpayments (dynamic table) =====
  final List<DownpaymentRowVM> downpayments = [];

  // ===== Government Fees =====
  String govPercentOfTotalRent = '';
  String govCalculatedAmount = ''; // Auto-calculated amount from percentage
  String govMunicipality = '';
  String govElectricity = '';
  String govSewerage = '';
  String govTotal = '';

  // ===== Administrative Fees (dynamic list) =====
  final List<AdministrativeFeeRowVM> administrativeFees = [];
  String admTotal = '';

  // Track manual override of totals
  bool _govTotalManual = false;
  bool _admTotalManual = false;

  // Track if user has manually modified downpayments
  bool _downpaymentsManuallyModified = false;

  // Track if end date was manually overridden
  bool _endDateManuallyOverridden = false;

  // ===== Office =====
  String officeName = '';
  String officeLogoFileName = '';
  String? _officeLogoUrl;
  File? _selectedLogoFile;

  // ===== Loading states =====
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  File? get selectedLogoFile => _selectedLogoFile;
  String? get officeLogoUrl => _officeLogoUrl;

  // Check if logo is selected (either file or URL available)
  bool get hasLogoSelected =>
      _selectedLogoFile != null || _officeLogoUrl != null;

  /// Check if smart calculation can be performed
  bool get canGenerateSmartDownpayments {
    final totalAmt = _toDoubleOrNull(totalAmount);
    final numInstallments = _toIntOrNull(numberOfInstallments);
    final startDateParsed = _toDateOrNull(startDate);
    final endDateParsed = _toDateOrNull(endDate);

    return totalAmt != null &&
        totalAmt > 0 &&
        numInstallments != null &&
        numInstallments > 0 &&
        startDateParsed != null &&
        endDateParsed != null &&
        !endDateParsed.isBefore(startDateParsed);
  }

  // ===== Derived =====
  bool get hasAnyContent =>
      propertyTitle.isNotEmpty ||
      propertyType.isNotEmpty ||
      parking ||
      date.isNotEmpty ||
      startDate.isNotEmpty ||
      endDate.isNotEmpty ||
      customNote.isNotEmpty ||
      currencyCode.isNotEmpty ||
      totalAmount.isNotEmpty ||
      numberOfInstallments.isNotEmpty ||
      paymentType.isNotEmpty ||
      insuranceAmount.isNotEmpty ||
      insuranceReturnable ||
      officeName.isNotEmpty ||
      officeLogoFileName.isNotEmpty ||
      govPercentOfTotalRent.isNotEmpty ||
      govCalculatedAmount.isNotEmpty ||
      govMunicipality.isNotEmpty ||
      govElectricity.isNotEmpty ||
      govSewerage.isNotEmpty ||
      govTotal.isNotEmpty ||
      administrativeFees.isNotEmpty ||
      admTotal.isNotEmpty ||
      downpayments.isNotEmpty;

  // ---------- Lifecycle ----------
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ---------- Setters ----------
  void setPropertyTitle(String v) {
    propertyTitle = v;
    notifyListeners();
  }

  void setPropertyType(String v) {
    propertyType = v;
    notifyListeners();
  }

  void setParking(bool v) {
    parking = v;
    notifyListeners();
  }

  void setDate(String v) {
    date = v;
    notifyListeners();
  }

  void setStartDate(String v) {
    startDate = v;

    // Auto-calculate end date (1 year contract minus 1 day) only if not manually overridden
    if (v.isNotEmpty && !_endDateManuallyOverridden) {
      try {
        final DateTime startDateTime = DateTime.parse(v);
        final DateTime endDateTime =
            startDateTime.add(const Duration(days: 365 - 1));
        endDate =
            '${endDateTime.year.toString().padLeft(4, '0')}-${endDateTime.month.toString().padLeft(2, '0')}-${endDateTime.day.toString().padLeft(2, '0')}';
      } catch (e) {}
    }

    _generateSmartDownpayments(); // Smart calculation
    notifyListeners();
  }

  void setEndDate(String v) {
    endDate = v;
    // Mark as manually overridden if user explicitly sets end date
    _endDateManuallyOverridden = true;
    _generateSmartDownpayments(); // Smart calculation
    notifyListeners();
  }

  void setCustomNote(String v) {
    customNote = v;
    notifyListeners();
  }

  void setWelcomeMessageMode(WelcomeMessageMode mode) {
    welcomeMessageMode = mode;
    notifyListeners();
  }

  void setCustomWelcomeMessage(String message) {
    customWelcomeMessage = message;

    notifyListeners();
  }

  void setCurrencyCode(String v) {
    currencyCode = v;
    notifyListeners();
  }

  void setTotalAmount(String v) {
    totalAmount = v;
    _recalcGovTotalIfAuto(); // affects % of rent
    _recalcGovCalculatedAmount(); // recalculate percentage amount
    _generateSmartDownpayments(); // Smart calculation
    notifyListeners();
  }

  void setNumberOfInstallments(String v) {
    numberOfInstallments = v;
    _generateSmartDownpayments(); // Smart calculation
    notifyListeners();
  }

  void setPaymentType(String v) {
    paymentType = v;
    _updateDownpaymentMethods(); // Update existing downpayment methods
    notifyListeners();
  }

  void setInsuranceAmount(String v) {
    insuranceAmount = v;
    notifyListeners();
  }

  void setInsuranceReturnable(bool v) {
    insuranceReturnable = v;
    notifyListeners();
  }

  // ---- Government setters (auto total) ----
  void setGovPercentOfTotalRent(String v) {
    govPercentOfTotalRent = v;
    _recalcGovCalculatedAmount(); // recalculate percentage amount
    _recalcGovTotalIfAuto();
    notifyListeners();
  }

  void setGovMunicipality(String v) {
    govMunicipality = v;
    _recalcGovTotalIfAuto();
    notifyListeners();
  }

  void setGovElectricity(String v) {
    govElectricity = v;
    _recalcGovTotalIfAuto();
    notifyListeners();
  }

  void setGovSewerage(String v) {
    govSewerage = v;
    _recalcGovTotalIfAuto();
    notifyListeners();
  }

  /// If user types here, treat as manual override.
  void setGovTotal(String v) {
    govTotal = v;
    _govTotalManual = v.trim().isNotEmpty;
    if (!_govTotalManual) _recalcGovTotalIfAuto();
    notifyListeners();
  }

  // ---- Administrative setters (auto total) ----
  void addAdministrativeFeeRow() {
    administrativeFees.add(AdministrativeFeeRowVM(
      title: '',
      amount: '',
    ));
    notifyListeners();
  }

  void removeAdministrativeFeeRow(int index) {
    if (index >= 0 && index < administrativeFees.length) {
      administrativeFees.removeAt(index);
      _recalcAdmTotalIfAuto();
      notifyListeners();
    }
  }

  void updateAdministrativeFeeTitle(int index, String title) {
    if (index < 0 || index >= administrativeFees.length) return;
    administrativeFees[index].title = title;
    notifyListeners();
  }

  void updateAdministrativeFeeAmount(int index, String amount) {
    if (index < 0 || index >= administrativeFees.length) return;
    administrativeFees[index].amount = amount;
    _recalcAdmTotalIfAuto();
    notifyListeners();
  }

  /// If user types here, treat as manual override.
  void setAdmTotal(String v) {
    admTotal = v;
    _admTotalManual = v.trim().isNotEmpty;
    if (!_admTotalManual) _recalcAdmTotalIfAuto();
    notifyListeners();
  }

  void setOfficeName(String v) {
    officeName = v;
    notifyListeners();
  }

  // ===== Downpayments row controls =====
  void addDownpaymentRow() {
    final year = DateTime.now().year.toString();
    final nextNo = downpayments.length + 1;
    downpayments.add(DownpaymentRowVM(
      method: 'cash',
      number: nextNo.toString(),
      date: '$year-', // help user: prefill current year
      amount: '',
    ));
    notifyListeners();
  }

  void removeDownpaymentRow(int index) {
    if (index >= 0 && index < downpayments.length) {
      downpayments.removeAt(index);
      _renumberDownpayments(); // keep sequence 1..n
      notifyListeners();
    }
  }

  void _renumberDownpayments() {
    for (var i = 0; i < downpayments.length; i++) {
      downpayments[i].number = '${i + 1}';
    }
  }

  void updateDownpaymentMethod(int index, String method) {
    if (index < 0 || index >= downpayments.length) return;
    downpayments[index].method = method;
    _downpaymentsManuallyModified = true;
    notifyListeners();
  }

  /// Number is auto-managed; ignore user input and resequence.
  void updateDownpaymentNumber(int index, String number) {
    if (index < 0 || index >= downpayments.length) return;
    _renumberDownpayments();
    notifyListeners();
  }

  void updateDownpaymentDate(int index, String dateStr) {
    if (index < 0 || index >= downpayments.length) return;
    final year = DateTime.now().year.toString();
    var s = dateStr.trim();
    if (s.isEmpty) {
      s = '$year-';
    } else if (!RegExp(r'^\d{4}-').hasMatch(s)) {
      // user typed without year -> prefix current year
      s = '$year-$s';
    }
    downpayments[index].date = s;
    _downpaymentsManuallyModified = true;
    notifyListeners();
  }

  void updateDownpaymentAmount(int index, String amountStr) {
    if (index < 0 || index >= downpayments.length) return;
    downpayments[index].amount = amountStr;
    _downpaymentsManuallyModified = true;
    notifyListeners();
  }

  // ===== Smart Downpayment Generation =====
  /// Generates downpayment schedule for rental quotations.
  /// In real estate rentals, payments are made in advance at the beginning
  /// of each rental period, not spread evenly throughout the entire lease term.
  void _generateSmartDownpayments() {
    // Don't auto-generate if user has manually modified downpayments
    // unless they explicitly ask for recalculation
    if (_downpaymentsManuallyModified) return;

    // Only generate if we have all required data
    final totalAmt = _toDoubleOrNull(totalAmount);
    final numInstallments = _toIntOrNull(numberOfInstallments);
    final startDateParsed = _toDateOrNull(startDate);
    final endDateParsed = _toDateOrNull(endDate);

    // Clear validation - need all 4 pieces of data
    if (totalAmt == null ||
        totalAmt <= 0 ||
        numInstallments == null ||
        numInstallments <= 0 ||
        startDateParsed == null ||
        endDateParsed == null ||
        endDateParsed.isBefore(startDateParsed)) {
      return;
    }

    // Calculate amount per installment
    final amountPerInstallment = totalAmt / numInstallments;

    // Calculate total months between start and end date
    final totalMonths = _getMonthsBetweenDates(startDateParsed, endDateParsed);

    // For rent payments, divide the rental period by number of installments
    // to get payment intervals (payments should be made in advance)
    final monthsBetweenPayments =
        numInstallments > 1 ? totalMonths / numInstallments : 0;

    // Clear existing downpayments and generate new ones
    downpayments.clear();

    for (int i = 0; i < numInstallments; i++) {
      // Calculate payment date - all payments should be in advance
      DateTime paymentDate;
      if (i == 0) {
        // First payment is always on start date (advance payment)
        paymentDate = startDateParsed;
      } else {
        // Subsequent payments are made at the beginning of each period
        // Calculate months to add based on payment intervals
        final monthsToAdd = (monthsBetweenPayments * i).round();
        paymentDate = _addMonthsToDate(startDateParsed, monthsToAdd);

        // Ensure the day stays the same as start date (handle month-end edge cases)
        paymentDate =
            _adjustDayToMatchStartDate(paymentDate, startDateParsed.day);

        // Ensure payment doesn't go beyond the end date
        if (paymentDate.isAfter(endDateParsed)) {
          // If calculated date exceeds end date, place it before end date
          // This handles edge cases where the calculation might push beyond contract end
          paymentDate = _addMonthsToDate(endDateParsed, -1);
          paymentDate =
              _adjustDayToMatchStartDate(paymentDate, startDateParsed.day);
        }
      }

      // Format date as YYYY-MM-DD
      final dateString = '${paymentDate.year.toString().padLeft(4, '0')}-'
          '${paymentDate.month.toString().padLeft(2, '0')}-'
          '${paymentDate.day.toString().padLeft(2, '0')}';

      // Use payment method from Money & Terms section
      final method = paymentType.isNotEmpty ? paymentType : '';

      downpayments.add(DownpaymentRowVM(
        method: method,
        number: '${i + 1}',
        date: dateString,
        amount: amountPerInstallment.toStringAsFixed(2),
      ));
    }
  }

  // /// Force recalculation even if user has made manual changes
  // void recalculateDownpayments() {
  //   _downpaymentsManuallyModified = false; // Reset flag
  //   _generateSmartDownpayments();
  //   notifyListeners();
  // }

  /// Trigger smart calculation if no downpayments exist and calculation is possible
  void triggerInitialSmartCalculation() {
    if (downpayments.isEmpty && canGenerateSmartDownpayments) {
      _generateSmartDownpayments();
      notifyListeners();
    }
  }

  /// Updates payment methods in existing downpayment rows when paymentType changes
  void _updateDownpaymentMethods() {
    if (downpayments.isNotEmpty && paymentType.isNotEmpty) {
      for (var payment in downpayments) {
        payment.method = paymentType;
      }
    }
  }

  // ===== Media (logo) =====
  Future<void> selectLogo(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        _selectedLogoFile = File(result.files.single.path!);
        officeLogoFileName = result.files.single.name;

        // Don't upload immediately - will be handled during save
        // Just update UI to show file is selected
        if (!_disposed) {
          _showToast('Logo selected: ${officeLogoFileName}', Colors.green);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Logo picking error: $e');
      if (!_disposed)
        _showToast('Error selecting logo: ${e.toString()}', Colors.red);
    }
  }

  void clearLogo() {
    _selectedLogoFile = null;
    _officeLogoUrl = null;
    officeLogoFileName = '';
    if (!_disposed) {
      _showToast('Logo cleared', Colors.orange);
      notifyListeners();
    }
  }

  // // ===== Validation =====
  // bool _validateForm() {
  //   if (propertyTitle.trim().isEmpty) {
  //     _showToast('Property title is required', Colors.red);
  //     return false;
  //   }
  //   if (officeName.trim().isEmpty) {
  //     _showToast('Office name is required', Colors.red);
  //     return false;
  //   }
  //   if (totalAmount.trim().isEmpty) {
  //     _showToast('Total amount is required', Colors.red);
  //     return false;
  //   }
  //   return true;
  // }

  // ===== Helpers: parsing & derived totals =====
  double? _toDoubleOrNull(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', ''));
  }

  int? _toIntOrNull(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  DateTime? _toDateOrNull(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  // --- Live auto totals ---
  void _recalcGovTotalIfAuto() {
    if (_govTotalManual) return;
    final t = _calcGovTotal();
    govTotal = t > 0 ? t.toStringAsFixed(2) : '';
  }

  void _recalcAdmTotalIfAuto() {
    if (_admTotalManual) return;
    final t = _calcAdmTotal();
    admTotal = t > 0 ? t.toStringAsFixed(2) : '';
  }

  /// Calculate the actual amount from percentage of total rent
  void _recalcGovCalculatedAmount() {
    final totalAmt = _toDoubleOrNull(totalAmount) ?? 0;
    final percent = _toDoubleOrNull(govPercentOfTotalRent);

    if (percent != null && percent > 0 && totalAmt > 0) {
      final calculatedAmount = totalAmt * percent / 100.0;
      govCalculatedAmount = calculatedAmount.toStringAsFixed(2);
    } else {
      govCalculatedAmount = '';
    }
  }

  double _calcGovTotal() {
    final totalAmt = _toDoubleOrNull(totalAmount) ?? 0;
    final percent = _toDoubleOrNull(govPercentOfTotalRent);
    final fromPercent = (percent == null) ? 0 : (totalAmt * percent / 100.0);
    final municipality = _toDoubleOrNull(govMunicipality) ?? 0;
    final electricity = _toDoubleOrNull(govElectricity) ?? 0;
    final sewerage = _toDoubleOrNull(govSewerage) ?? 0;
    return fromPercent + municipality + electricity + sewerage;
  }

  double _calcAdmTotal() {
    double total = 0;
    for (var fee in administrativeFees) {
      final amount = _toDoubleOrNull(fee.amount) ?? 0;
      total += amount;
    }
    return total;
  }

  /// Final safety before save (fills totals if user left them empty)
  void _computeDerivedTotals() {
    if (govTotal.trim().isEmpty) {
      final sum = _calcGovTotal();
      if (sum > 0) govTotal = sum.toStringAsFixed(2);
    }
    if (admTotal.trim().isEmpty) {
      final sum = _calcAdmTotal();
      if (sum > 0) admTotal = sum.toStringAsFixed(2);
    }
  }

  // ===== Save =====
  Future<void> save(BuildContext context) async {
    if (_disposed) return;
    // if (!_validateForm()) return;

    // QUOTA CHECK: Check if user can add more quotations
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final canAdd = await QuotaHelper.checkAndWarnQuota(
        context: context,
        uid: user.uid,
        section: 'quotations',
      );

      if (!canAdd) {
        return; // User hit quota limit
      }
    }

    _computeDerivedTotals();

    _isLoading = true;
    if (!_disposed) notifyListeners();

    try {
      final dpItems = downpayments.map((r) {
        return DownpaymentItem(
          method: PaymentMethodX.fromString(r.method),
          number: _toIntOrNull(r.number) ?? 0,
          date: _toDateOrNull(r.date),
          amount: _toDoubleOrNull(r.amount) ?? 0,
        );
      }).toList();

      final quotation = QuotationModel(
        userId: '',
        propertyTitle: propertyTitle,
        propertyType: propertyType.isEmpty ? null : propertyType,
        parking: parking,
        date: date.isEmpty ? null : date,
        startDate: startDate.isEmpty ? null : startDate,
        endDate: endDate.isEmpty ? null : endDate,
        currencyCode: currencyCode.isEmpty ? 'AED' : currencyCode,
        totalAmount: _toDoubleOrNull(totalAmount) ?? 0,
        numberOfInstallments: _toIntOrNull(numberOfInstallments),
        paymentType: paymentType,
        insuranceAmount: _toDoubleOrNull(insuranceAmount),
        insuranceReturnable: insuranceReturnable,
        officeName: officeName,
        officeLogoUrl: _officeLogoUrl,
        customNote: customNote.isEmpty ? null : customNote,
        welcomeMessageMode: welcomeMessageMode,
        customWelcomeMessage:
            customWelcomeMessage.isEmpty ? null : customWelcomeMessage,
        downpayments: dpItems,
        governmentFees: GovernmentFees(
          percentOfTotalRent: _toDoubleOrNull(govPercentOfTotalRent),
          municipality: _toDoubleOrNull(govMunicipality),
          electricity: _toDoubleOrNull(govElectricity),
          sewerage: _toDoubleOrNull(govSewerage),
          total: _toDoubleOrNull(govTotal),
        ),
        administrativeFees: AdministrativeFees(
          fees: administrativeFees.map((fee) {
            return AdministrativeFeeItem(
              title: fee.title,
              amount: _toDoubleOrNull(fee.amount) ?? 0,
            );
          }).toList(),
          total: _toDoubleOrNull(admTotal),
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      String? quotationId;
      if (_selectedLogoFile != null) {
        quotationId = await _quotationService.saveQuotationWithMediaFast(
          quotation,
          [_selectedLogoFile!],
        );
      } else {
        quotationId = await _quotationService.saveQuotation(quotation);
      }

      if (quotationId != null && !_disposed) {
        // Update quota count
        if (user != null) {
          await _incrementQuotaCount(user.uid, 'quotations');
        }

        // Generate PDF locally FIRST (fast local operation)
        await _generateAndSavePdfLocally(quotationId, quotation, context);
      }

      if (!_disposed && quotationId != null && context.mounted) {
        _showToast('Quotation and PDF saved successfully!', Colors.green);
        context.go('/home');
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (!_disposed) {
        _showToast('Failed to save quotation: ${e.toString()}', Colors.red);
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _incrementQuotaCount(String uid, String section) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (e) {
    }
  }

  // ===== Cancel =====
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
                  child: const Text('Keep Editing')),
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

  // ===== Date calculation helpers =====

  /// Calculate the number of months between two dates for rental period calculation
  int _getMonthsBetweenDates(DateTime startDate, DateTime endDate) {
    int months = (endDate.year - startDate.year) * 12;
    months += endDate.month - startDate.month;

    // For rental calculations, we typically want the full month count
    // If the end day is less than start day, we still count it as a full month
    // since rent is usually paid for complete months
    if (endDate.day >= startDate.day) {
      months += 0; // No adjustment needed
    }

    return months;
  }

  /// Add months to a date while maintaining the day of month
  DateTime _addMonthsToDate(DateTime date, int months) {
    int targetYear = date.year;
    int targetMonth = date.month + months;

    // Handle year overflow
    while (targetMonth > 12) {
      targetYear++;
      targetMonth -= 12;
    }
    while (targetMonth < 1) {
      targetYear--;
      targetMonth += 12;
    }

    // Try to maintain the same day, but handle month-end edge cases
    int targetDay = date.day;
    int daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;

    if (targetDay > daysInTargetMonth) {
      targetDay = daysInTargetMonth; // Use last day of target month
    }

    return DateTime(targetYear, targetMonth, targetDay);
  }

  /// Adjust the day to match the start date day, handling edge cases
  DateTime _adjustDayToMatchStartDate(DateTime date, int targetDay) {
    // Get the number of days in the target month
    int daysInMonth = DateTime(date.year, date.month + 1, 0).day;

    // If the target day exists in this month, use it
    if (targetDay <= daysInMonth) {
      return DateTime(date.year, date.month, targetDay);
    } else {
      // If target day doesn't exist (e.g., Feb 30), use the last day of the month
      return DateTime(date.year, date.month, daysInMonth);
    }
  }

  // ===== Toast =====
  void _showToast(String message, Color backgroundColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  // ===== Clear form =====
  void clearForm() {
    propertyTitle = '';
    propertyType = '';
    parking = false;
    date = '';
    startDate = '';
    endDate = '';
    customNote = '';

    // Welcome message fields
    welcomeMessageMode = WelcomeMessageMode.auto;
    customWelcomeMessage = '';

    currencyCode = 'AED';
    totalAmount = '';
    numberOfInstallments = '';
    paymentType = ''; // No default, let user choose
    insuranceAmount = '';
    insuranceReturnable = false;
    downpayments.clear();
    govPercentOfTotalRent = '';
    govCalculatedAmount = '';
    govMunicipality = '';
    govElectricity = '';
    govSewerage = '';
    govTotal = '';
    administrativeFees.clear();
    admTotal = '';
    officeName = '';
    officeLogoFileName = '';
    _officeLogoUrl = null;
    _selectedLogoFile = null;
    _govTotalManual = false;
    _admTotalManual = false;
    _downpaymentsManuallyModified = false;
    _endDateManuallyOverridden = false; // Reset end date override flag
    if (!_disposed) notifyListeners();
  }

  // ===== Local-First PDF Generation =====
  /// Generates PDF locally first, saves to local storage, updates DB with local path,
  /// then uploads to Firebase in background - Professional app approach
  Future<void> _generateAndSavePdfLocally(
    String quotationId,
    QuotationModel quotation,
    BuildContext context,
  ) async {
    try {
      // Get the current locale from context
      final currentLocale = Localizations.localeOf(context);

      // If user selected a logo file, inject it into the quotation for PDF generation
      final quotationForPdf = (_selectedLogoFile != null)
          ? quotation.copyWith(
              officeLogoUrl: 'file://${_selectedLogoFile!.path}')
          : quotation;

      // Check if we need to wait for logo upload completion
      final hasLocalLogo =
          quotation.officeLogoUrl?.startsWith('local://') == true ||
              quotation.officeLogoUrl?.startsWith('file://') == true;

      // Wait a small moment for logo upload to complete if needed
      if (hasLocalLogo) {
        await Future.delayed(const Duration(milliseconds: 300));

        // Get updated quotation data with uploaded logo
        final latestQuotation =
            await _quotationService.getQuotationById(quotationId);
        final quotationToUse = latestQuotation ?? quotationForPdf;

        // Generate PDF locally with updated data (may have file:// URL)
        final localPdfPath = await PdfGenerationService.generateQuotationPdf(
          quotationToUse,
          locale: currentLocale,
        );

        // Create local URL for immediate use
        final localPdfUrl = 'local://$localPdfPath';

        // Update quotation with LOCAL PDF URL immediately (user sees PDF instantly)
        await _quotationService.updateQuotation(
          quotationId,
          quotationToUse.copyWith(pdfUrl: localPdfUrl),
        );

        // Upload to Firebase in background (non-blocking)
        _uploadPdfToFirebaseInBackground(
            localPdfPath, quotationId, quotationToUse);
      } else {
        // Logo already uploaded or not needed, generate PDF immediately
        final pdfPath = await PdfGenerationService.generateQuotationPdf(
          quotationForPdf, // Use quotationForPdf which may have file:// URL
          locale: currentLocale,
        );

        // Create local URL for immediate use
        final localPdfUrl = 'local://$pdfPath';

        // Update quotation with LOCAL PDF URL immediately
        await _quotationService.updateQuotation(
          quotationId,
          quotationForPdf.copyWith(pdfUrl: localPdfUrl),
        );

        // Upload to Firebase in background (non-blocking)
        _uploadPdfToFirebaseInBackground(pdfPath, quotationId, quotation);
      }

    } catch (e) {
      // Don't show error to user for PDF generation, just log it
    }
  }

  /// Uploads PDF to Firebase Storage in background and updates database with Firebase URL
  Future<void> _uploadPdfToFirebaseInBackground(
    String localPdfPath,
    String quotationId,
    QuotationModel quotation,
  ) async {
    try {
      // Upload PDF to Firebase Storage
      final firebasePdfUrl = await PdfGenerationService.uploadPdfToStorage(
        localPdfPath,
        quotationId,
      );

      // Update quotation with Firebase URL (replaces local URL)
      await _quotationService.updateQuotation(
        quotationId,
        quotation.copyWith(pdfUrl: firebasePdfUrl),
      );

    } catch (e) {
      // PDF remains available locally, just log the upload error
    }
  }
}
