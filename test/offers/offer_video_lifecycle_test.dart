import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:video_player/video_player.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Private Offer video players across the ways the viewer actually moves:
/// several videos in the Details gallery, full screen opened and closed over
/// it, navigation while a player is still starting. A platform player that
/// records every creation and disposal stands in for ExoPlayer.
///
/// Regression (Samsung, 2026-09-27): "A VideoPlayerController was used after
/// being disposed". Proven cause: to open a third video the shared manager
/// disposed the oldest paused controller although a mounted player (Offer
/// Details, under full screen) still held it.

class _FakePlayer extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Set<int> live = {};
  final List<int> disposed = [];
  int created = 0;
  int _next = 1;

  /// When set, initialization waits for it (a slow network start).
  Completer<void>? holdInitialization;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    created += 1;
    live.add(id);
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    void initialized() {
      if (events.isClosed) return;
      events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 1),
        size: const Size(1080, 1920),
      ));
    }

    final hold = holdInitialization;
    if (hold == null) {
      scheduleMicrotask(initialized);
    } else {
      unawaited(hold.future.then((_) => initialized()));
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    live.remove(playerId);
    disposed.add(playerId);
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
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

late Directory _tempDir;

String _url(String id, [String signature = 's']) =>
    'https://r2.example.test/bucket/$id.mp4?X-Amz-Signature=$signature';

OfferMediaRef _video(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: 'offer-media:owner-l:$id',
      signedUrl: _url(id),
      isVideo: true,
      durationMs: 60000,
    );

Finder _byTypeName(String name) =>
    find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

/// Plays, seeks and pauses [controller]; false when it is refused as
/// disposed — the exact error the device showed.
Future<bool> _usable(VideoPlayerController controller) async {
  try {
    await controller.play();
    await controller.seekTo(const Duration(seconds: 5));
    await controller.pause();
    return true;
  } on FlutterError catch (error) {
    if ('$error'.contains('used after being disposed')) return false;
    rethrow;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePlayer player;
  final manager = VideoPlayerResourceManager();

  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('offer_video_life');
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

  // -------------------------------------------------------------------------
  // The manager: who owns a controller, and when it may be disposed. Real
  // async (runAsync): creating and disposing a player are platform calls.
  // -------------------------------------------------------------------------

  group('VideoPlayerResourceManager', () {
    Future<VideoPlayerController> open(String id,
            [String signature = 's']) async =>
        (await manager.getController(_url(id, signature),
            key: 'k:$id', maxAttempts: 1))!;

    testWidgets(
        'a held player is never disposed to make room for another video '
        '(the device crash)', (tester) async {
      await tester.runAsync(() async {
        await manager.disposeAll();
        final a = await open('a');
        final b = await open('b');
        final c = await open('c'); // Over the two-player limit.

        expect(await _usable(a), isTrue,
            reason: 'Details still shows a; it must not have been disposed');
        expect(await _usable(b), isTrue);
        expect(await _usable(c), isTrue);
        expect(player.disposed, isEmpty);

        for (final controller in [a, b, c]) {
          await manager.release(controller);
        }
        expect(manager.livePlayerCount, 1, reason: 'one idle player is kept');
        await manager.disposeAll();
      });
    });

    testWidgets(
        'an idle player makes room; a disposed controller is never handed '
        'out again', (tester) async {
      await tester.runAsync(() async {
        await manager.disposeAll();
        final a = await open('a');
        final b = await open('b');
        await manager.release(a); // Idle.

        await open('c'); // Room is made from the idle player.
        expect(player.disposed, hasLength(1));
        expect(await _usable(a), isFalse, reason: 'a was disposed');

        final aAgain = await open('a');
        expect(identical(aAgain, a), isFalse,
            reason: 'never the disposed controller');
        expect(await _usable(aAgain), isTrue);
        expect(await _usable(b), isTrue);
        await manager.disposeAll();
      });
    });

    testWidgets(
        'one video shown twice shares one player, disposed only after its '
        'last holder lets go', (tester) async {
      await tester.runAsync(() async {
        await manager.disposeAll();
        final first = await open('a');
        final second = await open('a');
        expect(identical(first, second), isTrue);
        expect(player.created, 1);
        expect(manager.holdersOf(first), 2);

        await manager.release(first); // Full screen closed.
        expect(manager.holdersOf(first), 1);
        expect(await _usable(first), isTrue);

        await manager.release(second); // Details closed: idle, kept.
        expect(manager.livePlayerCount, 1);
        await open('b');
        await open('c'); // The idle one goes to make room.
        expect(await _usable(first), isFalse);
        await manager.disposeAll();
      });
    });

    testWidgets(
        'a newer link of a video that is shown leaves the shown player alone',
        (tester) async {
      await tester.runAsync(() async {
        await manager.disposeAll();
        final shown = await open('a', 'old');
        final renewed = await open('a', 'new');

        expect(identical(shown, renewed), isFalse);
        expect(await _usable(shown), isTrue);

        await manager.release(shown);
        await manager.release(renewed);
        expect(manager.livePlayerCount, 1,
            reason: 'the older link is not kept as a second idle player');
        await manager.disposeAll();
      });
    });

    testWidgets('two requests while a video starts open one platform player',
        (tester) async {
      await tester.runAsync(() async {
        await manager.disposeAll();
        player.holdInitialization = Completer<void>();
        final first = open('a');
        final second = open('a');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        player.holdInitialization!.complete();

        final controllers = await Future.wait([first, second]);
        expect(identical(controllers[0], controllers[1]), isTrue);
        expect(player.created, 1);
        expect(manager.holdersOf(controllers[0]), 2);
        await manager.disposeAll();
      });
    });

    testWidgets('releasing twice, or an unknown controller, changes nothing',
        (tester) async {
      await tester.runAsync(() async {
        await manager.disposeAll();
        final a = await open('a');
        final b = await open('b');
        await manager.release(a);
        await manager.release(a);
        expect(manager.holdersOf(b), 1);
        expect(await _usable(b), isTrue);

        final stranger = VideoPlayerController.networkUrl(Uri.parse(_url('x')));
        await manager.release(stranger);
        expect(manager.livePlayerCount, 2);
        await manager.disposeAll();
        expect(player.live, isEmpty, reason: 'every platform player freed');
      });
    });
  });

  // -------------------------------------------------------------------------
  // The widgets, moving as a viewer does.
  // -------------------------------------------------------------------------

  Widget app(Widget home) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: home),
      );

  Widget gallery(List<OfferMediaRef> refs) => SizedBox(
        height: 280,
        child: OptimizedMediaGalleryWidget(mediaRefs: refs),
      );

  /// Frames, with a moment of real time between them: disposing a
  /// VideoPlayerController completes only when real time passes, which a
  /// widget test's fake clock alone never provides.
  Future<void> frames(WidgetTester tester, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapToPlay(WidgetTester tester) async {
    await tester.tap(_byTypeName('OfferVideoTile').last);
    await frames(tester);
  }

  Future<void> nextPage(WidgetTester tester, {bool back = false}) async {
    await tester.fling(
        find.byType(PageView).last, Offset(back ? 400 : -400, 0), 2000);
    await frames(tester, 10);
  }

  /// Uses the player on screen the way its controls do.
  Future<void> useVisiblePlayer(WidgetTester tester) async {
    final shown = tester.widget<VideoPlayer>(find.byType(VideoPlayer).last);
    await tester.runAsync(() async {
      expect(await _usable(shown.controller), isTrue,
          reason: 'the player on screen must still be usable');
    });
  }

  Future<void> start(WidgetTester tester, Widget home) async {
    await tester.runAsync(manager.disposeAll);
    await tester.pumpWidget(app(home));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester, 3);
    await tester.runAsync(manager.disposeAll);
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets(
      'full screen over Details, three videos played there, back to Details: '
      'the Details player still works', (tester) async {
    await start(tester, gallery([_video('a'), _video('b'), _video('c')]));

    await tapToPlay(tester); // Details: a.
    await tester.tap(find.text('View All'));
    await frames(tester);
    await tapToPlay(tester); // Full screen: a, the same player.
    await nextPage(tester);
    await tapToPlay(tester); // b
    await nextPage(tester);
    await tapToPlay(tester); // c: a third player is needed.
    expect(find.byType(VideoPlayer), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await frames(tester);

    expect(tester.takeException(), isNull);
    await useVisiblePlayer(tester);
    await finish(tester);
  });

  testWidgets('switching repeatedly between videos in Details', (tester) async {
    await start(tester, gallery([_video('a'), _video('b'), _video('c')]));

    for (var round = 0; round < 3; round++) {
      await tapToPlay(tester);
      await nextPage(tester);
      await tapToPlay(tester);
      await nextPage(tester);
      await tapToPlay(tester);
      await nextPage(tester, back: true);
      await nextPage(tester, back: true);
    }

    expect(tester.takeException(), isNull);
    expect(manager.livePlayerCount, lessThanOrEqualTo(2),
        reason: 'players are not kept alive indefinitely');
    await finish(tester);
  });

  testWidgets('opening and closing full screen repeatedly', (tester) async {
    await start(tester, gallery([_video('a'), _video('b')]));
    await tapToPlay(tester);

    for (var round = 0; round < 3; round++) {
      await tester.tap(find.text('View All'));
      await frames(tester);
      await tapToPlay(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await frames(tester);
      expect(tester.takeException(), isNull);
    }

    await useVisiblePlayer(tester);
    await finish(tester);
  });

  testWidgets(
      'leaving while a player is still starting gives its controller back',
      (tester) async {
    player.holdInitialization = Completer<void>();
    await start(tester, gallery([_video('a'), _video('b')]));

    await tester.tap(_byTypeName('OfferVideoTile').last);
    await tester.pump();
    await tester.pumpWidget(app(const Text('elsewhere'))); // Navigated away.
    player.holdInitialization!.complete();
    await frames(tester, 5);

    expect(tester.takeException(), isNull);
    expect(player.created, 1);
    expect(manager.getResourceStats()['heldControllers'], 0,
        reason: 'the late controller was released, not left held forever');
    await finish(tester);
  });

  testWidgets(
      'every platform player is freed once the players are gone and the '
      'manager is cleared', (tester) async {
    await start(tester, gallery([_video('a'), _video('b'), _video('c')]));
    await tapToPlay(tester);
    await nextPage(tester);
    await tapToPlay(tester);

    await tester.pumpWidget(const SizedBox());
    await frames(tester, 3);
    expect(manager.getResourceStats()['heldControllers'], 0);
    await tester.runAsync(manager.disposeAll);
    await tester.pump(const Duration(minutes: 1));

    expect(player.live, isEmpty);
    expect(player.disposed, hasLength(player.created));
  });
}
