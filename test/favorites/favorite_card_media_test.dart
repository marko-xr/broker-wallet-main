// Which picture a favorite's card shows from its record's private media:
// the first photo; if the record has only videos, the first video's frame; a
// video that comes first never hides a photo. Pure logic, no engine needed.

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorite_card_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = 'user-1';

String _key(String mediaId) =>
    offerMediaCacheKey(ownerId: _account, mediaObjectId: mediaId)!;

OfferMediaRef _photo(String id, {String? url = 'https://signed.example/p'}) =>
    OfferMediaRef(
      mediaObjectId: id,
      cacheKey: _key(id),
      signedUrl: url,
    );

OfferMediaRef _video(
  String id, {
  String? url = 'https://signed.example/v',
  String? poster,
}) =>
    OfferMediaRef(
      mediaObjectId: id,
      cacheKey: _key(id),
      signedUrl: url,
      isVideo: true,
      posterPath: poster,
    );

OfferModel _offer({List<String> mediaObjectIds = const []}) {
  final now = DateTime(2026, 1, 1);
  return OfferModel(
    id: 'offer-1',
    userId: _account,
    offerType: 'rent',
    selectedCity: 'Dubai',
    selectedAreas: const ['Marina'],
    location: 'Dubai Marina',
    phoneNumber: '500000000',
    countryCode: '+971',
    minPrice: '1000',
    maxPrice: '2000',
    notes: '',
    specificPropertyType: 'Apartment',
    rooms: 1,
    bathrooms: 1,
    pickUpLocation: '',
    pickUpLatitude: 0,
    pickUpLongitude: 0,
    pickUpAddress: '',
    uploadedFileName: '',
    createdAt: now,
    updatedAt: now,
    mediaUrls: const [],
    mediaObjectIds: mediaObjectIds,
  );
}

void main() {
  group('pick', () {
    test('the first photo wins even when a video comes first', () {
      final picked = FavoriteCardMedia.pick([
        _video('v1'),
        _photo('p1'),
        _photo('p2'),
      ]);

      expect(picked!.isVideo, isFalse);
      expect(picked.cacheKey, _key('p1'));
      expect(picked.signedUrl, 'https://signed.example/p');
    });

    test('with only videos, the first video\'s frame is used', () {
      final picked = FavoriteCardMedia.pick([
        _video('v1', poster: '/frames/v1.jpg'),
        _video('v2'),
      ]);

      expect(picked!.isVideo, isTrue);
      expect(picked.cacheKey, _key('v1'));
      expect(picked.posterPath, '/frames/v1.jpg');
    });

    test('a video that cannot be drawn is passed over for one that can', () {
      final picked = FavoriteCardMedia.pick([
        _video('v1', url: null),
        _video('v2'),
      ]);

      expect(picked!.cacheKey, _key('v2'));
    });

    test('a photo held only on this device counts as drawable', () {
      final picked = FavoriteCardMedia.pick([
        OfferMediaRef(
          mediaObjectId: 'p1',
          cacheKey: _key('p1'),
          localFilePath: '/offer_media/p1.jpg',
        ),
      ]);

      expect(picked!.isVideo, isFalse);
      expect(picked.signedUrl, isNull);
    });

    test('nothing drawable, or an item with no identity, picks nothing', () {
      expect(FavoriteCardMedia.pick(const []), isNull);
      expect(FavoriteCardMedia.pick([_photo('p1', url: null)]), isNull);
      expect(
        FavoriteCardMedia.pick([
          const OfferMediaRef(
            mediaObjectId: 'p1',
            cacheKey: null,
            signedUrl: 'https://signed.example/p',
          ),
        ]),
        isNull,
        reason: 'without an account-scoped key it cannot be cached safely',
      );
    });
  });

  group('fromOffer', () {
    late OfferMediaUrlCache cache;
    setUp(() => cache = OfferMediaUrlCache());

    void remember(String id, {required bool isVideo}) => cache.put(
          _key(id),
          'https://signed.example/$id',
          DateTime.now().add(const Duration(minutes: 10)),
          isVideo: isVideo,
        );

    test('an Offer whose first file is a video shows its first photo', () {
      remember('v1', isVideo: true);
      remember('p1', isVideo: false);

      final picked = FavoriteCardMedia.fromOffer(
        _offer(mediaObjectIds: ['v1', 'p1']),
        urlCache: cache,
      );

      expect(picked!.isVideo, isFalse);
      expect(picked.cacheKey, _key('p1'));
      expect(picked.signedUrl, 'https://signed.example/p1');
    });

    test('an Offer with only videos shows its first video\'s frame', () {
      remember('v1', isVideo: true);
      remember('v2', isVideo: true);

      final picked = FavoriteCardMedia.fromOffer(
        _offer(mediaObjectIds: ['v1', 'v2']),
        urlCache: cache,
      );

      expect(picked!.isVideo, isTrue);
      expect(picked.cacheKey, _key('v1'));
    });

    test('an item whose kind is unknown is never guessed to be a photo', () {
      // Only 'p2' was remembered; 'v1' could be a video.
      remember('p2', isVideo: false);

      final picked = FavoriteCardMedia.fromOffer(
        _offer(mediaObjectIds: ['v1', 'p2']),
        urlCache: cache,
      );

      expect(picked!.cacheKey, _key('p2'));
      expect(
        FavoriteCardMedia.fromOffer(
          _offer(mediaObjectIds: ['v1']),
          urlCache: cache,
        ),
        isNull,
      );
    });

    test('an Offer with no private media (plain URLs) has none', () {
      expect(
        FavoriteCardMedia.fromOffer(_offer(), urlCache: cache),
        isNull,
      );
    });
  });

  group('stored form', () {
    test('keeps the identity and the kind, never a link', () {
      final stored = FavoriteCardMedia(
        cacheKey: _key('p1'),
        isVideo: false,
        signedUrl: 'https://signed.example/secret?sig=abc',
        posterPath: '/frames/p1.jpg',
      ).toStored();

      expect(stored.contains('https'), isFalse);
      expect(stored.contains('sig='), isFalse);
      expect(stored.contains('/frames'), isFalse);

      final restored = FavoriteCardMedia.fromStored(stored)!;
      expect(restored.cacheKey, _key('p1'));
      expect(restored.isVideo, isFalse);
      expect(restored.signedUrl, isNull);
    });

    test('anything else restores to nothing', () {
      expect(FavoriteCardMedia.fromStored(null), isNull);
      expect(FavoriteCardMedia.fromStored(''), isNull);
      expect(FavoriteCardMedia.fromStored('not json'), isNull);
      expect(FavoriteCardMedia.fromStored('[1,2]'), isNull);
      expect(FavoriteCardMedia.fromStored('{"k":"x","v":true}'), isNull,
          reason: 'a key that is not a private-media identity');
      expect(FavoriteCardMedia.fromStored('{"k":"${_key('p1')}"}'), isNull,
          reason: 'the kind is required');
    });
  });
}
