import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Route paths for the Broker Wallet Plus journey. All are root-level GoRouter
/// routes pushed over the main shell, so the StatefulShellRoute tabs keep
/// their own state underneath.
class PlusRoutes {
  const PlusRoutes._();

  /// The Plus paywall: benefits, plan choice and Free versus Plus.
  static const String paywall = '/plus';

  /// Purchase review, shown before the secure store hand-off.
  static const String review = '/plus/review';

  /// Purchase progress and result: processing, success, pending, failure.
  static const String purchase = '/plus/purchase';

  /// Restore purchases.
  static const String restore = '/plus/restore';

  /// Subscription & Billing: the hub for every plan state, free included.
  /// Profile opens it; every management task is one tap below it.
  static const String billing = '/subscription-billing';

  /// Manage subscription: plan details and the actions the store performs.
  static const String manage = '/subscription-billing/manage';

  /// Change billing period (monthly or annual), confirmed in the store.
  static const String changePeriod = '/subscription-billing/change-period';

  /// Payment methods: where the store's own payment methods are managed.
  static const String paymentMethods = '/subscription-billing/payment-methods';

  /// Billing history and receipts, which the store keeps.
  static const String history = '/subscription-billing/history';

  /// Subscription help topics.
  static const String help = '/subscription-billing/help';

  /// Terms, privacy and subscription information.
  static const String legal = '/subscription-billing/legal';

  /// Plan usage: how much of each section and tool has been used.
  static const String usage = '/subscription-billing/usage';

  /// Former name of [billing] ("My Plan"). Kept only as a redirect so existing
  /// links and notification routes keep working.
  static const String myPlan = '/my-plan';

  /// Former routes, kept only as redirects to [paywall].
  static const String legacySubscription = '/subscription';
  static const String legacyPaymentSelection = '/payment-selection/:plan';

  /// Existing app routes the Plus screens link to.
  static const String terms = '/terms-conditions';
  static const String privacy = '/privacy-policy';
  static const String support = '/help-support';
}

class PlusNavigation {
  const PlusNavigation._();

  /// The single entry used by Profile: everyone, whatever their plan state,
  /// goes to Subscription & Billing, which adapts to that state and offers
  /// the upgrade when there is none.
  static void open(BuildContext context) => context.push(PlusRoutes.billing);

  /// Straight to the paywall, for places that only ever offer an upgrade
  /// (quota limits).
  static void openPaywall(BuildContext context) =>
      context.push(PlusRoutes.paywall);
}
