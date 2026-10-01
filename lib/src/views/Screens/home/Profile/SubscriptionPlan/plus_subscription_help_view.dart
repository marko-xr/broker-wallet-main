import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Subscription help: the usual problems, each a row that goes straight to the
/// screen that deals with it, and the way to reach Broker Wallet support.
///
/// It is a signpost, not a help system. Every topic opens a screen that already
/// exists (receipts, payment methods, restore, manage subscription), and
/// "Contact support" opens the existing Help & Support. It invents no phone
/// number, email address, ticket or chat.
class PlusSubscriptionHelpView extends StatelessWidget {
  const PlusSubscriptionHelpView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return PlusScreenScaffold(
      title: l10n.translate('plusRowHelpTitle'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            l10n.translate('plusHelpIntro'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
        ),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.receipt_long_outlined,
              title: l10n.translate('plusHelpBilling'),
              subtitle: l10n.translate('plusHelpBillingSubtitle'),
              onTap: () => context.push(PlusRoutes.history),
            ),
            PlusActionRow(
              icon: Icons.account_balance_wallet_outlined,
              title: l10n.translate('plusHelpPayment'),
              subtitle: l10n.translate('plusHelpPaymentSubtitle'),
              onTap: () => context.push(PlusRoutes.paymentMethods),
            ),
            PlusActionRow(
              icon: Icons.restore_rounded,
              title: l10n.translate('plusHelpRestore'),
              subtitle: l10n.translate('plusHelpRestoreSubtitle'),
              onTap: () => context.push(PlusRoutes.restore),
            ),
            PlusActionRow(
              icon: Icons.tune_rounded,
              title: l10n.translate('plusManageSubscription'),
              subtitle: l10n.translate('plusHelpManageSubtitle'),
              onTap: () => context.push(PlusRoutes.manage),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.support_agent_rounded,
              title: l10n.translate('plusContactSupport'),
              subtitle: l10n.translate('plusHelpSupportSubtitle'),
              onTap: () => context.push(PlusRoutes.support),
            ),
          ],
        ),
      ],
    );
  }
}
