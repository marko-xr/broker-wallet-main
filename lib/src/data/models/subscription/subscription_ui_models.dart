import 'package:flutter/foundation.dart';

/// Presentation models for the Broker Wallet Plus subscription experience.
///
/// Everything in this file is *display state*. None of it is entitlement
/// authority: a value here is only ever a snapshot of what a billing source
/// (later: RevenueCat reconciled by the server) reported. The UI must never
/// derive access to a feature from these types.

/// Billing period of a Plus plan as the store reports it.
enum SubscriptionPeriod { monthly, annual }

/// Where the user's subscription is billed.
enum PlusStore { appStore, googlePlay, unknown }

/// The store this device would purchase through.
PlusStore currentPlusStore() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return PlusStore.appStore;
    case TargetPlatform.android:
      return PlusStore.googlePlay;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return PlusStore.unknown;
  }
}

/// How the Plus plan should be presented for the current user.
enum SubscriptionStatus {
  free,
  trial,
  active,
  cancelledActive,
  gracePeriod,
  billingIssue,
  expired,
}

extension SubscriptionStatusX on SubscriptionStatus {
  /// The user is presented as being on the Plus plan right now.
  ///
  /// Deliberately true for [SubscriptionStatus.gracePeriod] and
  /// [SubscriptionStatus.billingIssue]: those states must not tell the user
  /// that Plus is already lost. Only [SubscriptionStatus.expired] (or free)
  /// means Plus is no longer present.
  bool get isCurrentPlus =>
      this != SubscriptionStatus.free && this != SubscriptionStatus.expired;

  /// A payment problem the user can still fix in the store.
  bool get needsPaymentAttention =>
      this == SubscriptionStatus.gracePeriod ||
      this == SubscriptionStatus.billingIssue;

  /// The subscription will renew on its own.
  bool get autoRenews =>
      this == SubscriptionStatus.active ||
      this == SubscriptionStatus.trial ||
      this == SubscriptionStatus.gracePeriod ||
      this == SubscriptionStatus.billingIssue;
}

/// One purchasable Plus plan, as supplied by the billing source.
///
/// Prices are complete, already localised store strings. Nothing in the UI may
/// build a price from a number or assume a currency.
@immutable
class SubscriptionPlanUiModel {
  const SubscriptionPlanUiModel({
    required this.id,
    required this.period,
    required this.localizedPrice,
    this.fullBillingPeriodPrice,
    this.monthlyEquivalent,
    this.savingsPercent,
    this.freeTrialDays,
    this.introductoryOfferText,
  });

  /// Opaque identifier handed back to the billing source on purchase.
  final String id;
  final SubscriptionPeriod period;

  /// Headline price for one billing period, e.g. the store's own string.
  final String localizedPrice;

  /// The amount actually charged each billing period, when the store reports
  /// it separately from [localizedPrice].
  final String? fullBillingPeriodPrice;

  /// Per-month equivalent of an annual plan. Always secondary to the full
  /// charge; never shown on its own.
  final String? monthlyEquivalent;

  /// Savings versus the monthly plan. Only ever data-supplied.
  final int? savingsPercent;

  final int? freeTrialDays;

  /// Ready-made introductory offer text from the store. Wins over a text
  /// generated from [freeTrialDays].
  final String? introductoryOfferText;

  /// The full amount charged each billing period.
  String get chargedPerPeriod => fullBillingPeriodPrice ?? localizedPrice;

  bool get hasFreeTrial =>
      (freeTrialDays ?? 0) > 0 ||
      (introductoryOfferText?.trim().isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is SubscriptionPlanUiModel &&
      other.id == id &&
      other.period == period &&
      other.localizedPrice == localizedPrice &&
      other.fullBillingPeriodPrice == fullBillingPeriodPrice &&
      other.monthlyEquivalent == monthlyEquivalent &&
      other.savingsPercent == savingsPercent &&
      other.freeTrialDays == freeTrialDays &&
      other.introductoryOfferText == introductoryOfferText;

  @override
  int get hashCode => Object.hash(
        id,
        period,
        localizedPrice,
        fullBillingPeriodPrice,
        monthlyEquivalent,
        savingsPercent,
        freeTrialDays,
        introductoryOfferText,
      );
}

/// The set of plans the billing source offers for Broker Wallet Plus.
@immutable
class SubscriptionOfferingUiModel {
  const SubscriptionOfferingUiModel({
    required this.plans,
    this.preselectedPeriod,
    this.isPreview = false,
  });

  /// No plans: subscriptions cannot be offered in this build.
  const SubscriptionOfferingUiModel.unavailable()
      : plans = const <SubscriptionPlanUiModel>[],
        preselectedPeriod = null,
        isPreview = false;

  final List<SubscriptionPlanUiModel> plans;

  /// Period the source suggests selecting first. Falls back to the first plan.
  final SubscriptionPeriod? preselectedPeriod;

  /// True when the plans are development preview data, not store prices.
  final bool isPreview;

  bool get isAvailable => plans.isNotEmpty;

  SubscriptionPlanUiModel? planFor(SubscriptionPeriod period) {
    for (final plan in plans) {
      if (plan.period == period) return plan;
    }
    return null;
  }

  SubscriptionPlanUiModel? get defaultPlan {
    if (plans.isEmpty) return null;
    final preferred = preselectedPeriod;
    if (preferred != null) {
      final match = planFor(preferred);
      if (match != null) return match;
    }
    return plans.first;
  }
}

/// A snapshot of the user's subscription for display.
///
/// Not entitlement authority. The only code allowed to produce a state other
/// than [SubscriptionUiState.free] is a billing source reporting what the
/// store says, or the debug-only preview.
@immutable
class SubscriptionUiState {
  const SubscriptionUiState({
    required this.status,
    this.period,
    this.renewsOn,
    this.expiresOn,
    this.trialEndsOn,
    this.nextChargePrice,
    this.billingPeriodPrice,
    this.store = PlusStore.unknown,
    this.managementUri,
    this.isPreview = false,
  });

  const SubscriptionUiState.free()
      : status = SubscriptionStatus.free,
        period = null,
        renewsOn = null,
        expiresOn = null,
        trialEndsOn = null,
        nextChargePrice = null,
        billingPeriodPrice = null,
        store = PlusStore.unknown,
        managementUri = null,
        isPreview = false;

  final SubscriptionStatus status;
  final SubscriptionPeriod? period;

  /// Next renewal, when the subscription will renew.
  final DateTime? renewsOn;

  /// When access ends (cancelled), the grace period ends, or when the plan
  /// expired.
  final DateTime? expiresOn;
  final DateTime? trialEndsOn;

  /// Store-formatted price of the next charge, when the source supplies it.
  /// Null when nothing will be charged (renewal off, expired).
  final String? nextChargePrice;

  /// Store-formatted full amount of one billing period, when the source
  /// supplies it. Never derived from another price.
  final String? billingPeriodPrice;

  /// The store the subscription is billed through.
  final PlusStore store;

  /// Store-provided deep link to subscription management, when known.
  final Uri? managementUri;

  /// True when this state came from the debug preview, not a billing source.
  final bool isPreview;

  bool get isCurrentPlus => status.isCurrentPlus;
}

/// Where a purchase attempt currently is.
enum PurchasePhase {
  idle,
  initiating,
  waitingForStore,
  verifying,
  finalizing,
  success,
  pending,
  cancelled,
  storeProblem,
  networkProblem,
  verificationFailed,
  unknownFailure,
}

extension PurchasePhaseX on PurchasePhase {
  bool get isInProgress =>
      this == PurchasePhase.initiating ||
      this == PurchasePhase.waitingForStore ||
      this == PurchasePhase.verifying ||
      this == PurchasePhase.finalizing;

  bool get isFailure =>
      this == PurchasePhase.storeProblem ||
      this == PurchasePhase.networkProblem ||
      this == PurchasePhase.verificationFailed ||
      this == PurchasePhase.unknownFailure;

  /// A result the user has to read, as opposed to idle or in progress.
  bool get isResult =>
      this == PurchasePhase.success ||
      this == PurchasePhase.pending ||
      this == PurchasePhase.cancelled ||
      isFailure;

  /// Zero-based position among the four progress steps, or -1.
  int get stepIndex {
    switch (this) {
      case PurchasePhase.initiating:
        return 0;
      case PurchasePhase.waitingForStore:
        return 1;
      case PurchasePhase.verifying:
        return 2;
      case PurchasePhase.finalizing:
        return 3;
      case PurchasePhase.idle:
      case PurchasePhase.success:
      case PurchasePhase.pending:
      case PurchasePhase.cancelled:
      case PurchasePhase.storeProblem:
      case PurchasePhase.networkProblem:
      case PurchasePhase.verificationFailed:
      case PurchasePhase.unknownFailure:
        return -1;
    }
  }
}

/// One step reported by a billing source during a purchase.
@immutable
class PurchaseUpdate {
  const PurchaseUpdate(this.phase, {this.entitlement});

  final PurchasePhase phase;

  /// The state the source reports once the purchase is confirmed. A
  /// [PurchasePhase.success] without one is never shown as success.
  final SubscriptionUiState? entitlement;
}

/// Where a restore attempt currently is.
enum RestorePhase {
  idle,
  restoring,
  restored,
  nothingFound,
  conflict,
  failed,
  unavailable,
}

extension RestorePhaseX on RestorePhase {
  bool get isResult =>
      this != RestorePhase.idle && this != RestorePhase.restoring;
}

/// The outcome a billing source reports for a restore.
@immutable
class RestoreResult {
  const RestoreResult(this.phase, {this.entitlement});

  final RestorePhase phase;
  final SubscriptionUiState? entitlement;
}
