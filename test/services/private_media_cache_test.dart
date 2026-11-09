// M1b (tracker §7AZ, D-M1a-1..5): the private image cache.
//
// Runs the production configuration (`bwPrivateMedia`, 200 entries, 30 days)
// with path_provider pointed at temporary folders. On this host the library
// picks its JSON index (`bwPrivateMedia.json`); on Android/iOS it picks the
// SQLite one (`bwPrivateMedia.db`) with the same fields, so reading the JSON
// shows exactly what the phone's index would hold.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _m1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _m2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _s1 = 'session-1';
const _s2 = 'session-2';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5]);

/// Everything a signed R2 link carries that must never reach the disk.
const _signedMarkers = ['X-Amz', 'r2.example', 'sig-', 'Signature'];

String _offerKey(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

/// Hands out a different signed link on every call, like the Worker.
class _Signer {
  int calls = 0;
  String? Function()? override;

  Future<String?> call() async {
    calls++;
    final o = override;
    if (o != null) return o();
    return 'https://r2.example/bucket/profiles/x.jpg'
        '?X-Amz-Expires=900&X-Amz-Signature=sig-$calls';
  }
}

class _Response implements FileServiceResponse {
  _Response(this.bytes, {this.statusCode = 200});

  final List<int> bytes;
  @override
  final int statusCode;
  @override
  String get fileExtension => '.jpg';

  @override
  Stream<List<int>> get content => Stream.value(bytes);
  @override
  int? get contentLength => bytes.length;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 7));
  @override
  String? get eTag => '"etag-from-r2"';
}

/// Stands in for the network: counts requests and records the links used.
class _Transport extends FileService {
  final List<String> urls = [];
  final List<Map<String, String>?> headers = [];
  Completer<void>? gate;
  FutureOr<FileServiceResponse> Function(String url)? answer;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    this.headers.add(headers);
    final g = gate;
    if (g != null) await g.future;
    final a = answer;
    if (a != null) return a(url);
    return _Response(_jpeg);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late Directory temp;
  late _Transport transport;
  late _Signer signer;
  PrivateMediaScope? scope;
  late PrivateMediaCache cache;
  final reports = <String>[];
  final printed = <String>[];
  late FlutterExceptionHandler? previousOnError;
  late DebugPrintCallback previousPrint;

  PrivateMediaCache open() => PrivateMediaCache(
        currentScope: () => scope,
        transport: transport,
      );

  /// Every byte this cache wrote that is not image bytes: the index and the
  /// file names.
  String persisted() {
    final buffer = StringBuffer();
    for (final dir in [support, temp]) {
      for (final entity in dir.listSync(recursive: true)) {
        buffer.writeln(entity.path);
        if (entity is File &&
            !entity.path.contains(
                '${PrivateMediaCache.storeKey}${Platform.pathSeparator}')) {
          buffer.writeln(
              utf8.decode(entity.readAsBytesSync(), allowMalformed: true));
        }
      }
    }
    return buffer.toString();
  }

  Future<List<Map<String, dynamic>>> index() async {
    await cache.dispose(); // writes the JSON index now
    cache = open();
    final file = File(
        '${support.path}${Platform.pathSeparator}${PrivateMediaCache.storeKey}.json');
    if (!file.existsSync()) return const [];
    return (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
  }

  List<File> storedFiles() {
    final dir = Directory(
        '${temp.path}${Platform.pathSeparator}${PrivateMediaCache.storeKey}');
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  setUp(() {
    support = Directory.systemTemp.createTempSync('m1b_support_');
    temp = Directory.systemTemp.createTempSync('m1b_temp_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => support.path,
        'getTemporaryDirectory' => temp.path,
        _ => null,
      },
    );
    transport = _Transport();
    signer = _Signer();
    scope = const PrivateMediaScope(account: _a, session: _s1);
    cache = open();
    reports.clear();
    printed.clear();
    previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => reports.add(details.toString());
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add('$message');
  });

  tearDown(() async {
    await cache.dispose();
    FlutterError.onError = previousOnError;
    debugPrint = previousPrint;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    for (final dir in [support, temp]) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('identity', () {
    test('profile key is account-scoped; Offer/Owner keys stay as they are',
        () {
      expect(
          PrivateMediaCache.profileMediaKey(accountId: _a, mediaObjectId: _m1),
          'profile-media:$_a:$_m1');
      expect(
          PrivateMediaCache.profileMediaKey(accountId: ' ', mediaObjectId: _m1),
          isNull);
      expect(
          PrivateMediaCache.profileMediaKey(accountId: _a, mediaObjectId: ''),
          isNull);
      expect(_offerKey(_a, _m1), 'offer-media:$_a:$_m1');
      expect(PrivateMediaCache.accountOf(_offerKey(_a, _m1)), _a);
      expect(
          PrivateMediaCache.accountOf(offerMediaPosterKey(_offerKey(_b, _m1))),
          _b);
      expect(PrivateMediaCache.accountOf('profile-media:$_b:$_m2'), _b);
      for (final bad in [
        '',
        _m1,
        'offer-media:',
        'offer-media::$_m1',
        'offer-media:$_a',
        'offer-media:$_a:',
        'other:$_a:$_m1'
      ]) {
        expect(PrivateMediaCache.accountOf(bad), isNull, reason: bad);
      }
    });

    test('the stored address is a fixed pseudo-URL made of the key only', () {
      final key = _offerKey(_a, _m1);
      final url = PrivateMediaCache.pseudoUrlFor(key);
      expect(url, startsWith('bw-private-media://v1/'));
      expect(url, contains(_m1));
      expect(PrivateMediaCache.pseudoUrlFor(key), url, reason: 'stable');
    });

    test('production settings: own store, 200 entries, 30 days unused', () {
      expect(PrivateMediaCache.storeKey, 'bwPrivateMedia');
      expect(PrivateMediaCache.storeKey, isNot(DefaultCacheManager.key));
      expect(PrivateMediaCache.maxEntries, 200);
      expect(PrivateMediaCache.unusedFor, const Duration(days: 30));
      expect(PrivateMediaCache.maxBytes, 10 * 1024 * 1024);
    });

    test('no application session: the shared instance has no scope', () {
      expect(PrivateMediaCache.applicationScope(), isNull);
    });
  });

  group('one download per media id, never per signed link', () {
    test('three different signed links for one item: one download', () async {
      final key = _offerKey(_a, _m1);
      for (var i = 0; i < 3; i++) {
        final file = await cache.get(key, signedUrl: signer.call);
        expect(file, isNotNull);
        expect(file!.readAsBytesSync(), _jpeg);
      }
      expect(transport.urls, hasLength(1));
      expect(signer.calls, 1, reason: 'a held copy needs no new link');
      expect(transport.headers.single ?? const {}, isEmpty,
          reason: 'no Authorization or If-None-Match sent to R2');
    });

    test('three callers at once: one link, one download, one file', () async {
      final key = _offerKey(_a, _m1);
      transport.gate = Completer<void>();
      final calls = [
        for (var i = 0; i < 3; i++) cache.get(key, signedUrl: signer.call)
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      transport.gate!.complete();
      final files = await Future.wait(calls);
      expect(files.map((f) => f?.path).toSet(), hasLength(1));
      expect(files.first, isNotNull);
      expect(transport.urls, hasLength(1));
      expect(signer.calls, 1);
      expect(storedFiles(), hasLength(1));
    });

    test('a held copy is shown with no network, even with an expired link',
        () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      // The old link has long expired and R2 would refuse any link now.
      transport.answer = (_) => _Response(const [], statusCode: 403);
      signer.override = () => throw StateError('must not be asked');

      expect((await cache.cached(key))!.readAsBytesSync(), _jpeg);
      expect((await cache.get(key, signedUrl: signer.call))!.readAsBytesSync(),
          _jpeg);
      expect(transport.urls, hasLength(1));
      expect(signer.calls, 1);
    });

    test('a replaced photo is a new media id, so a new entry', () async {
      await cache.get(_offerKey(_a, _m1), signedUrl: signer.call);
      await cache.get(_offerKey(_a, _m2), signedUrl: signer.call);
      expect(transport.urls, hasLength(2));
      expect(storedFiles(), hasLength(2));
    });
  });

  group('signed links are never kept', () {
    test('the index holds the pseudo-URL and key only', () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      await cache.get(key, signedUrl: signer.call);
      final rows = await index();
      expect(rows, hasLength(1));
      expect(rows.single['url'], PrivateMediaCache.pseudoUrlFor(key));
      expect(rows.single['key'], key);
      expect(rows.single['eTag'], isNull, reason: 'R2 ETag not kept');
      final everything = persisted();
      for (final marker in _signedMarkers) {
        expect(everything, isNot(contains(marker)), reason: marker);
      }
      expect(transport.urls.single, contains('X-Amz-Signature'),
          reason: 'the link was used, in memory');
    });

    test('after refusals, errors carrying the link, retries and a restart',
        () async {
      final key = _offerKey(_a, _m1);
      transport.answer = (_) => _Response(const [], statusCode: 403);
      expect(await cache.get(key, signedUrl: signer.call), isNull);
      transport.answer = (url) =>
          throw HttpExceptionWithStatus(500, 'x $url', uri: Uri.parse(url));
      expect(await cache.get(key, signedUrl: signer.call), isNull);
      transport.answer = (url) => throw Exception('failed $url');
      expect(await cache.get(key, signedUrl: signer.call), isNull);
      transport.answer = null;
      expect(await cache.get(key, signedUrl: signer.call), isNotNull);
      await cache.dispose();
      cache = open();
      expect(await cache.cached(key), isNotNull);

      expect(signer.calls, 4);
      final rows = await index();
      expect(rows.single['url'], PrivateMediaCache.pseudoUrlFor(key));
      final everything = [persisted(), ...reports, ...printed].join('\n');
      for (final marker in _signedMarkers) {
        expect(everything, isNot(contains(marker)), reason: marker);
      }
      expect(reports, isEmpty, reason: 'no error report at all');
    });
  });

  group('account and session isolation', () {
    test('another account cannot read this account\'s copy', () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      scope = const PrivateMediaScope(account: _b, session: _s2);

      expect(await cache.cached(key), isNull);
      expect(await cache.get(key, signedUrl: signer.call), isNull);
      expect(signer.calls, 1, reason: 'not even asked for a link');
      // The same media id under B is B's own, separate entry.
      expect(await cache.cached(_offerKey(_b, _m1)), isNull);
      expect(await cache.get(_offerKey(_b, _m1), signedUrl: signer.call),
          isNotNull);
      expect(transport.urls, hasLength(2));
    });

    test('a key that names no account is refused', () async {
      expect(await cache.get(_m1, signedUrl: signer.call), isNull);
      expect(await cache.cached(_m1), isNull);
      expect(signer.calls, 0);
      expect(transport.urls, isEmpty);
    });

    test('signed out: nothing shown or fetched; same account back: no network',
        () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      scope = null;
      expect(await cache.cached(key), isNull,
          reason: 'bytes alone are no permission');
      expect(await cache.get(key, signedUrl: signer.call), isNull);
      expect(storedFiles(), hasLength(1), reason: 'sign-out keeps the copy');

      scope = const PrivateMediaScope(account: _a, session: _s2);
      expect((await cache.cached(key))!.readAsBytesSync(), _jpeg);
      expect(transport.urls, hasLength(1));
      expect(signer.calls, 1);
    });

    for (final (name, next) in [
      ('session replaced', const PrivateMediaScope(account: _a, session: _s2)),
      ('account switched', const PrivateMediaScope(account: _b, session: _s2)),
      ('signed out', null),
    ]) {
      test('$name during the download: the late bytes are dropped', () async {
        final key = _offerKey(_a, _m1);
        transport.gate = Completer<void>();
        final pending = cache.get(key, signedUrl: signer.call);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        scope = next;
        transport.gate!.complete();
        expect(await pending, isNull);
        expect(storedFiles(), isEmpty, reason: 'nothing written');
        scope = const PrivateMediaScope(account: _a, session: _s1);
        expect(await cache.cached(key), isNull);
      });
    }

    test('account switched while a held copy is read: not handed over',
        () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      // Fires during the read's file-system wait, after the first check.
      Timer.run(
          () => scope = const PrivateMediaScope(account: _b, session: _s2));
      expect(await cache.cached(key), isNull);
    });

    test('account switched while the bytes are written: not handed over',
        () async {
      final key = _offerKey(_a, _m1);
      transport.answer = (_) {
        // Fires during the library's file write, after the last check in
        // the file service.
        Timer.run(
            () => scope = const PrivateMediaScope(account: _b, session: _s2));
        return _Response(_jpeg);
      };
      expect(await cache.get(key, signedUrl: signer.call), isNull);
    });

    test('session replaced while the link is signed: R2 is never asked',
        () async {
      signer.override = () {
        scope = const PrivateMediaScope(account: _a, session: _s2);
        return 'https://r2.example/x?X-Amz-Signature=sig-late';
      };
      expect(
          await cache.get(_offerKey(_a, _m1), signedUrl: signer.call), isNull);
      expect(transport.urls, isEmpty);
    });

    test('a caller of a replaced session does not share the new download',
        () async {
      final key = _offerKey(_a, _m1);
      transport.gate = Completer<void>();
      final old = cache.get(key, signedUrl: signer.call);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      scope = const PrivateMediaScope(account: _a, session: _s2);
      final fresh = cache.get(key, signedUrl: signer.call);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      transport.gate!.complete();
      expect(await old, isNull);
      // The new session's own request ran under its own authorization.
      expect(await fresh, isNotNull);
      expect(signer.calls, 2);
    });
  });

  group('misses fail safely', () {
    test('offline with no copy: nothing shown, nothing stored', () async {
      transport.answer = (_) => throw const SocketException('offline');
      expect(
          await cache.get(_offerKey(_a, _m1), signedUrl: signer.call), isNull);
      expect(storedFiles(), isEmpty);
      expect(await cache.cached(_offerKey(_a, _m1)), isNull);
    });

    test('no link (no access) and a failing signer: nothing fetched', () async {
      signer.override = () => null;
      expect(
          await cache.get(_offerKey(_a, _m1), signedUrl: signer.call), isNull);
      signer.override = () => throw StateError('worker said no');
      expect(
          await cache.get(_offerKey(_a, _m1), signedUrl: signer.call), isNull);
      expect(transport.urls, isEmpty);
    });

    test('empty or oversized answers are refused, nothing stored', () async {
      transport.answer = (_) => _Response(const []);
      expect(
          await cache.get(_offerKey(_a, _m1), signedUrl: signer.call), isNull);
      transport.answer =
          (_) => _Response(Uint8List(PrivateMediaCache.maxBytes + 1));
      expect(
          await cache.get(_offerKey(_a, _m1), signedUrl: signer.call), isNull);
      expect(storedFiles(), isEmpty);
    });

    test('a truncated copy is dropped and fetched again with authorization',
        () async {
      final key = _offerKey(_a, _m1);
      final file = await cache.get(key, signedUrl: signer.call);
      file!.writeAsBytesSync([0xFF, 0xD8]);
      expect(await cache.cached(key), isNull);
      expect(storedFiles(), isEmpty, reason: 'the broken copy is removed');
      expect((await cache.get(key, signedUrl: signer.call))!.readAsBytesSync(),
          _jpeg);
      expect(signer.calls, 2);
    });

    test('a vanished file is a miss', () async {
      final key = _offerKey(_a, _m1);
      (await cache.get(key, signedUrl: signer.call))!.deleteSync();
      expect(await cache.cached(key), isNull);
    });

    test('an evicted entry comes back only through authorization', () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      await cache.forget(key); // what eviction does: row and file gone
      expect(await cache.cached(key), isNull);
      expect(storedFiles(), isEmpty);
      signer.override = () => null; // access since revoked
      expect(await cache.get(key, signedUrl: signer.call), isNull);
      expect(transport.urls, hasLength(1));
    });

    test('a link the cache did not ask for is never fetched', () async {
      final service =
          PrivateMediaCache(currentScope: () => scope, transport: transport);
      // Anything outside get() — e.g. a library refresh — reaches the
      // service with no authorization and is refused.
      await expectLater(
          service.debugFileService
              .get(PrivateMediaCache.pseudoUrlFor(_offerKey(_a, _m1))),
          throwsA(isA<PrivateMediaUnavailable>()));
      expect(transport.urls, isEmpty);
      await service.dispose();
    });
  });

  group('restart and account deletion', () {
    test('after a restart the copy is shown with no network', () async {
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      await cache.dispose();
      cache = open();
      expect((await cache.cached(key))!.readAsBytesSync(), _jpeg);
      expect(transport.urls, hasLength(1));
    });

    test('forgetAccount removes that account only', () async {
      const near = '$_a-0'; // an id that starts with A's id
      await cache.get(_offerKey(_a, _m1), signedUrl: signer.call);
      await cache.get(offerMediaPosterKey(_offerKey(_a, _m1)),
          signedUrl: signer.call);
      await cache.get(
          PrivateMediaCache.profileMediaKey(accountId: _a, mediaObjectId: _m2)!,
          signedUrl: signer.call);
      scope = const PrivateMediaScope(account: _b, session: _s2);
      await cache.get(_offerKey(_b, _m1), signedUrl: signer.call);
      scope = const PrivateMediaScope(account: near, session: _s2);
      await cache.get(_offerKey(near, _m1), signedUrl: signer.call);
      expect(storedFiles(), hasLength(5));

      expect(await cache.forgetAccount(_a), 3);
      expect(storedFiles(), hasLength(2));
      expect(await cache.cached(_offerKey(near, _m1)), isNotNull);
      scope = const PrivateMediaScope(account: _b, session: _s2);
      expect(await cache.cached(_offerKey(_b, _m1)), isNotNull);
      scope = const PrivateMediaScope(account: _a, session: _s1);
      expect(await cache.cached(_offerKey(_a, _m1)), isNull);
      final keys = [for (final r in await index()) r['key']];
      expect(keys, unorderedEquals([_offerKey(_b, _m1), _offerKey(near, _m1)]));
      expect(await cache.forgetAccount(''), 0);
    });

    test('the image cache everyone else uses is never touched', () async {
      final legacyIndex = File(
          '${support.path}${Platform.pathSeparator}libCachedImageData.json')
        ..writeAsStringSync('[{"key":"legacy"}]');
      final legacyDir =
          Directory('${temp.path}${Platform.pathSeparator}libCachedImageData')
            ..createSync();
      final legacyFile =
          File('${legacyDir.path}${Platform.pathSeparator}a.file')
            ..writeAsBytesSync([5, 5]);
      final key = _offerKey(_a, _m1);
      await cache.get(key, signedUrl: signer.call);
      await cache.forget(key);
      await cache.get(key, signedUrl: signer.call);
      await cache.forgetAccount(_a);
      await cache.dispose();
      cache = open();
      expect(legacyIndex.readAsStringSync(), '[{"key":"legacy"}]');
      expect(legacyFile.readAsBytesSync(), [5, 5]);
      final source =
          File('lib/src/services/private_media_cache.dart').readAsStringSync();
      for (final banned in [
        'DefaultCacheManager',
        'emptyCache',
        'libCachedImageData'
      ]) {
        expect(source, isNot(contains(banned)), reason: banned);
      }
    });
  });

  group('Delete Account removes the deleted account\'s private copies', () {
    test('the cleaner asks for exactly that account', () async {
      final asked = <String>[];
      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
        forgetQuotationPdfs: (_) async => 0,
        forgetPrivateMedia: (uid) async {
          asked.add(uid);
          return 0;
        },
      ).clear(deletedUid: _a, wasSignedInAccount: false);
      expect(asked, [_a]);
    });

    test('by default it is the private cache\'s forgetAccount', () {
      final source =
          File('lib/src/services/deleted_account_local_data_cleaner.dart')
              .readAsStringSync();
      expect(source, contains('PrivateMediaCache.instance.forgetAccount'));
    });
  });

  group('the immutability this cache relies on (Worker contract)', () {
    final worker = File('cloudflare/workers/r2-profile-upload/worker.js')
        .readAsStringSync()
        .replaceAll('\r', '');

    String body(String name) {
      final start = worker.indexOf('async function $name(');
      expect(start, isNonNegative, reason: name);
      final end = worker.indexOf('\n}\n', start);
      return worker.substring(start, end);
    }

    test('every upload gets a new media id', () {
      expect(body('handleAuthorize'),
          contains('const mediaObjectId = crypto.randomUUID();'));
      expect(
          worker,
          contains(
              'const mediaObjectId = requestedId ?? crypto.randomUUID();'));
    });

    test('a ready item is never signed for upload again', () {
      final resume = body('resumeMediaUpload');
      final ready = resume.substring(
          resume.indexOf("case 'ready':"), resume.indexOf("case 'failed':"));
      expect(ready, isNot(contains('signMediaUpload')));
      expect(resume, contains("case 'pending_upload':"));
    });
  });
}
