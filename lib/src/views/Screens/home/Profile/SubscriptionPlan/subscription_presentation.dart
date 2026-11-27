import 'package:flutter/foundation.dart';

/// What the Profile subscription screens may show. Nothing in this file reads,
/// grants or stores an entitlement: a future trusted server or store source
/// fills these values. Until then every screen gets [unavailable].
enum SubscriptionStatus {
  loading,
  unavailable,
  offline,
  free,
  plusRenewing,
  plusCancelScheduled,
  paymentIssue,
  activationPending,
  expiredOverLimit,
  expiredWithinFree,
}

enum PlusBillingCycle { monthly, annual }

enum BillingProvider { appStore, googlePlay, tap }

/// A way to pay shown in the Android payment sheet. This is presentation only:
/// no option starts a transaction.
enum PaymentOption { googlePlay, tapCard }

enum PaymentSheetState { ready, loading, providerUnavailable }

/// The 11 independent Free usage categories.
enum UsageCategory {
  owners,
  offers,
  requests,
  watchmen,
  offices,
  brokers,
  quotations,
  scanner,
  signature,
  imagesToPdf,
  combinePdfs;

  static const records = [owners, offers, requests, watchmen, offices, brokers];
  static const toolkit = [scanner, signature, imagesToPdf, combinePdfs];
}

enum UsageDataState { loading, unavailable, empty, populated }

enum PriceDataState { loading, unavailable, reference, store }

enum RestorePurchaseState {
  ready,
  checking,
  nothingFound,
  unavailable,
  linkedToOtherAccount,
  restored,
}

enum SubscriptionFlowState {
  priceLoading,
  pricesUnavailable,
  purchaseReview,
  purchaseCanceled,
  purchasePending,
  purchaseFailed,
  activationPending,
  activationSuccess,
  verificationFailed,
  entitlementMismatch,
  providerUnavailable,
}

/// What the debug payment sheet hands to the sample review screen.
@immutable
class PaymentReviewRequest {
  const PaymentReviewRequest({required this.cycle, required this.option});

  final PlusBillingCycle cycle;
  final PaymentOption option;
}

/// A price in AED. [storeLabel] is the localized price a store returned; when
/// present it replaces the approved reference amount on screen.
@immutable
class PlanPrice {
  const PlanPrice(this.fils, {this.storeLabel});

  final int fils;
  final String? storeLabel;

  String get amount {
    final whole = fils ~/ 100;
    final part = (fils % 100).toString().padLeft(2, '0');
    return '$whole.$part';
  }
}

/// Approved reference figures for display. The store remains the authority
/// for the final price at checkout.
abstract final class SubscriptionPolicy {
  static const monthlyPrice = PlanPrice(2000);
  static const annualPrice = PlanPrice(18000);
  static const annualMonthlyEquivalent = PlanPrice(1500);
  static const annualSavingPercent = 25;
  static const freeCreationsPerCategory = 5;
  static const freeEditsPerItem = 3;
}

abstract final class SubscriptionRoutes {
  static const limits = '/subscription-limits';
  static const compare = '/subscription-compare';
  static const usage = '/subscription-usage';
  static const manage = '/subscription-manage';
  static const cancellation = '/subscription-cancellation';
  static const restore = '/subscription-restore';
  static const checkout = '/subscription-checkout';
  static const playCheckout = '/subscription-play';
  static const changeCard = '/subscription-change-card';
  static const paymentReturn = '/subscription-return';
  static const preview = '/subscription-preview';
  static const flowState = '/subscription-preview-state';
}

/// Free edits used on one record. Each record has its own allowance.
@immutable
class ItemEditUsage {
  const ItemEditUsage({
    required this.category,
    required this.title,
    required this.editsUsed,
  });

  final UsageCategory category;
  final String title;
  final int editsUsed;

  bool get isExhausted => editsUsed >= SubscriptionPolicy.freeEditsPerItem;
}

@immutable
class UsageSnapshot {
  const UsageSnapshot({
    required this.state,
    this.created = const {},
    this.items = const [],
  });

  const UsageSnapshot.unavailable()
      : state = UsageDataState.unavailable,
        created = const {},
        items = const [];

  final UsageDataState state;
  final Map<UsageCategory, int> created;
  final List<ItemEditUsage> items;

  /// Null means no trusted count exists; it is never shown as zero.
  int? createdFor(UsageCategory category) => switch (state) {
        UsageDataState.empty => 0,
        UsageDataState.populated => created[category],
        UsageDataState.loading || UsageDataState.unavailable => null,
      };
}

@immutable
class SubscriptionPresentation {
  const SubscriptionPresentation({
    required this.status,
    this.cycle,
    this.provider,
    this.startedAt,
    this.paidThrough,
    this.nextChargeAt,
    this.renewalPrice,
    this.usage = const UsageSnapshot.unavailable(),
    this.prices = PriceDataState.reference,
    this.isSample = false,
    this.tapCardEligibilityVerified = false,
  });

  /// The production default: no trusted subscription source is connected.
  const SubscriptionPresentation.unavailable()
      : status = SubscriptionStatus.unavailable,
        cycle = null,
        provider = null,
        startedAt = null,
        paidThrough = null,
        nextChargeAt = null,
        renewalPrice = null,
        usage = const UsageSnapshot.unavailable(),
        prices = PriceDataState.reference,
        isSample = false,
        tapCardEligibilityVerified = false;

  final SubscriptionStatus status;
  final PlusBillingCycle? cycle;
  final BillingProvider? provider;
  final DateTime? startedAt;
  final DateTime? paidThrough;
  final DateTime? nextChargeAt;
  final PlanPrice? renewalPrice;
  final UsageSnapshot usage;
  final PriceDataState prices;

  /// True only for labelled design previews in debug builds.
  final bool isSample;

  /// A future trusted server decision that this account and storefront may be
  /// offered card billing next to Google Play. Nothing in the app can set it:
  /// no preference, build flag or user action reaches this field.
  final bool tapCardEligibilityVerified;

  /// Only these two states present Plus as active.
  bool get hasVerifiedPlus =>
      status == SubscriptionStatus.plusRenewing ||
      status == SubscriptionStatus.plusCancelScheduled;

  bool get isUnconfirmed =>
      status == SubscriptionStatus.loading ||
      status == SubscriptionStatus.unavailable ||
      status == SubscriptionStatus.offline;

  /// A next charge exists only while auto-renewal is on.
  DateTime? get nextPaymentDate =>
      status == SubscriptionStatus.plusRenewing ? nextChargeAt : null;
}
