import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Covers the local-first Offer media path.
///
/// Private R2 media is served through a signed URL that the Worker re-mints on
/// every `/offer-media` call, so before this path existed the screen could not
/// draw anything until two network round trips had finished — even when the
/// exact bytes were already on the device. Remembering an Offer's durable
/// media ids, and where their bytes live, makes the first frame free.
const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

late Directory _tempDir;

/// Files and Hive mappings are prepared in `setUpAll`, never inside a
/// `testWidgets` body: that body runs in a fake-async zone where real disk and
/// Hive I/O never settles.
late File _localOnlyFile;
late File _preferLocalFile;

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

Future<File> _writeImage(String name) async {
  final file = File('${_tempDir.path}/$name');
  await file.writeAsBytes(base64Decode(_onePixelPngBase64));
  return file;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _tempDir = await Directory.systemTemp.createTemp('offer_media_test');
    Hive.init(_tempDir.path);
    // The shared image cache cannot be constructed under `flutter test`; these
    // tests cover the catalogue and the local-file lookup, not third-party
    // cache eviction.
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    await OfflineMediaService.instance.initialize();

    _localOnlyFile = await _writeImage('local-only.png');
    _preferLocalFile = await _writeImage('prefer-local.png');
    await OfflineMediaService.instance.mapMediaIdToLocalFile(
      'offer-media:owner-1:media-a',
      _localOnlyFile.path,
    );
    await OfflineMediaService.instance.mapMediaIdToLocalFile(
      'offer-media:owner-1:media-b',
      _preferLocalFile.path,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {
      // A temp directory left behind is harmless.
    }
  });

  // Each test uses its own account/Offer ids rather than a shared reset:
  // clearing between tests would call into the shared image cache, whose
  // platform storage is unavailable inside a unit test.

  group('Offer media catalogue', () {
    test('remembers media ids in display order', () async {
      await OfflineMediaService.instance.writeOfferMediaCatalog(
        ownerId: 'owner-order',
        offerId: 'offer-order',
        mediaObjectIds: const ['media-a', 'media-b'],
      );

      expect(
        OfflineMediaService.instance.readOfferMediaCatalog(
          ownerId: 'owner-order',
          offerId: 'offer-order',
        ),
        ['media-a', 'media-b'],
      );
    });

    test('one account cannot read back another account catalogue', () async {
      await OfflineMediaService.instance.writeOfferMediaCatalog(
        ownerId: 'owner-scope',
        offerId: 'offer-scope',
        mediaObjectIds: const ['media-a'],
      );

      expect(
        OfflineMediaService.instance.readOfferMediaCatalog(
          ownerId: 'owner-other',
          offerId: 'offer-scope',
        ),
        isEmpty,
      );
    });

    test('an authoritative empty response clears the catalogue', () async {
      final offline = OfflineMediaService.instance;
      await offline.writeOfferMediaCatalog(
        ownerId: 'owner-clear',
        offerId: 'offer-clear',
        mediaObjectIds: const ['media-a'],
      );
      await offline.writeOfferMediaCatalog(
        ownerId: 'owner-clear',
        offerId: 'offer-clear',
        mediaObjectIds: const [],
      );

      expect(
        offline.readOfferMediaCatalog(
          ownerId: 'owner-clear',
          offerId: 'offer-clear',
        ),
        isEmpty,
      );
    });

    test('forgetting one account leaves every other account untouched',
        () async {
      final offline = OfflineMediaService.instance;
      await offline.writeOfferMediaCatalog(
        ownerId: 'owner-deleted',
        offerId: 'offer-deleted',
        mediaObjectIds: const ['media-a'],
      );
      await offline.writeOfferMediaCatalog(
        ownerId: 'owner-kept',
        offerId: 'offer-kept',
        mediaObjectIds: const ['media-z'],
      );

      await offline.forgetOfferMedia(ownerId: 'owner-deleted');

      expect(
        offline.readOfferMediaCatalog(
          ownerId: 'owner-deleted',
          offerId: 'offer-deleted',
        ),
        isEmpty,
      );
      expect(
        offline.readOfferMediaCatalog(
          ownerId: 'owner-kept',
          offerId: 'offer-kept',
        ),
        ['media-z'],
      );
    });

    test('missing identity never writes or reads an unscoped entry', () async {
      final offline = OfflineMediaService.instance;
      await offline.writeOfferMediaCatalog(
        ownerId: '',
        offerId: 'offer-unscoped',
        mediaObjectIds: const ['media-a'],
      );

      expect(
        offline.readOfferMediaCatalog(ownerId: '', offerId: 'offer-unscoped'),
        isEmpty,
      );
      expect(
        offline.readOfferMediaCatalog(ownerId: 'owner-1', offerId: ''),
        isEmpty,
      );
    });
  });

  group('MediaItem.fromOfferMedia', () {
    test('an item held only locally is still known to be an image', () {
      final item = MediaItem.fromOfferMedia(const OfferMediaRef(
        mediaObjectId: 'media-a',
        cacheKey: 'offer-media:owner-1:media-a',
        localFilePath: '/cache/media-a',
      ));

      expect(item.type, MediaType.image);
      expect(item.url, isEmpty);
      expect(item.cacheKey, 'offer-media:owner-1:media-a');
    });

    test('a resolved item carries its signed URL and its stable key', () {
      final item = MediaItem.fromOfferMedia(const OfferMediaRef(
        mediaObjectId: 'media-a',
        cacheKey: 'offer-media:owner-1:media-a',
        signedUrl: 'https://media-api.example.test/a.jpg?X-Amz-Signature=aaa',
      ));

      expect(item.type, MediaType.image);
      expect(item.url, contains('X-Amz-Signature'));
      expect(item.cacheKey, 'offer-media:owner-1:media-a');
    });
  });

  group('gallery rendering from locally held bytes', () {
    testWidgets('paints from disk with no URL and no network request',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaRefs: const [
              OfferMediaRef(
                mediaObjectId: 'media-a',
                cacheKey: 'offer-media:owner-1:media-a',
                localFilePath: '/ignored/by/the/widget',
              ),
            ],
          ),
        ),
      );

      // Nothing was asked of the network: there is no CachedNetworkImage at
      // all, only a file-backed image.
      expect(find.byType(CachedNetworkImage), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect((image.image as FileImage).file.path, _localOnlyFile.path);
    });

    testWidgets('prefers held bytes over a freshly signed URL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaRefs: const [
              OfferMediaRef(
                mediaObjectId: 'media-b',
                cacheKey: 'offer-media:owner-1:media-b',
                signedUrl: 'https://media-api.example.test/b.jpg?sig=fresh',
              ),
            ],
          ),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
    });

    testWidgets(
        'falls back to the signed URL under its stable key when the bytes '
        'are not held', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaRefs: const [
              OfferMediaRef(
                mediaObjectId: 'media-c',
                cacheKey: 'offer-media:owner-1:media-c',
                signedUrl: 'https://media-api.example.test/c.jpg?sig=fresh',
              ),
            ],
          ),
        ),
      );

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, 'offer-media:owner-1:media-c');
      expect(image.imageUrl, contains('sig=fresh'));
    });

    testWidgets('another account cannot address these cached bytes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OptimizedMediaGalleryWidget(
            mediaRefs: [
              OfferMediaRef(
                mediaObjectId: 'media-a',
                // The same media object, but a different signed-in account.
                cacheKey: offerMediaCacheKey(
                  ownerId: 'owner-2',
                  mediaObjectId: 'media-a',
                ),
                signedUrl: 'https://media-api.example.test/a.jpg?sig=other',
              ),
            ],
          ),
        ),
      );

      // No FileImage: owner-2 gets a different key and must fetch its own.
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, 'offer-media:owner-2:media-a');
    });
  });

  group('applyOfferMedia', () {
    test('replaces media as a unit and clears it on an empty resolution', () {
      final base = _offer(
        mediaUrls: const ['https://example.test/old.jpg'],
        mediaObjectIds: const ['old-media'],
      ).copyWith(mediaUrl: 'https://example.test/old.jpg');

      final replaced = applyOfferMedia(
        base,
        const OfferMediaResolution(
          offerId: 'offer-1',
          ownerId: 'owner-1',
          items: [
            OfferMediaRef(
              mediaObjectId: 'new-media',
              cacheKey: 'offer-media:owner-1:new-media',
              signedUrl: 'https://example.test/new.jpg',
            ),
          ],
        ),
      );
      expect(replaced.mediaUrls, ['https://example.test/new.jpg']);
      expect(replaced.mediaObjectIds, ['new-media']);
      expect(replaced.mediaUrl, 'https://example.test/new.jpg');

      final cleared = applyOfferMedia(
        base,
        const OfferMediaResolution(
          offerId: 'offer-1',
          ownerId: 'owner-1',
          items: [],
        ),
      );
      expect(cleared.mediaUrls, isEmpty);
      expect(cleared.mediaObjectIds, isEmpty);
      expect(cleared.mediaUrl, isNull);
    });
  });
}
