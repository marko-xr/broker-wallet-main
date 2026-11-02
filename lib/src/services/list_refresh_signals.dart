import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// One shared source of "a good moment to read the lists again" hints for the
/// six offline lists.
///
/// A hint comes when the app returns to the foreground and, once
/// [useConnectivity] has been called, when the device goes from no network to
/// some network. A hint is only a hint: a network connection does not prove
/// the Internet or the server can be reached, nor that the session is still
/// valid. Each list decides itself whether a read is due (see
/// `localFirstList`).
///
/// One lifecycle observer and at most one connectivity subscription are
/// attached, and only while some list is listening.
class ListRefreshSignals with WidgetsBindingObserver {
  ListRefreshSignals._() : reconnectDebounce = const Duration(seconds: 1);

  /// A separate instance for tests, with its own connectivity source.
  @visibleForTesting
  ListRefreshSignals.forTesting({
    Stream<List<ConnectivityResult>> Function()? connectivity,
    this.reconnectDebounce = const Duration(seconds: 1),
  }) : _connectivitySource = connectivity;

  static final ListRefreshSignals instance = ListRefreshSignals._();

  /// How long a regained network must last before it is a hint; changes in
  /// between (Wi-Fi to mobile, a drop and a return) count once.
  final Duration reconnectDebounce;

  late final StreamController<void> _hints = StreamController<void>.broadcast(
    onListen: _attach,
    onCancel: _detach,
  );
  bool _attached = false;

  Stream<List<ConnectivityResult>> Function()? _connectivitySource;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool? _online; // unknown until the first connectivity event
  Timer? _reconnect;

  /// An event each time the app is resumed or the network comes back.
  Stream<void> get hints => _hints.stream;

  /// Adds "the network is back" hints, from the device's connectivity state
  /// unless [source] is given. Called once at app start; until then (and in
  /// tests that do not call it) only app-resume hints are sent.
  void useConnectivity([Stream<List<ConnectivityResult>> Function()? source]) {
    _connectivitySource = source ?? () => Connectivity().onConnectivityChanged;
    if (_attached && _connectivity == null) _listenToConnectivity();
  }

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
    _attached = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding (a plain unit test): no lifecycle hints.
    }
    if (_connectivitySource != null) _listenToConnectivity();
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _reconnect?.cancel();
    _reconnect = null;
    unawaited(_connectivity?.cancel());
    _connectivity = null;
    _online = null;
  }

  void _listenToConnectivity() {
    final source = _connectivitySource;
    if (source == null) return;
    try {
      _connectivity = source().listen(
        _onConnectivity,
        // A failing connectivity source only means no such hints.
        onError: (Object _) {},
      );
    } catch (_) {
      _connectivity = null;
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final wasOnline = _online;
    _online = online;
    if (!online) {
      _reconnect?.cancel();
      _reconnect = null;
      return;
    }
    // The first event is the state at subscription, not a change; and a move
    // between networks (Wi-Fi to mobile) is not a return.
    if (wasOnline != false) return;
    _reconnect?.cancel();
    _reconnect = Timer(reconnectDebounce, () {
      _reconnect = null;
      if (_attached) _hints.add(null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hints.add(null);
  }

  /// Sends a resume hint, as the app coming back to the foreground would.
  @visibleForTesting
  void debugResume() => _hints.add(null);
}
