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

/// Manage subscription: the details of the current plan and the few things
/// that can be done about it.
///
/// Separate from Payment methods on purpose. This screen is about the
/// subscription (its period, renewal, dates and charge) and shows only the
/// values the billing source supplied. Every action here is a hand-off: the
/// store changes, cancels or renews a subscription, never Broker Wallet, so
/// each action opens a short explanation and, where a safe link exists, a way
/// to continue in the store. Nothing on this screen claims a change happened.
class PlusManageSubscriptionView extends StatelessWidget {
  const PlusManageSubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final status = state.status;
    final title = l10n.translate('plusManageSubscription');

    if (!status.isCurrentPlus) {
      return PlusScreenScaffold(
        title: title,
        children: [
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
      );
    }

    final storeName = plusStoreName(l10n, store);
    final canChangePeriod = status == SubscriptionStatus.active ||
        status == SubscriptionStatus.trial;

    return PlusScreenScaffold(
      title: title,
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        _StatusNotice(state: state, store: store),
        _PrimaryAction(state: state, store: store),
        PlusSectionLabel(l10n.translate('plusManageDetailsLabel')),
        PlusSubscriptionDetails(state: state, store: store),
        const SizedBox(height: 24),
        SettingsSectionCard(
          children: [
            if (canChangePeriod)
              PlusActionRow(
                icon: Icons.swap_horiz_rounded,
                title: l10n.translate('plusChangePeriodRow'),
                subtitle: l10n.translate('plusChangePeriodRowSubtitle'),
                onTap: () => context.push(PlusRoutes.changePeriod),
              ),
            PlusActionRow(
              icon: Icons.storefront_outlined,
              title: l10n.plusText('plusManageInStore', {'store': storeName}),
              subtitle: l10n.plusText('plusManageInStoreSubtitle', {
                'store': storeName,
              }),
              onTap: () => PlusManageSheet.show(
                context,
                store: store,
                action: PlusManageAction.manage,
                managementUri: state.managementUri,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Cancelling is a store action; deleting the account is not one.
        PlusFootnote(
          l10n.plusText('plusDeleteAccountNote', {'store': storeName}),
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}

/// The calm explanation that goes with each non-trivial status. A payment
/// problem or a cancelled renewal is explained, never presented as Plus
/// already being gone.
class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.state, required this.store});

  final SubscriptionUiState state;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, store);
    final date = state.expiresOn;
    final dateText = date != null ? plusFormatDate(context, date) : null;

    final PlusNoticeCard? notice;
    switch (state.status) {
      case SubscriptionStatus.free:
      case SubscriptionStatus.active:
      case SubscriptionStatus.expired:
        notice = null;
      case SubscriptionStatus.trial:
        notice = PlusNoticeCard(
          icon: Icons.timelapse_rounded,
          tone: PlusTone.positive,
          title: l10n.translate('plusTrialNoticeTitle'),
          body: l10n.plusText('plusTrialNoticeBody', {'store': storeName}),
        );
      case SubscriptionStatus.cancelledActive:
        notice = PlusNoticeCard(
          icon: Icons.event_available_rounded,
          title: l10n.translate('plusCancelledActiveTitle'),
          body: dateText != null
              ? l10n.plusText('plusCancelledActiveBody', {'date': dateText})
              : l10n.translate('plusCancelledActiveBodyNoDate'),
        );
      case SubscriptionStatus.gracePeriod:
      case SubscriptionStatus.billingIssue:
        notice = PlusNoticeCard(
          icon: Icons.info_outline_rounded,
          tone: PlusTone.attention,
          title: l10n.translate('plusIssueTitle'),
          body: plusPaymentIssueBody(context, l10n, state, store),
        );
    }

    if (notice == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: notice);
  }
}

/// The one thing worth doing first, when the state has one: turn renewal back
/// on, or fix the payment method.
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
      case SubscriptionStatus.cancelledActive:
        label = l10n.translate('plusResubscribe');
        onPressed = () => PlusManageSheet.show(
              context,
              store: store,
              action: PlusManageAction.resubscribe,
              managementUri: state.managementUri,
            );
      case SubscriptionStatus.gracePeriod:
      case SubscriptionStatus.billingIssue:
        label = l10n.translate('plusFixPayment');
        onPressed = () => context.push(PlusRoutes.paymentDetails);
      case SubscriptionStatus.free:
      case SubscriptionStatus.active:
      case SubscriptionStatus.trial:
      case SubscriptionStatus.expired:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: PlusPrimaryButton(label: label, onPressed: onPressed),
    );
  }
}
