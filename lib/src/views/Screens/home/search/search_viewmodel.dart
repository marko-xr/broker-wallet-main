import 'dart:async';
import 'dart:io' show SocketException;

import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'search_card_media.dart';
import 'search_card_media_source.dart';
import 'search_data_source.dart';
import 'search_engine.dart';
import 'search_result.dart';
import 'package:broker_wallet/src/common/utils/search_text.dart';

// The result types are defined with [SearchResult]; Search code imports them
// from here.
export 'search_result.dart';

/// Why a search could not be answered, in terms a screen can word for a person.
/// The technical error itself is never shown.
enum SearchErrorKind {
  /// The records could not be reached: no connection, or it timed out.
  network,

  /// The sign-in is missing or no longer valid.
  session,

  /// Anything else.
  generic,
}

/// Sorts a failure into a [SearchErrorKind].
SearchErrorKind classifySearchError(Object error) {
  if (error is TimeoutException || error is SocketException) {
    return SearchErrorKind.network;
  }
  final type = error.runtimeType.toString();
  if (type.contains('SocketException') ||
      type.contains('ClientException') ||
      type.contains('HandshakeException') ||
      type.contains('Timeout') ||
      type.contains('Retryable')) {
    return SearchErrorKind.network;
  }
  if (error is StateError && error.message.toLowerCase().contains('session')) {
    return SearchErrorKind.session;
  }
  if (error is AuthException) return SearchErrorKind.session;
  if (error is PostgrestException &&
      (error.code == '42501' ||
          error.code == 'PGRST301' ||
          error.code == 'PGRST303')) {
    return SearchErrorKind.session;
  }
  return SearchErrorKind.generic;
}

/// State of the Search screen.
///
/// Search is local. The first time there is something to search for, the signed
/// in user's own records are loaded once, indexed, and every query after that is
/// answered from memory. This class keeps that picture correct:
///
///  * **Latest query wins.** Every search is stamped with a generation; one that
///    finishes after a newer one (or after the query was cleared, or after this
///    object was disposed) is dropped and can change nothing.
///  * **One load.** Searches that need the records while they are loading share
///    that one load.
///  * **Fresh records.** The records are reloaded when the user's own data
///    changes anywhere in the app ([CoreEntityMutationNotifier]), when they are
///    older than [cacheValidFor], and when the signed-in user is not the one
///    they were loaded for.
///  * **User-safe failures.** A failure becomes a [SearchErrorKind], never the
///    technical message; if records are already loaded they keep serving.
class SearchViewModel extends ChangeNotifier {
  SearchViewModel({
    SearchDataSource? dataSource,
    SearchEngine? engine,
    this.debounce = defaultDebounce,
    this.cacheValidFor = defaultCacheValidFor,
    Stream<void>? dataChanges,
    DateTime Function()? clock,
    SearchCardMediaResolver? cardMedia,
  })  : _dataSource = dataSource ?? DefaultSearchDataSource(),
        _engine = engine ?? SearchEngine(),
        _clock = clock ?? DateTime.now,
        cardMedia = cardMedia ??
            SearchCardMediaResolver(source: DefaultSearchCardMediaSource()) {
    _dataChanges = (dataChanges ?? CoreEntityMutationNotifier.changes)
        .listen((_) => _dataVersion++);
  }

  /// How long typing must pause before a search runs.
  static const Duration defaultDebounce = Duration(milliseconds: 300);

  /// How long loaded records are trusted when nothing says they changed.
  static const Duration defaultCacheValidFor = Duration(minutes: 5);

  final Duration debounce;
  final Duration cacheValidFor;

  /// Chooses the photo or video frame each Offer and Owner card shows. The list
  /// read carries no media links, so a card asks for its own when it is on
  /// screen; what was asked is forgotten whenever the records are read again.
  final SearchCardMediaResolver cardMedia;

  final SearchDataSource _dataSource;
  final SearchEngine _engine;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _dataChanges;

  // ---- what the screen shows ------------------------------------------------

  /// What is typed in the search field, as typed.
  String query = '';

  /// The query the results below answer, trimmed and with its whitespace
  /// collapsed. Empty until a search has been answered.
  String resultsQuery = '';

  /// The answer: best match first, no record twice.
  List<SearchResult> searchResults = const <SearchResult>[];

  /// True while the records are being loaded for the first time and there is
  /// nothing to show yet.
  bool isLoading = false;

  /// Why the last search failed; null when it did not.
  SearchErrorKind? errorKind;

  /// The kind of record to limit results to; exactly one chip is selected,
  /// "All" unless the person chose another.
  final List<FilterModel> filters = [
    FilterModel(label: 'All', labelKey: 'all', selected: true),
    FilterModel(label: 'Requested', labelKey: 'requested'),
    FilterModel(label: 'Offers', labelKey: 'offers'),
    FilterModel(label: 'Owners', labelKey: 'owners'),
    FilterModel(label: 'Offices', labelKey: 'offices'),
    FilterModel(label: 'Brokers', labelKey: 'brokers'),
    FilterModel(label: 'Watchmen', labelKey: 'watchmen'),
  ];

  // ---- internals ------------------------------------------------------------

  Timer? _debounceTimer;
  bool _disposed = false;

  /// Bumped by every search and every clear; a search whose number is no longer
  /// current has been superseded.
  int _generation = 0;

  SearchCorpus? _corpus;
  DateTime? _corpusLoadedAt;
  String? _corpusUserId;

  /// Counts the user's own data changing; the corpus remembers the count it was
  /// loaded at.
  int _dataVersion = 0;
  int _corpusDataVersion = 0;

  Future<void>? _loading;

  /// Identifies the question the current results answer (words + filter).
  String? _resultsKey;

  // ---- derived state --------------------------------------------------------

  bool get hasQuery => SearchText.tokens(query).isNotEmpty;

  bool get hasResults => hasQuery && searchResults.isNotEmpty;

  /// Whether a search has been answered for the current question. Until it has,
  /// an empty list means "not asked yet", not "nothing found".
  bool get hasAnswer => _resultsKey != null;

  /// The chip that is selected. Never changes state: a read is only a read.
  FilterModel? get selectedFilter {
    for (final filter in filters) {
      if (filter.selected) return filter;
    }
    return filters.isEmpty ? null : filters.first;
  }

  String? get selectedFilterKey => selectedFilter?.labelKey ?? 'all';

  SearchResultType? get _selectedType {
    switch (selectedFilterKey) {
      case 'requested':
        return SearchResultType.request;
      case 'offers':
        return SearchResultType.offer;
      case 'owners':
        return SearchResultType.owner;
      case 'offices':
        return SearchResultType.office;
      case 'brokers':
        return SearchResultType.broker;
      case 'watchmen':
        return SearchResultType.watchmen;
    }
    return null;
  }

  // ---- input ----------------------------------------------------------------

  /// The search text changed. Searches once typing pauses for [debounce]; an
  /// empty or meaningless query (blank, or only punctuation) goes back to the
  /// starting state at once.
  void updateQuery(String value) {
    if (value == query) return;
    query = value;
    _debounceTimer?.cancel();

    final tokens = SearchText.tokens(value);
    if (tokens.isEmpty) {
      _clear();
      return;
    }
    // Only spacing or case changed: the answer is the one already on screen.
    if (_keyOf(tokens) == _resultsKey && errorKind == null && _corpusFresh) {
      return;
    }
    _debounceTimer = Timer(debounce, () => unawaited(_search()));
  }

  /// The keyboard's Search action: search now, without waiting for a pause.
  void submitQuery(String value) {
    query = value;
    _debounceTimer?.cancel();
    if (SearchText.tokens(value).isEmpty) {
      _clear();
      return;
    }
    unawaited(_search());
  }

  /// Chooses the kind of record to search, or — when it is already chosen —
  /// goes back to "All". One search runs, for the query as it is now.
  void toggleFilter(int index) {
    if (index < 0 || index >= filters.length) return;
    final tapped = filters[index];
    final isAll = tapped.labelKey == 'all';
    if (tapped.selected && isAll) return; // already showing everything

    final chosen = tapped.selected ? 0 : index;
    for (var i = 0; i < filters.length; i++) {
      filters[i].selected = i == chosen;
    }

    _debounceTimer?.cancel();
    if (hasQuery) unawaited(_search());
    _notify();
  }

  /// Tries again after a failure, reloading the records.
  void retry() {
    _debounceTimer?.cancel();
    if (!hasQuery) return;
    _corpusLoadedAt = null; // forces a reload
    unawaited(_search());
  }

  /// Refreshes the answer if the records it was made from have changed or aged
  /// out. Called when the Search tab comes back to the front.
  void refreshIfStale() {
    if (_disposed || !hasQuery || _corpusFresh) return;
    unawaited(_search());
  }

  /// Drops loaded records so the next search reads them again.
  void refreshCache() {
    _corpusLoadedAt = null;
    if (hasQuery) unawaited(_search());
  }

  // ---- searching ------------------------------------------------------------

  bool get _corpusUsable =>
      _corpus != null && _corpusUserId == _dataSource.currentUserId;

  bool get _corpusFresh {
    final loadedAt = _corpusLoadedAt;
    if (!_corpusUsable || loadedAt == null) return false;
    if (_corpusDataVersion != _dataVersion) return false;
    return _clock().difference(loadedAt) < cacheValidFor;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  String _keyOf(List<String> tokens) =>
      '${tokens.join(' ')}|${selectedFilterKey ?? 'all'}';

  Future<void> _search() async {
    final generation = ++_generation;
    final tokens = SearchText.tokens(query);
    if (tokens.isEmpty) {
      _clear();
      return;
    }
    final display = SearchText.collapse(query);
    final type = _selectedType;
    final key = _keyOf(tokens);

    try {
      if (!_corpusUsable) {
        // Nothing to search yet: show that, and leave the last answer alone
        // until there is a new one.
        isLoading = true;
        errorKind = null;
        _notify();
      }

      if (!_corpusFresh) {
        try {
          await _load();
        } catch (error) {
          if (!_isCurrent(generation)) return;
          // Records already loaded keep serving; only a search with nothing to
          // search through fails.
          if (!_corpusUsable) {
            searchResults = const <SearchResult>[];
            resultsQuery = '';
            _resultsKey = null;
            errorKind = classifySearchError(error);
            isLoading = false;
            _notify();
            return;
          }
        }
        if (!_isCurrent(generation)) return;
      }

      final corpus = _corpus;
      if (corpus == null || !_corpusUsable) return;

      searchResults = _engine.search(
        corpus,
        tokens: tokens,
        displayQuery: display,
        type: type,
      );
      resultsQuery = display;
      _resultsKey = key;
      errorKind = null;
      isLoading = false;
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      searchResults = const <SearchResult>[];
      resultsQuery = '';
      _resultsKey = null;
      errorKind = classifySearchError(error);
      isLoading = false;
      _notify();
    }
  }

  /// Loads and indexes the records, once however many searches ask for them. A
  /// failed load is not remembered: the next search tries again.
  Future<void> _load() {
    return _loading ??= _loadRecords().whenComplete(() => _loading = null);
  }

  Future<void> _loadRecords() async {
    final version = _dataVersion;
    final userId = _dataSource.currentUserId;
    final data = await _dataSource.load();
    if (_disposed) return;
    _corpus = _engine.index(data);
    cardMedia.invalidate();
    _corpusLoadedAt = _clock();
    _corpusUserId = userId;
    // If the user's data changed while this was loading, these records are
    // already out of date, and the next search reads them again.
    _corpusDataVersion = version;
  }

  /// Back to the starting state: nothing in flight may change it afterwards.
  void _clear() {
    _generation++;
    searchResults = const <SearchResult>[];
    resultsQuery = '';
    _resultsKey = null;
    errorKind = null;
    isLoading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    unawaited(_dataChanges.cancel());
    super.dispose();
  }
}
