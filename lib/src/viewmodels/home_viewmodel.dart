import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../data/models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../repositories/repository_provider.dart';
import '../data/models/filter_model.dart';
import '../data/models/grid_item_model.dart';
import '../data/models/unified_item_model.dart';
import '../services/ScreenServices/watchmen_service.dart';
import '../services/ScreenServices/broker_service.dart';
import '../services/ScreenServices/offer_service.dart';
import '../services/ScreenServices/office_service.dart';
import '../services/ScreenServices/owner_service.dart';
import '../services/ScreenServices/request_service.dart';
import '../services/count_cache_service.dart';
import '../config/supabase_config.dart';
import '../services/supabase_home_counts_service.dart';
import '../services/core_entity_mutation_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeViewModel extends ChangeNotifier {
  int selectedIndex = 0;

  // Services
  final WatchmenService _watchmenService = WatchmenService();
  final BrokerService _brokerService = BrokerService();
  final OfferService _offerService = OfferService();
  final OfficeService _officeService = OfficeService();
  final OwnerService _ownerService = OwnerService();
  final RequestService _requestService = RequestService();
  final QuotationService _quotationService = QuotationService();
  final CountCacheService _countCache = CountCacheService.instance;
  final SupabaseHomeCountsService _supabaseHomeCountsService =
      SupabaseHomeCountsService();

  // Track if streams have been initialized
  bool _streamsInitialized = false;

  // Dynamic counts - initialized from cache for instant display
  int _watchmenCount = 0;
  int _brokersCount = 0;
  int _offersCount = 0;
  int _officesCount = 0;
  int _ownersCount = 0;
  int _requestedCount = 0;
  int _quotationCount = 0;

  // Filtered counts for display
  int _filteredWatchmenCount = 0;
  int _filteredBrokersCount = 0;
  int _filteredOffersCount = 0;
  int _filteredOfficesCount = 0;
  int _filteredOwnersCount = 0;
  int _filteredRequestedCount = 0;
  int _filteredQuotationCount = 0;

  // Filtered items for display
  List<UnifiedItemModel> _filteredItems = [];

  // Loading state for filter application
  bool _isFilterLoading = false;

  // Single combined stream subscription for efficiency
  StreamSubscription? _combinedSubscription;
  StreamSubscription? _authSubscription;
  StreamSubscription<AuthState>? _supabaseAuthSubscription;
  StreamSubscription<void>? _coreMutationSubscription;
  // Filter subscriptions for managing filter-specific streams
  List<StreamSubscription> _filterSubscriptions = [];
  Timer? _updateTimer;

  final List<FilterModel> filters = [
    FilterModel(label: 'Recently Added', labelKey: 'recentlyAdded'),
    FilterModel(label: 'Less Price', labelKey: 'lessPrice'),
    FilterModel(label: 'This Week', labelKey: 'thisWeek'),
  ];

  List<GridItemModel> get items {
    // Use filtered counts if a filter is selected, otherwise use normal counts
    final bool hasSelectedFilter = filters.any((filter) => filter.selected);

    return [
      GridItemModel(
          asset: 'assets/icons/requested-svg.svg',
          label: 'Requested',
          labelKey: 'requested',
          count: hasSelectedFilter ? _filteredRequestedCount : _requestedCount),
      GridItemModel(
          asset: 'assets/icons/offers-svg.svg',
          label: 'Offers',
          labelKey: 'offers',
          count: hasSelectedFilter ? _filteredOffersCount : _offersCount),
      GridItemModel(
          asset: 'assets/icons/owners-svg.svg',
          label: 'Owners',
          labelKey: 'owners',
          count: hasSelectedFilter ? _filteredOwnersCount : _ownersCount),
      GridItemModel(
          asset: 'assets/icons/offices-svg.svg',
          label: 'Offices',
          labelKey: 'offices',
          count: hasSelectedFilter ? _filteredOfficesCount : _officesCount),
      GridItemModel(
          asset: 'assets/icons/brokers-svg.svg',
          label: 'Brokers',
          labelKey: 'brokers',
          count: hasSelectedFilter ? _filteredBrokersCount : _brokersCount),
      GridItemModel(
          asset: 'assets/icons/watchman-svg.svg',
          label: 'Watchmen',
          labelKey: 'watchmen',
          count: hasSelectedFilter ? _filteredWatchmenCount : _watchmenCount),
      GridItemModel(
          asset: 'assets/icons/quotation-svg.svg',
          label: 'Quotation',
          labelKey: 'quotation',
          count: hasSelectedFilter ? _filteredQuotationCount : _quotationCount),
      GridItemModel(
          asset: 'assets/icons/toolkit-svg.svg',
          label: 'Toolkit',
          labelKey: 'toolkit'),
      GridItemModel(
          asset: 'assets/icons/Map.svg', label: 'Map', labelKey: 'map'),
    ];
  }

  final AuthRepository _authRepository;

  UserModel? get currentUser => _authRepository.currentUser;
  String? get currentUserId => _authRepository.currentUserId;

  HomeViewModel({AuthRepository? authRepository})
      : _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository {
    _loadCachedCountsInstantly();
    // Delay stream initialization until user is authenticated
    _initializeStreamsWhenReady();
  }

  /// Load cached counts instantly from memory - no async delays
  void _loadCachedCountsInstantly() {
    final cachedCounts = _countCache.getAllCachedCounts();
    _watchmenCount = cachedCounts['watchmen'] ?? 0;
    _brokersCount = cachedCounts['brokers'] ?? 0;
    _offersCount = cachedCounts['offers'] ?? 0;
    _officesCount = cachedCounts['offices'] ?? 0;
    _ownersCount = cachedCounts['owners'] ?? 0;
    _requestedCount = cachedCounts['requested'] ?? 0;
    _quotationCount = cachedCounts['quotation'] ?? 0;

    // Don't call notifyListeners here - let the UI render immediately with cached values
  }

  /// Initialize streams only when Auth is ready
  void _initializeStreamsWhenReady() {
    if (_streamsInitialized) return;

    if (SupabaseConfig.useSupabaseAuth) {
      _initializeSupabaseCountsWhenReady();
      return;
    }

    // Check if user is already authenticated
    final currentUser = _authRepository.currentUser;
    if (currentUser != null) {
      _initializeLiveStreams();
      _streamsInitialized = true;
      return;
    }

    // Otherwise, wait for auth state change
    _authSubscription ??= _authRepository.authStateChanges.listen(
      (user) {
        if (user != null && !_streamsInitialized) {
          _initializeLiveStreams();
          _streamsInitialized = true;
        } else if (user == null && _streamsInitialized) {
          _resetCountsForSignedOutUser();
          _streamsInitialized = false;
        }
      },
      // The repository forwards auth-stream errors; an authoritative sign-out
      // still arrives as a null user, so there is nothing to do here but
      // refuse to crash.
      onError: (Object _, StackTrace __) {},
    );
  }

  void _initializeSupabaseCountsWhenReady() {
    final client = Supabase.instance.client;

    if (client.auth.currentSession != null) {
      unawaited(_loadSupabaseCounts());
    }

    _supabaseAuthSubscription ??= client.auth.onAuthStateChange.listen(
      (data) {
        if (data.session != null) {
          unawaited(_loadSupabaseCounts());
        } else {
          _resetCountsForSignedOutUser();
        }
      },
      // Supabase republishes auth failures on this stream — a failed token
      // refresh, and every `AuthException` its deep-link observer catches.
      // Without this handler such an error becomes an unhandled async error
      // that crashes out of a screen that only counts rows.
      onError: (Object _, StackTrace __) {},
    );
    _coreMutationSubscription ??=
        CoreEntityMutationNotifier.changes.listen((_) {
      unawaited(_loadSupabaseCounts());
    });
  }

  Future<void> _loadSupabaseCounts() async {
    try {
      final counts = await _supabaseHomeCountsService.getCounts(fallback: {
        'watchmen': _watchmenCount,
        'brokers': _brokersCount,
        'offers': _offersCount,
        'offices': _officesCount,
        'owners': _ownersCount,
        'requested': _requestedCount,
        'quotation': _quotationCount,
      });
      _handleCombinedUpdate(counts);
    } catch (error, stackTrace) {
      debugPrint('Supabase Home count refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Keep the last cached counts if the network is temporarily unavailable.
    }
  }

  void _resetCountsForSignedOutUser() {
    _watchmenCount = 0;
    _brokersCount = 0;
    _offersCount = 0;
    _officesCount = 0;
    _ownersCount = 0;
    _requestedCount = 0;
    _quotationCount = 0;
    _clearFilteredData();
    notifyListeners();
  }

  /// Initialize live streams with combined subscription for efficiency
  void _initializeLiveStreams() {
    // Combine all streams and debounce updates to prevent excessive rebuilds
    _combinedSubscription = _createCombinedStream().listen(
      _handleCombinedUpdate,
      onError: (error) {
        // Continue with cached values on error
      },
    );
  }

  /// Create a single combined stream from all services
  Stream<Map<String, int>> _createCombinedStream() {
    return Stream.periodic(const Duration(seconds: 2), (_) {
      // Use periodic to debounce rapid Firestore updates
      return null;
    }).asyncMap((_) async {
      // Get latest data from all services concurrently
      final results = await Future.wait([
        _watchmenService.getUserWatchmen().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
        _brokerService.getUserBrokers().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
        _offerService.getUserOffers().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
        _officeService.getUserOffices().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
        _ownerService.getUserOwners().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
        _requestService.getUserRequests().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
        _quotationService.getUserQuotations().first.timeout(
              const Duration(seconds: 5),
              onTimeout: () => [],
            ),
      ]);

      return {
        'watchmen': results[0].length,
        'brokers': results[1].length,
        'offers': results[2].length,
        'offices': results[3].length,
        'owners': results[4].length,
        'requested': results[5].length,
        'quotation': results[6].length,
      };
    }).distinct((previous, next) {
      // Only emit if counts actually changed
      return previous['watchmen'] == next['watchmen'] &&
          previous['brokers'] == next['brokers'] &&
          previous['offers'] == next['offers'] &&
          previous['offices'] == next['offices'] &&
          previous['owners'] == next['owners'] &&
          previous['requested'] == next['requested'] &&
          previous['quotation'] == next['quotation'];
    });
  }

  /// Handle combined stream updates with debouncing
  void _handleCombinedUpdate(Map<String, int> newCounts) {
    // Cancel previous timer to debounce rapid updates
    _updateTimer?.cancel();

    _updateTimer = Timer(const Duration(milliseconds: 100), () {
      bool hasChanges = false;

      // Check if any counts actually changed
      if (_watchmenCount != newCounts['watchmen']) {
        _watchmenCount = newCounts['watchmen']!;
        hasChanges = true;
      }
      if (_brokersCount != newCounts['brokers']) {
        _brokersCount = newCounts['brokers']!;
        hasChanges = true;
      }
      if (_offersCount != newCounts['offers']) {
        _offersCount = newCounts['offers']!;
        hasChanges = true;
      }
      if (_officesCount != newCounts['offices']) {
        _officesCount = newCounts['offices']!;
        hasChanges = true;
      }
      if (_ownersCount != newCounts['owners']) {
        _ownersCount = newCounts['owners']!;
        hasChanges = true;
      }
      if (_requestedCount != newCounts['requested']) {
        _requestedCount = newCounts['requested']!;
        hasChanges = true;
      }
      if (_quotationCount != newCounts['quotation']) {
        _quotationCount = newCounts['quotation']!;
        hasChanges = true;
      }

      if (hasChanges) {
        // Update cache with new counts
        _countCache.updateCachedCounts(newCounts);

        // Notify UI only once with all changes
        notifyListeners();
      }
    });
  }

  Future<void> refreshCounts() async {
    if (SupabaseConfig.useSupabaseAuth) {
      _clearFilteredData();
      for (final filter in filters) {
        filter.selected = false;
      }
      await _loadSupabaseCounts();
      notifyListeners();
      return;
    }

    // Cancel existing subscription
    _combinedSubscription?.cancel();
    _updateTimer?.cancel();

    // Clear filtered data
    _clearFilteredData();

    // Clear all filter selections
    for (final filter in filters) {
      filter.selected = false;
    }

    // Force reload from cache first, then reinitialize streams
    _loadCachedCountsInstantly();
    _initializeLiveStreams();

    notifyListeners();
  }

  void toggleFilter(int index) {
    // Home-domain data is still backed by Firebase at this migration stage.
    // Keep filters inert in Supabase Auth test mode rather than crossing
    // identities/backends.
    if (SupabaseConfig.useSupabaseAuth) {
      return;
    }

    // If the tapped filter is already selected, deselect it
    if (filters[index].selected) {
      filters[index].selected = false;
      _isFilterLoading = false;
      // Reset to show all items
      _clearFilteredData();
      notifyListeners();
    } else {
      // Set loading state immediately to prevent empty state flash
      _isFilterLoading = true;
      // Deselect all other filters
      for (int i = 0; i < filters.length; i++) {
        filters[i].selected = i == index;
      }
      // Select the tapped filter
      filters[index].selected = true;
      // Notify listeners FIRST to show loading state immediately
      notifyListeners();
      // Then apply the selected filter (async operation)
      _applyFilter(filters[index]);
    }
  }

  /// Clear all filter selections and return to showing all items
  /// This method is called when user navigates away from home screen
  void clearAllFilters() {
    bool hadSelectedFilter = filters.any((filter) => filter.selected);

    if (hadSelectedFilter) {
      // Deselect all filters
      for (final filter in filters) {
        filter.selected = false;
      }

      // Clear filtered data and reset to show all items
      _isFilterLoading = false;
      _clearFilteredData();

      notifyListeners();
    }
  }

  // Clear filtered data and show all items
  void _clearFilteredData() {
    // Cancel filter subscriptions
    for (final subscription in _filterSubscriptions) {
      subscription.cancel();
    }
    _filterSubscriptions.clear();

    _filteredItems.clear();
    _filteredWatchmenCount = 0;
    _filteredBrokersCount = 0;
    _filteredOffersCount = 0;
    _filteredOfficesCount = 0;
    _filteredOwnersCount = 0;
    _filteredRequestedCount = 0;
    _filteredQuotationCount = 0;
  }

  // Apply the selected filter
  void _applyFilter(FilterModel filter) {
    switch (filter.labelKey) {
      case 'recentlyAdded':
        _applyRecentlyAddedFilter();
        break;
      case 'lessPrice':
        _applyLessPriceFilter();
        break;
      case 'thisWeek':
        _applyThisWeekFilter();
        break;
      default:
    }
  }

  // Filter for items added in the last 12 hours
  void _applyRecentlyAddedFilter() {
    _clearFilteredData();
    final now = DateTime.now();

    // Get recent items from all services
    _filterRecentItems(now);
  }

  // Filter for items with lowest prices (only applies to offers and requests)
  void _applyLessPriceFilter() {
    _clearFilteredData();

    // Get offers and requests, sort by price, take lowest 6
    _filterLowPriceItems();
  }

  // Filter for items added in the last week
  void _applyThisWeekFilter() {
    _clearFilteredData();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    // Get items from the last week
    _filterWeekItems(weekAgo);
  }

  // Helper method to filter recent items (last 12 hours)
  void _filterRecentItems(DateTime now) {
    final twelveHoursAgo = now.subtract(const Duration(hours: 12));

    // Listen to all services and filter by date
    _subscribeToFilteredData((items) {
      return items
          .where((item) => item.createdAt.isAfter(twelveHoursAgo))
          .toList();
    });
  }

  // Helper method to filter low price items (lowest 6 items with prices)
  void _filterLowPriceItems() {
    _subscribeToFilteredData((items) {
      // Filter items that have prices (offers and requests)
      final itemsWithPrices = items
          .where((item) => item.averagePrice != null && item.averagePrice! > 0)
          .toList();

      // Sort by average price and take the lowest 6
      itemsWithPrices.sort((a, b) => (a.averagePrice ?? double.infinity)
          .compareTo(b.averagePrice ?? double.infinity));

      return itemsWithPrices.take(6).toList();
    });
  }

  // Helper method to filter items from this week
  void _filterWeekItems(DateTime weekAgo) {
    _subscribeToFilteredData((items) {
      return items.where((item) => item.createdAt.isAfter(weekAgo)).toList();
    });
  }

  // Subscribe to all data sources and apply filter function
  void _subscribeToFilteredData(
      List<UnifiedItemModel> Function(List<UnifiedItemModel>) filterFunction) {
    // Cancel existing filter subscriptions
    _clearFilteredData();

    // Combine streams from all services
    final List<Stream<List<UnifiedItemModel>>> streams = [
      _requestService.getUserRequests().map((requests) =>
          requests.map((r) => UnifiedItemModel.fromRequest(r)).toList()),
      _offerService.getUserOffers().map((offers) =>
          offers.map((o) => UnifiedItemModel.fromOffer(o)).toList()),
      _brokerService.getUserBrokers().map((brokers) =>
          brokers.map((b) => UnifiedItemModel.fromBroker(b)).toList()),
      _ownerService.getUserOwners().map((owners) =>
          owners.map((o) => UnifiedItemModel.fromOwner(o)).toList()),
      _officeService.getUserOffices().map((offices) =>
          offices.map((o) => UnifiedItemModel.fromOffice(o)).toList()),
      _watchmenService.getUserWatchmen().map((watchmen) =>
          watchmen.map((w) => UnifiedItemModel.fromWatchmen(w)).toList()),
    ];

    // Combine all streams and apply filter

    // Create a custom stream combiner
    _subscribeToMultipleStreams(streams, (allItems) {
      final filteredItems = filterFunction(allItems);
      _updateFilteredCounts(filteredItems);
      notifyListeners();
    });
  }

  // Helper to subscribe to multiple streams
  void _subscribeToMultipleStreams(
    List<Stream<List<UnifiedItemModel>>> streams,
    void Function(List<UnifiedItemModel>) onUpdate,
  ) {
    // Cancel existing filter subscriptions
    for (final subscription in _filterSubscriptions) {
      subscription.cancel();
    }
    _filterSubscriptions.clear();

    final List<List<UnifiedItemModel>> currentData =
        List.generate(streams.length, (_) => []);

    for (int i = 0; i < streams.length; i++) {
      final subscription = streams[i].listen((data) {
        currentData[i] = data;

        // Combine all current data and update
        final allItems = currentData.expand((list) => list).toList();
        onUpdate(allItems);
      });
      _filterSubscriptions.add(subscription);
    }
  }

  // Update filtered counts based on filtered items
  void _updateFilteredCounts(List<UnifiedItemModel> filteredItems) {
    // Store the filtered items for display
    _filteredItems = filteredItems;
    // Filter data is now ready, set loading to false
    _isFilterLoading = false;

    _filteredRequestedCount =
        filteredItems.where((item) => item.type == ItemType.request).length;
    _filteredOffersCount =
        filteredItems.where((item) => item.type == ItemType.offer).length;
    _filteredBrokersCount =
        filteredItems.where((item) => item.type == ItemType.broker).length;
    _filteredOwnersCount =
        filteredItems.where((item) => item.type == ItemType.owner).length;
    _filteredOfficesCount =
        filteredItems.where((item) => item.type == ItemType.office).length;
    _filteredWatchmenCount =
        filteredItems.where((item) => item.type == ItemType.watchmen).length;
    _filteredQuotationCount =
        filteredItems.where((item) => item.type == ItemType.quotation).length;
  }

  // Getter for filtered items (for potential use in UI)
  List<UnifiedItemModel> get filteredItems => _filteredItems;

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

  bool get isFilterLoading => _isFilterLoading;

  void selectNav(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel subscriptions and timers to prevent memory leaks
    _combinedSubscription?.cancel();
    _authSubscription?.cancel();
    _supabaseAuthSubscription?.cancel();
    _coreMutationSubscription?.cancel();
    for (final subscription in _filterSubscriptions) {
      subscription.cancel();
    }
    _filterSubscriptions.clear();
    _updateTimer?.cancel();
    super.dispose();
  }
}
