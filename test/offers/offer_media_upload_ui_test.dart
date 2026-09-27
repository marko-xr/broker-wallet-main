import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Widgets/media_upload_widget.dart';
import 'package:broker_wallet/src/Views/Widgets/unified_media_preview_grid.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_upload_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// How Offer media in the upload queue is drawn — on the Add/Edit form's grid,
/// on Offer Details and full screen — and how a private video plays: only
/// when tapped, with one automatic new link when its link has expired.
///
/// Also checks that Owner media, which shares these widgets, renders exactly
/// as before. Local widget tests only; not device verification.

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

late Directory _tempDir;
late File _pendingPhoto;
late File _poster;
late Map<String, dynamic> _en;
late Map<String, dynamic> _ar;

Finder _byTypeName(String name) =>
    find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

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

OfferMediaRef _pendingImage(
  String id, {
  OfferMediaUploadPhase phase = OfferMediaUploadPhase.uploading,
  double? progress,
  String? failureKey,
}) =>
    OfferMediaRef(
      mediaObjectId: id,
      cacheKey: 'offer-media:owner-ui:$id',
      localFilePath: _pendingPhoto.path,
      uploadPhase: phase,
      progress: progress,
      failureMessageKey: failureKey,
      displayName: '$id.jpg',
      byteLength: 68,
    );

OfferMediaRef _serverVideo(String id, {String? url}) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: 'offer-media:owner-ui:$id',
      // An unplayable link: the test player fails at once, as an expired
      // signed link would on a device.
      signedUrl: url ?? 'https://r2.example.test/$id.bin?X-Amz-Signature=old',
      isVideo: true,
      posterPath: _poster.path,
      durationMs: 83000,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('offer_upload_ui_test');
    Hive.init(_tempDir.path);
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    await OfflineMediaService.instance.initialize();
    _pendingPhoto = File('${_tempDir.path}/pending.png')
      ..writeAsBytesSync(base64Decode(_onePixelPngBase64));
    _poster = File('${_tempDir.path}/poster.png')
      ..writeAsBytesSync(base64Decode(_onePixelPngBase64));

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
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async => true,
    );
    await AppLocalizations.preloadAllLanguages();
    _en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    _ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('upload state overlay', () {
    testWidgets('queued, uploading with its percentage, and nothing when ready',
        (tester) async {
      await tester.pumpWidget(_app(const Column(children: [
        Expanded(
            child: OfferMediaUploadStatus(phase: OfferMediaUploadPhase.queued)),
        Expanded(
          child: OfferMediaUploadStatus(
            phase: OfferMediaUploadPhase.uploading,
            progress: 0.42,
          ),
        ),
        Expanded(
            child: OfferMediaUploadStatus(phase: OfferMediaUploadPhase.ready)),
      ])));
      await tester.pump();

      expect(find.text(_en['offerMediaQueued'] as String), findsOneWidget);
      expect(find.text('${_en['uploading']} 42%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_en['retry'] as String), findsNothing);
      expect(find.text(_en['remove'] as String), findsNothing);
    });

    testWidgets(
        'a failure that can pass offers Retry and Remove; a refusal offers '
        'only Remove', (tester) async {
      final retried = <String>[];
      final removed = <String>[];
      await tester.pumpWidget(_app(Column(children: [
        Expanded(
          child: OfferMediaUploadStatus(
            phase: OfferMediaUploadPhase.retryableFailure,
            failureMessageKey: 'offerMediaUploadInterrupted',
            onRetry: () => retried.add('a'),
            onRemove: () => removed.add('a'),
          ),
        ),
        Expanded(
          child: OfferMediaUploadStatus(
            phase: OfferMediaUploadPhase.permanentFailure,
            failureMessageKey: 'offerMediaUploadRejected',
            onRetry: () => retried.add('b'),
            onRemove: () => removed.add('b'),
          ),
        ),
      ])));
      await tester.pump();

      expect(find.text(_en['offerMediaUploadInterrupted'] as String),
          findsOneWidget);
      expect(
          find.text(_en['offerMediaUploadRejected'] as String), findsOneWidget);
      expect(find.text(_en['retry'] as String), findsOneWidget);
      expect(find.text(_en['remove'] as String), findsNWidgets(2));

      await tester.tap(find.text(_en['retry'] as String));
      await tester.tap(find.text(_en['remove'] as String).last);
      expect(retried, ['a']);
      expect(removed, ['b']);
    });

    testWidgets('speaks Arabic in Arabic', (tester) async {
      await tester.pumpWidget(_app(
        const OfferMediaUploadStatus(phase: OfferMediaUploadPhase.queued),
        locale: const Locale('ar'),
      ));
      await tester.pump();

      expect(find.text(_ar['offerMediaQueued'] as String), findsOneWidget);
    });
  });

  group('Add/Edit form grid (Offer media)', () {
    testWidgets(
        'an upload shows its state on its tile, with Retry, and every item '
        'stays reachable through "+N more"', (tester) async {
      final retried = <int>[];
      final removed = <int>[];
      var showAll = 0;
      final items = <OfferMediaRef>[
        OfferMediaRef(
          mediaObjectId: 'server-1',
          cacheKey: 'offer-media:owner-ui:server-1',
          localFilePath: _pendingPhoto.path,
        ),
        _pendingImage('p1',
            phase: OfferMediaUploadPhase.retryableFailure,
            failureKey: 'offerMediaUploadInterrupted'),
        _pendingImage('p2', progress: 0.5),
        _pendingImage('p3', phase: OfferMediaUploadPhase.queued),
        _pendingImage('p4', phase: OfferMediaUploadPhase.queued),
      ];

      await tester.pumpWidget(_app(SingleChildScrollView(
        child: Builder(
          builder: (context) => MediaUploadWidget(
            selectedFiles: const [],
            onSelectMedia: () {},
            onRemoveFile: (_) {},
            onClearAll: () {},
            localization: AppLocalizations.of(context),
            maxDisplayFiles: 3,
            showUploadButton: false,
            offerMedia: items,
            onRemoveOfferMedia: removed.add,
            onRetryOfferMedia: retried.add,
            onShowAllMedia: () => showAll += 1,
          ),
        ),
      )));
      await tester.pump();

      // The server item has no overlay; the two shown uploads do.
      expect(find.byType(OfferMediaUploadStatus), findsNWidgets(2));
      expect(find.text(_en['photo'] as String), findsOneWidget,
          reason: 'a server item is named by its kind, not "Unknown file"');
      expect(find.text('${_en['uploading']} 50%'), findsOneWidget);

      await tester.tap(find.text(_en['retry'] as String));
      expect(retried, [1]);

      // The first tile's remove button.
      await tester.tap(find.byIcon(Icons.close).first);
      expect(removed, [0]);

      await tester.ensureVisible(find.text('+2 more'));
      await tester.pump();
      await tester.tap(find.text('+2 more'));
      expect(showAll, 1);
    });

    testWidgets('Owner media keeps its URL/file grid with no upload state',
        (tester) async {
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: Builder(
          builder: (context) => MediaUploadWidget(
            selectedFiles: const [],
            existingFileUrls: const [
              'https://example.test/owner/a.jpg',
              'https://example.test/owner/b.jpg',
              'https://example.test/owner/c.jpg',
              'https://example.test/owner/d.jpg',
            ],
            onSelectMedia: () {},
            onRemoveFile: (_) {},
            onRemoveExistingFile: (_) {},
            onClearAll: () {},
            localization: AppLocalizations.of(context),
            maxDisplayFiles: 3,
            showUploadButton: false,
            // Offer callbacks passed by mistake still do nothing here.
            onRetryOfferMedia: (_) {},
            onShowAllMedia: () {},
          ),
        ),
      )));
      await tester.pump();

      final grid = tester.widget<UnifiedMediaPreviewGrid>(
          find.byType(UnifiedMediaPreviewGrid));
      expect(grid.onRetry, isNull);
      expect(grid.onShowAll, isNull);
      expect(grid.mediaItems.map((i) => i.offerMedia), everyElement(isNull));
      expect(find.byType(OfferMediaUploadStatus), findsNothing);
      expect(find.text('+1 more'), findsOneWidget);
    });
  });

  group('Offer Details gallery', () {
    testWidgets(
        'an upload is drawn from its own file, with its state and working '
        'Retry and Remove', (tester) async {
      final retried = <String>[];
      final removed = <String>[];
      await tester.pumpWidget(_app(SizedBox(
        height: 300,
        child: OptimizedMediaGalleryWidget(
          mediaRefs: [
            _pendingImage('p9',
                phase: OfferMediaUploadPhase.retryableFailure,
                failureKey: 'offerMediaUploadInterrupted'),
          ],
          onRetryUpload: retried.add,
          onRemoveUpload: removed.add,
        ),
      )));
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image).first);
      final provider = image.image;
      final source =
          provider is ResizeImage ? provider.imageProvider : provider;
      expect(source, isA<FileImage>());
      expect((source as FileImage).file.path, _pendingPhoto.path);
      expect(find.text(_en['offerMediaUploadInterrupted'] as String),
          findsOneWidget);

      await tester.tap(find.text(_en['retry'] as String));
      await tester.tap(find.text(_en['remove'] as String));
      expect(retried, ['p9']);
      expect(removed, ['p9']);
    });

    testWidgets(
        'a private video shows its still frame and length and loads nothing '
        'until tapped', (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        height: 300,
        child: OptimizedMediaGalleryWidget(mediaRefs: [_serverVideo('v1')]),
      )));
      await tester.pump();

      expect(_byTypeName('OfferVideoTile'), findsOneWidget);
      expect(_byTypeName('OptimizedVideoPlayerWidget'), findsNothing);
      expect(find.text('${_en['offerMediaTapToPlay']} · 1:23'), findsOneWidget);
      final poster = tester.widget<Image>(find.byType(Image).first);
      final provider = poster.image;
      final file = (provider is ResizeImage ? provider.imageProvider : provider)
          as FileImage;
      expect(file.file.path, _poster.path);
    });

    testWidgets(
        'an expired link is signed again once, automatically; a second '
        'failure is explained with Retry', (tester) async {
      final refreshed = <String>[];
      await tester.pumpWidget(_app(SizedBox(
        height: 300,
        child: OptimizedMediaGalleryWidget(
          mediaRefs: [_serverVideo('v2')],
          refreshSignedUrl: (id) async {
            refreshed.add(id);
            return 'https://r2.example.test/$id.bin?X-Amz-Signature=new';
          },
        ),
      )));
      await tester.pump();

      await tester.tap(find.text('${_en['offerMediaTapToPlay']} · 1:23'));
      await tester.pumpAndSettle();

      expect(refreshed, ['v2'], reason: 'exactly one automatic refresh');
      expect(find.text(_en['offerMediaVideoUnavailable'] as String),
          findsOneWidget);
      expect(find.text('Error loading video'), findsNothing,
          reason: 'no raw player error text for a private video');

      await tester.tap(find.text(_en['retry'] as String));
      await tester.pumpAndSettle();

      expect(refreshed, ['v2', 'v2'], reason: 'Retry allows one more refresh');
    });

    testWidgets('a video still uploading cannot be played yet', (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        height: 300,
        child: OptimizedMediaGalleryWidget(mediaRefs: [
          OfferMediaRef(
            mediaObjectId: 'v3',
            cacheKey: 'offer-media:owner-ui:v3',
            isVideo: true,
            posterPath: _poster.path,
            uploadPhase: OfferMediaUploadPhase.queued,
          ),
        ]),
      )));
      await tester.pump();

      expect(find.textContaining(_en['offerMediaTapToPlay'] as String),
          findsNothing);
      expect(find.text(_en['offerMediaQueued'] as String), findsOneWidget);
    });

    testWidgets(
        'a video still uploading plays from its own local copy, never from '
        'the network, with its progress shown beside it', (tester) async {
      // An unplayable extension makes the test player fail at once, like a
      // device that cannot open the file; that must not ask for a new link.
      final local = File('${_tempDir.path}/pending-video.bin')
        ..writeAsBytesSync(List<int>.filled(32, 1));
      final refreshed = <String>[];
      await tester.pumpWidget(_app(SizedBox(
        height: 300,
        child: OptimizedMediaGalleryWidget(
          mediaRefs: [
            OfferMediaRef(
              mediaObjectId: 'v7',
              cacheKey: 'offer-media:owner-ui:v7',
              isVideo: true,
              localFilePath: local.path,
              posterPath: _poster.path,
              durationMs: 83000,
              uploadPhase: OfferMediaUploadPhase.uploading,
              progress: 0.4,
            ),
          ],
          refreshSignedUrl: (id) async {
            refreshed.add(id);
            return null;
          },
        ),
      )));
      await tester.pump();

      expect(find.text('${_en['uploading']} 40%'), findsOneWidget);
      await tester.tap(find.text('${_en['offerMediaTapToPlay']} · 1:23'));
      await tester.pump();

      final player = tester.widget(_byTypeName('OptimizedVideoPlayerWidget'))
          as OptimizedVideoPlayerWidget;
      expect(player.videoUrl, local.path);
      await tester.pumpAndSettle();
      expect(refreshed, isEmpty, reason: 'a local copy needs no link');
      expect(find.text(_en['offerMediaVideoUnavailable'] as String),
          findsOneWidget);
    });

    testWidgets(
        'an automatic retry reads as retrying, and finishing as finishing — '
        'neither as a failure', (tester) async {
      await tester.pumpWidget(_app(Column(children: [
        const SizedBox(
          height: 120,
          child: OfferMediaUploadStatus(
            phase: OfferMediaUploadPhase.retrying,
            failureMessageKey: 'offerMediaUploadInterrupted',
          ),
        ),
        const SizedBox(
          height: 120,
          child: OfferMediaUploadStatus(
            phase: OfferMediaUploadPhase.confirming,
          ),
        ),
      ])));
      await tester.pump();

      expect(find.text(_en['offerMediaRetrying'] as String), findsOneWidget);
      expect(find.text(_en['offerMediaFinishing'] as String), findsOneWidget);
      expect(find.text(_en['offerMediaUploadInterrupted'] as String),
          findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('full screen', () {
    testWidgets('an upload is shown from its file with its state',
        (tester) async {
      await tester.pumpWidget(_app(FullScreenMediaViewer(
        mediaRefs: [
          _pendingImage('p5', phase: OfferMediaUploadPhase.queued),
          _serverVideo('v5'),
        ],
      )));
      await tester.pump();

      expect(find.text(_en['offerMediaQueued'] as String), findsOneWidget);
      expect(find.textContaining('%'), findsNothing,
          reason: 'a snapshot never shows a stale percentage');
    });

    testWidgets('a private video opened full screen is not preloaded',
        (tester) async {
      await tester.pumpWidget(_app(FullScreenMediaViewer(
        mediaRefs: [
          _pendingImage('p6', phase: OfferMediaUploadPhase.queued),
          _serverVideo('v6'),
        ],
        initialIndex: 1,
      )));
      await tester.pump();

      expect(_byTypeName('OfferVideoTile'), findsOneWidget);
      expect(_byTypeName('Chewie'), findsNothing,
          reason: 'no private video is preloaded');
      expect(find.text('${_en['offerMediaTapToPlay']} · 1:23'), findsOneWidget);
    });
  });
}
