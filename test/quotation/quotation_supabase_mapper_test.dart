// Contract tests for the Quotation <-> hosted `save_quotation` mapping.
//
// The mapping is pure, so these pin the exact payload the Flutter client sends
// and how a hosted row is read back, without any client or network. They cover
// the rules the hosted RPC enforces: a complete 18-key header, server-controlled
// fields never sent, a unique positive downpayment sequence, an explicit-offset
// timestamp, the strict payment enum, and no stored row for an empty section.

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_supabase_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a44';

/// The 18 header keys `public.save_quotation` requires, exactly.
const _headerKeys = <String>{
  'property_title',
  'property_type',
  'parking',
  'subtitle',
  'display_date',
  'start_date_text',
  'end_date_text',
  'currency_code',
  'professional_fee',
  'total_amount',
  'number_of_installments',
  'payment_type',
  'insurance_amount',
  'insurance_returnable',
  'office_name',
  'custom_note',
  'welcome_message_mode',
  'custom_welcome_message',
};

QuotationModel _quotation({
  String title = 'Apartment 306',
  List<DownpaymentItem> downpayments = const [],
  GovernmentFees? government,
  AdministrativeFees? administrative,
  String? paymentType,
  String? currencyCode = 'AED',
  WelcomeMessageMode mode = WelcomeMessageMode.auto,
  String? customWelcome,
}) {
  return QuotationModel(
    userId: 'user-1',
    propertyTitle: title,
    officeName: 'Realtig',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    propertyType: 'Apartment',
    parking: true,
    date: '2026-10-01',
    startDate: '2026-10-01',
    endDate: '2027-09-30',
    currencyCode: currencyCode,
    totalAmount: 120000,
    numberOfInstallments: 4,
    paymentType: paymentType,
    insuranceAmount: 2000,
    insuranceReturnable: true,
    welcomeMessageMode: mode,
    customWelcomeMessage: customWelcome,
    downpayments: downpayments,
    governmentFees: government,
    administrativeFees: administrative,
    // Server-controlled identity that must never be written by a save.
    version: 7,
    officeLogoMediaId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    pdfMediaId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  );
}

void main() {
  group('save payload: header', () {
    test('has exactly the 18 contract keys and never a server-controlled field',
        () {
      final payload = QuotationSupabaseMapper.toSavePayload(
        _quotation(),
        quotationId: _id,
      );

      expect(payload.header.keys.toSet(), _headerKeys);
      for (final forbidden in const [
        'office_logo_media_id',
        'pdf_media_id',
        'owner_id',
        'version',
        'created_at',
        'updated_at',
        'deleted_at',
        'id',
      ]) {
        expect(payload.header.containsKey(forbidden), isFalse,
            reason: '$forbidden is server-controlled');
      }
      expect(payload.toRpcParams().keys.toSet(), {
        'p_quotation_id',
        'p_expected_version',
        'p_header',
        'p_downpayments',
        'p_government_fees',
        'p_administrative_fees',
      });
    });

    test('maps the form fields to their hosted columns', () {
      final h = QuotationSupabaseMapper.toSavePayload(
        _quotation(paymentType: 'bankTransfer'),
        quotationId: _id,
      ).header;

      expect(h['property_title'], 'Apartment 306');
      expect(h['property_type'], 'Apartment');
      expect(h['parking'], true);
      expect(h['display_date'], '2026-10-01');
      expect(h['start_date_text'], '2026-10-01');
      expect(h['end_date_text'], '2027-09-30');
      expect(h['currency_code'], 'AED');
      expect(h['total_amount'], 120000);
      expect(h['number_of_installments'], 4);
      expect(h['payment_type'], 'bank_transfer');
      expect(h['insurance_amount'], 2000);
      expect(h['insurance_returnable'], true);
      expect(h['office_name'], 'Realtig');
      expect(h['welcome_message_mode'], 'auto');
    });

    test('create sends a null expected version; update sends that exact version',
        () {
      final create = QuotationSupabaseMapper.toSavePayload(
        _quotation(),
        quotationId: _id,
      );
      expect(create.expectedVersion, isNull);
      expect(create.toRpcParams()['p_expected_version'], isNull);
      expect(create.toRpcParams().containsKey('p_expected_version'), isTrue);

      final update = QuotationSupabaseMapper.toSavePayload(
        _quotation(),
        quotationId: _id,
        expectedVersion: 7,
      );
      expect(update.toRpcParams()['p_expected_version'], 7);
      expect(update.toRpcParams()['p_quotation_id'], _id);
    });

    test('blank optional text becomes explicit null, never an empty string', () {
      final model = QuotationModel(
        userId: 'u',
        propertyTitle: 'Villa',
        officeName: '',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        propertyType: '   ',
        date: '',
        customNote: '',
      );
      final h = QuotationSupabaseMapper.toSavePayload(model, quotationId: _id)
          .header;

      expect(h['property_type'], isNull);
      expect(h['display_date'], isNull);
      expect(h['custom_note'], isNull);
      expect(h['subtitle'], isNull);
      expect(h['office_name'], '', reason: 'office_name is not nullable');
      expect(h.keys.toSet(), _headerKeys,
          reason: 'null values are still present as explicit keys');
    });

    test('a blank property title is refused before any request', () {
      expect(
        () => QuotationSupabaseMapper.toSavePayload(
          _quotation(title: '   '),
          quotationId: _id,
        ),
        throwsA(isA<QuotationValidationException>().having(
            (e) => e.reason, 'reason', QuotationValidationReason.titleRequired)),
      );
    });

    test('the currency is a trimmed upper-case 3-letter code, AED otherwise',
        () {
      String currency(String? value) => QuotationSupabaseMapper.toSavePayload(
            _quotation(currencyCode: value),
            quotationId: _id,
          ).header['currency_code'] as String;

      expect(currency(' usd '), 'USD');
      expect(currency(null), 'AED');
      expect(currency(''), 'AED');
      expect(currency('DIRHAM'), 'AED');
    });

    test('payment_type maps the form value to the hosted enum, null when unset',
        () {
      String? wire(String? v) => QuotationSupabaseMapper.paymentTypeToWire(v);
      expect(wire('cash'), 'cash');
      expect(wire('cheque'), 'cheque');
      expect(wire('cheques'), 'cheque');
      expect(wire('bankTransfer'), 'bank_transfer');
      expect(wire('bank_transfer'), 'bank_transfer');
      expect(wire('other'), 'other');
      expect(wire(''), isNull);
      expect(wire(null), isNull);
      expect(wire('crypto'), isNull);
    });

    test('a custom welcome message travels with its mode', () {
      final h = QuotationSupabaseMapper.toSavePayload(
        _quotation(mode: WelcomeMessageMode.custom, customWelcome: 'Hello'),
        quotationId: _id,
      ).header;
      expect(h['welcome_message_mode'], 'custom');
      expect(h['custom_welcome_message'], 'Hello');
    });
  });

  group('save payload: children', () {
    test('downpayments are sequenced 1..n in list order with explicit-offset dates',
        () {
      final payload = QuotationSupabaseMapper.toSavePayload(
        _quotation(downpayments: [
          DownpaymentItem(
              method: PaymentMethod.cash,
              number: 9, // ignored: the list order is the sequence
              date: DateTime(2026, 10, 1),
              amount: 30000),
          DownpaymentItem(
              method: PaymentMethod.bankTransfer,
              number: 9,
              date: null,
              amount: 30000.5),
          DownpaymentItem(
              method: PaymentMethod.other,
              number: 0,
              date: DateTime(2027, 2, 28),
              amount: 0),
        ]),
        quotationId: _id,
      );

      final rows = payload.downpayments;
      expect(rows.map((r) => r['sequence_number']), [1, 2, 3]);
      expect(rows.map((r) => r['method']), ['cash', 'bank_transfer', 'other']);
      expect(rows[0]['due_at'], '2026-10-01T00:00:00.000Z');
      expect(rows[1]['due_at'], isNull);
      expect(rows[2]['due_at'], '2027-02-28T00:00:00.000Z');
      expect(rows[1]['amount'], 30000.5);
      for (final row in rows) {
        expect(row.keys.toSet(), {'sequence_number', 'method', 'due_at', 'amount'});
        final dueAt = row['due_at'] as String?;
        if (dueAt != null) {
          expect(
            RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d+)?(Z|[+-]\d{2}:\d{2})$')
                .hasMatch(dueAt),
            isTrue,
            reason: 'the hosted RPC refuses a timestamp without an offset',
          );
        }
      }
    });

    test('a due date is the same calendar date whatever the device time zone',
        () {
      // A local-midnight DateTime must not shift to the previous day when it
      // is anchored: only its year/month/day are used.
      final local = DateTime(2026, 3, 1, 0, 0);
      final payload = QuotationSupabaseMapper.toSavePayload(
        _quotation(downpayments: [
          DownpaymentItem(
              method: PaymentMethod.cash, number: 1, date: local, amount: 1),
        ]),
        quotationId: _id,
      );
      expect(payload.downpayments.single['due_at'], '2026-03-01T00:00:00.000Z');
    });

    test('an empty government section is not sent; a filled one has all 5 keys',
        () {
      expect(
        QuotationSupabaseMapper.toSavePayload(
          _quotation(),
          quotationId: _id,
        ).governmentFees,
        isNull,
      );

      final gov = QuotationSupabaseMapper.toSavePayload(
        _quotation(
          government: GovernmentFees(
            percentOfTotalRent: 2,
            municipality: 100,
            total: 2500,
          ),
        ),
        quotationId: _id,
      ).governmentFees!;
      expect(gov.keys.toSet(), {
        'percent_of_total_rent',
        'municipality',
        'electricity',
        'sewerage',
        'total',
      });
      expect(gov['percent_of_total_rent'], 2);
      expect(gov['electricity'], isNull);
      expect(gov['total'], 2500);
    });

    test('administrative fees get 0-based ordinals; untouched empty rows are skipped',
        () {
      final payload = QuotationSupabaseMapper.toSavePayload(
        _quotation(
          administrative: AdministrativeFees(fees: [
            AdministrativeFeeItem(title: 'Commission', amount: 5000),
            AdministrativeFeeItem(title: '  ', amount: 0), // left empty
            AdministrativeFeeItem(title: 'Typing', amount: 150.25),
          ]),
        ),
        quotationId: _id,
      );
      expect(payload.administrativeFees, [
        {'ordinal': 0, 'title': 'Commission', 'amount': 5000},
        {'ordinal': 1, 'title': 'Typing', 'amount': 150.25},
      ]);
    });

    test('an administrative fee with an amount but no title is refused', () {
      expect(
        () => QuotationSupabaseMapper.toSavePayload(
          _quotation(
            administrative: AdministrativeFees(
                fees: [AdministrativeFeeItem(title: '', amount: 10)]),
          ),
          quotationId: _id,
        ),
        throwsA(isA<QuotationValidationException>().having((e) => e.reason,
            'reason', QuotationValidationReason.administrativeFeeTitleRequired)),
      );
    });

    test('children are plain data: no media id or owner anywhere in the payload',
        () {
      final params = QuotationSupabaseMapper.toSavePayload(
        _quotation(
          downpayments: [
            DownpaymentItem(
                method: PaymentMethod.cash, number: 1, amount: 1, date: null),
          ],
          government: GovernmentFees(total: 1),
          administrative: AdministrativeFees(
              fees: [AdministrativeFeeItem(title: 'x', amount: 1)]),
        ),
        quotationId: _id,
        expectedVersion: 3,
      ).toRpcParams().toString();

      expect(params.contains('media'), isFalse);
      expect(params.contains('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), isFalse);
      expect(params.contains('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), isFalse);
      expect(params.contains('owner'), isFalse);
      expect(params.contains('user-1'), isFalse);
    });
  });

  group('read mapping', () {
    Map<String, dynamic> row({
      Object? downpayments,
      Object? government,
      Object? fees,
    }) =>
        {
          'id': _id,
          'owner_id': 'user-1',
          'property_title': 'Apartment 306',
          'property_type': 'Apartment',
          'parking': true,
          'subtitle': null,
          'display_date': '2026-10-01',
          'start_date_text': '2026-10-01',
          'end_date_text': '2027-09-30',
          'currency_code': 'AED',
          'professional_fee': null,
          'total_amount': 120000,
          'number_of_installments': 4,
          'payment_type': 'bank_transfer',
          'insurance_amount': 2000.5,
          'insurance_returnable': true,
          'office_name': 'Realtig',
          'custom_note': null,
          'welcome_message_mode': 'custom',
          'custom_welcome_message': 'Hello',
          'office_logo_media_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'pdf_media_id': null,
          'version': 5,
          'created_at': '2026-10-01T10:00:00+00:00',
          'updated_at': '2026-10-02T11:30:00+00:00',
          'deleted_at': null,
          'quotation_downpayments': downpayments ?? <Object>[],
          'quotation_government_fees': government,
          'quotation_administrative_fees': fees ?? <Object>[],
        };

    test('the aggregate round-trips: what was sent is what is read back', () {
      final original = _quotation(
        paymentType: 'bankTransfer',
        mode: WelcomeMessageMode.custom,
        customWelcome: 'Hello',
        downpayments: [
          DownpaymentItem(
              method: PaymentMethod.cash,
              number: 1,
              date: DateTime(2026, 10, 1),
              amount: 30000),
          DownpaymentItem(
              method: PaymentMethod.bankTransfer,
              number: 2,
              date: DateTime(2027, 1, 1),
              amount: 30000),
        ],
        government: GovernmentFees(percentOfTotalRent: 2, total: 2400),
        administrative: AdministrativeFees(fees: [
          AdministrativeFeeItem(title: 'Commission', amount: 5000),
          AdministrativeFeeItem(title: 'Typing', amount: 150),
        ]),
      );
      final sent = QuotationSupabaseMapper.toSavePayload(original,
          quotationId: _id);

      // Echo exactly what was sent as the hosted rows, in a scrambled order.
      final hosted = row(
        downpayments: sent.downpayments.reversed.toList(),
        government: sent.governmentFees,
        fees: sent.administrativeFees.reversed.toList(),
      );
      final read = QuotationSupabaseMapper.aggregateFromRow(hosted);

      expect(read.id, _id);
      expect(read.propertyTitle, original.propertyTitle);
      expect(read.paymentType, 'bankTransfer');
      expect(read.welcomeMessageMode, WelcomeMessageMode.custom);
      expect(read.customWelcomeMessage, 'Hello');
      expect(read.totalAmount, 120000);
      expect(read.insuranceAmount, 2000.5);
      expect(read.parking, true);
      expect(read.downpayments.map((d) => d.number), [1, 2],
          reason: 'ordered by sequence, not by arrival');
      expect(read.downpayments.map((d) => d.method),
          [PaymentMethod.cash, PaymentMethod.bankTransfer]);
      expect(read.downpayments.first.date, DateTime(2026, 10, 1));
      expect(read.governmentFees.percentOfTotalRent, 2);
      expect(read.governmentFees.total, 2400);
      expect(read.administrativeFees.fees.map((f) => f.title),
          ['Commission', 'Typing'],
          reason: 'ordered by ordinal');
      expect(read.administrativeFees.total, 5150,
          reason: 'the hosted contract stores rows only; the total is their sum');
    });

    test('server identity is carried as version and media ids only', () {
      final read = QuotationSupabaseMapper.aggregateFromRow(row());
      expect(read.version, 5);
      expect(read.officeLogoMediaId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(read.hasLogo, isTrue);
      expect(read.pdfMediaId, isNull);
      expect(read.hasPdf, isFalse);
      expect(read.userId, 'user-1');
      expect(read.createdAt.toUtc(), DateTime.utc(2026, 10, 1, 10));
    });

    test('a due date is read back as the stored calendar date in any zone', () {
      final read = QuotationSupabaseMapper.aggregateFromRow(row(downpayments: [
        {
          'sequence_number': 1,
          'method': 'cash',
          'due_at': '2026-03-01T00:00:00+00:00',
          'amount': 10,
        },
        {
          'sequence_number': 2,
          'method': 'cheque',
          'due_at': null,
          'amount': 10,
        },
      ]));
      expect(read.downpayments[0].date, DateTime(2026, 3, 1));
      expect(read.downpayments[1].date, isNull);
    });

    test('a one-to-one government relation may arrive as an object, a list or null',
        () {
      final asObject = QuotationSupabaseMapper.aggregateFromRow(
          row(government: {'percent_of_total_rent': 2, 'total': 10}));
      final asList = QuotationSupabaseMapper.aggregateFromRow(row(government: [
        {'percent_of_total_rent': 2, 'total': 10}
      ]));
      final none = QuotationSupabaseMapper.aggregateFromRow(row());

      expect(asObject.governmentFees.percentOfTotalRent, 2);
      expect(asList.governmentFees.total, 10);
      expect(none.governmentFees.isEmpty, isTrue);
    });

    test('numeric columns may arrive as numbers or strings', () {
      final read = QuotationSupabaseMapper.aggregateFromRow(row(downpayments: [
        {'sequence_number': '1', 'method': 'cash', 'due_at': null, 'amount': '12.5'}
      ]));
      expect(read.downpayments.single.amount, 12.5);
      expect(read.downpayments.single.number, 1);
    });

    test('a list row carries only what a card needs, with hasPdf from the id', () {
      final card = QuotationSupabaseMapper.headerFromRow({
        'id': _id,
        'owner_id': 'user-1',
        'property_title': 'Villa',
        'property_type': null,
        'display_date': null,
        'total_amount': 99,
        'number_of_installments': null,
        'office_name': 'Realtig',
        'currency_code': 'AED',
        'office_logo_media_id': null,
        'pdf_media_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'version': 2,
        'created_at': '2026-10-01T10:00:00+00:00',
        'updated_at': '2026-10-01T10:00:00+00:00',
      });
      expect(card.propertyTitle, 'Villa');
      expect(card.hasPdf, isTrue);
      expect(card.hasLogo, isFalse);
      expect(card.version, 2);
    });
  });
}
