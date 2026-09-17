import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

// -----------------------------------------------------------------------------
// Client-level regression test for the favorite_* insert permission fix.
//
// `FavoriteService.addToFavorites` reads the process-wide `Supabase.instance`
// singleton via `RepositoryProvider`, which in turn requires a fully
// initialized Supabase bootstrap and a real AuthRepository identity. Neither
// is practical to fake here without either driving the real bootstrap flow or
// adding a test-only seam to production code, so this test does not call
// `FavoriteService.addToFavorites` itself. Instead it exercises the exact same
// `upsert(...)` call shape now used at
// lib/src/views/Screens/home/favorites/favorites_service.dart:161-168,
// against a real `SupabaseClient` wired to a recording mock transport — the
// same harness pattern already used in test/auth/phone_verification_test.dart.
// This proves the outgoing request's shape and semantics; it does not prove
// server-side conflict handling, which requires a real Postgres instance.
// -----------------------------------------------------------------------------

void main() {
  const ownerId = '5ec0de00-0000-4000-8000-00000000000a';
  const targetId = '5ec0de00-0000-4000-8000-00000000000b';

  sb.SupabaseClient buildClient(List<http.Request> requests) {
    return sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        // PostgREST's default response for an insert with no trailing
        // .select() is 201 with an empty body (Prefer: return=minimal).
        // `request:` must be set explicitly here: http's MockClient takes it
        // from the returned Response rather than attaching it automatically,
        // and postgrest's response parser dereferences it unconditionally.
        return http.Response('', 201, request: request, headers: {
          'content-type': 'application/json',
        });
      }),
    );
  }

  Future<void> addFavorite(sb.SupabaseClient client) {
    // Exact call shape used by FavoriteService.addToFavorites for every one
    // of the six favorite_* tables.
    return client.from('favorite_brokers').upsert(
      {
        'owner_id': ownerId,
        'target_id': targetId,
      },
      ignoreDuplicates: true,
    );
  }

  test('add-favorite upsert requests conflict-ignore, not conflict-update',
      () async {
    final requests = <http.Request>[];
    final client = buildClient(requests);

    await addFavorite(client);

    expect(requests, hasLength(1));
    final request = requests.single;

    // POST, not PATCH: PostgREST never issues an UPDATE statement for this
    // call shape, matching the database's INSERT/SELECT/DELETE-only grants.
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/favorite_brokers');

    // This is the exact header that changes with ignoreDuplicates: true. The
    // pre-fix code (bare .upsert(...)) sends resolution=merge-duplicates,
    // which PostgREST executes as ON CONFLICT DO UPDATE and which requires
    // UPDATE privilege the authenticated role does not have.
    final prefer = request.headers['Prefer'] ?? request.headers['prefer'];
    expect(prefer, contains('resolution=ignore-duplicates'));
    expect(prefer, isNot(contains('resolution=merge-duplicates')));
  });

  test(
      'the request body never carries added_at, so the client can never '
      'overwrite an existing favorite\'s original timestamp', () async {
    final requests = <http.Request>[];
    final client = buildClient(requests);

    await addFavorite(client);

    final decoded = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(decoded.keys, unorderedEquals(['owner_id', 'target_id']));
    expect(decoded['owner_id'], ownerId);
    expect(decoded['target_id'], targetId);
    expect(decoded.containsKey('added_at'), isFalse);
  });

  test(
      'a repeated add for the same (owner_id, target_id) completes without '
      'throwing, requiring no client-side duplicate-key handling', () async {
    final requests = <http.Request>[];
    final client = buildClient(requests);

    // Two calls simulate a double-tap / retry landing on an already-favorited
    // row. Both are expected to resolve normally: this is the behavior the
    // ignoreDuplicates: true change is meant to guarantee at the call site.
    // The server actually deduplicating via ON CONFLICT DO NOTHING is a
    // Postgres/PostgREST guarantee this test does not and cannot exercise.
    await addFavorite(client);
    await addFavorite(client);

    expect(requests, hasLength(2));
    for (final request in requests) {
      final prefer = request.headers['Prefer'] ?? request.headers['prefer'];
      expect(prefer, contains('resolution=ignore-duplicates'));
    }
  });
}
