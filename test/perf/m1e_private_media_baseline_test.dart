// M1e-a (tracker §7AZ): request-count and cost baseline of the Offer/Owner
// private image path, measured with explicit counters on controlled fakes.
//
// Measured, not inferred:
//  * Worker media resolutions — the only place links are signed. Faked here
//    by [_Worker]; each call returns a fresh signed link per item, as the
//    real Worker does.
//  * Image byte downloads and their bytes — [_Transport], the private
//    cache's network.
//  * Old-cache lookups — `OfflineMediaService.fetchCachedBytes`.
//  * Copies (M1d-1) and mapping switches (M1d-2) — the test hooks.
//  * Where each displayed file came from (first-frame `heldNow`, private
//    copy, old cache, download).
//  * Wall-clock timings on this test VM only (never a device claim).
//
// The display is driven the way the production widgets call it (see the
// tracker for the code references): `PrivateMediaImage` asks `heldNow` and
// otherwise `load(key, link)` for each page it builds; the gallery's warm-up
// calls `load` for the current item and the next two when a link is known;
// the full-screen viewer resolves its page and each visible thumbnail
// through `heldNow` or `PrivateMediaImageProvider`.
//
// Nothing here talks to a real service. Reported lines carry no links, ids
// or account values.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _sA1 = PrivateMediaScope(account: _a, session: 'session-1');
const _sA2 = PrivateMediaScope(account: _a, session: 'session-2');

/// A real, decodable 1×1 PNG: the bytes every fake download returns unless
/// a test asks for a size.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _ids = 0;
String _uuid(String head) =>
    '$head-cccc-4ccc-8ccc-${(++_ids).toString().padLeft(12, '0')}';
String _media() => _uuid('cccccccc');
String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

/// One reported metric line (no links, ids or account values).
final _report = <String>[];
void _line(String scenario, Map<String, Object> metrics) {
  final line =
      'M1E|$scenario|${metrics.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
  _report.add(line);
  // ignore: avoid_print
  print(line);
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

/// R2, as the private cache reaches it: counts downloads and bytes.
class _Transport extends FileService {
  int downloads = 0;
  int bytes = 0;
  final perLink = <String, int>{};
  List<int> body = _png;
  Completer<void>? gate;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    downloads++;
    perLink[url] = (perLink[url] ?? 0) + 1;
    final g = gate;
    if (g != null) await g.future;
    bytes += body.length;
    return _Response(body);
  }
}

/// The Worker's media route: each call signs every item again.
class _Worker {
  int calls = 0;
  int signed = 0;
  bool offline = false;

  List<String> resolve(List<String> mediaIds) {
    calls++;
    if (offline) throw const SocketException('offline');
    final first = signed;
    signed += mediaIds.length;
    return [
      for (var i = 0; i < mediaIds.length; i++)
        'https://r2.example/b/o.png?X-Amz-Signature=sig-${calls}_${first + i}',
    ];
  }
}

class _SignedIn {
  _SignedIn(this.uid);
  final String uid;

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((_) async => throw const SocketException('offline')),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<void> signIn() {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    final jwt = '${part({'alg': 'HS256'})}.'
        '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.s';
    return client.auth.setInitialSession(jsonEncode({
      'access_token': jwt,
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'r',
      'user': {
        'id': uid,
        'aud': 'authenticated',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));
  }
}

R2OfferMediaUploadService _unreachable(sb.SupabaseClient c, MediaParent p) =>
    R2OfferMediaUploadService(
      supabaseClient: c,
      parent: p,
      httpClient: MockClient((_) async => throw const SocketException('x')),
    );

/// Where one displayed image came from.
enum _From { firstFrame, privateCopy, oldCache, download, none }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late _Worker worker;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;
  Map<String, String> legacy = {};
  var legacyLookups = 0;
  var copies = 0;
  var switches = 0;
  final offline = OfflineMediaService.instance;

  PrivateMediaCache open() =>
      PrivateMediaCache(currentScope: () => scope, transport: transport);

  Directory dir(Directory base, String name) =>
      Directory('${base.path}${Platform.pathSeparator}$name');

  int sizeOf(Directory d) => d.existsSync()
      ? d
          .listSync(recursive: true)
          .whereType<File>()
          .fold(0, (s, f) => s + f.lengthSync())
      : 0;

  File oldCopy(String key, List<int> bytes) {
    final d = dir(temp, 'libCachedImageData')..createSync(recursive: true);
    final f = File('${d.path}${Platform.pathSeparator}${_uuid('ee')}.png')
      ..writeAsBytesSync(bytes);
    legacy[key] = f.path;
    return f;
  }

  Future<String> catalogue(String account, List<String> ids) async {
    final record = _uuid('dddddddd');
    await offline.writeOfferMediaCatalog(
        ownerId: account, offerId: record, mediaObjectIds: ids);
    return record;
  }

  Future<void> settle() => PrivateMediaImages.debugMigrationsSettled();

  /// One image as `PrivateMediaImage` gets it, classified by its source.
  Future<_From> show(String key, String? link) async {
    if (PrivateMediaImages.heldNow(key) != null) return _From.firstFrame;
    final before = transport.downloads;
    final lookups = legacyLookups;
    final file = await PrivateMediaImages.load(key, signedUrl: link);
    if (file == null) return _From.none;
    if (transport.downloads > before) return _From.download;
    if (legacyLookups > lookups && !file.path.contains('bwPrivateMedia')) {
      return _From.oldCache;
    }
    return _From.privateCopy;
  }

  /// Opens a details gallery of [ids]: one Worker resolution, the visible
  /// page, and the warm-up of the current item and the next two.
  Future<List<_From>> openGallery(String account, List<String> ids,
      {int page = 0}) async {
    List<String?> links;
    try {
      links = worker.resolve(ids);
      for (var i = 0; i < ids.length; i++) {
        OfferMediaUrlCache.instance.put(_key(account, ids[i]), links[i]!,
            DateTime.now().add(const Duration(minutes: 15)));
      }
    } on SocketException {
      links = List<String?>.filled(ids.length, null);
    }
    final keys = [for (final id in ids) _key(account, id)];
    final visible = show(keys[page], links[page]);
    final warm = [
      for (var i = page; i < (page + 3).clamp(0, ids.length); i++)
        if (links[i] != null)
          PrivateMediaImages.load(keys[i], signedUrl: links[i]),
    ];
    final from = await visible;
    await Future.wait(warm);
    await settle();
    return [from];
  }

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m1e_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async {};
    await offline.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      documents.deleteSync(recursive: true);
    } catch (_) {}
    // ignore: avoid_print
    print('M1E-SUMMARY\n${_report.join('\n')}');
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('m1e_support_');
    temp = Directory.systemTemp.createTempSync('m1e_temp_');
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
    worker = _Worker();
    scope = _sA1;
    cache = open();
    PrivateMediaImages.cache = () => cache;
    OfflineMediaService.removePrivateBytes = (key) => cache.forget(key);
    OfflineMediaService.debugForgetDeletedAccounts();
    OfflineMediaService.sessionScope = () => scope;
    PrivateMediaImages.debugForgetMigrations();
    PrivateMediaImages.debugOnMigration = (k, o) {
      if (o == 'adopted') copies++;
    };
    PrivateMediaImages.debugOnMapping = (k, o) {
      if (o == 'switched') switches++;
    };
    legacy = {};
    legacyLookups = 0;
    copies = 0;
    switches = 0;
    OfflineMediaService.fetchCachedBytes = (key, url) async {
      legacyLookups++;
      return legacy[key];
    };
    OfferMediaUrlCache.instance.clear();
  });

  tearDown(() async {
    await settle().timeout(const Duration(seconds: 5), onTimeout: () {});
    PrivateMediaImages.debugOnMigration = null;
    PrivateMediaImages.debugOnMapping = null;
    PrivateMediaImages.cache = () => PrivateMediaCache.instance;
    OfflineMediaService.sessionScope = PrivateMediaCache.applicationScope;
    OfflineMediaService.debugForgetDeletedAccounts();
    await cache.dispose().timeout(const Duration(seconds: 2), onTimeout: () {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    for (final d in [support, temp]) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // -----------------------------------------------------------------------
  test('A/C/H: first display, reopens, new signed links each time', () async {
    final ids = [_media()];
    await catalogue(_a, ids);
    final clock = Stopwatch()..start();
    final first = await openGallery(_a, ids);
    final firstMs = clock.elapsedMicroseconds / 1000;
    expect(first, [_From.download]);
    expect(transport.downloads, 1);
    final opens = <_From>[];
    clock.reset();
    for (var i = 0; i < 3; i++) {
      opens.addAll(await openGallery(_a, ids));
    }
    final reopenMs = clock.elapsedMicroseconds / 1000 / 3;
    expect(opens, List.filled(3, _From.firstFrame));
    expect(transport.downloads, 1, reason: 'H: 4 links, 1 download');
    expect(transport.perLink.length, 1);
    _line('A first display (1 image, nothing held)', {
      'worker': 1,
      'signed': 1,
      'downloads': 1,
      'bytes': transport.bytes,
      'from': first.single.name,
      'vmMs': firstMs.toStringAsFixed(1),
    });
    _line('C/H reopen x3 (new links each)', {
      'worker': worker.calls - 1,
      'signed': worker.signed - 1,
      'downloads': transport.downloads - 1,
      'from': opens.first.name,
      'vmMsPerOpen': reopenMs.toStringAsFixed(2),
    });
  });

  test('B: held by the private cache but not mapped', () async {
    final key = _key(_a, _media());
    await cache.get(key, signedUrl: () async => 'https://r2.example/x?sig');
    await offline.mapMediaIdToLocalFile(key, '/gone'); // mapping dead
    final before = transport.downloads;
    final clock = Stopwatch()..start();
    final from = await show(key, null);
    final ms = clock.elapsedMicroseconds / 1000;
    expect(from, _From.privateCopy);
    expect(transport.downloads, before);
    // The next frame finds it synchronously (the mapping was healed).
    expect(PrivateMediaImages.heldNow(key), isNotNull);
    clock.reset();
    for (var i = 0; i < 100; i++) {
      await cache.cached(key);
    }
    final lookupUs = clock.elapsedMicroseconds / 100;
    clock.reset();
    for (var i = 0; i < 1000; i++) {
      PrivateMediaImages.heldNow(key);
    }
    final heldUs = clock.elapsedMicroseconds / 1000;
    _line('B private copy, no mapping', {
      'worker': 0,
      'downloads': 0,
      'from': from.name,
      'vmMs': ms.toStringAsFixed(2),
      'privateLookupUs': lookupUs.toStringAsFixed(1),
      'heldNowUs': heldUs.toStringAsFixed(2),
    });
  });

  test('D: an Owner gallery behaves the same', () async {
    final ids = [_media(), _media()];
    await catalogue(_a, ids); // an Owner record's catalogue: same box
    await openGallery(_a, ids);
    final afterFirst = transport.downloads;
    final reopen = await openGallery(_a, ids);
    expect(afterFirst, 2, reason: 'current + next (warm-up)');
    expect(reopen, [_From.firstFrame]);
    expect(transport.downloads, afterFirst);
    _line('D Owner gallery (2 images) first + reopen', {
      'worker': worker.calls,
      'downloadsFirst': afterFirst,
      'downloadsReopen': transport.downloads - afterFirst,
    });
  });

  test('F/E: eight images, swiping, the viewer opened and closed', () async {
    final ids = [for (var i = 0; i < 8; i++) _media()];
    await catalogue(_a, ids);
    final keys = [for (final id in ids) _key(_a, id)];
    await openGallery(_a, ids);
    final atOpen = transport.downloads;
    expect(atOpen, 3, reason: 'the page and the warm-up of the next two');

    // The viewer: its page and the visible thumbnails (about six fit).
    final links = worker.resolve(ids);
    var viewerLoads = 0;
    Future<void> viewer() async {
      for (var i = 0; i < 6; i++) {
        if (PrivateMediaImages.heldNow(keys[i]) == null) {
          viewerLoads++;
          await PrivateMediaImages.load(keys[i], signedUrl: links[i]);
        }
      }
    }

    await viewer();
    final afterViewer = transport.downloads;
    for (var i = 0; i < 4; i++) {
      await viewer(); // closed and opened again
    }
    expect(transport.downloads, afterViewer, reason: 'reopen: no download');

    // Swiping through all eight: each page plus its warm-up.
    for (var p = 0; p < 8; p++) {
      await openGallery(_a, ids, page: p);
    }
    final afterSwipe = transport.downloads;
    final reopen = await openGallery(_a, ids);
    expect(afterSwipe, 8, reason: 'each image once');
    expect(reopen, [_From.firstFrame]);
    _line('F 8 images: first open', {'worker': 1, 'downloads': atOpen});
    _line('E viewer first open (6 thumbnails)', {
      'downloads': afterViewer - atOpen,
      'loadsNotHeld': viewerLoads,
    });
    _line('E viewer reopen x4', {'downloads': 0});
    _line('F swipe all 8, then reopen', {
      'downloadsTotal': afterSwipe,
      'downloadsReopen': 0,
      'workerPerOpen': 1,
      'signedPerOpen': 8,
      'privateDiskBytes': sizeOf(dir(temp, PrivateMediaCache.storeKey)),
    });
  });

  test('F (bounded larger set): 32 images', () async {
    final ids = [for (var i = 0; i < 32; i++) _media()];
    await catalogue(_a, ids);
    transport.body = List<int>.filled(64 * 1024, 7)..setAll(0, _png);
    final clock = Stopwatch()..start();
    for (var p = 0; p < 32; p++) {
      await openGallery(_a, ids, page: p);
    }
    final swipeMs = clock.elapsedMicroseconds / 1000;
    expect(transport.downloads, 32);
    clock.reset();
    var held = 0;
    for (final id in ids) {
      if (PrivateMediaImages.heldNow(_key(_a, id)) != null) held++;
    }
    final allHeldUs = clock.elapsedMicroseconds;
    expect(held, 32);
    _line('F 32 images x 64 KiB', {
      'downloads': transport.downloads,
      'bytes': transport.bytes,
      'privateDiskBytes': sizeOf(dir(temp, PrivateMediaCache.storeKey)),
      'vmMsAllPages': swipeMs.toStringAsFixed(0),
      'heldNowAll32Us': allHeldUs,
    });
  });

  test('G: five widgets asking for one image at once', () async {
    final key = _key(_a, _media());
    transport.gate = Completer<void>();
    final all = [
      for (var i = 0; i < 5; i++)
        PrivateMediaImages.load(key, signedUrl: 'https://r2.example/g$i?sig'),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 30));
    transport.gate!.complete();
    final files = await Future.wait(all);
    expect(files.map((f) => f?.path).toSet(), hasLength(1));
    expect(transport.downloads, 1);
    _line('G 5 concurrent requests, 5 different links',
        {'downloads': transport.downloads, 'duplicates': 0});
  });

  test('I/J: offline reopen and an unreachable Worker', () async {
    final backend = _SignedIn(_a);
    await backend.signIn();
    final service = SupabaseCoreEntitiesService(
      client: backend.client,
      offerMedia: _unreachable(backend.client, MediaParent.offer),
      ownerMedia: _unreachable(backend.client, MediaParent.owner),
    );
    final ids = [_media(), _media(), _media()];
    final record = await catalogue(_a, ids);
    for (var p = 0; p < 3; p++) {
      await openGallery(_a, ids, page: p); // an earlier online visit
    }
    final online = transport.downloads;
    OfferMediaUrlCache.instance.clear(); // links are memory-only
    worker.offline = true;

    final clock = Stopwatch()..start();
    final seeded = service.cachedOfferMedia(record);
    final seedUs = clock.elapsedMicroseconds;
    final shown = await openGallery(_a, ids);
    expect(seeded.where((r) => r.hasLocalBytes), hasLength(3));
    expect(shown, [_From.firstFrame]);
    expect(transport.downloads, online);
    _line('I/J offline reopen, Worker unreachable', {
      'workerAttempts': 1,
      'downloads': 0,
      'seededLocal': seeded.where((r) => r.hasLocalBytes).length,
      'seedUs': seedUs,
      'from': shown.single.name,
    });
  });

  test('K: restart with a valid private copy', () async {
    final ids = [_media()];
    await catalogue(_a, ids);
    await openGallery(_a, ids);
    await cache.dispose();
    cache = open();
    PrivateMediaImages.debugForgetMigrations();
    final lookups = legacyLookups;
    final clock = Stopwatch()..start();
    final held = PrivateMediaImages.heldNow(_key(_a, ids.single));
    final us = clock.elapsedMicroseconds;
    final shown = await openGallery(_a, ids);
    expect(held, isNotNull);
    expect(shown, [_From.firstFrame]);
    expect(transport.downloads, 1);
    expect(legacyLookups, lookups);
    _line('K restart, valid private copy', {
      'downloads': 0,
      'oldCacheLookups': 0,
      'firstFrameUs': us,
      'worker': 1,
    });
  });

  test('L/M/N: old copy migrated, mapping switched, copy evicted', () async {
    final ids = [_media()];
    await catalogue(_a, ids);
    final key = _key(_a, ids.single);
    final body = List<int>.filled(200 * 1024, 3)..setAll(0, _png);
    final old = oldCopy(key, body);
    final clock = Stopwatch()..start();
    final first = await show(key, null);
    final shownMs = clock.elapsedMicroseconds / 1000;
    await settle();
    final doneMs = clock.elapsedMicroseconds / 1000;
    expect(first, _From.oldCache);
    expect(copies, 1);
    expect(switches, 1);
    expect(transport.downloads, 0);
    final dup = sizeOf(dir(temp, PrivateMediaCache.storeKey));
    _line('M/N old copy: shown, copied, mapping switched', {
      'downloads': 0,
      'worker': 0,
      'copies': copies,
      'switches': switches,
      'vmMsShown': shownMs.toStringAsFixed(1),
      'vmMsCopiedAndSwitched': doneMs.toStringAsFixed(1),
      'duplicateBytes': dup,
    });

    await cache.forget(key); // evicted
    expect(PrivateMediaImages.heldNow(key)!.path, old.path);
    // The page alone: the widget draws the fallback and asks nothing more.
    final again = await show(key, null);
    await settle();
    expect(again, _From.firstFrame, reason: 'the fallback, synchronously');
    expect(copies, 1, reason: 'a fallback display alone does not re-copy');
    // An online open: the warm-up calls load with a link, which re-copies.
    await openGallery(_a, ids);
    expect(copies, 2);
    expect(switches, 2);
    expect(transport.downloads, 0);
    _line('L private copy evicted, old file still held', {
      'downloads': transport.downloads,
      'from': again.name,
      'reCopyOnFallbackDisplay': 0,
      'reCopyOnNextOnlineOpen': 1,
      'reSwitches': 1,
    });
  });

  test('O: missing or damaged copies', () async {
    final key = _key(_a, _media());
    await catalogue(_a, [key.split(':').last]);
    final file = await PrivateMediaImages.load(key,
        signedUrl: 'https://r2.example/o1?sig');
    file!.writeAsBytesSync(_png.sublist(0, 9)); // truncated
    await offline.mapMediaIdToLocalFile(key, '/gone');
    final noLink = await show(key, null);
    final withLink = await show(key, 'https://r2.example/o2?sig');
    expect(noLink, _From.none);
    expect(withLink, _From.download);
    _line('O damaged copy (size changed)', {
      'withoutLink': noLink.name,
      'withLink': withLink.name,
      'downloads': transport.downloads,
    });
  });

  test('P: session replaced while an image downloads', () async {
    final key = _key(_a, _media());
    transport.gate = Completer<void>();
    final pending =
        PrivateMediaImages.load(key, signedUrl: 'https://r2.example/p?sig');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    scope = _sA2;
    transport.gate!.complete();
    expect(await pending, isNull);
    expect(offline.getLocalFilePathForMediaId(key), isNull);
    _line('P session replaced mid-download', {
      'downloads': transport.downloads,
      'wastedBytes': transport.bytes,
      'published': 0,
    });
  });

  test('Q: Delete Account while media work is in flight', () async {
    final key = _key(_a, _media());
    transport.gate = Completer<void>();
    final pending =
        PrivateMediaImages.load(key, signedUrl: 'https://r2.example/q?sig');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    scope = null; // sign-out first, then the cleaner
    await offline.forgetOfferMedia(ownerId: _a);
    await cache.forgetAccount(_a);
    transport.gate!.complete();
    expect(await pending, isNull);
    expect(offline.getLocalFilePathForMediaId(key), isNull);
    await offline.mapMediaIdToLocalFile(key, '/late');
    expect(offline.getLocalFilePathForMediaId(key), isNull);
    _line('Q Delete Account vs in-flight download', {
      'downloads': transport.downloads,
      'mappingsAfter': 0,
      'lateWriteRefused': 'yes',
    });
  });

  test('isolation: another account never gets the copy', () async {
    final media = _media();
    await catalogue(_a, [media]);
    await openGallery(_a, [media]);
    scope = const PrivateMediaScope(account: _b, session: 'b');
    expect(PrivateMediaImages.heldNow(_key(_a, media)), isNull);
    expect(await PrivateMediaImages.load(_key(_a, media)), isNull);
  });

  test('decode cost: full size vs the widths the screens ask for', () async {
    // A 1600x1200 photo, encoded here (no asset, no network).
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < 12; y++) {
      for (var x = 0; x < 16; x++) {
        canvas.drawRect(Rect.fromLTWH(x * 100, y * 100, 100, 100),
            Paint()..color = Color(0xFF000000 | (x * 15 << 16) | (y * 20)));
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(1600, 1200);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final results = <String, Object>{'pngBytes': png.length};
    for (final (label, width) in [
      ('full', null),
      ('header1080', 1080),
      ('thumb120', 120),
    ]) {
      final clock = Stopwatch()..start();
      final codec = await ui.instantiateImageCodec(png, targetWidth: width);
      final frame = await codec.getNextFrame();
      final ms = clock.elapsedMicroseconds / 1000;
      results['${label}Ms'] = ms.toStringAsFixed(1);
      results['${label}DecodedBytes'] =
          frame.image.width * frame.image.height * 4;
      frame.image.dispose();
    }
    _line('decode (test VM, not a device)', results);
  });

  test('viewer image keys: held file vs not-yet-held provider', () {
    final key = _key(_a, 'm');
    // A held file is keyed by its path: a reopen hits the image cache.
    expect(FileImage(File('/x.png')), FileImage(File('/x.png')));
    // A not-yet-held item is keyed by identity AND link: every new link is
    // a new image-cache entry (a fresh decode, not a fresh download).
    expect(PrivateMediaImageProvider(key, signedUrl: 'l1'),
        isNot(PrivateMediaImageProvider(key, signedUrl: 'l2')));
    _line('viewer keys', {
      'heldFileKey': 'path',
      'notHeldKey': 'identity+link',
    });
  });
}
