// lib/src/viewmodels/AddScreens/add_quotation_viewmodel.dart
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/logo_background_removal_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/logo_optimization_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_media_workflow.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/pdf_generation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_supabase_mapper.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/services/core_entity_quota_bridge.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:io';

/// Renders a Quotation to a local PDF file and returns its path.
typedef QuotationPdfGenerator = Future<String> Function(
    QuotationModel quotation, {Locale? locale});
typedef QuotationCreationGate = Future<bool> Function(BuildContext context);

/// How one save attempt ended.
enum QuotationSaveKind {
  /// The Quotation, its logo change (if any) and its PDF are all saved.
  saved,

  /// The Quotation is saved, but the logo or the PDF did not finish. Saving
  /// again retries them against the saved Quotation.
  mediaIncomplete,

  /// The Quotation itself was not saved.
  failed,

  /// The form cannot be saved as it is; nothing was sent.
  invalid,

  /// Another save was already running.
  busy,
}

/// How picking an office logo ended.
enum QuotationLogoPick {
  /// A valid logo is now selected (it is uploaded when the Quotation is saved).
  selected,

  /// The user closed the picker without choosing.
  dismissed,

  /// The chosen file is not an accepted logo (type or size).
  rejected,

  /// The picker itself failed.
  failed,
}

/// What the editor shows while a save runs. One save is one operation to the
/// user, so there is never more than one progress indicator.
enum QuotationSaveProgress {
  /// Not saving: no indicator.
  idle,

  /// Saving: the Save button shows its own spinner.
  saving,

  /// Saving for [AddQuotationViewModel.defaultLongSaveThreshold] or more: one
  /// centered indicator replaces the button's spinner.
  longSaving,
}

/// The result of [AddQuotationViewModel.performSave]: what happened, and the
/// localization key of the message that tells the user.
class QuotationSaveOutcome {
  const QuotationSaveOutcome._(
    this.kind, {
    this.failure,
    this.validation,
    this.logoFailure,
    this.pdfFailure,
    this.wasUpdate = false,
  });

  const QuotationSaveOutcome.busy() : this._(QuotationSaveKind.busy);

  final QuotationSaveKind kind;
  final QuotationFailure? failure;
  final QuotationValidationReason? validation;
  final QuotationMediaFailure? logoFailure;
  final QuotationMediaFailure? pdfFailure;

  /// The Quotation already existed on the server, so this was an update.
  final bool wasUpdate;

  /// The localization key to show, or null for the existing create message.
  String? get messageKey {
    switch (kind) {
      case QuotationSaveKind.busy:
        return null;
      case QuotationSaveKind.saved:
        return wasUpdate ? 'quotationUpdatedSuccessfully' : null;
      case QuotationSaveKind.mediaIncomplete:
        return 'quotationSavedMediaFailure';
      case QuotationSaveKind.invalid:
        return validation ==
                QuotationValidationReason.administrativeFeeTitleRequired
            ? 'quotationAdminFeeTitleRequired'
            : 'quotationTitleRequired';
      case QuotationSaveKind.failed:
        switch (failure) {
          case QuotationFailure.versionConflict:
            return 'quotationVersionConflict';
          case QuotationFailure.notFound:
          case QuotationFailure.deleted:
            return 'quotationNoLongerAvailable';
          case QuotationFailure.invalidPayload:
            return 'quotationInvalidData';
          case QuotationFailure.notSignedIn:
          case QuotationFailure.permissionDenied:
            return 'quotationSessionExpired';
          case QuotationFailure.network:
            return 'quotationNetworkError';
          case QuotationFailure.idConflict:
          case QuotationFailure.unknown:
          case null:
            return 'quotationSaveFailed';
        }
    }
  }
}

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
  final QuotationService _quotationService;
  final AuthRepository _authRepository;
  final QuotationPdfGenerator _generatePdf;
  final Future<File?> Function() _pickLogoFile;
  final LogoBackgroundRemovalService _logoBackgroundRemovalService;
  final LogoOptimizationService _logoOptimizationService;
  final QuotationCreationGate _canCreate;
  final void Function(String message, Color color) _toast;
  final Uuid _uuid;
  final Duration _longSaveThreshold;

  /// How long a save may run before its progress moves from the button to one
  /// centered indicator. A save that finishes sooner never shows it.
  static const defaultLongSaveThreshold = Duration(seconds: 2);

  /// The Quotation being edited, or null when creating a new one.
  final String? editQuotationId;

  AddQuotationViewModel({
    QuotationService? quotationService,
    AuthRepository? authRepository,
    this.editQuotationId,
    QuotationPdfGenerator? pdfGenerator,
    Future<File?> Function()? logoPicker,
    LogoBackgroundRemovalService? logoBackgroundRemovalService,
    LogoOptimizationService? logoOptimizationService,
    QuotationCreationGate? creationGate,
    void Function(String message, Color color)? toast,
    Uuid? uuid,
    Duration longSaveThreshold = defaultLongSaveThreshold,
  })  : _quotationService = quotationService ?? QuotationService(),
        _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository,
        _generatePdf = pdfGenerator ?? PdfGenerationService.generateQuotationPdf,
        _pickLogoFile = logoPicker ?? _pickLogoFromDevice,
        _logoBackgroundRemovalService =
            logoBackgroundRemovalService ?? const LogoBackgroundRemovalService(),
        _logoOptimizationService =
            logoOptimizationService ?? const LogoOptimizationService(),
        _longSaveThreshold = longSaveThreshold,
        _canCreate = creationGate ??
            ((context) => CoreEntityQuotaBridge.canCreate(
                  context: context,
                  section: 'quotations',
                )),
        _toast = toast ?? _showPlatformToast,
        _uuid = uuid ?? const Uuid();

  bool _disposed = false;

  // ===== Hosted identity (server-controlled; never typed by the user) =====
  /// The Quotation's id: the one being edited, or the one generated for the
  /// first save and kept so a retry replays the same Quotation.
  String? _quotationId;

  /// The version the server last reported. Null until the Quotation exists on
  /// the server; a save with a version is an optimistic update against it.
  int? _version;

  /// The media the server confirmed as bound. Replaced only after a confirm.
  String? _boundLogoMediaId;
  String? _boundPdfMediaId;

  /// The identity of the selected logo file's upload, reused when the same
  /// logo is retried so a lost confirm answer resolves instead of failing.
  String? _pendingLogoMediaId;

  /// The user cleared a logo that is bound on the server.
  bool _logoRemovalRequested = false;

  /// The last logo file uploaded in this session, kept to draw the PDF.
  File? _uploadedLogoFile;

  /// A temporary PNG created locally when the user opts into background
  /// removal. The original picked image is never modified.
  File? _processedLogoFile;

  /// A temporary downsized copy of the picked logo, made in the background as
  /// soon as it is picked so Save only reuses it. Null when the picked file
  /// already fits (or could not be decoded) and is used as it is.
  File? _optimizedLogoFile;
  Future<File?>? _logoOptimization;

  /// A private signed URL used only to preview a logo already bound on the
  /// server. It is never persisted.
  String? _boundLogoPreviewUrl;
  DateTime? _boundLogoPreviewExpiry;

  bool _removeLogoBackground = false;
  bool _isProcessingLogoBackground = false;
  bool _saveEntryActive = false;
  QuotationSaveProgress _saveProgress = QuotationSaveProgress.idle;
  Timer? _longSaveTimer;
  bool _mediaVersionNeedsRefresh = false;

  /// The renderer of a PDF whose database save failed, still finishing. The
  /// next save waits for it so it can never delete that attempt's new file.
  Future<void>? _pdfDiscard;

  /// Removals of temporary files (dispose, cleared logo, reloaded form), run
  /// one after another so they can be waited for.
  Future<void> _tempCleanup = Future<void>.value();

  // ===== Existing-quotation loading =====
  bool _isLoadingExisting = false;
  bool _loadFailed = false;

  bool get isEditMode => editQuotationId != null;
  bool get isLoadingExisting => _isLoadingExisting;
  bool get loadFailed => _loadFailed;

  /// The server version this form is based on, for display and tests.
  int? get version => _version;
  String? get quotationId => _quotationId;
  String? get boundLogoMediaId => _boundLogoMediaId;
  String? get boundPdfMediaId => _boundPdfMediaId;

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

  /// A logo the user picked that is not yet bound on the server.
  File? _selectedLogoFile;

  // ===== Loading states =====
  bool _isLoading = false;

  bool get isLoading => _isLoading || _saveEntryActive;
  QuotationSaveProgress get saveProgress => _saveProgress;
  File? get selectedLogoFile => _selectedLogoFile;
  bool get removeLogoBackground => _removeLogoBackground;
  bool get isProcessingLogoBackground => _isProcessingLogoBackground;
  bool get canRemoveLogoBackground => _selectedLogoFile != null;
  String? get officeLogoPreviewUrl => _boundLogoPreviewUrl;

  /// The file currently shown in the logo preview. A processed transparent
  /// PNG wins while background removal is enabled.
  File? get officeLogoPreviewFile {
    if (_removeLogoBackground && _processedLogoFile != null) {
      return _processedLogoFile;
    }
    return _selectedLogoFile ?? _uploadedLogoFile;
  }

  // Check if a logo is selected (a new file, or one bound on the server)
  bool get hasLogoSelected =>
      _selectedLogoFile != null ||
      (_boundLogoMediaId != null && !_logoRemovalRequested);

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
    if (_disposed) return;
    _disposed = true;
    _longSaveTimer?.cancel();
    _deleteInBackground(_processedLogoFile);
    _deleteInBackground(_optimizedLogoFile);
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
  /// The device's file picker, restricted to images. Returns null when the
  /// user dismisses it.
  static Future<File?> _pickLogoFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  /// Picks a logo. Nothing is sent until the Quotation is saved; a file the
  /// server would refuse (not a JPG, PNG or WebP, or over 10 MB) is turned
  /// away here, before it can replace anything.
  Future<void> selectLogo(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final result = await pickLogo();
    if (_disposed) return;
    switch (result) {
      case QuotationLogoPick.selected:
        _toast('Logo selected: $officeLogoFileName', Colors.green);
      case QuotationLogoPick.rejected:
        _toast(loc.translate('quotationLogoUnsupported'), Colors.red);
      case QuotationLogoPick.failed:
        _toast('Error selecting logo', Colors.red);
      case QuotationLogoPick.dismissed:
        break;
    }
  }

  /// The picking itself, without any UI: opens the picker, checks the chosen
  /// file, and selects it only if it passes.
  Future<QuotationLogoPick> pickLogo() async {
    try {
      final file = await _pickLogoFile();
      if (file == null || _disposed) return QuotationLogoPick.dismissed;

      try {
        await QuotationMediaWorkflow.checkLogo(file);
      } on QuotationMediaException {
        return QuotationLogoPick.rejected;
      }

      await _deleteQuietly(_processedLogoFile);
      await _deleteQuietly(_optimizedLogoFile);
      _processedLogoFile = null;
      _optimizedLogoFile = null;
      _removeLogoBackground = false;
      _boundLogoPreviewUrl = null;
      _boundLogoPreviewExpiry = null;
      _selectedLogoFile = file;
      officeLogoFileName = _fileName(file.path);
      // A new selection is a new upload identity, and cancels a pending
      // removal: the replacement itself supersedes the bound logo.
      _pendingLogoMediaId = null;
      _logoRemovalRequested = false;
      _logoOptimization = _optimizeLogo(file);

      // Don't upload immediately - will be handled during save
      // Just update UI to show file is selected
      if (!_disposed) notifyListeners();
      return QuotationLogoPick.selected;
    } catch (e) {
      if (kDebugMode) debugPrint('Logo picking failed: ${e.runtimeType}');
      return QuotationLogoPick.failed;
    }
  }

  Future<void> setRemoveLogoBackground(
    BuildContext context,
    bool value,
  ) async {
    if (_isProcessingLogoBackground || _disposed) return;

    if (!value) {
      if (_removeLogoBackground) _pendingLogoMediaId = null;
      _removeLogoBackground = false;
      if (!_disposed) notifyListeners();
      return;
    }

    final source = _selectedLogoFile;
    if (source == null) return;

    final cached = _processedLogoFile;
    final cachedExists = cached != null && await cached.exists();
    if (_disposed || !identical(source, _selectedLogoFile)) return;
    if (cachedExists) {
      _pendingLogoMediaId = null;
      _removeLogoBackground = true;
      if (!_disposed) notifyListeners();
      return;
    }
    _processedLogoFile = null;

    final loc = AppLocalizations.of(context);
    _isProcessingLogoBackground = true;
    notifyListeners();
    try {
      final processed =
          await _logoBackgroundRemovalService.removeBackground(source);
      try {
        await QuotationMediaWorkflow.checkLogo(processed);
      } on QuotationMediaException {
        await _deleteQuietly(processed);
        rethrow;
      }

      if (_disposed || !identical(source, _selectedLogoFile)) {
        await _deleteQuietly(processed);
        return;
      }
      await _deleteQuietly(_processedLogoFile);
      _processedLogoFile = processed;
      _pendingLogoMediaId = null;
      _removeLogoBackground = true;
    } catch (_) {
      if (_disposed || !identical(source, _selectedLogoFile)) return;
      _removeLogoBackground = false;
      await _deleteQuietly(_processedLogoFile);
      _processedLogoFile = null;
      _toast(
        loc.translate('quotationLogoBackgroundRemovalFailed'),
        Colors.red,
      );
    } finally {
      _isProcessingLogoBackground = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Makes the downsized copy of a just-picked logo in the background, so Save
  /// only reuses it. It never fails the pick: any problem leaves the picked
  /// file in use as it is.
  Future<File?> _optimizeLogo(File source) async {
    File? optimized;
    try {
      optimized = await _logoOptimizationService.optimize(source);
      if (optimized != null) await QuotationMediaWorkflow.checkLogo(optimized);
    } catch (_) {
      await _deleteQuietly(optimized);
      return null;
    }
    if (_disposed || !identical(source, _selectedLogoFile)) {
      await _deleteQuietly(optimized);
      return null;
    }
    _optimizedLogoFile = optimized;
    return optimized;
  }

  void clearLogo() {
    _deleteInBackground(_processedLogoFile);
    _deleteInBackground(_optimizedLogoFile);
    _selectedLogoFile = null;
    _uploadedLogoFile = null;
    _processedLogoFile = null;
    _optimizedLogoFile = null;
    _logoOptimization = null;
    _removeLogoBackground = false;
    _boundLogoPreviewUrl = null;
    _boundLogoPreviewExpiry = null;
    _pendingLogoMediaId = null;
    officeLogoFileName = '';
    // A logo bound on the server is removed on save; until then it stays.
    _logoRemovalRequested = _boundLogoMediaId != null;
    if (!_disposed) {
      _toast('Logo cleared', Colors.orange);
      notifyListeners();
    }
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/') ? normalized.split('/').last : normalized;
  }

  static String _transparentLogoFileName(String original) {
    final dot = original.lastIndexOf('.');
    final base = dot > 0 ? original.substring(0, dot) : original;
    return '${base}_transparent.png';
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
  /// Saves the Quotation, then its logo change and its PDF, and tells the user
  /// how it went. Creating a Quotation needs free-plan quota; updating one
  /// does not.
  Future<void> save(BuildContext context) async {
    if (_disposed || isLoading || _isProcessingLogoBackground) return;
    _saveEntryActive = true;
    _beginSaveProgress();
    final clock = _SaveTimeline();
    final endUi = clock.begin('UI total');
    late QuotationSaveOutcome outcome;
    late AppLocalizations loc;
    late Locale locale;
    final wasEditing = isEditMode;
    try {
      final currentUserId = _authRepository.currentUserId;
      if (currentUserId == null) {
        _showToast('User must be logged in to create quotations', Colors.red);
        return;
      }

      if (_version == null) {
        final endQuota = clock.begin('quota preflight');
        final canAdd = await _canCreate(context);
        endQuota();
        if (!canAdd || _disposed || !context.mounted) return;
      }

      loc = AppLocalizations.of(context);
      locale = Localizations.localeOf(context);
      outcome =
          await _performSave(locale: locale, fromSave: true, clock: clock);
    } finally {
      _saveEntryActive = false;
      endUi();
      _finishSaveProgress();
    }
    if (_disposed ||
        !context.mounted ||
        outcome.kind == QuotationSaveKind.busy) {
      return;
    }

    final key = outcome.messageKey;
    switch (outcome.kind) {
      case QuotationSaveKind.saved:
        _showToast(
          key == null
              ? 'Quotation and PDF saved successfully!'
              : loc.translate(key),
          Colors.green,
        );
        if (wasEditing && context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      case QuotationSaveKind.mediaIncomplete:
        _showToast(loc.translate(key!), Colors.orange);
      case QuotationSaveKind.failed:
      case QuotationSaveKind.invalid:
        _showToast(loc.translate(key!), Colors.red);
      case QuotationSaveKind.busy:
        break;
    }
  }

  /// One save attempt, without any UI: the aggregate through `save_quotation`
  /// (a create, or an update against [version]), then the logo change, then a
  /// freshly generated PDF.
  ///
  /// The database aggregate and the media are separate trusted lifecycles, so
  /// this is not a transaction. The Quotation is saved first; the logo and the
  /// PDF are then bound to the saved Quotation, each replacing the previous
  /// one only after the server confirms it. A media failure leaves the saved
  /// Quotation intact (and the previously bound media in place) and is
  /// reported in the outcome; saving again retries it as an update.
  ///
  /// The PDF is not part of "after": it is drawn only from the form, so it is
  /// prepared while the database saves. Publishing it still waits for the save
  /// and for the logo, and a PDF whose save failed is discarded.
  Future<QuotationSaveOutcome> performSave({Locale? locale}) =>
      _performSave(locale: locale);

  Future<QuotationSaveOutcome> _performSave({
    Locale? locale,
    bool fromSave = false,
    _SaveTimeline? clock,
  }) async {
    if (_disposed ||
        _isLoading ||
        _isProcessingLogoBackground ||
        (_saveEntryActive && !fromSave)) {
      return const QuotationSaveOutcome.busy();
    }

    final userId = _authRepository.currentUserId;
    if (userId == null) {
      return const QuotationSaveOutcome._(
        QuotationSaveKind.failed,
        failure: QuotationFailure.notSignedIn,
      );
    }

    _isLoading = true;
    _beginSaveProgress();
    final timeline = clock ?? _SaveTimeline();
    final endTotal = timeline.begin('total');

    try {
      // A failed attempt's PDF renderer may still be finishing; it must end
      // before this attempt writes the same file.
      await _pdfDiscard;
      if (_disposed) return const QuotationSaveOutcome.busy();

      final endPreparation = timeline.begin('local preparation');
      _computeDerivedTotals();
      final wasUpdate = _version != null;
      final id = _quotationId ??=
          editQuotationId ?? _quotationService.generateNewQuotationId();
      final model = _buildModel(userId);
      try {
        // A form that can never be saved starts no work at all.
        QuotationSupabaseMapper.validate(model);
      } on QuotationValidationException catch (error) {
        return QuotationSaveOutcome._(
          QuotationSaveKind.invalid,
          validation: error.reason,
        );
      }
      final logo = _pickedLogoForSave();
      endPreparation();

      // The save's media steps and the database save each tell the lists to
      // refresh; one refresh at the end is enough.
      return await _quotationService.batchMutations(() => _saveAndPublish(
            id: id,
            model: model,
            wasUpdate: wasUpdate,
            logo: logo,
            locale: locale,
            timeline: timeline,
          ));
    } finally {
      _isLoading = false;
      endTotal();
      if (!_saveEntryActive) _finishSaveProgress();
    }
  }

  Future<QuotationSaveOutcome> _saveAndPublish({
    required String id,
    required QuotationModel model,
    required bool wasUpdate,
    required _PickedLogo? logo,
    required Locale? locale,
    required _SaveTimeline timeline,
  }) async {
    // The PDF carries nothing the server assigns, so it is prepared while the
    // database saves, not after. Both start here, in the same turn.
    final preparedPdf = _preparePdf(id, model, locale, logo, timeline);

    // This save owns the prepared PDF until [_publishPdf] takes it over, which
    // then publishes it or deletes it. On every other way out (a failed save,
    // or anything unexpected) the PDF is discarded here. It is a local only:
    // no later save can ever pick this result up.
    var pdfHandedOver = false;
    try {
      final QuotationSaveResult saved;
      final endDatabase = timeline.begin('database save');
      try {
        saved = await _quotationService.saveQuotation(
          model,
          quotationId: id,
          expectedVersion: _version,
        );
      } catch (error) {
        return _saveFailure(error);
      } finally {
        endDatabase();
      }
      _version = saved.version;
      if (!wasUpdate && saved.outcome == 'created') {
        unawaited(CoreEntityQuotaBridge.recordCreated(section: 'quotations'));
      }

      // Media changes bump the server version one after another, each against
      // the slot it replaces, so they stay in this order.
      _mediaVersionNeedsRefresh = false;
      final endLogo = timeline.begin('logo sync');
      final logoFailure = await _syncLogo(id, logo);
      endLogo();
      final endPublish = timeline.begin('PDF publication');
      pdfHandedOver = true;
      final pdfFailure = await _publishPdf(id, preparedPdf);
      endPublish();
      if (_mediaVersionNeedsRefresh) {
        final endRefresh = timeline.begin('media state refresh (fallback)');
        await _refreshServerState(id);
        endRefresh();
      }

      return QuotationSaveOutcome._(
        logoFailure == null && pdfFailure == null
            ? QuotationSaveKind.saved
            : QuotationSaveKind.mediaIncomplete,
        logoFailure: logoFailure,
        pdfFailure: pdfFailure,
        wasUpdate: wasUpdate,
      );
    } finally {
      if (!pdfHandedOver) _discardPreparedPdf(preparedPdf);
    }
  }

  static QuotationSaveOutcome _saveFailure(Object error) {
    if (error is QuotationValidationException) {
      return QuotationSaveOutcome._(
        QuotationSaveKind.invalid,
        validation: error.reason,
      );
    }
    return QuotationSaveOutcome._(
      QuotationSaveKind.failed,
      failure: error is QuotationException
          ? error.failure
          : QuotationFailure.unknown,
    );
  }

  /// The save is saving (the button spins), and becomes a long save (one
  /// centered indicator instead) if it is still running at the threshold.
  void _beginSaveProgress() {
    if (_saveProgress != QuotationSaveProgress.idle) return;
    _saveProgress = QuotationSaveProgress.saving;
    _longSaveTimer = Timer(_longSaveThreshold, () {
      if (_disposed || _saveProgress != QuotationSaveProgress.saving) return;
      _saveProgress = QuotationSaveProgress.longSaving;
      notifyListeners();
    });
    if (!_disposed) notifyListeners();
  }

  void _finishSaveProgress() {
    _longSaveTimer?.cancel();
    _longSaveTimer = null;
    _saveProgress = QuotationSaveProgress.idle;
    if (!_disposed) notifyListeners();
  }

  /// The logo this save uploads and draws, decided before the save starts so
  /// the PDF and the upload agree on it. Null when no new logo was picked.
  _PickedLogo? _pickedLogoForSave() {
    final selected = _selectedLogoFile;
    if (selected == null) return null;
    final processed = _processedLogoFile;
    if (_removeLogoBackground && processed != null) {
      return _PickedLogo(Future.value(processed), backgroundRemoved: true);
    }
    return _PickedLogo(
      _optimizedOrPicked(selected, _logoOptimization),
      backgroundRemoved: false,
    );
  }

  /// The downsized copy made when the logo was picked (Save waits for it only
  /// if it is still being made), or the picked file when there is none.
  Future<File> _optimizedOrPicked(
    File picked,
    Future<File?>? optimization,
  ) async =>
      (await optimization) ?? picked;

  /// Binds a newly picked logo, or removes a cleared one, against the logo the
  /// server last confirmed. The bound logo changes only when the server says
  /// so; on any failure it is left exactly as it was.
  Future<QuotationMediaFailure?> _syncLogo(
    String quotationId,
    _PickedLogo? picked,
  ) async {
    try {
      if (picked != null) {
        final uploadFile = await picked.file;
        final pendingId = _pendingLogoMediaId ??= _uuid.v4();
        final binding = await _quotationService.uploadOfficeLogo(
          quotationId: quotationId,
          file: uploadFile,
          expectedMediaId: _boundLogoMediaId,
          mediaObjectId: pendingId,
          originalFileName: picked.backgroundRemoved
              ? _transparentLogoFileName(officeLogoFileName)
              : officeLogoFileName,
        );
        _boundLogoMediaId = binding.mediaObjectId;
        _uploadedLogoFile = uploadFile;
        _selectedLogoFile = null;
        _logoOptimization = null;
        _boundLogoPreviewUrl = null;
        _boundLogoPreviewExpiry = null;
        _removeLogoBackground = false;
        _pendingLogoMediaId = null;
        _logoRemovalRequested = false;
        if (binding.resultingVersion != null) {
          _version = binding.resultingVersion;
        } else {
          _mediaVersionNeedsRefresh = true;
        }
      } else if (_logoRemovalRequested) {
        if (_boundLogoMediaId != null) {
          final removal = await _quotationService.removeOfficeLogo(
            quotationId: quotationId,
            expectedMediaId: _boundLogoMediaId,
          );
          if (removal.resultingVersion != null) {
            _version = removal.resultingVersion;
          } else {
            _mediaVersionNeedsRefresh = true;
          }
        }
        _boundLogoMediaId = null;
        _uploadedLogoFile = null;
        _logoRemovalRequested = false;
      }
      return null;
    } on QuotationMediaException catch (error) {
      _mediaVersionNeedsRefresh = true;
      return error.failure;
    } catch (_) {
      _mediaVersionNeedsRefresh = true;
      return QuotationMediaFailure.unknown;
    }
  }

  /// Renders the one PDF of this save. It runs while the database saves and
  /// the logo uploads; a failed renderer is reported as incomplete media,
  /// never as a saved PDF.
  Future<File?> _preparePdf(
    String quotationId,
    QuotationModel model,
    Locale? locale,
    _PickedLogo? picked,
    _SaveTimeline timeline,
  ) async {
    final endPreparation = timeline.begin('PDF preparation');
    try {
      // Everything about the logo is read here, before the first await, so the
      // answer does not depend on how far the save has progressed.
      final logoSource = await _logoSourceForPdf(
        quotationId,
        picked: picked,
        uploaded: _uploadedLogoFile,
        removed: _logoRemovalRequested,
        boundLogoId: _boundLogoMediaId,
        previewUrl: _boundLogoPreviewUrl,
        previewExpiry: _boundLogoPreviewExpiry,
      );
      final forPdf = model.copyWith(id: quotationId, officeLogoUrl: logoSource);
      return File(await _generatePdf(forPdf, locale: locale));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Quotation PDF preparation failed: ${error.runtimeType}');
      }
      return null;
    } finally {
      endPreparation();
    }
  }

  /// The PDF prepared beside a save that did not publish it. A running render
  /// cannot be cancelled, so it is left to finish: its file (private user
  /// data) is deleted the moment it exists, nothing waits for it before the
  /// user hears about the failure, and the next save waits for it so the two
  /// can never touch the same file.
  void _discardPreparedPdf(Future<File?> prepared) {
    _pdfDiscard = prepared.then(_deleteQuietly);
  }

  /// Completes when everything this view-model started in the background has
  /// finished and removed its own files: a discarded PDF render, a logo copy
  /// still being made, and temporary files deleted by [dispose], a cleared logo
  /// or a reloaded form. Tests wait on it before removing their temporary
  /// directory.
  @visibleForTesting
  Future<void> backgroundWorkSettled() async {
    await _pdfDiscard;
    await _logoOptimization;
    await _tempCleanup;
  }

  /// Removes a temporary file this view-model owns, in order with its other
  /// removals, without making the caller wait.
  void _deleteInBackground(File? file) {
    if (file == null) return;
    _tempCleanup = _tempCleanup.then((_) => _deleteQuietly(file));
  }

  /// Publishes only after logo sync; success still requires private PDF confirm.
  Future<QuotationMediaFailure?> _publishPdf(
    String quotationId,
    Future<File?> preparedPdf,
  ) async {
    final generated = await preparedPdf;
    if (generated == null) return QuotationMediaFailure.unknown;
    try {
      final binding = await _quotationService.publishPdf(
        quotationId: quotationId,
        pdf: generated,
        expectedMediaId: _boundPdfMediaId,
      );
      _boundPdfMediaId = binding.mediaObjectId;
      if (binding.resultingVersion != null) {
        _version = binding.resultingVersion;
      } else {
        _mediaVersionNeedsRefresh = true;
      }
      return null;
    } on QuotationMediaException catch (error) {
      _mediaVersionNeedsRefresh = true;
      await _deleteQuietly(generated);
      return error.failure;
    } catch (_) {
      _mediaVersionNeedsRefresh = true;
      await _deleteQuietly(generated);
      return QuotationMediaFailure.unknown;
    }
  }

  /// Where the PDF draws the office logo from: the logo being picked now (the
  /// prepared one), the file uploaded earlier in this session, or a short-lived
  /// signed URL for the bound logo, reused while it is still valid. Never
  /// stored; null when the Quotation has no logo.
  Future<String?> _logoSourceForPdf(
    String quotationId, {
    required _PickedLogo? picked,
    required File? uploaded,
    required bool removed,
    required String? boundLogoId,
    required String? previewUrl,
    required DateTime? previewExpiry,
  }) async {
    final local = picked != null ? await picked.file : uploaded;
    if (local != null && await local.exists()) {
      return Uri.file(local.path).toString();
    }
    if (removed || boundLogoId == null) return null;
    if (previewUrl != null &&
        previewExpiry != null &&
        previewExpiry
            .isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return previewUrl;
    }
    try {
      final signed = await _quotationService.signedOfficeLogo(quotationId);
      _boundLogoPreviewUrl = signed?.url;
      _boundLogoPreviewExpiry = signed?.expiresAt;
      return signed?.url;
    } catch (_) {
      return null;
    }
  }

  /// Media changes bump the server version; adopt it (and the bound ids) so
  /// the next save is an update against what the server really holds.
  Future<void> _refreshServerState(String quotationId) async {
    try {
      final state = await _quotationService.getMediaState(quotationId);
      if (state == null) return;
      _version = state.version;
      if (_boundLogoMediaId != state.officeLogoMediaId) {
        _boundLogoPreviewUrl = null;
        _boundLogoPreviewExpiry = null;
      }
      _boundLogoMediaId = state.officeLogoMediaId;
      _boundPdfMediaId = state.pdfMediaId;
    } catch (_) {
      // Keep the tracked values; the next save reports any real difference.
    }
  }

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// The form as a [QuotationModel]. Media ids are not part of it: they are
  /// server-controlled and are never sent by a save.
  QuotationModel _buildModel(String userId) {
    final dpItems = downpayments.map((r) {
      return DownpaymentItem(
        method: PaymentMethodX.fromString(r.method),
        number: _toIntOrNull(r.number) ?? 0,
        date: _toDateOrNull(r.date),
        amount: _toDoubleOrNull(r.amount) ?? 0,
      );
    }).toList();

    return QuotationModel(
      userId: userId,
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
  }

  // ===== Reopen / edit =====
  /// Loads the hosted aggregate into the form and keeps its version, so the
  /// next save is an update against exactly that version.
  Future<void> loadForEdit() async {
    final id = editQuotationId;
    if (id == null || _disposed) return;
    _isLoadingExisting = true;
    _loadFailed = false;
    notifyListeners();
    try {
      final quotation = await _quotationService.getQuotationById(id);
      if (quotation == null) {
        _loadFailed = true;
      } else {
        _quotationId = id;
        _applyModel(quotation);
        await _loadLogoPresentation();
      }
    } catch (_) {
      _loadFailed = true;
    } finally {
      _isLoadingExisting = false;
      notifyListeners();
    }
  }

  Future<void> _loadLogoPresentation() async {
    final logoId = _boundLogoMediaId;
    final quotationId = _quotationId ?? editQuotationId;
    if (logoId == null || quotationId == null) return;

    String? name;
    try {
      name = await _quotationService.getMediaFileName(logoId);
    } catch (_) {}
    officeLogoFileName = name ?? 'logo';

    try {
      final signed = await _quotationService.signedOfficeLogo(quotationId);
      _boundLogoPreviewUrl = signed?.url;
      _boundLogoPreviewExpiry = signed?.expiresAt;
    } catch (_) {
      _boundLogoPreviewUrl = null;
      _boundLogoPreviewExpiry = null;
    }
  }

  /// Fills the form from a loaded Quotation. A value the user did not type is
  /// not auto-recalculated over: a loaded schedule and end date count as
  /// entered, and a stored government total that differs from the sum of its
  /// parts counts as a manual total.
  void _applyModel(QuotationModel q) {
    propertyTitle = q.propertyTitle;
    propertyType = q.propertyType ?? '';
    parking = q.parking ?? false;
    date = q.date ?? '';
    startDate = q.startDate ?? '';
    endDate = q.endDate ?? '';
    customNote = q.customNote ?? '';
    welcomeMessageMode = q.welcomeMessageMode;
    customWelcomeMessage = q.customWelcomeMessage ?? '';
    currencyCode = (q.currencyCode == null || q.currencyCode!.isEmpty)
        ? 'AED'
        : q.currencyCode!;
    // A blank total is stored as 0; show it blank again.
    totalAmount = (q.totalAmount == null || q.totalAmount == 0)
        ? ''
        : _numberText(q.totalAmount!);
    numberOfInstallments = q.numberOfInstallments?.toString() ?? '';
    paymentType = q.paymentType ?? '';
    insuranceAmount =
        q.insuranceAmount == null ? '' : _numberText(q.insuranceAmount!);
    insuranceReturnable = q.insuranceReturnable ?? false;
    officeName = q.officeName;

    downpayments
      ..clear()
      ..addAll(q.downpayments.map((d) => DownpaymentRowVM(
            method: d.method.asString,
            number: '${d.number}',
            date: d.date == null ? '' : _dateText(d.date!),
            amount: d.amount.toStringAsFixed(2),
          )));

    final gov = q.governmentFees;
    govPercentOfTotalRent = gov.percentOfTotalRent == null
        ? ''
        : _numberText(gov.percentOfTotalRent!);
    govMunicipality =
        gov.municipality == null ? '' : _numberText(gov.municipality!);
    govElectricity =
        gov.electricity == null ? '' : _numberText(gov.electricity!);
    govSewerage = gov.sewerage == null ? '' : _numberText(gov.sewerage!);
    govTotal = gov.total == null ? '' : gov.total!.toStringAsFixed(2);
    _recalcGovCalculatedAmount();

    administrativeFees
      ..clear()
      ..addAll(q.administrativeFees.fees.map((f) => AdministrativeFeeRowVM(
            title: f.title,
            amount: _numberText(f.amount),
          )));
    admTotal = q.administrativeFees.fees.isEmpty
        ? ''
        : _calcAdmTotal().toStringAsFixed(2);

    _downpaymentsManuallyModified = downpayments.isNotEmpty;
    _endDateManuallyOverridden = endDate.isNotEmpty;
    _govTotalManual =
        gov.total != null && (gov.total! - _calcGovTotal()).abs() > 0.005;
    _admTotalManual = false;

    _version = q.version;
    _boundLogoMediaId = q.officeLogoMediaId;
    _boundPdfMediaId = q.pdfMediaId;
    _deleteInBackground(_processedLogoFile);
    _deleteInBackground(_optimizedLogoFile);
    _uploadedLogoFile = null;
    _selectedLogoFile = null;
    _processedLogoFile = null;
    _optimizedLogoFile = null;
    _logoOptimization = null;
    _boundLogoPreviewUrl = null;
    _boundLogoPreviewExpiry = null;
    _removeLogoBackground = false;
    _isProcessingLogoBackground = false;
    _pendingLogoMediaId = null;
    _logoRemovalRequested = false;
    officeLogoFileName = '';
  }

  String _numberText(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  String _dateText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
  void _showToast(String message, Color backgroundColor) =>
      _toast(message, backgroundColor);

  static void _showPlatformToast(String message, Color backgroundColor) {
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
    _deleteInBackground(_processedLogoFile);
    _deleteInBackground(_optimizedLogoFile);
    _selectedLogoFile = null;
    _uploadedLogoFile = null;
    _processedLogoFile = null;
    _optimizedLogoFile = null;
    _logoOptimization = null;
    _boundLogoPreviewUrl = null;
    _boundLogoPreviewExpiry = null;
    _removeLogoBackground = false;
    _isProcessingLogoBackground = false;
    _pendingLogoMediaId = null;
    _logoRemovalRequested = false;
    _govTotalManual = false;
    _admTotalManual = false;
    _downpaymentsManuallyModified = false;
    _endDateManuallyOverridden = false; // Reset end date override flag
    if (!_disposed) notifyListeners();
  }
}

/// Developer-only timing of one save (debug builds only). Stages are stamped
/// against one clock, so work that overlaps (the PDF is prepared while the
/// database saves) reads as overlapping ranges. It records no user data, URL or
/// token, and nothing here is ever shown to the user.
class _SaveTimeline {
  _SaveTimeline() : _clock = kDebugMode ? (Stopwatch()..start()) : null;

  final Stopwatch? _clock;

  /// Starts [stage]; call the returned function when it ends.
  void Function() begin(String stage) {
    final clock = _clock;
    if (clock == null) return _ignore;
    final startedAt = clock.elapsedMilliseconds;
    return () => debugPrint(
          'Quotation save timing: $stage +${startedAt}ms..+${clock.elapsedMilliseconds}ms',
        );
  }

  static void _ignore() {}
}

/// The logo a save uploads and draws, decided before the save starts: [file]
/// resolves to the transparent PNG when background removal is on, otherwise to
/// the downsized copy (Save waits for it only if it is still being made) or the
/// picked file itself.
class _PickedLogo {
  const _PickedLogo(this.file, {required this.backgroundRemoved});

  final Future<File> file;
  final bool backgroundRemoved;
}
