// M1d-1 (tracker §7AZ, D-M1d-1..6): an Offer or Owner image shown from the
// image cache in use before M1c is copied, once and with no network, into the
// private image cache (M1b).
//
// Under test:
//  * the trusted-identity rule: only the current session's own exact key
//    `offer-media:<account>:<mediaId>`, whose media id that account's media
//    catalogue names (or this run's Worker resolution, as an image);
//  * the bytes enter through the private cache's own file service, with its
//    size limit and session checks, plus a supported-image check; the copy is
//    read back and compared (SHA-256 and size);
//  * session checks after every wait, one copy at a time per item;
//  * and that nothing else changes: the old cache entry, url_mapping, the
//    catalogue and what the gallery and the full-screen viewer paint.
//
// Real files and Hive are used. Widget tests run their I/O in `runAsync`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/views/Widgets/private_media_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:photo_view/photo_view.dart';

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

/// Everything a signed R2 link carries that must never reach the disk.
const _signedMarkers = ['X-Amz', 'r2.example', 'sig-'];

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

var _ids = 0;

/// A fresh id per use, so tests sharing Hive never collide.
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
  Completer<void>? gate;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    final g = gate;
    if (g != null) await g.future;
    return _Response(_png);
  }
}

/// The index the library uses on this host, with its row insert held back
/// until [gate] opens — the order the phone's SQLite index can take, since
/// the library writes the row without waiting for it.
class _SlowInsertIndex extends JsonCacheInfoRepository {
  _SlowInsertIndex() : super(databaseName: PrivateMediaCache.storeKey);

  Completer<void>? gate;

  @override
  Future<CacheObject> insert(CacheObject cacheObject,
      {bool setTouchedToNow = true}) async {
    final g = gate;
    if (g != null) await g.future;
    return super.insert(cacheObject, setTouchedToNow: setTouchedToNow);
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
  Map<String, String> legacy = {};
  final legacyReads = <String>[];
  final outcomes = <String>[];
  final steps = <String>[];
  var oldCacheRemovals = 0;

  PrivateMediaCache open() {
    final opened =
        PrivateMediaCache(currentScope: () => scope, transport: transport);
    opened.debugOnAdoptStep = (step, file) async => steps.add(step);
    return opened;
  }

  String? mapped(String key) =>
      OfflineMediaService.instance.getLocalFilePathForMediaId(key);

  /// An entry of the old image cache under [key], as its files look on disk.
  File oldCopy(String key, List<int> bytes) {
    final dir = Directory('${temp.path}${Platform.pathSeparator}'
        'libCachedImageData')
      ..createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${_uuid('ee')}.png')
      ..writeAsBytesSync(bytes);
    legacy[key] = file.path;
    return file;
  }

  /// Remembers [media] in one of [account]'s Offer or Owner records, as the
  /// Worker's answer (or an accepted upload) does.
  Future<String> trust(String account, String media) async {
    final record = _uuid('dddddddd');
    await OfflineMediaService.instance.writeOfferMediaCatalog(
      ownerId: account,
      offerId: record,
      mediaObjectIds: [media],
    );
    return record;
  }

  List<File> privateFiles() {
    final dir = Directory(
        '${temp.path}${Platform.pathSeparator}${PrivateMediaCache.storeKey}');
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  Future<void> settle() => PrivateMediaImages.debugMigrationsSettled();

  void pathProvider({bool failTemp = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => support.path,
        'getTemporaryDirectory' =>
          failTemp ? throw PlatformException(code: 'unavailable') : temp.path,
        'getApplicationDocumentsDirectory' => documents.path,
        _ => null,
      },
    );
  }

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m1d_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async => oldCacheRemovals++;
    await OfflineMediaService.instance.initialize();
    await AppLocalizations.preloadAllLanguages();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      documents.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('m1d_support_');
    temp = Directory.systemTemp.createTempSync('m1d_temp_');
    pathProvider();
    transport = _Transport();
    scope = _sA1;
    cache = open();
    PrivateMediaImages.cache = () => cache;
    PrivateMediaImages.debugForgetMigrations();
    PrivateMediaImages.debugOnMigration =
        (key, outcome) => outcomes.add(outcome);
    legacy = {};
    legacyReads.clear();
    outcomes.clear();
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
    // The old cache is only ever read, never asked to download or remove.
    expect(legacyReads.where((read) => !read.endsWith('|null')), isEmpty);
    expect(oldCacheRemovals, 0);
    await cache.dispose().timeout(const Duration(seconds: 2), onTimeout: () {});
    PrivateMediaImages.cache = () => PrivateMediaCache.instance;
    PrivateMediaImages.debugOnMigration = null;
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
  group('an old copy is copied when it is shown', () {
    for (final kind in ['Offer', 'Owner']) {
      test('$kind image: shown from the old cache, copied once, no network',
          () async {
        // Offer and Owner media share `offer-media:<account>:<id>` and the
        // catalogue box; only the record id differs.
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        final modified = old.lastModifiedSync();

        final shown = await PrivateMediaImages.load(key, signedUrl: _link(1));
        expect(shown!.path, old.path, reason: 'the display path is unchanged');
        await settle();

        expect(outcomes, ['adopted']);
        final copy = await cache.cached(key);
        expect(copy, isNotNull);
        expect(copy!.path, isNot(old.path));
        expect(copy.readAsBytesSync(), _png);
        expect(transport.urls, isEmpty, reason: 'no download');
        expect(old.readAsBytesSync(), _png, reason: 'old entry kept');
        expect(old.lastModifiedSync(), modified);
        // M1d-2: the mapping now names the verified copy, keeping the old
        // path as its fallback.
        expect(mapped(key), copy.path);
        expect(OfflineMediaService.instance.previousCopyPathForMediaId(key),
            old.path);
      });
    }

    test('an item the Worker resolved in this run is trusted as an image',
        () async {
      final key = _key(_a, _mediaId());
      OfferMediaUrlCache.instance
          .put(key, _link(5), DateTime.now().add(const Duration(minutes: 10)));
      oldCopy(key, _png);
      await PrivateMediaImages.load(key);
      await settle();
      expect(outcomes, ['adopted']);
      expect(transport.urls, isEmpty);
    });

    test('shown at once while the copy is still being made', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      final gate = Completer<void>();
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step == 'written') await gate.future;
      };

      final shown = await PrivateMediaImages.load(key, signedUrl: _link(1));
      expect(shown!.path, old.path);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(outcomes, isEmpty, reason: 'the copy is still being made');
      // Reopening meanwhile paints the same file, also at once.
      expect((await PrivateMediaImages.load(key))!.path, old.path);

      gate.complete();
      await settle();
      expect(outcomes, ['adopted']);
    });

    test('no link is asked for and nothing is downloaded, now or later',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      await PrivateMediaImages.load(key, signedUrl: _link(1));
      await settle();

      var asked = 0;
      final copy = await cache.get(key, signedUrl: () async {
        asked++;
        return _link(2);
      });
      expect(copy, isNotNull);
      expect(asked, 0, reason: 'no signing request');
      for (var i = 0; i < 3; i++) {
        await PrivateMediaImages.load(key, signedUrl: _link(3 + i));
      }
      expect(transport.urls, isEmpty);
      expect(steps.where((s) => s == 'source_read'), hasLength(1));
      expect(outcomes, ['adopted'], reason: 'settled: no further attempts');
    });

    test('an unverified copy is never handed out', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      final gate = Completer<void>();
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step != 'written') return;
        await gate.future;
        file.writeAsBytesSync(_png.sublist(0, 10)); // fails the read-back
      };
      await PrivateMediaImages.load(key);
      while (!steps.contains('written')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // Asked while the copy is written but not yet verified.
      File? handed;
      var answered = false;
      final meanwhile = cache.cached(key).then((file) {
        handed = file;
        answered = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(answered, isFalse, reason: 'waits for the read-back');
      gate.complete();
      await meanwhile;
      expect(handed, isNull, reason: 'the copy failed its read-back');
      await settle();
      expect(outcomes, ['failed']);
    });
  });

  // ---------------------------------------------------------------------
  group('nothing is copied', () {
    test('when a valid private copy is already held; it is not replaced',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final held = await cache.get(key, signedUrl: () async => _link(1));
      final old = oldCopy(key, _jpeg(64));
      await OfflineMediaService.instance.mapMediaIdToLocalFile(key, old.path);

      expect((await PrivateMediaImages.load(key))!.path, old.path);
      await settle();
      expect(outcomes, ['alreadyHeld']);
      expect(steps, isEmpty, reason: 'the old copy is not even read');
      expect(await cache.adopt(key, old, origin: _sA1),
          PrivateMediaAdoption.alreadyHeld);
      final still = await cache.cached(key);
      expect(still!.path, held!.path);
      expect(still.readAsBytesSync(), _png);
    });

    test('while the private cache is downloading the item', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      transport.gate = Completer<void>();
      final download = cache.get(key, signedUrl: () async => _link(1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final old = oldCopy(key, _jpeg(64));

      expect(await cache.adopt(key, old, origin: _sA1),
          PrivateMediaAdoption.inProgress);
      transport.gate!.complete();
      expect((await download)!.readAsBytesSync(), _png,
          reason: 'the download is not overwritten');
      expect(steps, isEmpty);
    });

    test('a download asked for during the copy waits and reuses it', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      Future<File?>? download;
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step != 'source_read') return;
        // The same item is asked for, with a link, while it is copied.
        download = cache.get(key, signedUrl: () async => _link(1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      };
      await PrivateMediaImages.load(key);
      await settle();
      final copy = await download;
      expect(outcomes, ['adopted']);
      expect(copy!.path, (await cache.cached(key))!.path);
      expect(copy.readAsBytesSync(), _png);
      expect(transport.urls, isEmpty, reason: 'no second writer, no download');
      expect(privateFiles(), hasLength(1));
    });

    test('when the mapping names an adopted original, not the old cache',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _jpeg(64)); // the old cache also has an entry
      final original = File('${documents.path}${Platform.pathSeparator}'
          'original-${_uuid('ff')}.png')
        ..writeAsBytesSync(_png);
      await OfflineMediaService.instance
          .mapMediaIdToLocalFile(key, original.path);
      expect((await PrivateMediaImages.load(key))!.path, original.path);
      await settle();
      expect(outcomes, ['notPrevious']);
      expect(steps, isEmpty);
      expect(privateFiles(), isEmpty);
    });

    test('across accounts, even for the same media id', () async {
      final media = _mediaId();
      final keyA = _key(_a, media);
      final keyB = _key(_b, media);
      await trust(_a, media);
      await trust(_b, media);
      final oldA = oldCopy(keyA, _png);

      scope = _sB;
      expect(await PrivateMediaImages.load(keyA), isNull);
      expect(await PrivateMediaImages.load(keyB), isNull,
          reason: 'B has no old copy of its own');
      await settle();
      expect(outcomes, isEmpty);
      expect(await cache.adopt(keyA, oldA, origin: _sB),
          PrivateMediaAdoption.notAllowed);
      expect(await cache.adopt(keyA, oldA, origin: _sA1),
          PrivateMediaAdoption.notAllowed,
          reason: 'not the current session');
      expect(privateFiles(), isEmpty);

      scope = _sA1;
      await PrivateMediaImages.load(keyA);
      await settle();
      expect(outcomes, ['adopted']);
      scope = _sB;
      expect(await cache.cached(keyA), isNull);
      expect(await cache.cached(keyB), isNull, reason: 'A\'s copy is not B\'s');
    });

    test('for a media id nothing trusted names; it is not even read', () async {
      // Neither this account's catalogue nor this run's Worker answer.
      final unknown = _key(_a, _mediaId());
      oldCopy(unknown, _png);
      // Another account's catalogue does not vouch for this account's key.
      final elsewhere = _mediaId();
      await trust(_b, elsewhere);
      oldCopy(_key(_a, elsewhere), _png);
      // The Worker said video: not an image, whatever the catalogue says.
      final video = _mediaId();
      await trust(_a, video);
      OfferMediaUrlCache.instance.put(_key(_a, video), _link(1),
          DateTime.now().add(const Duration(minutes: 10)),
          isVideo: true);
      oldCopy(_key(_a, video), _png);
      // A still frame's key is not a media id.
      final pictured = _mediaId();
      await trust(_a, pictured);
      final poster = offerMediaPosterKey(_key(_a, pictured));
      oldCopy(poster, _png);

      for (final key in [
        unknown,
        _key(_a, elsewhere),
        _key(_a, video),
        poster
      ]) {
        expect(await PrivateMediaImages.load(key), isNotNull,
            reason: 'shown exactly as before');
      }
      await settle();
      expect(outcomes, List.filled(4, 'untrusted'));
      expect(steps, isEmpty);
      expect(privateFiles(), isEmpty);
    });

    test('for keys with no account: link-keyed and resized entries', () async {
      final media = _mediaId();
      await trust(_a, media);
      final resized = 'resized_w400_h300_${_key(_a, media)}';
      for (final key in [_link(1), resized, media]) {
        oldCopy(key, _png);
        expect(await PrivateMediaImages.load(key), isNull);
      }
      await settle();
      expect(outcomes, isEmpty);
      expect(legacyReads, isEmpty, reason: 'not even looked up');
      expect(privateFiles(), isEmpty);
    });

    test('from a missing, evicted, damaged, video or empty old copy', () async {
      Future<String> trusted() async {
        final media = _mediaId();
        await trust(_a, media);
        return _key(_a, media);
      }

      // Missing: the old cache names a file that is gone.
      final missing = await trusted();
      legacy[missing] = '${temp.path}${Platform.pathSeparator}gone.png';
      expect(await PrivateMediaImages.load(missing), isNull);
      // Evicted after it was shown: the mapping points at nothing.
      final evicted = await trusted();
      final old = oldCopy(evicted, _png);
      await PrivateMediaImages.load(evicted);
      await settle();
      outcomes.clear();
      await cache.forget(evicted);
      old.deleteSync();
      expect(await PrivateMediaImages.load(evicted), isNull);
      // Damaged, a video container, empty: shown as before, never copied.
      final unusable = [
        List<int>.filled(64, 7),
        [0, 0, 0, 24, ...ascii.encode('ftypisom'), 0, 0, 2, 0],
        <int>[],
      ];
      for (final bytes in unusable) {
        final key = await trusted();
        final file = oldCopy(key, bytes);
        expect((await PrivateMediaImages.load(key))!.path, file.path);
      }
      await settle();
      expect(outcomes, List.filled(3, 'unusableSource'));
      expect(privateFiles(), isEmpty);
    });

    test('from an old copy over 10 MiB; exactly 10 MiB is copied', () async {
      final big = _mediaId();
      final edge = _mediaId();
      await trust(_a, big);
      await trust(_a, edge);
      oldCopy(_key(_a, big), _jpeg(PrivateMediaCache.maxBytes + 1));
      oldCopy(_key(_a, edge), _jpeg(PrivateMediaCache.maxBytes));
      await PrivateMediaImages.load(_key(_a, big));
      await settle();
      await PrivateMediaImages.load(_key(_a, edge));
      await settle();
      expect(outcomes, ['unusableSource', 'adopted']);
      expect(await cache.cached(_key(_a, big)), isNull);
      expect((await cache.cached(_key(_a, edge)))!.lengthSync(),
          PrivateMediaCache.maxBytes);
    });
  });

  // ---------------------------------------------------------------------
  group('session changes, interruptions and failures', () {
    for (final (name, next) in [
      ('signed out', null),
      ('account switched', _sB),
      ('session replaced', _sA2),
    ]) {
      test('$name while the old copy is read: nothing is stored', () async {
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        cache.debugOnAdoptStep = (step, file) async {
          steps.add(step);
          if (step == 'source_read') scope = next;
        };
        expect((await PrivateMediaImages.load(key))!.path, old.path);
        await settle();
        expect(outcomes, ['notAllowed']);
        expect(steps, ['source_read'], reason: 'never written');
        expect(privateFiles(), isEmpty);
        expect(old.readAsBytesSync(), _png);
        expect(mapped(key), old.path);
      });

      test('$name after the copy is written: the copy is removed', () async {
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        cache.debugOnAdoptStep = (step, file) async {
          steps.add(step);
          if (step == 'written') scope = next;
        };
        await PrivateMediaImages.load(key);
        await settle();
        expect(outcomes, ['notAllowed']);
        expect(steps, ['source_read', 'written']);
        expect(privateFiles(), isEmpty, reason: 'no copy outlives its session');
        expect(old.readAsBytesSync(), _png);
      });
    }

    test('a replaced session: the next display in the new one copies it',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step == 'source_read' && scope == _sA1) scope = _sA2;
      };
      await PrivateMediaImages.load(key);
      await settle();
      await PrivateMediaImages.load(key); // the mapping now names the old copy
      await settle();
      expect(outcomes, ['notAllowed', 'adopted']);
      expect(transport.urls, isEmpty);
    });

    test('interrupted while writing: no partial copy; the next display retries',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step == 'written') throw const FileSystemException('interrupted');
      };
      expect((await PrivateMediaImages.load(key))!.path, old.path);
      await settle();
      expect(outcomes, ['failed']);
      expect(privateFiles(), isEmpty);

      cache.debugOnAdoptStep = (step, file) async => steps.add(step);
      expect((await PrivateMediaImages.load(key))!.path, old.path);
      await settle();
      expect(outcomes, ['failed', 'adopted']);
      expect((await cache.cached(key))!.readAsBytesSync(), _png);
    });

    for (final (name, damage) in [
      ('shorter', (File f) => f.writeAsBytesSync(_png.sublist(0, 10))),
      (
        'same size, one byte different',
        (File f) {
          final bytes = Uint8List.fromList(_png);
          bytes[bytes.length - 1] ^= 0xFF;
          f.writeAsBytesSync(bytes);
        }
      ),
    ]) {
      test('the copy reads back $name: removed, the old copy stays shown',
          () async {
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        cache.debugOnAdoptStep = (step, file) async {
          steps.add(step);
          if (step == 'written') damage(file);
        };
        await PrivateMediaImages.load(key);
        await settle();
        expect(outcomes, ['failed']);
        expect(await cache.cached(key), isNull);
        expect(privateFiles(), isEmpty);
        expect((await PrivateMediaImages.load(key))!.path, old.path);
        expect(old.readAsBytesSync(), _png);
      });
    }

    test('the private cache cannot open: the old copy is still shown',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      await cache.dispose();
      pathProvider(failTemp: true);
      cache = open();
      expect((await PrivateMediaImages.load(key))!.path, old.path);
      await settle();
      expect(outcomes, ['failed']);
      pathProvider();
      expect(privateFiles(), isEmpty);
      expect(old.readAsBytesSync(), _png);
    });

    test('the screen closes during the copy: it still completes', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      unawaited(PrivateMediaImages.load(key)); // nobody waits for it
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();
      expect(outcomes, ['adopted']);
    });

    test('many displays at once: one copy, the old copy read once', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      final shown = await Future.wait([
        for (var i = 0; i < 5; i++)
          PrivateMediaImages.load(key, signedUrl: _link(i)),
      ]);
      for (var i = 0; i < 3; i++) {
        shown.add(await PrivateMediaImages.load(key));
      }
      expect(shown.map((f) => f!.path).toSet(), {old.path});
      await settle();
      expect(outcomes, ['adopted']);
      expect(steps.where((s) => s == 'source_read'), hasLength(1));
      expect(privateFiles(), hasLength(1));
      expect(transport.urls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('restart', () {
    test('after a restart the copy is found: no second copy, no network',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      await PrivateMediaImages.load(key);
      await settle();
      final copy = mapped(key); // M1d-2 switched the mapping to it
      await cache.dispose();
      cache = open();
      PrivateMediaImages.debugForgetMigrations(); // a new process
      steps.clear();

      expect((await PrivateMediaImages.load(key))!.path, copy);
      await settle();
      expect(outcomes, ['adopted', 'alreadyHeld']);
      expect(steps, isEmpty);
      expect(privateFiles(), hasLength(1));
      expect(transport.urls, isEmpty);
    });

    test('a copy left damaged by an interrupted write is made again', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      await PrivateMediaImages.load(key);
      await settle();
      privateFiles().single.writeAsBytesSync(_png.sublist(0, 7));
      await cache.dispose();
      cache = open();
      PrivateMediaImages.debugForgetMigrations();

      await PrivateMediaImages.load(key);
      await settle();
      expect(outcomes, ['adopted', 'adopted']);
      expect((await cache.cached(key))!.readAsBytesSync(), _png);
      expect(transport.urls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('nothing else changes', () {
    test(
        'the old entry and catalogue stay as they were; the mapping only '
        'switches to the verified copy (M1d-2)', () async {
      final media = _mediaId();
      final other = _mediaId();
      final key = _key(_a, media);
      final record = _uuid('dddddddd');
      await OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _a, offerId: record, mediaObjectIds: [media, other]);
      final catalogue = OfflineMediaService.instance
          .readOfferMediaCatalog(ownerId: _a, offerId: record);
      final old = oldCopy(key, _png);
      final modified = old.lastModifiedSync();

      await PrivateMediaImages.load(key);
      final mappingWhenShown = mapped(key); // recorded by M1c, as before
      expect(mappingWhenShown, old.path);
      await settle();

      expect(outcomes, ['adopted']);
      expect(mapped(key), (await cache.cached(key))!.path);
      expect(OfflineMediaService.instance.previousCopyPathForMediaId(key),
          mappingWhenShown);
      expect(
          OfflineMediaService.instance
              .readOfferMediaCatalog(ownerId: _a, offerId: record),
          catalogue);
      expect(old.readAsBytesSync(), _png);
      expect(old.lastModifiedSync(), modified);
      expect(legacy[key], old.path);
    });

    test('no signed link is persisted anywhere', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      OfferMediaUrlCache.instance
          .put(key, _link(42), DateTime.now().add(const Duration(minutes: 10)));
      oldCopy(key, _png);
      await PrivateMediaImages.load(key, signedUrl: _link(43));
      await settle();
      expect(outcomes, ['adopted']);
      await cache.dispose(); // writes the private index out
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
      expect(written.toString(), contains(PrivateMediaCache.pseudoUrlFor(key)),
          reason: 'the index holds the pseudo-URL');
    });

    testWidgets(
        'the gallery and the viewer paint the same image, now from the '
        'verified copy (M1d-2)', (tester) async {
      final media = _mediaId();
      final key = _key(_a, media);
      late File old;
      await tester.runAsync(() async {
        await trust(_a, media);
        old = oldCopy(key, _png);
        // The first display (as in M1c's tests, outside the fake-async zone,
        // where the cache's real file work cannot run).
        expect((await PrivateMediaImages.load(key, signedUrl: _link(1)))!.path,
            old.path);
        await settle();
      });
      expect(outcomes, ['adopted']);
      final copy = mapped(key)!; // the switched mapping
      expect(copy, isNot(old.path));
      expect(File(copy).readAsBytesSync(), old.readAsBytesSync());
      // As the Worker's answer gives it: the gallery shows only items with a
      // link or a local file.
      final refs = [
        OfferMediaRef(mediaObjectId: media, cacheKey: key, signedUrl: _link(1)),
      ];
      Widget app(Widget home) => MaterialApp(
            localizationsDelegates: _delegates,
            supportedLocales: const [Locale('en'), Locale('ar')],
            home: home,
          );
      String paintedFile() {
        final image = tester.widget<Image>(find.descendant(
            of: find.byType(PrivateMediaImage), matching: find.byType(Image)));
        final provider = image.image is ResizeImage
            ? (image.image as ResizeImage).imageProvider
            : image.image;
        return (provider as FileImage).file.path;
      }

      for (var pass = 0; pass < 2; pass++) {
        await tester.runAsync(() async {
          await tester.pumpWidget(app(Scaffold(
            body: SizedBox(
              height: 300,
              child: OptimizedMediaGalleryWidget(
                  key: ValueKey(pass), mediaRefs: refs),
            ),
          )));
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
          await settle();
        });
        await tester.pump();
        expect(paintedFile(), copy, reason: 'pass $pass');
      }
      await tester.runAsync(() async {
        await tester.pumpWidget(app(FullScreenMediaViewer(mediaRefs: refs)));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      final view = tester.widget<PhotoView>(find.byType(PhotoView));
      expect((view.imageProvider as FileImage).file.path, copy);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox()); // the screen closes
        await settle();
      });
      expect(outcomes, ['adopted']);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('final review: cleanup, sessions, formats', () {
    test('index row written after the cleanup: no bytes, nothing readable',
        () async {
      // The copy fails its read-back (same size, one byte different) while
      // the index row is still being written, as SQLite can order it.
      final index = _SlowInsertIndex()..gate = Completer<void>();
      await cache.dispose();
      cache = PrivateMediaCache(
          currentScope: () => scope,
          transport: transport,
          debugRepository: index);
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step != 'written') return;
        final bytes = Uint8List.fromList(_png);
        bytes[bytes.length - 1] ^= 0xFF;
        file.writeAsBytesSync(bytes);
      };
      await PrivateMediaImages.load(key);
      await settle();
      expect(outcomes, ['failed']);
      expect(privateFiles(), isEmpty, reason: 'no orphaned bytes');

      index.gate!.complete(); // the row lands now, naming a removed file
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cache.cached(key), isNull, reason: 'nothing readable');
      expect(await index.get(key), isNull, reason: 'the stray row is dropped');
      expect((await PrivateMediaImages.load(key))!.path, old.path);
    });

    test('repeated failed copies leave nothing behind', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final old = oldCopy(key, _png);
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step == 'written') file.writeAsBytesSync(_png.sublist(0, 9));
      };
      for (var i = 0; i < 5; i++) {
        expect((await PrivateMediaImages.load(key))!.path, old.path);
        await settle();
      }
      expect(outcomes, List.filled(5, 'failed'));
      expect(privateFiles(), isEmpty);
      await cache.dispose();
      cache = open();
      final rows = File('${support.path}${Platform.pathSeparator}'
          '${PrivateMediaCache.storeKey}.json');
      expect(!rows.existsSync() || !rows.readAsStringSync().contains(media),
          isTrue,
          reason: 'no index rows accumulate');
    });

    test('a replaced session\'s unverified copy is never seen by the new one',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _png);
      Future<File?>? newSession;
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step != 'written') return;
        scope = _sA2; // replaced once the bytes are written
        newSession = cache.cached(key); // and the new session asks at once
        await Future<void>.delayed(const Duration(milliseconds: 100));
      };
      await PrivateMediaImages.load(key);
      await settle();
      expect(outcomes, ['notAllowed']);
      expect(await newSession, isNull);
      expect(privateFiles(), isEmpty);
    });

    test('a new session\'s copy is never removed by the old one\'s cleanup',
        () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      oldCopy(key, _jpeg(64));
      Future<File?>? newSession;
      cache.debugOnAdoptStep = (step, file) async {
        steps.add(step);
        if (step != 'written' || scope != _sA1) return;
        // Replaced after the old session wrote; the new one fetches its own
        // copy while the old session's cleanup is still to come.
        scope = _sA2;
        newSession = cache.get(key, signedUrl: () async => _link(1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      };
      await PrivateMediaImages.load(key);
      await settle();
      final mine = await newSession;
      expect(outcomes, ['notAllowed']);
      expect(mine, isNotNull);
      expect(mine!.existsSync(), isTrue, reason: 'not removed by the cleanup');
      expect((await cache.cached(key))!.path, mine.path);
      expect(mine.readAsBytesSync(), _png);
      expect(transport.urls, hasLength(1));
    });

    for (final slowIndex in [false, true]) {
      test(
          'Delete Account during a copy cannot bring the copy back'
          '${slowIndex ? ' (index row written late)' : ''}', () async {
        final index = _SlowInsertIndex();
        if (slowIndex) {
          index.gate = Completer<void>();
          await cache.dispose();
          cache = PrivateMediaCache(
              currentScope: () => scope,
              transport: transport,
              debugRepository: index);
        }
        final media = _mediaId();
        final key = _key(_a, media);
        await trust(_a, media);
        final old = oldCopy(key, _png);
        cache.debugOnAdoptStep = (step, file) async {
          steps.add(step);
          if (step != 'written') return;
          // completeAccountDeletion: sign-out first, then the cleaner.
          scope = null;
          await cache.forgetAccount(_a);
        };
        await PrivateMediaImages.load(key);
        await settle();
        index.gate?.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(outcomes.single, anyOf('notAllowed', 'failed'));
        expect(privateFiles(), isEmpty);
        scope = _sA2; // even a session for that id could read nothing
        expect(await cache.cached(key), isNull);
        expect(old.readAsBytesSync(), _png, reason: 'the old cache is kept');
      });
    }

    test('HEIC is not copied: shown as before, nothing downloaded', () async {
      final media = _mediaId();
      final key = _key(_a, media);
      await trust(_a, media);
      final heic = [
        0, 0, 0, 24, ...ascii.encode('ftypheic'), 0, 0, 0, 0, //
        ...ascii.encode('mif1heic'),
      ];
      final old = oldCopy(key, heic);
      expect((await PrivateMediaImages.load(key, signedUrl: _link(1)))!.path,
          old.path);
      await settle();
      expect((await PrivateMediaImages.load(key, signedUrl: _link(2)))!.path,
          old.path);
      await settle();
      expect(outcomes, ['unusableSource'], reason: 'settled: not retried');
      expect(transport.urls, isEmpty, reason: 'no download for migration');
      expect(privateFiles(), isEmpty);
      expect(old.readAsBytesSync(), heic);
    });
  });

  // ---------------------------------------------------------------------
  group('Delete Account stays account-scoped', () {
    test('forgetAccount removes the deleted account\'s copies only', () async {
      final mediaA = _mediaId();
      final mediaB = _mediaId();
      await trust(_a, mediaA);
      await trust(_b, mediaB);
      final oldA = oldCopy(_key(_a, mediaA), _png);
      final oldB = oldCopy(_key(_b, mediaB), _png);
      await PrivateMediaImages.load(_key(_a, mediaA));
      await settle();
      scope = _sB;
      await PrivateMediaImages.load(_key(_b, mediaB));
      await settle();
      expect(outcomes, ['adopted', 'adopted']);

      expect(await cache.forgetAccount(_a), 1);
      expect(await cache.cached(_key(_b, mediaB)), isNotNull);
      scope = _sA2;
      expect(await cache.cached(_key(_a, mediaA)), isNull);
      expect(oldA.existsSync() && oldB.existsSync(), isTrue,
          reason: 'the old cache is not M1d-1\'s to clear');
    });
  });

  // ---------------------------------------------------------------------
  group('measurements (test VM, not a device)', () {
    test('five old copies: before and after M1d-1', () async {
      const n = 5;
      final keys = <String>[];
      final old = <File>[];
      for (var i = 0; i < n; i++) {
        final media = _mediaId();
        await trust(_a, media);
        keys.add(_key(_a, media));
        old.add(oldCopy(keys.last, _jpeg(200 * 1024)));
      }
      final clock = Stopwatch()..start();
      for (final key in keys) {
        await PrivateMediaImages.load(key, signedUrl: _link(1));
      }
      final shownMs = clock.elapsedMicroseconds / 1000;
      await settle();
      final copiedMs = clock.elapsedMicroseconds / 1000;
      final legacyHits = legacyReads.length;
      final growth =
          privateFiles().fold<int>(0, (sum, f) => sum + f.lengthSync());

      // The old copies are evicted later (shared 200-entry limit): every
      // image is still shown, from the private copy, with no download.
      for (var i = 0; i < n; i++) {
        old[i].deleteSync();
      }
      var privateHits = 0;
      for (final key in keys) {
        final file = await PrivateMediaImages.load(key, signedUrl: _link(2));
        if (file != null && file.path.contains(PrivateMediaCache.storeKey)) {
          privateHits++;
        }
      }
      expect(outcomes.where((o) => o == 'adopted'), hasLength(n));
      expect(privateHits, n);
      expect(transport.urls, isEmpty);
      expect(growth, n * 200 * 1024);
      // ignore: avoid_print
      print('M1d-1 VM: n=$n legacyHits=$legacyHits '
          'adopted=${outcomes.length} privateHitsAfterEviction=$privateHits '
          'downloads=${transport.urls.length} signing=0 '
          'diskGrowthBytes=$growth shownMs=${shownMs.toStringAsFixed(1)} '
          'allCopiedMs=${copiedMs.toStringAsFixed(1)}');
    });

    test('without M1d-1 (untrusted ids): eviction costs a download each',
        () async {
      const n = 5;
      final keys = <String>[];
      final old = <File>[];
      for (var i = 0; i < n; i++) {
        keys.add(_key(_a, _mediaId())); // no catalogue: never copied
        old.add(oldCopy(keys.last, _jpeg(1024)));
      }
      for (final key in keys) {
        await PrivateMediaImages.load(key, signedUrl: _link(1));
      }
      await settle();
      for (final file in old) {
        file.deleteSync();
      }
      for (final key in keys) {
        await PrivateMediaImages.load(key, signedUrl: _link(2));
      }
      expect(outcomes, List.filled(n, 'untrusted'));
      expect(transport.urls, hasLength(n));
      // ignore: avoid_print
      print('M1d-1 VM baseline: n=$n downloadsAfterEviction='
          '${transport.urls.length}');
    });
  });
}
