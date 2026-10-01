import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';

/// The single seam between the Plus UI and whatever actually sells it.
///
/// Today nothing real implements this: release builds use
/// [UnavailablePlusBillingGateway] and debug builds may use the preview
/// gateway. When Google Play Billing / StoreKit arrive through RevenueCat, an
/// implementation of this interface is the *only* thing that has to change —
/// the screens only ever see [SubscriptionPlanUiModel], [PurchaseUpdate],
/// [RestoreResult] and [SubscriptionUiState].
///
/// Contract for a real implementation:
///  * report a [PurchasePhase.success] only with an entitlement the store and
///    server have confirmed; pending or unverified purchases must be reported
///    as [PurchasePhase.pending] / [PurchasePhase.verificationFailed];
///  * never fabricate an entitlement on restore;
///  * surface failures as phases, never as raw exceptions.
abstract class PlusBillingGateway {
  /// Whether this build can sell or restore subscriptions at all.
  bool get isBillingAvailable;

  /// The plans to offer, with complete store-localised prices.
  Future<SubscriptionOfferingUiModel> loadOffering();

  /// Runs a purchase, reporting each phase. The stream must end after a
  /// terminal phase.
  Stream<PurchaseUpdate> purchase(SubscriptionPlanUiModel plan);

  Future<RestoreResult> restorePurchases();
}

/// Used wherever no billing source exists, which is every build until
/// subscriptions are integrated. It offers nothing and unlocks nothing.
class UnavailablePlusBillingGateway implements PlusBillingGateway {
  const UnavailablePlusBillingGateway();

  @override
  bool get isBillingAvailable => false;

  @override
  Future<SubscriptionOfferingUiModel> loadOffering() async =>
      const SubscriptionOfferingUiModel.unavailable();

  @override
  Stream<PurchaseUpdate> purchase(SubscriptionPlanUiModel plan) =>
      Stream<PurchaseUpdate>.value(
        const PurchaseUpdate(PurchasePhase.unknownFailure),
      );

  @override
  Future<RestoreResult> restorePurchases() async =>
      const RestoreResult(RestorePhase.unavailable);
}
