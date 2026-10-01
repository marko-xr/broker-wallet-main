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

  /// Payment details: the payment summary, the payment method and one action.
  /// The first stop of the payment flow; the hub's payment row and a payment
  /// issue both lead here.
  static const String paymentDetails = '/subscription-billing/payment-details';

  /// Payment method: the selected provider and the actions around it.
  static const String paymentMethods = '/subscription-billing/payment-methods';

  /// The payment-methods family. Each is a dedicated screen; the store's own
  /// credential UI is only ever reached from the last step of one of them.
  static const String paymentMethodsAdd =
      '/subscription-billing/payment-methods/add';
  static const String paymentMethodsManage =
      '/subscription-billing/payment-methods/manage';

  /// Google Play only; the screen explains itself on the App Store.
  static const String paymentMethodsBackup =
      '/subscription-billing/payment-methods/backup';
  static const String paymentMethodsBilling =
      '/subscription-billing/payment-methods/billing';
  static const String paymentMethodsHelp =
      '/subscription-billing/payment-methods/help';

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
