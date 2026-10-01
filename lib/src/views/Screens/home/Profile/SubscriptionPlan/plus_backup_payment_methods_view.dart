import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_payment_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Backup payment methods: a Google Play feature, explained.
///
/// Google Play can keep a second payment method on the account and use it if
/// the main one fails, for eligible purchases and subscriptions. This screen
/// says what that is, why it can help prevent a billing interruption, and that
/// whether it is available (and what it covers) is Google Play's decision, not
/// Broker Wallet's. Setting one up happens in Google Play, through the final
/// hand-off step.
///
/// Apple has no equivalent and none is invented: the dashboard never links here
/// on the App Store, and if the route is opened anyway the screen says so and
/// leads back to Payment methods instead of showing Google wording.
class PlusBackupPaymentMethodsView extends StatelessWidget {
  const PlusBackupPaymentMethodsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final title = l10n.translate('plusPayBackupTitle');

    if (store != PlusStore.googlePlay) {
      return PlusScreenScaffold(
        title: title,
        children: [
          PlusNoticeCard(
            icon: Icons.info_outline_rounded,
            title: l10n.translate('plusBackupUnavailableTitle'),
            body: l10n.translate('plusBackupUnavailableBody'),
          ),
          const SizedBox(height: 16),
          PlusPrimaryButton(
            label: l10n.translate('plusBackToPaymentMethods'),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(PlusRoutes.paymentMethods);
              }
            },
          ),
        ],
      );
    }

    return PlusScreenScaffold(
      title: title,
      bottom: PlusBottomBar(
        child: PlusPrimaryButton(
          label: l10n.translate('plusBackupManage'),
          onPressed: () => showPlusHandoff(
            context,
            state: state,
            store: store,
            action: PlusManageAction.backupPaymentMethods,
          ),
        ),
      ),
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        PlusProviderCard(
          store: store,
          caption: l10n.translate('plusBackupIntro'),
          detail: plusManagedSecurelyText(l10n, store),
        ),
        const SizedBox(height: 16),
        PlusCheckRow(l10n.translate('plusBackupPointWhat')),
        PlusCheckRow(l10n.translate('plusBackupPointWhy')),
        PlusCheckRow(l10n.translate('plusBackupPointEligibility')),
        const SizedBox(height: 16),
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
