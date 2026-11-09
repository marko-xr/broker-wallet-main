// P4.0 (tracker §7AI): what a list read gets from a server that caps its
// answer at `max_rows`. PostgREST answers a capped read with status 200, the
// first `max_rows` rows and `Content-Range: 0-<max_rows - 1>/*`: nothing says
// rows were left out, so a read with no limit, range or count is cut silently.
//
// Since P4.1/P4.2 (§7AJ/§7AK) the six entity lists are read in pages, and
// since P4.4 (§7AO) the Favorites lists too: no list read is one unpaged
// request any more. This records the last one that was — 1,200 favorite
// Offers on a server capped at the hosted value (1,000, verified on the
// Dashboard in P4.3, §7AM) — now coming back whole.
import 'dart:convert';

import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/// The hosted `max_rows` (P4.3, §7AM).
const _maxRows = 1000;

void main() {
  test(
      '1,200 favorite Offers from a server capped at 1,000: all 1,200 come '
      'back, in pages of 500 with an exact count (was: 1,000, silently)',
      () async {
    final reads = <http.Request>[];
    final favorites = [
      for (var n = 0; n < 1200; n++)
        {
          'target_id':
              '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
          'added_at': DateTime.utc(2026, 1, 1)
              .add(Duration(minutes: 1200 - n))
              .toIso8601String(),
        },
    ];
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        if (table == 'favorite_offers') reads.add(request);
        var rows = table == 'favorite_offers'
            ? favorites
            : const <Map<String, String>>[];
        final total = rows.length;
        final or = request.url.queryParameters['or'];
        if (or != null) {
          final after =
              RegExp(r'target_id\.lt\.([0-9a-f-]+)').firstMatch(or)!.group(1);
          rows =
              rows.skipWhile((r) => r['target_id'] != after).skip(1).toList();
        }
        final limit =
            int.parse(request.url.queryParameters['limit'] ?? '$total');
        rows = rows.take(limit < _maxRows ? limit : _maxRows).toList();
        final counting =
            (request.headers['Prefer'] ?? '').contains('count=exact');
        final count = counting ? '$total' : '*';
        return http.Response(jsonEncode(rows), 200,
            headers: {
              'content-type': 'application/json',
              'content-range':
                  rows.isEmpty ? '*/$count' : '0-${rows.length - 1}/$count',
            },
            request: request);
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );

    final service = FavoriteService(client: client, currentUserId: () => _uid);
    final metadata = await service.getAllFavoritesWithMetadata();

    expect(metadata['offers'], hasLength(1200));
    expect(reads, hasLength(3));
    for (final read in reads) {
      expect(read.url.queryParameters['limit'], '500');
      expect(read.url.queryParameters.containsKey('offset'), isFalse);
    }
    expect(reads.first.headers['Prefer'], contains('count=exact'));
  });
}
