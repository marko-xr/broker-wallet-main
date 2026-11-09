// M1c (tracker §7AZ): Offer and Owner detail images through the private
// image cache (M1b).
//
// The resolver order under test, for an account-scoped key
// `offer-media:<account>:<mediaId>` (Offer and Owner media share it):
//  1. the file this device maps for the key (an adopted original, or a copy an
//     earlier open recorded) — only for the current session's account;
//  2. the private cache's copy;
//  3. the image cache in use before M1c, read only, with no network;
//  4. one download through the private cache with the link already in hand.
// Whatever was found is recorded in the existing `url_mapping` box (a file
// path, never a link), so the next cold or offline open paints at once.
//
// Real files and Hive are used. Widget tests that need real I/O run it inside
// `tester.runAsync`, because a `testWidgets` body runs in a fake-async zone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart'
    show OfferMediaException;
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offer_details_load_coordinator.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/views/Widgets/private_media_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/testing.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _s1 = 'session-1';
const _s2 = 'session-2';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

/// Everything a signed R2 link carries that must never reach the disk.
const _signedMarkers = ['X-Amz', 'r2.example', 'sig-'];

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Mounts [widget] and lets the localizations load.
Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
}

var _ids = 0;

/// A fresh media id per use, so tests sharing the Hive mapping never collide.
String _mediaId() {
  _ids++;
  return 'aaaaaaaa-aaaa-4aaa-8aaa-${_ids.toString().padLeft(12, '0')}';
}

String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

String _link(int n) =>
    'https://r2.example/bucket/x.jpg?X-Amz-Expires=900&X-Amz-Signature=sig-$n';

class _Response implements FileServiceResponse {
  _Response(this.bytes, {this.statusCode = 200});

  final List<int> bytes;
  @override
  final int statusCode;
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

/// Stands in for the network: counts downloads and records the links used.
class _Transport extends FileService {
  final List<String> urls = [];
  Completer<void>? gate;
  FutureOr<FileServiceResponse> Function(String url)? answer;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    final g = gate;
    if (g != null) await g.future;
    final a = answer;
    if (a != null) return a(url);
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
          'email': 'm1c@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));
}

/// The Worker's media routes, unreachable (no network).
R2OfferMediaUploadService _unreachableWorker(
        sb.SupabaseClient client, MediaParent parent) =>
    R2OfferMediaUploadService(
      supabaseClient: client,
      parent: parent,
      httpClient:
          MockClient((_) async => throw const SocketException('offline')),
    );

OfferModel _offerRecord(String id, String owner) => OfferModel(
      id: id,
      userId: owner,
      offerType: 'rent',
      selectedCity: '',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: '',
      specificPropertyType: '',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      status: PropertyStatus.available,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      mediaUrls: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;
  final legacyReads = <String>[];
  Map<String, String> legacy = {};

  PrivateMediaCache open() =>
      PrivateMediaCache(currentScope: () => scope, transport: transport);

  String? mapped(String key) =>
      OfflineMediaService.instance.getLocalFilePathForMediaId(key);

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m1c_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async {};
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
    // Each test is a fresh run: an account an earlier test deleted is not
    // still refused (DA-MAP-1 keeps that in process memory only).
    OfflineMediaService.debugForgetDeletedAccounts();
    support = Directory.systemTemp.createTempSync('m1c_support_');
    temp = Directory.systemTemp.createTempSync('m1c_temp_');
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
    cache = open();
    PrivateMediaImages.cache = () => cache;
    legacy = {};
    legacyReads.clear();
    OfflineMediaService.fetchCachedBytes = (key, url) async {
      legacyReads.add('$key|$url');
      return legacy[key];
    };
    OfferMediaUrlCache.instance.clear();
  });

  tearDown(() async {
    // A store opened inside a widget test's fake-async zone never finishes
    // opening; nothing else is waiting on it.
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
  group('local hit: no link, no download', () {
    for (final kind in ['Offer', 'Owner']) {
      test('$kind image: one download, then none on every reopen', () async {
        // Offer and Owner media are both `offer-media:<account>:<id>`.
        final key = _key(_a, _mediaId());
        final first = await PrivateMediaImages.load(key, signedUrl: _link(1));
        expect(first!.readAsBytesSync(), _png);
        expect(mapped(key), first.path, reason: 'next open paints at once');
        for (var i = 2; i <= 4; i++) {
          final again = await PrivateMediaImages.load(key, signedUrl: _link(i));
          expect(again!.path, first.path);
        }
        expect(transport.urls, [_link(1)], reason: '1 download, 1 link used');
      });
    }

    test('three signed links for one media id: one download', () async {
      final key = _key(_a, _mediaId());
      final files = [
        for (var i = 1; i <= 3; i++)
          await PrivateMediaImages.load(key, signedUrl: _link(i)),
      ];
      expect(files.map((f) => f!.path).toSet(), hasLength(1));
      expect(transport.urls, hasLength(1));
    });

    test('two widgets asking at once share one download', () async {
      final key = _key(_a, _mediaId());
      transport.gate = Completer<void>();
      final both = [
        PrivateMediaImages.load(key, signedUrl: _link(1)),
        PrivateMediaImages.load(key, signedUrl: _link(2)),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      transport.gate!.complete();
      final files = await Future.wait(both);
      expect(files.map((f) => f?.path).toSet(), hasLength(1));
      expect(files.first, isNotNull);
      expect(transport.urls, hasLength(1));
    });

    test('expired link while the bytes are valid: shown, nothing fetched',
        () async {
      final key = _key(_a, _mediaId());
      await PrivateMediaImages.load(key, signedUrl: _link(1));
      transport.answer = (_) => _Response(const [], statusCode: 403);
      expect(
          await PrivateMediaImages.load(key, signedUrl: _link(2)), isNotNull);
      // Even with the mapping gone, the private copy needs no link.
      await OfflineMediaService.instance.mapMediaIdToLocalFile(key, '/gone');
      expect(await PrivateMediaImages.load(key, signedUrl: null), isNotNull);
      expect(transport.urls, hasLength(1));
    });

    test('a link still valid in memory is preferred to the one in hand',
        () async {
      final key = _key(_a, _mediaId());
      OfferMediaUrlCache.instance
          .put(key, _link(7), DateTime.now().add(const Duration(minutes: 10)));
      await PrivateMediaImages.load(key, signedUrl: _link(1));
      expect(transport.urls, [_link(7)]);
    });
  });

  group('offline and restart', () {
    test('a caller that goes away does not stop the download', () async {
      final key = _key(_a, _mediaId());
      transport.gate = Completer<void>();
      // Started, then never awaited: the screen that asked has closed.
      unawaited(PrivateMediaImages.load(key, signedUrl: _link(1)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      transport.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(PrivateMediaImages.heldNow(key), isNotNull,
          reason: 'kept for the next open');
      expect(
          await PrivateMediaImages.load(key, signedUrl: _link(2)), isNotNull);
      expect(transport.urls, hasLength(1));
    });

    test('offline reopen in the same session: shown, no request', () async {
      final key = _key(_a, _mediaId());
      await PrivateMediaImages.load(key, signedUrl: _link(1));
      transport.answer = (_) => throw const SocketException('offline');
      expect(PrivateMediaImages.heldNow(key), isNotNull,
          reason: 'first frame, synchronously');
      expect(await PrivateMediaImages.load(key, signedUrl: null), isNotNull);
      expect(transport.urls, hasLength(1));
    });

    test('after a restart the copy is shown with no download', () async {
      final key = _key(_a, _mediaId());
      await PrivateMediaImages.load(key, signedUrl: _link(1));
      await cache.dispose();
      cache = open();
      await OfflineMediaService.instance.mapMediaIdToLocalFile(key, '/gone');
      expect(
          await PrivateMediaImages.load(key, signedUrl: _link(2)), isNotNull);
      expect(transport.urls, hasLength(1));
      expect(mapped(key), isNot('/gone'), reason: 'mapping healed');
    });

    test('offline with nothing held: nothing shown, nothing stored', () async {
      final key = _key(_a, _mediaId());
      transport.answer = (_) => throw const SocketException('offline');
      expect(await PrivateMediaImages.load(key, signedUrl: _link(1)), isNull);
      expect(mapped(key), isNull);
      expect(await cache.cached(key), isNull);
    });

    test('no link and nothing held: nothing fetched', () async {
      final key = _key(_a, _mediaId());
      expect(await PrivateMediaImages.load(key, signedUrl: null), isNull);
      expect(await PrivateMediaImages.load(key, signedUrl: ''), isNull);
      expect(transport.urls, isEmpty);
    });
  });

  group('account and session isolation', () {
    test('another account cannot read this account\'s copy or mapping',
        () async {
      final media = _mediaId();
      final keyA = _key(_a, media);
      await PrivateMediaImages.load(keyA, signedUrl: _link(1));
      scope = const PrivateMediaScope(account: _b, session: _s2);

      expect(mapped(keyA), isNotNull, reason: 'the mapping is there');
      expect(PrivateMediaImages.heldNow(keyA), isNull);
      expect(await PrivateMediaImages.load(keyA, signedUrl: _link(2)), isNull);
      expect(transport.urls, hasLength(1), reason: 'B never fetched A\'s');
      // The same media id under B is B's own entry, fetched for B.
      expect(
          await PrivateMediaImages.load(_key(_b, media), signedUrl: _link(3)),
          isNotNull);
      expect(transport.urls, hasLength(2));
    });

    test('signed out: nothing; same account back: shown with no network',
        () async {
      final key = _key(_a, _mediaId());
      await PrivateMediaImages.load(key, signedUrl: _link(1));
      scope = null;
      expect(PrivateMediaImages.heldNow(key), isNull);
      expect(await PrivateMediaImages.load(key, signedUrl: _link(2)), isNull);
      scope = const PrivateMediaScope(account: _a, session: _s2);
      expect(PrivateMediaImages.heldNow(key), isNotNull);
      expect(
          await PrivateMediaImages.load(key, signedUrl: _link(3)), isNotNull);
      expect(transport.urls, hasLength(1));
    });

    for (final (name, next) in [
      ('account switched', const PrivateMediaScope(account: _b, session: _s2)),
      ('session superseded', null),
      ('session replaced', const PrivateMediaScope(account: _a, session: _s2)),
    ]) {
      test('$name during the download: dropped, nothing mapped', () async {
        final key = _key(_a, _mediaId());
        transport.gate = Completer<void>();
        final pending = PrivateMediaImages.load(key, signedUrl: _link(1));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        scope = next;
        transport.gate!.complete();
        expect(await pending, isNull);
        expect(mapped(key), isNull);
        scope = const PrivateMediaScope(account: _a, session: _s1);
        expect(await cache.cached(key), isNull);
      });
    }

    test('a key with no account (no stable identity) is never used', () async {
      expect(PrivateMediaImages.heldNow(_mediaId()), isNull);
      expect(await PrivateMediaImages.load(_mediaId(), signedUrl: _link(1)),
          isNull);
      expect(transport.urls, isEmpty);
      expect(legacyReads, isEmpty);
    });
  });

  group('the image cache in use before M1c', () {
    test('its copy is shown with no download, and is left as it is', () async {
      final key = _key(_a, _mediaId());
      final old = File('${temp.path}${Platform.pathSeparator}legacy.png')
        ..writeAsBytesSync(_png);
      legacy[key] = old.path;
      final file = await PrivateMediaImages.load(key, signedUrl: _link(1));
      expect(file!.path, old.path);
      expect(legacyReads, ['$key|null'], reason: 'read only: no link given');
      expect(transport.urls, isEmpty);
      expect(mapped(key), old.path);
      expect(old.readAsBytesSync(), _png);
      expect(await cache.cached(key), isNull, reason: 'no migration');
    });

    test('account switched while it is read: its copy is not handed over',
        () async {
      final key = _key(_a, _mediaId());
      final old = File('${temp.path}${Platform.pathSeparator}legacy-b.png')
        ..writeAsBytesSync(_png);
      OfflineMediaService.fetchCachedBytes = (k, url) async {
        scope = const PrivateMediaScope(account: _b, session: _s2);
        return old.path;
      };
      expect(await PrivateMediaImages.load(key, signedUrl: _link(1)), isNull);
      expect(mapped(key), isNull);
      expect(transport.urls, isEmpty);
    });

    test('an existing mapping (adopted original) wins and is kept', () async {
      final key = _key(_a, _mediaId());
      final original = File('${documents.path}${Platform.pathSeparator}'
          'adopted-${_ids.toString()}.png')
        ..writeAsBytesSync(_png);
      await OfflineMediaService.instance
          .mapMediaIdToLocalFile(key, original.path);
      expect(PrivateMediaImages.heldNow(key)!.path, original.path);
      expect((await PrivateMediaImages.load(key, signedUrl: _link(1)))!.path,
          original.path);
      expect(transport.urls, isEmpty);
      expect(legacyReads, isEmpty);
    });
  });

  group('missing, evicted or damaged copies', () {
    test('a vanished mapped file and an evicted copy: fetched again', () async {
      final key = _key(_a, _mediaId());
      final file = await PrivateMediaImages.load(key, signedUrl: _link(1));
      await cache.forget(key);
      expect(file!.existsSync(), isFalse);
      final again = await PrivateMediaImages.load(key, signedUrl: _link(2));
      expect(again!.readAsBytesSync(), _png);
      expect(transport.urls, hasLength(2));
      expect(mapped(key), again.path);
    });

    test('a truncated private copy is dropped and fetched again', () async {
      final key = _key(_a, _mediaId());
      final file = await PrivateMediaImages.load(key, signedUrl: _link(1));
      file!.writeAsBytesSync([1, 2]);
      await OfflineMediaService.instance.mapMediaIdToLocalFile(key, '/gone');
      final again = await PrivateMediaImages.load(key, signedUrl: _link(2));
      expect(again!.readAsBytesSync(), _png);
      expect(transport.urls, hasLength(2));
    });

    test('a failed fetch never removes a held copy', () async {
      final key = _key(_a, _mediaId());
      final file = await PrivateMediaImages.load(key, signedUrl: _link(1));
      transport.answer = (_) => throw const SocketException('offline');
      await PrivateMediaImages.load(_key(_a, _mediaId()), signedUrl: _link(2));
      expect(file!.existsSync(), isTrue);
      expect(await cache.cached(key), isNotNull);
    });
  });

  group('revocation and Delete Account stay account-scoped', () {
    test('a removed or revoked item leaves this cache too; others stay',
        () async {
      final media = _mediaId();
      final keyA = _key(_a, media);
      final other = _key(_a, _mediaId());
      await PrivateMediaImages.load(keyA, signedUrl: _link(1));
      await PrivateMediaImages.load(other, signedUrl: _link(2));
      scope = const PrivateMediaScope(account: _b, session: _s2);
      await PrivateMediaImages.load(_key(_b, media), signedUrl: _link(3));
      final removed = <String>[];
      final previous = OfflineMediaService.removePrivateBytes;
      OfflineMediaService.removePrivateBytes = (key) async {
        removed.add(key);
        await cache.forget(key);
      };
      try {
        await OfflineMediaService.instance
            .forgetOfferMediaItems(ownerId: _a, mediaObjectIds: [media]);
      } finally {
        OfflineMediaService.removePrivateBytes = previous;
      }
      expect(removed, [keyA]);
      expect(mapped(keyA), isNull);
      expect(await cache.cached(_key(_b, media)), isNotNull);
      scope = const PrivateMediaScope(account: _a, session: _s1);
      expect(await cache.cached(keyA), isNull);
      expect(await cache.cached(other), isNotNull);
    });

    test('by default revocation reaches the private cache', () {
      final source = File('lib/src/services/offline_media_service.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(source, contains('removePrivateBytes = _removePrivateBytes'));
      expect(source, contains('PrivateMediaCache.instance.forget(cacheKey)'));
    });

    test('Delete Account: forgetAccount removes only that account', () async {
      final media = _mediaId();
      await PrivateMediaImages.load(_key(_a, media), signedUrl: _link(1));
      scope = const PrivateMediaScope(account: _b, session: _s2);
      await PrivateMediaImages.load(_key(_b, media), signedUrl: _link(2));
      expect(await cache.forgetAccount(_a), 1);
      expect(await cache.cached(_key(_b, media)), isNotNull);
    });
  });

  group('signed links are never kept', () {
    test('neither the private index nor the mapping holds a link', () async {
      final key = _key(_a, _mediaId());
      for (var i = 1; i <= 3; i++) {
        await PrivateMediaImages.load(key, signedUrl: _link(i));
      }
      transport.answer = (url) => throw Exception('failed $url');
      await PrivateMediaImages.load(_key(_a, _mediaId()), signedUrl: _link(9));
      await cache.dispose();
      cache = open();
      await Hive.box('url_mapping').flush();
      final written = StringBuffer();
      for (final dir in [support, documents]) {
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (f.path.endsWith('.lock')) continue; // held open by Hive
          written.writeln(f.path);
          written
              .writeln(latin1.decode(f.readAsBytesSync(), allowInvalid: true));
        }
      }
      for (final marker in _signedMarkers) {
        expect(written.toString(), isNot(contains(marker)), reason: marker);
      }
      expect(mapped(key), startsWith(temp.path),
          reason: 'the mapping holds a file path');
    });
  });

  // ---------------------------------------------------------------------
  // ---------------------------------------------------------------------
  // Final review A: the shared mapping and Delete Account.
  group('the shared url_mapping after Delete Account', () {
    test('forgetting one account clears its mapping and private copy only',
        () async {
      final media = _mediaId();
      final offerA = _mediaId();
      final offerB = _mediaId();
      final keyA = _key(_a, media);
      final keyB = _key(_b, media);
      await OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _a, offerId: offerA, mediaObjectIds: [media]);
      await PrivateMediaImages.load(keyA, signedUrl: _link(1));
      scope = const PrivateMediaScope(account: _b, session: _s2);
      await OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _b, offerId: offerB, mediaObjectIds: [media]);
      await PrivateMediaImages.load(keyB, signedUrl: _link(2));
      final fileA = File(mapped(keyA)!);
      final fileB = File(mapped(keyB)!);

      final previous = OfflineMediaService.removePrivateBytes;
      OfflineMediaService.removePrivateBytes = cache.forget;
      try {
        // What DeletedAccountLocalDataCleaner runs for account A.
        await OfflineMediaService.instance.forgetOfferMedia(ownerId: _a);
        await cache.forgetAccount(_a);
      } finally {
        OfflineMediaService.removePrivateBytes = previous;
      }

      expect(mapped(keyA), isNull, reason: 'A\'s mapping is gone');
      expect(fileA.existsSync(), isFalse, reason: 'A\'s private file is gone');
      expect(mapped(keyB), fileB.path, reason: 'B\'s mapping is untouched');
      expect(fileB.existsSync(), isTrue);
      expect(PrivateMediaImages.heldNow(keyB)!.path, fileB.path);
      expect(
          OfflineMediaService.instance
              .readOfferMediaCatalog(ownerId: _b, offerId: offerB),
          [media]);
    });

    test('a mapping whose private file was evicted fails safely', () async {
      final key = _key(_a, _mediaId());
      final file = await PrivateMediaImages.load(key, signedUrl: _link(1));
      file!.deleteSync(); // evicted or purged by the system
      expect(PrivateMediaImages.heldNow(key), isNull);
      transport.answer = (_) => throw const SocketException('offline');
      expect(await PrivateMediaImages.load(key, signedUrl: _link(2)), isNull);
    });
  });

  // ---------------------------------------------------------------------
  // Final review B: reopening offline when the Worker cannot be reached,
  // through the real catalogue reader and the real media resolution.
  group('offline reopen with the Worker unreachable', () {
    late _SignedIn backend;
    late SupabaseCoreEntitiesService service;

    setUp(() async {
      backend = _SignedIn(_a);
      await backend.signIn();
      service = SupabaseCoreEntitiesService(
        client: backend.client,
        offerMedia: _unreachableWorker(backend.client, MediaParent.offer),
        ownerMedia: _unreachableWorker(backend.client, MediaParent.owner),
      );
    });

    /// A first, online open on this device: the resolution remembered the
    /// ids and the gallery fetched and mapped the image.
    Future<String> openedOnlineBefore(String recordId, String media) async {
      await OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _a, offerId: recordId, mediaObjectIds: [media]);
      final file =
          await PrivateMediaImages.load(_key(_a, media), signedUrl: _link(1));
      return file!.path;
    }

    for (final (entry, resolved) in [
      ('opened from a list, Search or Favorites', false),
      ('opened with an already-resolved record', true),
    ]) {
      test(
          'Offer $entry: the cached image is shown at once, without the '
          'Worker', () async {
        final offerId = _mediaId();
        final media = _mediaId();
        final path = await openedOnlineBefore(offerId, media);
        OfferMediaUrlCache.instance.clear(); // links are memory-only
        transport.answer = (_) => throw const SocketException('offline');

        final coordinator = OfferDetailsLoadCoordinator(
          initialOffer: _offerRecord(offerId, _a),
          initialMetadataResolved: resolved,
          loadMetadata: (_) async => throw const SocketException('offline'),
          resolveMedia: service.resolveOfferMedia,
          readCachedMedia: service.cachedOfferMedia,
          onChanged: () {},
        );
        // Before any network answer: the seed already draws it.
        expect(coordinator.hasRenderableMedia, isTrue);
        expect(coordinator.displayItems.single.localFilePath, path);
        expect(PrivateMediaImages.heldNow(_key(_a, media))!.path, path);

        await coordinator.load(); // the metadata read or the Worker fails
        expect(
            resolved
                ? coordinator.mediaLoadFailed
                : coordinator.metadataLoadFailed,
            isTrue);
        // The saved record's text is what the screen shows; it is unchanged.
        expect(coordinator.offer.id, offerId);
        expect(coordinator.mediaAccessRevoked, isFalse);
        expect(coordinator.hasRenderableMedia, isTrue, reason: 'still shown');
        expect(File(path).existsSync(), isTrue, reason: 'nothing deleted');
        expect(transport.urls, hasLength(1),
            reason: 'no image request offline');
      });
    }

    test('Owner: the same, through the Owner catalogue and routes', () async {
      final recordId = _mediaId();
      final media = _mediaId();
      final path = await openedOnlineBefore(recordId, media);
      OfferMediaUrlCache.instance.clear();

      final seeded = service.cachedOwnerMedia(recordId);
      expect(seeded.single.localFilePath, path);
      await expectLater(
          service.resolveOwnerMedia(ownerRecordId: recordId, ownerId: _a),
          throwsA(isA<OfferMediaException>()
              .having((e) => e.isAccessDenied, 'access denied', isFalse)));
      expect(File(path).existsSync(), isTrue);
    });

    test('without its mapping the seed cannot see the private copy', () async {
      // Characterises the limit: the first-frame seed is synchronous and
      // reads url_mapping; the private index is asynchronous.
      final offerId = _mediaId();
      final media = _mediaId();
      await openedOnlineBefore(offerId, media);
      OfferMediaUrlCache.instance.clear();
      await OfflineMediaService.instance
          .mapMediaIdToLocalFile(_key(_a, media), '/gone');
      expect(service.cachedOfferMedia(offerId), isEmpty);
      expect(await cache.cached(_key(_a, media)), isNotNull,
          reason: 'the bytes are still held');
    });
  });

  group('the gallery and the full-screen viewer', () {
    Widget gallery(List<OfferMediaRef> refs) => MaterialApp(
          localizationsDelegates: _delegates,
          supportedLocales: const [Locale('en'), Locale('ar')],
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: OptimizedMediaGalleryWidget(
                mediaRefs: refs,
                imagePlaceholder: const Text('loading-placeholder'),
              ),
            ),
          ),
        );

    testWidgets(
        'a private item is drawn by PrivateMediaImage, never by '
        'the old network image', (tester) async {
      scope = null; // structure only: nothing is read
      final key = _key(_a, _mediaId());
      await _show(
          tester,
          gallery([
            OfferMediaRef(
                mediaObjectId: 'm', cacheKey: key, signedUrl: _link(1)),
          ]));
      expect(find.byType(PrivateMediaImage), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
          tester
              .widget<PrivateMediaImage>(find.byType(PrivateMediaImage))
              .cacheKey,
          key);
    });

    testWidgets(
        'the warm-up of nearby items never hands a link to the old '
        'cache', (tester) async {
      final keys = [for (var i = 0; i < 3; i++) _key(_a, _mediaId())];
      final asked = <String>[];
      PrivateMediaImages.debugLoad = (k, link) async {
        asked.add(k);
        return null;
      };
      addTearDown(() => PrivateMediaImages.debugLoad = null);
      await _show(
          tester,
          gallery([
            for (final k in keys)
              OfferMediaRef(mediaObjectId: k, cacheKey: k, signedUrl: _link(1)),
          ]));
      expect(legacyReads, isEmpty, reason: 'no old-cache download by link');
      expect(asked.toSet(), keys.toSet(), reason: 'current + next two warmed');
    });

    testWidgets('waiting with no link: the link that arrives is used',
        (tester) async {
      final key = _key(_a, _mediaId());
      final links = <String?>[];
      PrivateMediaImages.debugLoad = (k, link) async {
        links.add(link);
        return null;
      };
      addTearDown(() => PrivateMediaImages.debugLoad = null);
      Widget image(String? link) => MaterialApp(
          home: PrivateMediaImage(
              cacheKey: key,
              signedUrl: link,
              placeholder: const Text('wait'),
              errorWidget: const Text('failed')));
      await _show(tester, image(null));
      expect(find.text('wait'), findsOneWidget);
      await _show(tester, image(_link(5)));
      expect(links, [null, _link(5)]);
      expect(find.text('failed'), findsOneWidget,
          reason: 'a link in hand that still fails shows the error');
    });

    testWidgets('an item with no stable identity keeps the old path',
        (tester) async {
      await _show(
          tester,
          gallery([
            OfferMediaRef(
                mediaObjectId: '', cacheKey: null, signedUrl: _link(1)),
          ]));
      expect(find.byType(PrivateMediaImage), findsNothing);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('gallery order is the refs\' order', (tester) async {
      scope = null; // structure only: nothing is read
      final keys = [for (var i = 0; i < 3; i++) _key(_a, _mediaId())];
      await _show(
          tester,
          gallery([
            for (final k in keys)
              OfferMediaRef(mediaObjectId: k, cacheKey: k, signedUrl: _link(1)),
          ]));
      final shown = <String>[];
      for (var i = 0; i < keys.length; i++) {
        shown.add(tester
            .widget<PrivateMediaImage>(find.byType(PrivateMediaImage).first)
            .cacheKey);
        await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
        await tester.pumpAndSettle();
      }
      expect(shown, keys);
    });

    testWidgets('nothing held and no link yet: the existing placeholder',
        (tester) async {
      final key = _key(_a, _mediaId());
      await tester.runAsync(() async {
        await _show(
            tester,
            gallery([
              OfferMediaRef(mediaObjectId: 'm', cacheKey: key),
            ]));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.text('loading-placeholder'), findsOneWidget);
      expect(transport.urls, isEmpty);
    });

    testWidgets('a link that fails: the existing error with Retry',
        (tester) async {
      final key = _key(_a, _mediaId());
      transport.answer = (_) => _Response(const [], statusCode: 403);
      await tester.runAsync(() async {
        await _show(
            tester,
            gallery([
              OfferMediaRef(
                  mediaObjectId: 'm', cacheKey: key, signedUrl: _link(1)),
            ]));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    testWidgets('a held copy is painted from its file', (tester) async {
      final key = _key(_a, _mediaId());
      await tester.runAsync(() async {
        await PrivateMediaImages.load(key, signedUrl: _link(1));
        await _show(
            tester,
            gallery([
              OfferMediaRef(
                  mediaObjectId: 'm', cacheKey: key, signedUrl: _link(2)),
            ]));
      });
      final image = tester.widget<Image>(find.descendant(
          of: find.byType(PrivateMediaImage), matching: find.byType(Image)));
      final provider = image.image is ResizeImage
          ? (image.image as ResizeImage).imageProvider
          : image.image;
      expect(provider, isA<FileImage>());
      expect(transport.urls, hasLength(1));
    });

    testWidgets('closing the screen mid-load: the late answer is ignored',
        (tester) async {
      final key = _key(_a, _mediaId());
      final answer = Completer<File?>();
      final asked = <String>[];
      PrivateMediaImages.debugLoad = (k, link) {
        asked.add(k);
        return answer.future;
      };
      addTearDown(() => PrivateMediaImages.debugLoad = null);
      await _show(
          tester,
          gallery([
            OfferMediaRef(
                mediaObjectId: 'm', cacheKey: key, signedUrl: _link(1)),
          ]));
      expect(asked, contains(key));
      await _show(tester, const SizedBox()); // the screen closes
      answer.complete(File('unused'));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'no setState after dispose');
    });

    testWidgets('an undecodable copy fails safely to the error state',
        (tester) async {
      final key = _key(_a, _mediaId());
      final junk = File('${temp.path}${Platform.pathSeparator}junk.png')
        ..writeAsBytesSync(List<int>.filled(64, 7));
      await tester.runAsync(() =>
          OfflineMediaService.instance.mapMediaIdToLocalFile(key, junk.path));
      await tester.runAsync(() async {
        await _show(
            tester,
            gallery([
              OfferMediaRef(mediaObjectId: 'm', cacheKey: key),
            ]));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    testWidgets('full screen: held → its file; not held → the private cache',
        (tester) async {
      final held = _key(_a, _mediaId());
      final notHeld = _key(_a, _mediaId());
      final file = File('${temp.path}${Platform.pathSeparator}held.png')
        ..writeAsBytesSync(_png);
      await tester.runAsync(() =>
          OfflineMediaService.instance.mapMediaIdToLocalFile(held, file.path));
      for (final (key, expected) in [
        (held, isA<FileImage>()),
        (notHeld, isA<PrivateMediaImageProvider>()),
      ]) {
        await tester.runAsync(() async {
          await _show(
              tester,
              MaterialApp(
                localizationsDelegates: _delegates,
                supportedLocales: const [Locale('en'), Locale('ar')],
                home: FullScreenMediaViewer(key: ValueKey(key), mediaRefs: [
                  OfferMediaRef(
                      mediaObjectId: 'm', cacheKey: key, signedUrl: _link(1)),
                ]),
              ));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        final view = tester.widget<PhotoView>(find.byType(PhotoView));
        expect(view.imageProvider, expected);
        expect(find.byType(CachedNetworkImage), findsNothing);
      }
    });

    test('the full-screen provider is keyed by identity and link', () {
      final key = _key(_a, 'm');
      expect(PrivateMediaImageProvider(key, signedUrl: _link(1)),
          PrivateMediaImageProvider(key, signedUrl: _link(1)));
      expect(PrivateMediaImageProvider(key, signedUrl: _link(1)),
          isNot(PrivateMediaImageProvider(key, signedUrl: _link(2))));
    });

    test('the full-screen provider decodes the private copy', () async {
      final key = _key(_a, _mediaId());
      final completer = Completer<ImageInfo>();
      final stream = PrivateMediaImageProvider(key, signedUrl: _link(1))
          .resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener(
          (info, _) => completer.complete(info),
          onError: (e, _) => completer.completeError(e)));
      final info = await completer.future;
      expect(info.image.width, 1);
      expect(transport.urls, hasLength(1));
    });
  });
}
