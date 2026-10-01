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
import 'package:broker_wallet/src/views/Widgets/plus/plus_comparison_section.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_debug_preview_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_legal_footer.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_plan_selector.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// The Broker Wallet Plus paywall: what Plus adds, Free versus Plus, and the
/// billing-period choice. It only ever *presents* plans; the actual purchase
/// is handed to the billing source from the review screen.
class PlusPaywallView extends StatefulWidget {
  const PlusPaywallView({super.key});

  @override
  State<PlusPaywallView> createState() => _PlusPaywallViewState();
}

class _PlusPaywallViewState extends State<PlusPaywallView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PlusSubscriptionViewModel>().ensureOfferingLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final isPlus = vm.entitlement.isCurrentPlus;
    // The plan the pinned bar offers; null whenever nothing can be bought now.
    final purchasablePlan =
        !isPlus && vm.offeringState == OfferingLoadState.ready
            ? vm.selectedPlan
            : null;
    final showPreview = vm.offering.isPreview || vm.entitlement.isPreview;

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(
          l10n.translate('plusBrandName'),
          style: theme.textTheme.titleLarge,
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: const [PlusDebugButton()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const PlusHero(),
                  const SizedBox(height: 24),
                  if (showPreview) ...[
                    const PlusPreviewBanner(),
                    const SizedBox(height: 16),
                  ],
                  if (isPlus)
                    PlusNoticeCard(
                      icon: Icons.verified_rounded,
                      tone: PlusTone.positive,
                      title: l10n.translate('plusAlreadyPlusTitle'),
                      body: l10n.translate('plusAlreadyPlusBody'),
                      actionLabel: l10n.translate('plusBillingTitle'),
                      onAction: () =>
                          context.pushReplacement(PlusRoutes.billing),
                    )
                  else ...[
                    if (vm.status == SubscriptionStatus.expired) ...[
                      _ExpiredNotice(state: vm.entitlement),
                      const SizedBox(height: 16),
                    ],
                    if (vm.hasPendingPurchase) ...[
                      PlusNoticeCard(
                        icon: Icons.schedule_rounded,
                        title: l10n.translate('plusPendingBannerTitle'),
                        body: l10n.translate('plusPendingBannerBody'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // What Plus is, what it costs and how often it bills come
                    // first; the Free-versus-Plus detail is below the plans.
                    for (final key in PlusCatalog.highlightKeys)
                      PlusCheckRow(l10n.translate(key)),
                    const SizedBox(height: 16),
                    PlusSectionTitle(l10n.translate('plusChoosePlanTitle')),
                    _PlansBlock(vm: vm),
                    const SizedBox(height: 24),
                    const PlusComparisonSection(),
                  ],
                  const SizedBox(height: 24),
                  PlusLegalFooter(store: vm.effectiveStore, showRestore: true),
                ],
              ),
            ),
            if (purchasablePlan != null)
              _PurchaseBar(
                plan: purchasablePlan,
                status: vm.status,
                store: vm.effectiveStore,
              ),
          ],
        ),
      ),
    );
  }
}

class _PlansBlock extends StatelessWidget {
  const _PlansBlock({required this.vm});

  final PlusSubscriptionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    switch (vm.offeringState) {
      case OfferingLoadState.idle:
      case OfferingLoadState.loading:
        return PlusCard(
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.translate('plusLoadingPlans'))),
            ],
          ),
        );
      case OfferingLoadState.unavailable:
        return PlusNoticeCard(
          icon: Icons.schedule_rounded,
          title: l10n.translate('plusPlansUnavailableTitle'),
          body: l10n.translate('plusPlansUnavailableBody'),
        );
      case OfferingLoadState.ready:
        return PlusPlanSelector(
          plans: vm.offering.plans,
          selectedPeriod: vm.selectedPlan?.period,
          onSelected: vm.selectPeriod,
        );
    }
  }
}

class _ExpiredNotice extends StatelessWidget {
  const _ExpiredNotice({required this.state});

  final SubscriptionUiState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ended = state.expiresOn;
    return PlusNoticeCard(
      icon: Icons.event_busy_rounded,
      tone: PlusTone.attention,
      title: l10n.translate('plusExpiredTitle'),
      body: ended != null
          ? l10n.plusText(
              'plusExpiredBodyDate',
              {'date': plusFormatDate(context, ended)},
            )
          : l10n.translate('plusExpiredBody'),
    );
  }
}

/// The pinned footer: what will be charged, and the single primary action.
class _PurchaseBar extends StatelessWidget {
  const _PurchaseBar({
    required this.plan,
    required this.status,
    required this.store,
  });

  final SubscriptionPlanUiModel plan;
  final SubscriptionStatus status;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final summary =
        plusTrialDescription(l10n, plan) ?? plusBilledDescription(l10n, plan);
    final label = status == SubscriptionStatus.expired
        ? l10n.translate('plusResubscribe')
        : plan.hasFreeTrial
            ? l10n.translate('plusStartTrial')
            : l10n.translate('plusContinue');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: colors.outline.withValues(alpha: 0.18)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            summary,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.plusText(
              'plusBarCaption',
              {'store': plusStoreName(l10n, store)},
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          PlusPrimaryButton(
            label: label,
            onPressed: () => context.push(PlusRoutes.review),
          ),
        ],
      ),
    );
  }
}
