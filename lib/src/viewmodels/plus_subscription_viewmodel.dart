import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/services/subscription/debug_plus_billing_gateway.dart';
import 'package:broker_wallet/src/services/subscription/plus_billing_gateway.dart';

/// Whether the Plus plans have been fetched from the billing source.
enum OfferingLoadState { idle, loading, ready, unavailable }

/// Presentation state for the whole Broker Wallet Plus journey: paywall,
/// purchase review, purchase progress, restore and Subscription & Billing.
///
/// This class owns *what to show*. It never decides what the user may do:
/// access control stays with the server-side entitlement design, and nothing
/// here may be read as an `isPremium` flag. It also never fabricates an
/// entitlement — the only way [entitlement] changes to something other than
/// free is a [PlusBillingGateway] reporting one (or the debug-only preview
/// helpers, which are no-ops outside debug builds).
///
/// Future RevenueCat integration plugs in at two points and nowhere else:
///  * a real [PlusBillingGateway] replaces the unavailable/preview gateway;
///  * entitlement changes pushed by the store/server call [applyEntitlement].
class PlusSubscriptionViewModel extends ChangeNotifier {
  PlusSubscriptionViewModel({required PlusBillingGateway gateway})
      : _gateway = gateway;

  final PlusBillingGateway _gateway;

  String? _accountId;
  SubscriptionUiState _entitlement = const SubscriptionUiState.free();

  OfferingLoadState _offeringState = OfferingLoadState.idle;
  SubscriptionOfferingUiModel _offering =
      const SubscriptionOfferingUiModel.unavailable();
  SubscriptionPeriod? _selectedPeriod;

  PurchasePhase _purchasePhase = PurchasePhase.idle;
  bool _hasPendingPurchase = false;
  int _purchaseToken = 0;

  RestorePhase _restorePhase = RestorePhase.idle;
  int _restoreToken = 0;
  bool _debugRestoreHeld = false;
  PlusStore? _debugStore;

  bool _disposed = false;

  // ---- Reads ---------------------------------------------------------------

  String? get accountId => _accountId;
  SubscriptionUiState get entitlement => _entitlement;
  SubscriptionStatus get status => _entitlement.status;

  bool get isBillingAvailable => _gateway.isBillingAvailable;

  OfferingLoadState get offeringState => _offeringState;
  SubscriptionOfferingUiModel get offering => _offering;

  SubscriptionPeriod? get selectedPeriod => _selectedPeriod;

  /// The plan the user has chosen, or the offering's default.
  SubscriptionPlanUiModel? get selectedPlan {
    final period = _selectedPeriod;
    if (period != null) {
      final match = _offering.planFor(period);
      if (match != null) return match;
    }
    return _offering.defaultPlan;
  }

  PurchasePhase get purchasePhase => _purchasePhase;

  /// A purchase was started and the store has not confirmed it yet. Display
  /// only: it never grants anything.
  bool get hasPendingPurchase => _hasPendingPurchase;

  RestorePhase get restorePhase => _restorePhase;

  /// The store a purchase on this device goes through, or the store of the
  /// current subscription when it is known.
  PlusStore get effectiveStore {
    if (_entitlement.store != PlusStore.unknown) return _entitlement.store;
    // Debug builds can preview the other store's wording; never in release.
    if (kDebugMode && _debugStore != null) return _debugStore!;
    return currentPlusStore();
  }

  // ---- Account scope -------------------------------------------------------

  /// Binds the presentation state to the signed-in account. A different
  /// account (including signing out) starts again from free, so one account's
  /// state — preview or real — can never be shown to another.
  void attachAccount(String? accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _entitlement = const SubscriptionUiState.free();
    _purchaseToken++;
    _restoreToken++;
    _purchasePhase = PurchasePhase.idle;
    _restorePhase = RestorePhase.idle;
    _hasPendingPurchase = false;
    _debugRestoreHeld = false;
    // Provider calls this while building; notify after the frame is safe.
    scheduleMicrotask(_notifySafely);
  }

  // ---- Offering ------------------------------------------------------------

  /// Loads the plans once. Safe to call from every screen that needs them.
  Future<void> ensureOfferingLoaded() async {
    if (_offeringState == OfferingLoadState.loading ||
        _offeringState == OfferingLoadState.ready ||
        _offeringState == OfferingLoadState.unavailable) {
      return;
    }
    await _loadOffering();
  }

  Future<void> reloadOffering() => _loadOffering();

  Future<void> _loadOffering() async {
    _offeringState = OfferingLoadState.loading;
    _notifySafely();
    try {
      final loaded = await _gateway.loadOffering();
      if (_disposed) return;
      _offering = loaded;
      _offeringState = loaded.isAvailable
          ? OfferingLoadState.ready
          : OfferingLoadState.unavailable;
      final selected = _selectedPeriod;
      if (selected == null || loaded.planFor(selected) == null) {
        _selectedPeriod = loaded.defaultPlan?.period;
      }
    } catch (_) {
      if (_disposed) return;
      _offering = const SubscriptionOfferingUiModel.unavailable();
      _offeringState = OfferingLoadState.unavailable;
    }
    _notifySafely();
  }

  void selectPeriod(SubscriptionPeriod period) {
    if (_offering.planFor(period) == null || _selectedPeriod == period) return;
    _selectedPeriod = period;
    _notifySafely();
  }

  // ---- Purchase ------------------------------------------------------------

  /// Starts the purchase of [selectedPlan]. A second call while a purchase is
  /// in progress is ignored, so a repeated tap cannot start two.
  Future<void> beginPurchase() async {
    final plan = selectedPlan;
    if (plan == null || _purchasePhase.isInProgress) return;

    final token = ++_purchaseToken;
    _purchasePhase = PurchasePhase.initiating;
    _notifySafely();

    try {
      await for (final update in _gateway.purchase(plan)) {
        if (_disposed || token != _purchaseToken) return;
        _applyPurchaseUpdate(update);
      }
      if (!_disposed &&
          token == _purchaseToken &&
          _purchasePhase.isInProgress) {
        // The source ended without a result. Never leave the user waiting and
        // never guess success.
        _purchasePhase = PurchasePhase.unknownFailure;
        _notifySafely();
      }
    } catch (_) {
      if (_disposed || token != _purchaseToken) return;
      _purchasePhase = PurchasePhase.unknownFailure;
      _notifySafely();
    }
  }

  void _applyPurchaseUpdate(PurchaseUpdate update) {
    var phase = update.phase;
    if (phase == PurchasePhase.success) {
      final reported = update.entitlement;
      if (reported == null || !reported.isCurrentPlus) {
        // A "success" the source did not back with an entitlement is not
        // success. Do not unlock, do not celebrate.
        phase = PurchasePhase.verificationFailed;
      } else {
        _entitlement = reported;
        _hasPendingPurchase = false;
      }
    } else if (phase == PurchasePhase.pending) {
      _hasPendingPurchase = true;
    }
    _purchasePhase = phase;
    _notifySafely();
  }

  /// Clears a finished purchase result once the user has dealt with it.
  void acknowledgePurchaseResult() {
    if (_purchasePhase == PurchasePhase.idle || _purchasePhase.isInProgress) {
      return;
    }
    _purchasePhase = PurchasePhase.idle;
    _notifySafely();
  }

  // ---- Restore -------------------------------------------------------------

  Future<void> restorePurchases() async {
    if (_restorePhase == RestorePhase.restoring) return;
    _debugRestoreHeld = false;

    final token = ++_restoreToken;
    _restorePhase = RestorePhase.restoring;
    _notifySafely();

    try {
      final result = await _gateway.restorePurchases();
      if (_disposed || token != _restoreToken) return;
      var phase = result.phase;
      if (phase == RestorePhase.restored) {
        final reported = result.entitlement;
        if (reported == null || !reported.isCurrentPlus) {
          // Restore never manufactures an entitlement.
          phase = RestorePhase.nothingFound;
        } else {
          _entitlement = reported;
          _hasPendingPurchase = false;
        }
      }
      _restorePhase = phase;
    } catch (_) {
      if (_disposed || token != _restoreToken) return;
      _restorePhase = RestorePhase.failed;
    }
    _notifySafely();
  }

  /// Returns the restore screen to its starting point.
  void resetRestore() {
    if (_debugRestoreHeld ||
        _restorePhase == RestorePhase.idle ||
        _restorePhase == RestorePhase.restoring) {
      return;
    }
    _restorePhase = RestorePhase.idle;
    _notifySafely();
  }

  // ---- Entitlement from a real source --------------------------------------

  /// Entry point for entitlement changes reported by the billing source
  /// (later: RevenueCat reconciled with the server). Presentation only.
  void applyEntitlement(SubscriptionUiState state) {
    _entitlement = state;
    if (state.isCurrentPlus) _hasPendingPurchase = false;
    _notifySafely();
  }

  // ---- Debug-only preview --------------------------------------------------
  //
  // Every method below returns immediately outside debug builds. They change
  // what is *displayed* in this process only; nothing is persisted, sent or
  // treated as entitlement.

  /// The preview knobs, or null when this build has no preview gateway.
  DebugPlusPreviewConfig? get debugPreviewConfig {
    if (!kDebugMode) return null;
    final gateway = _gateway;
    return gateway is DebugPlusBillingGateway ? gateway.config : null;
  }

  void debugApplyEntitlement(SubscriptionUiState state) {
    if (!kDebugMode) return;
    applyEntitlement(state);
  }

  void debugShowPurchasePhase(PurchasePhase phase) {
    if (!kDebugMode) return;
    _purchaseToken++;
    _purchasePhase = phase;
    if (phase == PurchasePhase.pending) _hasPendingPurchase = true;
    _notifySafely();
  }

  void debugShowRestorePhase(RestorePhase phase) {
    if (!kDebugMode) return;
    _restoreToken++;
    _debugRestoreHeld = true;
    _restorePhase = phase;
    _notifySafely();
  }

  Future<void> debugReloadOffering() async {
    if (!kDebugMode) return;
    await _loadOffering();
  }

  /// Previews the wording of [store] (App Store or Google Play) wherever no
  /// subscription pins one. Display only; null restores this device's store.
  PlusStore? get debugStore => kDebugMode ? _debugStore : null;

  void debugSetStore(PlusStore? store) {
    if (!kDebugMode) return;
    _debugStore = store;
    _notifySafely();
  }

  void debugReset() {
    if (!kDebugMode) return;
    _purchaseToken++;
    _restoreToken++;
    _entitlement = const SubscriptionUiState.free();
    _purchasePhase = PurchasePhase.idle;
    _restorePhase = RestorePhase.idle;
    _hasPendingPurchase = false;
    _debugRestoreHeld = false;
    _debugStore = null;
    _notifySafely();
  }

  // ---- Plumbing ------------------------------------------------------------

  void _notifySafely() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
