// lib/src/data/models/ScreensModel/quotation_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Map<String, dynamic> toMap() => {
        'method': method.asString,
        'number': number,
        'date': date == null ? null : Timestamp.fromDate(date!),
        'amount': amount,
      };

  factory DownpaymentItem.fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return DownpaymentItem(
        method: PaymentMethod.other,
        number: 0,
        amount: 0,
        date: null,
      );
    }
    return DownpaymentItem(
      method: PaymentMethodX.fromString(data['method'] as String?),
      number: _toInt(data['number']),
      date: _toDate(data['date']),
      amount: _toDouble(data['amount']),
    );
  }
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

  Map<String, dynamic> toMap() => {
        'percentOfTotalRent': percentOfTotalRent,
        'municipality': municipality,
        'electricity': electricity,
        'sewerage': sewerage,
        'total': total,
      };

  factory GovernmentFees.fromMap(Map<String, dynamic>? data) {
    if (data == null) return GovernmentFees();
    return GovernmentFees(
      percentOfTotalRent: _toNullableDouble(data['percentOfTotalRent']),
      municipality: _toNullableDouble(data['municipality']),
      electricity: _toNullableDouble(data['electricity']),
      sewerage: _toNullableDouble(data['sewerage']),
      total: _toNullableDouble(data['total']),
    );
  }

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

  Map<String, dynamic> toMap() => {
        'title': title,
        'amount': amount,
      };

  factory AdministrativeFeeItem.fromMap(Map<String, dynamic> data) {
    return AdministrativeFeeItem(
      title: data['title'] ?? '',
      amount: _toNullableDouble(data['amount']) ?? 0.0,
    );
  }
}

/// Administrative fees section with dynamic fee items.
class AdministrativeFees {
  final List<AdministrativeFeeItem> fees;
  final double? total; // optional, may be computed on the fly

  AdministrativeFees({
    this.fees = const [],
    this.total,
  });

  Map<String, dynamic> toMap() => {
        'fees': fees.map((fee) => fee.toMap()).toList(),
        'total': total,
      };

  factory AdministrativeFees.fromMap(Map<String, dynamic>? data) {
    if (data == null) return AdministrativeFees();

    List<AdministrativeFeeItem> feesList = [];
    if (data['fees'] != null) {
      final feesData = data['fees'] as List;
      feesList =
          feesData.map((item) => AdministrativeFeeItem.fromMap(item)).toList();
    }
    // Support legacy format for backward compatibility
    else if (data['commission'] != null || data['typing'] != null) {
      if (data['commission'] != null) {
        feesList.add(AdministrativeFeeItem(
          title: 'Commission',
          amount: _toNullableDouble(data['commission']) ?? 0.0,
        ));
      }
      if (data['typing'] != null) {
        feesList.add(AdministrativeFeeItem(
          title: 'Typing',
          amount: _toNullableDouble(data['typing']) ?? 0.0,
        ));
      }
    }

    return AdministrativeFees(
      fees: feesList,
      total: _toNullableDouble(data['total']),
    );
  }

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
      paymentType; // "Cheques or Cash" (store literal: 'cheques' or 'cash')
  final double? insuranceAmount; // e.g., 2000
  final bool? insuranceReturnable; // "returnable"

  // Office
  final String officeName;
  final String? officeLogoUrl;

  // Notes
  final String? customNote; // extra note line if needed

  // Welcome message configuration
  final WelcomeMessageMode welcomeMessageMode; // auto, custom, or hidden
  final String? customWelcomeMessage; // used when mode is 'custom'

  // Tables / sections
  final List<DownpaymentItem> downpayments;
  final GovernmentFees governmentFees;
  final AdministrativeFees administrativeFees;

  // Storage
  final String? pdfUrl;
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
    this.pdfUrl,
  })  : governmentFees = governmentFees ?? GovernmentFees(),
        administrativeFees = administrativeFees ?? AdministrativeFees();

  /// Firestore serialization
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'propertyTitle': propertyTitle,
      'propertyType': propertyType,
      'parking': parking,
      'subtitle': subtitle,
      'date': date,
      'startDate': startDate,
      'endDate': endDate,
      'currencyCode': currencyCode,
      'professionalFee': professionalFee,
      'totalAmount': totalAmount,
      'numberOfInstallments': numberOfInstallments,
      'paymentType': paymentType,
      'insuranceAmount': insuranceAmount,
      'insuranceReturnable': insuranceReturnable,
      'officeName': officeName,
      'officeLogoUrl': officeLogoUrl,
      'customNote': customNote,
      'welcomeMessageMode': welcomeMessageMode.asString,
      'customWelcomeMessage': customWelcomeMessage,
      'downpayments': downpayments.map((e) => e.toMap()).toList(),
      'governmentFees': governmentFees.toMap(),
      'administrativeFees': administrativeFees.toMap(),
      'pdfUrl': pdfUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Firestore deserialization
  factory QuotationModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    final List<dynamic> dpRaw = (data['downpayments'] as List?) ?? const [];
    final Map<String, dynamic>? govRaw =
        data['governmentFees'] as Map<String, dynamic>?;
    final Map<String, dynamic>? admRaw =
        data['administrativeFees'] as Map<String, dynamic>?;

    return QuotationModel(
      id: doc.id,
      userId: (data['userId'] ?? '') as String,
      propertyTitle: (data['propertyTitle'] ?? '') as String,
      propertyType: data['propertyType'] as String?,
      parking: data['parking'] as bool?,
      subtitle: data['subtitle'] as String?,
      date: data['date'] as String?,
      startDate: data['startDate'] as String?,
      endDate: data['endDate'] as String?,
      currencyCode: data['currencyCode'] as String?,
      professionalFee: _toNullableDouble(data['professionalFee']),
      totalAmount: _toNullableDouble(data['totalAmount']),
      numberOfInstallments: _toNullableInt(data['numberOfInstallments']),
      paymentType: data['paymentType'] as String?,
      insuranceAmount: _toNullableDouble(data['insuranceAmount']),
      insuranceReturnable: data['insuranceReturnable'] as bool?,
      officeName: (data['officeName'] ?? '') as String,
      officeLogoUrl: data['officeLogoUrl'] as String?,
      customNote: data['customNote'] as String?,
      welcomeMessageMode:
          WelcomeMessageModeX.fromString(data['welcomeMessageMode'] as String?),
      customWelcomeMessage: data['customWelcomeMessage'] as String?,
      downpayments: dpRaw
          .map((e) => DownpaymentItem.fromMap(e as Map<String, dynamic>?))
          .toList(),
      governmentFees: GovernmentFees.fromMap(govRaw),
      administrativeFees: AdministrativeFees.fromMap(admRaw),
      pdfUrl: data['pdfUrl'] as String?,
      createdAt: _toDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(data['updatedAt']) ?? DateTime.now(),
    );
  }

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
    String? pdfUrl,
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
      pdfUrl: pdfUrl ?? this.pdfUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// -------- Helpers --------

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

double? _toNullableDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

int? _toNullableInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) {
    // Allow free-form strings; parsing best-effort.
    return DateTime.tryParse(v);
  }
  return null;
}
