// M3b-1 (tracker §7AZ, D-M3-1(b)): Favorites and Search card photos are drawn
// through the account-scoped private image path (M1b/M1c `PrivateMediaImage`)
// when the caller opts in with `privateCache: true`; Smart Map does not opt
// in and keeps the shared image cache exactly as before.
//
// With the opt-in, a card photo:
//  - is drawn only for the current authorized session's account's key;
//  - prefers bytes this device holds (the mapping, then M1d-2's
//    `::previous-copy` fallback, then the private cache), with no download;
//  - fetches with its link only when nothing is held — into the private
//    cache, whose index keeps a fixed address, never the link — and never
//    through the shared cache;
//  - is decoded at the card's 600-pixel width;
//  - keeps the card's own placeholder while there is nothing to draw.
// A video keeps its still-frame path, untouched.
//
// Real files, Hive and private cache; `testWidgets` bodies do their real I/O
// inside `tester.runAsync` (a widget test body runs in a fake-async zone).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';
import 'package:broker_wallet/src/views/Widgets/private_card_media.dart';
import 'package:broker_wallet/src/views/Widgets/private_media_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _s1 = 'session-1';
const _s2 = 'session-2';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'abababab-abab-4bab-8bab-${(++_n).toString().padLeft(12, '0')}';

String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

String _link(int n) =>
    'https://r2.example/bucket/x.jpg?X-Amz-Expires=900&X-Amz-Signature=sig-$n';

class _Response implements FileServiceResponse {
  @override
  int get statusCode => 200;
  @override
  String get fileExtension => '.png';
  @override
  Stream<List<int>> get content => Stream.value(_png);
  @override
  int? get contentLength => _png.length;
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
    return _Response();
  }
}

const _fallbackKey = ValueKey('card-fallback');

Widget _card({
  required String cacheKey,
  String? signedUrl,
  bool isVideo = false,
  bool privateCache = true,
}) =>
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 200,
          child: PrivateCardMedia(
            cacheKey: cacheKey,
            isVideo: isVideo,
            signedUrl: signedUrl,
            fallback: const ColoredBox(key: _fallbackKey, color: Colors.grey),
            privateCache: privateCache,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;
  final sharedCacheCalls = <String>[]; // the old cache: "key|link"

  /// A held file the mapping points at.
  Future<File> mapped(String key) async {
    final file = File('${temp.path}${Platform.pathSeparator}m-${++_n}.png')
      ..writeAsBytesSync(_png);
    await OfflineMediaService.instance.mapMediaIdToLocalFile(key, file.path);
    return file;
  }

  /// The FileImage the card paints, and its decode width; null when none.
  (FileImage, int?)? painted(WidgetTester tester) {
    final images = find.byType(Image);
    if (images.evaluate().isEmpty) return null;
    final image = tester.widget<Image>(images.first);
    final provider = image.image;
    if (provider is ResizeImage) {
      final inner = provider.imageProvider;
      return inner is FileImage ? (inner, provider.width) : null;
    }
    return provider is FileImage ? (provider, null) : null;
  }

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('m3b1_docs_');
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

  setUp(() {
    OfflineMediaService.debugForgetDeletedAccounts();
    support = Directory.systemTemp.createTempSync('m3b1_support_');
    temp = Directory.systemTemp.createTempSync('m3b1_temp_');
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
    sharedCacheCalls.clear();
    OfflineMediaService.fetchCachedBytes = (key, url) async {
      sharedCacheCalls.add('$key|$url');
      return null;
    };
    OfferMediaUrlCache.instance.clear();
  });

  tearDown(() async {
    PrivateMediaImages.debugLoad = null;
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

  group('opted in (Favorites, Search)', () {
    testWidgets('a held photo (mapping) is painted from its file at 600 px',
        (tester) async {
      final key = _key(_a, _id());
      late File file;
      await tester.runAsync(() async {
        file = await mapped(key);
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(1)));
      });
      expect(find.byType(PrivateMediaImage), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      final shown = painted(tester);
      expect(shown, isNotNull);
      expect(shown!.$1.file.path, file.path);
      expect(shown.$2, 600, reason: 'decoded at the card width');
      expect(transport.urls, isEmpty, reason: 'nothing downloaded');
      expect(sharedCacheCalls, isEmpty, reason: 'the old cache is not used');
    });

    testWidgets(
        'the private copy was evicted: the previous file is shown '
        '(M1d-2 fallback)', (tester) async {
      final key = _key(_a, _id());
      late File previous;
      await tester.runAsync(() async {
        previous = await mapped(key);
        final gone = '${temp.path}${Platform.pathSeparator}evicted.png';
        expect(
            await OfflineMediaService.instance.replaceMediaIdMapping(key,
                expected: previous.path,
                replacement: gone,
                previous: previous.path),
            isTrue);
        await tester.pumpWidget(_card(cacheKey: key));
      });
      expect(painted(tester)?.$1.file.path, previous.path);
      expect(transport.urls, isEmpty);
    });

    testWidgets(
        'bytes only in the private cache (no mapping): found and painted, '
        'with no download', (tester) async {
      final key = _key(_a, _id());
      await tester.runAsync(() async {
        expect(
            await cache.get(key, signedUrl: () async => _link(0)), isNotNull);
        expect(OfflineMediaService.instance.getLocalFilePathForMediaId(key),
            isNull);
        transport.urls.clear();
        await tester.pumpWidget(_card(cacheKey: key));
        await PrivateMediaImages.debugMigrationsSettled();
        for (var i = 0; i < 20 && painted(tester) == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await tester.pump();
        }
      });
      expect(painted(tester), isNotNull);
      expect(painted(tester)!.$2, 600);
      expect(transport.urls, isEmpty, reason: 'held: no download');
      expect(sharedCacheCalls, isEmpty);
    });

    testWidgets('nothing held and no link: the card\'s own placeholder',
        (tester) async {
      final key = _key(_a, _id());
      await tester.runAsync(() async {
        await tester.pumpWidget(_card(cacheKey: key));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      expect(painted(tester), isNull);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(transport.urls, isEmpty);
    });

    testWidgets(
        'nothing held, a link: one download into the private cache, never the '
        'old cache, and no link in its index', (tester) async {
      final key = _key(_a, _id());
      await tester.runAsync(() async {
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(7)));
        for (var i = 0; i < 40 && painted(tester) == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await tester.pump();
        }
      });
      expect(painted(tester), isNotNull);
      expect(transport.urls, [_link(7)], reason: 'one download, by its link');
      expect(sharedCacheCalls.where((c) => !c.endsWith('|null')), isEmpty,
          reason: 'no old-cache download by link (a read-only look is all)');
      // The private cache's files keep no signed link.
      for (final f in support.listSync(recursive: true).whereType<File>()) {
        if (!f.path.contains('bwPrivateMedia')) continue;
        final text = latin1.decode(f.readAsBytesSync(), allowInvalid: true);
        for (final marker in ['X-Amz', 'r2.example', 'sig-7']) {
          expect(text.contains(marker), isFalse, reason: '${f.path}: $marker');
        }
      }
    });

    testWidgets('a held image is not fetched again when the card rebuilds',
        (tester) async {
      final key = _key(_a, _id());
      await tester.runAsync(() async {
        await mapped(key);
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(1)));
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(2)));
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(3)));
      });
      expect(painted(tester), isNotNull);
      expect(transport.urls, isEmpty, reason: 'a new link is not a new fetch');
      expect(sharedCacheCalls, isEmpty);
    });

    testWidgets('another account\'s key is never read, even if mapped',
        (tester) async {
      final key = _key(_b, _id());
      await tester.runAsync(() async {
        await mapped(key);
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(1)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      expect(painted(tester), isNull);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(transport.urls, isEmpty, reason: 'nor fetched for it');
    });

    testWidgets('signed out, or the session not authorized: nothing is read',
        (tester) async {
      final key = _key(_a, _id());
      scope = null;
      await tester.runAsync(() async {
        await mapped(key);
        await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(1)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      expect(painted(tester), isNull);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(transport.urls, isEmpty);
    });

    testWidgets(
        'the session changes while the image is looked up: the late answer '
        'is not shown', (tester) async {
      final key = _key(_a, _id());
      await tester.runAsync(() async {
        expect(
            await cache.get(key, signedUrl: () async => _link(0)), isNotNull);
        // The card is built and its lookup started; before the lookup's first
        // wait ends, this device's session is replaced (no longer authorized).
        final pumping = tester.pumpWidget(_card(cacheKey: key));
        scope = null;
        await pumping;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump();
      });
      expect(painted(tester), isNull,
          reason: 'what the replaced session looked up is not drawn');
      expect(find.byKey(_fallbackKey), findsOneWidget);
    });

    testWidgets(
        'same account, a new authorized session: the new session reads its '
        'own copy', (tester) async {
      final key = _key(_a, _id());
      await tester.runAsync(() async {
        await mapped(key);
        scope = const PrivateMediaScope(account: _a, session: _s2);
        await tester.pumpWidget(_card(cacheKey: key));
      });
      expect(painted(tester), isNotNull,
          reason: 'the key is the account\'s; the new session may read it');
    });

    testWidgets('a card closed while loading takes no late answer',
        (tester) async {
      final key = _key(_a, _id());
      final answer = Completer<File?>();
      PrivateMediaImages.debugLoad = (k, link) => answer.future;
      await tester.pumpWidget(_card(cacheKey: key, signedUrl: _link(1)));
      await tester.pumpWidget(const SizedBox());
      answer.complete(File('unused'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no setState after close');
    });

    testWidgets('a video keeps its still-frame path', (tester) async {
      final key = _key(_a, _id());
      await tester
          .pumpWidget(_card(cacheKey: key, signedUrl: _link(1), isVideo: true));
      expect(find.byType(OfferVideoPoster), findsOneWidget);
      expect(find.byType(PrivateMediaImage), findsNothing);
      expect(sharedCacheCalls, isEmpty, reason: 'a video is never kept');
    });
  });

  group('not opted in (Smart Map): unchanged', () {
    testWidgets('a link: the shared cache keeps the photo, as before',
        (tester) async {
      final key = _key(_a, _id());
      await tester.pumpWidget(
          _card(cacheKey: key, signedUrl: _link(1), privateCache: false));
      expect(find.byType(PrivateMediaImage), findsNothing);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(sharedCacheCalls, ['$key|${_link(1)}'],
          reason: 'the old keep-on-device call, unchanged');
    });
  });

  group('who opts in', () {
    String squash(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    test('Favorites and Search cards opt in; Smart Map does not', () {
      for (final card in [
        'lib/src/views/Screens/home/favorites/favorites_card.dart',
        'lib/src/views/Screens/home/search/widgets/search_result_card.dart',
      ]) {
        expect(
            squash(card).contains('return PrivateCardMedia( '
                'cacheKey: media.cacheKey, isVideo: media.isVideo, '
                'signedUrl: media.signedUrl, posterPath: media.posterPath, '
                'fallback: _GradientIcon(type: widget.type, '
                'typeIcon: widget.typeIcon), privateCache: true, );'),
            isTrue,
            reason: card);
      }
      expect(
          squash('lib/src/views/Screens/home/map/map_view.dart')
              .contains('privateCache'),
          isFalse,
          reason: 'Smart Map keeps the shared cache (D-M3-1(b))');
    });

    test('the opt-in is off unless asked for', () {
      expect(
          squash('lib/src/views/Widgets/private_card_media.dart')
              .contains('this.privateCache = false,'),
          isTrue);
    });
  });
}
