import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_manage_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Building blocks for the payment screens (Payment details, Payment method,
/// Manage payment methods, Add payment method, Manage billing).
///
/// They give those screens the look of a payment product rather than a settings
/// list: large rounded cards, one clear selected provider, a payment summary,
/// and one obvious action per screen. Everything uses the Broker Wallet theme.
///
/// What they never do: show a card number, expiry, CVV, cardholder, bank
/// account, card brand or "default" marker. Google Play and the Apple Account
/// do not hand Broker Wallet a list of saved payment methods, so none is
/// invented; the provider itself is what these cards present. The credentials
/// belong to the store.

const double _kCardRadius = 20;

/// Google Play is a store; an Apple Account is an account. The icons differ so
/// the two platforms do not look like one screen with a word swapped.
IconData plusProviderIcon(PlusStore store) {
  return store == PlusStore.appStore
      ? Icons.account_circle_outlined
      : Icons.storefront_outlined;
}

String plusProviderTitle(AppLocalizations l10n, PlusStore store) {
  switch (store) {
    case PlusStore.googlePlay:
      return l10n.translate('plusStoreGooglePlay');
    case PlusStore.appStore:
      return l10n.translate('plusPmProviderApple');
    case PlusStore.unknown:
      return l10n.translate('plusPmProviderGeneric');
  }
}

/// "Managed securely by Google Play" — who holds the payment credentials.
String plusManagedSecurelyText(AppLocalizations l10n, PlusStore store) {
  switch (store) {
    case PlusStore.googlePlay:
      return l10n.translate('plusPdManagedGoogle');
    case PlusStore.appStore:
      return l10n.translate('plusPdManagedApple');
    case PlusStore.unknown:
      return l10n.translate('plusPdManagedGeneric');
  }
}

/// The provider's mark: a rounded tile with the provider's icon in the brand
/// colour. No logo asset is used or copied.
class PlusProviderMark extends StatelessWidget {
  const PlusProviderMark({super.key, required this.store, this.size = 56});

  final PlusStore store;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        plusProviderIcon(store),
        color: colors.primary,
        size: size * 0.5,
      ),
    );
  }
}

/// The payment provider as a large card: its mark, name, a caption, and (when
/// [selected]) a clear selected state with a check, like a chosen payment
/// method. [trailing] is an action such as "Change". [child] sits under the
/// row inside the same card (for example a payment-issue message and its fix).
///
/// At large text sizes [trailing] drops below the row so neither the name nor
/// the button is squeezed.
class PlusProviderCard extends StatelessWidget {
  const PlusProviderCard({
    super.key,
    required this.store,
    required this.caption,
    this.detail,
    this.selected = false,
    this.attention = false,
    this.trailing,
    this.child,
  });

  final PlusStore store;
  final String caption;

  /// A quieter line under the caption, shown with a lock.
  final String? detail;
  final bool selected;

  /// Highlights the card for a payment problem (a calm tint, not an alarm).
  final bool attention;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;

    final accent = attention ? colors.error : colors.primary;
    final highlighted = selected || attention;

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plusProviderTitle(l10n, store),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.8),
            height: 1.35,
          ),
        ),
      ],
    );

    final inline = trailing != null && !largeText;
    final below = trailing != null && largeText;

    return Semantics(
      container: true,
      selected: selected,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlighted
              ? accent.withValues(alpha: attention ? 0.06 : 0.07)
              : colors.surface,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(
            color: highlighted
                ? accent.withValues(alpha: attention ? 0.45 : 1)
                : colors.outline.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlusProviderMark(store: store),
                const SizedBox(width: 16),
                Expanded(child: texts),
                if (inline) ...[const SizedBox(width: 12), trailing!],
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, color: colors.primary),
                ],
              ],
            ),
            if (below) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: trailing!,
              ),
            ],
            if (detail != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: colors.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (child != null) ...[const SizedBox(height: 16), child!],
          ],
        ),
      ),
    );
  }
}

/// A compact outlined button for a card's trailing action ("Change").
class PlusCardButton extends StatelessWidget {
  const PlusCardButton(
      {super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The payment summary: what is being paid for and how it is billed, as one
/// clean card. Only values the billing source supplied appear; there is no
/// subtotal, tax, discount or total, because none is supplied.
///
/// A user without a current subscription sees a plain Free (or ended) card.
class PlusPaymentSummaryCard extends StatelessWidget {
  const PlusPaymentSummaryCard({
    super.key,
    required this.state,
    required this.store,
  });

  final SubscriptionUiState state;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final status = state.status;
    final isFree = status == SubscriptionStatus.free;
    final billed = status.isCurrentPlus;

    String? dateLabelKey;
    DateTime? dateValue;
    switch (status) {
      case SubscriptionStatus.active:
        dateLabelKey = 'plusDetailRenews';
        dateValue = state.renewsOn;
      case SubscriptionStatus.trial:
        dateLabelKey = 'plusDetailTrialEnds';
        dateValue = state.trialEndsOn;
      case SubscriptionStatus.cancelledActive:
        dateLabelKey = 'plusDetailAccessUntil';
        dateValue = state.expiresOn;
      case SubscriptionStatus.gracePeriod:
        dateLabelKey = 'plusDetailGraceUntil';
        dateValue = state.expiresOn;
      case SubscriptionStatus.expired:
        dateLabelKey = 'plusDetailExpiredOn';
        dateValue = state.expiresOn;
      case SubscriptionStatus.billingIssue:
      case SubscriptionStatus.free:
        break;
    }

    final period = state.period;
    final price = state.billingPeriodPrice;

    // A cancelled plan is still active: say so, then that renewal is off.
    final cancelledActive = status == SubscriptionStatus.cancelledActive;
    final chipStatus = cancelledActive ? SubscriptionStatus.active : status;

    final rows = <Widget>[
      if (billed && period != null)
        PlusDetailRow(
          label: l10n.translate('plusDetailBilling'),
          value: plusPeriodName(l10n, period),
        ),
      if (billed && price != null && period != null)
        PlusDetailRow(
          label: l10n.translate('plusDetailPrice'),
          value: plusPricePerPeriod(l10n, price, period),
        ),
      if (dateLabelKey != null && dateValue != null)
        PlusDetailRow(
          label: l10n.translate(dateLabelKey),
          value: plusFormatDate(context, dateValue),
        ),
      if (billed)
        PlusDetailRow(
          label: l10n.translate('plusDetailStore'),
          value: plusStoreName(l10n, store),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isFree
                      ? Icons.workspace_premium_outlined
                      : Icons.workspace_premium_rounded,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFree
                          ? l10n.translate('freePlan')
                          : l10n.translate('plusBrandName'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    if (isFree) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.translate('plusFreeHeroBody'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          PlusStatusChip(
                            label: plusStatusLabel(l10n, chipStatus),
                            tone: cancelledActive
                                ? PlusTone.positive
                                : plusStatusTone(status),
                            icon: plusStatusIcon(chipStatus),
                          ),
                          if (cancelledActive)
                            PlusStatusChip(
                              label: plusStatusLabel(
                                l10n,
                                SubscriptionStatus.cancelledActive,
                              ),
                              tone: PlusTone.neutral,
                              icon: Icons.autorenew_rounded,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.18)),
            const SizedBox(height: 4),
            ...rows,
          ],
        ],
      ),
    );
  }
}

/// A large tappable card for one action: icon, title, a line of explanation and
/// a direction-aware chevron. [prominent] fills it with the brand colour, for
/// the one action a screen most wants taken.
class PlusActionCard extends StatelessWidget {
  const PlusActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.prominent = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final foreground = prominent ? colors.onPrimary : colors.onSurface;
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    return Semantics(
      button: true,
      child: Material(
        color: prominent ? colors.primary : colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
          side: prominent
              ? BorderSide.none
              : BorderSide(color: colors.outline.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: prominent
                        ? colors.onPrimary.withValues(alpha: 0.18)
                        : colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: prominent ? colors.onPrimary : colors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: foreground.withValues(
                              alpha: prominent ? 0.9 : 0.7,
                            ),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isRtl
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_right_rounded,
                  color: foreground.withValues(alpha: prominent ? 0.9 : 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One task on a management screen: a small label ("Add"), a card that says
/// what it does in a line, and the button that does it. The first task of a
/// screen is [primary]; the rest are quieter.
class PlusTaskCard extends StatelessWidget {
  const PlusTaskCard({
    super.key,
    required this.label,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlusSectionLabel(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(_kCardRadius),
            border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: colors.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.7),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (primary)
                PlusPrimaryButton(label: buttonLabel, onPressed: onPressed)
              else
                PlusSecondaryButton(label: buttonLabel, onPressed: onPressed),
            ],
          ),
        ),
      ],
    );
  }
}

/// A large provider visual with its name, for the top of a screen that is about
/// one provider (Add payment method). It is deliberately a picture of who the
/// user is about to deal with, not a card form.
class PlusProviderHero extends StatelessWidget {
  const PlusProviderHero({super.key, required this.store});

  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        PlusProviderMark(store: store, size: 88),
        const SizedBox(height: 16),
        Text(
          plusProviderTitle(l10n, store),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// The calm notice for a payment problem. Shown only while the state needs
/// payment attention, and never says the subscription ended.
class PlusPaymentIssueNotice extends StatelessWidget {
  const PlusPaymentIssueNotice({
    super.key,
    required this.state,
    required this.store,
  });

  final SubscriptionUiState state;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PlusNoticeCard(
      icon: Icons.info_outline_rounded,
      tone: PlusTone.attention,
      title: l10n.translate('plusIssueTitle'),
      body: plusPaymentIssueBody(context, l10n, state, store),
    );
  }
}

/// The final step of a payment flow: the short hand-off explanation shown just
/// before the user goes to the store. It is never the whole flow; the dedicated
/// screen the user came from is.
///
/// FUTURE SEAM: when an official, verified destination for a payment-method
/// task exists, [plusManagementUri] returns it and the sheet offers "Continue
/// to <store>". When Google Play Billing is integrated, Google's own purchase
/// sheet shows the user's eligible saved payment methods and lets them pick or
/// add one; Broker Wallet never lists them. Until then the sheet gives the
/// exact steps and a plain Done, and never claims anything was opened.
Future<void> showPlusHandoff(
  BuildContext context, {
  required SubscriptionUiState state,
  required PlusStore store,
  required PlusManageAction action,
}) {
  return PlusManageSheet.show(
    context,
    store: store,
    action: action,
    managementUri: state.managementUri,
  );
}

/// A line of text with a leading icon, for the short "what to know" lines on
/// the Add payment method screen. Wraps for long Arabic and large text.
class PlusIconLine extends StatelessWidget {
  const PlusIconLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
