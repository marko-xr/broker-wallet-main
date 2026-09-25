import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_cache_manager.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_loading_placeholder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:photo_view/photo_view.dart';

/// Covers the single loading treatment for Offer media, and keeps the Owner
/// media pipeline out of it.
///
/// Resolving a signed URL and then fetching the bytes behind it are two stages
/// of one operation, and each used to draw its own `CircularProgressIndicator`.
/// Both stages now draw the same surface, so the hand-over is invisible.
///
/// [MediaLoadingPlaceholder] animates indefinitely when motion is allowed, so
/// those tests use `pump(duration)`; `pumpAndSettle` would never settle.
const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

const String _heldKey = 'offer-media:owner-1:media-held';

late Directory _root;
late File _heldFile;

Widget _app(Widget child, {bool? disableAnimations}) {
  final app = MaterialApp(
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
  if (disableAnimations == null) return app;
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: app,
  );
}

/// The gradient branch only exists when the sweep is running.
Finder _sweepInsidePlaceholder() => find.descendant(
      of: find.byType(MediaLoadingPlaceholder),
      matching: find.byType(DecoratedBox),
    );

Finder _stillInsidePlaceholder() => find.descendant(
      of: find.byType(MediaLoadingPlaceholder),
      matching: find.byType(ColoredBox),
    );

const OfferMediaRef _pendingImage = OfferMediaRef(
  mediaObjectId: 'media-a',
  cacheKey: 'offer-media:owner-1:media-a',
  signedUrl: 'https://media-api.example.test/a.jpg?X-Amz-Signature=aaa',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The shared image cache cannot be constructed under `flutter test`.
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    OfflineMediaService.removeCachedBytes = (_) async {};
    await AppLocalizations.preloadAllLanguages();

    // Prepared here, never inside a testWidgets body: that body runs in a
    // fake-async zone where real disk and Hive I/O never settles.
    _root = await Directory.systemTemp.createTemp('offer_media_loading_ui');
    Hive.init(_root.path);
    await OfflineMediaService.instance.initialize();
    _heldFile = File('${_root.path}/held.png');
    await _heldFile.writeAsBytes(base64Decode(_onePixelPngBase64));
    await OfflineMediaService.instance
        .mapMediaIdToLocalFile(_heldKey, _heldFile.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _root.delete(recursive: true);
    } catch (_) {
      // A temp directory left behind is harmless.
    }
  });

  group('F-7 reduce motion', () {
    testWidgets('normal motion runs the sweep', (tester) async {
      await tester.pumpWidget(
        _app(const MediaLoadingPlaceholder(), disableAnimations: false),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(_sweepInsidePlaceholder(), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0),
          reason: 'the sweep needs a frame pump while it is visible');
    });

    testWidgets('reduce motion replaces the sweep with a still surface',
        (tester) async {
      await tester.pumpWidget(
        _app(const MediaLoadingPlaceholder(), disableAnimations: true),
      );
      await tester.pumpAndSettle();

      expect(_sweepInsidePlaceholder(), findsNothing,
          reason: 'the animated branch must not be built at all');
      expect(_stillInsidePlaceholder(), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('F-6 reduce motion runs no ticker', (tester) async {
      await tester.pumpWidget(
        _app(const MediaLoadingPlaceholder(), disableAnimations: true),
      );
      await tester.pumpAndSettle();

      expect(SchedulerBinding.instance.transientCallbackCount, 0,
          reason: 'no frames may be requested for an animation nobody sees');
    });

    testWidgets('the setting is honoured when it changes while alive',
        (tester) async {
      await tester.pumpWidget(
        _app(const MediaLoadingPlaceholder(), disableAnimations: true),
      );
      await tester.pumpAndSettle();
      expect(_sweepInsidePlaceholder(), findsNothing);

      await tester.pumpWidget(
        _app(const MediaLoadingPlaceholder(), disableAnimations: false),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(_sweepInsidePlaceholder(), findsOneWidget);
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
    });

    testWidgets('it still announces a loading state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const MediaLoadingPlaceholder(), disableAnimations: true),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      handle.dispose();
    });
  });

  group('gallery loading surface', () {
    testWidgets(
        'an image whose bytes have not arrived shows the caller surface, '
        'not a second spinner', (tester) async {
      await tester.pumpWidget(_app(
        const OptimizedMediaGalleryWidget(
          mediaRefs: [_pendingImage],
          imagePlaceholder: MediaLoadingPlaceholder(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(MediaLoadingPlaceholder), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('callers that supply nothing keep the previous spinner',
        (tester) async {
      await tester.pumpWidget(_app(
        const OptimizedMediaGalleryWidget(
          mediaUrls: ['https://example.test/a.jpg'],
        ),
      ));
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(MediaLoadingPlaceholder), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('F-5 a held image keeps the surface while it decodes',
        (tester) async {
      await tester.pumpWidget(_app(
        const OptimizedMediaGalleryWidget(
          mediaRefs: [
            OfferMediaRef(
              mediaObjectId: 'media-held',
              cacheKey: _heldKey,
              localFilePath: 'set-in-hive',
            ),
          ],
          imagePlaceholder: MediaLoadingPlaceholder(),
        ),
      ));
      await tester.pump();

      // Reading and decoding the file is asynchronous, so there is an interval
      // with no frame to paint. It must not be an empty box.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(MediaLoadingPlaceholder), findsOneWidget,
          reason: 'the media area must never go blank while decoding');
      expect(find.byType(CachedNetworkImage), findsNothing,
          reason: 'held bytes are used, so nothing is fetched');
    });
  });

  group('Owner media keeps its own pipeline', () {
    testWidgets('full screen uses a plain NetworkImage without a cache key',
        (tester) async {
      await tester.pumpWidget(_app(
        const FullScreenMediaViewer(
          mediaUrls: ['https://owner.example.test/a.jpg'],
        ),
      ));
      await tester.pump(const Duration(milliseconds: 60));

      final photoView = tester.widget<PhotoView>(find.byType(PhotoView));
      expect(photoView.imageProvider, isA<NetworkImage>(),
          reason: 'Owner media was never part of the Offer delay correction');
      expect(photoView.imageProvider, isNot(isA<CachedNetworkImageProvider>()));
    });

    testWidgets('full screen still caches private Offer media by its identity',
        (tester) async {
      await tester.pumpWidget(_app(
        const FullScreenMediaViewer(mediaRefs: [_pendingImage]),
      ));
      await tester.pump(const Duration(milliseconds: 60));

      final photoView = tester.widget<PhotoView>(find.byType(PhotoView));
      expect(photoView.imageProvider, isA<CachedNetworkImageProvider>());
      expect(
        (photoView.imageProvider as CachedNetworkImageProvider).cacheKey,
        'offer-media:owner-1:media-a',
      );
    });
  });

  group('account isolation reaches memory', () {
    testWidgets('an account change releases retained Offer providers',
        (tester) async {
      final manager = MediaCacheManager();
      manager.getOptimizedImage(
        'https://media-api.example.test/x.jpg?sig=1',
        cacheKey: 'offer-media:owner-1:media-x',
      );
      expect(manager.debugRetainedOfferMediaCount, greaterThan(0));

      MediaCacheManager.invalidateForAccountChange();

      expect(manager.debugRetainedOfferMediaCount, 0);
    });

    testWidgets('removing bytes from disk also releases them from memory',
        (tester) async {
      final manager = MediaCacheManager();
      manager.getOptimizedImage(
        'https://media-api.example.test/y.jpg?sig=1',
        cacheKey: 'offer-media:owner-1:media-y',
      );
      expect(manager.debugRetainedOfferMediaCount, greaterThan(0));

      await OfflineMediaService.instance.forgetOfferMediaItems(
        ownerId: 'owner-1',
        mediaObjectIds: const ['media-y'],
      );

      expect(manager.debugRetainedOfferMediaCount, 0,
          reason: 'the presentation cache is registered as a forget listener');
    });
  });
}
