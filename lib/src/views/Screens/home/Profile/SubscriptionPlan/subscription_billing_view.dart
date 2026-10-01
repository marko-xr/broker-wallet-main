import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_manage_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Subscription & Billing: the hub Profile sends everyone to.
///
/// It answers one question first — what plan do I have, and is it in good
/// standing? — in a short summary, then gives each task its own row that opens
/// a screen of its own: Manage subscription, Payment methods, Billing history
/// & receipts, Restore purchases, Plan usage, Subscription help and Legal. It
/// deliberately carries no details, no instructions and no legal text itself,
/// so it stays readable at a glance whatever the plan state.
///
/// What each state shows:
///  * Free: the Free plan, one way to upgrade, and Restore. No billing rows,
///    because there is nothing to bill or manage.
///  * Active / trial: the summary and every management row.
///  * Cancelled (still active): the summary, Resubscribe, and the rows that
///    still apply. Renewal is off, so there is no payment method to fix.
///  * Grace / billing issue: a calm warning with "Update payment method" as the
///    one obvious next step, above the usual rows.
///  * Expired: when it ended, a way to view plans, receipts and Restore.
///
/// Broker Wallet sells digital access through the App Store and Google Play, so
/// payment methods, receipts and cancellation belong to the store. Nothing here
/// changes a subscription, and nothing here shows, collects or stores a card.
class SubscriptionBillingView extends StatelessWidget {
  const SubscriptionBillingView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final status = state.status;

    final showManage = status.isCurrentPlus;
    final showPayment = status.autoRenews;
    final showHistory =
        status.isCurrentPlus || status == SubscriptionStatus.expired;

    return PlusScreenScaffold(
      title: l10n.translate('plusBillingTitle'),
      children: [
        if (state.isPreview || vm.offering.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        PlusPlanSummaryCard(state: state, store: store),
        const SizedBox(height: 16),
        if (vm.hasPendingPurchase) ...[
          PlusNoticeCard(
            icon: Icons.schedule_rounded,
            title: l10n.translate('plusPendingBannerTitle'),
            body: l10n.translate('plusPendingBannerBody'),
          ),
          const SizedBox(height: 16),
        ],
        if (status.needsPaymentAttention) ...[
          _PaymentIssueCallout(state: state, store: store),
          const SizedBox(height: 16),
        ],
        _PrimaryAction(state: state, store: store),
        SettingsSectionCard(
          children: [
            if (showManage)
              PlusActionRow(
                icon: Icons.tune_rounded,
                title: l10n.translate('plusManageSubscription'),
                subtitle: l10n.translate('plusHubManageSubtitle'),
                onTap: () => context.push(PlusRoutes.manage),
              ),
            if (showPayment)
              PlusActionRow(
                icon: Icons.account_balance_wallet_outlined,
                title: l10n.translate('plusPaymentMethodsTitle'),
                subtitle: plusManagedByText(l10n, store),
                onTap: () => context.push(PlusRoutes.paymentMethods),
              ),
            if (showHistory)
              PlusActionRow(
                icon: Icons.receipt_long_outlined,
                title: l10n.translate('plusRowHistory'),
                subtitle: l10n.plusText(
                  'plusRowHistorySubtitle',
                  {'store': plusStoreName(l10n, store)},
                ),
                onTap: () => context.push(PlusRoutes.history),
              ),
            PlusActionRow(
              icon: Icons.restore_rounded,
              title: l10n.translate('plusRestorePurchases'),
              subtitle: l10n.translate('plusRowRestoreSubtitle'),
              onTap: () => context.push(PlusRoutes.restore),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.data_usage_rounded,
              tone: PlusTone.neutral,
              title: l10n.translate('plusUsageTitle'),
              subtitle: l10n.translate('plusUsageSubtitle'),
              onTap: () => context.push(PlusRoutes.usage),
            ),
            PlusActionRow(
              icon: Icons.support_agent_rounded,
              tone: PlusTone.neutral,
              title: l10n.translate('plusRowHelpTitle'),
              subtitle: l10n.translate('plusRowHelpSubtitle'),
              onTap: () => context.push(PlusRoutes.help),
            ),
            PlusActionRow(
              icon: Icons.gavel_rounded,
              tone: PlusTone.neutral,
              title: l10n.translate('plusLegalTitle'),
              subtitle: l10n.translate('plusLegalSubtitle'),
              onTap: () => context.push(PlusRoutes.legal),
            ),
          ],
        ),
      ],
    );
  }
}

/// The calm warning for a payment problem, with the one thing to do about it.
/// It never says the subscription ended: Plus access keeps following the
/// store's own subscription status.
class _PaymentIssueCallout extends StatelessWidget {
  const _PaymentIssueCallout({required this.state, required this.store});

  final SubscriptionUiState state;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlusNoticeCard(
          icon: Icons.info_outline_rounded,
          tone: PlusTone.attention,
          title: l10n.translate('plusIssueTitle'),
          body: plusPaymentIssueBody(context, l10n, state, store),
        ),
        const SizedBox(height: 12),
        PlusPrimaryButton(
          label: l10n.translate('plusFixPayment'),
          onPressed: () => context.push(PlusRoutes.paymentMethods),
        ),
      ],
    );
  }
}

/// The single most useful next step for the current state, if there is one.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.state, required this.store});

  final SubscriptionUiState state;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final String label;
    final VoidCallback onPressed;
    switch (state.status) {
      case SubscriptionStatus.free:
        label = l10n.translate('plusUpgradeToPlus');
        onPressed = () => context.push(PlusRoutes.paywall);
      case SubscriptionStatus.expired:
        label = l10n.translate('plusViewPlans');
        onPressed = () => context.push(PlusRoutes.paywall);
      case SubscriptionStatus.cancelledActive:
        label = l10n.translate('plusResubscribe');
        onPressed = () => PlusManageSheet.show(
              context,
              store: store,
              action: PlusManageAction.resubscribe,
              managementUri: state.managementUri,
            );
      case SubscriptionStatus.active:
      case SubscriptionStatus.trial:
      case SubscriptionStatus.gracePeriod:
      case SubscriptionStatus.billingIssue:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PlusPrimaryButton(label: label, onPressed: onPressed),
    );
  }
}
