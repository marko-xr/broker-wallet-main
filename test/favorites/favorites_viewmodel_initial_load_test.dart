import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

typedef MetadataMap = Map<String, List<FavoriteMetadata>>;

class FakeFavoriteService extends FavoriteService {
  FakeFavoriteService({
    this.cachedFavorites = const [],
    this.metadata = const {},
    this.metadataLoader,
  });

  final List<FavoriteItem> cachedFavorites;
  final MetadataMap metadata;
  final Future<MetadataMap> Function(int call)? metadataLoader;

  int authWaitCount = 0;
  int cacheInitializationCount = 0;
  int metadataLoadCount = 0;
  final List<List<FavoriteItem>> cacheWrites = [];

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    authWaitCount++;
  }

  @override
  Future<void> initializeCache({String? uidOverride}) async {
    cacheInitializationCount++;
  }

  @override
  List<FavoriteItem> getCachedFavoritesSync() =>
      List<FavoriteItem>.from(cachedFavorites);

  @override
  Future<MetadataMap> getAllFavoritesWithMetadata() async {
    metadataLoadCount++;
    final loader = metadataLoader;
    if (loader != null) {
      return loader(metadataLoadCount);
    }
    return metadata;
  }

  @override
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {
    cacheWrites.add(List<FavoriteItem>.from(favorites));
  }
}

/// A service whose cache box is not open when the screen is built: it has
/// nothing to read until [initializeCache] completes (held back by [openGate]).
class LateCacheFavoriteService extends FakeFavoriteService {
  LateCacheFavoriteService({
    required this.cacheAfterOpen,
    this.openGate,
    super.metadataLoader,
  });

  final List<FavoriteItem> cacheAfterOpen;
  final Completer<void>? openGate;
  bool _open = false;

  @override
  Future<void> initializeCache({String? uidOverride}) async {
    await super.initializeCache(uidOverride: uidOverride);
    if (openGate != null) await openGate!.future;
    _open = true;
  }

  @override
  List<FavoriteItem> getCachedFavoritesSync() =>
      _open ? List<FavoriteItem>.from(cacheAfterOpen) : <FavoriteItem>[];
}

/// An Owner source: the record, and what resolving its private media does.
class FakeOwnerService extends OwnerService {
  FakeOwnerService({
    required this.owners,
    this.media = const {},
    this.resolveFails = false,
    this.cached = const {},
    this.accountId = 'user-1',
  });

  final Map<String, OwnerModel> owners;

  /// Per Owner id: the server's media list; absent means no media stage.
  final Map<String, List<OfferMediaRef>> media;
  final bool resolveFails;

  /// Per Owner id: what this device already holds.
  final Map<String, List<OfferMediaRef>> cached;
  final String? accountId;
  int resolveCalls = 0;

  @override
  Future<OwnerModel?> getOwner(String ownerId) async => owners[ownerId];

  @override
  String? get currentOwnerId => accountId;

  @override
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  }) async {
    resolveCalls++;
    if (resolveFails)
      throw const OfferMediaException(OfferMediaFailureKind.transient);
    final items = media[recordId];
    if (items == null) return null;
    return OfferMediaResolution(
        offerId: recordId, ownerId: ownerId, items: items);
  }

  @override
  List<OfferMediaRef> cachedMedia(String recordId) =>
      cached[recordId] ?? const <OfferMediaRef>[];
}

OwnerModel owner(String id, {List<String> mediaUrls = const []}) {
  final now = DateTime(2026, 1, 1);
  return OwnerModel(
    id: id,
    userId: 'user-1',
    name: 'Owner $id',
    phoneNumber: '500000000',
    countryCode: '+971',
    typeOfProperties: 'Villa',
    propertyLocation: 'Dubai',
    notes: '',
    pickUpLocation: '',
    pickUpLatitude: 0,
    pickUpLongitude: 0,
    pickUpAddress: '',
    mediaUrls: mediaUrls,
    createdAt: now,
    updatedAt: now,
  );
}

String mediaKey(String mediaId) =>
    offerMediaCacheKey(ownerId: 'user-1', mediaObjectId: mediaId)!;

OfferMediaRef photoRef(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: mediaKey(id),
      signedUrl: 'https://signed.example/$id',
    );

OfferMediaRef videoRef(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: mediaKey(id),
      signedUrl: 'https://signed.example/$id',
      isVideo: true,
    );

class FakeOfferService extends OfferService {
  FakeOfferService(this.offers);

  final Map<String, OfferModel> offers;

  @override
  Future<OfferModel?> getOffer(String offerId) async => offers[offerId];
}

FavoriteItem cachedItem({
  required String id,
  required String type,
  required DateTime addedAt,
}) {
  return FavoriteItem(
    id: id,
    type: type,
    title: '$type-$id',
    subtitle: 'subtitle-$id',
    addedAt: addedAt,
  );
}

OfferModel offer(String id) {
  final now = DateTime(2026, 1, 1);
  return OfferModel(
    id: id,
    userId: 'user-1',
    offerType: 'rent',
    selectedCity: 'Dubai',
    selectedAreas: const ['Marina'],
    location: 'Dubai Marina',
    phoneNumber: '500000000',
    countryCode: '+971',
    minPrice: '1000',
    maxPrice: '2000',
    notes: '',
    specificPropertyType: 'Apartment $id',
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
  );
}

Future<void> flushAsync([int turns = 20]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached before the async test timeout.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoritesViewModel initial loading', () {
    test('empty cache starts exactly one authoritative metadata load',
        () async {
      final metadataCompleter = Completer<MetadataMap>();
      final favoriteService = FakeFavoriteService(
        metadataLoader: (_) => metadataCompleter.future,
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );

      await waitUntil(() => favoriteService.metadataLoadCount == 1);

      expect(favoriteService.cacheInitializationCount, 1);
      expect(favoriteService.metadataLoadCount, 1);

      metadataCompleter.complete({});
      await flushAsync();
      viewModel.dispose();
    });

    test('valid cache paints immediately and refreshes once in background',
        () async {
      final cached = cachedItem(
        id: 'cached-offer',
        type: 'offers',
        addedAt: DateTime(2026, 1, 1),
      );
      final metadataCompleter = Completer<MetadataMap>();
      final favoriteService = FakeFavoriteService(
        cachedFavorites: [cached],
        metadataLoader: (_) => metadataCompleter.future,
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );

      expect(
          viewModel.cachedFavorites.map((item) => item.id), ['cached-offer']);
      expect(
          viewModel.displayFavorites.map((item) => item.id), ['cached-offer']);

      await waitUntil(() => favoriteService.metadataLoadCount == 1);
      expect(favoriteService.cacheInitializationCount, 1);
      expect(favoriteService.metadataLoadCount, 1);

      metadataCompleter.complete({});
      await flushAsync();
      viewModel.dispose();
    });

    test(
        'a cache that opens after the screen was built paints while the first '
        'load is still running', () async {
      final metadataCompleter = Completer<MetadataMap>();
      final favoriteService = LateCacheFavoriteService(
        cacheAfterOpen: [
          cachedItem(
              id: 'cached-offer',
              type: 'offers',
              addedAt: DateTime(2026, 1, 1)),
        ],
        metadataLoader: (_) => metadataCompleter.future,
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );
      expect(viewModel.cachedFavorites, isEmpty,
          reason: 'nothing could be read when the screen was built');

      await waitUntil(() => viewModel.cachedFavorites.isNotEmpty);

      expect(viewModel.isLoading, isTrue, reason: 'the first load still runs');
      expect(
          viewModel.displayFavorites.map((item) => item.id), ['cached-offer']);

      metadataCompleter.complete({});
      await flushAsync();
      viewModel.dispose();
    });

    test(
        'once the first load has answered, a cache that opens late does not '
        'bring old items back', () async {
      final openGate = Completer<void>();
      final favoriteService = LateCacheFavoriteService(
        cacheAfterOpen: [
          cachedItem(
              id: 'old-offer', type: 'offers', addedAt: DateTime(2026, 1, 1)),
        ],
        openGate: openGate,
        metadataLoader: (_) async => <String, List<FavoriteMetadata>>{},
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );

      await waitUntil(
          () => favoriteService.metadataLoadCount == 1 && !viewModel.isLoading);
      openGate.complete();
      await flushAsync();

      expect(viewModel.cachedFavorites, isEmpty,
          reason: 'the load said there are none; that answer is the truth');
      expect(viewModel.displayFavorites, isEmpty);
      viewModel.dispose();
    });

    test('successful cold load preserves cached and ordered display semantics',
        () async {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 1, 2);
      final favoriteService = FakeFavoriteService(
        metadata: {
          'offers': [
            FavoriteMetadata(itemId: 'older', type: 'offers', addedAt: older),
            FavoriteMetadata(itemId: 'newer', type: 'offers', addedAt: newer),
          ],
        },
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService({
          'older': offer('older'),
          'newer': offer('newer'),
        }),
      );

      await waitUntil(() => viewModel.cachedFavorites.length == 2);

      expect(favoriteService.metadataLoadCount, 1);
      expect(favoriteService.cacheWrites, hasLength(1));
      expect(
        viewModel.cachedFavorites.map((item) => item.id),
        ['newer', 'older'],
      );
      expect(
        viewModel.displayFavorites.map((item) => item.id),
        ['newer', 'older'],
      );
      viewModel.dispose();
    });

    test('failed cold load settles safely and existing refresh can retry',
        () async {
      final favoriteService = FakeFavoriteService(
        metadataLoader: (call) {
          if (call == 1) {
            return Future<MetadataMap>.error(StateError('network failed'));
          }
          return Future<MetadataMap>.value({});
        },
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );

      await waitUntil(() => viewModel.error != null && !viewModel.isLoading);

      expect(favoriteService.metadataLoadCount, 1);
      expect(viewModel.error, contains('network failed'));

      await viewModel.refresh();

      expect(favoriteService.metadataLoadCount, 2);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.isRefreshing, isFalse);
      viewModel.dispose();
    });

    test('completion after disposal sends no late listener notification',
        () async {
      final metadataCompleter = Completer<MetadataMap>();
      final favoriteService = FakeFavoriteService(
        metadataLoader: (_) => metadataCompleter.future,
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );
      var listenerCalls = 0;
      viewModel.addListener(() => listenerCalls++);

      await waitUntil(() => favoriteService.metadataLoadCount == 1);
      listenerCalls = 0;
      viewModel.dispose();
      metadataCompleter.complete({});
      await flushAsync();

      expect(listenerCalls, 0);
    });

    test(
        'optimistic notification still triggers the existing debounced refresh',
        () async {
      final favoriteService = FakeFavoriteService();
      final optimisticService = OptimisticFavoritesService();
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );

      await waitUntil(() => favoriteService.metadataLoadCount == 1);
      optimisticService.clearState();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await waitUntil(() => favoriteService.metadataLoadCount == 2);

      expect(favoriteService.metadataLoadCount, 2);
      viewModel.dispose();
      optimisticService.dispose();
    });

    test('warm cached ordering and type filtering remain unchanged', () async {
      final metadataCompleter = Completer<MetadataMap>();
      final favoriteService = FakeFavoriteService(
        cachedFavorites: [
          cachedItem(
            id: 'request-newer',
            type: 'requests',
            addedAt: DateTime(2026, 1, 2),
          ),
          cachedItem(
            id: 'offer-older',
            type: 'offers',
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
        metadataLoader: (_) => metadataCompleter.future,
      );
      final viewModel = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: FakeOfferService(const {}),
      );

      expect(
        viewModel.displayFavorites.map((item) => item.id),
        ['request-newer', 'offer-older'],
      );

      final offersFilter =
          viewModel.filters.indexWhere((filter) => filter.labelKey == 'offers');
      viewModel.toggleFilter(offersFilter);

      expect(
          viewModel.displayFavorites.map((item) => item.id), ['offer-older']);

      await waitUntil(() => favoriteService.metadataLoadCount == 1);
      viewModel.dispose();
      metadataCompleter.complete({});
      await flushAsync();
    });
  });

  group('FavoritesViewModel card media', () {
    Future<FavoritesViewModel> load({
      Map<String, List<FavoriteMetadata>> metadata = const {},
      FakeOwnerService? owners,
      Map<String, OfferModel> offers = const {},
    }) async {
      final viewModel = FavoritesViewModel(
        favoriteService: FakeFavoriteService(metadata: metadata),
        offerService: FakeOfferService(offers),
        ownerService: owners ?? FakeOwnerService(owners: const {}),
      );
      addTearDown(viewModel.dispose);
      await waitUntil(() => viewModel.cachedFavorites.isNotEmpty);
      return viewModel;
    }

    Map<String, List<FavoriteMetadata>> ownerFavorites(List<String> ids) => {
          'owners': [
            for (final id in ids)
              FavoriteMetadata(
                  itemId: id, type: 'owners', addedAt: DateTime(2026, 1, 1)),
          ],
        };

    test('an Owner whose first file is a video shows its first photo',
        () async {
      final service = FakeOwnerService(
        owners: {'o1': owner('o1')},
        media: {
          'o1': [videoRef('v1'), photoRef('p1')],
        },
      );

      final vm = await load(metadata: ownerFavorites(['o1']), owners: service);

      final item = vm.cachedFavorites.single;
      expect(item.media!.isVideo, isFalse);
      expect(item.media!.cacheKey, mediaKey('p1'));
      expect(item.imageUrl, isNull);
    });

    test('an Owner with only videos shows the first video\'s frame', () async {
      final service = FakeOwnerService(
        owners: {'o1': owner('o1')},
        media: {
          'o1': [videoRef('v1'), videoRef('v2')],
        },
      );

      final vm = await load(metadata: ownerFavorites(['o1']), owners: service);

      expect(vm.cachedFavorites.single.media!.isVideo, isTrue);
      expect(vm.cachedFavorites.single.media!.cacheKey, mediaKey('v1'));
    });

    test('every Owner\'s media is resolved, each for its own record', () async {
      final service = FakeOwnerService(
        owners: {'o1': owner('o1'), 'o2': owner('o2')},
        media: {
          'o1': [photoRef('p1')],
          'o2': [videoRef('v2')],
        },
      );

      final vm =
          await load(metadata: ownerFavorites(['o1', 'o2']), owners: service);
      await waitUntil(() => vm.cachedFavorites.length == 2);

      expect(service.resolveCalls, 2);
      final byId = {for (final item in vm.cachedFavorites) item.id: item};
      expect(byId['o1']!.media!.cacheKey, mediaKey('p1'));
      expect(byId['o2']!.media!.cacheKey, mediaKey('v2'));
    });

    test('when the server cannot be asked, what the device holds is used',
        () async {
      final service = FakeOwnerService(
        owners: {'o1': owner('o1')},
        resolveFails: true,
        cached: {
          'o1': [
            OfferMediaRef(
              mediaObjectId: 'p1',
              cacheKey: mediaKey('p1'),
              localFilePath: '/offer_media/p1.jpg',
            ),
          ],
        },
      );

      final vm = await load(metadata: ownerFavorites(['o1']), owners: service);

      expect(vm.cachedFavorites.single.media!.cacheKey, mediaKey('p1'));
    });

    test(
        'an Owner that cannot be resolved at all is still listed, without media',
        () async {
      final service = FakeOwnerService(
        owners: {'o1': owner('o1')},
        resolveFails: true,
      );

      final vm = await load(metadata: ownerFavorites(['o1']), owners: service);

      expect(vm.cachedFavorites.single.id, 'o1');
      expect(vm.cachedFavorites.single.media, isNull);
    });

    test('a backend with no media stage keeps the row\'s own URL', () async {
      final service = FakeOwnerService(
        owners: {
          'o1': owner('o1', mediaUrls: ['https://legacy.example/o1.jpg']),
        },
      );

      final vm = await load(metadata: ownerFavorites(['o1']), owners: service);

      expect(vm.cachedFavorites.single.media, isNull);
      expect(
          vm.cachedFavorites.single.imageUrl, 'https://legacy.example/o1.jpg');
    });

    test('an Offer whose first file is a video shows its first photo',
        () async {
      final cache = OfferMediaUrlCache.instance;
      addTearDown(cache.clear);
      cache.put(mediaKey('v1'), 'https://signed.example/v1',
          DateTime.now().add(const Duration(minutes: 10)),
          isVideo: true);
      cache.put(mediaKey('p1'), 'https://signed.example/p1',
          DateTime.now().add(const Duration(minutes: 10)));
      final withMedia = offer('offer-1').copyWith(
        mediaObjectIds: ['v1', 'p1'],
        mediaUrls: ['https://signed.example/v1', 'https://signed.example/p1'],
      );

      final vm = await load(
        metadata: {
          'offers': [
            FavoriteMetadata(
                itemId: 'offer-1',
                type: 'offers',
                addedAt: DateTime(2026, 1, 1)),
          ],
        },
        offers: {'offer-1': withMedia},
      );

      final item = vm.cachedFavorites.single;
      expect(item.media!.isVideo, isFalse);
      expect(item.media!.cacheKey, mediaKey('p1'));
      expect(item.imageUrl, isNull,
          reason: 'the first URL is the video; it must not reach the card');
    });
  });
}
