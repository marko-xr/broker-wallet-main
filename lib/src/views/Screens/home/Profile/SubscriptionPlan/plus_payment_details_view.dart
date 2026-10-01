import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_payment_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';

/// Payment details: what is being paid for, how it is billed, and who looks
/// after the payment — on one screen that reads like a payment screen.
///
/// Three parts, top to bottom:
///  * the payment summary: Broker Wallet Plus, its billing status, period,
///    price, renewal or access-until date and the provider that bills it. Only
///    values the billing source supplied appear; there is no invented subtotal,
///    tax, discount or total.
///  * the payment method: the provider's card ("Google Play — managed securely
///    by Google Play") with a clear Change action. It is a provider card, not a
///    saved card: Google Play and the Apple Account do not give Broker Wallet a
///    list of the user's cards, so no card, digits, expiry or brand is shown.
///  * one obvious action pinned at the bottom.
///
/// With a payment issue the payment-method card is the highlighted part: a calm
/// message and "Update payment method", which goes to Payment method. The
/// pinned action then becomes "Manage billing".
class PlusPaymentDetailsView extends StatelessWidget {
  const PlusPaymentDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final attention = state.status.needsPaymentAttention;

    return PlusScreenScaffold(
      title: l10n.translate('plusPaymentDetailsTitle'),
      bottom: PlusBottomBar(
        child: PlusPrimaryButton(
          label: l10n.translate(
            attention ? 'plusPmManageBilling' : 'plusPdManageMethod',
          ),
          onPressed: () => context.push(
            attention
                ? PlusRoutes.paymentMethodsBilling
                : PlusRoutes.paymentMethods,
          ),
        ),
      ),
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        PlusSectionLabel(l10n.translate('plusPdSectionSummary')),
        PlusPaymentSummaryCard(state: state, store: store),
        const SizedBox(height: 24),
        PlusSectionLabel(l10n.translate('plusPmTitle')),
        PlusProviderCard(
          store: store,
          caption: l10n.translate('plusPdMethodCaption'),
          detail: plusManagedSecurelyText(l10n, store),
          attention: attention,
          // The healthy card carries the Change action; the card with a
          // problem carries the fix instead, so there is one action, not two.
          trailing: attention
              ? null
              : PlusCardButton(
                  label: l10n.translate('plusPdChange'),
                  onPressed: () => context.push(PlusRoutes.paymentMethods),
                ),
          child: attention
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.translate('plusPdIssueTitle'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plusPaymentIssueBody(context, l10n, state, store),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    PlusPrimaryButton(
                      label: l10n.translate('plusFixPayment'),
                      onPressed: () => context.push(PlusRoutes.paymentMethods),
                    ),
                  ],
                )
              : null,
        ),
      ],
    );
  }
}
