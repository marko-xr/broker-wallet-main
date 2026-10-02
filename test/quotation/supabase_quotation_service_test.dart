// Tests for the Supabase Quotation adapter: what it sends to the hosted
// `save_quotation` RPC and the tables, and how every backend refusal maps to a
// fixed category. A real SupabaseClient carries a locally set session and a
// recording MockClient answers, the same seam used by the Offer media tests.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_supabase_mapper.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _quotationId = '3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a44';

String _fakeJwt(String uid) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> _sessionJson(String uid) => {
      'access_token': _fakeJwt(uid),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'refresh',
      'user': {
        'id': uid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'quotation-test@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Records every request and answers it with [respond].
class _Backend {
  _Backend(this.respond);

  final http.Response Function(http.Request request) respond;
  final List<http.Request> requests = [];

  /// `MockClient` copies `response.request` onto the response it hands back, and
  /// postgrest's response parser dereferences that unconditionally (on success
  /// and on error), so a response built without it dies in a null-check
  /// `TypeError` before any `PostgrestException` exists. A real HTTP client
  /// always attaches the request, so every answer is re-bound to it here.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final response = respond(request);
    return http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  });

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;
}

Future<sb.SupabaseClient> _signedIn(http.Client httpClient) async {
  final client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: httpClient,
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(jsonEncode(_sessionJson(_uid)));
  return client;
}

QuotationModel _quotation({String title = 'Apartment 306'}) => QuotationModel(
      userId: _uid,
      propertyTitle: title,
      officeName: 'Realtig',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      totalAmount: 1000,
      downpayments: [
        DownpaymentItem(
            method: PaymentMethod.cash,
            number: 1,
            date: DateTime(2026, 10, 1),
            amount: 500),
      ],
      governmentFees: GovernmentFees(total: 20),
      administrativeFees: AdministrativeFees(
          fees: [AdministrativeFeeItem(title: 'Typing', amount: 10)]),
    );

http.Response _saved({int version = 1, String outcome = 'created'}) => _json([
      {
        'quotation_id': _quotationId,
        'resulting_version': version,
        'outcome': outcome,
        'created_at': '2026-10-02T10:00:00+00:00',
        'updated_at': '2026-10-02T10:00:00+00:00',
      }
    ]);

void main() {
  group('save', () {
    test('creates through the save_quotation RPC and nothing else', () async {
      final backend = _Backend((_) => _saved());
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      final result =
          await service.save(_quotation(), quotationId: _quotationId);

      expect(result.quotationId, _quotationId);
      expect(result.version, 1);
      expect(result.outcome, 'created');

      expect(backend.requests, hasLength(1),
          reason: 'one atomic call: no separate parent or child writes');
      final request = backend.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/save_quotation');
      expect(request.headers['Authorization'], startsWith('Bearer '));

      final body = backend.bodyOf(request);
      expect(body.keys.toSet(), {
        'p_quotation_id',
        'p_expected_version',
        'p_header',
        'p_downpayments',
        'p_government_fees',
        'p_administrative_fees',
      });
      expect(body['p_quotation_id'], _quotationId);
      expect(body['p_expected_version'], isNull);
      expect((body['p_header'] as Map).length, 18);
      expect((body['p_downpayments'] as List), hasLength(1));
      expect((body['p_administrative_fees'] as List), hasLength(1));
    });

    test(
        'never writes a table directly, and never sends a server-controlled field',
        () async {
      final backend = _Backend((_) => _saved());
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));
      await service.save(
        _quotation().copyWith(
          version: 9,
          officeLogoMediaId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          pdfMediaId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        ),
        quotationId: _quotationId,
        expectedVersion: 9,
      );

      for (final request in backend.requests) {
        expect(request.url.path.startsWith('/rest/v1/rpc/'), isTrue,
            reason: 'only RPCs: ${request.method} ${request.url.path}');
      }
      final raw = backend.requests.single.body;
      for (final forbidden in const [
        'office_logo_media_id',
        'pdf_media_id',
        'owner_id',
        'created_at',
        'deleted_at',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      ]) {
        expect(raw.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('an update sends the expected version and reports the resulting one',
        () async {
      final backend = _Backend((_) => _saved(version: 8, outcome: 'updated'));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      final result = await service.save(_quotation(),
          quotationId: _quotationId, expectedVersion: 7);

      expect(backend.bodyOf(backend.requests.single)['p_expected_version'], 7);
      expect(result.version, 8);
      expect(result.outcome, 'updated');
    });

    test('a replayed create is a success, not an error', () async {
      final backend = _Backend((_) => _saved(outcome: 'replayed'));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));
      final result =
          await service.save(_quotation(), quotationId: _quotationId);
      expect(result.outcome, 'replayed');
    });

    test(
        'PQT04 (a newer server version) is a version conflict, never overwritten',
        () async {
      final backend = _Backend((_) => _json({
            'code': 'PQT04',
            'message': 'version_conflict',
            'details': null,
            'hint': null,
          }, 400));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      await expectLater(
        service.save(_quotation(),
            quotationId: _quotationId, expectedVersion: 3),
        throwsA(isA<QuotationException>().having(
            (e) => e.failure, 'failure', QuotationFailure.versionConflict)),
      );
      expect(backend.requests, hasLength(1),
          reason: 'no silent retry and no fallback write');
    });

    for (final entry in const {
      'PQT01': QuotationFailure.notSignedIn,
      'PQT02': QuotationFailure.notFound,
      'PQT03': QuotationFailure.deleted,
      'PQT05': QuotationFailure.invalidPayload,
      'PQT06': QuotationFailure.idConflict,
      '42501': QuotationFailure.permissionDenied,
      'XX000': QuotationFailure.unknown,
    }.entries) {
      test('${entry.key} maps to ${entry.value.name}', () async {
        final backend = _Backend((_) => _json({
              'code': entry.key,
              'message': 'raw provider text that must never be shown',
              'details': null,
              'hint': null,
            }, 400));
        final service =
            SupabaseQuotationService(client: await _signedIn(backend.client));

        Object? caught;
        try {
          await service.save(_quotation(), quotationId: _quotationId);
        } catch (error) {
          caught = error;
        }
        expect(caught, isA<QuotationException>());
        expect((caught! as QuotationException).failure, entry.value);
        expect(caught.toString().contains('raw provider text'), isFalse);
      });
    }

    test('a blank title is refused before any request is made', () async {
      final backend = _Backend((_) => _saved());
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      await expectLater(
        service.save(_quotation(title: ' '), quotationId: _quotationId),
        throwsA(isA<QuotationValidationException>()),
      );
      expect(backend.requests, isEmpty);
    });

    test('without a session nothing is sent', () async {
      final backend = _Backend((_) => _saved());
      final client = sb.SupabaseClient(
        'https://unit-test.supabase.co',
        'unit-test-publishable-key',
        httpClient: backend.client,
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      final service = SupabaseQuotationService(client: client);

      await expectLater(
        service.save(_quotation(), quotationId: _quotationId),
        throwsA(isA<QuotationException>()
            .having((e) => e.failure, 'failure', QuotationFailure.notSignedIn)),
      );
      expect(backend.requests, isEmpty);
    });
  });

  group('error translation', () {
    test('connection problems are network, anything else is unknown', () {
      QuotationFailure of(Object e) =>
          SupabaseQuotationService.translate(e).failure;

      expect(of(TimeoutException('t')), QuotationFailure.network);
      expect(of(const SocketException('s')), QuotationFailure.network);
      expect(of(http.ClientException('c')), QuotationFailure.network);
      expect(of(sb.AuthException('a')), QuotationFailure.notSignedIn);
      expect(of(StateError('x')), QuotationFailure.unknown);
      expect(of(const QuotationException(QuotationFailure.deleted)),
          QuotationFailure.deleted);
    });
  });

  group('read', () {
    test('reopen reads the aggregate in one request, excluding deleted rows',
        () async {
      final backend = _Backend((_) => _json([
            {
              'id': _quotationId,
              'owner_id': _uid,
              'property_title': 'Apartment 306',
              'currency_code': 'AED',
              'office_name': 'Realtig',
              'version': 4,
              'office_logo_media_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'pdf_media_id': null,
              'created_at': '2026-10-01T10:00:00+00:00',
              'updated_at': '2026-10-01T10:00:00+00:00',
              'quotation_downpayments': [
                {
                  'sequence_number': 1,
                  'method': 'cash',
                  'due_at': '2026-10-01T00:00:00+00:00',
                  'amount': 500,
                }
              ],
              'quotation_government_fees': {'total': 20},
              'quotation_administrative_fees': [
                {'ordinal': 0, 'title': 'Typing', 'amount': 10}
              ],
            }
          ]));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      final loaded = await service.getQuotation(_quotationId);

      expect(backend.requests, hasLength(1));
      final request = backend.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/quotations');
      expect(request.url.queryParameters['id'], 'eq.$_quotationId');
      expect(request.url.queryParameters['deleted_at'], 'is.null');
      final select = request.url.queryParameters['select']!;
      expect(select, contains('quotation_downpayments'));
      expect(select, contains('quotation_government_fees'));
      expect(select, contains('quotation_administrative_fees'));

      expect(loaded, isNotNull);
      expect(loaded!.version, 4);
      expect(loaded.hasLogo, isTrue);
      expect(loaded.downpayments.single.amount, 500);
      expect(loaded.governmentFees.total, 20);
      expect(loaded.administrativeFees.fees.single.title, 'Typing');
    });

    test('a missing or deleted Quotation reads as null', () async {
      final backend = _Backend((_) => _json(<Object>[]));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));
      expect(await service.getQuotation(_quotationId), isNull);
      expect(await service.getMediaState(_quotationId), isNull);
    });

    test('the list is live rows only, newest first, header columns only',
        () async {
      final backend = _Backend((_) => _json([
            {
              'id': _quotationId,
              'owner_id': _uid,
              'property_title': 'Villa',
              'office_name': 'Realtig',
              'version': 2,
              'pdf_media_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              'created_at': '2026-10-01T10:00:00+00:00',
              'updated_at': '2026-10-01T10:00:00+00:00',
            }
          ]));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      final list = await service.listQuotations();

      final request = backend.requests.single;
      expect(request.url.path, '/rest/v1/quotations');
      expect(request.url.queryParameters['deleted_at'], 'is.null');
      // postgrest appends `.nullslast` to a descending order by default.
      expect(
          request.url.queryParameters['order'], startsWith('created_at.desc'));
      expect(request.url.queryParameters['select'],
          isNot(contains('quotation_downpayments')),
          reason: 'a card does not need the child tables');
      expect(list.single.propertyTitle, 'Villa');
      expect(list.single.hasPdf, isTrue);
    });

    test('media state reads the version and both bound ids', () async {
      final backend = _Backend((_) => _json([
            {
              'version': 6,
              'office_logo_media_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'pdf_media_id': null,
            }
          ]));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));
      final state = await service.getMediaState(_quotationId);

      expect(state!.version, 6);
      expect(state.officeLogoMediaId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(state.pdfMediaId, isNull);
    });
  });

  group('delete', () {
    test('is a soft delete of the live row: one PATCH of deleted_at, no DELETE',
        () async {
      final backend = _Backend((_) => _json([
            {'id': _quotationId}
          ]));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));

      await service.softDelete(_quotationId);

      expect(backend.requests, hasLength(1));
      final request = backend.requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, '/rest/v1/quotations');
      expect(request.url.queryParameters['id'], 'eq.$_quotationId');
      expect(request.url.queryParameters['deleted_at'], 'is.null',
          reason: 'only a live row; an already-deleted one is left alone');
      final body = backend.bodyOf(request);
      expect(body.keys.toSet(), {'deleted_at'},
          reason: 'the only column a client may change');
      expect(DateTime.parse(body['deleted_at'] as String).isUtc, isTrue);
    });

    test('an already-deleted Quotation is a success', () async {
      final backend = _Backend((_) => _json(<Object>[]));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));
      await service.softDelete(_quotationId); // does not throw
      expect(backend.requests.single.method, 'PATCH');
    });

    test('a refusal is a permission failure, not a crash', () async {
      final backend = _Backend((_) => _json({
            'code': '42501',
            'message': 'permission denied',
            'details': null,
            'hint': null,
          }, 403));
      final service =
          SupabaseQuotationService(client: await _signedIn(backend.client));
      await expectLater(
        service.softDelete(_quotationId),
        throwsA(isA<QuotationException>().having(
            (e) => e.failure, 'failure', QuotationFailure.permissionDenied)),
      );
    });
  });
}
