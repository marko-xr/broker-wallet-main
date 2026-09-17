import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
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
}
