// Pure mapping between the Quotation form model and the hosted Supabase
// aggregate. No client, no I/O: everything here is deterministic so the
// `save_quotation` contract can be tested without a network.
//
// Contract (supabase/migrations/20260930204217_quotation_save_rpc.sql):
//   public.save_quotation(p_quotation_id, p_expected_version, p_header,
//     p_downpayments, p_government_fees, p_administrative_fees)
// The header is a complete replacement with exactly 18 keys. Media ids,
// owner, version and timestamps are server-controlled and are never sent.

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';

/// Why a form cannot become a valid aggregate, detected before any request.
enum QuotationValidationReason {
  /// The property title is blank; the hosted schema requires one.
  titleRequired,

  /// An administrative fee has an amount but no title.
  administrativeFeeTitleRequired,
}

/// A form state that can never be saved. Carries only a fixed reason, never
/// user content.
class QuotationValidationException implements Exception {
  const QuotationValidationException(this.reason);

  final QuotationValidationReason reason;

  @override
  String toString() => 'QuotationValidationException(${reason.name})';
}

/// The six `save_quotation` arguments.
class QuotationSavePayload {
  const QuotationSavePayload({
    required this.quotationId,
    required this.expectedVersion,
    required this.header,
    required this.downpayments,
    required this.governmentFees,
    required this.administrativeFees,
  });

  final String quotationId;

  /// Null creates (or idempotently replays a create); a number is an
  /// optimistic update against exactly that server version.
  final int? expectedVersion;
  final Map<String, dynamic> header;
  final List<Map<String, dynamic>> downpayments;

  /// Null when the section is empty: no row is stored.
  final Map<String, dynamic>? governmentFees;
  final List<Map<String, dynamic>> administrativeFees;

  /// Named arguments for `SupabaseClient.rpc('save_quotation', params: …)`.
  Map<String, dynamic> toRpcParams() => <String, dynamic>{
        'p_quotation_id': quotationId,
        'p_expected_version': expectedVersion,
        'p_header': header,
        'p_downpayments': downpayments,
        'p_government_fees': governmentFees,
        'p_administrative_fees': administrativeFees,
      };
}

abstract final class QuotationSupabaseMapper {
  /// The list read: header columns only, enough for a card.
  static const String listColumns = 'id,owner_id,property_title,property_type,'
      'display_date,total_amount,number_of_installments,office_name,'
      'currency_code,office_logo_media_id,pdf_media_id,version,created_at,'
      'updated_at';

  /// The reopen read: the whole aggregate in one request.
  static const String aggregateColumns = '*,'
      'quotation_downpayments(sequence_number,method,due_at,amount),'
      'quotation_government_fees(percent_of_total_rent,municipality,'
      'electricity,sewerage,total),'
      'quotation_administrative_fees(ordinal,title,amount)';

  // ---------------------------------------------------------------------
  // Write side
  // ---------------------------------------------------------------------

  /// Throws [QuotationValidationException] for a form the hosted schema would
  /// refuse for a reason the user can fix. [toSavePayload] applies it first;
  /// callers use it to refuse a form before starting any other work.
  static void validate(QuotationModel quotation) {
    if (quotation.propertyTitle.trim().isEmpty) {
      throw const QuotationValidationException(
          QuotationValidationReason.titleRequired);
    }
    for (final fee in quotation.administrativeFees.fees) {
      if (fee.title.trim().isEmpty && fee.amount != 0) {
        throw const QuotationValidationException(
            QuotationValidationReason.administrativeFeeTitleRequired);
      }
    }
  }

  /// Builds the `save_quotation` arguments from [quotation].
  ///
  /// Throws [QuotationValidationException] as [validate] does.
  static QuotationSavePayload toSavePayload(
    QuotationModel quotation, {
    required String quotationId,
    int? expectedVersion,
  }) {
    validate(quotation);

    final header = <String, dynamic>{
      'property_title': quotation.propertyTitle,
      'property_type': _blankToNull(quotation.propertyType),
      'parking': quotation.parking,
      'subtitle': _blankToNull(quotation.subtitle),
      'display_date': _blankToNull(quotation.date),
      'start_date_text': _blankToNull(quotation.startDate),
      'end_date_text': _blankToNull(quotation.endDate),
      'currency_code': _currency(quotation.currencyCode),
      'professional_fee': quotation.professionalFee,
      'total_amount': quotation.totalAmount,
      'number_of_installments': quotation.numberOfInstallments,
      'payment_type': paymentTypeToWire(quotation.paymentType),
      'insurance_amount': quotation.insuranceAmount,
      'insurance_returnable': quotation.insuranceReturnable,
      'office_name': quotation.officeName,
      'custom_note': _blankToNull(quotation.customNote),
      'welcome_message_mode': quotation.welcomeMessageMode.asString,
      'custom_welcome_message': _blankToNull(quotation.customWelcomeMessage),
    };

    // The form renumbers its rows 1..n; the hosted schema needs a unique
    // positive sequence, so the list order is the sequence.
    final downpayments = <Map<String, dynamic>>[
      for (var i = 0; i < quotation.downpayments.length; i++)
        <String, dynamic>{
          'sequence_number': i + 1,
          'method': methodToWire(quotation.downpayments[i].method),
          'due_at': _dateOnlyToWire(quotation.downpayments[i].date),
          'amount': quotation.downpayments[i].amount,
        },
    ];

    final gov = quotation.governmentFees;
    final governmentFees = gov.isEmpty
        ? null
        : <String, dynamic>{
            'percent_of_total_rent': gov.percentOfTotalRent,
            'municipality': gov.municipality,
            'electricity': gov.electricity,
            'sewerage': gov.sewerage,
            'total': gov.total,
          };

    final administrativeFees = <Map<String, dynamic>>[];
    for (final fee in quotation.administrativeFees.fees) {
      // A blank title here is a row the user left empty: [validate] refused
      // one that has an amount.
      if (fee.title.trim().isEmpty) continue;
      administrativeFees.add(<String, dynamic>{
        'ordinal': administrativeFees.length,
        'title': fee.title,
        'amount': fee.amount,
      });
    }

    return QuotationSavePayload(
      quotationId: quotationId,
      expectedVersion: expectedVersion,
      header: header,
      downpayments: downpayments,
      governmentFees: governmentFees,
      administrativeFees: administrativeFees,
    );
  }

  /// The hosted `payment_type` for the form's value, or null when unset.
  static String? paymentTypeToWire(String? value) {
    switch (value?.trim()) {
      case 'cash':
        return 'cash';
      case 'cheque':
      case 'cheques':
        return 'cheque';
      case 'bankTransfer':
      case 'bank_transfer':
        return 'bank_transfer';
      case 'other':
        return 'other';
      default:
        return null;
    }
  }

  /// The form's `paymentType` for a hosted value ('' when unset).
  static String paymentTypeFromWire(String? value) {
    switch (value) {
      case 'cash':
        return 'cash';
      case 'cheque':
        return 'cheque';
      case 'bank_transfer':
        return 'bankTransfer';
      case 'other':
        return 'other';
      default:
        return '';
    }
  }

  static String methodToWire(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.cheque:
        return 'cheque';
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      case PaymentMethod.other:
        return 'other';
    }
  }

  static PaymentMethod methodFromWire(String? value) {
    switch (value) {
      case 'cash':
        return PaymentMethod.cash;
      case 'cheque':
        return PaymentMethod.cheque;
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      default:
        return PaymentMethod.other;
    }
  }

  // ---------------------------------------------------------------------
  // Read side
  // ---------------------------------------------------------------------

  /// A list card from a [listColumns] row.
  static QuotationModel headerFromRow(Map<String, dynamic> row) {
    return QuotationModel(
      id: _string(row['id']),
      userId: _string(row['owner_id']) ?? '',
      propertyTitle: _string(row['property_title']) ?? '',
      propertyType: _string(row['property_type']),
      date: _string(row['display_date']),
      totalAmount: _double(row['total_amount']),
      numberOfInstallments: _int(row['number_of_installments']),
      officeName: _string(row['office_name']) ?? '',
      currencyCode: _string(row['currency_code']),
      officeLogoMediaId: _string(row['office_logo_media_id']),
      pdfMediaId: _string(row['pdf_media_id']),
      version: _int(row['version']),
      createdAt: _timestamp(row['created_at']),
      updatedAt: _timestamp(row['updated_at']),
    );
  }

  /// The whole Quotation from an [aggregateColumns] row.
  static QuotationModel aggregateFromRow(Map<String, dynamic> row) {
    final downpayments = _rows(row['quotation_downpayments'])
      ..sort((a, b) => (_int(a['sequence_number']) ?? 0)
          .compareTo(_int(b['sequence_number']) ?? 0));
    final feeRows = _rows(row['quotation_administrative_fees'])
      ..sort((a, b) =>
          (_int(a['ordinal']) ?? 0).compareTo(_int(b['ordinal']) ?? 0));
    final govRows = _rows(row['quotation_government_fees']);
    final gov = govRows.isEmpty ? null : govRows.first;

    final fees = feeRows
        .map((r) => AdministrativeFeeItem(
              title: _string(r['title']) ?? '',
              amount: _double(r['amount']) ?? 0,
            ))
        .toList(growable: false);

    return headerFromRow(row).copyWith(
      propertyType: _string(row['property_type']),
      parking: row['parking'] as bool?,
      subtitle: _string(row['subtitle']),
      startDate: _string(row['start_date_text']),
      endDate: _string(row['end_date_text']),
      professionalFee: _double(row['professional_fee']),
      paymentType: paymentTypeFromWire(_string(row['payment_type'])),
      insuranceAmount: _double(row['insurance_amount']),
      insuranceReturnable: row['insurance_returnable'] as bool?,
      customNote: _string(row['custom_note']),
      welcomeMessageMode:
          WelcomeMessageModeX.fromString(_string(row['welcome_message_mode'])),
      customWelcomeMessage: _string(row['custom_welcome_message']),
      downpayments: downpayments
          .map((r) => DownpaymentItem(
                method: methodFromWire(_string(r['method'])),
                number: _int(r['sequence_number']) ?? 0,
                date: _dateOnlyFromWire(r['due_at']),
                amount: _double(r['amount']) ?? 0,
              ))
          .toList(growable: false),
      governmentFees: gov == null
          ? GovernmentFees()
          : GovernmentFees(
              percentOfTotalRent: _double(gov['percent_of_total_rent']),
              municipality: _double(gov['municipality']),
              electricity: _double(gov['electricity']),
              sewerage: _double(gov['sewerage']),
              total: _double(gov['total']),
            ),
      administrativeFees: AdministrativeFees(
        fees: fees,
        total: fees.isEmpty
            ? null
            : fees.fold<double>(0, (sum, fee) => sum + fee.amount),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  static String? _blankToNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// A 3-letter upper-case code, 'AED' when the form has none.
  static String _currency(String? value) {
    final code = value?.trim().toUpperCase() ?? '';
    return code.length == 3 ? code : 'AED';
  }

  /// A calendar date as UTC midnight with an explicit offset. The hosted
  /// column is a timestamptz and refuses offset-less values; anchoring the
  /// date at UTC midnight keeps it the same date on every device.
  static String? _dateOnlyToWire(DateTime? date) {
    if (date == null) return null;
    return DateTime.utc(date.year, date.month, date.day).toIso8601String();
  }

  /// The calendar date stored by [_dateOnlyToWire].
  static DateTime? _dateOnlyFromWire(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    final utc = parsed.toUtc();
    return DateTime(utc.year, utc.month, utc.day);
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static double? _double(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _int(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime _timestamp(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();

  /// An embedded relation arrives as a list, or as one object for a
  /// one-to-one relation, or as null; this normalizes all three to a list.
  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    if (value is Map) return [Map<String, dynamic>.from(value)];
    return <Map<String, dynamic>>[];
  }
}
