import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Legal: the subscription disclosure and the existing Terms and Privacy
/// screens.
///
/// The disclosure is the same sentence the paywall and the purchase review
/// already carry (how the store charges, renews and cancels). There is no
/// separate subscription-terms document in Broker Wallet yet, and this screen
/// does not write one: it links the legal screens that exist.
class PlusLegalView extends StatelessWidget {
  const PlusLegalView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, vm.effectiveStore);

    return PlusScreenScaffold(
      title: l10n.translate('plusLegalTitle'),
      children: [
        PlusSectionLabel(l10n.translate('plusSubscriptionInfoTitle')),
        PlusCard(
          child: Text(
            l10n.plusText('plusSubscriptionInfoBody', {'store': storeName}),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),
        PlusSectionLabel(l10n.translate('plusLegalDocuments')),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.description_outlined,
              tone: PlusTone.neutral,
              title: l10n.translate('termsConditions'),
              onTap: () => context.push(PlusRoutes.terms),
            ),
            PlusActionRow(
              icon: Icons.privacy_tip_outlined,
              tone: PlusTone.neutral,
              title: l10n.translate('privacyPolicy'),
              onTap: () => context.push(PlusRoutes.privacy),
            ),
          ],
        ),
      ],
    );
  }
}
