import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A private Offer video as the viewer actually uses it: tapped in the
/// gallery, opened by the real player widgets over a fake platform player
/// that records what it is asked to do.

class _FakePlayer extends VideoPlayerPlatform {
  _FakePlayer({this.size = const Size(1280, 720)});

  /// Phone recordings are portrait; the owner's test videos are 9:16.
  final Size size;
  final List<Duration> seeks = [];
  final List<String> sources = [];
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _next = 1;
  Duration _position = Duration.zero;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    sources.add(options.dataSource.uri ?? options.dataSource.asset ?? '');
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    scheduleMicrotask(() => events.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 1),
          size: size,
        )));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    _position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => _position;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose(int playerId) async {
    // Not awaited: a stream close completes only when the fake-async test
    // zone is pumped.
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

const _signed = 'https://r2.example.test/bucket/profiles/o/offers/f/'
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeed0dd9.mp4?X-Amz-Signature=abc';

late Directory _tempDir;

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

OfferMediaRef _readyVideo(String id, {String url = _signed}) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: 'offer-media:owner-v:$id',
      signedUrl: url,
      isVideo: true,
      durationMs: 60000,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePlayer player;

  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('offer_video_test');
    Hive.init(_tempDir.path);
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    await OfflineMediaService.instance.initialize();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  setUp(() {
    player = _FakePlayer();
    VideoPlayerPlatform.instance = player;
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> startPlaying(WidgetTester tester, Widget gallery,
      {Locale locale = const Locale('en')}) async {
    // The resource manager is a process-wide singleton: start every test
    // with no player left over from an earlier one.
    unawaited(VideoPlayerResourceManager().disposeAll());
    await tester.pumpWidget(_app(gallery, locale: locale));
    await tester.pump();
    // By type name: this file is reachable under two import spellings.
    await tester.tap(find
        .byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == 'OfferVideoTile')
        .first);
    // Player creation, initialization and Chewie's controls fading in.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    unawaited(VideoPlayerResourceManager().disposeAll());
    // Lets disposal and the player's initialization-timeout timer run out.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Rect barRect(WidgetTester tester) =>
      tester.getRect(find.byType(MaterialVideoProgressBar));

  testWidgets('dragging the seek bar of a private video in the gallery seeks',
      (tester) async {
    await startPlaying(
      tester,
      SizedBox(
        height: 280,
        child: OptimizedMediaGalleryWidget(
          mediaRefs: [_readyVideo('v1'), _readyVideo('v2')],
        ),
      ),
    );
    expect(player.sources.single, _signed,
        reason: 'the signed link reaches the player unchanged');
    expect(find.byType(MaterialVideoProgressBar), findsOneWidget);

    final bar = barRect(tester);
    await tester.dragFrom(
      Offset(bar.left + bar.width * 0.1, bar.center.dy),
      Offset(bar.width * 0.6, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.seeks, isNotEmpty, reason: 'the drag reached the seek bar');
    final seconds = player.seeks.last.inMilliseconds / 1000;
    expect(seconds, closeTo(42, 4), reason: '70 % of one minute');
    await finish(tester);
  });

  /// The Samsung phone's logical screen.
  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(tester.view.reset);
  }

  testWidgets(
      'a portrait video in the Details header seeks where the gallery draws '
      'its page dots', (tester) async {
    phoneScreen(tester);
    player = _FakePlayer(size: const Size(1080, 1920));
    VideoPlayerPlatform.instance = player;
    await startPlaying(
      tester,
      SizedBox(
        height: 280,
        child: OptimizedMediaGalleryWidget(
          mediaRefs: [for (var i = 0; i < 5; i++) _readyVideo('p$i')],
        ),
      ),
    );

    final bar = barRect(tester);
    await tester.tapAt(bar.center);
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.seeks, isNotEmpty,
        reason: 'a tap in the middle of the seek bar must seek');
    expect(player.seeks.last.inMilliseconds / 1000, closeTo(30, 4));
    await finish(tester);
  });

  testWidgets(
      'a portrait video full screen seeks by dragging, under the thumbnail '
      'strip', (tester) async {
    phoneScreen(tester);
    player = _FakePlayer(size: const Size(1080, 1920));
    VideoPlayerPlatform.instance = player;
    await startPlaying(
      tester,
      FullScreenMediaViewer(
        mediaRefs: [_readyVideo('f1'), _readyVideo('f2')],
      ),
    );

    final bar = barRect(tester);
    await tester.dragFrom(
      Offset(bar.left + bar.width * 0.1, bar.center.dy),
      Offset(bar.width * 0.4, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.seeks, isNotEmpty,
        reason: 'the drag must reach the seek bar, not the thumbnails');
    expect(player.seeks.last.inMilliseconds / 1000, closeTo(30, 4));
    await finish(tester);
  });

  testWidgets('seeking follows the finger in Arabic (right-to-left) too',
      (tester) async {
    phoneScreen(tester);
    await startPlaying(
      tester,
      SizedBox(
        height: 280,
        child: OptimizedMediaGalleryWidget(mediaRefs: [_readyVideo('r1')]),
      ),
      locale: const Locale('ar'),
    );

    final bar = barRect(tester);
    await tester.dragFrom(
      Offset(bar.left + bar.width * 0.1, bar.center.dy),
      Offset(bar.width * 0.7, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The bar is drawn left to right in both languages; the seek must land
    // where the finger was lifted on that drawing.
    expect(player.seeks.last.inMilliseconds / 1000, closeTo(48, 4));
    await finish(tester);
  });
}
