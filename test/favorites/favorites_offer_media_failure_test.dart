// FU-FAV-OFFER-MEDIA-FAILURE, Option B (tracker §7AZ, D-FOMF-1..5): a
// Favorites Offer card keeps the photo this device already holds when the
// Worker's media read fails for a temporary reason, and its encrypted saved
// card key is not overwritten with nothing.
//
// The media read of each Offer now carries an explicit outcome
// (`DisplayMediaOutcome`): resolved, a temporary failure, or refused. Only a
// temporary failure (timeout, no connection, 5xx, 503, a body that is not
// JSON) falls back to what this device holds — through the existing read-only
// lookup, with the device catalogue first, else the saved ids this same read
// listed, else the card key this account saved — and never with a link, a
// download or another Worker request. A refused read (401, any 403, any 404)
// shows nothing held (D-FOMF-2, D-FOMF-3). A successful answer, even an
// empty one, is the authority as before.
//
// Option C is NOT part of this checkpoint: the shared media client still
// treats a 403 `session_superseded`, a 404 without its not-found code and a
// 200 without a media list as it did (tests below record that, marked
// OPTION C OPEN), so D-FOMF-2/3/4 are not resolved here.
//
// The real entity and media services run on a recording HTTP stand-in; Hive,
// files and the private image cache are real; the session scope is
// test-controlled. Waits are Completers the test opens, or a bounded poll for
// a condition — never a fixed sleep.
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
import 'package:broker_wallet/src/views/Screens/home/favorites/favorite_card_media.dart';
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
const _other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
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

String _key(String media, {String account = _uid}) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

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

Map<String, dynamic> _row(String type, String id, {List<String>? listed}) {
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
  final embed = [
    for (var i = 0; i < (listed ?? const <String>[]).length; i++)
      {
        'media_id': listed![i],
        'ordinal': i,
        'media_objects': {'status': 'ready', 'content_type': 'image/jpeg'},
      },
  ];
  switch (type) {
    case 'offers':
      return {
        ...common,
        'offer_type': 'rent',
        'selected_city': 'Dubai',
        'specific_property_type': 'Offer $id',
        'offer_areas': [
          {'area': 'Marina', 'ordinal': 0},
        ],
        'offer_media': embed,
      };
    case 'owners':
      return {
        ...common,
        'name': 'Owner $id',
        'property_type_text': 'Villa',
        'owner_media': embed,
      };
  }
  throw ArgumentError(type);
}

/// How a Worker media read ends in the stand-in.
enum _Ends { answer, timeout, offline }

/// The recording stand-in for PostgREST and the media Worker.
class _Backend {
  final Map<String, List<Map<String, dynamic>>> rows = {};

  /// What the Worker lists per record: (media id, 'image' | 'video').
  final Map<String, List<(String, String)>> media = {};

  /// A non-200 answer per record: (status, body).
  final Map<String, (int, String)> refusal = {};

  /// A 200 answer whose body is given as is, per record.
  final Map<String, String> rawBody = {};

  /// A transport failure per record.
  final Map<String, _Ends> ends = {};

  /// When set, every media read waits for it before answering.
  Completer<void>? mediaGate;

  final List<http.BaseRequest> mediaCalls = [];
  var _signatures = 0;

  void reset() {
    rows.clear();
    media.clear();
    refusal.clear();
    rawBody.clear();
    ends.clear();
    mediaGate = null;
    mediaCalls.clear();
  }

  late final MockClient client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    if (url.host == 'media-api.brokerwallet.ae') {
      mediaCalls.add(request);
      final gate = mediaGate;
      if (gate != null) await gate.future;
      final id = url.queryParameters['offerId'] ??
          url.queryParameters['ownerRecordId'] ??
          '';
      switch (ends[id]) {
        case _Ends.timeout:
          throw TimeoutException('no answer');
        case _Ends.offline:
          throw const SocketException('offline');
        case _Ends.answer:
        case null:
          break;
      }
      final refused = refusal[id];
      if (refused != null) {
        return http.Response(refused.$2, refused.$1,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final raw = rawBody[id];
      if (raw != null) {
        return http.Response(raw, 200,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final items = [
        for (final (mediaId, type) in media[id] ?? const <(String, String)>[])
          {
            'mediaObjectId': mediaId,
            'url': 'https://signed.example/$mediaId?X-Amz-Signature='
                '${++_signatures}',
            'mediaType': type,
          },
      ];
      return http.Response(
          jsonEncode({'media': items, 'expiresInSeconds': 600}), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }
    if (url.host != 'unit-test.supabase.co') {
      throw StateError('unexpected host ${url.host}');
    }
    if (!url.path.startsWith('/rest/v1/')) {
      return http.Response('{}', 200, request: request);
    }
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
  _Favorites(this.metadata, {this.cached = const []});

  final Map<String, List<FavoriteMetadata>> metadata;

  /// This account's saved copy, as the screen shows it first.
  final List<FavoriteItem> cached;

  /// The favorites list cannot be read (offline reopening).
  bool metadataThrows = false;

  int metadataLoads = 0;
  final List<List<FavoriteItem>> saved = [];

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> initializeCache({String? uidOverride}) async {}

  @override
  List<FavoriteItem> getCachedFavoritesSync() => cached;

  @override
  Future<Map<String, List<FavoriteMetadata>>>
      getAllFavoritesWithMetadata() async {
    metadataLoads++;
    if (metadataThrows) throw const SocketException('offline');
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
/// optionally held at a gate.
class _Offers extends OfferService {
  int lookups = 0;
  final List<List<String>> lookupIds = [];
  Completer<void>? gate;
  bool lookupDone = false;

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

/// The saved card of an Offer, as this account's encrypted copy restores it.
FavoriteItem _savedCard(String offerId, String? mediaId,
        {bool video = false, String account = _uid}) =>
    FavoriteItem(
      id: offerId,
      type: 'offers',
      title: 'Offer $offerId',
      subtitle: 'Dubai',
      media: mediaId == null
          ? null
          : FavoriteCardMedia(
              cacheKey: _key(mediaId, account: account), isVideo: video),
      addedAt: DateTime.utc(2026, 11, 1, 12),
    );

String? _stored(FavoriteItem card) => card.media?.toStored();

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
    documents = Directory.systemTemp.createTempSync('fomf_docs_');
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
    support = Directory.systemTemp.createTempSync('fomf_support_');
    temp = Directory.systemTemp.createTempSync('fomf_temp_');
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

  Future<void> catalogue(String record, List<String> ids) =>
      OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _uid, offerId: record, mediaObjectIds: ids);

  List<String> catalogued(String record) => OfflineMediaService.instance
      .readOfferMediaCatalog(ownerId: _uid, offerId: record);

  /// An Offer the Worker lists with [media]; [listed] is what its row's
  /// media identity embed lists (the saved list's `listedMediaObjectIds`).
  String offer(List<(String, String)> media, {List<String>? listed}) {
    final id = _offerId();
    (backend.rows['offers'] ??= []).add(_row('offers', id, listed: listed));
    backend.media[id] = media;
    return id;
  }

  /// Opens Favorites for [ids] with the account's saved copy [cached] and
  /// waits until it has published (and saved) its first server answer.
  Future<(FavoritesViewModel, _Favorites)> open(
    Map<String, List<String>> ids,
    _Offers offers, {
    List<FavoriteItem> cached = const [],
    bool wait = true,
  }) async {
    final favorites = _Favorites(_metadata(ids), cached: cached);
    final vm = FavoritesViewModel(
      favoriteService: favorites,
      offerService: offers,
    );
    if (wait) await _until(() => favorites.saved.isNotEmpty);
    return (vm, favorites);
  }

  /// Opens Favorites for one Offer whose saved card is [saved] and returns
  /// the card shown and the card saved.
  Future<(FavoriteItem, FavoriteItem, _Offers)> refresh(
    String id,
    FavoriteItem saved, {
    _Offers? offers,
  }) =>
      recorded(() async {
        final service = offers ?? _Offers();
        final (vm, favorites) = await open(
            {
              'offers': [id]
            },
            service,
            cached: [saved]);
        final shown = vm.favorites.single;
        vm.dispose();
        return (shown, favorites.saved.last.single, service);
      });

  group('a temporary Worker failure keeps the held photo and its saved key',
      () {
    final failures = <String, void Function(String id)>{
      'a timeout': (id) => backend.ends[id] = _Ends.timeout,
      'no connection': (id) => backend.ends[id] = _Ends.offline,
      'a 500': (id) => backend.refusal[id] = (500, '{"error":"boom"}'),
      'a 502': (id) => backend.refusal[id] = (502, '{"error":"upstream"}'),
      'a 503 session check unavailable': (id) => backend.refusal[id] =
          (503, '{"error":"x","code":"session_check_unavailable"}'),
      'a 200 that is not JSON': (id) => backend.rawBody[id] = '<html>',
    };
    for (final MapEntry(key: name, value: breakRead) in failures.entries) {
      test('$name: the held photo and the saved key stay', () async {
        final m = _mediaId();
        await mapped(m);
        final id = offer([(m, 'image')]);
        breakRead(id);
        final (shown, saved, offers) = await refresh(id, _savedCard(id, m));
        expect(shown.media?.cacheKey, _key(m),
            reason: 'was the icon: a failure read as "no media"');
        expect(shown.media?.signedUrl, isNull, reason: 'held bytes, no link');
        expect(shown.imageUrl, isNull);
        expect(_stored(saved), jsonEncode({'k': _key(m), 'v': false}),
            reason: 'was null: the saved card key was overwritten');
        expect(backend.mediaCalls, hasLength(1), reason: 'no extra request');
        expect(offers.lookups, 1);
        expect(transport.urls, isEmpty, reason: 'no download');
      });
    }

    test('offline reopening after a failed refresh still has the photo',
        () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      final (_, saved, _) = await refresh(id, _savedCard(id, m));
      await recorded(() async {
        final favorites = _Favorites(
            _metadata({
              'offers': [id]
            }),
            cached: [saved])
          ..metadataThrows = true;
        final vm = FavoritesViewModel(
            favoriteService: favorites, offerService: _Offers());
        await _until(() => favorites.metadataLoads >= 1);
        await pumpEventQueue();
        expect(vm.favorites.single.media?.cacheKey, _key(m));
        vm.dispose();
      });
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
      backend.ends[id] = _Ends.offline;
      final (shown, saved, _) = await refresh(id, _savedCard(id, m));
      expect(shown.media?.cacheKey, _key(m));
      expect(saved.media?.cacheKey, _key(m));
    });

    test('a photo held only in the private cache', () async {
      final m = _mediaId();
      await privateOnly(m);
      transport.urls.clear();
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      final before = Map.of(Hive.box('url_mapping').toMap());
      final (shown, _, _) = await refresh(id, _savedCard(id, m));
      expect(shown.media?.cacheKey, _key(m));
      expect(transport.urls, isEmpty);
      expect(Hive.box('url_mapping').toMap(), before,
          reason: 'the lookup writes no mapping');
    });

    test('a video whose still frame is held shows that frame', () async {
      final v = _mediaId();
      await poster(v);
      final id = offer([(v, 'video')]);
      backend.ends[id] = _Ends.offline;
      final (shown, _, _) = await refresh(id, _savedCard(id, v, video: true));
      expect(shown.media?.isVideo, isTrue);
      expect(shown.media?.posterPath, isNotNull);
      expect(shown.media?.signedUrl, isNull,
          reason: 'the video is not fetched');
      expect(transport.urls, isEmpty);
    });

    test('the saved key whose bytes are gone: the icon, no key kept', () async {
      final m = _mediaId();
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      final (shown, saved, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull, reason: 'nothing is held: the placeholder');
      expect(saved.media, isNull);
      expect(offers.lookups, 1);
      expect(transport.urls, isEmpty, reason: 'nothing downloaded to fill it');
    });

    test('the device catalogue wins: an emptied entry shows nothing', () async {
      final m = _mediaId();
      await mapped(m); // left behind, but the Worker said none earlier
      final id = offer([(m, 'image')], listed: [m]);
      await catalogue(id, const []);
      backend.ends[id] = _Ends.offline;
      final (shown, saved, _) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(saved.media, isNull);
    });

    test('the catalogue order wins over the saved key', () async {
      final a = _mediaId(), b = _mediaId();
      await mapped(a);
      await mapped(b);
      final id = offer([(a, 'image'), (b, 'image')]);
      await catalogue(id, [b, a]);
      backend.ends[id] = _Ends.offline;
      final (shown, _, _) = await refresh(id, _savedCard(id, a));
      expect(shown.media?.cacheKey, _key(b));
    });

    test('with no catalogue, this read\'s saved ids win over the saved key',
        () async {
      final removed = _mediaId(), current = _mediaId();
      await mapped(removed);
      await mapped(current);
      final id = offer([(current, 'image')], listed: [current]);
      backend.ends[id] = _Ends.offline;
      final (shown, _, offers) = await refresh(id, _savedCard(id, removed));
      expect(shown.media?.cacheKey, _key(current),
          reason: 'the server no longer lists the saved card\'s item');
      expect(offers.lookupIds.single, [current]);
    });

    test('a saved key of another account is never used', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      final (shown, saved, offers) =
          await refresh(id, _savedCard(id, m, account: _other));
      expect(shown.media, isNull);
      expect(saved.media, isNull);
      expect(offers.lookupIds.single, isEmpty);
    });
  });

  group('authoritative answers and refusals: nothing held is shown', () {
    test('a successful empty list clears the card and its saved key', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer(const []);
      await catalogue(id, [m]);
      final (shown, saved, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(saved.media, isNull);
      expect(offers.lookups, 0);
      await _until(() => catalogued(id).isEmpty);
    });

    test('a successful changed list: only the new item', () async {
      final old = _mediaId(), now = _mediaId();
      await mapped(old);
      final id = offer([(now, 'image')]);
      await catalogue(id, [old]);
      final (shown, saved, offers) = await refresh(id, _savedCard(id, old));
      expect(shown.media?.cacheKey, _key(now));
      expect(saved.media?.cacheKey, _key(now));
      expect(offers.lookups, 0);
    });

    test('a confirmed 404 (offer_not_found): nothing, no lookup', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await catalogue(id, [m]);
      backend.refusal[id] = (404, '{"error":"x","code":"offer_not_found"}');
      final (shown, saved, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(saved.media, isNull);
      expect(offers.lookups, 0, reason: 'a revocation is never looked past');
      expect(catalogued(id), isEmpty);
    });

    test('a 401: nothing held is shown and nothing is removed', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await catalogue(id, [m]);
      backend.refusal[id] = (401, '{"error":"expired"}');
      final (shown, _, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(offers.lookups, 0);
      expect(catalogued(id), [m], reason: 'a session problem removes nothing');
    });

    test(
        'a 403 session_superseded: nothing held is shown (OPTION C OPEN: the '
        'shared client still removes this record\'s media)', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await catalogue(id, [m]);
      backend.refusal[id] = (403, '{"error":"x","code":"session_superseded"}');
      final (shown, _, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(offers.lookups, 0);
      expect(catalogued(id), isEmpty,
          reason: 'recorded as is: D-FOMF-2 is fixed only by Option C');
    });

    test(
        'a 404 without its code: nothing held is shown (OPTION C OPEN: still '
        'treated as a revocation by the shared client)', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await catalogue(id, [m]);
      backend.refusal[id] = (404, '{"error":"Not found"}');
      final (shown, _, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull, reason: 'inconclusive is not permission');
      expect(offers.lookups, 0);
      expect(catalogued(id), isEmpty,
          reason: 'recorded as is: D-FOMF-3 is fixed only by Option C');
    });

    test(
        'a 200 with no media list (OPTION C OPEN: still read as "none" by '
        'the shared client)', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await catalogue(id, [m]);
      backend.rawBody[id] = '{"offerId":"$id"}';
      final (shown, saved, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(saved.media, isNull);
      expect(offers.lookups, 0);
      // Recorded as is: D-FOMF-4 is fixed only by Option C.
      await _until(() => catalogued(id).isEmpty);
    });
  });

  group('accounts, sessions and screens that are gone', () {
    test('another account during the Worker request: nothing published',
        () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      backend.mediaGate = Completer<void>();
      await recorded(() async {
        final offers = _Offers();
        final (vm, favorites) = await open(
            {
              'offers': [id]
            },
            offers,
            cached: [_savedCard(id, m)],
            wait: false);
        await _until(() => backend.mediaCalls.length == 1);
        await FavoriteService.invalidateForAccountChange();
        backend.mediaGate!.complete();
        await _until(() => offers.lookupDone);
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
        }
        expect(favorites.saved, isEmpty, reason: 'nothing cached');
        vm.dispose();
      });
    });

    Future<(FavoritesViewModel, _Favorites, _Offers)> openAtLookup(
        String id, String m) async {
      final offers = _Offers()..gate = Completer<void>();
      final (vm, favorites) = await open(
          {
            'offers': [id]
          },
          offers,
          cached: [_savedCard(id, m)],
          wait: false);
      await _until(() => offers.lookups == 1);
      return (vm, favorites, offers);
    }

    test('the session is replaced during the lookup: nothing held is shown',
        () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      await catalogue(id, [m]); // the device knows the item
      backend.ends[id] = _Ends.offline;
      await recorded(() async {
        final (vm, favorites, offers) = await openAtLookup(id, m);
        scope = null;
        offers.gate!.complete();
        await _until(() => favorites.saved.isNotEmpty);
        expect(vm.favorites.single.media, isNull);
        expect(favorites.saved.last.single.media, isNull);
        vm.dispose();
      });
    });

    test('signed out during the lookup: nothing held is shown', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      await recorded(() async {
        final (vm, favorites, offers) = await openAtLookup(id, m);
        await sb.Supabase.instance.client.auth
            .signOut()
            .catchError((Object _) {});
        offers.gate!.complete();
        await _until(() => favorites.saved.isNotEmpty);
        expect(vm.favorites.single.media, isNull);
        expect(favorites.saved.last.single.media, isNull);
        vm.dispose();
      });
    });

    test('after Delete Account cleanup nothing held comes back', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      await OfflineMediaService.instance.forgetOfferMedia(ownerId: _uid);
      scope = null;
      final (shown, saved, _) = await refresh(id, _savedCard(id, m));
      expect(shown.media, isNull);
      expect(saved.media, isNull);
    });

    test('the screen closes during the lookup: nothing is published', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      await recorded(() async {
        final (vm, favorites, offers) = await openAtLookup(id, m);
        vm.dispose();
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
        }
        expect(favorites.saved, isEmpty);
      });
    });

    test('another account during the lookup: nothing published', () async {
      final m = _mediaId();
      await mapped(m);
      final id = offer([(m, 'image')]);
      backend.ends[id] = _Ends.offline;
      await recorded(() async {
        final (vm, favorites, offers) = await openAtLookup(id, m);
        await FavoriteService.invalidateForAccountChange();
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
        }
        expect(favorites.saved, isEmpty);
        vm.dispose();
      });
    });

    test('another account during a lookup: the next Offers are not looked up',
        () async {
      final a = _mediaId(), b = _mediaId();
      await mapped(a);
      await mapped(b);
      final first = offer([(a, 'image')]);
      final second = offer([(b, 'image')]);
      backend.ends[first] = _Ends.offline;
      backend.ends[second] = _Ends.offline;
      await recorded(() async {
        final offers = _Offers()..gate = Completer<void>();
        final (vm, favorites) = await open(
            {
              'offers': [first, second]
            },
            offers,
            cached: [_savedCard(first, a), _savedCard(second, b)],
            wait: false);
        await _until(() => offers.lookups == 1);
        await FavoriteService.invalidateForAccountChange();
        offers.gate!.complete();
        await _until(() => offers.lookupDone);
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
        }
        expect(offers.lookups, 1,
            reason: 'the old account\'s device is not read for the rest');
        expect(favorites.saved, isEmpty);
        vm.dispose();
      });
    });
  });

  group('everything else is unchanged', () {
    test('the links in memory: the Worker\'s photo, no lookup', () async {
      final m = _mediaId();
      final id = offer([(m, 'image')]);
      final (shown, saved, offers) = await refresh(id, _savedCard(id, m));
      expect(shown.media?.cacheKey, _key(m));
      expect(shown.media?.signedUrl, contains('X-Amz-Signature'));
      expect(saved.media?.cacheKey, _key(m));
      expect(offers.lookups, 0);
    });

    test('a Firebase-shaped Offer keeps its plain URL, no lookup', () async {
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
      final (shown, _, _) =
          await refresh(id, _savedCard(id, null), offers: offers);
      expect(shown.imageUrl, plain);
      expect(shown.media, isNull);
      expect(offers.lookups, 0);
    });

    test('Owners: a temporary failure keeps the catalogue photo, as before',
        () async {
      final m = _mediaId();
      await mapped(m);
      final id = _ownerId();
      (backend.rows['owners'] ??= []).add(_row('owners', id));
      backend.media[id] = [(m, 'image')];
      await catalogue(id, [m]);
      backend.ends[id] = _Ends.offline;
      final offers = _Offers();
      final cards = await recorded(() async {
        final (vm, _) = await open({
          'owners': [id]
        }, offers);
        final shown = List.of(vm.favorites);
        vm.dispose();
        return shown;
      });
      expect(cards.single.media?.cacheKey, _key(m));
      expect(offers.lookups, 0);
    });

    test('ten Offers failing: one Worker call each, no download, no link',
        () async {
      final ids = <String>[];
      final saved = <FavoriteItem>[];
      for (var i = 0; i < 10; i++) {
        final m = _mediaId();
        if (i.isEven) await mapped(m);
        final id = offer([(m, 'image')]);
        backend.ends[id] = _Ends.offline;
        ids.add(id);
        saved.add(_savedCard(id, m));
      }
      final offers = _Offers();
      final (cards, stored) = await recorded(() async {
        final (vm, favorites) =
            await open({'offers': ids}, offers, cached: saved);
        final shown = List.of(vm.favorites);
        vm.dispose();
        return (shown, favorites.saved.last);
      });
      expect(backend.mediaCalls, hasLength(10));
      expect(offers.lookups, 10);
      expect(cards.where((c) => c.media != null), hasLength(5));
      expect(stored.where((c) => c.media != null), hasLength(5),
          reason: 'the five held keys are saved again');
      expect(cards.where((c) => c.imageUrl != null), isEmpty);
      expect(transport.urls, isEmpty);
    });

    test('Search and Smart Map do not read the new outcome', () {
      for (final dir in [
        'lib/src/views/Screens/home/search',
        'lib/src/views/Screens/home/map',
      ]) {
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          expect(entity.readAsStringSync().contains('DisplayMediaOutcome'),
              isFalse,
              reason: entity.path);
        }
      }
    });
  });
}
