import 'dart:async';

import 'package:flutter/foundation.dart';

/// What a list screen's delete ended in.
enum EntityDeleteOutcome {
  /// The server accepted the delete; the item is gone from the list.
  deleted,

  /// The delete failed; the item is back as it was.
  failed,

  /// A delete of this item was already in flight (or done); nothing ran.
  ignored,
}

/// The list lifecycle shared by the six entity list screens (Requests, Offers,
/// Owners, Offices, Brokers, Watchmen).
///
/// The screen subscribes to its source once and keeps the last list it
/// received. A later list replaces it in place, a failed refresh leaves it on
/// screen, and a delete marks only its own item. The loading placeholder is
/// therefore shown only before the first list arrives, and the empty state only
/// when a received list is genuinely empty — never because a refresh or a
/// delete is in flight.
mixin EntityListState<T> on ChangeNotifier {
  StreamSubscription<List<T>>? _subscription;
  List<T>? _received;
  Object? _loadError;
  final Set<String> _deleting = <String>{};

  /// Items whose delete the server accepted but which the source may still
  /// list (a read that started before the delete). Hidden until the source
  /// stops listing them.
  final Set<String> _deleted = <String>{};
  bool _disposed = false;

  /// The identity of [item], or null when it has none.
  String? entityIdOf(T item);

  /// A fixed name for this list in debug timing lines; never user data.
  String get debugListName;

  /// Subscribes to [source] for the lifetime of this view model.
  @protected
  void listenToEntities(Stream<List<T>> source) {
    _subscription?.cancel();
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    _subscription = source.listen(
      (items) {
        if (stopwatch != null && _received == null) {
          debugPrint('[EntityList] $debugListName: first list after '
              '${stopwatch.elapsedMilliseconds} ms (${items.length} items)');
        }
        _received = items;
        _loadError = null;
        _deleted.removeWhere((id) => !_lists(items, id));
        _notify();
      },
      onError: (Object error, StackTrace _) {
        _loadError = error;
        if (kDebugMode) {
          debugPrint('[EntityList] $debugListName: read failed '
              '(${error.runtimeType}); '
              '${_received == null ? 'nothing to show' : 'current list kept'}');
        }
        _notify();
      },
    );
  }

  /// True until the first list — or a failure before it — arrives.
  bool get isInitialLoading => _received == null && _loadError == null;

  /// The first read failed, so there is no list to keep on screen.
  bool get hasLoadError => _received == null && _loadError != null;

  /// The failure behind [hasLoadError]; null otherwise.
  Object? get loadError => hasLoadError ? _loadError : null;

  /// The latest list, without items whose delete the server has accepted.
  List<T> get entities {
    final received = _received;
    if (received == null) return List<T>.empty();
    if (_deleted.isEmpty) return received;
    return received
        .where((item) => !_deleted.contains(entityIdOf(item)))
        .toList(growable: false);
  }

  /// Whether the item [id] is being deleted right now.
  bool isDeleting(String? id) => id != null && _deleting.contains(id);

  /// Runs [delete] for the item [id], marking only that item while it runs.
  ///
  /// The item stays listed until the server accepts the delete, and is back
  /// as it was if the delete fails. A second request for the same item while
  /// one is in flight runs nothing.
  @protected
  Future<EntityDeleteOutcome> deleteEntity(
    String id,
    Future<void> Function() delete,
  ) async {
    if (_deleting.contains(id) || _deleted.contains(id)) {
      return EntityDeleteOutcome.ignored;
    }
    _deleting.add(id);
    _notify();
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      await delete();
    } catch (error) {
      _deleting.remove(id);
      if (stopwatch != null) {
        debugPrint('[EntityList] $debugListName: delete failed after '
            '${stopwatch.elapsedMilliseconds} ms (${error.runtimeType})');
      }
      _notify();
      return EntityDeleteOutcome.failed;
    }
    _deleting.remove(id);
    final received = _received;
    if (received != null && _lists(received, id)) _deleted.add(id);
    if (stopwatch != null) {
      debugPrint('[EntityList] $debugListName: delete accepted after '
          '${stopwatch.elapsedMilliseconds} ms');
    }
    _notify();
    return EntityDeleteOutcome.deleted;
  }

  bool _lists(List<T> items, String id) =>
      items.any((item) => entityIdOf(item) == id);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
