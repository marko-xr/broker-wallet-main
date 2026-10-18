import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';

/// The pending combine: the files the user selected and, in order, the pages
/// that will make up the combined PDF. Pure logic with no I/O, so every edit
/// (order, ranges, removal, rotation) is testable on its own.
///
/// The page list is the truth the combine runs on; the final order the user
/// reviews is exactly this list. Files keep a position of their own; moving a
/// file moves the pages it contributes as one block and keeps the order of its
/// pages. A page the user moved between files stays where they put it until a
/// file is moved or a range is chosen again, and then that file's pages are
/// grouped again.
class CombinePlan {
  final List<CombineSource> _sources = <CombineSource>[];
  List<CombinePageRef> _pages = <CombinePageRef>[];

  List<CombineSource> get sources => List<CombineSource>.unmodifiable(_sources);
  List<CombinePageRef> get pages => List<CombinePageRef>.unmodifiable(_pages);

  bool get isEmpty => _sources.isEmpty;
  int get totalPages => _pages.length;
  int get totalSourceBytes => _sources.fold<int>(0, (sum, s) => sum + s.size);

  CombineSource? sourceById(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  bool containsPath(String path) => _sources.any((s) => s.path == path);

  /// The pages of [sourceId] in the order they will appear.
  List<CombinePageRef> pagesOf(String sourceId) => <CombinePageRef>[
        for (final p in _pages)
          if (p.sourceId == sourceId) p
      ];

  int selectedCount(String sourceId) =>
      _pages.where((p) => p.sourceId == sourceId).length;

  /// Adds [source] with all of its pages at the end. Returns false, adding
  /// nothing, when a file with the same path is already selected.
  bool addSource(CombineSource source) {
    if (containsPath(source.path)) return false;
    _sources.add(source);
    for (var i = 0; i < source.pageCount; i++) {
      _pages.add(CombinePageRef(sourceId: source.id, pageIndex: i));
    }
    return true;
  }

  /// Removes a file and every page it contributes.
  void removeSource(String sourceId) {
    _sources.removeWhere((s) => s.id == sourceId);
    _pages.removeWhere((p) => p.sourceId == sourceId);
  }

  /// Moves a file to [newIndex], its final position (as `onReorderItem` gives
  /// it), and regroups the
  /// pages to match the new file order.
  void moveSource(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sources.length) return;
    newIndex = newIndex.clamp(0, _sources.length - 1);
    final moved = _sources.removeAt(oldIndex);
    _sources.insert(newIndex, moved);
    _regroup();
  }

  /// Keeps only pages [from]..[to] (1-based, inclusive) of a file. Pages that
  /// stay keep their rotation; pages that return start unrotated.
  void selectRange(String sourceId, int from, int to) {
    final source = sourceById(sourceId);
    if (source == null) return;
    if (from < 1 || to > source.pageCount || from > to) {
      throw RangeError('range $from-$to is outside 1-${source.pageCount}');
    }
    final turns = <int, int>{
      for (final p in _pages)
        if (p.sourceId == sourceId) p.pageIndex: p.quarterTurns,
    };
    _pages.removeWhere((p) => p.sourceId == sourceId);
    for (var i = from - 1; i < to; i++) {
      _pages.add(CombinePageRef(
          sourceId: sourceId, pageIndex: i, quarterTurns: turns[i] ?? 0));
    }
    _regroup();
  }

  /// Selects every page of a file again.
  void useAllPages(String sourceId) {
    final source = sourceById(sourceId);
    if (source == null) return;
    selectRange(sourceId, 1, source.pageCount);
  }

  /// Moves a page to [newIndex], its final position (as `onReorderItem` gives
  /// it).
  void movePage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    newIndex = newIndex.clamp(0, _pages.length - 1);
    final moved = _pages.removeAt(oldIndex);
    _pages.insert(newIndex, moved);
  }

  void removePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pages.removeAt(index);
  }

  /// Turns the page at [index] by [quarterTurns] clockwise quarter turns
  /// (negative turns it back).
  void rotatePage(int index, int quarterTurns) {
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    _pages[index] = page.withQuarterTurns(page.quarterTurns + quarterTurns);
  }

  void clear() {
    _sources.clear();
    _pages = <CombinePageRef>[];
  }

  /// Why this plan cannot be combined yet, or null when it can.
  CombinePdfFailure? get blocker {
    if (_sources.length < 2) return CombinePdfFailure.tooFewFiles;
    if (_pages.isEmpty) return CombinePdfFailure.noPages;
    if (_sources.length > CombineLimits.maxSources ||
        _pages.length > CombineLimits.maxTotalPages ||
        totalSourceBytes > CombineLimits.maxTotalSourceBytes) {
      return CombinePdfFailure.selectionTooLarge;
    }
    for (final source in _sources) {
      if (selectedCount(source.id) == 0)
        return CombinePdfFailure.fileHasNoPages;
    }
    return null;
  }

  /// The id of the first selected file that has no page left, for a message.
  String? get firstEmptySourceId {
    for (final source in _sources) {
      if (selectedCount(source.id) == 0) return source.id;
    }
    return null;
  }

  void _regroup() {
    final next = <CombinePageRef>[];
    for (final source in _sources) {
      next.addAll(_pages.where((p) => p.sourceId == source.id));
    }
    _pages = next;
  }
}
