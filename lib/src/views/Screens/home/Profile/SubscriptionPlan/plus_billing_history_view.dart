import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Billing history & receipts.
///
/// Every Broker Wallet Plus charge is made by the App Store or Google Play, so
/// the purchase history and the receipts belong to the user's store account.
/// Broker Wallet keeps no transactions of its own and has no purchase-history
/// source yet, so this screen lists nothing and invents nothing: no invoice
/// numbers, amounts, dates or card details. It says so plainly, and shows the
/// exact steps to find the real record in the store.
///
/// When a real provider integration can supply history, it belongs in this
/// screen's body; the screen, its route and its place under Subscription &
/// Billing do not have to change.
class PlusBillingHistoryView extends StatelessWidget {
  const PlusBillingHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final store = vm.effectiveStore;

    final String introKey;
    final List<String> stepKeys;
    switch (store) {
      case PlusStore.googlePlay:
        introKey = 'plusHistoryIntroGoogle';
        stepKeys = const ['plusManageStepAndroid1', 'plusHistoryStepAndroid2'];
      case PlusStore.appStore:
        introKey = 'plusHistoryIntroApple';
        stepKeys = const ['plusManageStepIos1', 'plusHistoryStepIos2'];
      case PlusStore.unknown:
        introKey = 'plusHistoryIntroGeneric';
        stepKeys = const ['plusManageStepGeneric1', 'plusHistoryStepGeneric2'];
    }

    return PlusScreenScaffold(
      title: l10n.translate('plusRowHistory'),
      children: [
        if (vm.entitlement.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        PlusInfoHeader(
          icon: Icons.receipt_long_outlined,
          title: plusManagedByText(l10n, store),
          body: l10n.translate(introKey),
        ),
        const SizedBox(height: 24),
        PlusSectionLabel(l10n.translate('plusHistoryHowTo')),
        PlusCard(
          child: Column(
            children: [
              for (var i = 0; i < stepKeys.length; i++)
                PlusStepRow(
                  number: i + 1,
                  text: l10n.translate(stepKeys[i]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PlusFootnote(
          l10n.translate('plusHistoryNothingListed'),
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 24),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.support_agent_rounded,
              tone: PlusTone.neutral,
              title: l10n.translate('plusHistoryHelp'),
              subtitle: l10n.translate('plusHistoryHelpSubtitle'),
              onTap: () => context.push(PlusRoutes.help),
            ),
          ],
        ),
      ],
    );
  }
}
