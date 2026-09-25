import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_cache_manager.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the stable `mediaObjectId` -> `cacheKey` wiring added so a
/// re-signed Offer media URL (minted fresh on every `/offer-media` call)
/// still resolves to the same disk-cache entry as its previous resolution,
/// instead of guaranteeing a re-download on every open — including after an
/// app restart, when the URL-keyed default would always miss.
OfferModel _offer({
  List<String> mediaUrls = const [],
  List<String> mediaObjectIds = const [],
}) =>
    OfferModel(
      id: 'offer-1',
      userId: 'owner-1',
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
      mediaUrls: mediaUrls,
      mediaObjectIds: mediaObjectIds,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The shared image cache cannot be constructed under `flutter test`; these
    // tests assert cache-key wiring, not third-party cache behaviour.
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    await AppLocalizations.preloadAllLanguages();
  });

  group('OfferModel.mediaObjectIds', () {
    test('defaults to empty, matching the untouched bulk-list fetch shape',
        () {
      final offer = _offer(mediaUrls: const ['https://example.test/a.jpg']);
      expect(offer.mediaObjectIds, isEmpty);
    });

    test('copyWith carries stable ids alongside their URLs', () {
      final base = _offer();
      final resolved = base.copyWith(
        mediaUrls: const [
          'https://example.test/a.jpg',
          'https://example.test/b.jpg',
        ],
        mediaObjectIds: const ['media-a', 'media-b'],
      );

      expect(resolved.mediaUrls, hasLength(2));
      expect(resolved.mediaObjectIds, ['media-a', 'media-b']);
    });

    test('copyWith with no mediaObjectIds argument preserves the previous list',
        () {
      final base = _offer(
        mediaUrls: const ['https://example.test/a.jpg'],
        mediaObjectIds: const ['media-a'],
      );
      final resolved = base.copyWith(location: 'Dubai');

      expect(resolved.mediaObjectIds, ['media-a']);
    });

    test('an authoritative empty media result clears every stale media field',
        () {
      final base = _offer(
        mediaUrls: const ['https://example.test/old.jpg'],
        mediaObjectIds: const ['old-media'],
      ).copyWith(mediaUrl: 'https://example.test/old.jpg');

      final cleared = base.copyWith(
        mediaUrls: const [],
        mediaObjectIds: const [],
        clearMediaUrl: true,
      );

      expect(cleared.mediaUrl, isNull);
      expect(cleared.mediaUrls, isEmpty);
      expect(cleared.mediaObjectIds, isEmpty);
    });
  });

  group('account-scoped Offer media cache identity', () {
    test('same media id is isolated between two authenticated owners', () {
      final ownerA = offerMediaCacheKey(
        ownerId: 'owner-a',
        mediaObjectId: 'media-1',
      );
      final ownerB = offerMediaCacheKey(
        ownerId: 'owner-b',
        mediaObjectId: 'media-1',
      );

      expect(ownerA, 'offer-media:owner-a:media-1');
      expect(ownerB, 'offer-media:owner-b:media-1');
      expect(ownerA, isNot(ownerB));
    });

    test('missing owner or media identity disables stable private caching', () {
      expect(
        offerMediaCacheKey(ownerId: '', mediaObjectId: 'media-1'),
        isNull,
      );
      expect(
        offerMediaCacheKey(ownerId: 'owner-a', mediaObjectId: ''),
        isNull,
      );
    });

    test('a fresh signed URL replaces the failed in-memory provider', () {
      final manager = MediaCacheManager();
      final first = manager.getOptimizedImage(
        'https://example.test/a.jpg?signature=expired',
        cacheKey: 'offer-media:owner-a:media-1',
      ) as CachedNetworkImageProvider;
      final second = manager.getOptimizedImage(
        'https://example.test/a.jpg?signature=fresh',
        cacheKey: 'offer-media:owner-a:media-1',
      ) as CachedNetworkImageProvider;

      expect(first.cacheKey, second.cacheKey);
      expect(first.url, contains('expired'));
      expect(second.url, contains('fresh'));
    });
  });

  group('OptimizedMediaGalleryWidget cache-key wiring', () {
    testWidgets('a same-index media id becomes the image cache key',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaUrls: const [
              'https://media-api.example.test/img.jpg?X-Amz-Signature=aaa',
            ],
            mediaIds: const ['media-object-a'],
            mediaOwnerId: 'owner-1',
          ),
        ),
      );

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, 'offer-media:owner-1:media-object-a');
    });

    testWidgets('a re-signed URL for the same media id keeps the same key',
        (tester) async {
      const mediaId = 'media-object-stable';

      Future<String?> keyFor(String signedUrl) async {
        await tester.pumpWidget(
          MaterialApp(
            home: OptimizedMediaGalleryWidget(
              mediaUrls: [signedUrl],
              mediaIds: const [mediaId],
              mediaOwnerId: 'owner-1',
            ),
          ),
        );
        return tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .cacheKey;
      }

      final first = await keyFor(
        'https://media-api.example.test/img.jpg?X-Amz-Signature=aaa&X-Amz-Date=1',
      );
      final second = await keyFor(
        'https://media-api.example.test/img.jpg?X-Amz-Signature=zzz&X-Amz-Date=2',
      );

      expect(first, 'offer-media:owner-1:$mediaId');
      expect(second, 'offer-media:owner-1:$mediaId');
      expect(first, second);
    });

    testWidgets('distinct media ids never collide', (tester) async {
      Future<String?> keyFor(String url, String id) async {
        await tester.pumpWidget(
          MaterialApp(
            home: OptimizedMediaGalleryWidget(
              mediaUrls: [url],
              mediaIds: [id],
              mediaOwnerId: 'owner-1',
            ),
          ),
        );
        return tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .cacheKey;
      }

      final keyA =
          await keyFor('https://example.test/a.jpg?sig=1', 'media-a');
      final keyB =
          await keyFor('https://example.test/b.jpg?sig=2', 'media-b');

      expect(keyA, 'offer-media:owner-1:media-a');
      expect(keyB, 'offer-media:owner-1:media-b');
      expect(keyA, isNot(keyB));
    });

    testWidgets(
        'a mediaIds length mismatch falls back to no cache key rather than '
        'misaligning an id to the wrong URL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaUrls: const [
              'https://example.test/a.jpg',
              'https://example.test/b.jpg',
            ],
            // Deliberately shorter than mediaUrls.
            mediaIds: const ['media-a'],
            mediaOwnerId: 'owner-1',
          ),
        ),
      );

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, isNull);
    });

    testWidgets('an empty-string id at an index is treated as no id',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaUrls: const ['https://example.test/a.jpg'],
            mediaIds: const [''],
            mediaOwnerId: 'owner-1',
          ),
        ),
      );

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, isNull);
    });

    testWidgets(
        'omitting mediaIds entirely preserves the previous URL-keyed behavior',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaUrls: const ['https://example.test/a.jpg'],
          ),
        ),
      );

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, isNull);
      expect(image.imageUrl, 'https://example.test/a.jpg');
    });

    testWidgets('image failure offers one localized explicit retry',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OptimizedMediaGalleryWidget(
            mediaUrls: const ['https://example.test/a.jpg?signature=expired'],
            mediaIds: const ['media-a'],
            mediaOwnerId: 'owner-1',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pump();

      final networkImage =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final context = tester.element(find.byType(CachedNetworkImage));
      final errorWidget = networkImage.errorWidget!(
        context,
        networkImage.imageUrl,
        StateError('expired'),
      );
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: errorWidget,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load image'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });
  });
}
