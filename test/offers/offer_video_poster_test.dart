import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_video_poster_service.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Still frames of ready private Offer videos on a device that never had the
/// uploader's own frame (another device, or this one after a reinstall).
///
/// Local only: the frame maker is simulated; the platform's
/// `MediaMetadataRetriever` read of a real signed link is device-verified
/// separately.

const _ownerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _ownerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _link = 'https://r2.example.test/bucket/v.mp4?X-Amz-Signature=abc';

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

late Directory _root;
late Directory _docs;
late Directory _tmp;
var _seq = 0;

String _key(String owner) =>
    offerMediaCacheKey(ownerId: owner, mediaObjectId: 'video-${_seq++}')!;

void main() {
  final made = <String>[];
  String? session = _ownerA;
  Completer<void>? hold;
  var failNext = false;

  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('offer_poster_test_');
    _docs = await Directory('${_root.path}/docs').create();
    _tmp = await Directory('${_root.path}/tmp').create();
    Hive.init('${_root.path}/hive');
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.resolveDocumentsDirectory = () async => _docs;
    await OfflineMediaService.instance.initialize();
    OfferVideoPosterService.temporaryDirectory = () async => _tmp;
    OfferVideoPosterService.currentOwnerId = () => session;
    OfferVideoPosterService.generate = (url, target) async {
      made.add(url);
      await hold?.future;
      if (failNext) {
        failNext = false;
        return null;
      }
      File(target).writeAsBytesSync(base64Decode(_onePixelPngBase64));
      return target;
    };
  });

  setUp(() {
    made.clear();
    session = _ownerA;
    hold = null;
    failNext = false;
    OfferVideoPosterService.instance.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _root.delete(recursive: true);
    } catch (_) {}
  });

  final service = OfferVideoPosterService.instance;

  test(
      'a ready video with no frame gets one, kept under its stable, '
      'account-scoped media id — never under its link', () async {
    final key = _key(_ownerA);

    final path = await service.ensure(cacheKey: key, signedUrl: _link);

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(
        OfflineMediaService.instance
            .getLocalFilePathForMediaId(offerMediaPosterKey(key)),
        path);
    expect(path, contains('/offer_media/'));
    expect(path, contains(_ownerA), reason: 'the account-deletion prefix');
    expect(path, isNot(contains('X-Amz')));
    expect(_tmp.listSync(), isEmpty, reason: 'the temporary frame is gone');
  });

  test(
      'a kept frame is used again — after a restart too — without reading '
      'the video', () async {
    final key = _key(_ownerA);
    await service.ensure(cacheKey: key, signedUrl: _link);
    made.clear();

    service.reset(); // What a restart leaves: only what is on disk.
    final again = await service.ensure(cacheKey: key, signedUrl: _link);

    expect(again, isNotNull);
    expect(service.localPoster(key), again);
    expect(made, isEmpty);
  });

  test('a video asked for twice at once is read once', () async {
    final key = _key(_ownerA);
    hold = Completer<void>();

    final first = service.ensure(cacheKey: key, signedUrl: _link);
    final second = service.ensure(cacheKey: key, signedUrl: '$_link&other');
    hold!.complete();

    expect(await first, isNotNull);
    expect(await second, await first);
    expect(made, hasLength(1));
  });

  test("another account's video is never read or answered", () async {
    final key = _key(_ownerB);

    expect(await service.ensure(cacheKey: key, signedUrl: _link), isNull);
    expect(made, isEmpty);

    session = _ownerB;
    await service.ensure(cacheKey: key, signedUrl: _link);
    session = _ownerA;
    expect(await service.ensure(cacheKey: key, signedUrl: _link), isNull,
        reason: "B's kept frame is not handed to A");
  });

  test('no link means nothing is read', () async {
    expect(
        await service.ensure(cacheKey: _key(_ownerA), signedUrl: null), isNull);
    expect(
        await service.ensure(cacheKey: _key(_ownerA), signedUrl: '  '), isNull);
    expect(made, isEmpty);
  });

  test('a failure leaves the placeholder and is not retried at once', () async {
    final key = _key(_ownerA);
    failNext = true;

    expect(await service.ensure(cacheKey: key, signedUrl: _link), isNull);
    expect(await service.ensure(cacheKey: key, signedUrl: _link), isNull);
    expect(made, hasLength(1));
  });

  group('OfferVideoPoster', () {
    Widget app(Widget child) => MaterialApp(
          home: Scaffold(body: SizedBox(width: 200, height: 200, child: child)),
        );

    const loading = Text('loading');
    const placeholder = Text('placeholder');

    testWidgets(
        'shows the loading surface while a frame is made, then the frame; '
        'reopened, the frame at once', (tester) async {
      final key = _key(_ownerA);
      hold = Completer<void>();
      // The frame is made with real file and storage I/O, so the job starts
      // outside the widget test's fake clock; the widget joins it.
      late Future<String?> job;
      await tester.runAsync(() async {
        job = service.ensure(cacheKey: key, signedUrl: _link);
      });

      await tester.pumpWidget(app(OfferVideoPoster(
        cacheKey: key,
        signedUrl: _link,
        placeholder: placeholder,
        loading: loading,
      )));
      expect(find.text('loading'), findsOneWidget);

      await tester.runAsync(() async {
        hold!.complete();
        await job;
      });
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('loading'), findsNothing);

      // Closed and opened again: drawn at once, the video is not read again.
      made.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(OfferVideoPoster(
        cacheKey: key,
        signedUrl: '$_link&renewed',
        placeholder: placeholder,
        loading: loading,
      )));
      expect(find.byType(Image), findsOneWidget);
      expect(made, isEmpty);
    });

    testWidgets('a video with no link and no frame shows the placeholder',
        (tester) async {
      await tester.pumpWidget(app(OfferVideoPoster(
        cacheKey: _key(_ownerA),
        placeholder: placeholder,
        loading: loading,
      )));
      expect(find.text('placeholder'), findsOneWidget);
      expect(made, isEmpty);
    });
  });
}
