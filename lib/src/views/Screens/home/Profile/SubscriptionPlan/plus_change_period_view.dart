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

/// Change billing period: the Broker Wallet-owned step before switching
/// between monthly and annual in the store.
///
/// Plus is a single plan sold on two billing periods, so changing the plan and
/// changing the billing period are the same action; this screen is where both
/// live. It shows the current period, the options, and what happens next, then
/// hands over to the store. It never changes the subscription, never invents a
/// price (an option shows the store's own price only when the billing source
/// has supplied one) and never claims a change happened.
class PlusChangePeriodView extends StatefulWidget {
  const PlusChangePeriodView({super.key});

  @override
  State<PlusChangePeriodView> createState() => _PlusChangePeriodViewState();
}

class _PlusChangePeriodViewState extends State<PlusChangePeriodView> {
  SubscriptionPeriod? _selected;

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
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final storeName = plusStoreName(l10n, store);
    final current = state.period;
    final title = l10n.translate('plusChangePeriodRow');

    final canChange = state.status == SubscriptionStatus.active ||
        state.status == SubscriptionStatus.trial;
    if (!canChange) {
      return PlusScreenScaffold(
        title: title,
        children: [
          PlusNoticeCard(
            icon: Icons.info_outline_rounded,
            title: l10n.translate('plusChangePeriodUnavailableTitle'),
            body: l10n.translate('plusChangePeriodUnavailableBody'),
          ),
          const SizedBox(height: 16),
          PlusSecondaryButton(
            label: l10n.translate('plusManageSubscription'),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(PlusRoutes.manage);
              }
            },
          ),
        ],
      );
    }

    final chosen = _selected;
    final canContinue = chosen != null && chosen != current;

    return PlusScreenScaffold(
      title: title,
      bottom: PlusBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.plusText('plusChangePeriodNote', {'store': storeName}),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.75),
                  ),
            ),
            const SizedBox(height: 10),
            PlusPrimaryButton(
              label: l10n.translate('plusContinue'),
              onPressed: canContinue
                  ? () => PlusManageSheet.show(
                        context,
                        store: store,
                        action: PlusManageAction.changePeriod,
                        managementUri: state.managementUri,
                      )
                  : null,
            ),
          ],
        ),
      ),
      children: [
        if (vm.offering.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        PlusInfoHeader(
          icon: Icons.swap_horiz_rounded,
          title: current != null
              ? l10n.plusText('plusChangePeriodCurrent', {
                  'period': plusPeriodName(l10n, current),
                })
              : l10n.translate('plusChangePeriodRow'),
          body: l10n.plusText('plusChangePeriodIntro', {'store': storeName}),
        ),
        const SizedBox(height: 24),
        PlusSectionLabel(l10n.translate('plusChangePeriodOptions')),
        for (final period in SubscriptionPeriod.values) ...[
          _PeriodOption(
            period: period,
            isCurrent: period == current,
            selected: period == chosen,
            plan: vm.offering.planFor(period),
            storeName: storeName,
            onTap: period == current
                ? null
                : () => setState(() => _selected = period),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PeriodOption extends StatelessWidget {
  const _PeriodOption({
    required this.period,
    required this.isCurrent,
    required this.selected,
    required this.plan,
    required this.storeName,
    required this.onTap,
  });

  final SubscriptionPeriod period;
  final bool isCurrent;
  final bool selected;

  /// The store's own plan for this period, when the billing source has
  /// supplied one. Without it no price is shown at all.
  final SubscriptionPlanUiModel? plan;
  final String storeName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final periodName = plusPeriodName(l10n, period);
    final detail = plan != null
        ? plusBilledDescription(l10n, plan!)
        : l10n.plusText('plusChangePeriodPriceInStore', {'store': storeName});

    return Semantics(
      button: onTap != null,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: isCurrent
          ? '$periodName, ${l10n.translate('plusChangePeriodCurrentBadge')}'
          : periodName,
      child: Material(
        color:
            selected ? colors.primary.withValues(alpha: 0.08) : colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? colors.primary
                    : colors.outline.withValues(alpha: 0.25),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isCurrent
                        ? Icons.check_circle_rounded
                        : selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                    color: isCurrent || selected
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            periodName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.onSurface,
                            ),
                          ),
                          if (isCurrent)
                            PlusStatusChip(
                              label: l10n
                                  .translate('plusChangePeriodCurrentBadge'),
                              tone: PlusTone.positive,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.75),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
