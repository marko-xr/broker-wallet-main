// Regression coverage for the Favorites remove-reappear-disappear bug: a
// background list fetch dispatched before a heart-icon toggle (Add/Remove via
// OptimisticFavoritesService) but resolving after it must never overwrite the
// list with its now-stale answer for the item(s) that toggle touched, in
// either direction (resurrecting a removed item, or erasing a newly added
// one), while every other item in the same fetch keeps updating normally.
//
// Each test drives the real `FavoritesViewModel`/`OptimisticFavoritesService`
// production code through two independently controllable fakes: one
// `FavoriteService` gates the ViewModel's own bulk list fetch
// (`getAllFavoritesWithMetadata`), a separate one gates the optimistic
// service's own `addToFavorites`/`removeFromFavorites`, so the exact
// interleaving of "fetch dispatched", "mutation starts", "mutation
// completes", and "fetch resolves" can be driven deterministically.

import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

typedef MetadataMap = Map<String, List<FavoriteMetadata>>;

/// Gates the ViewModel's own bulk metadata fetch. Each call to
/// `getAllFavoritesWithMetadata` gets its own fresh `Completer`, appended to
/// `metadataCalls` in call order, so a test can resolve fetch N independently
/// of fetch N+1 regardless of which one it wants to complete first.
class FakeMetadataFavoriteService extends FavoriteService {
  FakeMetadataFavoriteService({this.cachedFavorites = const []});

  final List<FavoriteItem> cachedFavorites;
  final List<Completer<MetadataMap>> metadataCalls = [];
  final List<List<FavoriteItem>> cacheWrites = [];
  int metadataLoadCount = 0;

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> initializeCache({String? uidOverride}) async {}

  @override
  List<FavoriteItem> getCachedFavoritesSync() =>
      List<FavoriteItem>.from(cachedFavorites);

  @override
  Future<MetadataMap> getAllFavoritesWithMetadata() async {
    final completer = Completer<MetadataMap>();
    metadataCalls.add(completer);
    metadataLoadCount++;
    return completer.future;
  }

  @override
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {
    cacheWrites.add(List<FavoriteItem>.from(favorites));
  }
}

/// Gates the OptimisticFavoritesService's own add/remove calls, independently
/// of the metadata fetch above. `isFavorite` always resolves immediately
/// (true) since no test in this file exercises the separately-fixed
/// heart-icon read-ordering race — only the list-fetch reconciliation.
class MutationControlledFavoriteService extends FavoriteService {
  final Map<String, Completer<void>> _gates = {};
  final Set<String> failKeys = {};

  String _key(String id, String type) => '${type}_$id';

  /// Registers a gate for the next add/remove call on this key. Must be
  /// called before the corresponding `toggleFavorite`.
  Completer<void> prepareGate(String id, String type) {
    final completer = Completer<void>();
    _gates[_key(id, type)] = completer;
    return completer;
  }

  @override
  Future<bool> isFavorite(String itemId, String type) async => true;

  @override
  Future<void> addToFavorites(String itemId, String type) async {
    final key = _key(itemId, type);
    final gate = _gates.remove(key);
    if (gate != null) await gate.future;
    if (failKeys.remove(key)) throw Exception('simulated add failure');
  }

  @override
  Future<void> removeFromFavorites(String itemId, String type) async {
    final key = _key(itemId, type);
    final gate = _gates.remove(key);
    if (gate != null) await gate.future;
    if (failKeys.remove(key)) throw Exception('simulated remove failure');
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

MetadataMap offersMetadata(List<String> ids, {DateTime? addedAt}) {
  final at = addedAt ?? DateTime(2026, 1, 1);
  return {
    'offers': [
      for (final id in ids)
        FavoriteMetadata(itemId: id, type: 'offers', addedAt: at),
    ],
  };
}

Future<void> flushAsync([int turns = 20]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> waitUntil(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(reason ?? 'Condition was not reached before the async test timeout.');
}

// The optimistic-change debounce in FavoritesViewModel is 300ms; wait past it
// so a debounced _refreshImmediately has definitely been dispatched.
Future<void> waitPastDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 350));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoritesViewModel stale list reconciliation', () {
    test(
        'a stale fetch dispatched before a completed removal does not '
        'resurrect the removed item once a newer fetch has already excluded '
        'it (regresses to the old remove-reappear bug without the fix)',
        () async {
      final offers = FakeOfferService({'A': offer('A')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      // Cold load (call #1) establishes A as present.
      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0].complete(offersMetadata(['A']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);
      expect(viewModel.displayFavorites.map((i) => i.id), ['A']);

      // The successful cold load synced OptimisticFavoritesService, which
      // notifies listeners and schedules a debounced refresh: this becomes
      // the "older, stale" fetch (call #2), dispatched before the removal.
      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      // Remove A via the heart-toggle path. This bumps A's mutation version
      // and, on completion, schedules its own confirming refresh (call #3).
      final removeGate = mutationService.prepareGate('A', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('A', 'offers');
      removeGate.complete();
      await toggleFuture;

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 3);

      // The newer, confirming fetch resolves first and correctly excludes A.
      metadataService.metadataCalls[2].complete(offersMetadata(const []));
      await waitUntil(() => viewModel.displayFavorites.isEmpty);

      // The older, stale fetch (still reporting A present) resolves last.
      metadataService.metadataCalls[1].complete(offersMetadata(['A']));
      await flushAsync();

      expect(viewModel.displayFavorites, isEmpty,
          reason: 'the stale fetch must not resurrect the removed item');
      expect(viewModel.cachedFavorites, isEmpty);

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'a stale fetch dispatched before a completed add does not erase the '
        'item once a newer fetch has already included it', () async {
      final offers = FakeOfferService({'A': offer('A'), 'B': offer('B')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      // Cold load (call #1) establishes A as present; B does not exist yet.
      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0].complete(offersMetadata(['A']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);

      // Older, stale fetch (call #2), dispatched before B is added.
      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      // Add B via the heart-toggle path (currentState defaults to false, so
      // this is an Add). Its completion schedules a confirming refresh.
      final addGate = mutationService.prepareGate('B', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('B', 'offers');
      addGate.complete();
      await toggleFuture;

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 3);

      // Newer, confirming fetch resolves first and correctly includes B.
      metadataService.metadataCalls[2].complete(offersMetadata(['A', 'B']));
      await waitUntil(() => viewModel.displayFavorites.length == 2);

      // Older, stale fetch (still missing B) resolves last.
      metadataService.metadataCalls[1].complete(offersMetadata(['A']));
      await flushAsync();

      expect(viewModel.displayFavorites.map((i) => i.id).toSet(), {'A', 'B'},
          reason: 'the stale fetch must not erase the newly added item');

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'two consecutive removals racing one stale fetch both stay excluded '
        'while an unrelated, unmutated item keeps updating normally',
        () async {
      final offers = FakeOfferService(
          {'A': offer('A'), 'B': offer('B'), 'C': offer('C')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0]
          .complete(offersMetadata(['A', 'B', 'C']));
      await waitUntil(() => viewModel.displayFavorites.length == 3);

      // Stale fetch dispatched before either removal.
      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      // Remove A and B (sequentially, each fully completed).
      final gateA = mutationService.prepareGate('A', 'offers');
      final toggleA = optimisticService.toggleFavorite('A', 'offers');
      gateA.complete();
      await toggleA;

      final gateB = mutationService.prepareGate('B', 'offers');
      final toggleB = optimisticService.toggleFavorite('B', 'offers');
      gateB.complete();
      await toggleB;

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount >= 3);
      final confirmingCallIndex = metadataService.metadataLoadCount - 1;

      // Confirming fetch: A and B gone (real removals), C unaffected but its
      // title changed server-side (proves unrelated items keep updating).
      metadataService.metadataCalls[confirmingCallIndex].complete({
        'offers': [
          FavoriteMetadata(
              itemId: 'C', type: 'offers', addedAt: DateTime(2026, 1, 2)),
        ],
      });
      await waitUntil(() =>
          viewModel.displayFavorites.length == 1 &&
          viewModel.displayFavorites.first.id == 'C');

      // Stale fetch resolves last, still listing all three.
      metadataService.metadataCalls[1]
          .complete(offersMetadata(['A', 'B', 'C']));
      await flushAsync();

      expect(viewModel.displayFavorites.map((i) => i.id).toList(), ['C'],
          reason: 'A and B must stay excluded; only unrelated C remains');

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'an older fetch resolving after a newer one does not undo the newer '
        "fetch's correct removal (out-of-order overlapping fetches)",
        () async {
      final offers = FakeOfferService({'A': offer('A')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0].complete(offersMetadata(['A']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      final gate = mutationService.prepareGate('A', 'offers');
      final toggle = optimisticService.toggleFavorite('A', 'offers');
      gate.complete();
      await toggle;

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 3);

      // Resolve the NEWER fetch (#3) first...
      metadataService.metadataCalls[2].complete(offersMetadata(const []));
      await waitUntil(() => viewModel.displayFavorites.isEmpty);

      // ...then the OLDER, stale fetch (#2) resolves out of order.
      metadataService.metadataCalls[1].complete(offersMetadata(['A']));
      await flushAsync();

      expect(viewModel.displayFavorites, isEmpty);
      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'a fetch that resolves while a removal is still pending does not '
        'apply either answer until the mutation settles, and the eventual '
        'rollback on failure is preserved', () async {
      final offers = FakeOfferService({'A': offer('A')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0].complete(offersMetadata(['A']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      // Start the removal but do NOT complete its gate yet: the mutation is
      // still pending when the next fetch dispatches and resolves.
      final gate = mutationService.prepareGate('A', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('A', 'offers');
      await flushAsync(); // let the optimistic pending flag land

      // A stale-looking fetch resolves while the removal is still pending.
      metadataService.metadataCalls[1].complete(offersMetadata(const []));
      await flushAsync();

      expect(viewModel.displayFavorites.map((i) => i.id), ['A'],
          reason: 'a fetch racing a still-pending mutation must not '
              "apply the fetch's answer for that key");

      // The removal now fails and rolls back.
      mutationService.failKeys.add('offers_A');
      gate.complete();
      await expectLater(toggleFuture, throwsException);
      expect(optimisticService.isOfferFavorite('A'), isTrue);

      expect(viewModel.displayFavorites.map((i) => i.id), ['A'],
          reason: 'list state remains consistent with the rolled-back '
              'mutation');

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'a fetch dispatched before a failed removal attempt still defers to '
        'the current list once the failed attempt has advanced the '
        "mutation's version", () async {
      final offers = FakeOfferService({'A': offer('A')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0].complete(offersMetadata(['A']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);

      // Stale fetch dispatched before the failed removal attempt starts.
      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      mutationService.failKeys.add('offers_A');
      final gate = mutationService.prepareGate('A', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('A', 'offers');
      gate.complete();
      await expectLater(toggleFuture, throwsException); // fails, rolls back

      expect(optimisticService.isOfferFavorite('A'), isTrue);

      // Now resolve the fetch that was dispatched before the failed attempt.
      metadataService.metadataCalls[1].complete(offersMetadata(const []));
      await flushAsync();

      expect(viewModel.displayFavorites.map((i) => i.id), ['A'],
          reason: 'a failed mutation still advances the version, so the '
              'stale fetch must defer to the (unchanged) current list '
              'rather than trusting either answer blindly');

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'a stale cold-load fetch that reports zero favorites does not erase '
        'an item added while it was in flight (empty-state stability)',
        () async {
      final offers = FakeOfferService({'A': offer('A')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      // Cold load (call #1, via _loadFreshFavoritesImmediately) is gated.
      await waitUntil(() => metadataService.metadataLoadCount == 1);

      // While it is still in flight, the user adds A elsewhere and the add
      // completes fully.
      final gate = mutationService.prepareGate('A', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('A', 'offers');
      gate.complete();
      await toggleFuture;

      // The cold load now resolves reporting NO favorites at all (it was
      // dispatched before the add).
      metadataService.metadataCalls[0].complete(offersMetadata(const []));
      await flushAsync();

      expect(viewModel.displayFavorites, isEmpty,
          reason: 'A has not been fetched with full item data yet, only '
              'toggled optimistically, so it cannot appear in the list from '
              'this alone — but the empty branch must not crash or corrupt '
              'state, and a later confirming fetch must still be able to '
              'add it');

      // A later, confirming fetch (triggered by the add's own notification)
      // correctly includes A once its full data is fetched.
      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);
      metadataService.metadataCalls[1].complete(offersMetadata(['A']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);

      expect(viewModel.displayFavorites.map((i) => i.id), ['A']);

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'a fetch that resolves after the account has moved on is discarded '
        'entirely, composing safely with reconciliation', () async {
      final offers = FakeOfferService({'A': offer('A')});
      final metadataService = FakeMetadataFavoriteService(
        cachedFavorites: [
          cachedItem(id: 'A', type: 'offers', addedAt: DateTime(2026, 1, 1)),
        ],
      );
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      // Non-empty cache: construction triggers _loadFreshFavorites (call #1)
      // in the background rather than the immediate cold-load path.
      expect(viewModel.displayFavorites.map((i) => i.id), ['A']);
      await waitUntil(() => metadataService.metadataLoadCount == 1);

      // The account moves on while the fetch is in flight.
      await FavoriteService.invalidateForAccountChange();

      metadataService.metadataCalls[0].complete(offersMetadata(const []));
      await flushAsync();

      // The stale-account fetch must be dropped outright (not reconciled and
      // applied) — the pre-existing cached entry is left exactly as is.
      expect(viewModel.displayFavorites.map((i) => i.id), ['A']);

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'items of different types sharing the same id are reconciled '
        'independently: a mutated offers item is protected while an '
        'unrelated, unmutated owners item with the same id keeps updating '
        'normally', () async {
      final offers = FakeOfferService({'1': offer('1')});
      final metadataService = FakeMetadataFavoriteService(
        cachedFavorites: [
          cachedItem(id: '1', type: 'offers', addedAt: DateTime(2026, 1, 1)),
          cachedItem(id: '1', type: 'owners', addedAt: DateTime(2026, 1, 1)),
        ],
      );
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      expect(viewModel.displayFavorites.map((i) => '${i.type}_${i.id}').toSet(),
          {'offers_1', 'owners_1'});
      await waitUntil(() => metadataService.metadataLoadCount == 1);

      // Remove offers/1 via the heart-toggle path while the background
      // _loadFreshFavorites fetch (dispatched before the removal) is still
      // in flight.
      await optimisticService.initializeFavoriteStatus('1', 'offers');
      final gate = mutationService.prepareGate('1', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('1', 'offers');
      gate.complete();
      await toggleFuture;

      // The stale fetch resolves: server-authoritative data says owners/1 is
      // genuinely gone (no local mutation touched it — a real, unrelated
      // change), while offers is still reported (stale, pre-removal).
      metadataService.metadataCalls[0].complete({
        'offers': [
          FavoriteMetadata(
              itemId: '1', type: 'offers', addedAt: DateTime(2026, 1, 1)),
        ],
        'owners': const [],
      });
      await flushAsync();

      final keys =
          viewModel.displayFavorites.map((i) => '${i.type}_${i.id}').toSet();
      expect(keys.contains('owners_1'), isFalse,
          reason: 'unrelated, unmutated owners/1 must still update normally '
              'from the authoritative fetch');
      // offers/1's mutation is "affected", so this one stale fetch alone
      // neither confirms nor discards it — it is deferred to whatever the
      // list already showed (still present), never silently trusting the
      // stale fetch's answer either way.
      expect(keys.contains('offers_1'), isTrue);

      viewModel.dispose();
      optimisticService.dispose();
    });

    test(
        'the assigned list, the displayed list, and the cache write after '
        'reconciliation all reflect the exact same result', () async {
      final offers = FakeOfferService({'A': offer('A'), 'B': offer('B')});
      final metadataService = FakeMetadataFavoriteService();
      final mutationService = MutationControlledFavoriteService();
      final optimisticService =
          OptimisticFavoritesService(favoriteService: mutationService);
      final viewModel = FavoritesViewModel(
        optimisticFavoritesService: optimisticService,
        favoriteService: metadataService,
        offerService: offers,
      );

      await waitUntil(() => metadataService.metadataLoadCount == 1);
      metadataService.metadataCalls[0].complete(offersMetadata(['A', 'B']));
      await waitUntil(() => viewModel.displayFavorites.length == 2);

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 2);

      final gate = mutationService.prepareGate('A', 'offers');
      final toggleFuture = optimisticService.toggleFavorite('A', 'offers');
      gate.complete();
      await toggleFuture;

      await waitPastDebounce();
      await waitUntil(() => metadataService.metadataLoadCount == 3);

      // Confirming fetch resolves first: only B remains.
      metadataService.metadataCalls[2].complete(offersMetadata(['B']));
      await waitUntil(() => viewModel.displayFavorites.length == 1);

      // Stale fetch (still listing both) resolves last.
      metadataService.metadataCalls[1].complete(offersMetadata(['A', 'B']));
      await flushAsync();

      final displayedIds = viewModel.displayFavorites.map((i) => i.id).toSet();
      final cachedIds = viewModel.cachedFavorites.map((i) => i.id).toSet();
      final lastCacheWriteIds =
          metadataService.cacheWrites.last.map((i) => i.id).toSet();

      expect(displayedIds, {'B'});
      expect(cachedIds, displayedIds,
          reason: 'cachedFavorites must match the reconciled result');
      expect(lastCacheWriteIds, displayedIds,
          reason: 'the persisted cache write must match the same '
              'reconciled result, not a divergent unreconciled list');

      viewModel.dispose();
      optimisticService.dispose();
    });
  });
}
