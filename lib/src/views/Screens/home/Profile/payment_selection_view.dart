import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart';
import 'package:flutter/material.dart';

/// Keeps the historical payment-selection route safe for existing links. The
/// single subscription surface presents the unavailable store-product state.
class PaymentSelectionView extends StatelessWidget {
  const PaymentSelectionView({super.key, required this.selectedPlan});

  final SubscriptionPlan selectedPlan;

  @override
  Widget build(BuildContext context) => const SubscriptionView();
}
