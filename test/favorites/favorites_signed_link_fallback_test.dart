// M3b-3 (tracker §7AZ, D-M3b3-1): a Favorites Offer card never uses the
// Worker's rotating signed R2 link as its `imageUrl`.
//
// Under Supabase an Offer's `mediaUrls` hold only the links the Worker signed
// for this read (`applyOfferMedia`). The card is normally built from the
// media ids and those links kept in memory (`FavoriteCardMedia.fromOffer`).
// When the links are no longer in memory (a link inside the 60-second safety
// margin, a session change clearing them), the card used to fall back to
// `imageUrl = mediaUrls.first` — a signed link that the card, the shared
// image builder and the grid's prefetch then key the old shared image cache
// by. Now:
//  - the card is drawn from what this device holds of exactly the items the
//    Worker just listed (mapping, previous copy, private cache — read only),
//    in the Worker's order, by their stable keys;
//  - with nothing held the card shows its icon (D-M3b3-1);
//  - an Offer with plain URLs and no media ids (the Firebase shape) keeps them;
//  - Worker calls, Owners and the other four types are unchanged.
//
// The real entity and media services run on a recording HTTP stand-in (as in
// favorites_request_count_test); Hive, files and the private image cache are
// real; the session scope is test-controlled. Waits are Completers the test
// opens, or a bounded poll for a condition — never a fixed sleep.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _sessionId = '11111111-1111-4111-8111-111111111111';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _uuid(String head) =>
    '$head-0000-4000-8000-${(++_n).toString().padLeft(12, '0')}';
String _offerId() => _uuid('20000000');
String _ownerId() => _uuid('30000000');
String _mediaId() => _uuid('dddddddd');

String _key(String media) =>
    offerMediaCacheKey(ownerId: _uid, mediaObjectId: media)!;

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

Map<String, dynamic> _row(String type, String id) {
  final common = <String, dynamic>{
    'id': id,
    'owner_id': _uid,
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

/// The recording stand-in for PostgREST and the media Worker.
class _Backend {
  final Map<String, List<Map<String, dynamic>>> rows = {};

  /// What the Worker lists per record: (media id, 'image' | 'video').
  final Map<String, List<(String, String)>> media = {};

  /// A non-200 Worker status per record.
  final Map<String, int> status = {};

  /// The lifetime the Worker states for its links. Under 60 s the app's
  /// in-memory link cache treats them as already expired.
  int expiresInSeconds = 600;

  final List<http.BaseRequest> rest = [];
  final List<http.BaseRequest> mediaCalls = [];
  final List<String> signedLinks = [];
  var _signatures = 0;

  void reset() {
    rows.clear();
    media.clear();
    status.clear();
    expiresInSeconds = 600;
    rest.clear();
    mediaCalls.clear();
    signedLinks.clear();
  }

  late final MockClient client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    if (url.host == 'media-api.brokerwallet.ae') {
      mediaCalls.add(request);
      final id = url.queryParameters['offerId'] ??
          url.queryParameters['ownerRecordId'] ??
          '';
      final code = status[id];
      if (code != null) {
        return http.Response('{"code":"denied"}', code,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final items = [
        for (final (mediaId, type) in media[id] ?? const <(String, String)>[])
          {
            'mediaObjectId': mediaId,
            // A fresh signature on every read, as R2 gives.
            'url': 'https://signed.example/$mediaId?X-Amz-Signature='
                '${++_signatures}',
            'mediaType': type,
          },
      ];
      for (final item in items) {
        signedLinks.add(item['url']!);
      }
      return http.Response(
          jsonEncode({'media': items, 'expiresInSeconds': expiresInSeconds}),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    if (url.host != 'unit-test.supabase.co') {
      throw StateError('unexpected host ${url.host}');
    }
    if (!url.path.startsWith('/rest/v1/')) {
      return http.Response('{}', 200, request: request);
    }
    rest.add(request);
    final table = url.pathSegments.last;
    final q = url.queryParameters;
    Iterable<Map<String, dynamic>> found = rows[table] ?? const [];
    final idFilter = q['id'];
    if (idFilter != null && idFilter.startsWith('in.(')) {
      final ids = idFilter
          .substring(4, idFilter.length - 1)
          .split(',')
          .map((v) => v.replaceAll('"', ''))
          .toSet();
      found = found.where((r) => ids.contains(r['id']));
    }
    return http.Response(jsonEncode(found.toList()), 200,
        headers: {'content-type': 'application/json'}, request: request);
  }
}

class _Favorites extends FavoriteService {
  _Favorites(this.metadata);

  final Map<String, List<FavoriteMetadata>> metadata;
  int metadataLoads = 0;
  final List<List<FavoriteItem>> saved = [];

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
  }) async {
    saved.add(List.of(favorites));
  }
}

/// The app's Offer service with its read-only held-media lookup counted, and
/// optionally held at a gate or answered by the test.
class _Offers extends OfferService {
  int lookups = 0;
  final List<List<String>> lookupIds = [];
  Completer<void>? gate;
  bool lookupDone = false;

  /// Replaces what the lookup returns (for a candidate list in a given
  /// order); null runs the real lookup.
  List<OfferMediaRef> Function(List<String> ids)? answer;

  /// Replaces the read by id (for a Firebase-shaped Offer).
  List<OfferModel>? plainOffers;

  @override
  Future<List<OfferMediaRef>> discoverHeldOfferMedia(
    String offerId, {
    required String ownerId,
    required List<String> ids,
  }) async {
    lookups++;
    lookupIds.add(List.of(ids));
    try {
      final wait = gate;
      if (wait != null) await wait.future;
      final fixed = answer;
      if (fixed != null) return fixed(ids);
      return await super
          .discoverHeldOfferMedia(offerId, ownerId: ownerId, ids: ids);
    } finally {
      lookupDone = true;
    }
  }

  @override
  Future<List<OfferModel>> getOffersByIds(
    List<String> offerIds, {
    bool Function()? stop,
  }) {
    final plain = plainOffers;
    if (plain != null) return Future.value(plain);
    return super.getOffersByIds(offerIds, stop: stop);
  }
}

class _Response implements FileServiceResponse {
  _Response(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  String get fileExtension => '.png';
  @override
  Stream<List<int>> get content => Stream.value(bytes);
  @override
  int? get contentLength => bytes.length;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 7));
  @override
  String? get eTag => null;
}

/// The private image cache's network: every download is counted.
class _Transport extends FileService {
  final List<String> urls = [];
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    return _Response(_png);
  }
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

/// A bounded poll for a condition the test cannot be told about directly.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 2000; i++) {
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

/// What the Favorites grid hands its prefetch: the first eight cards'
/// non-empty `imageUrl`s (favorites_view `_prefetchVisibleImages`).
List<String> _prefetched(List<FavoriteItem> cards) => [
      for (final card in cards.take(8))
        if (card.imageUrl case final url? when url.isNotEmpty) url,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = _Backend();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m3b3_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async {};
    await OfflineMediaService.instance.initialize();
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
      documents.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    backend.reset();
    OfflineMediaService.debugForgetDeletedAccounts();
    support = Directory.systemTemp.createTempSync('m3b3_support_');
    temp = Directory.systemTemp.createTempSync('m3b3_temp_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => support.path,
        'getTemporaryDirectory' => temp.path,
        'getApplicationDocumentsDirectory' => documents.path,
        _ => null,
      },
    );
    transport = _Transport();
    scope = const PrivateMediaScope(account: _uid, session: _sessionId);
    cache = PrivateMediaCache(currentScope: () => scope, transport: transport);
    PrivateMediaImages.cache = () => cache;
    await _signIn();
  });

  tearDown(() async {
    OfferMediaUrlCache.instance.clear();
    await cache.dispose().timeout(const Duration(seconds: 2), onTimeout: () {});
    PrivateMediaImages.cache = () => PrivateMediaCache.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    for (final dir in [support, temp]) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<T> recorded<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => backend.client);

  File file(String name) => File('${temp.path}${Platform.pathSeparator}$name')
    ..writeAsBytesSync(_png);

  Future<String> mapped(String media) async {
    final f = file('m-$media.png');
    await OfflineMediaService.instance
        .mapMediaIdToLocalFile(_key(media), f.path);
    return f.path;
  }

  Future<void> privateOnly(String media) async {
    final f = await cache.get(_key(media),
        signedUrl: () async => 'https://r2.example/x.png?X-Amz-Signature=s');
    expect(f, isNotNull);
    expect(OfflineMediaService.instance.getLocalFilePathForMediaId(_key(media)),
        isNull);
  }

  Future<void> poster(String media) async {
    final f = file('poster-$media.png');
    await OfflineMediaService.instance
        .mapMediaIdToLocalFile(offerMediaPosterKey(_key(media)), f.path);
  }

  Map<dynamic, dynamic> mappings() => Map.of(Hive.box('url_mapping').toMap());

  /// An Offer the Worker lists with [media] (id, kind).
  String offer(List<(String, String)> media) {
    final id = _offerId();
    (backend.rows['offers'] ??= []).add(_row('offers', id));
    backend.media[id] = media;
    return id;
  }

  /// Opens Favorites for [ids] with [offers] and waits for its first load.
  Future<(FavoritesViewModel, _Favorites)> open(
    Map<String, List<String>> ids,
    _Offers offers, {
    bool wait = true,
  }) async {
    final favorites = _Favorites(_metadata(ids));
    final vm = FavoritesViewModel(
      favoriteService: favorites,
      offerService: offers,
    );
    if (wait) {
      await _until(() => favorites.metadataLoads == 1 && !vm.isLoading);
    }
    return (vm, favorites);
  }

  /// Loads Favorites for [ids] and returns the cards shown.
  Future<List<FavoriteItem>> load(
    Map<String, List<String>> ids, {
    _Offers? offers,
  }) =>
      recorded(() async {
        final (vm, _) = await open(ids, offers ?? _Offers());
        final shown = List<FavoriteItem>.from(vm.favorites);
        vm.dispose();
        return shown;
      });

  FavoriteItem only(List<FavoriteItem> cards) {
    expect(cards, hasLength(1));
    return cards.single;
  }

  group('the links are still in memory: unchanged', () {
    test('the card is the Worker\'s photo with its link; no lookup', () async {
      final m = _mediaId();
      final id = offer([(m, 'image')]);
      final offers = _Offers();
      final card = only(await load({
        'offers': [id]
      }, offers: offers));
      expect(card.media?.cacheKey, _key(m));
      expect(card.media?.signedUrl, contains('X-Amz-Signature'));
      expect(card.imageUrl, isNull);
      expect(offers.lookups, 0);
      expect(backend.mediaCalls, hasLength(1));
    });
  });

  group('the links are no longer in memory (inside the safety margin)', () {
    setUp(() => backend.expiresInSeconds = 30);

    test('nothing held: the icon, never the rotating signed link', () async {
      final m = _mediaId();
      final id = offer([(m, 'image')]);
      final offers = _Offers();
      final card = only(await load({
        'offers': [id]
      }, offers: offers));
      expect(card.imageUrl, isNull,
          reason: 'was the signed link: an old-cache key that rotates');
      expect(card.media, isNull, reason: 'the card shows its icon');
      expect(_prefetched([card]), isEmpty, reason: 'no link to prefetch');
      expect(offers.lookups, 1);
      expect(offers.lookupIds.single, [m],
          reason: 'only the items the Worker just listed');
      expect(backend.mediaCalls, hasLength(1), reason: 'no extra Worker call');
      expect(transport.urls, isEmpty, reason: 'looking downloads nothing');
    });

    test('a photo held through its mapping is drawn by its stable key',
        () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      final before = mappings();
      final offers = _Offers();
      final card = only(await load({
        'offers': [id]
      }, offers: offers));
      expect(card.media?.cacheKey, _key(m));
      expect(card.media?.isVideo, isFalse);
      expect(card.media?.signedUrl, isNull, reason: 'held bytes, no link');
      expect(card.imageUrl, isNull);
      expect(transport.urls, isEmpty);
      expect(mappings(), before, reason: 'the lookup writes no mapping');
      expect(backend.mediaCalls, hasLength(1));
    });

    test('a photo held through the previous-copy fallback', () async {
      final m = _mediaId();
      final original = await mapped(m);
      final copy = file('copy-$m.png');
      expect(
          await OfflineMediaService.instance.replaceMediaIdMapping(_key(m),
              expected: original, replacement: copy.path, previous: original),
          isTrue);
      copy.deleteSync();
      final id = offer([(m, 'image')]);
      final card = only(await load({
        'offers': [id]
      }));
      expect(card.media?.cacheKey, _key(m));
      expect(card.imageUrl, isNull);
      expect(transport.urls, isEmpty);
    });

    test('a photo held only in the private cache, with no mapping', () async {
      final m = _mediaId();
      await privateOnly(m);
      transport.urls.clear();
      final id = offer([(m, 'image')]);
      final before = mappings();
      final card = only(await load({
        'offers': [id]
      }));
      expect(card.media?.cacheKey, _key(m));
      expect(card.media?.signedUrl, isNull);
      expect(card.imageUrl, isNull);
      expect(transport.urls, isEmpty, reason: 'no download to look');
      expect(mappings(), before);
    });

    test('links that change on every read never reach the card', () async {
      final m = _mediaId();
      final id = offer([(m, 'image')]);
      final first = only(await load({
        'offers': [id]
      }));
      final second = only(await load({
        'offers': [id]
      }));
      expect(backend.signedLinks.toSet(), hasLength(2),
          reason: 'the Worker signed afresh each time');
      for (final card in [first, second]) {
        expect(card.imageUrl, isNull);
        expect(backend.signedLinks.contains(card.media?.signedUrl), isFalse);
      }
      expect(backend.mediaCalls, hasLength(2), reason: 'one per open');
    });

    test('only items the Worker listed now, in its order', () async {
      final removed = _mediaId(), a = _mediaId(), b = _mediaId();
      final id = offer([(a, 'image'), (b, 'image')]);
      final offers = _Offers()
        // The lookup, following an older catalogue, offers a removed item
        // first and the current ones in another order.
        ..answer = (_) => [
              OfferMediaRef(
                  mediaObjectId: removed,
                  cacheKey: _key(removed),
                  localFilePath: '/held/removed.png'),
              OfferMediaRef(
                  mediaObjectId: b,
                  cacheKey: _key(b),
                  localFilePath: '/held/b.png'),
              OfferMediaRef(
                  mediaObjectId: a,
                  cacheKey: _key(a),
                  localFilePath: '/held/a.png'),
            ];
      final card = only(await load({
        'offers': [id]
      }, offers: offers));
      expect(card.media?.cacheKey, _key(a),
          reason: 'the removed item never; the Worker\'s first photo first');
    });

    test('a removed item still in the catalogue is never shown', () async {
      final removed = _mediaId(), current = _mediaId();
      await mapped(removed);
      final id = offer([(current, 'image')]);
      await OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _uid, offerId: id, mediaObjectIds: [removed]);
      final card = only(await load({
        'offers': [id]
      }));
      expect(card.media?.cacheKey == _key(removed), isFalse);
      expect(card.imageUrl, isNull);
    });

    test('a photo before a video frame; a video frame alone is its poster',
        () async {
      final v = _mediaId(), p = _mediaId();
      await poster(v);
      await mapped(p);
      final both = offer([(v, 'video'), (p, 'image')]);
      final v2 = _mediaId();
      await poster(v2);
      final videoOnly = offer([(v2, 'video')]);
      final v3 = _mediaId();
      final nothingHeld = offer([(v3, 'video')]);
      final cards = await load({
        'offers': [both, videoOnly, nothingHeld]
      });
      final byId = {for (final c in cards) c.id: c};
      expect(byId[both]!.media?.cacheKey, _key(p));
      expect(byId[both]!.media?.isVideo, isFalse);
      expect(byId[videoOnly]!.media?.isVideo, isTrue);
      expect(byId[videoOnly]!.media?.posterPath, isNotNull);
      expect(byId[videoOnly]!.media?.signedUrl, isNull,
          reason: 'no link: the video itself is never fetched');
      expect(byId[nothingHeld]!.media, isNull);
      for (final card in cards) {
        expect(card.imageUrl, isNull,
            reason: 'a video link is never drawn as a photo');
      }
      expect(transport.urls, isEmpty);
    });

    test('the saved copy keeps the stable key, never a link', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      late _Favorites favorites;
      await recorded(() async {
        final (vm, f) = await open({
          'offers': [id]
        }, _Offers());
        favorites = f;
        vm.dispose();
      });
      final saved = favorites.saved.last.single;
      expect(saved.media?.toStored(), jsonEncode({'k': _key(m), 'v': false}),
          reason: 'the same {"k","v"} identity the encrypted copy keeps');
      expect(saved.imageUrl, isNull);
    });

    test('no lookup, no link: a Worker 403 or 404 shows nothing held',
        () async {
      for (final code in [403, 404]) {
        final m = _mediaId();
        await mapped(m);
        final id = offer([(m, 'image')]);
        backend.status[id] = code;
        await OfflineMediaService.instance.writeOfferMediaCatalog(
            ownerId: _uid, offerId: id, mediaObjectIds: [m]);
        final offers = _Offers();
        final card = only(await load({
          'offers': [id]
        }, offers: offers));
        expect(card.media, isNull, reason: '$code');
        expect(card.imageUrl, isNull, reason: '$code');
        expect(offers.lookups, 0, reason: '$code: nothing to bring back');
        expect(
            OfflineMediaService.instance
                .readOfferMediaCatalog(ownerId: _uid, offerId: id),
            isEmpty,
            reason: '$code: the revocation emptied the catalogue');
      }
    });

    test(
        'FU-FAV-OFFER-MEDIA-FAILURE (open, unchanged): an ordinary Worker '
        'failure shows the icon and saves no card key', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.status[id] = 500;
      final offers = _Offers();
      late _Favorites favorites;
      await recorded(() async {
        final (vm, f) = await open({
          'offers': [id]
        }, offers);
        favorites = f;
        expect(vm.favorites.single.media, isNull);
        expect(vm.favorites.single.imageUrl, isNull);
        vm.dispose();
      });
      expect(offers.lookups, 0);
      expect(favorites.saved.last.single.media, isNull,
          reason: 'the existing behaviour, recorded, not changed here');
    });
  });

  group('accounts, sessions and screens that are gone', () {
    setUp(() => backend.expiresInSeconds = 30);

    Future<(FavoritesViewModel, _Favorites, _Offers)> openHeld(
        String id) async {
      final offers = _Offers()..gate = Completer<void>();
      final (vm, favorites) = await open({
        'offers': [id]
      }, offers, wait: false);
      await _until(() => offers.lookups == 1);
      return (vm, favorites, offers);
    }

    test('another account during the lookup: nothing is published', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await recorded(() async {
        final (vm, favorites, offers) = await openHeld(id);
        await FavoriteService.invalidateForAccountChange();
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        await pumpEventQueue();
        expect(vm.favorites, isEmpty);
        expect(favorites.saved, isEmpty, reason: 'nor cached');
        vm.dispose();
      });
    });

    test('another account during a lookup: the next Offers are not looked up',
        () async {
      final first = offer([(_mediaId(), 'image')]);
      final second = offer([(_mediaId(), 'image')]);
      await recorded(() async {
        final offers = _Offers()..gate = Completer<void>();
        final (vm, favorites) = await open({
          'offers': [first, second]
        }, offers, wait: false);
        await _until(() => offers.lookups == 1);
        await FavoriteService.invalidateForAccountChange();
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        await pumpEventQueue();
        expect(offers.lookups, 1,
            reason: 'the old account\'s device is not read for the rest');
        expect(vm.favorites, isEmpty);
        expect(favorites.saved, isEmpty);
        vm.dispose();
      });
    });

    test('the session is replaced during the lookup: nothing held is shown',
        () async {
      final m = _mediaId(), p = _mediaId();
      await mapped(m);
      await privateOnly(p);
      final id = offer([(p, 'image'), (m, 'image')]);
      await recorded(() async {
        final (vm, _, offers) = await openHeld(id);
        scope = null; // the authorized session is gone
        offers.gate!.complete();
        await _until(() => !vm.isLoading);
        expect(vm.favorites.single.media, isNull);
        expect(vm.favorites.single.imageUrl, isNull);
        vm.dispose();
      });
    });

    test('signed out during the lookup: nothing held is shown', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await recorded(() async {
        final (vm, favorites, offers) = await openHeld(id);
        await sb.Supabase.instance.client.auth
            .signOut()
            .catchError((Object _) {});
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        await pumpEventQueue();
        for (final card in vm.favorites) {
          expect(card.media, isNull);
          expect(card.imageUrl, isNull);
        }
        vm.dispose();
      });
    });

    test('after Delete Account cleanup nothing held comes back', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await OfflineMediaService.instance.forgetOfferMedia(ownerId: _uid);
      scope = null; // the deleted account has no session
      final card = only(await load({
        'offers': [id]
      }));
      expect(card.media, isNull);
      expect(card.imageUrl, isNull);
    });

    test('the screen closes during the lookup: nothing is published', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await recorded(() async {
        final (vm, favorites, offers) = await openHeld(id);
        vm.dispose();
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        await pumpEventQueue();
        expect(favorites.saved, isEmpty);
      });
    });
  });

  group('everything else is unchanged', () {
    test('a Firebase-shaped Offer (plain URLs, no media ids) keeps its URL',
        () async {
      final id = _offerId();
      const plain = 'https://firebasestorage.example/o/photo.jpg';
      final offers = _Offers()
        ..plainOffers = [
          OfferModel(
            id: id,
            userId: _uid,
            offerType: 'rent',
            selectedCity: 'Dubai',
            selectedAreas: const ['Marina'],
            location: '',
            phoneNumber: '500000000',
            countryCode: '+971',
            minPrice: '',
            maxPrice: '',
            squareFootage: '',
            notes: '',
            propertyType: null,
            specificPropertyType: 'Offer',
            rooms: 0,
            bathrooms: 0,
            pickUpLocation: '',
            pickUpLatitude: null,
            pickUpLongitude: null,
            pickUpAddress: '',
            uploadedFileName: '',
            createdAt: DateTime.utc(2026, 11, 1),
            updatedAt: DateTime.utc(2026, 11, 1),
            mediaUrls: const [plain],
          ),
        ];
      final card = only(await load({
        'offers': [id]
      }, offers: offers));
      expect(card.imageUrl, plain);
      expect(card.media, isNull);
      expect(offers.lookups, 0);
    });

    test('Owners: the Worker\'s media as before, never an imageUrl', () async {
      backend.expiresInSeconds = 30;
      final m = _mediaId();
      final id = _ownerId();
      (backend.rows['owners'] ??= []).add(_row('owners', id));
      backend.media[id] = [(m, 'image')];
      final offers = _Offers();
      final card = only(await load({
        'owners': [id]
      }, offers: offers));
      expect(card.media?.cacheKey, _key(m));
      expect(card.media?.signedUrl, contains('X-Amz-Signature'),
          reason: 'Owners take the link from the answer itself, unchanged');
      expect(card.imageUrl, isNull);
      expect(offers.lookups, 0);
      expect(backend.mediaCalls, hasLength(1));
    });

    test('Requests, Offices, Brokers and Watchmen: no media, no lookup',
        () async {
      backend.expiresInSeconds = 30;
      final ids = <String, List<String>>{};
      for (final (type, head) in [
        ('requests', '10000000'),
        ('offices', '40000000'),
        ('brokers', '50000000'),
        ('watchmen', '60000000'),
      ]) {
        final id = _uuid(head);
        (backend.rows[type] ??= []).add(_row(type, id));
        ids[type] = [id];
      }
      final offers = _Offers();
      final cards = await load(ids, offers: offers);
      expect(cards, hasLength(4));
      for (final card in cards) {
        expect(card.media, isNull, reason: card.type);
        expect(card.imageUrl, isNull, reason: card.type);
      }
      expect(offers.lookups, 0);
      expect(backend.mediaCalls, isEmpty);
    });

    test('ten Offers: one Worker call each, no link anywhere on a card',
        () async {
      backend.expiresInSeconds = 30;
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        final m = _mediaId();
        if (i.isEven) await mapped(m);
        ids.add(offer([(m, 'image')]));
      }
      final offers = _Offers();
      final cards = await load({'offers': ids}, offers: offers);
      expect(cards, hasLength(10));
      expect(backend.mediaCalls, hasLength(10));
      expect(offers.lookups, 10);
      expect(cards.where((c) => c.media != null), hasLength(5));
      expect(cards.where((c) => c.media == null), hasLength(5),
          reason: 'the icon where nothing is held');
      expect(_prefetched(cards), isEmpty);
      expect(cards.where((c) => c.imageUrl != null), isEmpty);
      expect(transport.urls, isEmpty);
    });

    test('the view model never hands a private link to imageUrl', () {
      final source =
          File('lib/src/views/Screens/home/favorites/favorites_viewmodel.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n')
              .replaceAll(RegExp(r'\s+'), ' ');
      expect(
          source.contains('imageUrl: media == null && '
              'offer.mediaObjectIds.isEmpty && '
              'offer.mediaUrls.isNotEmpty ? offer.mediaUrls.first : null,'),
          isTrue);
      expect(source.contains('_offerService.discoverHeldOfferMedia('), isTrue);
      expect(source.contains('resolveOfferMedia('), isFalse,
          reason: 'no new Worker call from the view model');
    });
  });
}
