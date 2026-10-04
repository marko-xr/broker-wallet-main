// The preview of a video in Share: the picker's tiles and the compact summary in
// Share Options are one widget, and it resolves a video's still frame the way
// the gallery's own video tile does — the record's frame, the frame this device
// keeps, one made once from the original already on the device or from the link
// the record already holds, and only then a plain placeholder.
//
// Local widget tests. The frame maker is simulated (the platform's read of a
// real signed link is a device check), so these prove which source is asked,
// how often, and what is drawn — never how a phone decodes a video.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_video_poster_service.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/views/Widgets/share_media_picker.dart';

const _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _link = 'https://r2.example.test/bucket/v.mp4?X-Amz-Signature=abc';

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

const ValueKey<String> _placeholder = ValueKey('share-media-video-placeholder');
const ValueKey<String> _badge = ValueKey('share-media-video-indicator');

late Directory _root;
late Directory _docs;
late Directory _tmp;
var _seq = 0;

void main() {
  final made = <String>[];
  Completer<void>? hold;
  var failNext = false;

  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('share_preview_test_');
    _docs = await Directory('${_root.path}/docs').create();
    _tmp = await Directory('${_root.path}/tmp').create();
    Hive.init('${_root.path}/hive');
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.resolveDocumentsDirectory = () async => _docs;
    await OfflineMediaService.instance.initialize();
    OfferVideoPosterService.temporaryDirectory = () async => _tmp;
    OfferVideoPosterService.currentOwnerId = () => _owner;
    OfferVideoPosterService.generate = (source, target) async {
      made.add(source);
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

  /// A ready video as a gallery holds it. Each call is a new video, so a frame
  /// kept for one test is never found by another.
  OfferMediaRef video({
    String? link = _link,
    String? poster,
    String? local,
    bool identity = true,
  }) {
    final id = 'video-${_seq++}';
    return OfferMediaRef(
      mediaObjectId: id,
      cacheKey: identity
          ? offerMediaCacheKey(ownerId: _owner, mediaObjectId: id)
          : null,
      isVideo: true,
      signedUrl: link,
      posterPath: poster,
      localFilePath: local,
    );
  }

  ShareMediaItem itemOf(OfferMediaRef ref) =>
      ShareMediaItem.fromRefs(<OfferMediaRef>[ref]).single;

  Widget app(List<Widget> children) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final child in children)
                  SizedBox(width: 120, height: 120, child: child),
              ],
            ),
          ),
        ),
      );

  File writePng(String name) => File('${_root.path}/$name')
    ..writeAsBytesSync(base64Decode(_onePixelPngBase64));

  group('a video with a frame', () {
    testWidgets(
        'one the record already carries is drawn, with the play badge and no '
        'placeholder, and nothing is made', (tester) async {
      final ref = video(poster: writePng('carried.png').path);

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));

      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(_badge), findsOneWidget);
      expect(find.byKey(_placeholder), findsNothing);
      expect(find.byIcon(Icons.videocam_outlined), findsNothing,
          reason: 'no generic video icon over a real frame');
      expect(made, isEmpty);
    });

    testWidgets(
        'one this device already keeps is drawn at once, and the video is not '
        'read again', (tester) async {
      final ref = video();
      await tester.runAsync(
          () => service.ensure(cacheKey: ref.cacheKey, signedUrl: _link));
      made.clear();
      service.reset(); // What a restart leaves: only what is on disk.

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));

      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(_badge), findsOneWidget);
      expect(find.byKey(_placeholder), findsNothing);
      expect(made, isEmpty);
    });

    testWidgets(
        'one the gallery has not made yet is made once from the link the '
        'record already holds, and kept for the gallery too', (tester) async {
      final ref = video();
      hold = Completer<void>();
      late Future<String?> job;
      // The frame is made with real file and storage work, so the job starts
      // outside the widget test's fake clock; the preview joins it.
      await tester.runAsync(() async {
        job = service.ensure(cacheKey: ref.cacheKey, signedUrl: _link);
      });

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));
      expect(find.byKey(_placeholder), findsOneWidget,
          reason: 'one plain placeholder while the frame is made');
      expect(find.byKey(_badge), findsNothing);

      await tester.runAsync(() async {
        hold!.complete();
        await job;
      });
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(_badge), findsOneWidget);
      expect(find.byKey(_placeholder), findsNothing);
      expect(made, <String>[_link]);
      expect(service.localPoster(ref.cacheKey), isNotNull,
          reason: 'the frame the gallery looks for is now there');
    });

    testWidgets(
        'one whose original this device already holds is read from there, '
        'not from the network', (tester) async {
      final original = File('${_root.path}/original-${_seq++}.mp4')
        ..writeAsBytesSync(<int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]);
      final ref = video(local: original.path);
      hold = Completer<void>();
      late Future<String?> job;
      await tester.runAsync(() async {
        job = service.ensure(cacheKey: ref.cacheKey, signedUrl: original.path);
      });

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));
      await tester.runAsync(() async {
        hold!.complete();
        await job;
      });
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(made, <String>[original.path]);
      expect(made.contains(_link), isFalse);
    });

    testWidgets(
        'the picker tile and the compact summary share one resolution: the '
        'video is read once for both', (tester) async {
      final ref = video();
      final item = itemOf(ref);
      hold = Completer<void>();
      late Future<String?> job;
      await tester.runAsync(() async {
        job = service.ensure(cacheKey: ref.cacheKey, signedUrl: _link);
      });

      await tester.pumpWidget(app([
        ShareMediaPreview(item: item),
        ShareMediaPreview(item: item, cacheWidth: 126),
      ]));
      expect(find.byKey(_placeholder), findsNWidgets(2));

      await tester.runAsync(() async {
        hold!.complete();
        await job;
      });
      await tester.pump();

      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byKey(_badge), findsNWidgets(2));
      expect(find.byKey(_placeholder), findsNothing);
      expect(made, hasLength(1));
    });
  });

  group('a video with no frame to show', () {
    testWidgets(
        'a frame that could not be made leaves one plain placeholder, with no '
        'badge over it', (tester) async {
      final ref = video();
      failNext = true;
      await tester.runAsync(
          () => service.ensure(cacheKey: ref.cacheKey, signedUrl: _link));

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));
      await tester.pump();

      expect(find.byKey(_placeholder), findsOneWidget);
      expect(find.byKey(_badge), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget,
          reason: 'one video symbol, not several');
      expect(made, hasLength(1), reason: 'not retried at once');
    });

    testWidgets('a frame file that is missing falls back the same way',
        (tester) async {
      final ref = video(
        identity: false,
        poster: '${_root.path}/gone-${_seq++}.png',
      );

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));

      expect(find.byKey(_placeholder), findsOneWidget);
      expect(find.byKey(_badge), findsNothing);
      expect(made, isEmpty);
    });

    testWidgets(
        'an old record with only a stored link has no stable identity to keep '
        'a frame under, so nothing is read for it', (tester) async {
      final ref = video(identity: false);

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));
      await tester.pump();

      expect(find.byKey(_placeholder), findsOneWidget);
      expect(find.byKey(_badge), findsNothing);
      expect(made, isEmpty);
    });

    testWidgets(
        'no link and no kept frame: nothing is read, and no link is '
        'asked for', (tester) async {
      final ref = video(link: null);

      await tester.pumpWidget(app([ShareMediaPreview(item: itemOf(ref))]));
      await tester.pump();

      expect(find.byKey(_placeholder), findsOneWidget);
      expect(find.byKey(_badge), findsNothing);
      expect(made, isEmpty);
    });
  });
}
