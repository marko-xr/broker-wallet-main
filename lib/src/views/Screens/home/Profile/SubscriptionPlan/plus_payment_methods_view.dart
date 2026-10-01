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

/// Payment method: the provider that pays for Broker Wallet Plus, shown as the
/// one selected payment method, and the few things to do about it.
///
/// Broker Wallet sells digital access through Google Play (and, on iOS, the App
/// Store), so the payment method is the provider's: the user's Google Play
/// account holds their cards. The screen therefore shows ONE selected card — the
/// provider — instead of a list of cards, and never offers a choice between
/// Google Play, Apple, cards or PayPal. Below it, the most important action
/// stands out (Manage payment methods), then Add payment method and, for a
/// subscriber, Manage subscription billing, with help as a quiet link.
///
/// What it never does: show a card number, expiry, brand, bank account or
/// "default" marker, collect any credential, or imitate the store's form.
///
/// With a payment issue a calm notice leads the screen and the prominent action
/// is the way to fix it: Payment details → Payment method → Manage / Add →
/// store hand-off.
class PlusPaymentMethodsView extends StatelessWidget {
  const PlusPaymentMethodsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final status = state.status;
    final isApple = store == PlusStore.appStore;
    final storeName = plusStoreName(l10n, store);

    final String addSubtitleKey;
    final String manageSubtitleKey;
    switch (store) {
      case PlusStore.googlePlay:
        addSubtitleKey = 'plusPmAddSubtitleGoogle';
        manageSubtitleKey = 'plusPmManageSubtitleGoogle';
      case PlusStore.appStore:
        addSubtitleKey = 'plusPmAddSubtitleApple';
        manageSubtitleKey = 'plusPmManageSubtitleApple';
      case PlusStore.unknown:
        addSubtitleKey = 'plusPmAddSubtitleGeneric';
        manageSubtitleKey = 'plusPmManageSubtitleGeneric';
    }

    return PlusScreenScaffold(
      title: l10n.translate('plusPmTitle'),
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        if (status.needsPaymentAttention) ...[
          PlusPaymentIssueNotice(state: state, store: store),
          const SizedBox(height: 16),
        ],
        PlusProviderCard(
          store: store,
          caption: l10n.translate('plusPmSelectedCaption'),
          detail: plusManagedSecurelyText(l10n, store),
          selected: true,
        ),
        const SizedBox(height: 24),
        PlusActionCard(
          prominent: true,
          icon: Icons.account_balance_wallet_outlined,
          title: l10n.translate('plusPayManageTitle'),
          subtitle: l10n.translate(manageSubtitleKey),
          onTap: () => context.push(PlusRoutes.paymentMethodsManage),
        ),
        const SizedBox(height: 12),
        PlusActionCard(
          icon: Icons.add_circle_outline_rounded,
          title: l10n.translate('plusPayAddTitle'),
          subtitle: l10n.translate(addSubtitleKey),
          onTap: () => context.push(PlusRoutes.paymentMethodsAdd),
        ),
        if (status.isCurrentPlus) ...[
          const SizedBox(height: 12),
          PlusActionCard(
            icon: Icons.receipt_long_outlined,
            title: isApple
                ? l10n.plusText('plusPmManageSubscription', {
                    'store': storeName,
                  })
                : l10n.translate('plusPmManageBillingFull'),
            subtitle: l10n.plusText('plusPmSubscriptionSubtitle', {
              'store': storeName,
            }),
            onTap: () => context.push(PlusRoutes.paymentMethodsBilling),
          ),
        ],
        const SizedBox(height: 24),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.support_agent_rounded,
              tone: PlusTone.neutral,
              title: l10n.translate('plusPmHelp'),
              subtitle: l10n.translate('plusPmHelpSubtitle'),
              onTap: () => context.push(PlusRoutes.paymentMethodsHelp),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PlusFootnote(
          l10n.translate('plusPaySafetyNote'),
          icon: Icons.lock_outline_rounded,
        ),
      ],
    );
  }
}
