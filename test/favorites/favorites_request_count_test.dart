// P3.4 (tracker §7AH): the requests Favorites sends to load the cards, with
// the real entity services and media service on a recording HTTP stand-in.
// Nothing reaches a real host: Supabase is initialized with the recorder,
// and every `http.Client()` the media service creates comes from it too.
//
// The favorites metadata (which ids are favorites) comes from a fake here;
// its own six requests are measured in favorites_metadata_requests_test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/bounded_tasks.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _otherUid = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _sessionId = '11111111-1111-4111-8111-111111111111';

String _id(String type, int n) {
  const prefix = {
    'requests': '1',
    'offers': '2',
    'owners': '3',
    'offices': '4',
    'brokers': '5',
    'watchmen': '6',
  };
  return '${prefix[type]}0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
}

const _types = [
  'requests',
  'offers',
  'owners',
  'offices',
  'brokers',
  'watchmen',
];

String _fakeJwt() {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({
        'sub': _uid,
        'session_id': _sessionId,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
      })}.sig';
}

Map<String, dynamic> _row(String type, String id, {String owner = _uid}) {
  final common = <String, dynamic>{
    'id': id,
    'owner_id': owner,
    'phone_number': '500000000',
    'country_code': '+971',
    'notes': '',
    'created_at': '2026-11-01T10:00:00Z',
    'updated_at': '2026-11-01T10:00:00Z',
    'deleted_at': null,
  };
  switch (type) {
    case 'requests':
      return {
        ...common,
        'request_type': 'rent',
        'selected_city': 'Dubai',
        'specific_property_type': 'Request $id',
        'request_areas': [
          {'area': 'Marina', 'ordinal': 0},
        ],
      };
    case 'offers':
      return {
        ...common,
        'offer_type': 'rent',
        'selected_city': 'Dubai',
        'specific_property_type': 'Offer $id',
        'offer_areas': [
          {'area': 'Marina', 'ordinal': 0},
        ],
      };
    case 'owners':
      return {...common, 'name': 'Owner $id', 'property_type_text': 'Villa'};
    case 'offices':
      return {...common, 'office_name': 'Office $id', 'manager_name': 'M'};
    case 'brokers':
      return {...common, 'name': 'Broker $id'};
    case 'watchmen':
      return {...common, 'name': 'Watchman $id', 'building_name': 'B'};
  }
  throw ArgumentError(type);
}

/// The recording stand-in for PostgREST and the media Worker. Rows are
/// filtered the way the server would for this account: by `id`, `owner_id`
/// and `deleted_at`.
class _Backend {
  final Map<String, List<Map<String, dynamic>>> rows = {
    for (final type in _types) type: [],
  };

  /// Media per record id, as the Worker lists it.
  final Map<String, List<Map<String, dynamic>>> media = {};

  /// Tables whose reads fail with a 500.
  final Set<String> failingTables = {};

  final List<http.BaseRequest> rest = [];
  final List<http.BaseRequest> mediaCalls = [];
  int _restInFlight = 0;
  int _mediaInFlight = 0;
  int maxRestInFlight = 0;
  int maxMediaInFlight = 0;

  /// When set, every table read waits for it before answering.
  Completer<void>? restGate;

  /// Media reads fail with a 500.
  bool failingMedia = false;

  /// When set, every media read waits for it before answering.
  Completer<void>? mediaGate;

  void reset() {
    for (final list in rows.values) {
      list.clear();
    }
    media.clear();
    failingTables.clear();
    restGate = null;
    failingMedia = false;
    mediaGate = null;
    rest.clear();
    mediaCalls.clear();
    maxRestInFlight = 0;
    maxMediaInFlight = 0;
  }

  late final MockClient client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    if (url.host == 'media-api.brokerwallet.ae') {
      mediaCalls.add(request);
      _mediaInFlight++;
      if (_mediaInFlight > maxMediaInFlight) maxMediaInFlight = _mediaInFlight;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final gate = mediaGate;
      if (gate != null) await gate.future;
      _mediaInFlight--;
      if (failingMedia) {
        return http.Response('{"code":"unavailable"}', 500,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final id = url.queryParameters['offerId'] ??
          url.queryParameters['ownerRecordId'] ??
          '';
      return http.Response(
          jsonEncode({'media': media[id] ?? [], 'expiresInSeconds': 600}), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }
    if (url.host != 'unit-test.supabase.co') {
      throw StateError('unexpected host ${url.host}');
    }
    if (!url.path.startsWith('/rest/v1/')) {
      return http.Response('{}', 200, request: request);
    }
    rest.add(request);
    _restInFlight++;
    if (_restInFlight > maxRestInFlight) maxRestInFlight = _restInFlight;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    _restInFlight--;
    final gate = restGate;
    if (gate != null) await gate.future;
    final table = url.pathSegments.last;
    if (failingTables.contains(table)) {
      return http.Response('{"message":"unavailable"}', 500,
          headers: {'content-type': 'application/json'}, request: request);
    }
    final q = url.queryParameters;
    Iterable<Map<String, dynamic>> found = rows[table] ?? const [];
    final idFilter = q['id'];
    if (idFilter != null) {
      final ids = idFilter.startsWith('eq.')
          ? {idFilter.substring(3)}
          : idFilter
              .substring(4, idFilter.length - 1)
              .split(',')
              .map((v) => v.replaceAll('"', ''))
              .toSet();
      found = found.where((r) => ids.contains(r['id']));
    }
    final owner = q['owner_id'];
    if (owner != null) {
      found = found.where((r) => 'eq.${r['owner_id']}' == owner);
    }
    if (q['deleted_at'] == 'is.null') {
      found = found.where((r) => r['deleted_at'] == null);
    }
    // The server's order is not the favorites' order: answer backwards.
    return http.Response(jsonEncode(found.toList().reversed.toList()), 200,
        headers: {'content-type': 'application/json'}, request: request);
  }
}

class _Favorites extends FavoriteService {
  _Favorites(this.metadata);

  final Map<String, List<FavoriteMetadata>> metadata;
  int metadataLoads = 0;

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> initializeCache({String? uidOverride}) async {}

  @override
  List<FavoriteItem> getCachedFavoritesSync() => const [];

  @override
  Future<Map<String, List<FavoriteMetadata>>>
      getAllFavoritesWithMetadata() async {
    metadataLoads++;
    return metadata;
  }

  @override
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {}
}

Map<String, List<FavoriteMetadata>> _metadata(Map<String, List<String>> ids) {
  var minute = 0;
  return {
    for (final entry in ids.entries)
      entry.key: [
        for (final id in entry.value)
          FavoriteMetadata(
            itemId: id,
            type: entry.key,
            addedAt: DateTime.utc(2026, 11, 1, 12, minute++),
          ),
      ],
  };
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition not reached');
}

Future<void> _signIn() =>
    sb.Supabase.instance.client.auth.setInitialSession(jsonEncode({
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
        'email': 'favorites@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = _Backend();

  late Directory hiveDir;
  setUpAll(() async {
    // The media service remembers each record's media ids on this device.
    hiveDir = Directory.systemTemp.createTempSync('favorites_requests_');
    Hive.init(hiveDir.path);
    // The image cache it warms keeps its files in the temporary directory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => hiveDir.path,
    );
    SharedPreferences.setMockInitialValues({});
    await sb.Supabase.initialize(
      url: 'https://unit-test.supabase.co',
      publishableKey: 'unit-test-publishable-key',
      httpClient: backend.client,
      authOptions: const sb.FlutterAuthClientOptions(
        localStorage: sb.EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    backend.reset();
    await _signIn();
  });
  tearDown(OfferMediaUrlCache.instance.clear);

  /// Runs [body] with every HTTP client created inside it answered by the
  /// recorder (the media service creates its own).
  Future<T> recorded<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => backend.client);

  /// Opens Favorites with these favorites and waits for its first load.
  Future<FavoritesViewModel> open(
      Map<String, List<FavoriteMetadata>> metadata) async {
    final favorites = _Favorites(metadata);
    final vm = FavoritesViewModel(favoriteService: favorites);
    await _until(() => favorites.metadataLoads == 1 && !vm.isLoading);
    return vm;
  }

  /// Loads Favorites for [ids] and returns the cards shown.
  Future<List<FavoriteItem>> load(Map<String, List<String>> ids) =>
      recorded(() async {
        final vm = await open(_metadata(ids));
        final shown = List<FavoriteItem>.from(vm.favorites);
        vm.dispose();
        return shown;
      });

  void seed(String type, int count, {bool withMedia = false}) {
    for (var n = 1; n <= count; n++) {
      final id = _id(type, n);
      backend.rows[type]!.add(_row(type, id));
      if (withMedia) {
        backend.media[id] = [
          {
            'mediaObjectId': 'm-$id',
            'url': 'https://signed.example/$id',
            'mediaType': 'image',
          },
        ];
      }
    }
  }

  List<String> ids(String type, int count) =>
      [for (var n = 1; n <= count; n++) _id(type, n)];

  Set<String> idsAsked(http.BaseRequest r) {
    final filter = r.url.queryParameters['id']!;
    expect(filter, startsWith('in.('));
    return filter
        .substring(4, filter.length - 1)
        .split(',')
        .map((id) => id.replaceAll('"', ''))
        .toSet();
  }

  test(
      'each type is one request with the single read\'s owner, deletion and '
      'column filters, for exactly the favorite ids', () async {
    for (final type in _types) {
      seed(type, 2);
    }
    final shown = await load({for (final type in _types) type: ids(type, 2)});
    expect(shown, hasLength(12));
    expect(backend.rest, hasLength(6));
    expect(backend.maxRestInFlight, 6,
        reason: 'the six types are read together');

    final batchSelect = <String, String?>{};
    for (final r in backend.rest) {
      final table = r.url.pathSegments.last;
      final q = r.url.queryParameters;
      expect(r.method, 'GET', reason: table);
      expect(q['owner_id'], 'eq.$_uid', reason: table);
      expect(q['deleted_at'], 'is.null', reason: table);
      expect(idsAsked(r), ids(table, 2).toSet(), reason: table);
      expect(q.keys.toSet(), {'select', 'owner_id', 'id', 'deleted_at'},
          reason: '$table: no limit, order or range');
      batchSelect[table] = q['select'];
    }

    // The single-record reads, for their columns.
    backend.rest.clear();
    await recorded(() async {
      final core =
          SupabaseCoreEntitiesService(client: sb.Supabase.instance.client);
      await core.getRequest(_id('requests', 1));
      await core.getOfferMetadata(_id('offers', 1));
      await core.getOwner(_id('owners', 1));
      await core.getOffice(_id('offices', 1));
      await core.getBroker(_id('brokers', 1));
      await core.getWatchman(_id('watchmen', 1));
    });
    for (final r in backend.rest) {
      final table = r.url.pathSegments.last;
      expect(batchSelect[table], r.url.queryParameters['select'],
          reason: '$table: the same columns as its single read');
    }
  });

  test('request counts: none, one, many of one type, all six types', () async {
    expect(await load({}), isEmpty);
    expect(backend.rest, isEmpty);
    expect(backend.mediaCalls, isEmpty);

    backend.reset();
    seed('offers', 1, withMedia: true);
    expect(await load({'offers': ids('offers', 1)}), hasLength(1));
    expect(backend.rest, hasLength(1));
    expect(backend.mediaCalls, hasLength(1));

    backend.reset();
    seed('requests', 10);
    expect(await load({'requests': ids('requests', 10)}), hasLength(10));
    expect(backend.rest, hasLength(1), reason: 'was 10, one after another');

    backend.reset();
    for (final type in _types) {
      seed(type, 2, withMedia: type == 'offers' || type == 'owners');
    }
    expect(await load({for (final type in _types) type: ids(type, 2)}),
        hasLength(12));
    expect(backend.rest, hasLength(6), reason: 'was 12');
    expect(backend.mediaCalls, hasLength(4), reason: '2 Offers + 2 Owners');
  });

  test(
      'media is still one Worker call per Offer and per Owner, at most '
      '$mediaReadsAtOnce at a time, and every card keeps its media', () async {
    seed('offers', 10, withMedia: true);
    final offers = await load({'offers': ids('offers', 10)});
    expect(backend.rest, hasLength(1));
    expect(backend.mediaCalls, hasLength(10));
    expect(mediaReadsAtOnce, 4);
    expect(backend.maxMediaInFlight, inInclusiveRange(2, 4),
        reason: 'was 1: Offers were read one after another');
    for (final card in offers) {
      expect(card.media?.cacheKey, isNotNull, reason: card.id);
      expect(
          (card.originalData as OfferModel).mediaObjectIds, ['m-${card.id}']);
    }

    backend.reset();
    seed('owners', 10, withMedia: true);
    final owners = await load({'owners': ids('owners', 10)});
    expect(backend.rest, hasLength(1));
    expect(backend.mediaCalls, hasLength(10));
    expect(backend.maxMediaInFlight, inInclusiveRange(2, 4),
        reason: 'was 10 at once: no limit');
    for (final card in owners) {
      expect(card.media?.cacheKey, isNotNull, reason: card.id);
    }
  });

  test('an Offer whose media cannot be read is still listed, without media',
      () async {
    seed('offers', 2, withMedia: true);
    backend.failingMedia = true;
    final shown = await load({'offers': ids('offers', 2)});
    expect(shown.map((c) => c.id).toSet(), ids('offers', 2).toSet());
    expect(shown.every((c) => c.media == null), isTrue);
  });

  test(
      'cards keep the favorites\' order whatever order the server answers '
      'in, ties included', () async {
    seed('offers', 3);
    seed('requests', 2);
    final same = DateTime.utc(2026, 11, 1, 12);
    final metadata = {
      'offers': [
        for (final id in ids('offers', 3))
          FavoriteMetadata(itemId: id, type: 'offers', addedAt: same),
      ],
      'requests': [
        FavoriteMetadata(
            itemId: _id('requests', 1),
            type: 'requests',
            addedAt: DateTime.utc(2026, 11, 2)),
        FavoriteMetadata(
            itemId: _id('requests', 2),
            type: 'requests',
            addedAt: DateTime.utc(2026, 10, 30)),
      ],
    };
    final shown = await recorded(() async {
      final vm = await open(metadata);
      final cards = List<FavoriteItem>.from(vm.favorites);
      vm.dispose();
      return cards;
    });
    expect(shown.map((c) => c.id), [
      _id('requests', 1),
      ...ids('offers', 3),
      _id('requests', 2),
    ]);
  });

  test(
      'missing, deleted and other-account records have no card; the other '
      'favorites are unaffected', () async {
    seed('offers', 2);
    seed('requests', 1);
    backend.rows['offers']!.add({
      ..._row('offers', _id('offers', 3)),
      'deleted_at': '2026-11-02T00:00:00Z',
    });
    backend.rows['offers']!
        .add(_row('offers', _id('offers', 4), owner: _otherUid));
    final shown = await load({
      'offers': ids('offers', 5),
      'requests': ids('requests', 1),
    });
    expect(shown.map((c) => c.id).toSet(),
        {_id('offers', 1), _id('offers', 2), _id('requests', 1)});
    expect(backend.rest, hasLength(2));
  });

  test(
      '250 favorites of one type are read 100 ids at a time and every one '
      'is shown', () async {
    seed('brokers', 250);
    final shown = await load({'brokers': ids('brokers', 250)});
    expect(shown, hasLength(250));
    expect(backend.rest, hasLength(3));
    final asked = [for (final r in backend.rest) idsAsked(r)];
    expect(asked.map((s) => s.length), [100, 100, 50]);
    expect(asked.expand((s) => s).toSet(), ids('brokers', 250).toSet());
  });

  test(
      'a type that cannot be read keeps the cards already shown for it; the '
      'other types still refresh', () async {
    seed('offers', 2);
    seed('requests', 1);
    await recorded(() async {
      final vm = await open(_metadata(
          {'offers': ids('offers', 2), 'requests': ids('requests', 1)}));
      expect(vm.favorites, hasLength(3));

      backend.failingTables.add('offers');
      backend.rows['requests']!.first['specific_property_type'] = 'Renamed';
      await vm.refresh();

      final byId = {for (final c in vm.favorites) c.id: c};
      expect(byId.keys.toSet(),
          {_id('offers', 1), _id('offers', 2), _id('requests', 1)},
          reason: 'a failed read is not an empty one');
      expect(byId[_id('requests', 1)]!.title, 'Renamed');
      vm.dispose();
    });
  });

  test('on a first load, a type that cannot be read is left out alone',
      () async {
    seed('offers', 2);
    seed('requests', 1);
    backend.failingTables.add('offers');
    final shown = await load(
        {'offers': ids('offers', 2), 'requests': ids('requests', 1)});
    expect(shown.map((c) => c.id), [_id('requests', 1)]);
  });

  test('an account change during the read publishes and notifies nothing',
      () async {
    seed('offers', 2);
    backend.restGate = Completer<void>();
    await recorded(() async {
      final favorites = _Favorites(_metadata({'offers': ids('offers', 2)}));
      final vm = FavoritesViewModel(favoriteService: favorites);
      var notified = 0;
      vm.addListener(() => notified++);
      await _until(() => backend.rest.isNotEmpty);
      notified = 0; // the "loading" notice, sent before the change

      await FavoriteService.invalidateForAccountChange();
      backend.restGate!.complete();
      await _until(() => backend.mediaCalls.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(vm.favorites, isEmpty);
      expect(notified, 0);
      vm.dispose();
    });
  });

  test('records answered after the signed-in account changed are refused',
      () async {
    seed('requests', 1);
    backend.restGate = Completer<void>();
    await recorded(() async {
      final core =
          SupabaseCoreEntitiesService(client: sb.Supabase.instance.client);
      final read = core.getRequestsByIds(ids('requests', 1));
      await _until(() => backend.rest.isNotEmpty);
      await sb.Supabase.instance.client.auth.signOut();
      backend.restGate!.complete();
      await expectLater(read, throwsA(isA<StateError>()));
    });
  });

  test(
      'Offers and Owners loading together run at most 4 media reads each '
      '(8 in all)', () async {
    seed('offers', 10, withMedia: true);
    seed('owners', 10, withMedia: true);
    final shown =
        await load({'offers': ids('offers', 10), 'owners': ids('owners', 10)});
    expect(shown, hasLength(20));
    expect(backend.mediaCalls, hasLength(20));
    expect(backend.maxMediaInFlight, inInclusiveRange(5, 8),
        reason: 'the limit is per type: 4 Offers + 4 Owners');
  });

  test('closing the screen during the read starts no media read', () async {
    seed('offers', 10, withMedia: true);
    seed('owners', 10, withMedia: true);
    backend.restGate = Completer<void>();
    await recorded(() async {
      final favorites = _Favorites(_metadata(
          {'offers': ids('offers', 10), 'owners': ids('owners', 10)}));
      final vm = FavoritesViewModel(favoriteService: favorites);
      await _until(() => backend.rest.isNotEmpty);
      vm.dispose();
      backend.restGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.mediaCalls, isEmpty);
    });
  });

  test(
      'closing the screen while media is being read starts no further media '
      'read, for Offers and for Owners', () async {
    seed('offers', 10, withMedia: true);
    seed('owners', 10, withMedia: true);
    backend.mediaGate = Completer<void>();
    await recorded(() async {
      final favorites = _Favorites(_metadata(
          {'offers': ids('offers', 10), 'owners': ids('owners', 10)}));
      final vm = FavoritesViewModel(favoriteService: favorites);
      await _until(() => backend.mediaCalls.length == 8);
      vm.dispose();
      backend.mediaGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(backend.mediaCalls, hasLength(8),
          reason: 'the 4 + 4 already running finish; none starts after');
    });
  });
}
