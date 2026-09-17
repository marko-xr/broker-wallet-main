import 'dart:async';

import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';

// -----------------------------------------------------------------------------
// Regression coverage for the Favorites stale-heart ordering fix.
//
// Root cause (established in a prior read-only audit): `toggleFavorite`
// (a mutation) and `initializeFavoriteStatus`/`updateLoadedFavorites`/
// `batchInitializeFavorites` (reads) all publish into the same shared,
// singleton `_optimisticState` map with no ordering relationship between
// them. An older read — dispatched before a removal, but resolving after it
// because its own server round trip happened to take longer — could
// silently overwrite the removal's correct result, because the only
// existing guard was an account-generation check, which says nothing about
// *item-level* ordering.
//
// This file drives `OptimisticFavoritesService`'s actual production methods
// (not a standalone version-counter helper) against a `_ControlledFavoriteService`
// fake whose async methods resolve only when the test explicitly completes
// them — this makes the interleaving deterministic instead of relying on
// real timing races. `OptimisticFavoritesService`'s optional `favoriteService`
// constructor parameter (added alongside this fix) is what makes this
// possible; it mirrors the same injectable-service pattern already used by
// `FavoritesViewModel`'s constructor.
// -----------------------------------------------------------------------------

class _ControlledFavoriteService extends FavoriteService {
  final Map<String, Completer<void>> _addGates = {};
  final Map<String, Completer<void>> _removeGates = {};
  final Map<String, Completer<bool>> _isFavoriteGates = {};
  final List<String> addCalls = [];
  final List<String> removeCalls = [];
  final List<String> isFavoriteCalls = [];

  String _key(String itemId, String type) => '$type-$itemId';

  Completer<void> addGate(String itemId, String type) =>
      _addGates.putIfAbsent(_key(itemId, type), () => Completer<void>());

  Completer<void> removeGate(String itemId, String type) =>
      _removeGates.putIfAbsent(_key(itemId, type), () => Completer<void>());

  /// Each call to `isFavorite` for a given key gets its *own* completer, so
  /// two overlapping reads for the same key can be resolved independently
  /// and in either order. `callIndex` is 1-based, in dispatch order.
  Completer<bool> isFavoriteGate(String itemId, String type, int callIndex) =>
      _isFavoriteGates.putIfAbsent(
        '${_key(itemId, type)}#$callIndex',
        () => Completer<bool>(),
      );

  @override
  Future<void> addToFavorites(String itemId, String type) {
    addCalls.add(_key(itemId, type));
    return addGate(itemId, type).future;
  }

  @override
  Future<void> removeFromFavorites(String itemId, String type) {
    removeCalls.add(_key(itemId, type));
    return removeGate(itemId, type).future;
  }

  @override
  Future<bool> isFavorite(String itemId, String type) {
    isFavoriteCalls.add(_key(itemId, type));
    final callIndex =
        isFavoriteCalls.where((k) => k == _key(itemId, type)).length;
    return isFavoriteGate(itemId, type, callIndex).future;
  }
}

void main() {
  late _ControlledFavoriteService fake;
  late OptimisticFavoritesService service;

  setUp(() {
    fake = _ControlledFavoriteService();
    service = OptimisticFavoritesService(favoriteService: fake);
  });

  group('Read vs. mutation ordering (per-key)', () {
    test(
        '1. an older status read resolving after a successful Remove does '
        'not overwrite it: final heart is false', () async {
      // Seed: item currently favorited, via a completed read — matching how
      // the app would ordinarily have arrived at "currently favorited".
      final seedGate = fake.isFavoriteGate('X', 'brokers', 1);
      final seedFuture = service.initializeFavoriteStatus('X', 'brokers');
      seedGate.complete(true);
      await seedFuture;
      expect(service.isFavorite('X', 'brokers'), isTrue);

      // A read starts (e.g. another widget showing the same item mounts)
      // and its query is dispatched but not yet resolved.
      final staleReadFuture = service.initializeFavoriteStatus('X', 'brokers');

      // The user removes the item via a different widget. toggleFavorite's
      // own removeFromFavorites call is also gated, so we can complete it
      // whenever we choose.
      final toggleFuture = service.toggleFavorite('X', 'brokers');
      fake.removeGate('X', 'brokers').complete();
      final toggleResult = await toggleFuture;
      expect(toggleResult, isFalse);
      expect(service.isFavorite('X', 'brokers'), isFalse,
          reason: 'the removal must be reflected immediately');

      // The earlier, still-pending read now resolves with stale
      // pre-removal server truth.
      fake.isFavoriteGate('X', 'brokers', 2).complete(true);
      await staleReadFuture;

      expect(
        service.isFavorite('X', 'brokers'),
        isFalse,
        reason: 'a stale read must never resurrect a confirmed removal',
      );
    });

    test(
        '2. an older status read resolving after a successful Add does not '
        'overwrite it: final heart is true', () async {
      // Start unfavorited (default).
      expect(service.isFavorite('Y', 'offices'), isFalse);

      final staleReadFuture = service.initializeFavoriteStatus('Y', 'offices');

      final toggleFuture = service.toggleFavorite('Y', 'offices');
      fake.addGate('Y', 'offices').complete();
      final toggleResult = await toggleFuture;
      expect(toggleResult, isTrue);
      expect(service.isFavorite('Y', 'offices'), isTrue);

      // Stale read reports "not favorited" (pre-add truth).
      fake.isFavoriteGate('Y', 'offices', 1).complete(false);
      await staleReadFuture;

      expect(
        service.isFavorite('Y', 'offices'),
        isTrue,
        reason: 'a stale read must never revert a confirmed addition',
      );
    });

    test(
        '3. a read that starts while a Remove is already pending cannot '
        'supersede the successful Remove, even though its own baseline '
        'already "includes" that mutation', () async {
      // Seed favorited.
      final seedFuture = service.initializeFavoriteStatus('Z', 'watchmen');
      fake.isFavoriteGate('Z', 'watchmen', 1).complete(true);
      await seedFuture;
      expect(service.isFavorite('Z', 'watchmen'), isTrue);

      // The removal starts FIRST this time (unlike test 1, where the read
      // started first) — the read is dispatched while the removal is
      // already in flight.
      final toggleFuture = service.toggleFavorite('Z', 'watchmen');
      expect(service.isLoading('Z', 'watchmen'), isTrue);

      final readFuture = service.initializeFavoriteStatus('Z', 'watchmen');

      fake.removeGate('Z', 'watchmen').complete();
      await toggleFuture;
      expect(service.isFavorite('Z', 'watchmen'), isFalse);

      // The read, dispatched while the removal was pending, now resolves
      // with the pre-removal server value.
      fake.isFavoriteGate('Z', 'watchmen', 2).complete(true);
      await readFuture;

      expect(
        service.isFavorite('Z', 'watchmen'),
        isFalse,
        reason: 'a read launched during a pending mutation must never '
            'invalidate that mutation\'s successful result',
      );
    });
  });

  group('Overlapping reads', () {
    test(
        '4. two overlapping reads for the same key finishing in reverse '
        'order converge on the later-dispatched read\'s result, not the '
        'earlier one\'s', () async {
      final firstRead = service.initializeFavoriteStatus('W', 'requests');
      final secondRead = service.initializeFavoriteStatus('W', 'requests');

      // Second (newer) read resolves first, with the current truth: true.
      fake.isFavoriteGate('W', 'requests', 2).complete(true);
      await secondRead;
      expect(service.isFavorite('W', 'requests'), isTrue);

      // First (older) read resolves second, with stale data: false.
      fake.isFavoriteGate('W', 'requests', 1).complete(false);
      await firstRead;

      expect(
        service.isFavorite('W', 'requests'),
        isTrue,
        reason: 'the older read must not overwrite the newer, already-'
            'applied read\'s result merely because it finishes later',
      );
    });
  });

  group('Failure handling', () {
    test(
        '5. a failed mutation rolls back to the pre-toggle state and never '
        'reports false success', () async {
      expect(service.isFavorite('F', 'offers'), isFalse);

      final toggleFuture = service.toggleFavorite('F', 'offers');
      expect(service.isFavorite('F', 'offers'), isTrue,
          reason: 'optimistic update is immediate');

      fake.addGate('F', 'offers').completeError(Exception('network error'));

      await expectLater(toggleFuture, throwsA(isA<Exception>()));
      expect(service.isFavorite('F', 'offers'), isFalse,
          reason: 'a failed add must roll back to unfavorited');
      expect(service.isLoading('F', 'offers'), isFalse);
    });
  });

  group('Account-generation safety', () {
    test(
        '6. a status read that resolves after an account transition is '
        'discarded, unrelated to the item-level ordering fix', () async {
      final readFuture = service.initializeFavoriteStatus('G', 'owners');
      await FavoriteService.invalidateForAccountChange();
      fake.isFavoriteGate('G', 'owners', 1).complete(true);
      await readFuture;

      expect(
        service.isFavorite('G', 'owners'),
        isFalse,
        reason: 'a completion for a previous account generation must never '
            'publish into the current one',
      );
    });
  });

  group('Key independence', () {
    test(
        '7. concurrent operations on different keys do not affect each '
        'other', () async {
      final removeA = service.toggleFavorite('A', 'brokers');
      final addB = service.toggleFavorite('B', 'brokers');

      // Complete B's add first, then A's (seed A as favorited first via a
      // direct state assumption is unnecessary — starting state is false
      // for both, so "toggle" on A is actually an add too; that's fine,
      // independence is what is under test, not the specific transition).
      fake.addGate('B', 'brokers').complete();
      fake.addGate('A', 'brokers').complete();

      await Future.wait([removeA, addB]);

      expect(service.isFavorite('A', 'brokers'), isTrue);
      expect(service.isFavorite('B', 'brokers'), isTrue);
    });
  });

  group('Full-list refresh safety (updateLoadedFavorites)', () {
    test(
        'a key with a removal already pending at snapshot time is skipped, '
        'while an unrelated key in the same batch is still applied', () async {
      // Seed P as currently favorited.
      final seedFuture = service.initializeFavoriteStatus('P', 'offices');
      fake.isFavoriteGate('P', 'offices', 1).complete(true);
      await seedFuture;
      expect(service.isFavorite('P', 'offices'), isTrue);

      // Start removing P, but do not let the backend call complete yet.
      final togglePending = service.toggleFavorite('P', 'offices');
      expect(service.isLoading('P', 'offices'), isTrue);
      expect(service.isFavorite('P', 'offices'), isFalse,
          reason: 'the optimistic remove already flipped this locally');

      // The caller (FavoritesViewModel) captures its snapshot now, exactly
      // as it would immediately before dispatching an authoritative fetch.
      final snapshot = service.snapshotMutationVersions();
      expect(snapshot.pendingKeys, contains('offices_P'));

      // The authoritative list this stale fetch eventually returns still
      // lists P as favorited (fetched before the removal committed),
      // alongside an unrelated item Q.
      service.updateLoadedFavorites(
        {
          'offices': ['P', 'Q'],
        },
        expectedGeneration: FavoriteService.currentAccountGeneration,
        mutationSnapshot: snapshot,
      );

      expect(
        service.isFavorite('P', 'offices'),
        isFalse,
        reason: 'P had a removal pending at snapshot time; the stale bulk '
            'fetch must not resurrect it as favorited',
      );
      expect(
        service.isFavorite('Q', 'offices'),
        isTrue,
        reason: 'Q was not touched by any mutation and should still be '
            'applied normally',
      );

      // Let the pending removal actually resolve, for test hygiene.
      fake.removeGate('P', 'offices').complete();
      await togglePending;
      expect(service.isFavorite('P', 'offices'), isFalse);
    });

    test(
        'a key whose mutation version changed after the snapshot was taken '
        'is also skipped', () async {
      final snapshot = service.snapshotMutationVersions();
      expect(snapshot.pendingKeys, isEmpty);

      // A mutation starts and completes entirely *after* the snapshot was
      // taken but *before* updateLoadedFavorites is called.
      final toggleFuture = service.toggleFavorite('R', 'watchmen');
      fake.addGate('R', 'watchmen').complete();
      await toggleFuture;
      expect(service.isFavorite('R', 'watchmen'), isTrue);

      // A stale fetch, dispatched before that mutation, now tries to apply
      // its (outdated) view that R was not favorited — i.e. it simply omits
      // R from the loaded list.
      service.updateLoadedFavorites(
        {'watchmen': <String>[]},
        expectedGeneration: FavoriteService.currentAccountGeneration,
        mutationSnapshot: snapshot,
      );

      expect(
        service.isFavorite('R', 'watchmen'),
        isTrue,
        reason: 'updateLoadedFavorites only ever adds true entries for '
            'items present in its list; R\'s true value set by the more '
            'recent mutation must remain untouched',
      );
    });
  });
}
