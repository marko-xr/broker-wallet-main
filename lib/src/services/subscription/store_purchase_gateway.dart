import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';

/// What the store reported for a purchase or restore. None of these grants
/// anything: Plus starts only when the trusted server confirms it.
enum StorePurchaseOutcome { purchased, cancelled, pending, failed, unavailable }

/// A plan as the store returned it, with the store's own localized price.
class StoreProduct {
  const StoreProduct({required this.cycle, required this.priceLabel});

  final PlusBillingCycle cycle;
  final String priceLabel;
}

/// A store answer, with the purchase tokens the server must verify.
class StorePurchaseResult {
  const StorePurchaseResult(this.outcome, {this.purchaseTokens = const []});

  final StorePurchaseOutcome outcome;
  final List<String> purchaseTokens;
}

/// The app's boundary to Google Play Billing.
///
/// `GooglePlayStoreGateway` implements it in the Android app;
/// [UnavailableStoreGateway] keeps every other platform closed. An
/// implementation must leave acknowledgement to the server.
abstract interface class StorePurchaseGateway {
  bool get isAvailable;

  Future<List<StoreProduct>> loadProducts();

  /// Buys [cycle] under [accountReference], the opaque id issued by the server.
  Future<StorePurchaseResult> purchase(
    PlusBillingCycle cycle, {
    required String accountReference,
  });

  /// The store's active purchases on this device, for the server to verify.
  Future<StorePurchaseResult> restore();
}

class UnavailableStoreGateway implements StorePurchaseGateway {
  const UnavailableStoreGateway();

  @override
  bool get isAvailable => false;

  @override
  Future<List<StoreProduct>> loadProducts() async => const [];

  @override
  Future<StorePurchaseResult> purchase(
    PlusBillingCycle cycle, {
    required String accountReference,
  }) async =>
      const StorePurchaseResult(StorePurchaseOutcome.unavailable);

  @override
  Future<StorePurchaseResult> restore() async =>
      const StorePurchaseResult(StorePurchaseOutcome.unavailable);
}
