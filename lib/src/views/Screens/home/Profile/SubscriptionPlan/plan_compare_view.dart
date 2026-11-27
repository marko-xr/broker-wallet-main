import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';

class PlanCompareView extends StatelessWidget {
  const PlanCompareView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SubscriptionPage(
      title: loc.translate('subCompareTitle'),
      children: [
        SubHeading(loc.translate('subCompareHeading')),
        const SizedBox(height: 8),
        SubBodyText(loc.translate('subCompareIntro')),
        const SizedBox(height: 16),
        const PlanComparisonTable(),
        const SizedBox(height: 16),
        SubNotice(
          icon: Icons.info_outline_rounded,
          text: loc.translate('subCompareFootnote'),
        ),
      ],
    );
  }
}

/// Free against Plus. [compact] keeps only the limits for the plans screen.
class PlanComparisonTable extends StatelessWidget {
  const PlanComparisonTable({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fiveEach = loc.translate('subFiveEachLifetime');
    final unlimited = loc.translate('unlimited');
    final yes = loc.translate('subYes');
    final rows = <(String, String, String)>[
      (loc.categoryList(UsageCategory.records), fiveEach, unlimited),
      (
        loc.categoryName(UsageCategory.quotations),
        loc.translate('subFiveLifetime'),
        unlimited
      ),
      (loc.categoryList(UsageCategory.toolkit), fiveEach, unlimited),
      (
        loc.translate('subRowContentEdits'),
        loc.translate('subThreePerItem'),
        unlimited
      ),
      if (!compact) ...[
        (loc.translate('subRowViewSearch'), yes, yes),
        (loc.translate('subRowShareFavorites'), yes, yes),
        (loc.translate('subRowSmartMap'), yes, yes),
        (loc.translate('subRowUaeLinks'), yes, yes),
        (loc.translate('subRowExistingDocuments'), yes, yes),
      ],
    ];
    final header = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
    );
    final plusStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: subToneColor(colors, SubTone.positive),
    );
    final freeStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.onSurface,
    );
    final featureStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurface,
      height: 1.35,
    );
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final freeName = loc.translate('subPlanFree');
    final plusName = loc.translate('subPlanPlus');
    return LayoutBuilder(builder: (context, constraints) {
      // Three columns would split words on narrow, large-text layouts.
      final stacked = constraints.maxWidth / scale < 270;
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: subCardDecoration(colors),
          child: Column(
            children: [
              if (!stacked)
                Container(
                  color: colors.onSurface.withValues(alpha: 0.04),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: ExcludeSemantics(
                    child: _cells(
                      Text(loc.translate('subFeature'), style: header),
                      Text(
                        freeName,
                        textAlign: TextAlign.center,
                        style: header,
                      ),
                      Text(
                        plusName,
                        textAlign: TextAlign.center,
                        style: header?.copyWith(
                          color: subToneColor(colors, SubTone.positive),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final (feature, free, plus) in rows)
                Semantics(
                  label: '$feature. $freeName: $free. $plusName: $plus.',
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feature,
                                  style: featureStyle?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _stackedValue(
                                    freeName, free, featureStyle, freeStyle),
                                _stackedValue(
                                    plusName, plus, featureStyle, plusStyle),
                              ],
                            )
                          : _cells(
                              Text(feature, style: featureStyle),
                              Text(free,
                                  textAlign: TextAlign.center,
                                  style: freeStyle),
                              Text(plus,
                                  textAlign: TextAlign.center,
                                  style: plusStyle),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _stackedValue(
    String plan,
    String value,
    TextStyle? planStyle,
    TextStyle? valueStyle,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: Text(plan, style: planStyle)),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(value, textAlign: TextAlign.end, style: valueStyle),
            ),
          ],
        ),
      );

  Widget _cells(Widget feature, Widget free, Widget plus) => Row(
        children: [
          Expanded(flex: 5, child: feature),
          const SizedBox(width: 6),
          Expanded(flex: 3, child: free),
          const SizedBox(width: 6),
          Expanded(flex: 3, child: plus),
        ],
      );
}
