import 'package:broker_wallet/src/services/subscription/billing_availability.dart';
import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/viewmodels/subscription_checkout_controller.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/restore_purchases_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Whether this build can really restore: the Android app with the store and
/// the trusted backend connected.
bool canRestoreLive() =>
    BillingAvailability.backendEnabled && BillingServices.store().isAvailable;

/// Restore against Google Play, then the server. Only the server's answer can
/// show "restored"; a purchase of another account is reported, never moved.
class LiveRestoreView extends StatefulWidget {
  const LiveRestoreView({super.key});

  @override
  State<LiveRestoreView> createState() => _LiveRestoreViewState();
}

class _LiveRestoreViewState extends State<LiveRestoreView> {
  RestorePurchaseState _state = RestorePurchaseState.ready;

  Future<void> _check() async {
    setState(() => _state = RestorePurchaseState.checking);
    final result = await SubscriptionCheckoutController(
      store: BillingServices.store(),
      backend: BillingServices.subscription(),
      billing: BillingServices.billing(),
    ).restore();
    if (!mounted) return;
    if (result == CheckoutResult.activated) {
      try {
        context.read<SubscriptionStateController>().refresh();
      } on ProviderNotFoundException {
        // Nothing else on screen depends on the shared state.
      }
    }
    setState(() {
      _state = switch (result) {
        CheckoutResult.activated => RestorePurchaseState.restored,
        CheckoutResult.nothingToRestore => RestorePurchaseState.nothingFound,
        CheckoutResult.linkedToOtherAccount =>
          RestorePurchaseState.linkedToOtherAccount,
        _ => RestorePurchaseState.unavailable,
      };
    });
  }

  @override
  Widget build(BuildContext context) => RestorePurchasesView(
        state: _state,
        live: true,
        onCheck: _state == RestorePurchaseState.checking ? null : _check,
      );
}
