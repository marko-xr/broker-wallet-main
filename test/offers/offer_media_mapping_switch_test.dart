// M1d-2 (tracker §7AZ, D-M1d-3): once an image shown from the image cache
// used before M1c has a verified private copy (M1d-1), its `url_mapping`
// entry is switched to that copy — by compare-and-set, only from the exact
// old-cache path captured when the image was shown, only in the session that
// showed it, and only when the copy's bytes equal the old file's.
//
// The switch also records the old-cache path it replaced as the key's
// fallback, so the synchronous readers (the details seed, `heldNow`) still
// find the old file if the private copy is later evicted or damaged: a
// switch never removes the only usable path to bytes this device holds.
//
// Real files, Hive and (for the seed) the real entities service are used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
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
const _sB = PrivateMediaScope(account: _b, session: 'session-3');

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

/// JPEG-signed bytes of exactly [length].
Uint8List _jpeg(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, const [0xFF, 0xD8, 0xFF, 0xE0]);
  for (var i = 4; i < length; i++) {
    bytes[i] = i % 251;
  }
  return bytes;
}

const _signedMarkers = ['X-Amz', 'r2.example', 'sig-'];

var _ids = 0;

String _uuid(String head) {
  _ids++;
  return '$head-cccc-4ccc-8ccc-${_ids.toString().padLeft(12, '0')}';
}

String _mediaId() => _uuid('cccccccc');

String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

String _link(int n) =>
    'https://r2.example/bucket/x.jpg?X-Amz-Expires=900&X-Amz-Signature=sig-$n';

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

/// Stands in for R2: counts downloads.
class _Transport extends FileService {
  final List<String> urls = [];

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    return _Response(_png);
  }
}

/// A Supabase client signed in as [uid], with no network behind it.
class _SignedIn {
  _SignedIn(this.uid);

  final String uid;

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient:
        MockClient((request) async => throw const SocketException('offline')),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  String _jwt() {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
  }

  Future<void> signIn() => client.auth.setInitialSession(jsonEncode({
        'access_token': _jwt(),
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
          'email': 'm1d2@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));
}

R2OfferMediaUploadService _unreachableWorker(
        sb.SupabaseClient client, MediaParent parent) =>
    R2OfferMediaUploadService(
      supabaseClient: client,
      parent: parent,
      httpClient:
          MockClient((_) async => throw const SocketException('offline')),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;
  Map<String, String> legacy = {};
  final legacyReads = <String>[];
  final outcomes = <String>[];
  final switches = <String>[];
  final steps = <String>[];
  var oldCacheRemovals = 0;

  PrivateMediaCache open() {
    final opened =
        PrivateMediaCache(currentScope: () => scope, transport: transport);
    opened.debugOnAdoptStep = (step, file) async => steps.add(step);
    return opened;
  }

  final offline = OfflineMediaService.instance;
  String? mapped(String key) => offline.getLocalFilePathForMediaId(key);
  String? fallback(String key) => offline.previousCopyPathForMediaId(key);

  File oldCopy(String key, List<int> bytes) {
    final dir =
        Directory('${temp.path}${Platform.pathSeparator}libCachedImageData')
          ..createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${_uuid('ee')}.png')
      ..writeAsBytesSync(bytes);
    legacy[key] = file.path;
    return file;
  }

  Future<String> trust(String account, String media) async {
    final record = _uuid('dddddddd');
    await offline.writeOfferMediaCatalog(
        ownerId: account, offerId: record, mediaObjectIds: [media]);
    return record;
  }

  List<File> privateFiles() {
    final dir = Directory(
        '${temp.path}${Platform.pathSeparator}${PrivateMediaCache.storeKey}');
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  Future<void> settle() => PrivateMediaImages.debugMigrationsSettled();

  /// An old copy for a trusted media id of [account], shown once and copied.
  Future<(String key, File old)> shownAndCopied({
    String account = _a,
    List<int>? bytes,
  }) async {
    final media = _mediaId();
    final key = _key(account, media);
    await trust(account, media);
    final old = oldCopy(key, bytes ?? _png);
    await PrivateMediaImages.load(key);
    await settle();
    return (key, old);
  }

  bool isPrivate(String? path) =>
      path != null && path.contains(PrivateMediaCache.storeKey);

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m1d2_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async => oldCacheRemovals++;
    await offline.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      documents.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('m1d2_support_');
    temp = Directory.systemTemp.createTempSync('m1d2_temp_');
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
    scope = _sA1;
    cache = open();
    PrivateMediaImages.cache = () => cache;
    OfflineMediaService.removePrivateBytes = (key) => cache.forget(key);
    PrivateMediaImages.debugForgetMigrations();
    PrivateMediaImages.debugOnMigration = (key, o) => outcomes.add(o);
    PrivateMediaImages.debugOnMapping = (key, o) => switches.add(o);
    legacy = {};
    legacyReads.clear();
    outcomes.clear();
    switches.clear();
    steps.clear();
    oldCacheRemovals = 0;
    OfflineMediaService.fetchCachedBytes = (key, url) async {
      legacyReads.add('$key|$url');
      return legacy[key];
    };
    OfferMediaUrlCache.instance.clear();
  });

  tearDown(() async {
    await settle().timeout(const Duration(seconds: 5), onTimeout: () {});
    expect(legacyReads.where((read) => !read.endsWith('|null')), isEmpty,
        reason: 'the old cache is only read');
    PrivateMediaImages.debugBeforeMappingSwitch = null;
    PrivateMediaImages.switchMapping = PrivateMediaImages.defaultSwitchMapping;
    PrivateMediaImages.debugOnMapping = null;
    PrivateMediaImages.debugOnMigration = null;
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

  // ---------------------------------------------------------------------
  group('a verified copy takes over the mapping', () {
    for (final kind in ['Offer', 'Owner']) {
      test('$kind image: switched to the private copy, old path kept',
          () async {
        final (key, old) = await shownAndCopied();
        expect(outcomes, ['adopted']);
        expect(switches, ['switched']);
        final now = mapped(key);
        expect(isPrivate(now), isTrue);
        expect(File(now!).readAsBytesSync(), _png);
        expect(fallback(key), old.path, reason: 'the old path is the fallback');
        expect(PrivateMediaImages.heldNow(key)!.path, now);
        expect(old.readAsBytesSync(), _png, reason: 'nothing deleted');
        expect(transport.urls, isEmpty);
        expect(oldCacheRemovals, 0);
      });
    }

    test('the switch happens with no test hooks installed', () async {
      // As in production: every optional hook absent, defaults in place.
      PrivateMediaImages.debugOnMapping = null;
      PrivateMediaImages.debugOnMigration = null;
      PrivateMediaImages.debugBeforeMappingSwitch = null;
      PrivateMediaImages.switchMapping =
          PrivateMediaImages.defaultSwitchMapping;
      cache.debugOnAdoptStep = null;
      expect(PrivateMediaImages.debugLoad, isNull);
      final (key, old) = await shownAndCopied();
      expect(isPrivate(mapped(key)), isTrue);
      expect(File(mapped(key)!).readAsBytesSync(), old.readAsBytesSync());
      expect(fallback(key), old.path);
      expect(transport.urls, isEmpty);
    });

    test('the image is shown at once; the switch never delays it', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      final gate = Completer<void>();
      PrivateMediaImages.debugBeforeMappingSwitch = (k, f) => gate.future;
      final clock = Stopwatch()..start();
      final shown = await PrivateMediaImages.load(key);
      final firstMs = clock.elapsedMicroseconds / 1000;
      expect(shown!.path, old.path);
      expect(PrivateMediaImages.heldNow(key)!.path, old.path,
          reason: 'still the old file until the switch');
      gate.complete();
      await settle();
      expect(switches, ['switched']);
      // ignore: avoid_print
      print('M1d-2 VM: first display ${firstMs.toStringAsFixed(1)} ms');
    });

    test('an image M1d-1 already copied (earlier run) is switched too',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      expect(await cache.adopt(key, old, origin: _sA1),
          PrivateMediaAdoption.adopted);
      await offline.mapMediaIdToLocalFile(key, old.path);
      steps.clear();

      expect((await PrivateMediaImages.load(key))!.path, old.path);
      await settle();
      expect(outcomes, ['alreadyHeld']);
      expect(switches, ['switched']);
      expect(isPrivate(mapped(key)), isTrue);
      expect(steps, isEmpty, reason: 'no second copy');
    });
  });

  // ---------------------------------------------------------------------
  group('the mapping is left as it is', () {
    test('when the copy fails', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      cache.debugOnAdoptStep = (step, file) async {
        if (step == 'written') file.writeAsBytesSync(_png.sublist(0, 9));
      };
      await PrivateMediaImages.load(key);
      await settle();
      expect(outcomes, ['failed']);
      expect(switches, isEmpty);
      expect(mapped(key), old.path);
      expect(fallback(key), isNull);
    });

    test('when another writer changed the mapping meanwhile', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      final adopted = File('${documents.path}${Platform.pathSeparator}'
          'adopted-${_uuid('ab')}.png')
        ..writeAsBytesSync(_png);
      cache.debugOnAdoptStep = (step, file) async {
        // An upload adopted its original for this id while the copy ran.
        if (step == 'written') {
          await offline.mapMediaIdToLocalFile(key, adopted.path);
        }
      };
      await PrivateMediaImages.load(key);
      await settle();
      expect(switches, ['changed']);
      expect(mapped(key), adopted.path, reason: 'the newer mapping wins');
      expect(fallback(key), isNull);
    });

    for (final (name, next) in [
      ('account switched', _sB),
      ('signed out', null),
      ('session replaced', _sA2),
    ]) {
      test('$name just before the switch', () async {
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        PrivateMediaImages.debugBeforeMappingSwitch = (k, f) async {
          scope = next;
        };
        await PrivateMediaImages.load(key);
        await settle();
        expect(switches, ['notAllowed']);
        expect(mapped(key), old.path);
        expect(fallback(key), isNull);
      });
    }

    test('a replaced session: the new session switches it on its display',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      PrivateMediaImages.debugBeforeMappingSwitch = (k, f) async {
        if (scope == _sA1) scope = _sA2;
      };
      await PrivateMediaImages.load(key);
      await settle();
      await PrivateMediaImages.load(key);
      await settle();
      expect(switches, ['notAllowed', 'switched']);
      expect(outcomes, ['adopted', 'alreadyHeld']);
      expect(isPrivate(mapped(key)), isTrue);
      expect(transport.urls, isEmpty);
    });

    test('when the copy disappeared before the switch', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      PrivateMediaImages.debugBeforeMappingSwitch = (k, copy) async {
        copy.deleteSync(); // evicted at the last moment
      };
      await PrivateMediaImages.load(key);
      await settle();
      expect(switches, ['missing']);
      expect(mapped(key), old.path);
    });

    test('when the copy differs from the old file', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      await cache.get(key, signedUrl: () async => _link(1)); // other bytes
      final old = oldCopy(key, _jpeg(64));
      await offline.mapMediaIdToLocalFile(key, old.path);
      await PrivateMediaImages.load(key);
      await settle();
      expect(switches, ['differs']);
      expect(mapped(key), old.path);
    });

    test('when the mapping write fails: both files are kept', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      PrivateMediaImages.switchMapping = (key, expected, copy, previous) =>
          throw const FileSystemException('disk full');
      await PrivateMediaImages.load(key);
      await settle();
      expect(switches, ['failed']);
      expect(mapped(key), old.path);
      expect(old.existsSync(), isTrue);
      expect(await cache.cached(key), isNotNull, reason: 'copy kept');
    });

    test('another account\'s mapping is never touched', () async {
      final media = _mediaId();
      final keyB = _key(_b, media);
      final bFile = File('${documents.path}${Platform.pathSeparator}'
          'b-${_uuid('bb')}.png')
        ..writeAsBytesSync(_png);
      await offline.mapMediaIdToLocalFile(keyB, bFile.path);
      final (keyA, _) = await shownAndCopied();
      expect(switches, ['switched']);
      expect(mapped(keyB), bFile.path);
      expect(fallback(keyB), isNull);
      expect(isPrivate(mapped(keyA)), isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('concurrency and Delete Account', () {
    test('many displays at once: one copy, one switch', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      final shown = await Future.wait([
        for (var i = 0; i < 5; i++) PrivateMediaImages.load(key),
      ]);
      expect(shown.map((f) => f!.path).toSet(), {old.path});
      await settle();
      for (var i = 0; i < 3; i++) {
        await PrivateMediaImages.load(key);
      }
      await settle();
      expect(outcomes, ['adopted']);
      expect(switches, ['switched']);
      expect(steps.where((s) => s == 'source_read'), hasLength(1));
      expect(privateFiles(), hasLength(1));
    });

    for (final atSwitch in [false, true]) {
      test(
          'Delete Account ${atSwitch ? 'just before the switch' : 'during '
              'the copy'}: nothing comes back', () async {
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        Future<void> deleteAccount() async {
          // completeAccountDeletion: sign-out first, then the cleaner.
          scope = null;
          await offline
              .forgetOfferMediaItems(ownerId: _a, mediaObjectIds: [media]);
          await cache.forgetAccount(_a);
        }

        if (atSwitch) {
          PrivateMediaImages.debugBeforeMappingSwitch =
              (k, f) => deleteAccount();
        } else {
          cache.debugOnAdoptStep = (step, file) async {
            if (step == 'written') await deleteAccount();
          };
        }
        await PrivateMediaImages.load(key);
        await settle();
        expect(mapped(key), isNull);
        expect(fallback(key), isNull);
        expect(privateFiles(), isEmpty);
        scope = _sA2;
        expect(PrivateMediaImages.heldNow(key), isNull);
        expect(await cache.cached(key), isNull);
        // The existing cleaner asked the old cache to drop its entry; the
        // test leaves the file to show that M1d-2 never deletes it itself.
        expect(oldCacheRemovals, 1);
        expect(old.existsSync(), isTrue);
      });
    }

    test('Delete Account after the switch also removes the fallback', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      await PrivateMediaImages.load(key);
      await settle();
      expect(fallback(key), isNotNull);
      await offline.forgetOfferMediaItems(ownerId: _a, mediaObjectIds: [media]);
      expect(mapped(key), isNull);
      expect(fallback(key), isNull);
      oldCacheRemovals = 0; // the existing cleaner's own request
    });
  });

  // ---------------------------------------------------------------------
  group('eviction, damage and restart never hide a held image', () {
    test('private copy evicted: the old file is shown again, then re-copied',
        () async {
      final (key, old) = await shownAndCopied();
      final copy = mapped(key)!;
      await cache.forget(key); // evicted by the private cache's own limits
      expect(File(copy).existsSync(), isFalse);

      expect(offline.usableLocalPathForMediaId(key), old.path);
      expect(PrivateMediaImages.heldNow(key)!.path, old.path);
      expect((await PrivateMediaImages.load(key))!.path, old.path);
      await settle();
      expect(switches, ['switched', 'switched'], reason: 'healed');
      expect(isPrivate(mapped(key)), isTrue);
      expect(File(mapped(key)!).existsSync(), isTrue);
      expect(transport.urls, isEmpty);
    });

    test('the offline seed still lists an evicted copy\'s image', () async {
      final backend = _SignedIn(_a);
      await backend.signIn();
      final service = SupabaseCoreEntitiesService(
        client: backend.client,
        offerMedia: _unreachableWorker(backend.client, MediaParent.offer),
        ownerMedia: _unreachableWorker(backend.client, MediaParent.owner),
      );
      final media = _mediaId();
      final key = _key(_a, media);
      final record = await trust(_a, media);
      final old = oldCopy(key, _png);
      await PrivateMediaImages.load(key);
      await settle();
      expect(
          service.cachedOfferMedia(record).single.localFilePath, mapped(key));
      await cache.forget(key);

      final seeded = service.cachedOfferMedia(record);
      expect(seeded, hasLength(1), reason: 'not dropped from the first frame');
      expect(seeded.single.localFilePath, old.path);
      expect(service.cachedOwnerMedia(record).single.localFilePath, old.path);
    });

    test('old and private files both gone: nothing shown, nothing fetched',
        () async {
      final (key, old) = await shownAndCopied();
      await cache.forget(key);
      old.deleteSync();
      expect(PrivateMediaImages.heldNow(key), isNull);
      expect(await PrivateMediaImages.load(key), isNull);
      expect(transport.urls, isEmpty, reason: 'no link, no download');
    });

    test('a damaged copy: dropped on the next run, re-copied from the old file',
        () async {
      final (key, old) = await shownAndCopied();
      File(mapped(key)!).writeAsBytesSync(_png.sublist(0, 7)); // truncated
      await cache.dispose();
      cache = open();
      PrivateMediaImages.debugForgetMigrations(); // the next run
      // Shown once as it is; the copy's length check drops it, and the old
      // file — still held — is copied and switched to again.
      await PrivateMediaImages.load(key);
      await settle();
      expect(outcomes, ['adopted', 'adopted']);
      expect(switches, ['switched', 'switched']);
      expect(File(mapped(key)!).readAsBytesSync(), _png, reason: 're-copied');
      expect(fallback(key), old.path);
      expect(transport.urls, isEmpty);
    });

    test('restart with a valid private mapping: shown, no work, no network',
        () async {
      final (key, _) = await shownAndCopied();
      final copy = mapped(key);
      await cache.dispose();
      cache = open();
      PrivateMediaImages.debugForgetMigrations();
      steps.clear();
      expect(PrivateMediaImages.heldNow(key)!.path, copy);
      expect((await PrivateMediaImages.load(key, signedUrl: _link(2)))!.path,
          copy);
      await settle();
      expect(steps, isEmpty);
      expect(switches, ['switched'], reason: 'nothing to switch again');
      expect(mapped(key), copy);
      expect(transport.urls, isEmpty);
    });

    test('restart with a stale mapping: the old file, then re-copied',
        () async {
      final (key, old) = await shownAndCopied();
      final copy = mapped(key)!;
      await cache.dispose();
      File(copy).deleteSync(); // e.g. the system cleared temporary files
      cache = open();
      PrivateMediaImages.debugForgetMigrations();
      expect(PrivateMediaImages.heldNow(key)!.path, old.path);
      await PrivateMediaImages.load(key);
      await settle();
      expect(switches, ['switched', 'switched']);
      expect(File(mapped(key)!).existsSync(), isTrue);
      expect(transport.urls, isEmpty);
    });

    test('a valid local hit asks for no link and downloads nothing', () async {
      final (key, _) = await shownAndCopied();
      var asked = 0;
      for (var i = 0; i < 3; i++) {
        await PrivateMediaImages.load(key, signedUrl: _link(i));
      }
      await cache.get(key, signedUrl: () async {
        asked++;
        return _link(9);
      });
      expect(asked, 0);
      expect(transport.urls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('nothing else changes', () {
    test('Favorites/Search readers get the same bytes, and recover', () async {
      final (key, old) = await shownAndCopied();
      // Favorites/Search cards read the mapping directly (unchanged code).
      final card = await offline.ensureMediaIdCached(cacheKey: key, url: null);
      expect(File(card!).readAsBytesSync(), old.readAsBytesSync());
      await cache.forget(key);
      // Evicted: the card's own fallback finds the old entry, as before.
      final again = await offline.ensureMediaIdCached(cacheKey: key, url: null);
      expect(again, old.path);
      expect(transport.urls, isEmpty);
    });

    test('no signed link is persisted; the old files are untouched', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      OfferMediaUrlCache.instance
          .put(key, _link(42), DateTime.now().add(const Duration(minutes: 10)));
      final old = oldCopy(key, _png);
      final modified = old.lastModifiedSync();
      await PrivateMediaImages.load(key, signedUrl: _link(43));
      await settle();
      expect(switches, ['switched']);
      await cache.dispose();
      cache = open();
      final written = StringBuffer();
      for (final dir in [documents, support, temp]) {
        for (final entity in dir.listSync(recursive: true)) {
          written.writeln(entity.path);
          if (entity is File && !entity.path.endsWith('.lock')) {
            written.writeln(
                utf8.decode(entity.readAsBytesSync(), allowMalformed: true));
          }
        }
      }
      for (final marker in _signedMarkers) {
        expect(written.toString(), isNot(contains(marker)), reason: marker);
      }
      expect(old.readAsBytesSync(), _png);
      expect(old.lastModifiedSync(), modified);
      expect(oldCacheRemovals, 0);
    });

    test('measurements (test VM, not a device)', () async {
      const n = 5;
      final keys = <String>[];
      final old = <File>[];
      for (var i = 0; i < n; i++) {
        final media = _mediaId();
        await trust(_a, media);
        keys.add(_key(_a, media));
        old.add(oldCopy(keys.last, _jpeg(100 * 1024)));
      }
      for (final key in keys) {
        await PrivateMediaImages.load(key, signedUrl: _link(1));
      }
      await settle();
      final readsAfterFirst = legacyReads.length;
      // Reopen: every image from its private copy, synchronously.
      var privateHits = 0;
      final clock = Stopwatch()..start();
      for (final key in keys) {
        if (isPrivate(PrivateMediaImages.heldNow(key)?.path)) privateHits++;
      }
      final heldUs = clock.elapsedMicroseconds;
      for (final key in keys) {
        await PrivateMediaImages.load(key, signedUrl: _link(2));
      }
      await settle();
      // Evict every private copy: the old files are used again.
      for (final key in keys) {
        await cache.forget(key);
      }
      var fallbackHits = 0;
      for (final key in keys) {
        if (PrivateMediaImages.heldNow(key)?.path == legacy[key]) {
          fallbackHits++;
        }
      }
      expect(privateHits, n);
      expect(fallbackHits, n);
      expect(switches.where((s) => s == 'switched'), hasLength(n));
      expect(legacyReads.length, readsAfterFirst, reason: 'no lookups on hits');
      expect(transport.urls, isEmpty);
      // ignore: avoid_print
      print('M1d-2 VM: n=$n switched=${switches.length} '
          'privateHits=$privateHits fallbackHitsAfterEviction=$fallbackHits '
          'oldCacheLookups=$readsAfterFirst downloads=${transport.urls.length} '
          'signing=0 copies=${steps.where((s) => s == 'source_read').length} '
          'heldNowAllUs=$heldUs');
    });
  });
}
