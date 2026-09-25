import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offer_details_load_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers telling a revoked grant apart from a bad connection.
///
/// Only one outcome may remove privately held image bytes: the Worker
/// answering authoritatively that this account has no such Offer. Everything
/// else — an expired signed URL, a timeout, an upstream failure, a rejected
/// token — establishes nothing about access, so previously authorized media
/// must stay exactly as it is.
OfferModel _offer(String id, {String ownerId = 'owner-a'}) => OfferModel(
      id: id,
      userId: ownerId,
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: 'list value',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '1',
      maxPrice: '2',
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
      mediaUrls: const <String>[],
    );

List<OfferMediaRef> _held({String ownerId = 'owner-a'}) => [
      OfferMediaRef(
        mediaObjectId: 'media-a',
        cacheKey: offerMediaCacheKey(
          ownerId: ownerId,
          mediaObjectId: 'media-a',
        ),
        localFilePath: '/cache/media-a.jpg',
      ),
    ];

OfferDetailsLoadCoordinator _coordinator({
  required Future<OfferMediaResolution?> Function() onResolve,
  void Function()? onChanged,
}) =>
    OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: true,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) => onResolve(),
      readCachedMedia: (id) => _held(),
      onChanged: onChanged ?? () {},
    );

void main() {
  group('Worker status classification', () {
    test('404 is the authoritative "no such Offer for this account"', () {
      // assertOwnsOffer reaches 404 only after its ownership query succeeded
      // and returned no row; an upstream failure answers 502 instead.
      final error = R2OfferMediaHttpException(404);
      expect(error.isAccessDenied, isTrue);
      expect(error.isUnauthenticated, isFalse);
    });

    test('403 is also treated as a definitive rejection', () {
      expect(R2OfferMediaHttpException(403).isAccessDenied, isTrue);
    });

    test('401 is a session problem, never proof of revocation', () {
      final error = R2OfferMediaHttpException(401);
      expect(error.isUnauthenticated, isTrue);
      expect(error.isAccessDenied, isFalse,
          reason: 'a rejected token must never delete private media');
    });

    test('server failures establish nothing about access', () {
      for (final status in [500, 502, 503, 504]) {
        final error = R2OfferMediaHttpException(status);
        expect(error.isAccessDenied, isFalse, reason: 'status $status');
        expect(error.isUnauthenticated, isFalse, reason: 'status $status');
      }
    });

    test('it stays catchable as the existing exception type', () {
      expect(R2OfferMediaHttpException(404), isA<R2UploadException>());
    });

    test('the Worker message is never carried into the app', () {
      // Only the status travels; provider text can name internal detail.
      expect(R2OfferMediaHttpException(404).message, isNot(contains('owned')));
    });
  });

  group('an expired signed URL is not a revocation', () {
    test('image transport failures never produce an access-denied outcome',
        () async {
      // A signed R2 GET that has expired fails on the cache manager's path,
      // which is a different code path from the Worker API entirely. It
      // resolves to "no local bytes", never to an authorization verdict.
      OfflineMediaService.fetchCachedBytes =
          (_, __) async => throw const R2UploadException('403 from R2');
      addTearDown(() {
        OfflineMediaService.fetchCachedBytes = (_, __) async => null;
      });

      Object? thrown;
      try {
        await OfflineMediaService.instance.ensureMediaIdCached(
          cacheKey: 'offer-media:owner-a:media-a',
          url: 'https://media.example.test/a.jpg?X-Amz-Signature=expired',
        );
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isNot(isA<OfferMediaException>()));
    });
  });

  group('coordinator reaction', () {
    test('a proven revocation stops displaying and offers no retry', () async {
      var calls = 0;
      final coordinator = _coordinator(onResolve: () async {
        calls++;
        throw const OfferMediaException(OfferMediaFailureKind.accessDenied);
      });

      expect(coordinator.hasRenderableMedia, isTrue);
      await coordinator.load();

      expect(coordinator.mediaAccessRevoked, isTrue);
      expect(coordinator.mediaItems, isEmpty);
      expect(coordinator.hasRenderableMedia, isFalse,
          reason: 'nothing may redisplay media the server says is gone');
      expect(coordinator.offer.mediaUrls, isEmpty);
      expect(coordinator.mediaLoadFailed, isFalse,
          reason: 'this is settled, not a retryable transport problem');

      await coordinator.retry();
      expect(calls, 1, reason: 'a retry cannot change an authoritative answer');
    });

    test('a transient failure keeps held media and allows a retry', () async {
      var calls = 0;
      final coordinator = _coordinator(onResolve: () async {
        calls++;
        throw const OfferMediaException(OfferMediaFailureKind.transient);
      });

      await coordinator.load();

      expect(coordinator.mediaAccessRevoked, isFalse);
      expect(coordinator.mediaLoadFailed, isTrue);
      expect(coordinator.hasRenderableMedia, isTrue,
          reason: 'offline or a timeout says nothing about access');

      await coordinator.retry();
      expect(calls, 2);
    });

    test('a rejected token keeps held media', () async {
      final coordinator = _coordinator(
        onResolve: () async => throw const OfferMediaException(
          OfferMediaFailureKind.unauthenticated,
        ),
      );

      await coordinator.load();

      expect(coordinator.mediaAccessRevoked, isFalse);
      expect(coordinator.mediaLoadFailed, isTrue);
      expect(coordinator.hasRenderableMedia, isTrue);
    });

    test('an unexpected error stays retryable rather than destructive',
        () async {
      final coordinator =
          _coordinator(onResolve: () async => throw StateError('boom'));

      await coordinator.load();

      expect(coordinator.mediaAccessRevoked, isFalse);
      expect(coordinator.mediaLoadFailed, isTrue);
      expect(coordinator.hasRenderableMedia, isTrue);
    });

    test('a revocation after disposal never calls back', () async {
      final completer = Completer<OfferMediaResolution?>();
      var notifications = 0;
      final coordinator = _coordinator(
        onResolve: () => completer.future,
        onChanged: () => notifications++,
      );

      final load = coordinator.load();
      final before = notifications;
      coordinator.dispose();
      completer.completeError(
        const OfferMediaException(OfferMediaFailureKind.accessDenied),
      );
      await load;

      expect(notifications, before);
    });
  });
}
