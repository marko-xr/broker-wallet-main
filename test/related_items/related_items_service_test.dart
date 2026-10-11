import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/related_items_service.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _otherId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _phone = '0552885222';

String _fakeJwt() {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expires = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _userId, 'exp': expires.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> _row(
  String id, {
  String owner = _userId,
  String phone = _phone,
  bool deleted = false,
}) =>
    {
      'id': id,
      'owner_id': owner,
      'phone_number': phone,
      'created_at': '2026-10-01T10:00:00Z',
      'updated_at': '2026-10-01T10:00:00Z',
      if (deleted) 'deleted_at': '2026-10-02T10:00:00Z',
    };

void main() {
  test('Supabase related reads need no Firebase App and keep the phone, owner, '
      'deleted-row and ten-item contract', () async {
    final requests = <http.Request>[];
    var failNextRead = false;
    final fixtures = {
      'offers': [
        for (var i = 0; i < 12; i++) _row('offer-$i'),
        _row('other-owner', owner: _otherId),
        _row('deleted-offer', deleted: true),
        _row('other-phone', phone: '0500000000'),
      ],
      'requests': [
        _row('request-1'),
        _row('request-2'),
        _row('deleted-request', deleted: true),
      ],
    };
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (failNextRead) {
          failNextRead = false;
          return http.Response(jsonEncode({'message': 'read failed'}), 500,
              headers: {'content-type': 'application/json'}, request: request);
        }
        final table = request.url.pathSegments.last;
        final rows = fixtures[table]!;
        final params = request.url.queryParameters;
        final matched = rows
            .where((row) =>
                row['owner_id'] ==
                    params['owner_id']?.replaceFirst('eq.', '') &&
                row['phone_number'] ==
                    params['phone_number']?.replaceFirst('eq.', '') &&
                row['deleted_at'] == null &&
                params['deleted_at'] == 'is.null')
            .toList();
        final limited = params['limit'] == null
            ? matched
            : matched.take(int.parse(params['limit']!)).toList();
        return http.Response(
          jsonEncode(limited),
          200,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-${limited.length - 1}/${matched.length}',
          },
          request: request,
        );
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': DateTime.now().add(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _userId,
        'aud': 'authenticated',
        'email': 'related@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));

    // Owner, Office, Broker and Watchman all construct this same service.
    RelatedItemsService();
    final service = RelatedItemsService(
      coreEntities: SupabaseCoreEntitiesService(
        client: client,
        offerMedia: R2OfferMediaUploadService(supabaseClient: client),
      ),
    );
    final offers = await service.getRelatedOffers('055 288-5222').first;
    final relatedRequests =
        await service.getRelatedRequests('055 288-5222').first;
    expect(offers, hasLength(10));
    expect(
      relatedRequests.map((item) => item.id),
      containsAll(['request-1', 'request-2']),
    );
    expect(
      offers.every((item) =>
          item.userId == _userId && item.phoneNumber == _phone),
      isTrue,
    );
    expect(await service.getRelatedItemsCount('055 288-5222'), 14);
    expect(requests, hasLength(4));
    for (final request in requests) {
      final params = request.url.queryParameters;
      expect(params['owner_id'], 'eq.$_userId');
      expect(params['phone_number'], 'eq.$_phone');
      expect(params['deleted_at'], 'is.null');
    }
    expect(
      requests.take(2).every(
          (request) => request.url.queryParameters['limit'] == '10'),
      isTrue,
    );
    expect(
      requests.take(2).every(
          (request) =>
              request.url.queryParameters['order'] == 'id.asc.nullslast'),
      isTrue,
    );
    expect(await service.getRelatedOffers('').first, isEmpty);
    expect(requests, hasLength(4));
    failNextRead = true;
    await expectLater(
      service.getRelatedOffers(_phone),
      emitsError(isA<sb.PostgrestException>()),
    );
  });

  test('all four migrated detail screens use the shared related service', () {
    for (final entity in ['owners', 'offices', 'brokers', 'watchmen']) {
      final source = File('lib/src/views/Screens/ViewDetails/'
          '${entity}_view_details.dart').readAsStringSync();
      expect(source, contains('RelatedItemsService();'), reason: entity);
      expect(source, contains('_relatedItemsService.getRelatedOffers('),
          reason: entity);
      expect(source, contains('.getRelatedRequests('), reason: entity);
    }
  });
}
