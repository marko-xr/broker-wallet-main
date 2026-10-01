import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/services/subscription/plus_billing_gateway.dart';

/// DEBUG-ONLY presentation preview for the Plus experience.
///
/// This exists so every subscription screen and state can be looked at before
/// real billing exists. It is created only when `kDebugMode` is true (see the
/// provider in `main.dart`), so a release or profile build never contains a
/// path that produces anything but the unavailable gateway.
///
/// What it is not: it never touches Supabase, Firestore, RevenueCat or any
/// store, persists nothing, and every state it produces carries
/// `isPreview: true`. The prices below are layout placeholders, not proposed
/// pricing and not a currency decision.

/// Which plans the preview offering contains.
enum DebugOfferingMode { both, monthlyOnly, annualOnly, none }

/// Mutable knobs the debug sheet turns.
class DebugPlusPreviewConfig {
  DebugOfferingMode offeringMode = DebugOfferingMode.both;

  /// Free-trial length applied to every preview plan; 0 means no trial.
  int trialDays = 0;

  /// The terminal phase the next preview purchase ends in.
  PurchasePhase purchaseOutcome = PurchasePhase.success;

  /// The phase the next preview restore ends in.
  RestorePhase restoreOutcome = RestorePhase.restored;
}

/// Placeholder store strings used by the preview.
class DebugPlusPreviewData {
  const DebugPlusPreviewData._();

  static const String monthlyPrice = 'AED 9.99';
  static const String annualPrice = 'AED 99.99';
  static const String annualMonthlyEquivalent = 'AED 8.33';
  static const int annualSavingsPercent = 17;
  static const int previewTrialDays = 7;

  static String priceFor(SubscriptionPeriod period) =>
      period == SubscriptionPeriod.monthly ? monthlyPrice : annualPrice;

  /// A representative [SubscriptionUiState] for [status], billed through
  /// [store] (this device's store when omitted).
  static SubscriptionUiState entitlementFor(
    SubscriptionStatus status, {
    SubscriptionPeriod period = SubscriptionPeriod.annual,
    PlusStore? store,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    final billedThrough = store ?? currentPlusStore();
    final cycleDays = period == SubscriptionPeriod.monthly ? 23 : 214;
    final price = priceFor(period);

    switch (status) {
      case SubscriptionStatus.free:
        return const SubscriptionUiState.free();
      case SubscriptionStatus.trial:
        final trialEnd = base.add(const Duration(days: previewTrialDays));
        return SubscriptionUiState(
          status: status,
          period: period,
          trialEndsOn: trialEnd,
          renewsOn: trialEnd,
          nextChargePrice: price,
          billingPeriodPrice: price,
          store: billedThrough,
          isPreview: true,
        );
      case SubscriptionStatus.active:
        return SubscriptionUiState(
          status: status,
          period: period,
          renewsOn: base.add(Duration(days: cycleDays)),
          nextChargePrice: price,
          billingPeriodPrice: price,
          store: billedThrough,
          isPreview: true,
        );
      case SubscriptionStatus.cancelledActive:
        return SubscriptionUiState(
          status: status,
          period: period,
          expiresOn: base.add(Duration(days: cycleDays)),
          billingPeriodPrice: price,
          store: billedThrough,
          isPreview: true,
        );
      case SubscriptionStatus.gracePeriod:
        return SubscriptionUiState(
          status: status,
          period: period,
          expiresOn: base.add(const Duration(days: 5)),
          nextChargePrice: price,
          billingPeriodPrice: price,
          store: billedThrough,
          isPreview: true,
        );
      case SubscriptionStatus.billingIssue:
        return SubscriptionUiState(
          status: status,
          period: period,
          nextChargePrice: price,
          billingPeriodPrice: price,
          store: billedThrough,
          isPreview: true,
        );
      case SubscriptionStatus.expired:
        return SubscriptionUiState(
          status: status,
          period: period,
          expiresOn: base.subtract(const Duration(days: 12)),
          store: billedThrough,
          isPreview: true,
        );
    }
  }
}

class DebugPlusBillingGateway implements PlusBillingGateway {
  DebugPlusBillingGateway({
    DebugPlusPreviewConfig? config,
    this.stepDelay = const Duration(milliseconds: 900),
  })  : assert(kDebugMode, 'The Plus preview gateway is debug-only.'),
        config = config ?? DebugPlusPreviewConfig();

  final DebugPlusPreviewConfig config;

  /// How long each preview purchase step stays on screen.
  final Duration stepDelay;

  @override
  bool get isBillingAvailable => true;

  @override
  Future<SubscriptionOfferingUiModel> loadOffering() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final mode = config.offeringMode;
    if (mode == DebugOfferingMode.none) {
      return const SubscriptionOfferingUiModel.unavailable();
    }
    final trial = config.trialDays > 0 ? config.trialDays : null;

    final monthly = SubscriptionPlanUiModel(
      id: 'debug.preview.monthly',
      period: SubscriptionPeriod.monthly,
      localizedPrice: DebugPlusPreviewData.monthlyPrice,
      freeTrialDays: trial,
    );
    final annual = SubscriptionPlanUiModel(
      id: 'debug.preview.annual',
      period: SubscriptionPeriod.annual,
      localizedPrice: DebugPlusPreviewData.annualPrice,
      fullBillingPeriodPrice: DebugPlusPreviewData.annualPrice,
      monthlyEquivalent: DebugPlusPreviewData.annualMonthlyEquivalent,
      savingsPercent: DebugPlusPreviewData.annualSavingsPercent,
      freeTrialDays: trial,
    );

    switch (mode) {
      case DebugOfferingMode.both:
        return SubscriptionOfferingUiModel(
          plans: [monthly, annual],
          preselectedPeriod: SubscriptionPeriod.annual,
          isPreview: true,
        );
      case DebugOfferingMode.monthlyOnly:
        return SubscriptionOfferingUiModel(plans: [monthly], isPreview: true);
      case DebugOfferingMode.annualOnly:
        return SubscriptionOfferingUiModel(plans: [annual], isPreview: true);
      case DebugOfferingMode.none:
        return const SubscriptionOfferingUiModel.unavailable();
    }
  }

  @override
  Stream<PurchaseUpdate> purchase(SubscriptionPlanUiModel plan) async* {
    final outcome = config.purchaseOutcome;
    for (final phase in _phasesBefore(outcome)) {
      yield PurchaseUpdate(phase);
      await Future<void>.delayed(stepDelay);
    }
    yield PurchaseUpdate(
      outcome,
      entitlement: outcome == PurchasePhase.success
          ? _entitlementForPurchase(plan)
          : null,
    );
  }

  @override
  Future<RestoreResult> restorePurchases() async {
    await Future<void>.delayed(stepDelay * 2);
    final outcome = config.restoreOutcome;
    return RestoreResult(
      outcome,
      entitlement: outcome == RestorePhase.restored
          ? DebugPlusPreviewData.entitlementFor(SubscriptionStatus.active)
          : null,
    );
  }

  /// Progress steps shown before [outcome] is reported, so a cancelled
  /// purchase stops at the store sheet and a verification failure stops at
  /// verification, as the real flow would.
  List<PurchasePhase> _phasesBefore(PurchasePhase outcome) {
    switch (outcome) {
      case PurchasePhase.success:
        return const [
          PurchasePhase.initiating,
          PurchasePhase.waitingForStore,
          PurchasePhase.verifying,
          PurchasePhase.finalizing,
        ];
      case PurchasePhase.pending:
      case PurchasePhase.verificationFailed:
        return const [
          PurchasePhase.initiating,
          PurchasePhase.waitingForStore,
          PurchasePhase.verifying,
        ];
      case PurchasePhase.cancelled:
      case PurchasePhase.storeProblem:
      case PurchasePhase.networkProblem:
        return const [
          PurchasePhase.initiating,
          PurchasePhase.waitingForStore,
        ];
      case PurchasePhase.unknownFailure:
      case PurchasePhase.idle:
      case PurchasePhase.initiating:
      case PurchasePhase.waitingForStore:
      case PurchasePhase.verifying:
      case PurchasePhase.finalizing:
        return const [PurchasePhase.initiating];
    }
  }

  SubscriptionUiState _entitlementForPurchase(SubscriptionPlanUiModel plan) {
    final now = DateTime.now();
    final trialDays = plan.freeTrialDays ?? 0;
    if (trialDays > 0) {
      final trialEnd = now.add(Duration(days: trialDays));
      return SubscriptionUiState(
        status: SubscriptionStatus.trial,
        period: plan.period,
        trialEndsOn: trialEnd,
        renewsOn: trialEnd,
        nextChargePrice: plan.chargedPerPeriod,
        billingPeriodPrice: plan.chargedPerPeriod,
        store: currentPlusStore(),
        isPreview: true,
      );
    }
    return DebugPlusPreviewData.entitlementFor(
      SubscriptionStatus.active,
      period: plan.period,
      now: now,
    ).withPrices(plan.chargedPerPeriod);
  }
}

extension on SubscriptionUiState {
  /// Same state, with the previewed plan's own price as both amounts.
  SubscriptionUiState withPrices(String price) => SubscriptionUiState(
        status: status,
        period: period,
        renewsOn: renewsOn,
        expiresOn: expiresOn,
        trialEndsOn: trialEndsOn,
        nextChargePrice: price,
        billingPeriodPrice: price,
        store: store,
        managementUri: managementUri,
        isPreview: isPreview,
      );
}
