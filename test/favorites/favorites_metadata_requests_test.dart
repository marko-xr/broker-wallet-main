// P3.4 (tracker §7AH): which favorites this account has — six small lists,
// one per type — read with the real FavoriteService on a recording client.
import 'dart:convert';

import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const _tables = {
  'offers': 'favorite_offers',
  'requests': 'favorite_requests',
  'owners': 'favorite_owners',
  'offices': 'favorite_offices',
  'brokers': 'favorite_brokers',
  'watchmen': 'favorite_watchmen',
};

class _Backend {
  final List<http.Request> requests = [];
  final Set<String> failing = {};
  int _inFlight = 0;
  int maxInFlight = 0;

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      _inFlight++;
      if (_inFlight > maxInFlight) maxInFlight = _inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      _inFlight--;
      final table = request.url.pathSegments.last;
      if (failing.contains(table)) {
        return http.Response('{"message":"unavailable"}', 500,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final n = _tables.values.toList().indexOf(table) + 1;
      return http.Response(
          jsonEncode([
            {'target_id': 'id-$n-b', 'added_at': '2026-11-0${n}T10:00:00Z'},
            {'target_id': 'id-$n-a', 'added_at': '2026-10-0${n}T10:00:00Z'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
}

void main() {
  late _Backend backend;
  late FavoriteService service;

  setUp(() {
    backend = _Backend();
    service =
        FavoriteService(client: backend.client, currentUserId: () => _uid);
  });

  test(
      'the six lists are asked for together, each with the same filter and '
      'order as before', () async {
    final favorites = await service.getAllFavoritesWithMetadata();

    expect(backend.requests, hasLength(6));
    expect(backend.maxInFlight, 6, reason: 'was 1: six in a row');
    expect(backend.requests.map((r) => r.url.pathSegments.last).toSet(),
        _tables.values.toSet());
    for (final r in backend.requests) {
      expect(r.method, 'GET');
      expect(r.url.queryParameters, {
        'select': 'target_id,added_at',
        'owner_id': 'eq.$_uid',
        'order': 'added_at.desc.nullslast',
      });
    }

    expect(favorites.keys.toSet(), _tables.keys.toSet());
    var n = 0;
    for (final type in _tables.keys) {
      n++;
      final list = favorites[type]!;
      expect(list.map((m) => m.itemId), ['id-$n-b', 'id-$n-a'], reason: type);
      expect(list.every((m) => m.type == type), isTrue, reason: type);
      expect(list.first.addedAt, DateTime.utc(2026, 11, n, 10), reason: type);
    }
  });

  test('one list that cannot be read still fails the whole read, as before',
      () async {
    backend.failing.add('favorite_owners');
    expect(await service.getAllFavoritesWithMetadata(), isEmpty);
  });
}
