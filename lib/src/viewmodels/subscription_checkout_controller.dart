import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/store_purchase_gateway.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';

/// Where a purchase or restore ended, from the server's point of view.
enum CheckoutResult {
  /// The trusted server confirms Plus.
  activated,

  /// The store accepted it but the server has not confirmed it yet.
  activationPending,

  /// The store has no completed payment yet (for example a pending method).
  purchasePending,
  cancelled,
  failed,
  unavailable,

  /// The purchase belongs to another Broker Wallet account and was not moved.
  linkedToOtherAccount,

  /// A restore found nothing active for this account.
  nothingToRestore,
}

/// Runs a Google Play purchase or restore and then asks the server what is true.
///
/// A store callback never grants Plus here. The only way to
/// [CheckoutResult.activated] is a state from the trusted backend that says the
/// account has Plus, after the server verified the token with Google.
class SubscriptionCheckoutController {
  SubscriptionCheckoutController({
    required StorePurchaseGateway store,
    required SubscriptionBackend backend,
    required BillingBackend billing,
    Future<void> Function(Duration)? wait,
    this.confirmAttempts = 5,
    this.confirmInterval = const Duration(seconds: 4),
  })  : _store = store,
        _backend = backend,
        _billing = billing,
        _wait = wait ?? Future<void>.delayed;

  final StorePurchaseGateway _store;
  final SubscriptionBackend _backend;
  final BillingBackend _billing;
  final Future<void> Function(Duration) _wait;
  final int confirmAttempts;
  final Duration confirmInterval;

  Future<CheckoutResult> purchase(PlusBillingCycle cycle) async {
    if (!_store.isAvailable) return CheckoutResult.unavailable;
    final StorePurchaseResult result;
    try {
      final reference = await _billing.preparePlayPurchase();
      result = await _store.purchase(cycle, accountReference: reference);
    } catch (_) {
      return CheckoutResult.failed;
    }
    return _settle(result, isRestore: false);
  }

  Future<CheckoutResult> restore() async {
    if (!_store.isAvailable) return CheckoutResult.unavailable;
    final StorePurchaseResult result;
    try {
      result = await _store.restore();
    } catch (_) {
      return CheckoutResult.failed;
    }
    return _settle(result, isRestore: true);
  }

  Future<CheckoutResult> _settle(
    StorePurchaseResult result, {
    required bool isRestore,
  }) async {
    switch (result.outcome) {
      case StorePurchaseOutcome.cancelled:
        return CheckoutResult.cancelled;
      case StorePurchaseOutcome.pending:
        return CheckoutResult.purchasePending;
      case StorePurchaseOutcome.failed:
        return CheckoutResult.failed;
      case StorePurchaseOutcome.unavailable:
        return CheckoutResult.unavailable;
      case StorePurchaseOutcome.purchased:
        if (result.purchaseTokens.isEmpty) {
          return isRestore
              ? CheckoutResult.nothingToRestore
              : CheckoutResult.activationPending;
        }
        return _confirm(result.purchaseTokens, isRestore: isRestore);
    }
  }

  Future<CheckoutResult> _confirm(
    List<String> tokens, {
    required bool isRestore,
  }) async {
    for (var attempt = 0; attempt < confirmAttempts; attempt++) {
      if (attempt > 0) await _wait(confirmInterval);
      try {
        final sync = await _billing.verifyPlayPurchases(tokens);
        if (sync == StoreSyncResult.linkedToOtherAccount) {
          return CheckoutResult.linkedToOtherAccount;
        }
        final SubscriptionServerState state = await _backend.fetchState();
        if (state.isPlus && !state.isTest) return CheckoutResult.activated;
      } catch (_) {
        // The notification may still arrive; the next attempt asks again.
      }
    }
    return isRestore
        ? CheckoutResult.nothingToRestore
        : CheckoutResult.activationPending;
  }
}
