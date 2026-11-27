import 'package:broker_wallet/src/services/subscription/billing_availability.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';

enum SubscriptionPlatform { android, ios, web, other }

/// Where a subscription is managed, seen from this device.
enum ManagementPath { thisStore, otherStore, tapBilling, notOnThisDevice, none }

/// What each platform may present. Android shows the purchase journey, the web
/// app takes card payments through Tap, and iPhone stays informational: no
/// provider, payment method, link or checkout step.
abstract final class SubscriptionPlatformPolicy {
  /// Set only by the debug state preview. Ignored outside debug builds.
  static SubscriptionPlatform? debugOverride;

  static SubscriptionPlatform get current {
    if (kDebugMode && debugOverride != null) return debugOverride!;
    if (kIsWeb) return SubscriptionPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => SubscriptionPlatform.android,
      TargetPlatform.iOS => SubscriptionPlatform.ios,
      _ => SubscriptionPlatform.other,
    };
  }

  static bool showsPurchaseJourney(SubscriptionPlatform platform) =>
      platform == SubscriptionPlatform.android ||
      platform == SubscriptionPlatform.web;

  /// The Tap choice inside the Android app: a debug build on the isolated
  /// Staging backend only, until Google Play billing-choice eligibility for
  /// this app in the UAE is verified. No flag or preference can widen it.
  static bool get androidCardTestAllowed =>
      kDebugMode && BillingAvailability.isStagingBackend;

  /// Google Play is the compliant Android path. Card is added only for a
  /// labelled debug sample, isolated Staging testing, or a future
  /// server-verified eligibility decision. The web app pays by card.
  static List<PaymentOption> paymentOptions(
    SubscriptionPlatform platform,
    SubscriptionPresentation presentation, {
    bool debugBuild = kDebugMode,
    bool? cardTestAllowed,
  }) {
    if (platform == SubscriptionPlatform.web) {
      return const [PaymentOption.tapCard];
    }
    if (platform != SubscriptionPlatform.android) return const [];
    final cardAllowed = presentation.tapCardEligibilityVerified ||
        (debugBuild && presentation.isSample) ||
        (cardTestAllowed ?? androidCardTestAllowed);
    return [PaymentOption.googlePlay, if (cardAllowed) PaymentOption.tapCard];
  }

  /// Whether this option can start a real, server-verified payment here.
  static bool canStartCheckout(
    SubscriptionPlatform platform,
    PaymentOption option, {
    bool? backendEnabled,
    bool? cardTestAllowed,
    bool storeAvailable = false,
  }) {
    if (!(backendEnabled ?? BillingAvailability.backendEnabled)) {
      return false;
    }
    return switch ((platform, option)) {
      (SubscriptionPlatform.web, PaymentOption.tapCard) => true,
      (SubscriptionPlatform.android, PaymentOption.tapCard) =>
        cardTestAllowed ?? androidCardTestAllowed,
      (SubscriptionPlatform.android, PaymentOption.googlePlay) => storeAvailable,
      _ => false,
    };
  }

  /// Only a debug sample may continue to the sample review screen.
  static bool canPreviewCheckout(
    SubscriptionPresentation presentation, {
    bool debugBuild = kDebugMode,
  }) =>
      debugBuild && presentation.isSample;

  /// The owner's proposed iPhone web-activation sheet, for design review.
  /// Apple's rules for the UAE storefront do not allow it in a store build,
  /// so it is compiled out of release and no server value can turn it on.
  static bool canShowIosWebActivationPreview({bool debugBuild = kDebugMode}) =>
      debugBuild;

  /// Receipts, payment method and restore rows. On iPhone they appear only
  /// for a verified App Store subscription.
  static bool showsStoreDetails(
    SubscriptionPlatform platform,
    SubscriptionPresentation presentation,
  ) =>
      platform == SubscriptionPlatform.android ||
      platform == SubscriptionPlatform.web ||
      (platform == SubscriptionPlatform.ios &&
          presentation.provider == BillingProvider.appStore);

  /// Restoring reads the device's store, which a browser does not have.
  static bool showsRestore(SubscriptionPlatform platform) =>
      platform == SubscriptionPlatform.android;

  /// A Tap subscription is never named on a device that must not show Tap.
  static bool hidesProvider(
    SubscriptionPlatform platform,
    BillingProvider? provider,
  ) =>
      provider == BillingProvider.tap &&
      platform != SubscriptionPlatform.android &&
      platform != SubscriptionPlatform.web;

  /// Each provider keeps its own management path: no provider can cancel a
  /// subscription that another provider bills.
  static ManagementPath managementPath(
    SubscriptionPlatform platform,
    BillingProvider? provider,
  ) {
    if (provider == null) return ManagementPath.none;
    return switch ((platform, provider)) {
      (SubscriptionPlatform.android, BillingProvider.googlePlay) ||
      (SubscriptionPlatform.ios, BillingProvider.appStore) =>
        ManagementPath.thisStore,
      (SubscriptionPlatform.android, BillingProvider.appStore) ||
      (SubscriptionPlatform.ios, BillingProvider.googlePlay) ||
      (SubscriptionPlatform.web, BillingProvider.googlePlay) ||
      (SubscriptionPlatform.web, BillingProvider.appStore) =>
        ManagementPath.otherStore,
      (SubscriptionPlatform.android, BillingProvider.tap) ||
      (SubscriptionPlatform.web, BillingProvider.tap) =>
        ManagementPath.tapBilling,
      _ => ManagementPath.notOnThisDevice,
    };
  }
}
