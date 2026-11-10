// M2-3b (tracker §7AZ, D-M2-3-1..4): Offer and Owner Details find the images
// this device already holds through the saved list's media identity
// (`listedMediaObjectIds`, M2-2) — the service half.
//
// Precedence under test:
//  - a catalogue entry for the record (written only from a Worker answer or
//    an accepted upload), even an empty one, wins: saved ids are not used and
//    never merged;
//  - only when there is no entry at all are the saved ids used — for a record
//    of the signed-in account, whose authorized session may read the keys,
//    and only items whose bytes are on this device;
//  - bytes in the private cache with no mapping are found by a read-only
//    lookup: no download, no signed link, no mapping or catalogue write.
//
// Real Hive, files and private cache; the session scope and the network are
// test-controlled (both Supabase and the cache transport count requests).
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
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _s1 = 'session-1';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'dddddddd-dddd-4ddd-8ddd-${(++_n).toString().padLeft(12, '0')}';

String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

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
  final restCalls = <http.BaseRequest>[];
  late sb.SupabaseClient client;
  late SupabaseCoreEntitiesService core;
  late OfferService offers;
  late OwnerService owners;

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
          'email': 'm23@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));

  /// Bytes held through a mapping (an earlier open, an adopted original).
  Future<String> mapped(String account, String media) async {
    final file = File('${temp.path}${Platform.pathSeparator}m-$media.png')
      ..writeAsBytesSync(_png);
    await OfflineMediaService.instance
        .mapMediaIdToLocalFile(_key(account, media), file.path);
    return file.path;
  }

  /// Bytes held only in the private cache: no mapping.
  Future<void> privateOnly(String account, String media) async {
    final file = await cache.get(_key(account, media),
        signedUrl: () async => 'https://r2.example/x.png?X-Amz-Signature=s');
    expect(file, isNotNull);
    expect(
        OfflineMediaService.instance
            .getLocalFilePathForMediaId(_key(account, media)),
        isNull);
  }

  Future<void> catalogue(String record, List<String> ids) =>
      OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _a, offerId: record, mediaObjectIds: ids);

  List<String> idsOf(List<OfferMediaRef> refs) =>
      [for (final r in refs) r.mediaObjectId];

  Map<dynamic, dynamic> mappings() => Map.of(Hive.box('url_mapping').toMap());

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m23_docs_');
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
    support = Directory.systemTemp.createTempSync('m23_support_');
    temp = Directory.systemTemp.createTempSync('m23_temp_');
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
    restCalls.clear();
    client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        restCalls.add(request);
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
            restCalls.add(request);
            throw const SocketException('offline');
          }),
        );
    core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: worker(MediaParent.offer),
      ownerMedia: worker(MediaParent.owner),
    );
    offers = OfferService(coreEntities: () => core, currentUserId: () => _a);
    owners = OwnerService(coreEntities: () => core, currentUserId: () => _a);
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

  // Offers and Owners go through their own services to the same code.
  final kinds = <(
    String,
    List<OfferMediaRef> Function(String, String, List<String>),
    Future<List<OfferMediaRef>> Function(String, String, List<String>),
  )>[
    (
      'Offer',
      (r, o, ids) => offers.listedOfferMedia(r, ownerId: o, ids: ids),
      (r, o, ids) => offers.discoverHeldOfferMedia(r, ownerId: o, ids: ids),
    ),
    (
      'Owner',
      (r, o, ids) => owners.listedMedia(r, ownerId: o, ids: ids),
      (r, o, ids) => owners.discoverHeldMedia(r, ownerId: o, ids: ids),
    ),
  ];

  for (final (kind, listed, discover) in kinds) {
    group(kind, () {
      test('no catalogue: saved ids with bytes draw at once, in saved order',
          () async {
        final record = _id();
        final ids = [_id(), _id(), _id()];
        for (final m in ids) {
          await mapped(_a, m);
        }
        final saved = [ids[2], ids[0], ids[1]];
        final refs = listed(record, _a, saved);
        expect(idsOf(refs), saved);
        for (final r in refs) {
          expect(r.hasLocalBytes, isTrue);
          expect(r.signedUrl, isNull, reason: 'no link: local bytes only');
          expect(r.cacheKey, _key(_a, r.mediaObjectId));
        }
      });

      test('only the held part of a partly cached record is shown', () async {
        final record = _id();
        final held = [_id(), _id()];
        final missing = _id();
        for (final m in held) {
          await mapped(_a, m);
        }
        final refs = listed(record, _a, [held[0], missing, held[1]]);
        expect(idsOf(refs), [held[0], held[1]],
            reason: 'an id with no bytes is never shown offline');
      });

      test(
          'bytes in the private cache with no mapping: found by the read-only '
          'lookup, in order, with no download and no mapping written',
          () async {
        final record = _id();
        final a = _id(), b = _id(), c = _id();
        await mapped(_a, a);
        await privateOnly(_a, b);
        await privateOnly(_a, c);
        transport.urls.clear();
        final before = mappings();
        expect(idsOf(listed(record, _a, [c, a, b])), [a],
            reason: 'the first frame shows what has a mapping');
        final found = await discover(record, _a, [c, a, b]);
        expect(idsOf(found), [c, a, b]);
        for (final r in found) {
          expect(r.hasLocalBytes, isTrue);
        }
        expect(transport.urls, isEmpty, reason: 'no download');
        expect(mappings(), before, reason: 'the lookup writes no mapping');
        expect(
            OfflineMediaService.instance
                .readOfferMediaCatalog(ownerId: _a, offerId: record),
            isEmpty,
            reason: 'nor a catalogue');
        expect(restCalls, isEmpty, reason: 'no Supabase or Worker request');
      });

      test('a catalogue with ids wins: saved ids are not used or merged',
          () async {
        final record = _id();
        final fromWorker = _id(), fromList = _id();
        await mapped(_a, fromWorker);
        await mapped(_a, fromList);
        await catalogue(record, [fromWorker]);
        expect(listed(record, _a, [fromList]), isEmpty);
        expect(idsOf(await discover(record, _a, [fromList])), [fromWorker],
            reason: 'the lookup follows the catalogue, not the saved ids');
      });

      test('an empty catalogue entry (the Worker said none) also wins',
          () async {
        final record = _id();
        final fromList = _id();
        await mapped(_a, fromList);
        await catalogue(record, const []);
        expect(listed(record, _a, [fromList]), isEmpty);
        expect(await discover(record, _a, [fromList]), isEmpty);
      });

      test('no saved ids (old list, Favorites copy, invalid field): nothing',
          () async {
        final record = _id();
        expect(listed(record, _a, const []), isEmpty);
        expect(await discover(record, _a, const []), isEmpty);
      });

      test('a record of another account is never used', () async {
        final record = _id();
        final m = _id();
        await mapped(_a, m);
        expect(listed(record, _b, [m]), isEmpty);
        expect(await discover(record, _b, [m]), isEmpty);
      });

      test('without an authorized session nothing is read', () async {
        final record = _id();
        final m = _id(), p = _id();
        await mapped(_a, m);
        await privateOnly(_a, p);
        scope = null; // superseded, not yet authorized, or signed out
        expect(listed(record, _a, [m, p]), isEmpty);
        expect(await discover(record, _a, [m, p]), isEmpty);
        scope = const PrivateMediaScope(account: _b, session: 'session-b');
        expect(listed(record, _a, [m, p]), isEmpty,
            reason: 'another account\'s session');
        expect(await discover(record, _a, [m, p]), isEmpty);
      });

      test('signed out of Supabase: nothing', () async {
        final record = _id();
        final m = _id();
        await mapped(_a, m);
        await client.auth.signOut().catchError((Object _) {});
        expect(listed(record, _a, [m]), isEmpty);
        expect(await discover(record, _a, [m]), isEmpty);
      });

      test('the session ends while the lookup waits: nothing is returned',
          () async {
        final record = _id();
        final p = _id(), q = _id();
        await privateOnly(_a, p);
        await privateOnly(_a, q);
        final pending = discover(record, _a, [p, q]);
        scope = null;
        expect(await pending, isEmpty);
      });

      test(
          'the session ends mid-lookup: not even an item found before it '
          'is returned', () async {
        final record = _id();
        final m = _id(), p = _id();
        await mapped(_a, m); // found at once, before the wait
        await privateOnly(_a, p); // found only after a wait
        final pending = discover(record, _a, [m, p]);
        scope = null; // the session ends while the lookup waits on p
        expect(await pending, isEmpty);
      });

      test('after Delete Account cleanup nothing comes back', () async {
        final record = _id();
        final m = _id();
        await mapped(_a, m);
        await OfflineMediaService.instance.forgetOfferMedia(ownerId: _a);
        scope = null; // the deleted account has no session
        expect(listed(record, _a, [m]), isEmpty);
        expect(await discover(record, _a, [m]), isEmpty);
      });
    });
  }

  test('the existing catalogue seed is unchanged by M2-3b', () async {
    final record = _id();
    final m = _id();
    await mapped(_a, m);
    await catalogue(record, [m]);
    expect(idsOf(offers.cachedOfferMedia(record)), [m]);
    expect(idsOf(owners.cachedMedia(record)), [m]);
  });
}
