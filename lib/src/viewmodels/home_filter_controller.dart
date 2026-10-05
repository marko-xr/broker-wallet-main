import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/filter_model.dart';
import '../data/models/unified_item_model.dart';
import 'home_filter_rules.dart';

/// Why a Home filter could not be answered, in terms a screen can word for a
/// person. The technical error itself is never shown.
enum HomeFilterErrorKind {
  /// The records could not be reached: no connection, or it timed out.
  network,

  /// The sign-in is missing or no longer valid.
  session,

  /// Anything else.
  generic,
}

/// Where the Home filters read the signed-in user's records from.
abstract class HomeFilterDataSource {
  /// Reads the records of every one of [types] as one snapshot: it completes
  /// only when all of them have been read, and fails when any could not be, so
  /// a caller never sees a part of the answer.
  Future<List<UnifiedItemModel>> load(List<ItemType> types);
}

enum _Phase {
  /// No filter is chosen.
  idle,

  /// A filter is chosen and has nothing to show yet.
  loading,

  /// A filter is chosen and its records are in [HomeFilterController.items].
  ready,

  /// A filter is chosen and could not be answered.
  failed,

  /// A chip is chosen whose filter is not built yet
  /// ([HomeFilterKind.isImplemented] is false). Nothing is read.
  unavailable,
}

/// The Home filter chips and what the chosen one found.
///
/// One chip is chosen at a time. Choosing a chip reads every record the filter
/// needs, concurrently, and shows the answer only when all of them have
/// arrived: until then there is one loading state, never a part of the list.
/// The records come from the app's own services, so the backend in use is
/// theirs to decide and the signed-in session is the ownership boundary.
///
/// A chip whose filter is not built yet can still be chosen and cleared like the
/// others, but it reads nothing and is reported as [isUnavailable]: the screen
/// says so, instead of showing an empty list or an error for a question that was
/// never asked.
///
/// Every read is stamped with a generation. Choosing another chip, clearing,
/// refreshing, or the user's data changing makes the earlier read stale, and a
/// stale read that finishes late changes nothing.
class HomeFilterController extends ChangeNotifier {
  HomeFilterController({
    required HomeFilterDataSource dataSource,
    required HomeFilterErrorKind Function(Object error) classifyError,
    DateTime Function()? clock,
    this.loadTimeout = defaultLoadTimeout,
  })  : _dataSource = dataSource,
        _classifyError = classifyError,
        _clock = clock ?? DateTime.now;

  /// How long a read may take before it is reported as a connection problem.
  /// It exists so a read that never answers cannot leave a spinner forever.
  static const Duration defaultLoadTimeout = Duration(seconds: 30);

  final Duration loadTimeout;

  final HomeFilterDataSource _dataSource;
  final HomeFilterErrorKind Function(Object error) _classifyError;
  final DateTime Function() _clock;

  /// The chips, in order. Exactly one is [FilterModel.selected] while a filter
  /// is chosen, none otherwise.
  final List<FilterModel> filters = [
    for (final kind in HomeFilterKind.values)
      FilterModel(label: kind.label, labelKey: kind.labelKey),
  ];

  _Phase _phase = _Phase.idle;
  List<UnifiedItemModel> _items = const <UnifiedItemModel>[];
  HomeFilterErrorKind? _errorKind;

  /// Bumped by everything that makes an earlier read stale.
  int _generation = 0;
  bool _disposed = false;

  // ---- what the screen shows ------------------------------------------------

  /// The chosen chip, or null when none is.
  FilterModel? get selectedFilter {
    for (final filter in filters) {
      if (filter.selected) return filter;
    }
    return null;
  }

  /// The chosen chip's localization key, or null when none is chosen.
  String? get selectedFilterKey {
    final selected = selectedFilter;
    return selected?.labelKey ?? selected?.label;
  }

  /// True while the chosen filter has nothing to show yet.
  bool get isLoading => _phase == _Phase.loading;

  /// True while the chosen chip is one whose filter is not built yet.
  bool get isUnavailable => _phase == _Phase.unavailable;

  /// Why the chosen filter could not be answered; null when it could.
  HomeFilterErrorKind? get errorKind =>
      _phase == _Phase.failed ? _errorKind : null;

  /// What the chosen filter found: empty while loading, after a failure, when
  /// the chosen chip has no filter yet, and when no filter is chosen.
  List<UnifiedItemModel> get items => _items;

  /// How many of [items] are of [type].
  int countOf(ItemType type) =>
      _items.where((item) => item.type == type).length;

  HomeFilterKind? get _selectedKind {
    final index = filters.indexWhere((filter) => filter.selected);
    return index < 0 ? null : HomeFilterKind.values[index];
  }

  // ---- input ----------------------------------------------------------------

  /// A tap on a chip. The chosen chip clears the filter; any other chip is
  /// chosen at once and its records are read (or, for a chip whose filter is not
  /// built yet, nothing is read and the chip is reported as [isUnavailable]).
  /// One chip is chosen at a time.
  void toggle(int index) {
    if (index < 0 || index >= filters.length) return;
    if (filters[index].selected) {
      clear();
      return;
    }
    for (var i = 0; i < filters.length; i++) {
      filters[i].selected = i == index;
    }
    final kind = HomeFilterKind.values[index];
    if (kind.isImplemented) {
      _begin(kind);
    } else {
      _showUnavailable();
    }
  }

  /// Back to no filter. Anything still being read is dropped.
  void clear() {
    _generation++;
    final hadFilter = _phase != _Phase.idle || selectedFilter != null;
    for (final filter in filters) {
      filter.selected = false;
    }
    _phase = _Phase.idle;
    _items = const <UnifiedItemModel>[];
    _errorKind = null;
    if (hadFilter) _notify();
  }

  /// Tries again after a failure.
  void retry() {
    final kind = _selectedKind;
    if (kind == null || _phase != _Phase.failed) return;
    _begin(kind);
  }

  /// Reads the chosen filter again because the person asked to refresh. What is
  /// on screen stays until the new answer arrives; if that cannot be had, the
  /// failure is shown rather than an answer that may no longer be true. Does
  /// nothing when no filter is chosen, or when the chosen chip has no filter yet.
  /// Never throws.
  Future<void> refresh() async {
    final kind = _selectedKind;
    if (kind == null || !kind.isImplemented) return;
    final generation = ++_generation;
    if (_phase == _Phase.failed) {
      _phase = _Phase.loading;
      _errorKind = null;
      _notify();
    }
    await _read(kind, generation, quietOnFailure: false);
  }

  /// The user's own records changed (one was created, edited or deleted). When
  /// a filter is chosen it is read again, quietly: what is on screen stays until
  /// the new answer arrives, and if that cannot be had the answer already on
  /// screen is kept. Does nothing when no filter is chosen, or when the chosen
  /// chip has no filter yet.
  void onDataChanged() {
    final kind = _selectedKind;
    if (kind == null || !kind.isImplemented) return;
    final generation = ++_generation;
    unawaited(_read(kind, generation, quietOnFailure: true));
  }

  // ---- reading --------------------------------------------------------------

  /// The chosen chip has no filter behind it: show that, read nothing, and make
  /// whatever the previously chosen chip was still reading stale.
  void _showUnavailable() {
    _generation++;
    _phase = _Phase.unavailable;
    _items = const <UnifiedItemModel>[];
    _errorKind = null;
    _notify();
  }

  void _begin(HomeFilterKind kind) {
    final generation = ++_generation;
    _phase = _Phase.loading;
    _items = const <UnifiedItemModel>[];
    _errorKind = null;
    _notify();
    unawaited(_read(kind, generation, quietOnFailure: false));
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _read(
    HomeFilterKind kind,
    int generation, {
    required bool quietOnFailure,
  }) async {
    try {
      final records = await _dataSource
          .load(HomeFilterRules.typesFor(kind))
          .timeout(loadTimeout);
      if (!_isCurrent(generation)) return;
      _items = HomeFilterRules.apply(kind, records, now: _clock());
      _errorKind = null;
      _phase = _Phase.ready;
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      if (quietOnFailure && _phase == _Phase.ready) {
        // A background re-read failed: what is on screen was true when it was
        // read and nothing asked for a new answer, so it stays. The error's
        // type is logged, never its message.
        debugPrint('Home filter refresh failed: ${error.runtimeType}');
        return;
      }
      _items = const <UnifiedItemModel>[];
      _errorKind = _classifyError(error);
      _phase = _Phase.failed;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
