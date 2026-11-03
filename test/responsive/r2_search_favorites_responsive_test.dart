import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_card.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_data_source.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_engine.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search/search_fixtures.dart' as fixtures;
import 'r2_test_fakes.dart';
import 'responsive_harness.dart';

class _SearchSource implements SearchDataSource {
  _SearchSource(this.loader);

  final Future<SearchData> Function() loader;

  @override
  String? get currentUserId => 'responsive-user';

  @override
  Future<SearchData> load() => loader();
}

class _NoMediaSource implements SearchCardMediaSource {
  @override
  String? get accountId => null;

  @override
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId) => const [];

  @override
  Future<OfferMediaResolution?> resolve(
    CardMediaKind kind,
    String recordId,
    String accountId,
  ) async =>
      null;
}

SearchCardMediaResolver _noMedia() =>
    SearchCardMediaResolver(source: _NoMediaSource());

class _FavoritesService extends FavoriteService {
  _FavoritesService({
    this.metadata = const {},
    this.loader,
  });

  final Map<String, List<FavoriteMetadata>> metadata;
  final Future<Map<String, List<FavoriteMetadata>>> Function()? loader;

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> initializeCache({String? uidOverride}) async {}

  @override
  List<FavoriteItem> getCachedFavoritesSync() => const [];

  @override
  Future<Map<String, List<FavoriteMetadata>>>
      getAllFavoritesWithMetadata() async =>
          loader == null ? metadata : loader!();

  @override
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {}
}

class _OfferService extends OfferService {
  _OfferService(this.items);

  final Map<String, OfferModel> items;

  @override
  Future<OfferModel?> getOffer(String offerId) async => items[offerId];

  // Favorites reads its Offers together (P3.4).
  @override
  Future<List<OfferModel>> getOffersByIds(
    List<String> offerIds, {
    bool Function()? stop,
  }) async =>
      [
        for (final id in offerIds)
          if (items[id] case final OfferModel offer) offer,
      ];
}

OfferModel _longOffer(String id) => fixtures.offer(
      id: id,
      city: 'Dubai Marina and an intentionally long district name',
      location: 'A very long tower and street description for layout testing',
      minPrice: '123456789',
      maxPrice: '987654321',
      propertyType: 'commercial_property_with_a_long_name',
      notes: 'long searchable responsive content',
    );

Widget _screen(Widget child) => withR2ScreenProviders(
      Scaffold(resizeToAvoidBottomInset: false, body: child),
    );

void main() {
  setUpAll(prepareResponsiveAssets);

  group('Search production view', () {
    testWidgets('initial state on the smallest phone', (tester) async {
      final vm = SearchViewModel(
        dataSource: _SearchSource(() async => const SearchData()),
        engine: SearchEngine(),
        debounce: Duration.zero,
        dataChanges: const Stream<void>.empty(),
        cardMedia: _noMedia(),
      );
      addTearDown(vm.dispose);
      const scenario = ResponsiveCase(Size(280, 600));

      await pumpResponsive(
        tester,
        scenario,
        home: _screen(SearchView(viewModel: vm)),
      );

      expect(find.byType(TextField), findsOneWidget);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets(
        'keyboard, Arabic, enlarged text, submit and clear remain usable',
        (tester) async {
      final vm = SearchViewModel(
        dataSource: _SearchSource(() async => const SearchData()),
        engine: SearchEngine(),
        debounce: Duration.zero,
        dataChanges: const Stream<void>.empty(),
        cardMedia: _noMedia(),
      );
      addTearDown(vm.dispose);
      const scenario = ResponsiveCase(
        Size(320, 568),
        locale: Locale('ar'),
        dark: true,
        textScale: 1.6,
        keyboard: 240,
      );

      await pumpResponsive(
        tester,
        scenario,
        home: _screen(SearchView(viewModel: vm)),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'نتيجة غير موجودة');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expectNoLayoutException(tester, scenario);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.text('نتيجة غير موجودة'), findsNothing);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('loading and error states fit', (tester) async {
      final gate = Completer<SearchData>();
      final loading = SearchViewModel(
        dataSource: _SearchSource(() => gate.future),
        engine: SearchEngine(),
        debounce: Duration.zero,
        dataChanges: const Stream<void>.empty(),
        cardMedia: _noMedia(),
      )..submitQuery('Dubai');
      addTearDown(loading.dispose);
      const loadingCase = ResponsiveCase(
        Size(360, 640),
        dark: true,
        textScale: 2,
      );
      await pumpResponsive(
        tester,
        loadingCase,
        home: _screen(SearchView(viewModel: loading)),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expectNoLayoutException(tester, loadingCase);
      gate.complete(const SearchData());
      await tester.pumpAndSettle();

      final failed = SearchViewModel(
        dataSource: _SearchSource(() async => throw StateError('failure')),
        engine: SearchEngine(),
        debounce: Duration.zero,
        dataChanges: const Stream<void>.empty(),
        cardMedia: _noMedia(),
      )..submitQuery('Dubai');
      addTearDown(failed.dispose);
      const errorCase = ResponsiveCase(
        Size(430, 932),
        locale: Locale('ar'),
        dark: true,
        safeArea: EdgeInsets.only(top: 28, bottom: 34),
      );
      await pumpResponsive(
        tester,
        errorCase,
        home: _screen(SearchView(viewModel: failed)),
      );
      expect(find.byType(ElevatedButton), findsOneWidget);
      expectNoLayoutException(tester, errorCase);
    });

    for (final scenario in <ResponsiveCase>[
      const ResponsiveCase(Size(393, 852), textScale: 2),
      const ResponsiveCase(
        Size(640, 360),
        locale: Locale('ar'),
        dark: true,
        textScale: 2,
        safeArea: EdgeInsets.only(top: 20, bottom: 20),
      ),
      const ResponsiveCase(Size(800, 1280), dark: true),
    ]) {
      testWidgets('long populated results: $scenario', (tester) async {
        final vm = SearchViewModel(
          dataSource: _SearchSource(
            () async => SearchData(
              offers: [_longOffer('offer-1'), _longOffer('offer-2')],
            ),
          ),
          engine: SearchEngine(),
          debounce: Duration.zero,
          dataChanges: const Stream<void>.empty(),
          cardMedia: _noMedia(),
        )..submitQuery('responsive');
        addTearDown(vm.dispose);

        await pumpResponsive(
          tester,
          scenario,
          home: _screen(SearchView(viewModel: vm)),
        );

        if (find.byType(SearchResultCard).evaluate().isEmpty) {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
        }
        expect(find.byType(SearchResultCard), findsNWidgets(2));
        await tester.ensureVisible(find.byType(SearchResultCard).last);
        await tester.pumpAndSettle();
        expectNoLayoutException(tester, scenario);
      });
    }
  });

  group('Favorites production view', () {
    Future<void> pumpFavorites(
      WidgetTester tester,
      ResponsiveCase scenario,
      _FavoritesService favoriteService, {
      Map<String, OfferModel> offers = const {},
    }) async {
      final optimistic = OptimisticFavoritesService(
        favoriteService: QuietFavoriteService(),
      );
      final vm = FavoritesViewModel(
        favoriteService: favoriteService,
        offerService: _OfferService(offers),
      );
      addTearDown(vm.dispose);
      addTearDown(optimistic.dispose);

      await pumpResponsive(
        tester,
        scenario,
        home: withR2ScreenProviders(
          Scaffold(
            resizeToAvoidBottomInset: false,
            body: FavoritesView(viewModel: vm),
          ),
          favorites: optimistic,
        ),
      );
    }

    testWidgets('empty smallest phone', (tester) async {
      const scenario = ResponsiveCase(Size(280, 600));
      await pumpFavorites(tester, scenario, _FavoritesService());
      expect(find.byType(FavoritesView), findsOneWidget);
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('loading and error states fit enlarged Arabic', (tester) async {
      final gate = Completer<Map<String, List<FavoriteMetadata>>>();
      const loadingCase = ResponsiveCase(
        Size(320, 568),
        locale: Locale('ar'),
        textScale: 1.6,
      );
      await pumpFavorites(
        tester,
        loadingCase,
        _FavoritesService(loader: () => gate.future),
      );
      expectNoLayoutException(tester, loadingCase);
      gate.complete(const {});
      await tester.pumpAndSettle();

      const errorCase = ResponsiveCase(
        Size(360, 640),
        locale: Locale('ar'),
        dark: true,
        textScale: 2,
      );
      await pumpFavorites(
        tester,
        errorCase,
        _FavoritesService(loader: () async => throw StateError('failure')),
      );
      expect(find.byType(ElevatedButton), findsOneWidget);
      expectNoLayoutException(tester, errorCase);
    });

    for (final scenario in <ResponsiveCase>[
      const ResponsiveCase(Size(393, 852), textScale: 2),
      const ResponsiveCase(
        Size(640, 360),
        locale: Locale('ar'),
        dark: true,
        textScale: 2,
        safeArea: EdgeInsets.only(top: 20, bottom: 20),
      ),
      const ResponsiveCase(Size(800, 1280), dark: true),
    ]) {
      testWidgets('long populated favorites: $scenario', (tester) async {
        final now = DateTime(2026, 10, 23);
        final offer1 = _longOffer('favorite-1');
        final offer2 = _longOffer('favorite-2');
        final service = _FavoritesService(
          metadata: {
            'offers': [
              FavoriteMetadata(
                itemId: 'favorite-1',
                type: 'offers',
                addedAt: now,
              ),
              FavoriteMetadata(
                itemId: 'favorite-2',
                type: 'offers',
                addedAt: now.subtract(const Duration(hours: 1)),
              ),
            ],
          },
        );
        await pumpFavorites(
          tester,
          scenario,
          service,
          offers: {'favorite-1': offer1, 'favorite-2': offer2},
        );

        expect(find.byType(FavoriteCard), findsNWidgets(2));
        await tester.ensureVisible(find.byType(FavoriteCard).last);
        await tester.pumpAndSettle();
        expectNoLayoutException(tester, scenario);
      });
    }
  });
}
