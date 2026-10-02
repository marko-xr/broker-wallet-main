// lib/src/views/Screens/home/quotation/quotation_model.dart

/// Payment method for a single downpayment row.
enum PaymentMethod { cash, cheque, bankTransfer, other }

/// Welcome message display mode for PDF generation.
enum WelcomeMessageMode { auto, custom, hidden }

extension PaymentMethodX on PaymentMethod {
  String get asString {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.cheque:
        return 'cheque';
      case PaymentMethod.bankTransfer:
        return 'bankTransfer';
      case PaymentMethod.other:
        return 'other';
    }
  }

  static PaymentMethod fromString(String? v) {
    switch (v) {
      case 'cash':
        return PaymentMethod.cash;
      case 'cheque':
        return PaymentMethod.cheque;
      case 'bankTransfer':
        return PaymentMethod.bankTransfer;
      default:
        return PaymentMethod.other;
    }
  }
}

extension WelcomeMessageModeX on WelcomeMessageMode {
  String get asString {
    switch (this) {
      case WelcomeMessageMode.auto:
        return 'auto';
      case WelcomeMessageMode.custom:
        return 'custom';
      case WelcomeMessageMode.hidden:
        return 'hidden';
    }
  }

  static WelcomeMessageMode fromString(String? v) {
    switch (v) {
      case 'auto':
        return WelcomeMessageMode.auto;
      case 'custom':
        return WelcomeMessageMode.custom;
      case 'hidden':
        return WelcomeMessageMode.hidden;
      default:
        return WelcomeMessageMode.auto;
    }
  }
}

/// Table row under "Downpayments" (Payment method / No. / Date / Amount).
class DownpaymentItem {
  final PaymentMethod method;
  final int number; // installment sequence number (1..n)
  final DateTime? date; // nullable to allow empty date fields in UI
  final double amount;

  DownpaymentItem({
    required this.method,
    required this.number,
    required this.amount,
    this.date,
  });
}

/// Government fees section (e.g., 2% of total rent, Municipality, Electricity, Sewerage, Total).
class GovernmentFees {
  final double? percentOfTotalRent; // e.g., 2 -> means 2%
  final double? municipality;
  final double? electricity;
  final double? sewerage;
  final double? total; // optional, may be computed on the fly

  GovernmentFees({
    this.percentOfTotalRent,
    this.municipality,
    this.electricity,
    this.sewerage,
    this.total,
  });

  /// Whether any value is present. An all-empty section is not stored.
  bool get isEmpty =>
      percentOfTotalRent == null &&
      municipality == null &&
      electricity == null &&
      sewerage == null &&
      total == null;

  GovernmentFees copyWith({
    double? percentOfTotalRent,
    double? municipality,
    double? electricity,
    double? sewerage,
    double? total,
  }) {
    return GovernmentFees(
      percentOfTotalRent: percentOfTotalRent ?? this.percentOfTotalRent,
      municipality: municipality ?? this.municipality,
      electricity: electricity ?? this.electricity,
      sewerage: sewerage ?? this.sewerage,
      total: total ?? this.total,
    );
  }
}

/// Administrative fee item for dynamic fees.
class AdministrativeFeeItem {
  final String title;
  final double amount;

  AdministrativeFeeItem({
    required this.title,
    required this.amount,
  });
}

/// Administrative fees section with dynamic fee items.
class AdministrativeFees {
  final List<AdministrativeFeeItem> fees;

  /// The section total. The hosted contract stores the fee rows only, so a
  /// reopened Quotation carries the sum of its rows here.
  final double? total;

  AdministrativeFees({
    this.fees = const [],
    this.total,
  });

  AdministrativeFees copyWith({
    List<AdministrativeFeeItem>? fees,
    double? total,
  }) {
    return AdministrativeFees(
      fees: fees ?? this.fees,
      total: total ?? this.total,
    );
  }
}

/// The main Quotation model adjusted to match the final DOCX format.
/// All fields are optional-friendly so empty rows/sections can be hidden in the PDF.
///
/// Persistence is the hosted Supabase aggregate (`save_quotation`). Private
/// media is referenced by stable media id only ([officeLogoMediaId],
/// [pdfMediaId]); both are server-controlled and are never part of a save.
/// [officeLogoUrl] is a transient presentation source for PDF generation (a
/// local file path or a short-lived signed URL) and is never persisted.
class QuotationModel {
  final String? id;
  final String userId;

  // Header / general
  final String propertyTitle; // e.g., "Apartment 306"
  final String? propertyType; // e.g., Apartment / Office
  final bool?
      parking; // Yes/No (if true, show in PDF; if false/null, don't show)
  final String? subtitle;
  final String? date; // keep as String to avoid breaking current UI
  final String? startDate; // "Starting"
  final String? endDate; // "Ending"
  final String? currencyCode; // default 'AED' in VM/UI if null

  // Money & terms
  final double? professionalFee; // "Professional Fee"
  final double? totalAmount; // "Total amount" (overall)
  final int? numberOfInstallments; // "Number of installments"
  final String?
      paymentType; // 'cash' | 'cheque' | 'bankTransfer' | 'other' (UI form)
  final double? insuranceAmount; // e.g., 2000
  final bool? insuranceReturnable; // "returnable"

  // Office
  final String officeName;
  final String? officeLogoUrl; // transient presentation source, never stored

  // Notes
  final String? customNote; // extra note line if needed

  // Welcome message configuration
  final WelcomeMessageMode welcomeMessageMode; // auto, custom, or hidden
  final String? customWelcomeMessage; // used when mode is 'custom'

  // Tables / sections
  final List<DownpaymentItem> downpayments;
  final GovernmentFees governmentFees;
  final AdministrativeFees administrativeFees;

  // Hosted identity (server-controlled)
  /// The aggregate version the server last reported. Null until the
  /// Quotation exists on the server.
  final int? version;

  /// The bound office logo's stable media id, or null.
  final String? officeLogoMediaId;

  /// The bound PDF's stable media id, or null.
  final String? pdfMediaId;

  final DateTime createdAt;
  final DateTime updatedAt;

  QuotationModel({
    this.id,
    required this.userId,
    required this.propertyTitle,
    required this.officeName,
    required this.createdAt,
    required this.updatedAt,
    this.propertyType,
    this.parking,
    this.subtitle,
    this.date,
    this.startDate,
    this.endDate,
    this.currencyCode,
    this.professionalFee,
    this.totalAmount,
    this.numberOfInstallments,
    this.paymentType,
    this.insuranceAmount,
    this.insuranceReturnable,
    this.officeLogoUrl,
    this.customNote,
    this.welcomeMessageMode = WelcomeMessageMode.auto,
    this.customWelcomeMessage,
    this.downpayments = const [],
    GovernmentFees? governmentFees,
    AdministrativeFees? administrativeFees,
    this.version,
    this.officeLogoMediaId,
    this.pdfMediaId,
  })  : governmentFees = governmentFees ?? GovernmentFees(),
        administrativeFees = administrativeFees ?? AdministrativeFees();

  /// Whether a generated PDF is bound to this Quotation.
  bool get hasPdf => pdfMediaId != null && pdfMediaId!.isNotEmpty;

  /// Whether an office logo is bound to this Quotation.
  bool get hasLogo => officeLogoMediaId != null && officeLogoMediaId!.isNotEmpty;

  QuotationModel copyWith({
    String? id,
    String? userId,
    String? propertyTitle,
    String? propertyType,
    bool? parking,
    String? subtitle,
    String? date,
    String? startDate,
    String? endDate,
    String? currencyCode,
    double? professionalFee,
    double? totalAmount,
    int? numberOfInstallments,
    String? paymentType,
    double? insuranceAmount,
    bool? insuranceReturnable,
    String? officeName,
    String? officeLogoUrl,
    String? customNote,
    WelcomeMessageMode? welcomeMessageMode,
    String? customWelcomeMessage,
    List<DownpaymentItem>? downpayments,
    GovernmentFees? governmentFees,
    AdministrativeFees? administrativeFees,
    int? version,
    String? officeLogoMediaId,
    String? pdfMediaId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuotationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      propertyTitle: propertyTitle ?? this.propertyTitle,
      propertyType: propertyType ?? this.propertyType,
      parking: parking ?? this.parking,
      subtitle: subtitle ?? this.subtitle,
      date: date ?? this.date,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      currencyCode: currencyCode ?? this.currencyCode,
      professionalFee: professionalFee ?? this.professionalFee,
      totalAmount: totalAmount ?? this.totalAmount,
      numberOfInstallments: numberOfInstallments ?? this.numberOfInstallments,
      paymentType: paymentType ?? this.paymentType,
      insuranceAmount: insuranceAmount ?? this.insuranceAmount,
      insuranceReturnable: insuranceReturnable ?? this.insuranceReturnable,
      officeName: officeName ?? this.officeName,
      officeLogoUrl: officeLogoUrl ?? this.officeLogoUrl,
      customNote: customNote ?? this.customNote,
      welcomeMessageMode: welcomeMessageMode ?? this.welcomeMessageMode,
      customWelcomeMessage: customWelcomeMessage ?? this.customWelcomeMessage,
      downpayments: downpayments ?? this.downpayments,
      governmentFees: governmentFees ?? this.governmentFees,
      administrativeFees: administrativeFees ?? this.administrativeFees,
      version: version ?? this.version,
      officeLogoMediaId: officeLogoMediaId ?? this.officeLogoMediaId,
      pdfMediaId: pdfMediaId ?? this.pdfMediaId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
