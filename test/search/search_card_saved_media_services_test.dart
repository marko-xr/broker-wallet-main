// M3b-2 (tracker §7AZ, D-M3-3): the Search card resolver with the app's own
// media source and services — real Hive (`url_mapping`, the media catalogue),
// real files and the real private image cache. Supabase, the Worker and the
// private cache's network are test-controlled and count every request.
//
// Pinned here, end to end:
//  - held bytes named by the saved ids (no catalogue entry) are shown with no
//    Supabase, Worker or image request, and the lookup writes no mapping and
//    no catalogue;
//  - the previous-copy fallback and bytes held only in the private cache count
//    as held;
//  - a catalogue entry (even an empty one) wins over the saved ids;
//  - a Worker 403/404 empties the catalogue, and nothing held comes back;
//  - without an authorized session, or signed out, nothing held is shown;
//  - no signed link is written anywhere on disk;
//  - a resolver built without the Search setting (as Smart Map's) is unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
const _s1 = 'session-1';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'eeeeeeee-eeee-4eee-8eee-${(++_n).toString().padLeft(12, '0')}';

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

/// The private cache's network: every download is counted.
class _Transport extends FileService {
  final List<String> urls = [];
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    return _Response(_png);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;
  final supabaseCalls = <http.BaseRequest>[];
  final workerCalls = <http.BaseRequest>[];

  /// What the Worker answers: a status and the media ids it lists.
  var workerStatus = 200;
  var workerMedia = <String>[];
  var workerOffline = false;

  /// The body of a non-200 answer (Option C: only a 404 with the route's own
  /// not-found code proves the record gone).
  var workerBody = '{"error":"denied"}';

  /// The Single Active Device gate de-authorizes the session as the Worker
  /// refuses it (a 403 `session_superseded`).
  var supersedeOnRefusal = false;

  late sb.SupabaseClient client;
  late SupabaseCoreEntitiesService core;
  late OfferService offers;
  late OwnerService owners;
  late DefaultSearchCardMediaSource source;

  String jwt(String uid) {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
  }

  Future<void> signIn(String uid) => client.auth.setInitialSession(jsonEncode({
        'access_token': jwt(uid),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'refresh_token': 'refresh',
        'user': {
          'id': uid,
          'aud': 'authenticated',
          'email': 'm3b2@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));

  File file(String name) => File('${temp.path}${Platform.pathSeparator}$name')
    ..writeAsBytesSync(_png);

  /// Bytes held through a mapping (an earlier open, an adopted original).
  Future<String> mapped(String media) async {
    final f = file('m-$media.png');
    await OfflineMediaService.instance
        .mapMediaIdToLocalFile(_key(media), f.path);
    return f.path;
  }

  /// Bytes held only in the private cache: no mapping.
  Future<void> privateOnly(String media) async {
    final f = await cache.get(_key(media),
        signedUrl: () async => 'https://r2.example/x.png?X-Amz-Signature=s');
    expect(f, isNotNull);
    expect(OfflineMediaService.instance.getLocalFilePathForMediaId(_key(media)),
        isNull);
  }

  Future<void> catalogue(String record, List<String> ids) =>
      OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _a, offerId: record, mediaObjectIds: ids);

  bool hasCatalogue(String record) => OfflineMediaService.instance
      .hasOfferMediaCatalog(ownerId: _a, offerId: record);

  Map<dynamic, dynamic> mappings() => Map.of(Hive.box('url_mapping').toMap());

  SearchCardMediaResolver search() =>
      SearchCardMediaResolver(source: source, heldMedia: source);

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m3b2_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async {};
    await OfflineMediaService.instance.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      documents.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    OfflineMediaService.debugForgetDeletedAccounts();
    support = Directory.systemTemp.createTempSync('m3b2_support_');
    temp = Directory.systemTemp.createTempSync('m3b2_temp_');
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
    scope = const PrivateMediaScope(account: _a, session: _s1);
    cache = PrivateMediaCache(currentScope: () => scope, transport: transport);
    PrivateMediaImages.cache = () => cache;
    supabaseCalls.clear();
    workerCalls.clear();
    workerStatus = 200;
    workerMedia = <String>[];
    workerOffline = false;
    workerBody = '{"error":"denied"}';
    supersedeOnRefusal = false;
    client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        supabaseCalls.add(request);
        throw const SocketException('offline');
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await signIn(_a);
    R2OfferMediaUploadService worker(MediaParent parent) =>
        R2OfferMediaUploadService(
          supabaseClient: client,
          parent: parent,
          httpClient: MockClient((request) async {
            workerCalls.add(request);
            if (workerOffline) throw const SocketException('offline');
            if (workerStatus != 200) {
              if (supersedeOnRefusal) scope = null;
              return http.Response(workerBody, workerStatus);
            }
            return http.Response(
                jsonEncode({
                  'expiresInSeconds': 900,
                  'media': [
                    for (final id in workerMedia)
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
    core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: worker(MediaParent.offer),
      ownerMedia: worker(MediaParent.owner),
    );
    offers = OfferService(coreEntities: () => core, currentUserId: () => _a);
    owners = OwnerService(coreEntities: () => core, currentUserId: () => _a);
    source = DefaultSearchCardMediaSource(offers: offers, owners: owners);
  });

  tearDown(() async {
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

  for (final kind in CardMediaKind.values) {
    group(kind.name, () {
      test('saved ids with mapped bytes: shown with no request of any kind',
          () async {
        final record = _id();
        final m1 = _id(), m2 = _id();
        await mapped(m2);
        await mapped(m1);
        transport.urls.clear();
        final before = mappings();
        final resolver = search();
        final saved = [_id(), m2, m1]; // the first has no bytes here
        expect(resolver.current(kind, record, listedIds: saved)?.cacheKey,
            _key(m2),
            reason: 'the first held photo in saved order, on the first frame');
        final media = await resolver.resolve(kind, record, listedIds: saved);
        expect(media?.cacheKey, _key(m2));
        expect(media?.signedUrl, isNull, reason: 'local bytes, no link');
        await pumpEventQueue();
        expect(workerCalls, isEmpty);
        expect(supabaseCalls, isEmpty);
        expect(transport.urls, isEmpty);
        expect(mappings(), before, reason: 'looking writes no mapping');
        expect(hasCatalogue(record), isFalse, reason: 'nor a catalogue');
      });

      test('the previous-copy fallback counts as held', () async {
        final record = _id();
        final m = _id();
        final original = await mapped(m);
        final copy = file('copy-$m.png');
        expect(
            await OfflineMediaService.instance.replaceMediaIdMapping(_key(m),
                expected: original, replacement: copy.path, previous: original),
            isTrue);
        copy.deleteSync(); // the private copy was evicted
        expect(OfflineMediaService.instance.usableLocalPathForMediaId(_key(m)),
            original);
        final media = await search().resolve(kind, record, listedIds: [m]);
        expect(media?.cacheKey, _key(m));
        expect(workerCalls, isEmpty);
      });

      test(
          'bytes only in the private cache: found read-only, no request, '
          'no mapping, no catalogue', () async {
        final record = _id();
        final p = _id();
        await privateOnly(p);
        transport.urls.clear();
        final before = mappings();
        final resolver = search();
        expect(resolver.current(kind, record, listedIds: [p]), isNull);
        final media = await resolver.resolve(kind, record, listedIds: [p]);
        expect(media?.cacheKey, _key(p));
        await pumpEventQueue();
        expect(workerCalls, isEmpty);
        expect(supabaseCalls, isEmpty);
        expect(transport.urls, isEmpty, reason: 'no download to look');
        expect(mappings(), before);
        expect(hasCatalogue(record), isFalse);
      });

      test('a catalogued item held only in the private cache needs no Worker',
          () async {
        final record = _id();
        final c = _id(), fromList = _id();
        await privateOnly(c);
        await mapped(fromList);
        await catalogue(record, [c]);
        final media =
            await search().resolve(kind, record, listedIds: [fromList]);
        expect(media?.cacheKey, _key(c),
            reason: 'the catalogue, not the saved ids');
        expect(workerCalls, isEmpty);
      });

      test(
          'an empty catalogue entry wins: the Worker is asked, its answer '
          'replaces the catalogue, and no link reaches the disk', () async {
        final record = _id();
        final fromList = _id(), fromWorker = _id();
        await mapped(fromList);
        await catalogue(record, const []);
        workerMedia = [fromWorker];
        final resolver = search();
        expect(resolver.current(kind, record, listedIds: [fromList]), isNull);
        final media =
            await resolver.resolve(kind, record, listedIds: [fromList]);
        expect(media?.cacheKey, _key(fromWorker));
        expect(media?.signedUrl, contains('X-Amz-Signature'),
            reason: 'the link is for drawing now, held in memory only');
        expect(workerCalls, hasLength(1));
        await pumpEventQueue();
        expect(
            OfflineMediaService.instance
                .readOfferMediaCatalog(ownerId: _a, offerId: record),
            [fromWorker]);
        expect(resolver.current(kind, record, listedIds: [fromList])?.cacheKey,
            _key(fromWorker),
            reason: 'the fresh answer wins; the saved ids are not merged');
        await Hive.box('url_mapping').flush();
        for (final dir in [documents, support]) {
          for (final entity in dir.listSync(recursive: true)) {
            // Hive holds a lock on its .lock files; they carry no data.
            if (entity is! File || entity.path.endsWith('.lock')) continue;
            final text = latin1.decode(entity.readAsBytesSync());
            expect(text.contains('X-Amz-Signature'), isFalse,
                reason: entity.path);
            expect(text.contains('r2.example'), isFalse, reason: entity.path);
          }
        }
      });

      // Option C (D-FOMF-2/3): only a 404 with the route's own not-found
      // code proves the record gone; a 403 is about the session.
      {
        test(
            'a Worker 404 with the route\'s not-found code: nothing held '
            'comes back afterwards', () async {
          final record = _id();
          final v = _id(), p = _id();
          // Only a video frame and a private photo of another id are held:
          // the frame is not a photo, so the Worker is still asked.
          final poster = file('poster-$v.png');
          await OfflineMediaService.instance
              .mapMediaIdToLocalFile(offerMediaPosterKey(_key(v)), poster.path);
          await privateOnly(p);
          workerStatus = 404;
          workerBody = jsonEncode({
            'error': 'x',
            'code': kind == CardMediaKind.offer
                ? 'offer_not_found'
                : 'owner_not_found',
          });
          final resolver = search();
          expect(
              resolver.current(kind, record, listedIds: [v])?.isVideo, isTrue);
          final media = await resolver.resolve(kind, record, listedIds: [v]);
          expect(media, isNull);
          expect(workerCalls, hasLength(1));
          expect(hasCatalogue(record), isTrue);
          expect(
              OfflineMediaService.instance
                  .readOfferMediaCatalog(ownerId: _a, offerId: record),
              isEmpty);
          expect(resolver.current(kind, record, listedIds: [v, p]), isNull);
          expect(
              await search().resolve(kind, record, listedIds: [v, p]), isNull,
              reason: 'a new Search screen: the emptied catalogue still wins');
        });

        test(
            'a Worker 403 session_superseded: nothing held is shown and '
            'nothing is removed', () async {
          final record = _id();
          final v = _id(), p = _id();
          final poster = file('poster-$v.png');
          await OfflineMediaService.instance
              .mapMediaIdToLocalFile(offerMediaPosterKey(_key(v)), poster.path);
          await privateOnly(p);
          workerStatus = 403;
          workerBody = '{"error":"x","code":"session_superseded"}';
          supersedeOnRefusal = true;
          final resolver = search();
          final media = await resolver.resolve(kind, record, listedIds: [v]);
          expect(media, isNull, reason: 'the superseded session reads nothing');
          expect(workerCalls, hasLength(1));
          expect(hasCatalogue(record), isFalse, reason: 'nothing reconciled');
          expect(
              OfflineMediaService.instance
                  .getLocalFilePathForMediaId(offerMediaPosterKey(_key(v))),
              isNotNull,
              reason: 'the still frame is kept');
          scope = const PrivateMediaScope(account: _a, session: 'session-2');
          expect(await cache.cached(_key(p)), isNotNull,
              reason: 'the next authorized session finds the bytes kept');
        });
      }

      test('an ordinary Worker failure keeps only what is still allowed',
          () async {
        final record = _id();
        final v = _id();
        final poster = file('poster-$v.png');
        await OfflineMediaService.instance
            .mapMediaIdToLocalFile(offerMediaPosterKey(_key(v)), poster.path);
        workerOffline = true;
        final media = await search().resolve(kind, record, listedIds: [v]);
        expect(media?.cacheKey, _key(v));
        expect(media?.isVideo, isTrue);
        expect(hasCatalogue(record), isFalse,
            reason: 'a failure establishes nothing');
      });

      test('without an authorized session nothing held is shown', () async {
        final record = _id();
        final m = _id(), p = _id();
        await mapped(m);
        await privateOnly(p);
        scope = null; // superseded, not yet authorized
        workerOffline = true;
        final resolver = search();
        expect(resolver.current(kind, record, listedIds: [m, p]), isNull);
        expect(await resolver.resolve(kind, record, listedIds: [m, p]), isNull);
      });

      test('the session ends during the lookup: nothing held is returned',
          () async {
        final record = _id();
        final p = _id(), q = _id();
        await privateOnly(p);
        await privateOnly(q);
        workerOffline = true;
        final pending = search().resolve(kind, record, listedIds: [p, q]);
        scope = null;
        expect(await pending, isNull);
      });

      test('signed out: nothing is read and nothing is asked', () async {
        final record = _id();
        final m = _id();
        await mapped(m);
        await client.auth.signOut().catchError((Object _) {});
        workerCalls.clear();
        final resolver = search();
        expect(resolver.current(kind, record, listedIds: [m]), isNull);
        expect(await resolver.resolve(kind, record, listedIds: [m]), isNull);
        expect(workerCalls, isEmpty);
      });

      test('without the Search setting (Smart Map): the Worker is asked',
          () async {
        final record = _id();
        final m = _id();
        await mapped(m);
        workerOffline = true;
        final resolver = SearchCardMediaResolver(source: source);
        expect(resolver.current(kind, record, listedIds: [m]), isNull);
        expect(await resolver.resolve(kind, record, listedIds: [m]), isNull);
        expect(workerCalls, hasLength(1), reason: 'exactly as before M3b-2');
      });
    });
  }
}
