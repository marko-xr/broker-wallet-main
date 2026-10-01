import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';

/// Visual weight of a status or notice. Colours come from the theme only:
/// positive uses the brand primary, attention uses the theme's error colour.
enum PlusTone { positive, neutral, attention }

Color plusToneColor(ColorScheme colors, PlusTone tone) {
  switch (tone) {
    case PlusTone.positive:
      return colors.primary;
    case PlusTone.neutral:
      return colors.onSurface.withValues(alpha: 0.7);
    case PlusTone.attention:
      return colors.error;
  }
}

/// A payment problem asks for attention; an ended or cancelled plan is just a
/// state, so it stays calm.
PlusTone plusStatusTone(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.active:
    case SubscriptionStatus.trial:
      return PlusTone.positive;
    case SubscriptionStatus.free:
    case SubscriptionStatus.cancelledActive:
    case SubscriptionStatus.expired:
      return PlusTone.neutral;
    case SubscriptionStatus.gracePeriod:
    case SubscriptionStatus.billingIssue:
      return PlusTone.attention;
  }
}

IconData plusStatusIcon(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.free:
      return Icons.workspace_premium_outlined;
    case SubscriptionStatus.active:
      return Icons.verified_rounded;
    case SubscriptionStatus.trial:
      return Icons.timelapse_rounded;
    case SubscriptionStatus.cancelledActive:
      return Icons.event_available_rounded;
    case SubscriptionStatus.gracePeriod:
      return Icons.hourglass_bottom_rounded;
    case SubscriptionStatus.billingIssue:
      return Icons.error_outline_rounded;
    case SubscriptionStatus.expired:
      return Icons.event_busy_rounded;
  }
}

String plusStatusLabel(AppLocalizations l10n, SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.free:
      return l10n.translate('freePlan');
    case SubscriptionStatus.active:
      return l10n.translate('plusStatusActive');
    case SubscriptionStatus.trial:
      return l10n.translate('plusStatusTrial');
    case SubscriptionStatus.cancelledActive:
      return l10n.translate('plusStatusCancelledActive');
    case SubscriptionStatus.gracePeriod:
      return l10n.translate('plusStatusGracePeriod');
    case SubscriptionStatus.billingIssue:
      return l10n.translate('plusStatusBillingIssue');
    case SubscriptionStatus.expired:
      return l10n.translate('plusStatusExpired');
  }
}

String plusStoreName(AppLocalizations l10n, PlusStore store) {
  switch (store) {
    case PlusStore.appStore:
      return l10n.translate('plusStoreAppStore');
    case PlusStore.googlePlay:
      return l10n.translate('plusStoreGooglePlay');
    case PlusStore.unknown:
      return l10n.translate('plusStoreGeneric');
  }
}

String plusPeriodName(AppLocalizations l10n, SubscriptionPeriod period) {
  return period == SubscriptionPeriod.monthly
      ? l10n.translate('plusPeriodMonthly')
      : l10n.translate('plusPeriodAnnual');
}

/// "{price} / month" or "{price} / year". The price is an opaque store string.
String plusPricePerPeriod(
  AppLocalizations l10n,
  String price,
  SubscriptionPeriod period,
) {
  return l10n.plusText(
    period == SubscriptionPeriod.monthly
        ? 'plusPricePerMonth'
        : 'plusPricePerYear',
    {'price': price},
  );
}

/// "Annual • USD 49.99 / year", or just the period when no price was supplied.
String plusPeriodPriceLine(
  AppLocalizations l10n,
  SubscriptionPeriod period,
  String? price,
) {
  if (price == null || price.trim().isEmpty) {
    return plusPeriodName(l10n, period);
  }
  return l10n.plusText('plusPeriodPriceLine', {
    'period': plusPeriodName(l10n, period),
    'price': plusPricePerPeriod(l10n, price, period),
  });
}

/// How often the subscription renews, e.g. "Every year until cancelled".
String plusRenewalFrequency(AppLocalizations l10n, SubscriptionPeriod period) {
  return period == SubscriptionPeriod.monthly
      ? l10n.translate('plusRenewsMonthly')
      : l10n.translate('plusRenewsAnnually');
}

/// What is actually charged, in words. For an annual plan this always states
/// the full annual charge.
String plusBilledDescription(AppLocalizations l10n, SubscriptionPlanUiModel p) {
  return l10n.plusText(
    p.period == SubscriptionPeriod.monthly
        ? 'plusBilledMonthly'
        : 'plusBilledAnnually',
    {'price': p.chargedPerPeriod},
  );
}

/// Introductory offer text for [plan], or null when it has none. A store
/// supplied text always wins over a generated one.
String? plusTrialDescription(
  AppLocalizations l10n,
  SubscriptionPlanUiModel plan,
) {
  final supplied = plan.introductoryOfferText?.trim();
  if (supplied != null && supplied.isNotEmpty) return supplied;
  final days = plan.freeTrialDays ?? 0;
  if (days <= 0) return null;
  return l10n.plusText(
    plan.period == SubscriptionPeriod.monthly
        ? 'plusTrialThenMonthly'
        : 'plusTrialThenAnnually',
    {'days': '$days', 'price': plan.chargedPerPeriod},
  );
}

/// A renewal or expiry date with the year and the full month name (for example
/// "January 15, 2027"), in the active language's own month names and digits,
/// so it is unambiguous for any reader.
String plusFormatDate(BuildContext context, DateTime date) {
  try {
    return DateFormat.yMMMMd(Localizations.localeOf(context).toString())
        .format(date);
  } catch (_) {
    return MaterialLocalizations.of(context).formatFullDate(date);
  }
}

/// The compact form of [plusFormatDate] ("Jan 15, 2027") for tiles and chips.
String plusFormatShortDate(BuildContext context, DateTime date) {
  try {
    return DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(date);
  } catch (_) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
}

/// A thing the user can ask the store to do. Broker Wallet performs none of
/// them: each one only explains, and later hands off to, the store.
enum PlusManageAction {
  /// Review, change or cancel the subscription.
  manage,

  /// Switch between the monthly and the annual billing period.
  changePeriod,

  /// Turn renewal back on after cancelling.
  resubscribe,

  /// Add a payment method to the store account.
  addPaymentMethod,

  /// Review, edit or remove the store account's payment methods.
  managePaymentMethods,

  /// Google Play only: set up a backup payment method.
  backupPaymentMethods,

  /// Fix the payment method behind a payment issue.
  updatePaymentMethod,
}

extension PlusManageActionX on PlusManageAction {
  /// Actions about the payment method rather than the subscription itself.
  bool get isPaymentMethodAction =>
      this == PlusManageAction.addPaymentMethod ||
      this == PlusManageAction.managePaymentMethods ||
      this == PlusManageAction.backupPaymentMethods ||
      this == PlusManageAction.updatePaymentMethod;
}

/// Where [action] is carried out for [store], or null when there is no public
/// link that is safe to assume.
///
/// This is the one place a native hand-off plugs in later (StoreKit's
/// subscription-management sheet, Play's management deep link). A link the
/// billing source supplies wins for the subscription actions. The payment
/// methods of a store account have no documented link, so adding, managing or
/// backing them up is guidance only (null). Fixing the payment method behind a
/// Google Play subscription opens that subscription's own page; the App Store
/// keeps payment methods in Settings, which no link reaches, so it is guidance
/// only there.
Uri? plusManagementUri(
  PlusStore store,
  PlusManageAction action, {
  Uri? supplied,
}) {
  switch (action) {
    case PlusManageAction.manage:
    case PlusManageAction.changePeriod:
    case PlusManageAction.resubscribe:
      return _subscriptionPage(store, supplied);
    case PlusManageAction.updatePaymentMethod:
      return store == PlusStore.googlePlay
          ? _subscriptionPage(store, supplied)
          : null;
    case PlusManageAction.addPaymentMethod:
    case PlusManageAction.managePaymentMethods:
    case PlusManageAction.backupPaymentMethods:
      return null;
  }
}

Uri? _subscriptionPage(PlusStore store, Uri? supplied) {
  if (supplied != null) return supplied;
  switch (store) {
    case PlusStore.googlePlay:
      return Uri.parse('https://play.google.com/store/account/subscriptions');
    case PlusStore.appStore:
      return Uri.parse('https://apps.apple.com/account/subscriptions');
    case PlusStore.unknown:
      return null;
  }
}

/// "Managed by Apple" / "Managed by Google Play": who owns the payment method.
String plusManagedByText(AppLocalizations l10n, PlusStore store) {
  switch (store) {
    case PlusStore.appStore:
      return l10n.translate('plusManagedByApple');
    case PlusStore.googlePlay:
      return l10n.translate('plusManagedByGoogle');
    case PlusStore.unknown:
      return l10n.translate('plusManagedByGeneric');
  }
}

/// The calm sentence under a payment-issue notice. During a grace period it
/// says Plus stays active until the supplied date; otherwise it says only that
/// Plus access follows the store's own subscription status. It never says the
/// subscription ended.
String plusPaymentIssueBody(
  BuildContext context,
  AppLocalizations l10n,
  SubscriptionUiState state,
  PlusStore store,
) {
  final storeName = plusStoreName(l10n, store);
  if (state.status == SubscriptionStatus.gracePeriod) {
    final until = state.expiresOn;
    return until != null
        ? l10n.plusText('plusIssueGraceBody', {
            'store': storeName,
            'date': plusFormatDate(context, until),
          })
        : l10n.plusText('plusIssueGraceBodyNoDate', {'store': storeName});
  }
  return l10n.plusText('plusIssueBody', {'store': storeName});
}

/// The one-line status summary on the Profile "Subscription & Billing" tile,
/// built only from [state]: nothing here is a fixed example.
String plusProfileTileSubtitle(
  BuildContext context,
  AppLocalizations l10n,
  SubscriptionUiState state,
) {
  const separator = ' • ';
  final plus = l10n.translate('plusPlanShort');
  final period = state.period;

  switch (state.status) {
    case SubscriptionStatus.free:
      return '${l10n.translate('freePlan')}$separator'
          '${l10n.translate('plusUpgradeToPlus')}';
    case SubscriptionStatus.active:
      return [
        plus,
        plusStatusLabel(l10n, SubscriptionStatus.active),
        if (period != null) plusPeriodName(l10n, period),
      ].join(separator);
    case SubscriptionStatus.trial:
      final ends = state.trialEndsOn;
      return [
        plus,
        plusStatusLabel(l10n, SubscriptionStatus.trial),
        if (ends != null)
          l10n.plusText(
            'plusTileEnds',
            {'date': plusFormatShortDate(context, ends)},
          ),
      ].join(separator);
    case SubscriptionStatus.cancelledActive:
      final until = state.expiresOn;
      return [
        plus,
        until != null
            ? l10n.plusText(
                'plusTileActiveUntil',
                {'date': plusFormatShortDate(context, until)},
              )
            : plusStatusLabel(l10n, SubscriptionStatus.cancelledActive),
      ].join(separator);
    case SubscriptionStatus.gracePeriod:
    case SubscriptionStatus.billingIssue:
      return [
        plus,
        plusStatusLabel(l10n, SubscriptionStatus.billingIssue),
      ].join(separator);
    case SubscriptionStatus.expired:
      return [
        plus,
        plusStatusLabel(l10n, SubscriptionStatus.expired),
      ].join(separator);
  }
}

/// The single most useful date line for the plan summary ("Renews on …",
/// "Active until …"), or null when the state carries no such date.
String? plusHeroDateLine(
  BuildContext context,
  AppLocalizations l10n,
  SubscriptionUiState state,
) {
  String? line(String key, DateTime? date) => date == null
      ? null
      : l10n.plusText(key, {'date': plusFormatDate(context, date)});

  switch (state.status) {
    case SubscriptionStatus.active:
      return line('plusHeroRenewsOn', state.renewsOn);
    case SubscriptionStatus.trial:
      return line('plusHeroTrialEnds', state.trialEndsOn);
    case SubscriptionStatus.cancelledActive:
      return line('plusHeroActiveUntil', state.expiresOn);
    case SubscriptionStatus.gracePeriod:
      return line('plusHeroGraceUntil', state.expiresOn);
    case SubscriptionStatus.expired:
      return line('plusHeroExpiredOn', state.expiresOn);
    case SubscriptionStatus.billingIssue:
    case SubscriptionStatus.free:
      return null;
  }
}
