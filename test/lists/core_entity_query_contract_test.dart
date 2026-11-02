// P3.0: the requests the shared core-entity service sends today, recorded as
// they are (characterization, not a fix). Each finding behind them is in the
// performance tracker, section 7Z.
//
// - A soft delete is a PATCH by id with no row confirmation: PostgREST
//   answers 204 whether or not a row changed, and that counts as success.
// - The six list reads ask for every row (no limit, no range, no count), so
//   a server row cap can shorten a list silently, and an empty answer looks
//   the same whatever its cause.
// - Home counts send seven GET requests that also return the id rows.
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
/// database's session gate filters out; writes answer 204 with no body, as
/// PostgREST does whether or not a row was changed.
class _Backend {
  final List<http.Request> requests = [];

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/rest/v1/')) requests.add(request);
      if (request.method == 'PATCH') {
        return http.Response('', 204, request: request);
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
      'each of the six deletes is a PATCH by id with no row confirmation, '
      'and a 204 with no row counts as success', () async {
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
      await delete.value(); // completes: a 204 is taken as "deleted"
      final r = backend.requests.single;
      expect(r.method, 'PATCH', reason: delete.key);
      expect(table(r), delete.key);
      expect(r.url.queryParameters, {'id': 'eq.$_id'},
          reason: '${delete.key}: no deleted_at, owner or select filter');
      expect(prefer(r) ?? '', isNot(contains('return=representation')),
          reason: delete.key);
      expect(prefer(r) ?? '', isNot(contains('count=')), reason: delete.key);
      expect((json.decode(r.body) as Map).keys, ['deleted_at'],
          reason: delete.key);
    }
    await pumpEventQueue();
    expect(notified, 6, reason: 'every delete notifies every open list');
  });

  test(
      'each of the six list reads asks for every row: own, not deleted, '
      'newest first, with no limit, range or count; an empty answer is '
      'delivered as an empty list', () async {
    final reads = <String, Future<List<Object?>> Function()>{
      'requests': () => service.getRequests().first,
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
      'Home counts send seven GET requests that also return the id rows '
      '(select=id with an exact count), not seven HEAD counts', () async {
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
      expect(r.method, 'GET', reason: table(r));
      expect(r.url.queryParameters['select'], 'id', reason: table(r));
      expect(r.url.queryParameters['deleted_at'], 'is.null', reason: table(r));
      expect(prefer(r), contains('count=exact'), reason: table(r));
    }
  });
}
