import 'dart:io';

import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// -----------------------------------------------------------------------------
// Regression coverage for the Favorites account-isolation fix.
//
// This exercises the real `FavoriteService`/Hive layer against a temporary,
// isolated Hive directory (never the app's real boxes) — the same
// `CachedFavoriteItem` model and account-scoped box naming
// (`FavoriteService.boxNameForUid`) production code uses.
//
// Design under test: the on-disk cache is namespaced per canonical Supabase
// uid (one Hive box per account) rather than a single shared box guarded by
// a separately persisted "owner" marker. An earlier design used exactly that
// marker approach and was rejected during review: Hive and SharedPreferences
// are two independent, non-atomically-durable storage systems, so a hard
// process kill could let one account's Hive write commit while the other
// store still named a previous account — a real cross-account read became
// possible on the next launch. Per-account boxes remove the shared mutable
// state a marker would need to stay in sync with: there is nothing left that
// can point at the wrong account's data, because each account's data lives
// under a name only that account's own uid produces.
//
// `initializeCache(uidOverride: ...)` is a test-only injection point on
// `FavoriteService` (mirrors the existing injectable-service pattern already
// used by `FavoritesViewModel`'s constructor) — it exists because
// `FavoriteService._activeUserId` normally resolves through the
// `RepositoryProvider` singleton, which requires a fully initialized
// Supabase bootstrap with no other test seam. Production callers never pass
// it.
//
// What this file does NOT cover, and why: `OptimisticFavoritesService`'s own
// generation guards (`toggleFavorite`, `initializeFavoriteStatus`,
// `updateLoadedFavorites`) and its `syncAccountGeneration()` clearing cannot
// be driven under controlled timing here for the same `RepositoryProvider`
// reason, and the `main.dart` `ChangeNotifierProxyProvider` wiring that
// calls `syncAccountGeneration()` cannot be exercised without a widget host.
// Both are verified by direct source inspection only; see the checkpoint
// report.
// -----------------------------------------------------------------------------

FavoriteItem _item(String id, {String type = 'brokers'}) => FavoriteItem(
      id: id,
      type: type,
      title: 'title-$id',
      subtitle: 'subtitle-$id',
      addedAt: DateTime(2026, 1, 1),
    );

const _uidA = '5ec0de00-0000-4000-8000-00000000000a';
const _uidB = '5ec0de00-0000-4000-8000-00000000000b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('favorites_isolation_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(CachedFavoriteItemAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDown(() async {
    for (final uid in [_uidA, _uidB]) {
      final name = FavoriteService.boxNameForUid(uid);
      if (Hive.isBoxOpen(name)) {
        await Hive.box<CachedFavoriteItem>(name).clear();
      }
    }
  });

  group('Account-scoped box naming', () {
    test('different uids produce different, non-overlapping box names', () {
      expect(FavoriteService.boxNameForUid(_uidA),
          isNot(FavoriteService.boxNameForUid(_uidB)));
      expect(FavoriteService.boxNameForUid(_uidA),
          FavoriteService.boxNameForUid(_uidA));
    });

    test('the legacy fixed box name is never produced by boxNameForUid', () {
      expect(FavoriteService.boxNameForUid(_uidA),
          isNot(FavoriteService.legacyBoxName));
    });
  });

  group('Cross-account read safety (simulates process restart)', () {
    test(
        'account B never sees account A\'s cached favorites, even reading '
        'through a brand-new FavoriteService instance (as a fresh app '
        'process would)', () async {
      final serviceA = FavoriteService()..debugActiveUserIdOverride = _uidA;
      await serviceA.initializeCache(uidOverride: _uidA);
      await serviceA.cacheFavorites(
        [_item('a-broker')],
        expectedGeneration: FavoriteService.currentAccountGeneration,
      );
      expect(serviceA.getCachedFavoritesSync(), hasLength(1));

      // A brand-new instance, as a fresh process/restart would construct,
      // now resolving as a *different* account.
      final serviceB = FavoriteService()..debugActiveUserIdOverride = _uidB;
      await serviceB.initializeCache(uidOverride: _uidB);

      expect(
        serviceB.getCachedFavoritesSync(),
        isEmpty,
        reason: 'B must never read A\'s box, structurally — there is no '
            'name B\'s own initialization could ever produce that points '
            'at A\'s data',
      );
    });

    test(
        'the same account restarting (same uid, new instance) keeps its own '
        'warm cache — this is not weakened by account isolation', () async {
      final first = FavoriteService()..debugActiveUserIdOverride = _uidA;
      await first.initializeCache(uidOverride: _uidA);
      await first.cacheFavorites(
        [_item('persisted-broker')],
        expectedGeneration: FavoriteService.currentAccountGeneration,
      );

      // Simulates a cold restart under the same account: a fresh instance,
      // re-resolving the same uid.
      final restarted = FavoriteService()..debugActiveUserIdOverride = _uidA;
      await restarted.initializeCache(uidOverride: _uidA);

      expect(restarted.getCachedFavoritesSync(), hasLength(1));
      expect(
        restarted.getCachedFavoritesSync().single.id,
        'persisted-broker',
      );
    });

    test(
        'a service never initialized for any uid (e.g. read attempted '
        'before initializeCache resolves) reports no cache rather than an '
        'error', () {
      final service = FavoriteService();
      expect(service.getCachedFavoritesSync(), isEmpty);
    });
  });

  group('In-process stale-write protection (account-generation counter)', () {
    test(
        'a fetch that captured its generation before a transition cannot '
        'write its result after the transition (simulates: account A '
        'starts a refresh, signs out mid-fetch, its result lands late)',
        () async {
      final service = FavoriteService()..debugActiveUserIdOverride = _uidA;
      await service.initializeCache(uidOverride: _uidA);

      // Account A's in-flight fetch captures the generation at fetch-start,
      // exactly as FavoritesViewModel does via `_creationGeneration`.
      final generationWhenFetchStarted =
          FavoriteService.currentAccountGeneration;

      // Account A signs out (or a different account signs in) while that
      // fetch is still running — this is what
      // `AuthViewModel._handleSessionIdentity` now does.
      await FavoriteService.invalidateForAccountChange();

      // Account A's fetch finally resolves and tries to cache its (stale)
      // result, passing the generation it captured before the transition.
      await service.cacheFavorites(
        [_item('stale-from-account-a')],
        expectedGeneration: generationWhenFetchStarted,
      );

      expect(
        service.getCachedFavoritesSync(),
        isEmpty,
        reason: 'a stale write must never land, even into its own '
            'account\'s box',
      );
    });

    test(
        'a fetch that captured the current generation writes normally '
        '(no false positive when nothing changed)', () async {
      final service = FavoriteService()..debugActiveUserIdOverride = _uidA;
      await service.initializeCache(uidOverride: _uidA);

      final generation = FavoriteService.currentAccountGeneration;
      await service.cacheFavorites(
        [_item('still-current')],
        expectedGeneration: generation,
      );

      expect(service.getCachedFavoritesSync(), hasLength(1));
      expect(service.getCachedFavoritesSync().single.id, 'still-current');
    });

    test('invalidateForAccountChange is a monotonic counter', () async {
      final before = FavoriteService.currentAccountGeneration;
      await FavoriteService.invalidateForAccountChange();
      await FavoriteService.invalidateForAccountChange();
      expect(FavoriteService.currentAccountGeneration, before + 2);
    });
  });

  group('Stale initializeCache completion cannot publish active references',
      () {
    test(
        'an account transition while Hive.openBox is still in flight leaves '
        'the completion without an active cache reference, not just a '
        'later read-time rejection', () async {
      final service = FavoriteService()..debugActiveUserIdOverride = _uidA;

      // Deliberately not awaited yet: the transition below races against
      // Hive.openBox actually resolving, exercising the post-await guard
      // inside initializeCache itself rather than only the separate,
      // later `_hasValidCacheBoxForCurrentUser` check every read/write
      // already performs independently.
      final pending = service.initializeCache(uidOverride: _uidA);
      await FavoriteService.invalidateForAccountChange();
      await pending;

      expect(
        service.getCachedFavoritesSync(),
        isEmpty,
        reason: 'a stale initializeCache completion must not become this '
            'instance\'s active cache reference, even though the box it '
            'opened is real and otherwise usable',
      );

      // Confirms the instance has no valid active box at all (not merely an
      // empty one): a write captured before the same transition is still
      // correctly rejected too.
      await service.cacheFavorites(
        [_item('must-not-persist')],
        expectedGeneration: FavoriteService.currentAccountGeneration - 1,
      );
      expect(service.getCachedFavoritesSync(), isEmpty);
    });

    test(
        'an initializeCache call with no intervening transition still '
        'succeeds normally (the guard has no false positive)', () async {
      final service = FavoriteService()..debugActiveUserIdOverride = _uidA;

      final pending = service.initializeCache(uidOverride: _uidA);
      await pending;

      await service.cacheFavorites(
        [_item('normal-init')],
        expectedGeneration: FavoriteService.currentAccountGeneration,
      );

      expect(service.getCachedFavoritesSync(), hasLength(1));
    });
  });
}
