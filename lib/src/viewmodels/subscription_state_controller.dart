import 'dart:async';

import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';

/// The signed-in account's subscription state, as last confirmed by the server.
///
/// In memory only and scoped to one account: a change of account clears it at
/// once, and a late answer for the previous account is dropped. A failed read
/// shows "unavailable"; it is never Free and never keeps a previous Plus.
class SubscriptionStateController extends ChangeNotifier {
  SubscriptionStateController({
    SubscriptionBackend Function()? backend,
    Future<BillingChannels> Function()? channels,
  })  : _backendFactory = backend ?? SupabaseSubscriptionBackend.new,
        _channelsLoader =
            channels ?? (() => BillingServices.billing().fetchChannels());

  final SubscriptionBackend Function() _backendFactory;
  late final SubscriptionBackend _backend = _backendFactory();
  final Future<BillingChannels> Function() _channelsLoader;

  /// Closed until the server says otherwise, and again after any failure.
  BillingChannels _channels = BillingChannels.closed;

  String? _userId;
  int _generation = 0;
  bool _disposed = false;
  bool _loading = false;
  bool _testBusy = false;
  String? _testError;
  SubscriptionServerState? _state;

  SubscriptionServerState? get serverState => _state;
  bool get isLoading => _loading;
  bool get testBusy => _testBusy;

  /// The refusal code of the last test-mode request, until the next one.
  String? get testError => _testError;

  SubscriptionPresentation get presentation {
    final state = _state;
    if (state != null) {
      return state.toPresentation(
        tapCardEligibilityVerified: _channels.androidCardChoice,
      );
    }
    if (_loading) {
      return const SubscriptionPresentation(
        status: SubscriptionStatus.loading,
      );
    }
    return const SubscriptionPresentation.unavailable();
  }

  /// Follows the canonical signed-in identity.
  void attachUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _generation++;
    _state = null;
    _channels = BillingChannels.closed;
    // Kept for the whole session otherwise: an item made offline reaches the
    // server only when it uploads, so a fresh state may not include it yet.
    _startedWithoutServer.clear();
    _testError = null;
    _testBusy = false;
    _loading = false;
    final generation = _generation;
    scheduleMicrotask(() {
      if (generation != _generation) return;
      if (userId == null) {
        _notify();
      } else {
        unawaited(refresh());
      }
    });
  }

  Future<void> refresh() async {
    if (_userId == null) return;
    final generation = _generation;
    _loading = true;
    _notify();
    try {
      final state = await _backend.fetchState();
      if (generation != _generation) return;
      _state = state;
    } catch (_) {
      if (generation != _generation) return;
      _state = null;
    }
    BillingChannels channels;
    try {
      channels = await _channelsLoader();
    } catch (_) {
      channels = BillingChannels.closed;
    }
    if (generation != _generation) return;
    _channels = channels;
    _loading = false;
    _notify();
  }

  /// New items started offline per category in this session.
  final Map<UsageCategory, int> _startedWithoutServer = {};

  /// The decision when the server cannot be asked (offline read-only): the
  /// state it confirmed in this session, minus every item started offline. Each
  /// allowed answer is counted at once, so a cancelled start only makes the
  /// next one stricter. A Plus state counts only up to its confirmed date.
  QuotaDecision decideWithoutServer(String section, {DateTime? now}) {
    final state = _state;
    if (_userId == null || state == null) return QuotaDecision.unavailable;
    if (state.isPlus) {
      final until = state.paidThrough;
      return until != null && until.isAfter(now ?? DateTime.now())
          ? QuotaDecision.allowed
          : QuotaDecision.unavailable;
    }
    if (state.readOnly) return QuotaDecision.readOnly;
    final category = SubscriptionServerState.categoryOf(section);
    final created = category == null ? null : state.created[category];
    if (category == null || created == null) return QuotaDecision.unavailable;
    final started = _startedWithoutServer[category] ?? 0;
    if (created + started >= SubscriptionPolicy.freeCreationsPerCategory) {
      return QuotaDecision.limitReached;
    }
    _startedWithoutServer[category] = started + 1;
    return QuotaDecision.allowed;
  }

  /// The server's fresh decision for a new item in [section]; never a cached
  /// one, so a stale Plus cannot authorize a write.
  Future<QuotaDecision> checkCreate(String section) async {
    if (_userId == null) return QuotaDecision.unavailable;
    final generation = _generation;
    try {
      final state = await _backend.fetchState();
      if (generation != _generation) return QuotaDecision.unavailable;
      _state = state;
      _notify();
      return state.decideCreate(section);
    } catch (_) {
      return QuotaDecision.unavailable;
    }
  }

  /// Sends one test-mode action. The switch moves only when the server
  /// confirms; a refusal keeps the last verified state and reports the code.
  Future<void> runTestAction(String action) async {
    if (!kDebugMode || _userId == null || _testBusy) return;
    final generation = _generation;
    _testBusy = true;
    _testError = null;
    _notify();
    try {
      final state = await _backend.testControl(action);
      if (generation != _generation) return;
      _state = state;
    } on SubscriptionTestControlRefused catch (refusal) {
      if (generation != _generation) return;
      _testError = refusal.code;
    } catch (_) {
      if (generation != _generation) return;
      _testError = 'unavailable';
    }
    _testBusy = false;
    _notify();
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
