import 'package:flutter/foundation.dart';
import '../Views/Screens/home/favorites/favorites_service.dart';

/// Optimistic favorites manager with offline support and error rollback
class OptimisticFavoritesService extends ChangeNotifier {
  // `favoriteService` is an optional injection point for tests only —
  // mirrors the existing pattern already used by `FavoritesViewModel`'s own
  // constructor. Production (`main.dart`) always constructs this with no
  // arguments; the underlying `FavoriteService` is unaffected either way.
  OptimisticFavoritesService({FavoriteService? favoriteService})
      : _favoriteService = favoriteService ?? FavoriteService();

  final FavoriteService _favoriteService;

  // Local state for optimistic updates
  final Map<String, bool> _optimisticState = {};
  final Map<String, bool> _pendingOperations = {};
  final Set<String> _offlineQueue = {};

  // Per-key ordering guard against stale asynchronous completions.
  //
  // Two independent operation kinds write `_optimisticState[key]`: a
  // mutation (`toggleFavorite`, a user Add/Remove) and a read
  // (`initializeFavoriteStatus`/`updateLoadedFavorites`, a server status
  // check). Both are async, both can overlap, and either can finish after
  // the other started. Without ordering, an older read dispatched before a
  // removal — but resolving after it, reflecting pre-removal server truth —
  // could silently overwrite the removal's correct result: the exact defect
  // this guards against.
  //
  // `_mutationVersion[key]` is bumped only by `toggleFavorite`, at the start
  // of each attempt. A mutation's own result is authoritative unless a
  // *later* mutation has since taken over the same key (never by a read —
  // reads never bump this). `_readVersion[key]` is bumped only by a read, at
  // its start, purely to let two overlapping reads for the same key agree on
  // which one is newest regardless of completion order.
  //
  // A read publishes its result only if, at completion: no newer read has
  // since started for this key (`_readVersion` unchanged), no mutation has
  // started for this key since the read began (`_mutationVersion`
  // unchanged), and — critically — no mutation was *already in flight* when
  // the read started at all. That last condition is what a bare version
  // check misses: if a mutation is already pending when a read begins, the
  // read's own baseline already "includes" that mutation, so an unchanged
  // `_mutationVersion` alone would not detect it. A mutation in flight at
  // read-start always wins, however the read's own query happens to resolve.
  //
  // A mutation's rollback-on-failure is guarded the same way against a
  // *newer* mutation on the same key, so a stale failure can never roll back
  // state a later, successful mutation already established.
  final Map<String, int> _mutationVersion = {};
  final Map<String, int> _readVersion = {};

  // Track network connectivity (simplified - in real app use connectivity_plus)
  bool _isOnline = true;

  // The account generation this singleton's state was last confirmed
  // current for. This service is created once at the app root and never
  // recreated across an account transition (unlike FavoritesViewModel, which
  // is scoped to one session), so it is the one place that must be told
  // explicitly — see `syncAccountGeneration`, called from `main.dart`'s
  // ChangeNotifierProxyProvider whenever AuthViewModel notifies.
  int _syncedGeneration = FavoriteService.currentAccountGeneration;

  /// Clears previously-populated optimistic state (favorite flags, pending
  /// flags, the offline queue) the moment the canonical identity has moved
  /// on from whatever account this state described. A no-op when nothing has
  /// changed, so calling it on every `AuthViewModel` notification (including
  /// ones unrelated to auth, like profile edits) is safe and cheap.
  void syncAccountGeneration() {
    final current = FavoriteService.currentAccountGeneration;
    if (_syncedGeneration == current) return;
    _syncedGeneration = current;
    clearState();
  }

  /// Get current favorite status with optimistic state
  bool isFavorite(String itemId, String type) {
    final key = _getKey(itemId, type);
    return _optimisticState[key] ?? false;
  }

  /// Check if operation is in progress
  bool isLoading(String itemId, String type) {
    final key = _getKey(itemId, type);
    return _pendingOperations[key] ?? false;
  }

  /// Initialize with current server state. See the ordering-guard fields
  /// above for why this can lose to a concurrent mutation even though it may
  /// finish later — a read must never overwrite a user's own Add/Remove.
  Future<void> initializeFavoriteStatus(String itemId, String type) async {
    final key = _getKey(itemId, type);
    final startGeneration = FavoriteService.currentAccountGeneration;

    // Captured before issuing the query. A mutation already in flight for
    // this key always wins, regardless of how this read's own result turns
    // out — its query cannot be trusted to reflect that mutation's eventual
    // outcome just because it happens to resolve afterward.
    final mutationInFlightAtStart = _pendingOperations[key] == true;
    final mutationBaseline = _mutationVersion[key] ?? 0;
    final myReadVersion = (_readVersion[key] ?? 0) + 1;
    _readVersion[key] = myReadVersion;

    try {
      final serverState = await _favoriteService.isFavorite(itemId, type);

      final supersededByNewerRead = _readVersion[key] != myReadVersion;
      final supersededByMutation =
          (_mutationVersion[key] ?? 0) != mutationBaseline;
      final accountChanged =
          FavoriteService.currentAccountGeneration != startGeneration;

      if (mutationInFlightAtStart ||
          supersededByNewerRead ||
          supersededByMutation ||
          accountChanged) {
        return;
      }

      _optimisticState[key] = serverState;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to initialize favorite status: $e');
      // Keep optimistic state if server fails
    }
  }

  /// Optimistically toggle favorite with rollback on error
  Future<bool> toggleFavorite(String itemId, String type) async {
    final key = _getKey(itemId, type);
    final currentState = _optimisticState[key] ?? false;
    final newState = !currentState;

    // Prevent concurrent operations on same item
    if (_pendingOperations[key] == true) {
      return currentState;
    }

    // The canonical identity active right now, when this toggle is a live
    // user action for whoever is currently signed in. If it advances before
    // this call completes (the account signed out, or a different account
    // signed in — see `FavoriteService.invalidateForAccountChange`), the
    // completion below belongs to an account that is no longer current and
    // must not be allowed to write into this shared, singleton map: that map
    // is never recreated across an account transition, so a late write here
    // would otherwise resurrect one stale favorite flag for whoever is
    // signed in now.
    final startGeneration = FavoriteService.currentAccountGeneration;
    bool isStale() => FavoriteService.currentAccountGeneration != startGeneration;

    // This mutation is now the current one for this key — bumped before any
    // await, so any read that later checks `_mutationVersion[key]` for this
    // key sees the change immediately. A read never bumps this: only a later
    // *mutation* can supersede this one, never a mere status check.
    final myMutationVersion = (_mutationVersion[key] ?? 0) + 1;
    _mutationVersion[key] = myMutationVersion;
    bool supersededByNewerMutation() =>
        _mutationVersion[key] != myMutationVersion;

    // 1. Optimistic update (immediate UI feedback)
    _optimisticState[key] = newState;
    _pendingOperations[key] = true;
    notifyListeners();

    try {
      if (_isOnline) {
        // 2. Attempt server update
        final actualState = newState
            ? await _favoriteService
                .addToFavorites(itemId, type)
                .then((_) => true)
            : await _favoriteService
                .removeFromFavorites(itemId, type)
                .then((_) => false);

        if (isStale()) {
          return actualState;
        }

        // 3. Confirm optimistic state matches server — but only if no
        // *later* mutation has since taken over this key (this one's own
        // reentrancy guard above normally prevents that for this exact key,
        // this check is the same rule enforced explicitly and is what
        // stale reads check against).
        if (!supersededByNewerMutation()) {
          _optimisticState[key] = actualState;
          _pendingOperations[key] = false;
          notifyListeners();
        }

        return actualState;
      } else {
        // 4. Offline: queue for later sync
        if (!isStale() && !supersededByNewerMutation()) {
          _offlineQueue.add(key);
          _pendingOperations[key] = false;
          notifyListeners();
        }

        return newState;
      }
    } catch (e) {
      // 5. Rollback on error — but a stale failure must not roll back a
      // newer mutation's already-applied state, so this is guarded the same
      // way a success is.
      debugPrint('Failed to toggle favorite: $e');
      if (!isStale() && !supersededByNewerMutation()) {
        _optimisticState[key] = currentState; // Revert to original state
        _pendingOperations[key] = false;
        notifyListeners();
      }

      // Notify error to UI
      rethrow;
    }
  }

  /// Sync offline queue when network returns
  Future<void> syncOfflineQueue() async {
    if (!_isOnline || _offlineQueue.isEmpty) return;

    final queueCopy = Set<String>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final key in queueCopy) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final type = parts[0];
        final itemId = parts.sublist(1).join('_');

        try {
          final currentOptimisticState = _optimisticState[key] ?? false;

          if (currentOptimisticState) {
            await _favoriteService.addToFavorites(itemId, type);
          } else {
            await _favoriteService.removeFromFavorites(itemId, type);
          }
        } catch (e) {
          debugPrint('Failed to sync favorite $key: $e');
          // Re-queue failed items
          _offlineQueue.add(key);
        }
      }
    }

    notifyListeners();
  }

  /// Update network status
  void setOnlineStatus(bool isOnline) {
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      if (isOnline) {
        syncOfflineQueue();
      }
    }
  }

  /// Clear all local state (useful for logout)
  void clearState() {
    _optimisticState.clear();
    _pendingOperations.clear();
    _offlineQueue.clear();
    // A cleared account has no history worth preserving ordering for: the
    // next account starts every key's versioning fresh, at 0.
    _mutationVersion.clear();
    _readVersion.clear();
    notifyListeners();
  }

  /// Snapshot of every key's current mutation version and which keys have a
  /// mutation in flight right now, for a caller (namely
  /// `FavoritesViewModel`) to capture immediately before starting an
  /// authoritative list fetch, then pass back into [updateLoadedFavorites]
  /// or [batchInitializeFavorites]. This is what lets a bulk read reject a
  /// per-key mutation that was already in flight, or that started during the
  /// fetch — a generation/account check alone is too coarse and too late for
  /// that, since it only distinguishes accounts, not individual items.
  ({Map<String, int> versions, Set<String> pendingKeys})
      snapshotMutationVersions() {
    return (
      versions: Map<String, int>.from(_mutationVersion),
      pendingKeys: _pendingOperations.entries
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toSet(),
    );
  }

  /// Batch initialize multiple items (performance optimization). Currently
  /// unused in production, but protected with the same ordering guard as
  /// [initializeFavoriteStatus] since it is another read-style bulk
  /// publisher of `_optimisticState`. `mutationSnapshot` must be
  /// [snapshotMutationVersions]'s return value, captured before this call.
  Future<void> batchInitializeFavorites(
    List<String> itemIds,
    String type, {
    required ({Map<String, int> versions, Set<String> pendingKeys})
        mutationSnapshot,
  }) async {
    final startGeneration = FavoriteService.currentAccountGeneration;

    try {
      // Get all favorites of this type from server
      final serverFavorites = await _favoriteService.getAllFavorites();
      final typeFavorites = serverFavorites[type] ?? [];

      if (FavoriteService.currentAccountGeneration != startGeneration) return;

      // Update local state for all requested items, skipping any item whose
      // key was touched by a mutation during (or already in flight before)
      // this fetch — that mutation's own result is authoritative instead.
      for (final itemId in itemIds) {
        final key = _getKey(itemId, type);
        final wasPending = mutationSnapshot.pendingKeys.contains(key);
        final baseline = mutationSnapshot.versions[key] ?? 0;
        final unchanged = (_mutationVersion[key] ?? 0) == baseline;
        if (wasPending || !unchanged) continue;
        _optimisticState[key] = typeFavorites.contains(itemId);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to batch initialize favorites: $e');
    }
  }

  /// Bulk update optimistic state for loaded favorites (used by
  /// FavoritesViewModel). `expectedGeneration` must be the generation the
  /// caller's own fetch captured when it began — required, not optional, so
  /// this cannot be bypassed by omission the way the gap this closes was:
  /// a load that started under one account but only finishes resolving
  /// after a later account is current must not write that account's stale
  /// favorite flags into this shared, singleton map.
  ///
  /// `mutationSnapshot` must be [snapshotMutationVersions]'s return value,
  /// captured by the caller *before* it dispatched the authoritative fetch
  /// that produced [favoritesByType] — also required, for the same reason:
  /// the account-generation check alone cannot tell whether an *individual
  /// item* was mutated while this list was being fetched. Any key whose
  /// mutation version has since changed, or that already had a mutation in
  /// flight when the snapshot was taken, is skipped rather than overwritten
  /// — that key's own mutation is authoritative instead.
  void updateLoadedFavorites(
    Map<String, List<String>> favoritesByType, {
    required int expectedGeneration,
    required ({Map<String, int> versions, Set<String> pendingKeys})
        mutationSnapshot,
  }) {
    if (expectedGeneration != FavoriteService.currentAccountGeneration) {
      return;
    }
    for (final entry in favoritesByType.entries) {
      for (final itemId in entry.value) {
        final key = _getKey(itemId, entry.key);
        final wasPending = mutationSnapshot.pendingKeys.contains(key);
        final baseline = mutationSnapshot.versions[key] ?? 0;
        final unchanged = (_mutationVersion[key] ?? 0) == baseline;
        if (wasPending || !unchanged) continue;
        _optimisticState[key] = true;
      }
    }
    notifyListeners();
  }

  String _getKey(String itemId, String type) => '${type}_$itemId';

  /// Convenience methods for specific types
  Future<bool> toggleOfferFavorite(String offerId) =>
      toggleFavorite(offerId, 'offers');

  Future<bool> toggleRequestFavorite(String requestId) =>
      toggleFavorite(requestId, 'requests');

  Future<bool> toggleOwnerFavorite(String ownerId) =>
      toggleFavorite(ownerId, 'owners');

  Future<bool> toggleOfficeFavorite(String officeId) =>
      toggleFavorite(officeId, 'offices');

  Future<bool> toggleBrokerFavorite(String brokerId) =>
      toggleFavorite(brokerId, 'brokers');

  Future<bool> toggleWatchmenFavorite(String watchmenId) =>
      toggleFavorite(watchmenId, 'watchmen');

  bool isOfferFavorite(String offerId) => isFavorite(offerId, 'offers');
  bool isRequestFavorite(String requestId) => isFavorite(requestId, 'requests');
  bool isOwnerFavorite(String ownerId) => isFavorite(ownerId, 'owners');
  bool isOfficeFavorite(String officeId) => isFavorite(officeId, 'offices');
  bool isBrokerFavorite(String brokerId) => isFavorite(brokerId, 'brokers');
  bool isWatchmenFavorite(String watchmenId) =>
      isFavorite(watchmenId, 'watchmen');

  bool isOfferLoading(String offerId) => isLoading(offerId, 'offers');
  bool isRequestLoading(String requestId) => isLoading(requestId, 'requests');
  bool isOwnerLoading(String ownerId) => isLoading(ownerId, 'owners');
  bool isOfficeLoading(String officeId) => isLoading(officeId, 'offices');
  bool isBrokerLoading(String brokerId) => isLoading(brokerId, 'brokers');
  bool isWatchmenLoading(String watchmenId) =>
      isLoading(watchmenId, 'watchmen');
}
