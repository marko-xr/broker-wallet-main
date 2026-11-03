// P4.0 (tracker §7AI): what a list read gets today from a server that caps
// its answer at `max_rows` — recorded as it is (characterization, not a fix).
// Since P4.1 (§7AJ) Requests are read in pages and no longer cut; this
// records an Offers read, still one request.
// PostgREST answers a capped read with status 200, the first `max_rows` rows
// and `Content-Range: 0-<max_rows - 1>/*`: nothing says rows were left out.
// The list read sends no limit, range or count, so it cannot tell either.
import 'dart:convert';

import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/// The cap the server applies here. The hosted value is not known (§7AI);
/// the local configuration's is used.
const _maxRows = 1000;

String _fakeJwt() {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  test(
      'a read of 1,200 Offers from a server capped at 1,000 delivers 1,000 '
      'with no error and nothing marking the list as cut', () async {
    final requests = <http.Request>[];
    final rows = [
      for (var n = 0; n < 1200; n++)
        {
          'id': '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
          'owner_id': _uid,
          'offer_type': 'rent',
          'created_at': DateTime.utc(2026, 1, 1)
              .add(Duration(minutes: 1200 - n))
              .toIso8601String(),
          'offer_areas': const <Object>[],
        },
    ];
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        final capped = rows.take(_maxRows).toList();
        return http.Response(jsonEncode(capped), 200,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-${capped.length - 1}/*',
            },
            request: request);
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _uid,
        'aud': 'authenticated',
        'email': 'cap@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));

    final service = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: R2OfferMediaUploadService(
        supabaseClient: client,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
    final list = await service.getOffers().first;

    expect(list, hasLength(_maxRows), reason: '200 Offers silently missing');
    final read = requests.single;
    expect(read.url.queryParameters.containsKey('limit'), isFalse);
    expect(read.url.queryParameters.containsKey('offset'), isFalse);
    expect(read.headers['Prefer'] ?? '', isNot(contains('count=')));
    // One sort key: rows created at the same instant have no fixed order, so
    // no page boundary could be placed between them reliably.
    expect(read.url.queryParameters['order'], 'created_at.desc.nullslast');
  });
}
