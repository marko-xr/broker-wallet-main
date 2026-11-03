// P4.0 (tracker §7AI): what a list read gets from a server that caps its
// answer at `max_rows` — recorded as it is (characterization, not a fix).
// PostgREST answers a capped read with status 200, the first `max_rows` rows
// and `Content-Range: 0-<max_rows - 1>/*`: nothing says rows were left out.
//
// Since P4.1/P4.2 (§7AJ/§7AK) the six entity lists are read in pages and no
// longer cut. The Favorites lists (which records are favorites) are still
// one request each, with no limit, range or count, so this records them.
import 'dart:convert';

import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/// The cap the server applies here. The hosted value is not known (§7AI);
/// the local configuration's is used.
const _maxRows = 1000;

void main() {
  test(
      '1,200 favorite Offers from a server capped at 1,000: 1,000 come back, '
      'with no error and nothing marking the list as cut', () async {
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
        final rows = table == 'favorite_offers'
            ? favorites.take(_maxRows).toList()
            : const <Object>[];
        return http.Response(jsonEncode(rows), 200,
            headers: {
              'content-type': 'application/json',
              'content-range': rows.isEmpty ? '*/*' : '0-${rows.length - 1}/*',
            },
            request: request);
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );

    final service = FavoriteService(client: client, currentUserId: () => _uid);
    final metadata = await service.getAllFavoritesWithMetadata();

    expect(metadata['offers'], hasLength(_maxRows),
        reason: '200 favorite Offers silently missing');
    final read = reads.single;
    expect(read.url.queryParameters.containsKey('limit'), isFalse);
    expect(read.url.queryParameters.containsKey('offset'), isFalse);
    expect(read.headers['Prefer'] ?? '', isNot(contains('count=')));
  });
}
