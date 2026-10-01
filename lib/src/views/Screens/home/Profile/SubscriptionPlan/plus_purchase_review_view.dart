import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/plus_benefit_catalog.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_legal_footer.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_secure_checkout_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Purchase review: what the user is about to agree to, and nothing else.
///
/// It replaces the old payment-method picker. There is no card, PayPal, Apple
/// Pay or Google Pay choice here, and no payment details of any kind: a
/// digital subscription is bought through the App Store or Google Play, which
/// collect payment themselves. The screen states the plan, the full amount
/// that will be charged, how often it renews and which store bills it, then
/// "Continue" opens the secure-checkout step ([PlusSecureCheckoutSheet]) that
/// hands over to the billing source.
class PlusPurchaseReviewView extends StatelessWidget {
  const PlusPurchaseReviewView({super.key});

  /// Review → secure checkout → purchase. The purchase only begins when the
  /// user confirms the checkout step.
  Future<void> _continue(
    BuildContext context,
    PlusSubscriptionViewModel vm,
  ) async {
    if (vm.purchasePhase.isInProgress) return;
    final proceed = await PlusSecureCheckoutSheet.show(
      context,
      store: vm.effectiveStore,
      isPreview: vm.offering.isPreview,
    );
    if (!proceed || !context.mounted) return;
    // Starts synchronously (phase becomes `initiating` before this returns),
    // so a second tap on the button is already ignored.
    if (vm.purchasePhase.isInProgress) return;
    unawaited(vm.beginPurchase());
    context.pushReplacement(PlusRoutes.purchase);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final plan = vm.selectedPlan;

    final appBar = AppBar(
      leading: const BackArrowButton(),
      title: Text(
        l10n.translate('plusReviewTitle'),
        style: theme.textTheme.titleLarge,
      ),
      centerTitle: true,
      elevation: 0,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
    );

    if (plan == null || vm.entitlement.isCurrentPlus) {
      return Scaffold(
        appBar: appBar,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlusNoticeCard(
                  icon: Icons.info_outline_rounded,
                  title: l10n.translate('plusReviewNoPlanTitle'),
                  body: l10n.translate('plusReviewNoPlanBody'),
                ),
                const SizedBox(height: 16),
                PlusSecondaryButton(
                  label: l10n.translate('plusBackToPlans'),
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(PlusRoutes.paywall),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final storeName = plusStoreName(l10n, vm.effectiveStore);
    final trialDays = plan.freeTrialDays ?? 0;
    final trialValue = trialDays > 0
        ? l10n.plusText('plusTrialLength', {'days': '$trialDays'})
        : plan.introductoryOfferText?.trim();
    final equivalent = plan.monthlyEquivalent;

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (vm.offering.isPreview) ...[
                    const PlusPreviewBanner(),
                    const SizedBox(height: 16),
                  ],
                  PlusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const PlusIconBadge(
                              icon: Icons.workspace_premium_rounded,
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.translate('plusBrandName'),
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  Text(
                                    plusPeriodName(l10n, plan.period),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        if (plan.hasFreeTrial) ...[
                          if (trialValue != null && trialValue.isNotEmpty)
                            PlusDetailRow(
                              label: l10n.translate('plusReviewFreeTrial'),
                              value: trialValue,
                            ),
                          PlusDetailRow(
                            label: l10n.translate('plusReviewAfterTrial'),
                            value: plusPricePerPeriod(
                              l10n,
                              plan.chargedPerPeriod,
                              plan.period,
                            ),
                          ),
                        ] else
                          // The full amount of one billing period: for an
                          // annual plan, the whole annual charge.
                          PlusDetailRow(
                            label: l10n.translate('plusReviewCharged'),
                            value: plan.chargedPerPeriod,
                          ),
                        PlusDetailRow(
                          label: l10n.translate('plusReviewRenews'),
                          value: plusRenewalFrequency(l10n, plan.period),
                        ),
                        if (equivalent != null && equivalent.isNotEmpty)
                          PlusDetailRow(
                            label: l10n.translate('plusReviewEquivalent'),
                            value: l10n.plusText(
                              'plusPricePerMonth',
                              {'price': equivalent},
                            ),
                          ),
                        PlusDetailRow(
                          label: l10n.translate('plusDetailStore'),
                          value: storeName,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PlusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translate('plusReviewIncludedTitle'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final key in PlusCatalog.highlightKeys)
                          PlusCheckRow(l10n.translate(key)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PlusFootnote(
                    l10n.translate('plusReviewStepNoCard'),
                    icon: Icons.lock_outline_rounded,
                  ),
                  const SizedBox(height: 24),
                  PlusLegalFooter(store: vm.effectiveStore),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: colors.outline.withValues(alpha: 0.18),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.plusText('plusReviewStoreNote', {'store': storeName}),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 10),
                  PlusPrimaryButton(
                    label: plan.hasFreeTrial
                        ? l10n.translate('plusStartTrial')
                        : l10n.translate('plusContinue'),
                    isLoading: vm.purchasePhase.isInProgress,
                    onPressed: () => unawaited(_continue(context, vm)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
