import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offer_details_load_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

OfferModel _offer(
  String id, {
  String ownerId = 'owner-a',
  String location = 'list value',
  List<String> mediaUrls = const [],
  List<String> mediaIds = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return OfferModel(
    id: id,
    userId: ownerId,
    offerType: 'rent',
    selectedCity: 'Dubai',
    selectedAreas: const [],
    location: location,
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
    createdAt: now,
    updatedAt: now,
    mediaUrls: mediaUrls,
    mediaObjectIds: mediaIds,
  );
}

/// One authoritative `/offer-media` response.
OfferMediaResolution _media(
  String offerId, {
  String ownerId = 'owner-a',
  List<String> ids = const ['media-a'],
  List<String> urls = const ['https://example.test/a.jpg?signature=fresh'],
}) =>
    OfferMediaResolution(
      offerId: offerId,
      ownerId: ownerId,
      items: [
        for (var i = 0; i < ids.length; i++)
          OfferMediaRef(
            mediaObjectId: ids[i],
            cacheKey: offerMediaCacheKey(
              ownerId: ownerId,
              mediaObjectId: ids[i],
            ),
            signedUrl: i < urls.length ? urls[i] : null,
          ),
      ],
    );

/// Media this device already holds: an id and a file, but no URL at all.
List<OfferMediaRef> _localOnly({
  String ownerId = 'owner-a',
  List<String> ids = const ['media-a'],
}) =>
    [
      for (final id in ids)
        OfferMediaRef(
          mediaObjectId: id,
          cacheKey: offerMediaCacheKey(ownerId: ownerId, mediaObjectId: id),
          localFilePath: '/cache/$id.jpg',
        ),
    ];

void main() {
  test('trusted ID-loader metadata is not fetched twice', () async {
    var metadataCalls = 0;
    var mediaCalls = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a', location: 'authoritative'),
      initialMetadataResolved: true,
      loadMetadata: (id) async {
        metadataCalls++;
        return _offer(id);
      },
      resolveMedia: ({required offerId, required ownerId}) async {
        mediaCalls++;
        return _media(offerId, ownerId: ownerId);
      },
      onChanged: () {},
    );

    await coordinator.load();

    expect(metadataCalls, 0);
    expect(mediaCalls, 1);
    expect(coordinator.offer.location, 'authoritative');
    expect(coordinator.offer.mediaObjectIds, ['media-a']);
  });

  test('list fields stay usable while metadata then media resolve', () async {
    final metadata = Completer<OfferModel?>();
    final media = Completer<OfferMediaResolution?>();
    final states = <String>[];
    late OfferDetailsLoadCoordinator coordinator;
    coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) => metadata.future,
      resolveMedia: ({required offerId, required ownerId}) => media.future,
      onChanged: () {
        states.add(
          '${coordinator.offer.location}:'
          '${coordinator.isMetadataLoading}:'
          '${coordinator.isMediaLoading}',
        );
      },
    );

    final load = coordinator.load();
    expect(coordinator.offer.location, 'list value');
    expect(coordinator.isMetadataLoading, isTrue);

    metadata.complete(_offer('offer-a', location: 'fresh metadata'));
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.offer.location, 'fresh metadata');
    expect(coordinator.isMetadataLoading, isFalse);
    expect(coordinator.isMediaLoading, isTrue);

    media.complete(_media('offer-a'));
    await load;

    expect(coordinator.isLoading, isFalse);
    expect(coordinator.offer.mediaObjectIds, ['media-a']);
    expect(states, isNotEmpty);
  });

  test('media resolution starts before metadata returns, not after it',
      () async {
    final metadata = Completer<OfferModel?>();
    var mediaStarted = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) => metadata.future,
      resolveMedia: ({required offerId, required ownerId}) async {
        mediaStarted++;
        return _media(offerId, ownerId: ownerId);
      },
      onChanged: () {},
    );

    final load = coordinator.load();
    await Future<void>.delayed(Duration.zero);

    // The whole point of the split: signing does not queue behind the row.
    expect(mediaStarted, 1,
        reason: 'media must not wait for the metadata round trip');
    expect(coordinator.isMetadataLoading, isTrue);
    expect(coordinator.isMediaLoading, isTrue);

    metadata.complete(_offer('offer-a', location: 'fresh'));
    await load;

    expect(mediaStarted, 1, reason: 'no duplicate media request');
    expect(coordinator.offer.mediaObjectIds, ['media-a']);
  });

  test('locally held media is renderable before any load starts', () {
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId),
      readCachedMedia: (id) => _localOnly(),
      onChanged: () {},
    );

    expect(coordinator.hasRenderableMedia, isTrue);
    expect(coordinator.mediaIsAuthoritative, isFalse);
    expect(coordinator.mediaItems.single.hasSignedUrl, isFalse);
    expect(coordinator.mediaItems.single.hasLocalBytes, isTrue);
  });

  test('a caller-supplied model with URLs is preferred over the local cache',
      () {
    var cacheReads = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer(
        'offer-a',
        mediaUrls: const ['https://example.test/from-list.jpg'],
        mediaIds: const ['media-list'],
      ),
      initialMetadataResolved: false,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId),
      readCachedMedia: (id) {
        cacheReads++;
        return _localOnly();
      },
      onChanged: () {},
    );

    expect(cacheReads, 0);
    expect(coordinator.mediaItems.single.mediaObjectId, 'media-list');
    expect(coordinator.mediaItems.single.cacheKey,
        'offer-media:owner-a:media-list');
  });

  test('a fresh metadata row never blanks media already on screen', () async {
    final metadata = Completer<OfferModel?>();
    final media = Completer<OfferMediaResolution?>();
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) => metadata.future,
      resolveMedia: ({required offerId, required ownerId}) => media.future,
      readCachedMedia: (id) => _localOnly(),
      onChanged: () {},
    );

    final load = coordinator.load();
    metadata.complete(_offer('offer-a', location: 'fresh'));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.offer.location, 'fresh');
    expect(coordinator.hasRenderableMedia, isTrue);

    media.complete(_media('offer-a'));
    await load;

    // The authoritative set replaces the cached one wholesale.
    expect(coordinator.mediaIsAuthoritative, isTrue);
    expect(coordinator.mediaItems.single.hasSignedUrl, isTrue);
  });

  test('an authoritative empty response clears previously cached media',
      () async {
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: true,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId, ids: const [], urls: const []),
      readCachedMedia: (id) => _localOnly(),
      onChanged: () {},
    );

    expect(coordinator.hasRenderableMedia, isTrue);
    await coordinator.load();

    expect(coordinator.mediaItems, isEmpty);
    expect(coordinator.hasRenderableMedia, isFalse);
    expect(coordinator.mediaLoadFailed, isFalse);
  });

  test('a backend with no media stage keeps what metadata supplied', () async {
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) async => _offer(
        id,
        mediaUrls: const ['https://firebase.test/stable.jpg'],
      ),
      resolveMedia: ({required offerId, required ownerId}) async => null,
      onChanged: () {},
    );

    await coordinator.load();

    expect(coordinator.mediaLoadFailed, isFalse);
    expect(coordinator.hasRenderableMedia, isTrue);
    expect(coordinator.mediaItems.single.signedUrl,
        'https://firebase.test/stable.jpg');
    // No ids on this backend, so no stable key and the URL keys the cache.
    expect(coordinator.mediaItems.single.cacheKey, isNull);
  });

  test('media failure settles and one explicit retry obtains a fresh URL',
      () async {
    var mediaCalls = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a', location: 'authoritative'),
      initialMetadataResolved: true,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) async {
        mediaCalls++;
        if (mediaCalls == 1) throw StateError('expired transport');
        return _media(
          offerId,
          ownerId: ownerId,
          urls: const ['https://example.test/a.jpg?signature=new'],
        );
      },
      onChanged: () {},
    );

    await coordinator.load();
    expect(coordinator.isLoading, isFalse);
    expect(coordinator.mediaLoadFailed, isTrue);
    expect(mediaCalls, 1);

    await coordinator.retry();
    expect(mediaCalls, 2);
    expect(coordinator.mediaLoadFailed, isFalse);
    expect(coordinator.offer.mediaUrls.single, contains('signature=new'));
  });

  test('metadata failure retries metadata and cannot remain loading', () async {
    var metadataCalls = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) async {
        metadataCalls++;
        if (metadataCalls == 1) throw StateError('temporary');
        return _offer(id, location: 'fresh');
      },
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId),
      onChanged: () {},
    );

    await coordinator.load();
    expect(coordinator.metadataLoadFailed, isTrue);
    expect(coordinator.isLoading, isFalse);

    await coordinator.retry();
    expect(metadataCalls, 2);
    expect(coordinator.metadataLoadFailed, isFalse);
    expect(coordinator.offer.location, 'fresh');
  });

  test('null or mismatched metadata is never presented', () async {
    final missing = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) async => null,
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId),
      onChanged: () {},
    );
    await missing.load();
    expect(missing.detailsUnavailable, isTrue);
    expect(missing.isLoading, isFalse);

    final mismatched = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) async => _offer('offer-b'),
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId),
      onChanged: () {},
    );
    await mismatched.load();
    expect(mismatched.detailsUnavailable, isTrue);
    expect(mismatched.isLoading, isFalse);
  });

  test('late results from a previous Offer cannot update the new screen',
      () async {
    final oldMetadata = Completer<OfferModel?>();
    var oldNotifications = 0;
    final oldCoordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: false,
      loadMetadata: (id) => oldMetadata.future,
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId),
      onChanged: () => oldNotifications++,
    );
    final oldLoad = oldCoordinator.load();
    final notificationsBeforeDispose = oldNotifications;
    oldCoordinator.dispose();

    final newCoordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-b'),
      initialMetadataResolved: true,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) async =>
          _media(offerId, ownerId: ownerId, ids: const ['media-b']),
      onChanged: () {},
    );
    await newCoordinator.load();
    oldMetadata.complete(_offer('offer-a', location: 'late stale value'));
    await oldLoad;

    expect(oldNotifications, notificationsBeforeDispose);
    expect(newCoordinator.offer.id, 'offer-b');
    expect(newCoordinator.offer.mediaObjectIds, ['media-b']);
  });

  test('disposal prevents setState-style callbacks after an async result',
      () async {
    final media = Completer<OfferMediaResolution?>();
    var notifications = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a'),
      initialMetadataResolved: true,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) => media.future,
      onChanged: () => notifications++,
    );

    final load = coordinator.load();
    final notificationsBeforeDispose = notifications;
    coordinator.dispose();
    media.complete(_media('offer-a'));
    await load;

    expect(notifications, notificationsBeforeDispose);
  });

  test('media resolved for another owner is rejected without a loop', () async {
    var calls = 0;
    final coordinator = OfferDetailsLoadCoordinator(
      initialOffer: _offer('offer-a', ownerId: 'owner-a'),
      initialMetadataResolved: true,
      loadMetadata: (id) async => _offer(id),
      resolveMedia: ({required offerId, required ownerId}) async {
        calls++;
        return _media(offerId, ownerId: 'owner-b');
      },
      onChanged: () {},
    );

    await coordinator.load();

    expect(calls, 1);
    expect(coordinator.mediaLoadFailed, isTrue);
    expect(coordinator.isLoading, isFalse);
  });

  test('media started for a stale owner is discarded and re-requested',
      () async {
    final requestedOwners = <String>[];
    final coordinator = OfferDetailsLoadCoordinator(
      // A stale caller-supplied model claiming the wrong owner.
      initialOffer: _offer('offer-a', ownerId: 'owner-stale'),
      initialMetadataResolved: false,
      loadMetadata: (id) async => _offer(id, ownerId: 'owner-a'),
      resolveMedia: ({required offerId, required ownerId}) async {
        requestedOwners.add(ownerId);
        return _media(offerId, ownerId: ownerId);
      },
      onChanged: () {},
    );

    await coordinator.load();

    expect(requestedOwners, ['owner-stale', 'owner-a']);
    expect(coordinator.mediaLoadFailed, isFalse);
    expect(
        coordinator.mediaItems.single.cacheKey, 'offer-media:owner-a:media-a');
  });
}
