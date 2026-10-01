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

/// Manage payment methods: add, update, remove or review the methods behind
/// Broker Wallet Plus — in the store, which is the only place they exist.
///
/// The screen opens on the provider, with one sentence about it, and then shows
/// its tasks as clear cards, each with the button that does it: change or
/// manage (hand-off to the store), add (the Add payment method screen) and, on
/// Google Play only, backup payment methods. The user sees the actions first,
/// not paragraphs.
///
/// Broker Wallet holds no payment-method data, so it lists none: no card, no
/// masked number, no "default" marker, nothing built from invented data.
///
/// With a payment issue the screen also leads with a calm notice and one large
/// "Update payment method", the final hand-off step for fixing the method
/// behind the subscription.
class PlusManagePaymentMethodsView extends StatelessWidget {
  const PlusManagePaymentMethodsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final isApple = store == PlusStore.appStore;
    final isGoogle = store == PlusStore.googlePlay;
    final storeName = plusStoreName(l10n, store);

    final String introKey;
    final String addSubtitleKey;
    final String manageSubtitleKey;
    switch (store) {
      case PlusStore.googlePlay:
        introKey = 'plusManageMethodsIntroGoogle';
        addSubtitleKey = 'plusPmAddSubtitleGoogle';
        manageSubtitleKey = 'plusPmManageSubtitleGoogle';
      case PlusStore.appStore:
        introKey = 'plusManageMethodsIntroApple';
        addSubtitleKey = 'plusPmAddSubtitleApple';
        manageSubtitleKey = 'plusPmManageSubtitleApple';
      case PlusStore.unknown:
        introKey = 'plusManageMethodsIntroGeneric';
        addSubtitleKey = 'plusPmAddSubtitleGeneric';
        manageSubtitleKey = 'plusPmManageSubtitleGeneric';
    }

    return PlusScreenScaffold(
      title: l10n.translate('plusPayManageTitle'),
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        if (state.status.needsPaymentAttention) ...[
          PlusPaymentIssueNotice(state: state, store: store),
          const SizedBox(height: 12),
          PlusPrimaryButton(
            label: l10n.translate('plusFixPayment'),
            onPressed: () => showPlusHandoff(
              context,
              state: state,
              store: store,
              action: PlusManageAction.updatePaymentMethod,
            ),
          ),
          const SizedBox(height: 24),
        ],
        PlusProviderCard(
          store: store,
          caption: l10n.translate(introKey),
          detail: plusManagedSecurelyText(l10n, store),
        ),
        const SizedBox(height: 24),
        PlusTaskCard(
          primary: true,
          label: l10n.translate('plusMmLabelManage'),
          icon: isApple
              ? Icons.local_shipping_outlined
              : Icons.account_balance_wallet_outlined,
          title: isApple
              ? l10n.translate('plusPmSectionPaymentShipping')
              : l10n.translate('plusPayManageTitle'),
          subtitle: l10n.translate(manageSubtitleKey),
          // Apple keeps payment methods in Settings, not in the App Store, so
          // its button says what it shows: the steps.
          buttonLabel: isApple
              ? l10n.translate('plusMmShippingButton')
              : l10n.plusText('plusPmOpenInStore', {'store': storeName}),
          onPressed: () => showPlusHandoff(
            context,
            state: state,
            store: store,
            action: PlusManageAction.managePaymentMethods,
          ),
        ),
        const SizedBox(height: 20),
        PlusTaskCard(
          label: l10n.translate('plusMmLabelAdd'),
          icon: Icons.add_circle_outline_rounded,
          title: l10n.translate('plusPayAddTitle'),
          subtitle: l10n.translate(addSubtitleKey),
          buttonLabel: l10n.translate('plusPayAddTitle'),
          onPressed: () => context.push(PlusRoutes.paymentMethodsAdd),
        ),
        // Google Play only. Apple has no backup payment method, so none is
        // shown or invented.
        if (isGoogle) ...[
          const SizedBox(height: 20),
          PlusTaskCard(
            label: l10n.translate('plusMmLabelBackup'),
            icon: Icons.shield_outlined,
            title: l10n.translate('plusPayBackupTitle'),
            subtitle: l10n.translate('plusPmBackupSubtitleGoogle'),
            buttonLabel: l10n.translate('plusMmBackupButton'),
            onPressed: () => context.push(PlusRoutes.paymentMethodsBackup),
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
