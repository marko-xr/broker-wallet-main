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
import '../services/list_session_check.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_filter_controller.dart';
import 'home_filter_data_source.dart';
import 'home_filter_errors.dart';

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
  final CountCacheService _countCache;
  final SupabaseHomeCountsService _supabaseHomeCountsService =
      SupabaseHomeCountsService();
  final Future<Map<String, int>> Function(Map<String, int> fallback)?
      _readCountsOverride;
  final Stream<AuthState>? _authStateChangesOverride;
  // The existing session authority, for zeros that may come from a session
  // the database has replaced (its gate filters rows, it does not fail).
  final Future<bool>? Function(String? session) _confirmSession;
  final String? Function() _sessionNow;

  // Track if streams have been initialized
  bool _streamsInitialized = false;
  bool _disposed = false;

  // The account whose counts are held below (its Supabase user id), or null
  // when nobody is signed in. Counts are never shown for any other account.
  String? _countsAccountId;
  // Changes whenever the counts' account changes or the user signs out, so a
  // read that was started before can no longer change what is shown.
  int _countsEpoch = 0;

  // Dynamic counts - initialized from cache for instant display
  int _watchmenCount = 0;
  int _brokersCount = 0;
  int _offersCount = 0;
  int _officesCount = 0;
  int _ownersCount = 0;
  int _requestedCount = 0;
  int _quotationCount = 0;

  // The Home filters: which chip is chosen and what it found. Its own state;
  // it never touches the canonical counts above. It reads through the services
  // above, which choose the backend, so Home has no backend switch of its own.
  late final HomeFilterController _filters = HomeFilterController(
    dataSource: SnapshotHomeFilterDataSource(
      requests: _requestService.getUserRequests,
      offers: _offerService.getUserOffers,
      brokers: _brokerService.getUserBrokers,
      owners: _ownerService.getUserOwners,
      offices: _officeService.getUserOffices,
      watchmen: _watchmenService.getUserWatchmen,
    ),
    classifyError: classifyHomeFilterError,
    // The records read for a filter belong to the account they were read for.
    currentUserId: () => _authRepository.currentUserId,
  );

  // Single combined stream subscription for efficiency
  StreamSubscription? _combinedSubscription;
  StreamSubscription? _authSubscription;
  StreamSubscription<AuthState>? _supabaseAuthSubscription;
  StreamSubscription<void>? _coreMutationSubscription;
  Timer? _updateTimer;

  List<FilterModel> get filters => _filters.filters;

  List<GridItemModel> get items {
    // Use filtered counts if a filter is selected, otherwise use normal counts
    final bool hasSelectedFilter = filters.any((filter) => filter.selected);
    int count(ItemType type, int unfiltered) =>
        hasSelectedFilter ? _filters.countOf(type) : unfiltered;

    return [
      GridItemModel(
          asset: 'assets/icons/requested-svg.svg',
          label: 'Requested',
          labelKey: 'requested',
          count: count(ItemType.request, _requestedCount)),
      GridItemModel(
          asset: 'assets/icons/offers-svg.svg',
          label: 'Offers',
          labelKey: 'offers',
          count: count(ItemType.offer, _offersCount)),
      GridItemModel(
          asset: 'assets/icons/owners-svg.svg',
          label: 'Owners',
          labelKey: 'owners',
          count: count(ItemType.owner, _ownersCount)),
      GridItemModel(
          asset: 'assets/icons/offices-svg.svg',
          label: 'Offices',
          labelKey: 'offices',
          count: count(ItemType.office, _officesCount)),
      GridItemModel(
          asset: 'assets/icons/brokers-svg.svg',
          label: 'Brokers',
          labelKey: 'brokers',
          count: count(ItemType.broker, _brokersCount)),
      GridItemModel(
          asset: 'assets/icons/watchman-svg.svg',
          label: 'Watchmen',
          labelKey: 'watchmen',
          count: count(ItemType.watchmen, _watchmenCount)),
      GridItemModel(
          asset: 'assets/icons/quotation-svg.svg',
          label: 'Quotation',
          labelKey: 'quotation',
          count: count(ItemType.quotation, _quotationCount)),
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

  HomeViewModel({
    AuthRepository? authRepository,
    @visibleForTesting bool initializeStreams = true,
    @visibleForTesting CountCacheService? countCache,
    @visibleForTesting
    Future<Map<String, int>> Function(Map<String, int> fallback)? readCounts,
    @visibleForTesting Stream<AuthState>? authStateChanges,
    @visibleForTesting Future<bool>? Function(String? session)? confirmSession,
    @visibleForTesting String? Function()? sessionOf,
  })  : _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository,
        _countCache = countCache ?? CountCacheService.instance,
        _readCountsOverride = readCounts,
        _authStateChangesOverride = authStateChanges,
        _confirmSession = confirmSession ?? ListSessionCheck.confirmFor,
        _sessionNow = sessionOf ?? ListSessionCheck.currentSession {
    _filters.addListener(notifyListeners);
    _countsAccountId = _authRepository.currentUserId;
    _loadCachedCountsInstantly();
    // Widget tests can render the real Home screen without connecting to an
    // auth/backend stream. Production keeps the existing eager initialization.
    if (initializeStreams) {
      _initializeStreamsWhenReady();
    }
  }

  Map<String, int> get _shownCounts => {
        'watchmen': _watchmenCount,
        'brokers': _brokersCount,
        'offers': _offersCount,
        'offices': _officesCount,
        'owners': _ownersCount,
        'requested': _requestedCount,
        'quotation': _quotationCount,
      };

  /// Load the counts cached for [_countsAccountId] at once - no async delays
  void _loadCachedCountsInstantly() {
    final cachedCounts = _countCache.getAllCachedCounts(_countsAccountId);
    _watchmenCount = cachedCounts['watchmen'] ?? 0;
    _brokersCount = cachedCounts['brokers'] ?? 0;
    _offersCount = cachedCounts['offers'] ?? 0;
    _officesCount = cachedCounts['offices'] ?? 0;
    _ownersCount = cachedCounts['owners'] ?? 0;
    _requestedCount = cachedCounts['requested'] ?? 0;
    _quotationCount = cachedCounts['quotation'] ?? 0;

    // Don't call notifyListeners here - let the UI render immediately with cached values
  }

  /// Makes [accountId] the owner of the counts. When it differs from the
  /// current owner, nothing of the previous account stays: its pending update
  /// is dropped, reads it started are ignored, and the new account's own
  /// cached counts (or 0) are shown.
  void _useAccount(String accountId) {
    if (accountId == _countsAccountId) return;
    _countsEpoch++;
    _updateTimer?.cancel();
    _countsAccountId = accountId;
    _loadCachedCountsInstantly();
    notifyListeners();
  }

  /// True while counts read for [accountId] in [epoch] may still be shown.
  bool _isCurrentCounts(String accountId, int epoch) =>
      !_disposed &&
      epoch == _countsEpoch &&
      accountId == _countsAccountId &&
      accountId == _authRepository.currentUserId;

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
        if (user != null) _useAccount(user.uid);
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
    // The canonical identity is the Supabase user id, which the auth
    // repository reads from the current Supabase session.
    if (_authRepository.currentUserId != null) {
      unawaited(_loadSupabaseCounts());
    }

    final authStateChanges = _authStateChangesOverride ??
        Supabase.instance.client.auth.onAuthStateChange;
    _supabaseAuthSubscription ??= authStateChanges.listen(
      (data) {
        final accountId = data.session?.user.id;
        if (accountId != null) {
          _useAccount(accountId);
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
      // A chosen filter shows records that may just have changed.
      _filters.onDataChanged();
    });
  }

  Future<void> _loadSupabaseCounts() async {
    final accountId = _authRepository.currentUserId;
    if (accountId == null) return;
    _useAccount(accountId);
    final epoch = _countsEpoch;
    // The session the read is made under: its answer counts only while that
    // is still the signed-in session (a sign-out and a sign-in, even to the
    // same account, is a new one; a token refresh is not).
    final session = _sessionNow();
    bool stillTheReader() =>
        _isCurrentCounts(accountId, epoch) && _sessionNow() == session;
    try {
      // The fallback is what is shown now, which is this account's own.
      final fallback = _shownCounts;
      final counts = await (_readCountsOverride?.call(fallback) ??
          _supabaseHomeCountsService.getCounts(fallback: fallback));
      // Counts read for an account or session that is no longer shown are
      // dropped.
      if (!stillTheReader()) return;
      // A session the database has replaced counts 0 everywhere, with no
      // error. A 0 that would replace a count shown now is taken only once
      // the database confirms this read's session (which also starts the
      // usual sign-out when it has been replaced). Counts above 0 prove the
      // read was let through and need no check.
      if (_zeroesAShownCount(counts)) {
        final check = _confirmSession(session);
        if (check != null && !await check) return;
        if (!stillTheReader()) return;
      }
      _handleCombinedUpdate(counts,
          accountId: accountId, epoch: epoch, stillTheReader: stillTheReader);
    } catch (error, stackTrace) {
      debugPrint('Supabase Home count refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Keep the last cached counts if the network is temporarily unavailable.
    }
  }

  void _resetCountsForSignedOutUser() {
    // Whatever is still being read or waiting to be shown belonged to the
    // account that just left.
    _countsEpoch++;
    _updateTimer?.cancel();
    _countsAccountId = null;
    _watchmenCount = 0;
    _brokersCount = 0;
    _offersCount = 0;
    _officesCount = 0;
    _ownersCount = 0;
    _requestedCount = 0;
    _quotationCount = 0;
    // Nobody is signed in: no chip stays chosen, no read still in flight can
    // show a signed-out user's records to the next one, and nothing that was
    // read for this user is kept.
    _filters.reset();
    notifyListeners();
  }

  /// Initialize live streams with combined subscription for efficiency
  void _initializeLiveStreams() {
    // Combine all streams and debounce updates to prevent excessive rebuilds
    _combinedSubscription = _createCombinedStream().listen(
      (counts) {
        final accountId = _authRepository.currentUserId;
        if (accountId == null) return;
        _useAccount(accountId);
        _handleCombinedUpdate(counts,
            accountId: accountId, epoch: _countsEpoch);
      },
      onError: (error) {
        // Continue with cached values on error
      },
    );
  }

  /// Create a single combined stream from all services
  Stream<Map<String, int>> _createCombinedStream() {
    return Stream.periodic(const Duration(seconds: 2), (_) {
      // Use periodic to debounce rapid backend updates
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

  /// Whether [counts] would turn a count shown now into 0.
  bool _zeroesAShownCount(Map<String, int> counts) {
    final shown = _shownCounts;
    return counts.entries
        .any((entry) => entry.value == 0 && (shown[entry.key] ?? 0) > 0);
  }

  /// Handle combined stream updates with debouncing
  void _handleCombinedUpdate(
    Map<String, int> newCounts, {
    required String accountId,
    required int epoch,
    bool Function()? stillTheReader,
  }) {
    // Cancel previous timer to debounce rapid updates
    _updateTimer?.cancel();

    _updateTimer = Timer(const Duration(milliseconds: 100), () {
      if (!_isCurrentCounts(accountId, epoch)) return;
      if (stillTheReader != null && !stillTheReader()) return;
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
        // Update this account's cache with its new counts
        unawaited(_countCache.updateCachedCounts(accountId, newCounts));

        // Notify UI only once with all changes
        notifyListeners();
      }
    });
  }

  /// Reads the counts again. A refresh drops the chosen filter unless
  /// [keepFilter] is true, which is what a pull on the Home screen asks for:
  /// the chosen filter stays chosen and is read again along with the counts.
  Future<void> refreshCounts({bool keepFilter = false}) async {
    if (SupabaseConfig.useSupabaseAuth) {
      if (keepFilter) {
        await Future.wait<void>([_loadSupabaseCounts(), _filters.refresh()]);
      } else {
        _filters.clear();
        await _loadSupabaseCounts();
      }
      notifyListeners();
      return;
    }

    // Cancel existing subscription
    _combinedSubscription?.cancel();
    _updateTimer?.cancel();

    // Drop the chosen filter, unless the refresh is to keep it
    if (!keepFilter) _filters.clear();

    // Force reload from cache first, then reinitialize streams
    _loadCachedCountsInstantly();
    _initializeLiveStreams();

    if (keepFilter) await _filters.refresh();
    notifyListeners();
  }

  /// A tap on a Home filter chip. The chosen chip clears the filter; another
  /// chip is chosen at once and its records are read from the same services
  /// every list screen uses, whichever backend they are on.
  void toggleFilter(int index) => _filters.toggle(index);

  /// Clear all filter selections and return to showing all items
  /// This method is called when user navigates away from home screen
  void clearAllFilters() => _filters.clear();

  /// Tries the chosen filter again after it failed.
  void retryFilter() => _filters.retry();

  // What the chosen filter found, for the filtered list
  List<UnifiedItemModel> get filteredItems => _filters.items;

  FilterModel? get selectedFilter => _filters.selectedFilter;

  String? get selectedFilterKey => _filters.selectedFilterKey;

  bool get isFilterLoading => _filters.isLoading;

  /// True while the chosen chip is one whose filter is not built yet.
  bool get isFilterUnavailable => _filters.isUnavailable;

  /// Why the chosen filter could not be answered; null when it could.
  HomeFilterErrorKind? get filterErrorKind => _filters.errorKind;

  void selectNav(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Cancel subscriptions and timers to prevent memory leaks
    _combinedSubscription?.cancel();
    _authSubscription?.cancel();
    _supabaseAuthSubscription?.cancel();
    _coreMutationSubscription?.cancel();
    _filters.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }
}
