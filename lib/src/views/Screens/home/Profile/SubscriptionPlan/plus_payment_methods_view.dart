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

/// Payment methods: where the payment method behind Broker Wallet Plus is
/// added, changed and managed — which is always in the store, never here.
///
/// Broker Wallet sells digital access through the App Store and Google Play, so
/// the payment credentials belong to the user's Apple Account or Google Play
/// account. This screen is the Broker Wallet-owned front door to that: it says
/// whose payment methods these are, lists what can be done about them in that
/// store, and each row opens a short hand-off ([PlusManageSheet]) with the
/// exact steps. It is deliberately platform-aware, because Apple and Google
/// organise this differently.
///
/// What it never does: collect a card number, expiry or CVV, show a saved or
/// default card, or imitate the store's payment form. There is no payment
/// field on this screen, and no masked card is shown unless a real provider API
/// supplies one and the owner approves displaying it.
///
/// With a payment issue the screen opens on the fix: a calm notice and "Update
/// payment method", above the same list.
class PlusPaymentMethodsView extends StatelessWidget {
  const PlusPaymentMethodsView({super.key});

  void _open(
    BuildContext context,
    SubscriptionUiState state,
    PlusStore store,
    PlusManageAction action,
  ) {
    PlusManageSheet.show(
      context,
      store: store,
      action: action,
      managementUri: state.managementUri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final status = state.status;
    final storeName = plusStoreName(l10n, store);

    final String providerKey;
    final String introKey;
    switch (store) {
      case PlusStore.googlePlay:
        providerKey = 'plusStoreGooglePlay';
        introKey = 'plusPmIntroGoogle';
      case PlusStore.appStore:
        providerKey = 'plusPmProviderApple';
        introKey = 'plusPmIntroApple';
      case PlusStore.unknown:
        providerKey = 'plusPmProviderGeneric';
        introKey = 'plusPmIntroGeneric';
    }

    return PlusScreenScaffold(
      title: l10n.translate('plusPaymentMethodsTitle'),
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        if (status.needsPaymentAttention) ...[
          PlusNoticeCard(
            icon: Icons.info_outline_rounded,
            tone: PlusTone.attention,
            title: l10n.translate('plusIssueTitle'),
            body: plusPaymentIssueBody(context, l10n, state, store),
          ),
          const SizedBox(height: 12),
          PlusPrimaryButton(
            label: l10n.translate('plusFixPayment'),
            onPressed: () => _open(
              context,
              state,
              store,
              PlusManageAction.updatePaymentMethod,
            ),
          ),
          const SizedBox(height: 24),
        ],
        PlusInfoHeader(
          icon: Icons.account_balance_wallet_outlined,
          title: l10n.translate(providerKey),
          body: l10n.translate(introKey),
        ),
        const SizedBox(height: 24),
        ..._paymentMethodGroup(context, l10n, state, store),
        if (status.isCurrentPlus) ...[
          const SizedBox(height: 24),
          PlusSectionLabel(l10n.translate('plusPmSectionSubscription')),
          SettingsSectionCard(
            children: [
              PlusActionRow(
                icon: Icons.storefront_outlined,
                title: l10n.plusText('plusPmManageSubscription', {
                  'store': storeName,
                }),
                subtitle: l10n.plusText('plusPmSubscriptionSubtitle', {
                  'store': storeName,
                }),
                onTap: () =>
                    _open(context, state, store, PlusManageAction.manage),
              ),
            ],
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
              onTap: () => context.push(PlusRoutes.help),
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

  /// The platform-specific rows. Google Play keeps payment methods, adding and
  /// backup methods as separate things; the App Store keeps all of them in the
  /// Apple Account's Payment & Shipping settings.
  List<Widget> _paymentMethodGroup(
    BuildContext context,
    AppLocalizations l10n,
    SubscriptionUiState state,
    PlusStore store,
  ) {
    switch (store) {
      case PlusStore.googlePlay:
        return [
          PlusSectionLabel(l10n.translate('plusPmSectionPaymentMethods')),
          SettingsSectionCard(
            children: [
              PlusActionRow(
                icon: Icons.account_balance_wallet_outlined,
                title: l10n.translate('plusPayManageTitle'),
                subtitle: plusManagedByText(l10n, store),
                onTap: () => _open(
                  context,
                  state,
                  store,
                  PlusManageAction.managePaymentMethods,
                ),
              ),
              PlusActionRow(
                icon: Icons.add_circle_outline_rounded,
                title: l10n.translate('plusPayAddTitle'),
                subtitle: l10n.translate('plusPmAddSubtitleGoogle'),
                onTap: () => _open(
                  context,
                  state,
                  store,
                  PlusManageAction.addPaymentMethod,
                ),
              ),
              PlusActionRow(
                icon: Icons.shield_outlined,
                title: l10n.translate('plusPayBackupTitle'),
                subtitle: l10n.translate('plusPmBackupSubtitleGoogle'),
                onTap: () => _open(
                  context,
                  state,
                  store,
                  PlusManageAction.backupPaymentMethods,
                ),
              ),
            ],
          ),
        ];
      case PlusStore.appStore:
        return [
          PlusSectionLabel(l10n.translate('plusPmSectionPaymentShipping')),
          SettingsSectionCard(
            children: [
              PlusActionRow(
                icon: Icons.account_balance_wallet_outlined,
                title: l10n.translate('plusPayChangeTitle'),
                subtitle: plusManagedByText(l10n, store),
                onTap: () => _open(
                  context,
                  state,
                  store,
                  PlusManageAction.addPaymentMethod,
                ),
              ),
            ],
          ),
        ];
      case PlusStore.unknown:
        return [
          PlusSectionLabel(l10n.translate('plusPmSectionPaymentMethods')),
          SettingsSectionCard(
            children: [
              PlusActionRow(
                icon: Icons.account_balance_wallet_outlined,
                title: l10n.translate('plusPayChangeTitle'),
                subtitle: plusManagedByText(l10n, store),
                onTap: () => _open(
                  context,
                  state,
                  store,
                  PlusManageAction.addPaymentMethod,
                ),
              ),
            ],
          ),
        ];
    }
  }
}
