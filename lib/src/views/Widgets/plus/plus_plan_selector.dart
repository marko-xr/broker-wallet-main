import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';

/// Billing-period choice. Works with one plan or two, and in every case keeps
/// the amount actually charged per period on screen: an annual plan's
/// per-month equivalent is shown only as a smaller secondary line.
class PlusPlanSelector extends StatelessWidget {
  const PlusPlanSelector({
    super.key,
    required this.plans,
    required this.selectedPeriod,
    required this.onSelected,
  });

  final List<SubscriptionPlanUiModel> plans;
  final SubscriptionPeriod? selectedPeriod;
  final ValueChanged<SubscriptionPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < plans.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _PlanOptionCard(
            plan: plans[i],
            selected: plans[i].period == selectedPeriod,
            onTap: () => onSelected(plans[i].period),
          ),
        ],
      ],
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionPlanUiModel plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final trial = plusTrialDescription(l10n, plan);
    final equivalent = plan.monthlyEquivalent;
    final savings = plan.savingsPercent;

    final periodName = plusPeriodName(l10n, plan.period);
    final headline = plusPricePerPeriod(l10n, plan.localizedPrice, plan.period);

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '$periodName, $headline',
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
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
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
                          if (savings != null && savings > 0)
                            _Badge(
                              text: l10n.plusText(
                                'plusSavePercent',
                                {'percent': '$savings'},
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                      // The headline above is already the full amount charged
                      // for one period. A per-month equivalent is only ever a
                      // quieter second line.
                      if (equivalent != null && equivalent.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.plusText(
                            'plusMonthlyEquivalent',
                            {'price': equivalent},
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      if (trial != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          trial,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
