import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Category and per-item usage, ready for server-provided counters. Without a
/// trusted source it shows the unavailable state and never a made-up number.
class UsageDetailsView extends StatelessWidget {
  const UsageDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final usage = SubscriptionScope.of(context).usage;
    return SubscriptionPage(
      title: loc.translate('subUsageTitle'),
      children: [
        SubHeading(loc.translate('subUsageHeading')),
        const SizedBox(height: 8),
        SubBodyText(loc.translate('subUsageIntro')),
        const SizedBox(height: 16),
        ..._stateNotice(loc, usage),
        SubSection(loc.translate('subUsageCreations')),
        if (usage.state == UsageDataState.loading)
          const SubSkeleton(lines: 6)
        else
          SubUsageList(usage: usage),
        SubSection(loc.translate('subUsageEdits')),
        _ItemEdits(usage: usage),
        const SizedBox(height: 16),
        SubSecondaryButton(
          label: loc.translate('subHowLimitsTitle'),
          onPressed: () => context.push(SubscriptionRoutes.limits),
        ),
      ],
    );
  }

  List<Widget> _stateNotice(AppLocalizations loc, UsageSnapshot usage) {
    final key = switch (usage.state) {
      UsageDataState.loading => 'subUsageLoading',
      UsageDataState.unavailable => 'subUsageUnavailable',
      UsageDataState.empty => 'subUsageEmpty',
      UsageDataState.populated => null,
    };
    if (key == null) return const [];
    return [
      SubNotice(icon: Icons.info_outline_rounded, text: loc.translate(key)),
    ];
  }
}

class _ItemEdits extends StatelessWidget {
  const _ItemEdits({required this.usage});

  final UsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (usage.state == UsageDataState.loading) {
      return const SubSkeleton(lines: 3);
    }
    if (usage.items.isEmpty) {
      return SubCard(
        child: SubBodyText(
          loc.translate(
            usage.state == UsageDataState.unavailable
                ? 'subEditsUnavailable'
                : 'subEditsEmpty',
          ),
        ),
      );
    }
    return SubCard(
      child: Column(
        children: [for (final item in usage.items) _ItemEditRow(item: item)],
      ),
    );
  }
}

class _ItemEditRow extends StatelessWidget {
  const _ItemEditRow({required this.item});

  final ItemEditUsage item;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = item.isExhausted
        ? loc.translate('subNoFreeEdits')
        : loc.fill('subEditsUsed', {
            'used': '${item.editsUsed}',
            'limit': '${SubscriptionPolicy.freeEditsPerItem}',
          });
    final category = loc.categoryName(item.category);
    return Semantics(
      label: '${item.title}, $category, $status',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              SubBodyText('$category · $status'),
              const SizedBox(height: 6),
              SubEditMeter(used: item.editsUsed),
            ],
          ),
        ),
      ),
    );
  }
}
