// M2-1 (tracker §7AZ, D-M2-1..6): the Offer and Owner reads also bring each
// record's trusted media identity — the ids of its `ready` media, in gallery
// order — from the link tables (`offer_media` / `owner_media`) embedded in
// the same keyset-paged request. Nothing else changes: no extra request, the
// same pages, cursor, exact count and completeness rules, and no link,
// object key or bucket is asked for.
//
// The identity lands in `listedMediaObjectIds`, a field nothing displays yet
// (M2-2 saves it, M2-3 uses it). `OfferModel.mediaObjectIds` keeps its own
// meaning — ids aligned with signed links from the media Worker — so the
// edit form, Favorites and the details screen behave exactly as before.
//
// The server is an emulation of PostgREST for one table: owner and deleted
// filters, order, limit, keyset, exact count, and the embedded link rows
// (returned only when asked for, as PostgREST does). The database side of
// the same contract — left-join embedding, RLS and the session gate on the
// embedded rows — was executed on the real migrations (tracker §7AZ M2-1).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _s1 = 'a1a1a1a1-0000-4000-8000-000000000001';

String _sessionJson(String uid, String sessionId) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({
        'sub': uid,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'session_id': sessionId,
      })}.sig';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
    'refresh_token': 'refresh-$sessionId',
    'user': {
      'id': uid,
      'aud': 'authenticated',
      'email': '$uid@example.test',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-11T10:00:00Z',
    },
  });
}

String _media(int n) =>
    'cccccccc-cccc-4ccc-8ccc-${n.toString().padLeft(12, '0')}';

String _pgTime(DateTime t) {
  final u = t.toUtc().toIso8601String();
  return '${u.replaceFirst('Z', '')}+00:00';
}

final _base = DateTime.utc(2026, 1, 1);

/// One embedded link row as PostgREST returns it for
/// `media_id, ordinal, media_objects(status, content_type)`.
Map<String, dynamic> _link(String id, int ordinal,
        {String status = 'ready', String type = 'image/jpeg'}) =>
    {
      'media_id': id,
      'ordinal': ordinal,
      'media_objects': {'status': status, 'content_type': type},
    };

/// An Offer or Owner list, the way the app reads it.
class _Kind {
  const _Kind(this.table, this.link, this.prefix, this.columns);

  final String table;

  /// The embedded link table PostgREST returns for this parent.
  final String link;
  final String prefix;
  final Map<String, dynamic> Function(int n) columns;

  String id(int n) =>
      '${prefix}0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  Map<String, dynamic> row(int n,
          {String owner = _alice, DateTime? createdAt, List<Object?>? links}) =>
      {
        'id': id(n),
        'owner_id': owner,
        'phone_number': '50000$n',
        'country_code': '+971',
        'notes': 'Record $n',
        'created_at':
            _pgTime(createdAt ?? _base.add(Duration(microseconds: n * 1001))),
        'updated_at': _pgTime(_base),
        'deleted_at': null,
        ...columns(n),
        if (links != null) link: links,
      };
}

final _offers = _Kind(
    'offers',
    'offer_media',
    '2',
    (n) => {
          'offer_type': 'rent',
          'selected_city': 'Dubai',
          'location_text': 'Marina $n',
          'min_price': 1000,
          'max_price': 2000,
          'square_footage': 900,
          'property_type': 'residential',
          'specific_property_type': 'Apartment',
          'rooms': 2,
          'bathrooms': 2,
          'pickup_location_text': '',
          'pickup_address': '',
          'legacy_uploaded_file_name': '',
          'status': 'available',
          'offer_areas': [
            {'area': 'Marina', 'ordinal': 0},
          ],
        });

final _owners = _Kind(
    'owners',
    'owner_media',
    '3',
    (n) => {
          'name': 'Owner $n',
          'property_type_text': 'Villa',
          'property_location': 'Dubai Hills',
          'pickup_location_text': '',
          'pickup_address': '',
        });

/// PostgREST for one table, with embedded link rows.
class _Server {
  _Server(this.kind);

  final _Kind kind;
  final List<Map<String, dynamic>> rows = [];
  int? failOnPage;
  String? embedError;
  FutureOr<void> Function(int page)? beforePage;
  final List<http.Request> reads = [];
  int bodyBytes = 0;
  int _page = 0;

  static final _keyset = RegExp(
      r'^\(created_at\.lt\.(.+),and\(created_at\.eq\.(.+),id\.lt\.([0-9a-f-]+)\)\)$');

  static final Map<String, DateTime> _times = {};
  static DateTime time(Map<String, dynamic> row) => _times.putIfAbsent(
      row['created_at'] as String,
      () => DateTime.parse(row['created_at'] as String));

  static int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final t = time(b).compareTo(time(a));
    return t != 0 ? t : (b['id'] as String).compareTo(a['id'] as String);
  }

  List<Map<String, dynamic>>? _sorted;
  int _sortedLength = -1;
  List<Map<String, dynamic>> sorted() {
    if (_sorted == null || _sortedLength != rows.length) {
      _sorted = [...rows]..sort(compare);
      _sortedLength = rows.length;
    }
    return _sorted!;
  }

  late final MockClient client = MockClient((request) async {
    final url = request.url;
    if (!url.path.startsWith('/rest/v1/${kind.table}')) {
      return http.Response('[]', 200, request: request);
    }
    reads.add(request);
    final q = url.queryParameters;
    final select = q['select'] ?? '*';
    final error = embedError;
    if (error != null) {
      return http.Response(
          jsonEncode({'code': 'PGRST200', 'message': error}), 400,
          headers: {'content-type': 'application/json'}, request: request);
    }
    final page = ++_page;
    await beforePage?.call(page);
    // From that page on (the client retries a failed request).
    final failFrom = failOnPage;
    if (failFrom != null && page >= failFrom) {
      throw http.ClientException('connection reset', url);
    }
    var found = [
      for (final r in sorted())
        if ('eq.${r['owner_id']}' == q['owner_id'] && r['deleted_at'] == null)
          r,
    ];
    if ((q['id'] ?? '').startsWith('eq.')) {
      found = [
        for (final r in found)
          if ('eq.${r['id']}' == q['id']) r
      ];
    }
    if ((q['id'] ?? '').startsWith('in.')) {
      final wanted = q['id']!.substring(4, q['id']!.length - 1).split(',');
      found = [
        for (final r in found)
          if (wanted.contains(r['id'])) r
      ];
    }
    final keyset = q['or'];
    if (keyset != null) {
      final m = _keyset.firstMatch(keyset)!;
      final at = DateTime.parse(m.group(1)!);
      final after = m.group(3)!;
      found = [
        for (final r in found)
          if (time(r).isBefore(at) ||
              (time(r).isAtSameMomentAs(at) &&
                  (r['id'] as String).compareTo(after) < 0))
            r,
      ];
    }
    final total = found.length;
    final take = int.parse(q['limit'] ?? '$total');
    final embeds = select.contains('${kind.link}(');
    final answer = [
      for (final r in found.take(take))
        {
          for (final e in r.entries)
            if (e.key != kind.link || embeds) e.key: e.value,
          // PostgREST answers an asked-for one-to-many embed with [] when
          // there are no rows.
          if (embeds && !r.containsKey(kind.link)) kind.link: <Object>[],
        },
    ];
    final counting = (request.headers['Prefer'] ?? '').contains('count=exact');
    final range = answer.isEmpty
        ? '*/${counting ? total : '*'}'
        : '0-${answer.length - 1}/${counting ? total : '*'}';
    final body = jsonEncode(answer);
    bodyBytes += utf8.encode(body).length;
    return http.Response(body, answer.length < total ? 206 : 200,
        headers: {'content-type': 'application/json', 'content-range': range},
        request: request);
  });
}

class _Harness {
  _Harness(this.server, this.client, this.core, this.mediaCalls);

  final _Server server;
  final sb.SupabaseClient client;
  final SupabaseCoreEntitiesService core;
  final List<http.BaseRequest> mediaCalls;

  static Future<_Harness> start(_Kind kind) async {
    final server = _Server(kind);
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: server.client,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(_sessionJson(_alice, _s1));
    final mediaCalls = <http.BaseRequest>[];
    MockClient worker() => MockClient((request) async {
          mediaCalls.add(request);
          return http.Response('{"media":[]}', 200, request: request);
        });
    final core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: R2OfferMediaUploadService(
          supabaseClient: client, httpClient: worker()),
      ownerMedia: R2OfferMediaUploadService(
          supabaseClient: client,
          httpClient: worker(),
          parent: MediaParent.owner),
    );
    return _Harness(server, client, core, mediaCalls);
  }
}

List<String> _listed(Object? item) => item is OfferModel
    ? item.listedMediaObjectIds
    : (item as OwnerModel).listedMediaObjectIds;

Future<List<Object?>> _read(_Kind kind, _Harness h) =>
    kind == _offers ? h.core.getOffers().first : h.core.getOwners().first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => ListSessionCheck.debugOverride = null);

  for (final kind in [_offers, _owners]) {
    group(kind.table, () {
      late _Harness h;
      setUp(() async => h = await _Harness.start(kind));

      test('asks for the link rows: media id, ordinal, status and type only',
          () async {
        h.server.rows.add(kind.row(1));
        await _read(kind, h);
        final select = h.server.reads.single.url.queryParameters['select']!;
        expect(
            select,
            contains(
                '${kind.link}(media_id,ordinal,media_objects(status,content_type))'));
        for (final secret in ['object_key', 'bucket', 'url', 'signed']) {
          expect(select, isNot(contains(secret)), reason: secret);
        }
        expect(select, isNot(contains('!inner')),
            reason: 'a plain embed never removes a parent row');
        if (kind == _offers)
          expect(select, contains('offer_areas(area,ordinal)'));
      });

      test('zero, one and ten media, in gallery order', () async {
        h.server.rows
          ..add(kind.row(1, links: const []))
          ..add(kind.row(2, links: [_link(_media(1), 0)]))
          ..add(kind.row(3, links: [
            for (var i = 9; i >= 0; i--) _link(_media(10 + i), i),
          ]))
          ..add(kind.row(4)); // no embedded key at all: still a parent
        final list = await _read(kind, h);
        final byId = {for (final x in list) (x as dynamic).id: x};
        expect(list, hasLength(4), reason: 'every parent is kept');
        expect(_listed(byId[kind.id(1)]), isEmpty);
        expect(_listed(byId[kind.id(2)]), [_media(1)]);
        expect(_listed(byId[kind.id(3)]),
            [for (var i = 0; i < 10; i++) _media(10 + i)]);
        expect(_listed(byId[kind.id(4)]), isEmpty);
      });

      test('only ready media of a listable type; nothing malformed', () async {
        final good = _media(1);
        h.server.rows.add(kind.row(1, links: [
          _link(good, 3),
          _link(_media(2), 0, status: 'pending_upload'),
          _link(_media(3), 1, status: 'uploaded'),
          _link(_media(4), 2, status: 'deleted'),
          _link(_media(5), 4, status: 'failed'),
          _link(_media(6), 5, type: 'application/pdf'),
          _link(_media(7), 6, type: 'image/heic'), // the Worker lists it
          _link(good, 7), // the same media twice
          {
            'media_id': 'not-a-uuid',
            'ordinal': 8,
            'media_objects': {'status': 'ready', 'content_type': 'image/png'}
          },
          {
            'media_id': _media(8).toUpperCase(),
            'ordinal': 9,
            'media_objects': {'status': 'ready', 'content_type': 'image/png'}
          },
          {
            'media_id': _media(9),
            'ordinal': 'x',
            'media_objects': {'status': 'ready', 'content_type': 'image/png'}
          },
          {
            'media_id': _media(10),
            'ordinal': -1,
            'media_objects': {'status': 'ready', 'content_type': 'image/png'}
          },
          {'media_id': _media(11), 'ordinal': 10},
          {'media_id': _media(12), 'ordinal': 11, 'media_objects': null},
          {
            'media_id': _media(13),
            'ordinal': 12,
            'media_objects': {'status': null, 'content_type': null}
          },
          {
            'media_id': null,
            'ordinal': 13,
            'media_objects': {'status': 'ready', 'content_type': 'image/png'}
          },
          'not a map',
        ]));
        final list = await _read(kind, h);
        expect(_listed(list.single), [good, _media(7)]);
      });

      test('another parent type\'s links are ignored', () async {
        final other = kind == _offers ? 'owner_media' : 'offer_media';
        h.server.rows.add({
          ...kind.row(1),
          other: [_link(_media(1), 0)],
        });
        final list = await _read(kind, h);
        expect(_listed(list.single), isEmpty);
      });

      test('1,200 records: three pages, exact count, no extra request',
          () async {
        for (var n = 1; n <= 1200; n++) {
          h.server.rows.add(kind.row(n, links: [_link(_media(n), 0)]));
        }
        final list = await _read(kind, h);
        expect(list, hasLength(1200));
        expect(h.server.reads, hasLength(3));
        expect(h.server.reads.first.headers['Prefer'], contains('count=exact'));
        for (final r in h.server.reads) {
          expect(r.url.queryParameters['limit'], '500');
        }
        expect(h.mediaCalls, isEmpty, reason: 'no media Worker call');
        expect(
            [for (final x in list) _listed(x).single].toSet(), hasLength(1200));
      });

      test('equal created_at: the compound cursor loses and repeats nothing',
          () async {
        final same = DateTime.utc(2026, 3, 1);
        for (var n = 1; n <= 1100; n++) {
          h.server.rows
              .add(kind.row(n, createdAt: same, links: [_link(_media(n), 0)]));
        }
        final list = await _read(kind, h);
        expect(
            [for (final x in list) (x as dynamic).id].toSet(), hasLength(1100));
        expect(h.server.reads, hasLength(3));
      });

      test('other accounts\' rows are not read', () async {
        h.server.rows
          ..add(kind.row(1, links: [_link(_media(1), 0)]))
          ..add(kind.row(2, owner: _bob, links: [_link(_media(2), 0)]));
        final list = await _read(kind, h);
        expect(list, hasLength(1));
        expect(_listed(list.single), [_media(1)]);
      });

      test('an empty account: an empty list, as before', () async {
        expect(await _read(kind, h), isEmpty);
        expect(h.server.reads, hasLength(1));
      });

      for (final (name, setUpFailure) in [
        (
          'the embedded read fails (400)',
          (_Server s) => s.embedError = 'no relationship'
        ),
        ('the first page fails', (_Server s) => s.failOnPage = 1),
        ('a later page fails', (_Server s) => s.failOnPage = 2),
      ]) {
        test('$name: an error, never a part of the list', () async {
          for (var n = 1; n <= 1200; n++) {
            h.server.rows.add(kind.row(n, links: [_link(_media(n), 0)]));
          }
          setUpFailure(h.server);
          Object? error;
          List<Object?>? got;
          try {
            got = await _read(kind, h);
          } catch (e) {
            error = e;
          }
          expect(got, isNull);
          expect(error, isNotNull);
        });
      }

      test('the account changes during a paged read: no list', () async {
        for (var n = 1; n <= 1200; n++) {
          h.server.rows.add(kind.row(n, links: [_link(_media(n), 0)]));
        }
        h.server.beforePage = (page) async {
          if (page == 2) {
            await h.client.auth.setInitialSession(_sessionJson(_bob, _s1));
          }
        };
        Object? error;
        try {
          await _read(kind, h);
        } catch (e) {
          error = e;
        }
        expect(error, isNotNull);
      });

      test('the single-record read brings the same identity', () async {
        h.server.rows.add(
            kind.row(7, links: [_link(_media(2), 1), _link(_media(1), 0)]));
        final one = kind == _offers
            ? await h.core.getOfferMetadata(kind.id(7))
            : await h.core.getOwner(kind.id(7));
        expect(_listed(one), [_media(1), _media(2)]);
        expect(h.mediaCalls, isEmpty);
      });
    });
  }

  group('nothing that displays media changes', () {
    test('Offer: mediaObjectIds and mediaUrls stay empty for list rows',
        () async {
      final h = await _Harness.start(_offers);
      h.server.rows.add(_offers.row(1, links: [_link(_media(1), 0)]));
      final offer = (await h.core.getOffers().first).single;
      expect(offer.listedMediaObjectIds, [_media(1)]);
      expect(offer.mediaObjectIds, isEmpty,
          reason: 'its meaning (ids aligned with signed links) is unchanged');
      expect(offer.mediaUrls, isEmpty);
      expect(offer.mediaUrl, isNull);
    });

    test('Owner: mediaUrls stay empty for list rows', () async {
      final h = await _Harness.start(_owners);
      h.server.rows.add(_owners.row(1, links: [_link(_media(1), 0)]));
      final owner = (await h.core.getOwners().first).single;
      expect(owner.listedMediaObjectIds, [_media(1)]);
      expect(owner.mediaUrls, isEmpty);
      expect(owner.mediaUrl, isNull);
    });

    test('models built without the identity, and copies, keep it as given', () {
      final offer = OfferModel(
        userId: _alice,
        offerType: 'rent',
        selectedCity: '',
        selectedAreas: const [],
        location: '',
        phoneNumber: '',
        countryCode: '+971',
        minPrice: '',
        maxPrice: '',
        notes: '',
        specificPropertyType: '',
        rooms: 0,
        bathrooms: 0,
        pickUpLocation: '',
        pickUpLatitude: null,
        pickUpLongitude: null,
        pickUpAddress: '',
        uploadedFileName: '',
        createdAt: _base,
        updatedAt: _base,
        mediaUrls: const [],
      );
      expect(offer.listedMediaObjectIds, isEmpty);
      final withIds = offer.copyWith(listedMediaObjectIds: [_media(1)]);
      expect(withIds.copyWith(notes: 'x').listedMediaObjectIds, [_media(1)]);
      expect(withIds.copyWith(mediaObjectIds: [_media(2)]).listedMediaObjectIds,
          [_media(1)]);
      final owner = OwnerModel(
        userId: _alice,
        name: '',
        phoneNumber: '',
        countryCode: '+971',
        typeOfProperties: '',
        propertyLocation: '',
        notes: '',
        pickUpLocation: '',
        pickUpLatitude: null,
        pickUpLongitude: null,
        pickUpAddress: '',
        mediaUrls: const [],
        createdAt: _base,
        updatedAt: _base,
      );
      expect(owner.listedMediaObjectIds, isEmpty);
      expect(
          owner
              .copyWith(listedMediaObjectIds: [_media(1)])
              .copyWith(name: 'n')
              .listedMediaObjectIds,
          [_media(1)]);
    });

    test('the saved lists keep the identity (M2-2)', () async {
      final root = Directory.systemTemp.createTempSync('m2_1_cache_');
      addTearDown(() async {
        await Hive.close();
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      Hive.init(root.path);
      EncryptedAccountListCache.debugStorageRoot = root.path;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final offer = OfferModel(
        id: _offers.id(1),
        userId: _alice,
        offerType: 'rent',
        selectedCity: '',
        selectedAreas: const [],
        location: '',
        phoneNumber: '',
        countryCode: '+971',
        minPrice: '',
        maxPrice: '',
        notes: '',
        specificPropertyType: '',
        rooms: 0,
        bathrooms: 0,
        pickUpLocation: '',
        pickUpLatitude: null,
        pickUpLongitude: null,
        pickUpAddress: '',
        uploadedFileName: '',
        createdAt: _base,
        updatedAt: _base,
        mediaUrls: const [],
        listedMediaObjectIds: [_media(1)],
      );
      const offers = OffersLocalCache();
      await offers.write(_alice, [offer]);
      final readOffer = (await offers.read(_alice))!.single;
      expect(readOffer.id, offer.id);
      expect(readOffer.listedMediaObjectIds, [_media(1)],
          reason: 'saved inside the authenticated payload since M2-2');
      final owner = OwnerModel(
        id: _owners.id(1),
        userId: _alice,
        name: '',
        phoneNumber: '',
        countryCode: '+971',
        typeOfProperties: '',
        propertyLocation: '',
        notes: '',
        pickUpLocation: '',
        pickUpLatitude: null,
        pickUpLongitude: null,
        pickUpAddress: '',
        mediaUrls: const [],
        createdAt: _base,
        updatedAt: _base,
        listedMediaObjectIds: [_media(1)],
      );
      const owners = OwnersLocalCache();
      await owners.write(_alice, [owner]);
      final readOwner = (await owners.read(_alice))!.single;
      expect(readOwner.id, owner.id);
      expect(readOwner.listedMediaObjectIds, [_media(1)]);
    });
  });

  test('measurements: requests and body bytes before/after (test VM)',
      () async {
    final lines = <String>[];
    for (final kind in [_offers, _owners]) {
      for (final (count, links) in [
        (500, 3),
        (1000, 3),
        (5000, 3),
        (5000, 10),
        (20000, 3)
      ]) {
        final h = await _Harness.start(kind);
        for (var n = 1; n <= count; n++) {
          h.server.rows.add(kind.row(n, links: [
            for (var i = 0; i < links; i++) _link(_media(n * 16 + i), i),
          ]));
        }
        final clock = Stopwatch()..start();
        final list = await _read(kind, h);
        final ms = clock.elapsedMilliseconds;
        // The same rows without the embedded links: the payload before M2-1.
        final before = h.server.bodyBytes -
            [
              for (final r in h.server.rows)
                utf8.encode(jsonEncode({kind.link: r[kind.link]})).length -
                    2 +
                    1
            ].fold<int>(0, (a, b) => a + b);
        expect(list, hasLength(count));
        lines.add('${kind.table} n=$count links=$links: '
            'requests=${h.server.reads.length} bodyAfter=${h.server.bodyBytes} '
            'bodyBefore≈$before growth=${h.server.bodyBytes - before} '
            'perRecord=${((h.server.bodyBytes - before) / count).toStringAsFixed(0)}B '
            'readMs=$ms');
      }
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });
}
