import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/data/models/grid_item_model.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class GridItemCard extends StatelessWidget {
  final GridItemModel item;
  final VoidCallback? onTap;

  const GridItemCard({
    super.key,
    required this.item,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final localization = AppLocalizations.of(context);

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              item.asset,
              width: 40,
              height: 40,
              colorFilter: ColorFilter.mode(
                colors.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text.rich(
                TextSpan(
                  text: item.labelKey != null
                      ? localization.translate(item.labelKey!)
                      : item.label,
                  style: textTheme.bodySmall,
                  children: item.count == null
                      ? const <InlineSpan>[]
                      : <InlineSpan>[
                          TextSpan(
                            text: ' (${item.count})',
                            style: textTheme.bodyMedium,
                          ),
                        ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget list(BuildContext context, List<GridItemModel> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        const crossSpacing = 8.0;
        final cardWidth =
            (constraints.maxWidth - crossSpacing * (columns - 1)) / columns;
        final textTheme = Theme.of(context).textTheme;
        final fontSize = math.max(
          textTheme.bodySmall?.fontSize ?? 12,
          textTheme.bodyMedium?.fontSize ?? 14,
        );
        final lineHeight = math.max(
          textTheme.bodySmall?.height ?? 1.2,
          textTheme.bodyMedium?.height ?? 1.2,
        );
        final scaledLine =
            MediaQuery.textScalerOf(context).scale(fontSize) * lineHeight;
        final minimumHeight = 40 + 8 + (scaledLine * 2) + 16;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: crossSpacing,
            mainAxisSpacing: 12,
            mainAxisExtent: math.max(cardWidth / 0.8, minimumHeight),
          ),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return GridItemCard(
              item: item,
              onTap: getOnTapCallback(context, item.label),
            );
          },
        );
      },
    );
  }

  // CHANGE THIS: Remove the underscore to make it public
  static VoidCallback? getOnTapCallback(BuildContext context, String label) {
    switch (label) {
      case 'Requested':
        return () => context.push('/requested-list');
      case 'Offers':
        return () => context.push('/offers-list');
      case 'Owners':
        return () => context.push('/owners-list');
      case 'Offices':
        return () => context.push('/offices-list');
      case 'Watchmen':
        return () => context.push('/watchmen-list');
      case 'Brokers':
        return () => context.push('/brokers-list');
      case 'Toolkit':
        return () => context.push('/toolkit-list');
      case 'Quotation':
        return () => context.push('/quotation-list');
      case 'Map':
        return () => context.push('/map-view');
      default:
        return null;
    }
  }
}
