// P3.0: the requests the shared core-entity service sends today, recorded as
// they are (characterization, not a fix). Each finding behind them is in the
// performance tracker, section 7Z.
//
// - A soft delete was a PATCH by id with no row confirmation, and a 204 that
//   changed no row counted as success. Since P3.1a (§7AB) it asks for the
//   changed id and fails when no row was changed; the delete test below now
//   pins that contract (verified_soft_delete_test covers every case).
// - The six list reads asked for every row (no limit, no range, no count), so
//   a server row cap could shorten a list silently, and an empty answer looks
//   the same whatever its cause. Since P4.1 (§7AJ) Requests are read in
//   pages that must add up to an exact count; the other five are unchanged.
// - Home counts sent seven GET requests that also returned the id rows;
//   since P3.3 (§7AG) they are seven count-only HEAD requests with the same
//   filter, pinned by the Home counts test below.
import 'dart:convert';

import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/services/supabase_home_counts_service.dart';
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

/// A signed-in client that records every request. Reads answer `[]`, as
/// PostgREST does for an account with no rows and equally for a session the
/// database's session gate filters out; writes answer success with no
/// changed row, as PostgREST does when the update matched nothing.
class _Backend {
  final List<http.Request> requests = [];

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/rest/v1/')) requests.add(request);
      if (request.method == 'PATCH') {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'}, request: request);
      }
      return http.Response('[]', 200,
          headers: {
            'content-type': 'application/json',
            'content-range': '*/0',
          },
          request: request);
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
          'email': 'contract@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));
}

void main() {
  late _Backend backend;
  late SupabaseCoreEntitiesService service;

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
  });

  String table(http.Request r) => r.url.pathSegments.last;
  String? prefer(http.Request r) => r.headers['Prefer'];

  test(
      'each of the six deletes asks for the changed id of a not-yet-deleted '
      'row; a success that changed no row is no longer taken as deleted',
      () async {
    final deletes = <String, Future<void> Function()>{
      'requests': () => service.deleteRequest(_id),
      'offers': () => service.deleteOffer(_id),
      'owners': () => service.deleteOwner(_id),
      'offices': () => service.deleteOffice(_id),
      'brokers': () => service.deleteBroker(_id),
      'watchmen': () => service.deleteWatchman(_id),
    };
    var notified = 0;
    final changes = CoreEntityMutationNotifier.changes.listen((_) {
      notified++;
    });
    addTearDown(changes.cancel);

    for (final delete in deletes.entries) {
      backend.requests.clear();
      await expectLater(delete.value(), throwsA(isA<CoreEntityNotDeleted>()),
          reason: '${delete.key}: no changed row is not a delete');
      final r = backend.requests.first;
      expect(r.method, 'PATCH', reason: delete.key);
      expect(table(r), delete.key);
      expect(r.url.queryParameters,
          {'id': 'eq.$_id', 'deleted_at': 'is.null', 'select': 'id'},
          reason: delete.key);
      expect(prefer(r) ?? '', contains('return=representation'),
          reason: delete.key);
      expect(prefer(r) ?? '', isNot(contains('count=')), reason: delete.key);
      expect((json.decode(r.body) as Map).keys, ['deleted_at'],
          reason: delete.key);
      expect(backend.requests.map((r) => r.method), ['PATCH', 'GET'],
          reason: '${delete.key}: one read to tell "already deleted"');
    }
    await pumpEventQueue();
    expect(notified, 0, reason: 'an unconfirmed delete notifies nothing');
  });

  test(
      'Requests are read in pages (P4.1, §7AJ): own, not deleted, newest '
      'first with the id as tie breaker, 500 at a time, with an exact count',
      () async {
    backend.requests.clear();
    expect(await service.getRequests().first, isEmpty);
    final r = backend.requests.single;
    expect(r.method, 'GET');
    expect(table(r), 'requests');
    final q = r.url.queryParameters;
    expect(q['owner_id'], 'eq.$_uid');
    expect(q['deleted_at'], 'is.null');
    expect(q['order'], 'created_at.desc.nullslast,id.desc.nullslast');
    expect(q['limit'], '500');
    expect(q.containsKey('offset'), isFalse);
    expect(prefer(r) ?? '', contains('count=exact'));
  });

  test(
      'each of the other five list reads asks for every row: own, not '
      'deleted, newest first, with no limit, range or count; an empty answer '
      'is delivered as an empty list', () async {
    final reads = <String, Future<List<Object?>> Function()>{
      'offers': () => service.getOffers().first,
      'owners': () => service.getOwners().first,
      'offices': () => service.getOffices().first,
      'brokers': () => service.getBrokers().first,
      'watchmen': () => service.getWatchmen().first,
    };
    for (final read in reads.entries) {
      backend.requests.clear();
      expect(await read.value(), isEmpty, reason: read.key);
      final r = backend.requests.single;
      expect(r.method, 'GET', reason: read.key);
      expect(table(r), read.key);
      final q = r.url.queryParameters;
      expect(q['owner_id'], 'eq.$_uid', reason: read.key);
      expect(q['deleted_at'], 'is.null', reason: read.key);
      // One sort key: rows created at the same instant have no fixed order.
      expect(q['order'], 'created_at.desc.nullslast', reason: read.key);
      expect(q.containsKey('limit'), isFalse, reason: read.key);
      expect(q.containsKey('offset'), isFalse, reason: read.key);
      expect(r.headers.containsKey('Range'), isFalse, reason: read.key);
      expect(prefer(r) ?? '', isNot(contains('count=')), reason: read.key);
    }
  });

  test(
      'Home counts send seven count-only HEAD requests with an exact count '
      'and the same not-deleted filter; no rows are selected', () async {
    backend.requests.clear();
    await SupabaseHomeCountsService(client: backend.client).getCounts();
    expect(backend.requests, hasLength(7));
    expect(backend.requests.map(table).toSet(), {
      'watchmen',
      'brokers',
      'offers',
      'offices',
      'owners',
      'requests',
      'quotations',
    });
    for (final r in backend.requests) {
      expect(r.method, 'HEAD', reason: table(r));
      expect(r.url.queryParameters, {'deleted_at': 'is.null'},
          reason: table(r));
      expect(prefer(r), contains('count=exact'), reason: table(r));
    }
  });
}
