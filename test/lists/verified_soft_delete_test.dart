// P3.1a: a soft delete counts as done only when the server says a row was
// changed (or that this account's row was already deleted) — never because
// the HTTP call succeeded. PostgREST answers a PATCH that changed no row
// with success, for another account's row, a missing id or a superseded
// session alike (P3.0, §7Z, executed on a local PostgreSQL).
//
// A recording PostgREST stand-in answers each request the way the real one
// does for the case under test.
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

String _fakeJwt() {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

/// What the server holds for the row the test deletes.
enum _Row {
  /// This account's live row: the update changes it.
  live,

  /// This account's row, deleted before: the update changes nothing, the
  /// follow-up read finds it deleted.
  alreadyDeleted,

  /// No row this session may see: missing, another account's, or a
  /// superseded session. The update changes nothing, the read finds nothing.
  invisible,
}

class _Backend {
  _Row row = _Row.live;

  /// When set, the update fails with this HTTP status instead.
  int? updateStatus;

  /// When set, the update fails at the transport.
  Object? updateThrows;

  final List<http.Request> requests = [];

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      if (!request.url.path.startsWith('/rest/v1/')) {
        return http.Response('{}', 200, request: request);
      }
      requests.add(request);
      final q = request.url.queryParameters;
      final json = {'content-type': 'application/json'};
      if (request.method == 'PATCH') {
        if (updateThrows != null) throw updateThrows!;
        if (updateStatus != null) {
          return http.Response(
              jsonEncode({'code': '42501', 'message': 'permission denied'}),
              updateStatus!,
              headers: json,
              request: request);
        }
        final changes = row == _Row.live && q['deleted_at'] == 'is.null' ||
            row == _Row.alreadyDeleted && q['deleted_at'] != 'is.null' ||
            row == _Row.live && q['deleted_at'] == null;
        final returning =
            (request.headers['Prefer'] ?? '').contains('return=representation');
        if (changes && row == _Row.live) row = _Row.alreadyDeleted;
        if (!returning) return http.Response('', 204, request: request);
        return http.Response(
            jsonEncode(changes
                ? [
                    {'id': _id}
                  ]
                : []),
            200,
            headers: json,
            request: request);
      }
      if (request.method == 'GET') {
        final wantsDeleted = q['deleted_at'] == 'not.is.null';
        final found = row == _Row.alreadyDeleted && wantsDeleted;
        return http.Response(
            jsonEncode(found
                ? [
                    {'id': _id}
                  ]
                : []),
            200,
            headers: json,
            request: request);
      }
      return http.Response('[]', 200, headers: json, request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<void> signIn() => client.auth.setInitialSession(jsonEncode({
        'access_token': _fakeJwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'refresh_token': 'refresh',
        'user': {
          'id': _uid,
          'aud': 'authenticated',
          'email': 'delete@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));

  Iterable<http.Request> get patches =>
      requests.where((r) => r.method == 'PATCH');
}

void main() {
  late _Backend backend;
  late SupabaseCoreEntitiesService service;
  late int notified;
  late int sessionChecks;

  setUp(() async {
    backend = _Backend();
    await backend.signIn();
    service = SupabaseCoreEntitiesService(
      client: backend.client,
      offerMedia: R2OfferMediaUploadService(
        supabaseClient: backend.client,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
    notified = 0;
    final changes = CoreEntityMutationNotifier.changes.listen((_) {
      notified++;
    });
    addTearDown(changes.cancel);
    sessionChecks = 0;
    ListSessionCheck.debugOverride = (_) {
      sessionChecks++;
      return Future<bool>.value(true);
    };
    addTearDown(() => ListSessionCheck.debugOverride = null);
  });

  final deletes = <String, Future<void> Function(SupabaseCoreEntitiesService)>{
    'requests': (s) => s.deleteRequest(_id),
    'offers': (s) => s.deleteOffer(_id),
    'owners': (s) => s.deleteOwner(_id),
    'offices': (s) => s.deleteOffice(_id),
    'brokers': (s) => s.deleteBroker(_id),
    'watchmen': (s) => s.deleteWatchman(_id),
  };

  for (final delete in deletes.entries) {
    final table = delete.key;
    group(table, () {
      test(
          'a live row: one PATCH of deleted_at, only while not deleted, '
          'returning the changed id; verified and notified', () async {
        await delete.value(service);
        final r = backend.requests.single;
        expect(r.method, 'PATCH');
        expect(r.url.pathSegments.last, table);
        expect(r.url.queryParameters, {
          'id': 'eq.$_id',
          'deleted_at': 'is.null',
          'select': 'id',
        });
        expect(r.headers['Prefer'], contains('return=representation'));
        expect((json.decode(r.body) as Map).keys, ['deleted_at']);
        await pumpEventQueue();
        expect(notified, 1);
        expect(sessionChecks, 0);
      });

      test(
          'already deleted by this account: no second change (deleted_at and '
          'version kept), confirmed by one read, and treated as done',
          () async {
        backend.row = _Row.alreadyDeleted;
        await delete.value(service);
        expect(backend.patches, hasLength(1));
        final read = backend.requests.last;
        expect(read.method, 'GET');
        expect(read.url.queryParameters, {
          'id': 'eq.$_id',
          'deleted_at': 'not.is.null',
          'select': 'id',
        });
        await pumpEventQueue();
        expect(notified, 1);
      });

      test(
          'no row this session may change (missing, another account\'s, or a '
          'superseded session): not deleted, nothing notified, the session '
          'is checked, and the error says nothing about the row', () async {
        backend.row = _Row.invisible;
        Object? error;
        try {
          await delete.value(service);
        } catch (e) {
          error = e;
        }
        expect(error, isA<CoreEntityNotDeleted>());
        expect(error.toString(), isNot(contains(_id)));
        expect(error.toString(), isNot(contains(table)));
        expect(backend.requests.map((r) => r.method), ['PATCH', 'GET']);
        await pumpEventQueue();
        expect(notified, 0);
        expect(sessionChecks, 1);
      });

      test('an authorization failure is passed on unchanged; nothing notified',
          () async {
        backend.updateStatus = 401;
        await expectLater(
            delete.value(service), throwsA(isA<sb.PostgrestException>()));
        expect(backend.requests, hasLength(1));
        await pumpEventQueue();
        expect(notified, 0);
      });

      test('a network failure is passed on unchanged; nothing notified',
          () async {
        backend.updateThrows = const SocketException('offline');
        await expectLater(delete.value(service), throwsA(anything));
        await pumpEventQueue();
        expect(notified, 0);
        expect(sessionChecks, 0);
      });
    });
  }

  test(
      'two deletes of the same row: the first changes it, the second finds '
      'it already deleted; it is changed once', () async {
    await service.deleteBroker(_id);
    await service.deleteBroker(_id);
    final patches = backend.patches.toList();
    expect(patches, hasLength(2));
    expect(
        patches.every((p) => p.url.queryParameters['deleted_at'] == 'is.null'),
        isTrue,
        reason: 'neither may re-stamp a deleted row');
    expect(backend.requests.last.method, 'GET');
    await pumpEventQueue();
    expect(notified, 2);
  });
}
