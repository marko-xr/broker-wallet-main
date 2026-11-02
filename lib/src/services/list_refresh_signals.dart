import 'dart:async';

import 'package:flutter/widgets.dart';

/// One shared source of "a good moment to read the lists again" hints for the
/// six offline lists.
///
/// Today the only hint is the app coming back to the foreground. The app has
/// no connectivity package, so there is no reliable "network is back" event;
/// a list that failed retries on its own bounded schedule instead (see
/// `localFirstList`). A hint is only a hint: it never proves the server can
/// be reached, and a list decides itself whether a read is due.
///
/// The lifecycle observer is attached only while some list is listening.
class ListRefreshSignals with WidgetsBindingObserver {
  ListRefreshSignals._();

  static final ListRefreshSignals instance = ListRefreshSignals._();

  late final StreamController<void> _hints = StreamController<void>.broadcast(
    onListen: _attach,
    onCancel: _detach,
  );
  bool _attached = false;

  /// An event each time the app is resumed.
  Stream<void> get hints => _hints.stream;

  /// Whether the app is in the foreground now; true when that cannot be told
  /// (no binding, or no lifecycle state reported yet).
  bool get appIsActive {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  void _attach() {
    if (_attached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    } catch (_) {
      // No binding (a plain unit test): no lifecycle hints.
    }
  }

  void _detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hints.add(null);
  }

  /// Sends a resume hint, as the app coming back to the foreground would.
  @visibleForTesting
  void debugResume() => _hints.add(null);
}
