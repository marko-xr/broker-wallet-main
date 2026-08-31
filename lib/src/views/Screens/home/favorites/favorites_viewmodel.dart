import 'package:flutter/material.dart';
import '../../../../data/models/filter_model.dart';
import 'favorites_item_model.dart';
import '../../../../data/models/ScreensModel/offers_model.dart';
import '../../../../data/models/ScreensModel/request_model.dart';
import '../../../../data/models/ScreensModel/owners_model.dart';
import '../../../../data/models/ScreensModel/offices_model.dart';
import '../../../../data/models/ScreensModel/brokers_model.dart';
import '../../../../data/models/ScreensModel/watchmen_model.dart';
import 'favorites_service.dart';
import '../../../../services/ScreenServices/offer_service.dart';
import '../../../../services/ScreenServices/request_service.dart';
import '../../../../services/ScreenServices/owner_service.dart';
import '../../../../services/ScreenServices/office_service.dart';
import '../../../../services/ScreenServices/broker_service.dart';
import '../../../../services/ScreenServices/watchmen_service.dart';
import '../../../../services/optimistic_favorites_service.dart';
import '../../../../common/localization/localization_delegate.dart';
import 'dart:async';

class FavoritesViewModel extends ChangeNotifier {
  final OptimisticFavoritesService? _optimisticFavoritesService;
  final FavoriteService _favoriteService = FavoriteService();
  final OfferService _offerService = OfferService();
  final RequestService _requestService = RequestService();
  final OwnerService _ownerService = OwnerService();
  final OfficeService _officeService = OfficeService();
  final BrokerService _brokerService = BrokerService();
  final WatchmenService _watchmenService = WatchmenService();
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
  String? _error;
  bool _disposed = false;
  bool _cacheInitialized = false;

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

  FavoritesViewModel({OptimisticFavoritesService? optimisticFavoritesService})
      : _optimisticFavoritesService = optimisticFavoritesService {
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

    try {
      // Don't show loading state - this should be seamless
      final favoriteMetadata =
          await _favoriteService.getAllFavoritesWithMetadata();

      if (_disposed) return;

      // If no favorites, clear everything and update UI
      if (favoriteMetadata.values.every((metaList) => metaList.isEmpty)) {
        _allFavorites = [];
        _cachedFavorites = [];
        _applyFilter();
        _safeNotifyListeners();
        return;
      }

      // Load favorites with limited concurrency for speed
      final favorites =
          await _loadFavoritesWithLimitedConcurrency(favoriteMetadata);

      if (!_disposed) {
        favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        _allFavorites = favorites;
        _cachedFavorites = favorites;
        _applyFilter();

        // Update optimistic service state to keep it in sync
        _syncOptimisticServiceWithLoadedFavorites(favorites);

        _safeNotifyListeners();

        // Update cache in background
        _favoriteService.cacheFavorites(favorites);
      }
    } catch (e) {
      // Don't show error to user - this is a background operation
      // Debug log suppressed: Immediate favorites refresh failed: $e
    }
  }

  void _syncOptimisticServiceWithLoadedFavorites(List<FavoriteItem> favorites) {
    if (_optimisticFavoritesService == null) return;

    // Group favorites by type for batch updates
    final Map<String, List<String>> favoritesByType = {};
    for (final favorite in favorites) {
      favoritesByType.putIfAbsent(favorite.type, () => []).add(favorite.id);
    }

    // Update optimistic service state
    _optimisticFavoritesService.updateLoadedFavorites(favoritesByType);
  }

  void _initializeAndLoadFavorites() {
    // Load cached data synchronously if available
    _loadCachedFavoritesSync();

    // Initialize cache and load fresh data asynchronously
    _initializeCacheAsync();

    // If no cached data and no loading state, load fresh data immediately
    if (_cachedFavorites.isEmpty && !_isLoading) {
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

  Future<void> _initializeCacheAsync() async {
    try {
      // Ensure authentication is ready before proceeding
      await _favoriteService.waitForAuthReady();

      // Initialize cache first
      if (!_cacheInitialized) {
        await _initializeCache();
      }

      // Always load fresh data to ensure we have the latest
      // If we have cached data, this will happen in background
      // If we don't have cached data, this will show the loading state
      await loadFavorites();
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
    if (_disposed) return;

    // Ensure authentication is ready before proceeding
    await _favoriteService.waitForAuthReady();

    // Set loading state only if we truly have no data
    if (_cachedFavorites.isEmpty) {
      _isLoading = true;
      _error = null;
      _safeNotifyListeners();
    }

    try {
      // Get favorite metadata (IDs with timestamps) from Firestore
      final favoriteMetadata =
          await _favoriteService.getAllFavoritesWithMetadata();

      if (_disposed) return;

      // If no favorites, update state and return
      if (favoriteMetadata.values.every((metaList) => metaList.isEmpty)) {
        _allFavorites = [];
        _cachedFavorites = [];
        _applyFilter();
        _safeNotifyListeners();
        return;
      }

      // Load favorites in parallel with limited concurrency
      final favorites =
          await _loadFavoritesWithLimitedConcurrency(favoriteMetadata);

      if (!_disposed) {
        favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        _allFavorites = favorites;
        _cachedFavorites = favorites; // Also update cached for display
        _applyFilter();

        // Cache the data for future instant loads
        await _favoriteService.cacheFavorites(favorites);

        // Update optimistic service state to keep it in sync
        _syncOptimisticServiceWithLoadedFavorites(favorites);

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
    if (_disposed) return;

    // Don't set loading state if we already have cached data
    if (_cachedFavorites.isEmpty) {
      _isLoading = true;
      _error = null;
      _safeNotifyListeners();
    }

    await _loadFreshFavorites();
  }

  Future<void> _loadFreshFavorites() async {
    if (_disposed) return;

    try {
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
      if (!_disposed) {
        favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        _allFavorites = favorites;
        _applyFilter();

        // Update optimistic service state to keep it in sync
        _syncOptimisticServiceWithLoadedFavorites(favorites);

        // Cache the fresh data for future instant loads
        await _favoriteService.cacheFavorites(favorites);

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
    if (_disposed) return;

    _isRefreshing = true;
    _safeNotifyListeners();

    await _loadFreshFavorites();
  }

  Future<void> removeFavorite(FavoriteItem favorite) async {
    if (_disposed) return;

    try {
      // Remove from Firestore
      await _favoriteService.removeFromFavorites(favorite.id, favorite.type);

      // Immediately remove from local lists
      _allFavorites.removeWhere(
          (item) => item.id == favorite.id && item.type == favorite.type);
      _cachedFavorites.removeWhere(
          (item) => item.id == favorite.id && item.type == favorite.type);

      // Update filtered favorites
      _applyFilter();

      // Update cache
      await _favoriteService.cacheFavorites(_allFavorites);

      _safeNotifyListeners();
    } catch (e) {
      // Optionally show error message to user
    }
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // New methods that use metadata to preserve timestamps
  Future<void> _loadOffersWithMetadata(List<FavoriteMetadata> offerMetadata,
      List<FavoriteItem> favorites) async {
    for (final metadata in offerMetadata) {
      if (_disposed) return;

      try {
        final offer = await _offerService.getOffer(metadata.itemId);
        if (offer != null && !_disposed) {
          favorites.add(FavoriteItem(
            id: metadata.itemId,
            type: 'offers',
            title: _getOfferTitle(offer),
            subtitle: _getOfferSubtitle(offer),
            imageUrl: offer.mediaUrls.isNotEmpty ? offer.mediaUrls.first : null,
            addedAt: metadata.addedAt, // Use actual timestamp!
            originalData: offer,
          ));
        }
      } catch (e) {
        // Debug log suppressed: Error loading offer ${metadata.itemId}: $e
      }
    }
  }

  Future<void> _loadRequestsWithMetadata(List<FavoriteMetadata> requestMetadata,
      List<FavoriteItem> favorites) async {
    for (final metadata in requestMetadata) {
      if (_disposed) return;

      try {
        final request = await _requestService.getRequest(metadata.itemId);
        if (request != null && !_disposed) {
          favorites.add(FavoriteItem(
            id: metadata.itemId,
            type: 'requests',
            title: _getRequestTitle(request),
            subtitle: _getRequestSubtitle(request),
            addedAt: metadata.addedAt, // Use actual timestamp!
            originalData: request,
          ));
        }
      } catch (e) {
        // Debug log suppressed: Error loading request ${metadata.itemId}: $e
      }
    }
  }

  Future<void> _loadOwnersWithMetadata(List<FavoriteMetadata> ownerMetadata,
      List<FavoriteItem> favorites) async {
    for (final metadata in ownerMetadata) {
      if (_disposed) return;

      try {
        final owner = await _ownerService.getOwner(metadata.itemId);
        if (owner != null && !_disposed) {
          favorites.add(FavoriteItem(
            id: metadata.itemId,
            type: 'owners',
            title: owner.name.isNotEmpty
                ? owner.name
                : _localization?.translate('propertyOwner') ?? 'Property Owner',
            subtitle: owner.typeOfProperties.isNotEmpty
                ? owner.typeOfProperties
                : _localization?.translate('propertyOwner') ?? 'Property Owner',
            imageUrl: owner.mediaUrls.isNotEmpty ? owner.mediaUrls.first : null,
            addedAt: metadata.addedAt, // Use actual timestamp!
            originalData: owner,
          ));
        }
      } catch (e) {
        // Debug log suppressed: Error loading owner ${metadata.itemId}: $e
      }
    }
  }

  Future<void> _loadOfficesWithMetadata(List<FavoriteMetadata> officeMetadata,
      List<FavoriteItem> favorites) async {
    for (final metadata in officeMetadata) {
      if (_disposed) return;

      try {
        final office = await _officeService.getOffice(metadata.itemId);
        if (office != null && !_disposed) {
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
                : _localization?.translate('officeLocation') ??
                    'Office Location',
            addedAt: metadata.addedAt, // Use actual timestamp!
            originalData: office,
          ));
        }
      } catch (e) {
        // Debug log suppressed: Error loading office ${metadata.itemId}: $e
      }
    }
  }

  Future<void> _loadBrokersWithMetadata(List<FavoriteMetadata> brokerMetadata,
      List<FavoriteItem> favorites) async {
    for (final metadata in brokerMetadata) {
      if (_disposed) return;

      try {
        final broker = await _brokerService.getBroker(metadata.itemId);
        if (broker != null && !_disposed) {
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
      } catch (e) {
        // Debug log suppressed: Error loading broker ${metadata.itemId}: $e
      }
    }
  }

  Future<void> _loadWatchmenWithMetadata(
      List<FavoriteMetadata> watchmenMetadata,
      List<FavoriteItem> favorites) async {
    for (final metadata in watchmenMetadata) {
      if (_disposed) return;

      try {
        final watchmen = await _watchmenService.getWatchmen(metadata.itemId);
        if (watchmen != null && !_disposed) {
          favorites.add(FavoriteItem(
            id: metadata.itemId,
            type: 'watchmen',
            title: watchmen.name.isNotEmpty
                ? watchmen.name
                : _localization?.translate('watchmen') ?? 'Watchmen',
            subtitle: watchmen.buildingName.isNotEmpty
                ? (_localization?.translate('favoritesBuildingLabel') ??
                        'Building: {name}')
                    .replaceAll('{name}', watchmen.buildingName)
                : _localization?.translate('favoritesSecuritySubtitle') ??
                    'Security Guard',
            addedAt: metadata.addedAt, // Use actual timestamp!
            originalData: watchmen,
          ));
        }
      } catch (e) {
        // Debug log suppressed: Error loading watchman ${metadata.itemId}: $e
      }
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
