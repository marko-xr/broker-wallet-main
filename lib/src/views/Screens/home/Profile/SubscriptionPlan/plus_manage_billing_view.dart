import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_payment_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Manage billing: a billing dashboard for Broker Wallet Plus.
///
/// One summary card says what is billed and how — Broker Wallet Plus, its
/// status, the billing period and price, the next renewal or access-until date,
/// and the provider that bills it — using only the values the billing source
/// supplied. Under it, only the actions that matter: Manage subscription,
/// Payment method, Billing history & receipts and Restore purchases. The one
/// store action, "Manage in Google Play", is pinned at the bottom.
///
/// A user without a current subscription sees no renewal or charge information
/// at all, because there is none to show.
class PlusManageBillingView extends StatelessWidget {
  const PlusManageBillingView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final status = state.status;
    final storeName = plusStoreName(l10n, store);

    final hasSubscription = status.isCurrentPlus;
    final showHistory = hasSubscription || status == SubscriptionStatus.expired;

    return PlusScreenScaffold(
      title: l10n.translate('plusPmManageBilling'),
      bottom: hasSubscription
          ? PlusBottomBar(
              child: PlusPrimaryButton(
                label: l10n.plusText('plusPmOpenInStore', {'store': storeName}),
                onPressed: () => showPlusHandoff(
                  context,
                  state: state,
                  store: store,
                  action: PlusManageAction.manage,
                ),
              ),
            )
          : null,
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        if (hasSubscription) ...[
          if (status.needsPaymentAttention) ...[
            PlusPaymentIssueNotice(state: state, store: store),
            const SizedBox(height: 16),
          ],
          PlusPlanSummaryCard(state: state, store: store),
        ] else ...[
          PlusNoticeCard(
            icon: Icons.info_outline_rounded,
            title: l10n.translate('plusManageNoneTitle'),
            body: l10n.translate('plusManageNoneBody'),
          ),
          const SizedBox(height: 16),
          PlusPrimaryButton(
            label: l10n.translate('plusViewPlans'),
            onPressed: () => context.push(PlusRoutes.paywall),
          ),
        ],
        const SizedBox(height: 24),
        SettingsSectionCard(
          children: [
            if (hasSubscription)
              PlusActionRow(
                icon: Icons.tune_rounded,
                title: l10n.translate('plusManageSubscription'),
                subtitle: l10n.translate('plusHubManageSubtitle'),
                onTap: () => context.push(PlusRoutes.manage),
              ),
            PlusActionRow(
              icon: Icons.account_balance_wallet_outlined,
              title: l10n.translate('plusPmTitle'),
              subtitle: plusManagedByText(l10n, store),
              onTap: () => context.push(PlusRoutes.paymentMethods),
            ),
            if (showHistory)
              PlusActionRow(
                icon: Icons.receipt_long_outlined,
                title: l10n.translate('plusRowHistory'),
                subtitle: l10n.plusText('plusRowHistorySubtitle', {
                  'store': storeName,
                }),
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
      ],
    );
  }
}
