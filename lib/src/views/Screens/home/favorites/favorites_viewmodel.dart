import 'package:flutter/material.dart';
import '../../../../data/models/filter_model.dart';
import 'favorites_item_model.dart';
import '../../../../data/models/ScreensModel/offers_model.dart';
import '../../../../data/models/ScreensModel/request_model.dart';
import '../../../../data/models/ScreensModel/owners_model.dart';
import '../../../../data/models/ScreensModel/offices_model.dart';
import '../../../../data/models/ScreensModel/brokers_model.dart';
import '../../../../data/models/ScreensModel/watchmen_model.dart';
import 'favorite_card_media.dart';
import 'favorites_service.dart';
import '../../../../services/ScreenServices/offer_service.dart';
import '../../../../services/ScreenServices/request_service.dart';
import '../../../../services/ScreenServices/owner_service.dart';
import '../../../../services/ScreenServices/office_service.dart';
import '../../../../services/ScreenServices/broker_service.dart';
import '../../../../services/ScreenServices/watchmen_service.dart';
import '../../../../services/bounded_tasks.dart';
import '../../../../services/offer_media_cache_identity.dart'
    show offerMediaCacheKeyPrefix;
import '../../../../services/supabase_core_entities_service.dart'
    show DisplayMediaOutcome;
import '../../../../services/optimistic_favorites_service.dart';
import '../../../../common/localization/localization_delegate.dart';
import 'dart:async';

class FavoritesViewModel extends ChangeNotifier {
  final OptimisticFavoritesService? _optimisticFavoritesService;
  final FavoriteService _favoriteService;
  final OfferService _offerService;
  final RequestService _requestService;
  final OwnerService _ownerService;
  final OfficeService _officeService;
  final BrokerService _brokerService;
  final WatchmenService _watchmenService;
  AppLocalizations? _localization;

  // Add throttling for rapid updates
  Timer? _refreshThrottleTimer;

  final List<FilterModel> filters = [
    FilterModel(
        label: 'Recently Added',
        labelKey: 'recentlyAdded'), // Not selected by default - show all items
    FilterModel(label: 'Requests', labelKey: 'requests'),
    FilterModel(label: 'Offers', labelKey: 'offers'),
    FilterModel(label: 'Owners', labelKey: 'owners'),
    FilterModel(label: 'Offices', labelKey: 'offices'),
    FilterModel(label: 'Watchmen', labelKey: 'watchmen'),
    FilterModel(label: 'Brokers', labelKey: 'brokers'),
  ];

  List<FavoriteItem> _allFavorites = [];
  List<FavoriteItem> _filteredFavorites = [];
  List<FavoriteItem> _cachedFavorites = [];
  bool _isLoading = false;
  bool _isRefreshing = false;

  // Set when the favorites could not be read whole. The metadata read never
  // answers a failure with an empty list (FU-FAV-META-EMPTY), so a failed
  // read leaves what is shown as it is; with nothing to show, the screen's
  // error state appears instead of "no favorites". Cleared by the next
  // complete answer.
  String? _error;
  bool _disposed = false;
  bool _cacheInitialized = false;

  // The canonical-identity generation active when this instance was built.
  // If `AuthViewModel._handleSessionIdentity` advances the generation later
  // (the account signed out, or a different account signed in), any fetch
  // this instance already had in flight is for the wrong account and must
  // not publish or cache its result — see `_isCurrentForAccount`.
  final int _creationGeneration = FavoriteService.currentAccountGeneration;
  bool get _isCurrentForAccount =>
      !_disposed &&
      FavoriteService.currentAccountGeneration == _creationGeneration;

  List<FavoriteItem> get favorites => _filteredFavorites;
  List<FavoriteItem> get cachedFavorites => _cachedFavorites;
  List<FavoriteItem> get displayFavorites {
    // Always return filtered results
    if (_filteredFavorites.isNotEmpty) {
      return _filteredFavorites;
    }
    // If no filtered results but we have cached data, apply filter to cached data
    if (_cachedFavorites.isNotEmpty) {
      return _applyFilterToList(_cachedFavorites);
    }
    // Fallback to all favorites
    return _allFavorites;
  }

  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;
  bool get hasNoFavorites =>
      _allFavorites.isEmpty && _cachedFavorites.isEmpty && !_isLoading;
  bool get hasUnfilteredData =>
      _allFavorites.isNotEmpty || _cachedFavorites.isNotEmpty;

  FavoritesViewModel({
    OptimisticFavoritesService? optimisticFavoritesService,
    FavoriteService? favoriteService,
    OfferService? offerService,
    OwnerService? ownerService,
    RequestService? requestService,
    OfficeService? officeService,
    BrokerService? brokerService,
    WatchmenService? watchmenService,
  })  : _optimisticFavoritesService = optimisticFavoritesService,
        _favoriteService = favoriteService ?? FavoriteService(),
        _offerService = offerService ?? OfferService(),
        _ownerService = ownerService ?? OwnerService(),
        _requestService = requestService ?? RequestService(),
        _officeService = officeService ?? OfficeService(),
        _brokerService = brokerService ?? BrokerService(),
        _watchmenService = watchmenService ?? WatchmenService() {
    _initializeAndLoadFavorites();

    // Listen to changes in the optimistic favorites service
    if (_optimisticFavoritesService != null) {
      _optimisticFavoritesService.addListener(_onOptimisticFavoritesChanged);
    }
  }

  void updateLocalization(AppLocalizations localization) {
    final hasChanged =
        _localization?.locale.languageCode != localization.locale.languageCode;
    _localization = localization;
    if (hasChanged) {
      scheduleMicrotask(() {
        if (!_disposed) {
          _rebuildLocalizedFavorites();
        }
      });
    }
  }

  @override
  void dispose() {
    _optimisticFavoritesService?.removeListener(_onOptimisticFavoritesChanged);
    _refreshThrottleTimer?.cancel();
    _disposed = true;
    // A metadata read still in progress asks for no further page.
    _favoriteService.cancelMetadataReads();
    super.dispose();
  }

  void _onOptimisticFavoritesChanged() {
    if (_disposed) return;

    // Throttle rapid changes to prevent too many refreshes
    _refreshThrottleTimer?.cancel();
    _refreshThrottleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_disposed) {
        _refreshImmediately();
      }
    });
  }

  Future<void> _refreshImmediately() async {
    if (_disposed) return;

    // Captured before the fetch dispatches, so a per-key mutation that races
    // this refresh (including one already in flight right now) can be
    // detected once the fetch's result is about to be applied. The empty
    // fallback is never actually consulted: `_syncOptimisticServiceWithLoadedFavorites`
    // returns immediately when `_optimisticFavoritesService` is null, before
    // this value would be used.
    final mutationSnapshot = _optimisticFavoritesService
            ?.snapshotMutationVersions() ??
        (versions: const <String, int>{}, pendingKeys: const <String>{});

    try {
      // Don't show loading state - this should be seamless
      final favoriteMetadata =
          await _favoriteService.getAllFavoritesWithMetadata();

      if (!_isCurrentForAccount) return;

      // If no favorites, clear everything and update UI
      if (favoriteMetadata.values.every((metaList) => metaList.isEmpty)) {
        final reconciled = _reconcileFetchedFavorites(
          const [],
          mutationSnapshot: mutationSnapshot,
        );
        _allFavorites = reconciled;
        _error = null;
        _cachedFavorites = reconciled;
        _applyFilter();
        _safeNotifyListeners();
        return;
      }

      // Load favorites with limited concurrency for speed
      final favorites =
          await _loadFavoritesWithLimitedConcurrency(favoriteMetadata);

      if (_isCurrentForAccount) {
        favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        final reconciled = _reconcileFetchedFavorites(
          favorites,
          mutationSnapshot: mutationSnapshot,
        );
        _allFavorites = reconciled;
        _error = null;
        _cachedFavorites = reconciled;
        _applyFilter();

        // Update optimistic service state to keep it in sync
        _syncOptimisticServiceWithLoadedFavorites(
          reconciled,
          mutationSnapshot: mutationSnapshot,
        );

        _safeNotifyListeners();

        // Update cache in background
        _favoriteService.cacheFavorites(
          reconciled,
          expectedGeneration: _creationGeneration,
        );
      }
    } catch (e) {
      // Don't show error to user - this is a background operation
      // Debug log suppressed: Immediate favorites refresh failed: $e
    }
  }

  void _syncOptimisticServiceWithLoadedFavorites(
    List<FavoriteItem> favorites, {
    required ({Map<String, int> versions, Set<String> pendingKeys})
        mutationSnapshot,
  }) {
    if (_optimisticFavoritesService == null) return;

    // Group favorites by type for batch updates
    final Map<String, List<String>> favoritesByType = {};
    for (final favorite in favorites) {
      favoritesByType.putIfAbsent(favorite.type, () => []).add(favorite.id);
    }

    // Update optimistic service state. Guarded both by this instance's own
    // creation generation (a no-op if the account has since moved on) and by
    // `mutationSnapshot` — captured by the caller *before* the fetch that
    // produced `favorites` began — so a per-key mutation that raced this
    // fetch is never overwritten by this now-stale bulk result.
    _optimisticFavoritesService.updateLoadedFavorites(
      favoritesByType,
      expectedGeneration: _creationGeneration,
      mutationSnapshot: mutationSnapshot,
    );
  }

  // Reconciles a freshly fetched favorites list against the current
  // in-memory list so that a mutation (add/remove) which started or
  // completed after `mutationSnapshot` was captured is never overwritten by
  // this now-stale fetch — in either direction. For a key whose mutation
  // version has moved on (or is still pending) since the snapshot, the
  // *current* list's membership for that key wins; every other key defers to
  // the fetch, which is authoritative for anything not racing a mutation.
  // Keys are the union of both lists, so this fixes stale presence (a fetch
  // that still lists a just-removed item) and stale absence (a fetch that
  // predates a just-added item) symmetrically.
  List<FavoriteItem> _reconcileFetchedFavorites(
    List<FavoriteItem> fetched, {
    required ({Map<String, int> versions, Set<String> pendingKeys})
        mutationSnapshot,
  }) {
    final service = _optimisticFavoritesService;
    if (service == null) return fetched;

    final snapshotNow = service.snapshotMutationVersions();

    String keyOf(FavoriteItem item) => '${item.type}_${item.id}';

    bool isAffected(String key) {
      if (mutationSnapshot.pendingKeys.contains(key)) return true;
      if (snapshotNow.pendingKeys.contains(key)) return true;
      final before = mutationSnapshot.versions[key] ?? 0;
      final now = snapshotNow.versions[key] ?? 0;
      return before != now;
    }

    final fetchedByKey = {for (final item in fetched) keyOf(item): item};
    final currentByKey = {for (final item in _allFavorites) keyOf(item): item};
    final allKeys = {...fetchedByKey.keys, ...currentByKey.keys};

    final reconciled = <FavoriteItem>[];
    for (final key in allKeys) {
      if (isAffected(key)) {
        final preserved = currentByKey[key];
        if (preserved != null) reconciled.add(preserved);
      } else {
        final authoritative = fetchedByKey[key];
        if (authoritative != null) reconciled.add(authoritative);
      }
    }
    reconciled.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return reconciled;
  }

  void _initializeAndLoadFavorites() {
    // Load cached data synchronously if available
    _loadCachedFavoritesSync();

    final shouldLoadColdFavorites = _cachedFavorites.isEmpty;

    // Initialize cache and load fresh data asynchronously
    _initializeCacheAsync(skipInitialLoad: shouldLoadColdFavorites);

    // If no cached data and no loading state, load fresh data immediately
    if (shouldLoadColdFavorites && !_isLoading) {
      _loadFreshFavoritesImmediately();
    }
  }

  void _loadCachedFavoritesSync() {
    if (_disposed) return;

    try {
      final cachedFavorites = _favoriteService.getCachedFavoritesSync();

      if (cachedFavorites.isNotEmpty) {
        _cachedFavorites = cachedFavorites;
        // If we don't have fresh data yet, use cached as source for filtering
        if (_allFavorites.isEmpty) {
          _allFavorites = List.from(cachedFavorites);
        }
        _applyFilter();
        _safeNotifyListeners();
      }
      // NEVER set loading state - cached data should always be available
    } catch (e) {
      // Even on error, don't set loading state
    }
  }

  Future<void> _initializeCacheAsync({required bool skipInitialLoad}) async {
    try {
      // Ensure authentication is ready before proceeding
      await _favoriteService.waitForAuthReady();

      // Initialize cache first
      if (!_cacheInitialized) {
        await _initializeCache();
      }

      // The box is open now. A screen that found no cache when it was built
      // (the box was not open yet) shows what this account cached on its last
      // visit while the first load is still running, instead of waiting for
      // the network. Once that load has answered, its answer is the truth.
      if (_isLoading && _cachedFavorites.isEmpty) _loadCachedFavoritesSync();

      // Always load fresh data to ensure we have the latest
      // If we have cached data, this will happen in background
      // If we don't have cached data, this will show the loading state
      if (!skipInitialLoad) {
        await loadFavorites();
      }
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load favorites';
      _safeNotifyListeners();
    }
  }

  Future<void> _initializeCache() async {
    try {
      await _favoriteService.initializeCache();
      _cacheInitialized = true;
    } catch (e) {
      // Silently handle cache initialization errors
    }
  }

  void toggleFilter(int index) {
    if (_disposed) return;

    if (filters[index].selected) {
      // Allow deselecting - this will show all items
      filters[index].selected = false;
    } else {
      // Deselect all other filters and select this one
      for (int i = 0; i < filters.length; i++) {
        filters[i].selected = (i == index);
      }
    }

    _applyFilter();
    _safeNotifyListeners();
  }

  FilterModel? get selectedFilter {
    try {
      return filters.firstWhere((filter) => filter.selected);
    } catch (e) {
      return null;
    }
  }

  String? get selectedFilterKey {
    final selected = selectedFilter;
    return selected?.labelKey ?? selected?.label;
  }

  Future<void> _loadFreshFavoritesImmediately() async {
    if (!_isCurrentForAccount) return;

    // Ensure authentication is ready before proceeding
    await _favoriteService.waitForAuthReady();

    if (!_isCurrentForAccount) return;

    // Set loading state only if we truly have no data
    if (_cachedFavorites.isEmpty) {
      _isLoading = true;
      _error = null;
      _safeNotifyListeners();
    }

    try {
      // Captured immediately before the fetch dispatches, so a per-key
      // mutation that races it (including one already in flight) can be
      // detected once the fetch's result is about to be applied.
      final mutationSnapshot = _optimisticFavoritesService
              ?.snapshotMutationVersions() ??
          (versions: const <String, int>{}, pendingKeys: const <String>{});

      // Get favorite metadata (IDs with timestamps) from the backend
      final favoriteMetadata =
          await _favoriteService.getAllFavoritesWithMetadata();

      if (!_isCurrentForAccount) return;

      // If no favorites, update state and return
      if (favoriteMetadata.values.every((metaList) => metaList.isEmpty)) {
        final reconciled = _reconcileFetchedFavorites(
          const [],
          mutationSnapshot: mutationSnapshot,
        );
        _allFavorites = reconciled;
        _error = null;
        _cachedFavorites = reconciled;
        _applyFilter();
        _safeNotifyListeners();
        return;
      }

      // Load favorites in parallel with limited concurrency
      final favorites =
          await _loadFavoritesWithLimitedConcurrency(favoriteMetadata);

      if (_isCurrentForAccount) {
        favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        final reconciled = _reconcileFetchedFavorites(
          favorites,
          mutationSnapshot: mutationSnapshot,
        );
        _allFavorites = reconciled;
        _error = null;
        _cachedFavorites = reconciled; // Also update cached for display
        _applyFilter();

        // Cache the data for future instant loads
        await _favoriteService.cacheFavorites(
          reconciled,
          expectedGeneration: _creationGeneration,
        );

        // Update optimistic service state to keep it in sync
        _syncOptimisticServiceWithLoadedFavorites(
          reconciled,
          mutationSnapshot: mutationSnapshot,
        );

        _safeNotifyListeners();
      }
    } catch (e) {
      _error = 'Failed to load favorites: ${e.toString()}';
      // Debug log suppressed: Error loading favorites: $e
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<List<FavoriteItem>> _loadFavoritesWithLimitedConcurrency(
      Map<String, List<FavoriteMetadata>> favoriteMetadata) async {
    final List<FavoriteItem> favorites = [];
    final List<Future> futures = [];

    // Load offers
    if (favoriteMetadata['offers']?.isNotEmpty == true) {
      futures
          .add(_loadOffersWithMetadata(favoriteMetadata['offers']!, favorites));
    }

    // Load requests
    if (favoriteMetadata['requests']?.isNotEmpty == true) {
      futures.add(
          _loadRequestsWithMetadata(favoriteMetadata['requests']!, favorites));
    }

    // Load owners
    if (favoriteMetadata['owners']?.isNotEmpty == true) {
      futures
          .add(_loadOwnersWithMetadata(favoriteMetadata['owners']!, favorites));
    }

    // Load offices
    if (favoriteMetadata['offices']?.isNotEmpty == true) {
      futures.add(
          _loadOfficesWithMetadata(favoriteMetadata['offices']!, favorites));
    }

    // Load brokers
    if (favoriteMetadata['brokers']?.isNotEmpty == true) {
      futures.add(
          _loadBrokersWithMetadata(favoriteMetadata['brokers']!, favorites));
    }

    // Load watchmen
    if (favoriteMetadata['watchmen']?.isNotEmpty == true) {
      futures.add(
          _loadWatchmenWithMetadata(favoriteMetadata['watchmen']!, favorites));
    }

    // Wait for all to complete
    await Future.wait(futures);
    return favorites;
  }

  Future<void> loadFavorites() async {
    if (!_isCurrentForAccount) return;

    // Don't set loading state if we already have cached data
    if (_cachedFavorites.isEmpty) {
      _isLoading = true;
      _error = null;
      _safeNotifyListeners();
    }

    await _loadFreshFavorites();
  }

  Future<void> _loadFreshFavorites() async {
    if (!_isCurrentForAccount) return;

    try {
      // Captured immediately before the fetch dispatches, so a per-key
      // mutation that races it (including one already in flight) can be
      // detected once the fetch's result is about to be applied.
      final mutationSnapshot = _optimisticFavoritesService
              ?.snapshotMutationVersions() ??
          (versions: const <String, int>{}, pendingKeys: const <String>{});

      final favoriteMetadata =
          await _favoriteService.getAllFavoritesWithMetadata();
      final List<FavoriteItem> favorites = [];

      // Load all types in parallel for better performance
      final futures = <Future>[];

      // Load offers
      if (favoriteMetadata['offers']?.isNotEmpty == true) {
        futures.add(
            _loadOffersWithMetadata(favoriteMetadata['offers']!, favorites));
      }

      // Load requests
      if (favoriteMetadata['requests']?.isNotEmpty == true) {
        futures.add(_loadRequestsWithMetadata(
            favoriteMetadata['requests']!, favorites));
      }

      // Load owners
      if (favoriteMetadata['owners']?.isNotEmpty == true) {
        futures.add(
            _loadOwnersWithMetadata(favoriteMetadata['owners']!, favorites));
      }

      // Load offices
      if (favoriteMetadata['offices']?.isNotEmpty == true) {
        futures.add(
            _loadOfficesWithMetadata(favoriteMetadata['offices']!, favorites));
      }

      // Load brokers
      if (favoriteMetadata['brokers']?.isNotEmpty == true) {
        futures.add(
            _loadBrokersWithMetadata(favoriteMetadata['brokers']!, favorites));
      }

      // Load watchmen
      if (favoriteMetadata['watchmen']?.isNotEmpty == true) {
        futures.add(_loadWatchmenWithMetadata(
            favoriteMetadata['watchmen']!, favorites));
      }

      // Wait for all parallel loads to complete
      await Future.wait(futures);

      // Sort by added date and update state
      if (_isCurrentForAccount) {
        favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        final reconciled = _reconcileFetchedFavorites(
          favorites,
          mutationSnapshot: mutationSnapshot,
        );
        _allFavorites = reconciled;
        _error = null;
        _applyFilter();

        // Update optimistic service state to keep it in sync
        _syncOptimisticServiceWithLoadedFavorites(
          reconciled,
          mutationSnapshot: mutationSnapshot,
        );

        // Cache the fresh data for future instant loads
        await _favoriteService.cacheFavorites(
          reconciled,
          expectedGeneration: _creationGeneration,
        );

        _safeNotifyListeners();
      }
    } catch (e) {
      _error = 'Failed to load favorites: ${e.toString()}';
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      _safeNotifyListeners();
    }
  }

  // Future<void> _loadOffers(
  //     List<String> offerIds, List<FavoriteItem> favorites) async {
  //   for (final offerId in offerIds) {
  //     if (_disposed) return;

  //     try {
  //       final offer = await _offerService.getOffer(offerId);
  //       if (offer != null && !_disposed) {
  //         favorites.add(FavoriteItem(
  //           id: offerId,
  //           type: 'offers',
  //           title: _getOfferTitle(offer),
  //           subtitle: _getOfferSubtitle(offer),
  //           imageUrl: offer.mediaUrls.isNotEmpty ? offer.mediaUrls.first : null,
  //           addedAt: DateTime.now(),
  //           originalData: offer,
  //         ));
  //       }
  //     } catch (e) {
  //     }
  //   }
  // }

  // Future<void> _loadRequests(
  //     List<String> requestIds, List<FavoriteItem> favorites) async {
  //   for (final requestId in requestIds) {
  //     if (_disposed) return;

  //     try {
  //       final request = await _requestService.getRequest(requestId);
  //       if (request != null && !_disposed) {
  //         favorites.add(FavoriteItem(
  //           id: requestId,
  //           type: 'requests',
  //           title: _getRequestTitle(request),
  //           subtitle: _getRequestSubtitle(request),
  //           addedAt: DateTime.now(),
  //           originalData: request,
  //         ));
  //       }
  //     } catch (e) {
  //     }
  //   }
  // }

  // Future<void> _loadOwners(
  //     List<String> ownerIds, List<FavoriteItem> favorites) async {
  //   for (final ownerId in ownerIds) {
  //     if (_disposed) return;

  //     try {
  //       final owner = await _ownerService.getOwner(ownerId);
  //       if (owner != null && !_disposed) {
  //         favorites.add(FavoriteItem(
  //           id: ownerId,
  //           type: 'owners',
  //           title: owner.name.isNotEmpty ? owner.name : 'Property Owner',
  //           subtitle: owner.typeOfProperties.isNotEmpty
  //               ? owner.typeOfProperties
  //               : 'Property Owner',
  //           imageUrl: owner.mediaUrls.isNotEmpty ? owner.mediaUrls.first : null,
  //           addedAt: DateTime.now(),
  //           originalData: owner,
  //         ));
  //       }
  //     } catch (e) {
  //     }
  //   }
  // }

  // Future<void> _loadOffices(
  //     List<String> officeIds, List<FavoriteItem> favorites) async {
  //   for (final officeId in officeIds) {
  //     if (_disposed) return;

  //     try {
  //       final office = await _officeService.getOffice(officeId);
  //       if (office != null && !_disposed) {
  //         favorites.add(FavoriteItem(
  //           id: officeId,
  //           type: 'offices',
  //           title: office.officeName.isNotEmpty ? office.officeName : 'Office',
  //           subtitle: office.managerName.isNotEmpty
  //               ? 'Manager: ${office.managerName}'
  //               : 'Office Location',
  //           addedAt: DateTime.now(),
  //           originalData: office,
  //         ));
  //       }
  //     } catch (e) {
  //     }
  //   }
  // }

  // Future<void> _loadBrokers(
  //     List<String> brokerIds, List<FavoriteItem> favorites) async {
  //   for (final brokerId in brokerIds) {
  //     if (_disposed) return;

  //     try {
  //       final broker = await _brokerService.getBroker(brokerId);
  //       if (broker != null && !_disposed) {
  //         favorites.add(FavoriteItem(
  //           id: brokerId,
  //           type: 'brokers',
  //           title: broker.name.isNotEmpty ? broker.name : 'Broker',
  //           subtitle: 'Real Estate Broker',
  //           addedAt: DateTime.now(),
  //           originalData: broker,
  //         ));
  //       }
  //     } catch (e) {
  //     }
  //   }
  // }

  // Future<void> _loadWatchmen(
  //     List<String> watchmenIds, List<FavoriteItem> favorites) async {
  //   for (final watchmenId in watchmenIds) {
  //     if (_disposed) return;

  //     try {
  //       final watchmen = await _watchmenService.getWatchmen(watchmenId);
  //       if (watchmen != null && !_disposed) {
  //         favorites.add(FavoriteItem(
  //           id: watchmenId,
  //           type: 'watchmen',
  //           title: watchmen.name.isNotEmpty ? watchmen.name : 'Watchmen',
  //           subtitle: watchmen.buildingName.isNotEmpty
  //               ? 'Building: ${watchmen.buildingName}'
  //               : 'Security Watchmen',
  //           addedAt: DateTime.now(),
  //           originalData: watchmen,
  //         ));
  //       }
  //     } catch (e) {
  //     }
  //   }
  // }

  void _applyFilter() {
    if (_disposed) return;

    _filteredFavorites = _applyFilterToList(_allFavorites);
  }

  List<FavoriteItem> _applyFilterToList(List<FavoriteItem> favorites) {
    final selectedFilterKey = this.selectedFilterKey;

    if (selectedFilterKey == null) {
      // No filter selected - show all items, sorted by most recent first
      return List.from(favorites)
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } else if (selectedFilterKey == 'recentlyAdded') {
      // Recently Added: show items added in the last 24 hours
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));

      return favorites
          .where((favorite) => favorite.addedAt.isAfter(yesterday))
          .toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt)); // Most recent first
    } else {
      // Filter by specific type
      String filterType;
      switch (selectedFilterKey) {
        case 'requests':
          filterType = 'requests';
          break;
        case 'offers':
          filterType = 'offers';
          break;
        case 'owners':
          filterType = 'owners';
          break;
        case 'offices':
          filterType = 'offices';
          break;
        case 'brokers':
          filterType = 'brokers';
          break;
        case 'watchmen':
          filterType = 'watchmen';
          break;
        default:
          filterType = selectedFilterKey;
      }

      return favorites.where((favorite) => favorite.type == filterType).toList()
        ..sort((a, b) =>
            b.addedAt.compareTo(a.addedAt)); // Most recent first within type
    }
  }

  String _getOfferTitle(OfferModel offer) {
    if (offer.specificPropertyType.isNotEmpty) {
      return offer.specificPropertyType;
    }
    final localization = _localization;
    if (localization != null) {
      return offer.offerType == 'rent'
          ? localization.translate('rentOffer')
          : localization.translate('saleOffer');
    }
    return offer.offerType == 'rent' ? 'Rent Offer' : 'Sale Offer';
  }

  String _getOfferSubtitle(OfferModel offer) {
    List<String> parts = [];
    if (offer.selectedCity.isNotEmpty) {
      parts.add(offer.selectedCity);
    }
    final localization = _localization;
    if (offer.minPrice.isNotEmpty && offer.maxPrice.isNotEmpty) {
      if (localization != null) {
        parts.add(
          localization
              .translate('favoritesPriceRange')
              .replaceAll('{min}', _formatAmount(offer.minPrice, localization))
              .replaceAll('{max}', _formatAmount(offer.maxPrice, localization)),
        );
      } else {
        parts.add('${offer.minPrice} - ${offer.maxPrice} AED');
      }
    } else if (offer.minPrice.isNotEmpty) {
      if (localization != null) {
        parts.add(
          localization.translate('favoritesPriceFrom').replaceAll(
              '{amount}', _formatAmount(offer.minPrice, localization)),
        );
      } else {
        parts.add('From ${offer.minPrice} AED');
      }
    } else if (offer.maxPrice.isNotEmpty) {
      if (localization != null) {
        parts.add(
          localization.translate('favoritesPriceUpTo').replaceAll(
              '{amount}', _formatAmount(offer.maxPrice, localization)),
        );
      } else {
        parts.add('Up to ${offer.maxPrice} AED');
      }
    }
    return parts.join(' • ');
  }

  String _getRequestTitle(RequestModel request) {
    if (request.specificPropertyType.isNotEmpty) {
      return request.specificPropertyType;
    }
    final localization = _localization;
    if (localization != null) {
      return request.requestType == 'rent'
          ? localization.translate('rentRequest')
          : localization.translate('purchaseRequest');
    }
    return request.requestType == 'rent' ? 'Rent Request' : 'Purchase Request';
  }

  String _getRequestSubtitle(RequestModel request) {
    List<String> parts = [];
    if (request.selectedCity.isNotEmpty) {
      parts.add(request.selectedCity);
    }
    final localization = _localization;
    if (request.minPrice.isNotEmpty && request.maxPrice.isNotEmpty) {
      if (localization != null) {
        parts.add(
          localization
              .translate('favoritesPriceRange')
              .replaceAll(
                  '{min}', _formatAmount(request.minPrice, localization))
              .replaceAll(
                  '{max}', _formatAmount(request.maxPrice, localization)),
        );
      } else {
        parts.add('${request.minPrice} - ${request.maxPrice} AED');
      }
    } else if (request.minPrice.isNotEmpty) {
      if (localization != null) {
        parts.add(
          localization.translate('favoritesPriceFrom').replaceAll(
              '{amount}', _formatAmount(request.minPrice, localization)),
        );
      } else {
        parts.add('From ${request.minPrice} AED');
      }
    } else if (request.maxPrice.isNotEmpty) {
      if (localization != null) {
        parts.add(
          localization.translate('favoritesPriceUpTo').replaceAll(
              '{amount}', _formatAmount(request.maxPrice, localization)),
        );
      } else {
        parts.add('Up to ${request.maxPrice} AED');
      }
    }
    return parts.join(' • ');
  }

  Future<void> refresh() async {
    if (!_isCurrentForAccount) return;

    _isRefreshing = true;
    _safeNotifyListeners();

    await _loadFreshFavorites();
  }

  Future<void> removeFavorite(FavoriteItem favorite) async {
    if (!_isCurrentForAccount) return;

    try {
      // Remove from the backend
      await _favoriteService.removeFromFavorites(favorite.id, favorite.type);

      if (!_isCurrentForAccount) return;

      // Immediately remove from local lists
      _allFavorites.removeWhere(
          (item) => item.id == favorite.id && item.type == favorite.type);
      _cachedFavorites.removeWhere(
          (item) => item.id == favorite.id && item.type == favorite.type);

      // Update filtered favorites
      _applyFilter();

      // Update cache (never creates the encrypted copy; see the method)
      await _favoriteService.cacheFavoritesAfterRemoval(
        _allFavorites,
        expectedGeneration: _creationGeneration,
      );

      _safeNotifyListeners();
    } catch (e) {
      // Optionally show error message to user
    }
  }

  void _safeNotifyListeners() {
    // Centralizes the account-generation guard: once the canonical identity
    // has moved on from whichever account this instance was built for, every
    // notification path (loading flips, errors, filters, loaded results)
    // becomes a no-op, the same way a disposed instance already is. This is
    // a no-op change for a session with no account transition, since
    // `_isCurrentForAccount` is then identical to `!_disposed`.
    if (_isCurrentForAccount) {
      notifyListeners();
    }
  }

  // The cards of one type: its records are read together (a few requests,
  // not one per favorite), then each card is built in the favorites' own
  // order, with the time each was added. A favorite whose record is missing
  // or deleted has no card. When the records cannot be read, the cards
  // already shown for those favorites stay (a failed read is not an empty
  // one); the others of this read are not affected.

  /// The records of [metadata], by id, or null when they could not be read
  /// (the shown cards of [type] that are still favorites have then been added
  /// to [favorites] instead).
  Future<Map<String, T>?> _recordsOf<T>(
    String type,
    List<FavoriteMetadata> metadata,
    List<FavoriteItem> favorites,
    Future<List<T>> Function(List<String> ids) read,
    String? Function(T record) idOf,
  ) async {
    try {
      final records = await read([for (final m in metadata) m.itemId]);
      return {
        for (final record in records)
          if (idOf(record) case final String id) id: record,
      };
    } catch (e) {
      // Debug log suppressed: Error loading favorite $type records: $e
      if (_disposed) return null;
      final stillFavorites = {for (final m in metadata) m.itemId};
      favorites.addAll(_allFavorites.where(
          (item) => item.type == type && stillFavorites.contains(item.id)));
      return null;
    }
  }

  Future<void> _loadOffersWithMetadata(List<FavoriteMetadata> offerMetadata,
      List<FavoriteItem> favorites) async {
    final offers = await _recordsOf(
      'offers',
      offerMetadata,
      favorites,
      (ids) => _offerService.getOffersByIds(ids, stop: () => _disposed),
      (OfferModel offer) => offer.id,
    );
    if (offers == null || _disposed) return;
    for (final metadata in offerMetadata) {
      final offer = offers[metadata.itemId];
      if (offer == null) continue;
      // Private media is picked by kind (the first photo, else a video's
      // still frame); an Offer with plain URLs keeps its first URL.
      var media = FavoriteCardMedia.fromOffer(offer);
      // The media read failed for a temporary reason: nothing was learned
      // about the media, so the card keeps what this device holds instead of
      // reading the failure as "no media" (tracker §7AZ,
      // FU-FAV-OFFER-MEDIA-FAILURE, Option B, D-FOMF-1). A refused read
      // shows nothing held.
      if (media == null &&
          _offerService.displayMediaOutcomeOf(offer) ==
              DisplayMediaOutcome.transient) {
        media = await _heldOfferCardMediaAfterFailure(offer);
        if (!_isCurrentForAccount) return;
      }
      // The Worker listed private media but its links are no longer in
      // memory: the card is what this device holds of those items, never a
      // signed link (tracker §7AZ, M3b-3, D-M3b3-1).
      if (media == null && offer.mediaObjectIds.isNotEmpty) {
        media = await _heldOfferCardMedia(offer);
        if (!_isCurrentForAccount) return;
      }
      favorites.add(FavoriteItem(
        id: metadata.itemId,
        type: 'offers',
        title: _getOfferTitle(offer),
        subtitle: _getOfferSubtitle(offer),
        // Only plain URLs (an Offer with no private media ids): the private
        // media's links are signed per read and never become an image key.
        imageUrl: media == null &&
                offer.mediaObjectIds.isEmpty &&
                offer.mediaUrls.isNotEmpty
            ? offer.mediaUrls.first
            : null,
        media: media,
        addedAt: metadata.addedAt, // Use actual timestamp!
        originalData: offer,
      ));
    }
  }

  /// The card of an Offer whose media the Worker has just listed: the first
  /// photo (else a video's still frame) this device holds of exactly those
  /// items, in the Worker's order — through the mapping, its previous copy or
  /// the private image cache, read only, for the signed-in account and its
  /// authorized session. No network, no link; null (the card's icon) when
  /// nothing is held. The device's catalogue may be older than this answer,
  /// so an item the Worker no longer lists is never shown.
  Future<FavoriteCardMedia?> _heldOfferCardMedia(OfferModel offer) async {
    final recordId = offer.id?.trim() ?? '';
    final accountId = _offerService.currentOwnerId?.trim() ?? '';
    if (recordId.isEmpty || accountId.isEmpty || accountId != offer.userId) {
      return null;
    }
    final listed = offer.mediaObjectIds;
    final found = await _offerService.discoverHeldOfferMedia(
      recordId,
      ownerId: accountId,
      ids: listed,
    );
    final held = {for (final ref in found) ref.mediaObjectId: ref};
    return FavoriteCardMedia.pick([
      for (final id in listed)
        if (held[id] case final ref?) ref,
    ]);
  }

  /// The card of an Offer whose media read failed for a temporary reason
  /// (FU-FAV-OFFER-MEDIA-FAILURE, Option B, D-FOMF-1): the first photo (else a
  /// video's still frame) this device holds for it, found with no network,
  /// no link and no download, for the signed-in account and its authorized
  /// session. Which items: the device's catalogue entry for the record when
  /// it has one (even an empty one); otherwise the ids this same read listed;
  /// otherwise — the read listed none, which proves nothing — the item this
  /// account's card was showing. Null (the card's icon) when nothing is held.
  Future<FavoriteCardMedia?> _heldOfferCardMediaAfterFailure(
      OfferModel offer) async {
    final recordId = offer.id?.trim() ?? '';
    final accountId = _offerService.currentOwnerId?.trim() ?? '';
    if (recordId.isEmpty || accountId.isEmpty || accountId != offer.userId) {
      return null;
    }
    final listed = offer.listedMediaObjectIds;
    final shown =
        listed.isEmpty ? _shownOfferMediaId(recordId, accountId) : null;
    final found = await _offerService.discoverHeldOfferMedia(
      recordId,
      ownerId: accountId,
      ids: listed.isNotEmpty ? listed : [if (shown != null) shown],
    );
    return FavoriteCardMedia.pick(found);
  }

  /// The media id of the card this screen shows for the Offer [recordId] —
  /// its saved copy or its last answer — when that card is [accountId]'s.
  String? _shownOfferMediaId(String recordId, String accountId) {
    final prefix = '$offerMediaCacheKeyPrefix$accountId:';
    for (final item in [..._allFavorites, ..._cachedFavorites]) {
      if (item.type != 'offers' || item.id != recordId) continue;
      final key = item.media?.cacheKey;
      if (key == null || !key.startsWith(prefix)) return null;
      final id = key.substring(prefix.length);
      return id.isEmpty || id.contains(':') ? null : id;
    }
    return null;
  }

  Future<void> _loadRequestsWithMetadata(List<FavoriteMetadata> requestMetadata,
      List<FavoriteItem> favorites) async {
    final requests = await _recordsOf(
      'requests',
      requestMetadata,
      favorites,
      _requestService.getRequestsByIds,
      (RequestModel request) => request.id,
    );
    if (requests == null || _disposed) return;
    for (final metadata in requestMetadata) {
      final request = requests[metadata.itemId];
      if (request == null) continue;
      favorites.add(FavoriteItem(
        id: metadata.itemId,
        type: 'requests',
        title: _getRequestTitle(request),
        subtitle: _getRequestSubtitle(request),
        addedAt: metadata.addedAt, // Use actual timestamp!
        originalData: request,
      ));
    }
  }

  Future<void> _loadOwnersWithMetadata(List<FavoriteMetadata> ownerMetadata,
      List<FavoriteItem> favorites) async {
    final owners = await _recordsOf(
      'owners',
      ownerMetadata,
      favorites,
      _ownerService.getOwnersByIds,
      (OwnerModel owner) => owner.id,
    );
    if (owners == null || _disposed) return;
    final loaded = <(FavoriteMetadata, OwnerModel)>[
      for (final metadata in ownerMetadata)
        if (owners[metadata.itemId] case final OwnerModel owner)
          (metadata, owner),
    ];

    // An Owner's row carries no media links; its photos and videos are
    // private and are resolved apart, a few Owners at a time.
    final media = await mapWithLimit(
      loaded,
      mediaReadsAtOnce,
      (entry) => _ownerCardMedia(entry.$2),
      stop: () => _disposed,
    );
    if (_disposed) return;

    for (var i = 0; i < loaded.length; i++) {
      final (metadata, owner) = loaded[i];
      favorites.add(FavoriteItem(
        id: metadata.itemId,
        type: 'owners',
        title: owner.name.isNotEmpty
            ? owner.name
            : _localization?.translate('propertyOwner') ?? 'Property Owner',
        subtitle: owner.typeOfProperties.isNotEmpty
            ? owner.typeOfProperties
            : _localization?.translate('propertyOwner') ?? 'Property Owner',
        imageUrl: media[i] == null && owner.mediaUrls.isNotEmpty
            ? owner.mediaUrls.first
            : null,
        media: media[i],
        addedAt: metadata.addedAt, // Use actual timestamp!
        originalData: owner,
      ));
    }
  }

  /// The photo (or video frame) an Owner's card shows: from the server's
  /// current list; when that cannot be read, from what this device holds. A
  /// failure only means the card shows its icon, never that the Owner is lost.
  Future<FavoriteCardMedia?> _ownerCardMedia(OwnerModel owner) async {
    final recordId = owner.id?.trim() ?? '';
    final accountId = _ownerService.currentOwnerId?.trim() ?? '';
    if (recordId.isEmpty || accountId.isEmpty) return null;
    try {
      final resolution = await _ownerService.resolveMedia(
        recordId: recordId,
        ownerId: accountId,
      );
      // No separate media stage (the Firebase backend): the row's own URLs.
      if (resolution == null) return null;
      return FavoriteCardMedia.pick(resolution.items);
    } catch (_) {
      try {
        return FavoriteCardMedia.pick(_ownerService.cachedMedia(recordId));
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _loadOfficesWithMetadata(List<FavoriteMetadata> officeMetadata,
      List<FavoriteItem> favorites) async {
    final offices = await _recordsOf(
      'offices',
      officeMetadata,
      favorites,
      _officeService.getOfficesByIds,
      (OfficeModel office) => office.id,
    );
    if (offices == null || _disposed) return;
    for (final metadata in officeMetadata) {
      final office = offices[metadata.itemId];
      if (office == null) continue;
      favorites.add(FavoriteItem(
        id: metadata.itemId,
        type: 'offices',
        title: office.officeName.isNotEmpty
            ? office.officeName
            : _localization?.translate('office') ?? 'Office',
        subtitle: office.managerName.isNotEmpty
            ? (_localization?.translate('favoritesManagerLabel') ??
                    'Manager: {name}')
                .replaceAll('{name}', office.managerName)
            : _localization?.translate('officeLocation') ?? 'Office Location',
        addedAt: metadata.addedAt, // Use actual timestamp!
        originalData: office,
      ));
    }
  }

  Future<void> _loadBrokersWithMetadata(List<FavoriteMetadata> brokerMetadata,
      List<FavoriteItem> favorites) async {
    final brokers = await _recordsOf(
      'brokers',
      brokerMetadata,
      favorites,
      _brokerService.getBrokersByIds,
      (BrokerModel broker) => broker.id,
    );
    if (brokers == null || _disposed) return;
    for (final metadata in brokerMetadata) {
      final broker = brokers[metadata.itemId];
      if (broker == null) continue;
      favorites.add(FavoriteItem(
        id: metadata.itemId,
        type: 'brokers',
        title: broker.name.isNotEmpty
            ? broker.name
            : _localization?.translate('brokers') ?? 'Broker',
        subtitle: _localization?.translate('favoritesBrokerSubtitle') ??
            'Real Estate Broker',
        addedAt: metadata.addedAt, // Use actual timestamp!
        originalData: broker,
      ));
    }
  }

  Future<void> _loadWatchmenWithMetadata(
      List<FavoriteMetadata> watchmenMetadata,
      List<FavoriteItem> favorites) async {
    final watchmen = await _recordsOf(
      'watchmen',
      watchmenMetadata,
      favorites,
      _watchmenService.getWatchmenByIds,
      (WatchmenModel watchman) => watchman.id,
    );
    if (watchmen == null || _disposed) return;
    for (final metadata in watchmenMetadata) {
      final watchman = watchmen[metadata.itemId];
      if (watchman == null) continue;
      favorites.add(FavoriteItem(
        id: metadata.itemId,
        type: 'watchmen',
        title: watchman.name.isNotEmpty
            ? watchman.name
            : _localization?.translate('watchmen') ?? 'Watchmen',
        subtitle: watchman.buildingName.isNotEmpty
            ? (_localization?.translate('favoritesBuildingLabel') ??
                    'Building: {name}')
                .replaceAll('{name}', watchman.buildingName)
            : _localization?.translate('favoritesSecuritySubtitle') ??
                'Security Guard',
        addedAt: metadata.addedAt, // Use actual timestamp!
        originalData: watchman,
      ));
    }
  }

  String _formatAmount(String rawValue, AppLocalizations localization) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    final currency = localization.translate('aed');
    final upper = normalized.toUpperCase();
    if (upper.endsWith('AED') || normalized.endsWith(currency)) {
      return normalized;
    }

    final hasLetters = RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(normalized);
    if (hasLetters) {
      return normalized;
    }

    return '$normalized $currency';
  }

  void _rebuildLocalizedFavorites() {
    final localization = _localization;
    if (localization == null) {
      return;
    }

    _allFavorites = _allFavorites.map(_mapLocalizedFavorite).toList();
    _cachedFavorites = _cachedFavorites.map(_mapLocalizedFavorite).toList();
    _applyFilter();
    _safeNotifyListeners();
  }

  FavoriteItem _mapLocalizedFavorite(FavoriteItem item) {
    final data = item.originalData;
    if (data is OfferModel) {
      return FavoriteItem(
        id: item.id,
        type: item.type,
        title: _getOfferTitle(data),
        subtitle: _getOfferSubtitle(data),
        imageUrl: item.imageUrl,
        media: item.media,
        addedAt: item.addedAt,
        originalData: data,
      );
    }

    if (data is RequestModel) {
      return FavoriteItem(
        id: item.id,
        type: item.type,
        title: _getRequestTitle(data),
        subtitle: _getRequestSubtitle(data),
        imageUrl: item.imageUrl,
        media: item.media,
        addedAt: item.addedAt,
        originalData: data,
      );
    }

    if (data is OwnerModel) {
      return FavoriteItem(
        id: item.id,
        type: item.type,
        title: data.name.isNotEmpty
            ? data.name
            : _localization?.translate('propertyOwner') ?? 'Property Owner',
        subtitle: data.typeOfProperties.isNotEmpty
            ? data.typeOfProperties
            : _localization?.translate('propertyOwner') ?? 'Property Owner',
        imageUrl: item.imageUrl,
        media: item.media,
        addedAt: item.addedAt,
        originalData: data,
      );
    }

    if (data is OfficeModel) {
      return FavoriteItem(
        id: item.id,
        type: item.type,
        title: data.officeName.isNotEmpty
            ? data.officeName
            : _localization?.translate('office') ?? 'Office',
        subtitle: data.managerName.isNotEmpty
            ? (_localization?.translate('favoritesManagerLabel') ??
                    'Manager: {name}')
                .replaceAll('{name}', data.managerName)
            : _localization?.translate('officeLocation') ?? 'Office Location',
        imageUrl: item.imageUrl,
        media: item.media,
        addedAt: item.addedAt,
        originalData: data,
      );
    }

    if (data is BrokerModel) {
      return FavoriteItem(
        id: item.id,
        type: item.type,
        title: data.name.isNotEmpty
            ? data.name
            : _localization?.translate('brokerLabel') ?? 'Broker',
        subtitle: _localization?.translate('favoritesBrokerSubtitle') ??
            'Real Estate Broker',
        imageUrl: item.imageUrl,
        media: item.media,
        addedAt: item.addedAt,
        originalData: data,
      );
    }

    if (data is WatchmenModel) {
      return FavoriteItem(
        id: item.id,
        type: item.type,
        title: data.name.isNotEmpty
            ? data.name
            : _localization?.translate('watchmen') ?? 'Watchmen',
        subtitle: data.buildingName.isNotEmpty
            ? (_localization?.translate('favoritesBuildingLabel') ??
                    'Building: {name}')
                .replaceAll('{name}', data.buildingName)
            : _localization?.translate('favoritesSecuritySubtitle') ??
                'Security Guard',
        imageUrl: item.imageUrl,
        media: item.media,
        addedAt: item.addedAt,
        originalData: data,
      );
    }

    return FavoriteItem(
      id: item.id,
      type: item.type,
      title: _localizeFallbackTitle(item),
      subtitle: _localizeFallbackSubtitle(item),
      imageUrl: item.imageUrl,
      media: item.media,
      addedAt: item.addedAt,
      originalData: item.originalData,
    );
  }

  String _localizeFallbackTitle(FavoriteItem item) {
    final localization = _localization;
    if (localization == null) {
      return item.title;
    }

    final trimmed = item.title.trim();
    switch (trimmed) {
      case 'Rent Offer':
        return localization.translate('rentOffer');
      case 'Sale Offer':
        return localization.translate('saleOffer');
      case 'Rent Request':
        return localization.translate('rentRequest');
      case 'Purchase Request':
        return localization.translate('purchaseRequest');
      case 'Property Owner':
        return localization.translate('propertyOwner');
      case 'Office':
        return localization.translate('office');
      case 'Broker':
        return localization.translate('brokerLabel');
      case 'Watchmen':
        return localization.translate('watchmen');
      default:
        break;
    }

    if (trimmed.isEmpty) {
      switch (item.type) {
        case 'offers':
          return localization.translate('offers');
        case 'requests':
          return localization.translate('requests');
        case 'owners':
          return localization.translate('propertyOwner');
        case 'offices':
          return localization.translate('office');
        case 'brokers':
          return localization.translate('brokerLabel');
        case 'watchmen':
          return localization.translate('watchmen');
      }
    }

    return trimmed;
  }

  String _localizeFallbackSubtitle(FavoriteItem item) {
    final localization = _localization;
    if (localization == null) {
      return item.subtitle;
    }

    final trimmed = item.subtitle.trim();

    if (trimmed.startsWith('Manager:')) {
      final name = trimmed.substring('Manager:'.length).trim();
      return localization
          .translate('favoritesManagerLabel')
          .replaceAll('{name}', name);
    }

    if (trimmed == 'Office Location') {
      return localization.translate('officeLocation');
    }

    if (trimmed == 'Real Estate Broker') {
      return localization.translate('favoritesBrokerSubtitle');
    }

    if (trimmed == 'Security Guard') {
      return localization.translate('favoritesSecuritySubtitle');
    }

    if (trimmed == 'Property Owner') {
      return localization.translate('propertyOwner');
    }

    if (trimmed.startsWith('Building:')) {
      final name = trimmed.substring('Building:'.length).trim();
      return localization
          .translate('favoritesBuildingLabel')
          .replaceAll('{name}', name);
    }

    if (trimmed.startsWith('From ')) {
      final amount = trimmed.substring('From '.length).trim();
      return localization
          .translate('favoritesPriceFrom')
          .replaceAll('{amount}', _formatAmount(amount, localization));
    }

    if (trimmed.startsWith('Up to ')) {
      final amount = trimmed.substring('Up to '.length).trim();
      return localization
          .translate('favoritesPriceUpTo')
          .replaceAll('{amount}', _formatAmount(amount, localization));
    }

    final currencyValue = localization.translate('aed');
    final rangePattern = r'^(.+)\s-\s(.+)\s(?:AED|__CURRENCY__)$'
        .replaceFirst('__CURRENCY__', RegExp.escape(currencyValue));
    final rangeRegex = RegExp(
      rangePattern,
      caseSensitive: false,
    );
    final match = rangeRegex.firstMatch(trimmed);
    if (match != null) {
      final min = match.group(1)!.trim();
      final max = match.group(2)!.trim();
      return localization
          .translate('favoritesPriceRange')
          .replaceAll('{min}', _formatAmount(min, localization))
          .replaceAll('{max}', _formatAmount(max, localization));
    }

    return trimmed;
  }
}
