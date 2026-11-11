// M3b-2 (tracker §7AZ) measurement only, Windows test VM — NOT Samsung: what
// one screenful of 10 Offer cards costs in the Search card resolver with the
// Search setting (saved ids + read-only lookup before the Worker) against the
// same resolver without it (Smart Map's, and Search before M3b-2), through the
// app's real media source, services, Hive and private cache. Supabase, the
// Worker and the private cache's network are counted fakes.
//
// Scenarios: (A) no catalogue, saved ids with mapped bytes; (B) no catalogue,
// bytes only in the private cache; (C) nothing held, the Worker online;
// (D) empty saved ids, the Worker online. Counted: Worker requests, Supabase
// requests, private-cache downloads, saved-id reads and lookups, mapping and
// catalogue writes caused by resolving, the most resolver operations in
// flight, and photos found. The resolver never reads the old shared image
// cache (no such import; pinned by search_card_saved_media_test.dart), so its
// old-cache reads are 0 by construction. Drawing the photo (M3b-1) is not part
// of this measure.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _a = '11111111-1111-4111-8111-111111111111';
const _cards = 10;

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'ffffffff-ffff-4fff-8fff-${(++_n).toString().padLeft(12, '0')}';

String _key(String media) =>
    offerMediaCacheKey(ownerId: _a, mediaObjectId: media)!;

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

class _Transport extends FileService {
  int downloads = 0;
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    downloads++;
    return _Response(_png);
  }
}

/// The real source, with every resolver operation counted.
class _Counting implements SearchCardMediaSource, SearchCardHeldMedia {
  _Counting(this.real);
  final DefaultSearchCardMediaSource real;

  int listedReads = 0;
  int lookups = 0;
  int resolves = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  Future<T> _track<T>(Future<T> Function() run) async {
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    try {
      return await run();
    } finally {
      inFlight--;
    }
  }

  @override
  String? get accountId => real.accountId;

  @override
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId) =>
      real.cached(kind, recordId);

  @override
  List<OfferMediaRef> listed(
      CardMediaKind kind, String recordId, String accountId, List<String> ids) {
    listedReads++;
    return real.listed(kind, recordId, accountId, ids);
  }

  @override
  Future<List<OfferMediaRef>> discover(
      CardMediaKind kind, String recordId, String accountId, List<String> ids) {
    lookups++;
    return _track(() => real.discover(kind, recordId, accountId, ids));
  }

  @override
  Future<OfferMediaResolution?> resolve(
      CardMediaKind kind, String recordId, String accountId) {
    resolves++;
    return _track(() => real.resolve(kind, recordId, accountId));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  var workerRequests = 0;
  var supabaseRequests = 0;
  late sb.SupabaseClient client;
  late DefaultSearchCardMediaSource source;
  final lines = <String>[
    'M3b-2 Search card resolver, $_cards Offer cards, Windows test VM '
        '(NOT Samsung):',
    'scenario | setting | Worker | Supabase | downloads | saved-id reads | '
        'lookups | mapping writes | catalogue writes | max in flight | '
        'photos found',
  ];

  String jwt(String uid) {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
  }

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m3b2m_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async {};
    await OfflineMediaService.instance.initialize();
    support = Directory.systemTemp.createTempSync('m3b2m_support_');
    temp = Directory.systemTemp.createTempSync('m3b2m_temp_');
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
    cache = PrivateMediaCache(
      currentScope: () => const PrivateMediaScope(account: _a, session: 's1'),
      transport: transport,
    );
    PrivateMediaImages.cache = () => cache;
    client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        supabaseRequests++;
        throw const SocketException('offline');
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(jsonEncode({
      'access_token': jwt(_a),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _a,
        'aud': 'authenticated',
        'email': 'm3b2m@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));
    R2OfferMediaUploadService worker(MediaParent parent) =>
        R2OfferMediaUploadService(
          supabaseClient: client,
          parent: parent,
          httpClient: MockClient((request) async {
            workerRequests++;
            final id = _id();
            return http.Response(
                jsonEncode({
                  'expiresInSeconds': 900,
                  'media': [
                    {
                      'mediaObjectId': id,
                      'url': 'https://r2.example/$id.png?X-Amz-Signature=sig',
                      'mediaType': 'image',
                    },
                  ],
                }),
                200);
          }),
        );
    final core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: worker(MediaParent.offer),
      ownerMedia: worker(MediaParent.owner),
    );
    source = DefaultSearchCardMediaSource(
      offers: OfferService(coreEntities: () => core, currentUserId: () => _a),
      owners: OwnerService(coreEntities: () => core, currentUserId: () => _a),
    );
  });

  tearDownAll(() async {
    // ignore: avoid_print
    print(lines.join('\n'));
    await cache.dispose().timeout(const Duration(seconds: 2), onTimeout: () {});
    PrivateMediaImages.cache = () => PrivateMediaCache.instance;
    await Hive.close();
    for (final dir in [documents, support, temp]) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  int catalogueCount(List<String> records) => records
      .where((r) => OfflineMediaService.instance
          .hasOfferMediaCatalog(ownerId: _a, offerId: r))
      .length;

  /// Resolves [_cards] fresh records the way a screenful of cards asks, and
  /// records the counters. [prepare] gives each record its saved ids.
  Future<Map<String, int>> measure(
    String scenario,
    bool searchSetting,
    Future<List<String>> Function() prepare,
  ) async {
    final records = [for (var i = 0; i < _cards; i++) _id()];
    final saved = [for (var i = 0; i < _cards; i++) await prepare()];
    final counting = _Counting(source);
    final resolver = searchSetting
        ? SearchCardMediaResolver(source: counting, heldMedia: counting)
        : SearchCardMediaResolver(source: counting);
    workerRequests = 0;
    supabaseRequests = 0;
    transport.downloads = 0;
    final mappingsBefore = Map.of(Hive.box('url_mapping').toMap());
    var photos = 0;
    final results = await Future.wait([
      for (var i = 0; i < _cards; i++)
        resolver.resolve(CardMediaKind.offer, records[i], listedIds: saved[i]),
    ]);
    await pumpEventQueue();
    for (final media in results) {
      if (media != null && !media.isVideo) photos++;
    }
    final mappingsAfter = Hive.box('url_mapping').toMap();
    var mappingWrites = 0;
    for (final entry in mappingsAfter.entries) {
      if (mappingsBefore[entry.key] != entry.value) mappingWrites++;
    }
    final counts = {
      'worker': workerRequests,
      'supabase': supabaseRequests,
      'downloads': transport.downloads,
      'listed': counting.listedReads,
      'lookups': counting.lookups,
      'mappingWrites': mappingWrites,
      'catalogueWrites': catalogueCount(records),
      'maxInFlight': counting.maxInFlight,
      'photos': photos,
    };
    lines.add('$scenario | ${searchSetting ? 'Search (M3b-2)' : 'none (Map)'}'
        ' | ${counts['worker']} | ${counts['supabase']} | '
        '${counts['downloads']} | ${counts['listed']} | ${counts['lookups']} | '
        '${counts['mappingWrites']} | ${counts['catalogueWrites']} | '
        '${counts['maxInFlight']} | ${counts['photos']}');
    return counts;
  }

  Future<List<String>> mappedIds() async {
    final m = _id();
    final f = File('${temp.path}${Platform.pathSeparator}$m.png')
      ..writeAsBytesSync(_png);
    await OfflineMediaService.instance.mapMediaIdToLocalFile(_key(m), f.path);
    return [m];
  }

  Future<List<String>> privateIds() async {
    final m = _id();
    await cache.get(_key(m),
        signedUrl: () async => 'https://r2.example/x.png?X-Amz-Signature=s');
    return [m];
  }

  Future<List<String>> missingIds() async => [_id()];
  Future<List<String>> noIds() async => const <String>[];

  test('A: saved ids with mapped bytes', () async {
    final on = await measure('A mapped', true, mappedIds);
    expect(on['worker'], 0);
    expect(on['lookups'], 0, reason: 'held at once: no lookup needed');
    expect(on['photos'], _cards);
    expect(on['mappingWrites'], 0);
    expect(on['catalogueWrites'], 0);
    final off = await measure('A mapped', false, mappedIds);
    expect(off['worker'], _cards, reason: 'before M3b-2: one per card');
  });

  test('B: bytes only in the private cache', () async {
    final on = await measure('B private', true, privateIds);
    expect(on['worker'], 0);
    expect(on['downloads'], 0);
    expect(on['lookups'], _cards);
    expect(on['photos'], _cards);
    expect(on['mappingWrites'], 0);
    expect(on['catalogueWrites'], 0);
    expect(on['maxInFlight'], lessThanOrEqualTo(3));
    final off = await measure('B private', false, privateIds);
    expect(off['worker'], _cards);
  });

  test('C: nothing held, the Worker online', () async {
    final on = await measure('C nothing held', true, missingIds);
    expect(on['worker'], _cards, reason: 'the Worker is still asked');
    expect(on['lookups'], _cards);
    expect(on['maxInFlight'], lessThanOrEqualTo(3));
    expect(on['downloads'], 0, reason: 'resolving downloads nothing');
    final off = await measure('C nothing held', false, missingIds);
    expect(off['worker'], _cards);
  });

  test('D: empty saved ids, the Worker online', () async {
    final on = await measure('D empty ids', true, noIds);
    expect(on['worker'], _cards, reason: 'empty ids are unknown, not none');
    final off = await measure('D empty ids', false, noIds);
    expect(off['worker'], _cards);
  });
}
