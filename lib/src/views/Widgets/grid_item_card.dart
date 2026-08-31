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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.labelKey != null
                      ? localization.translate(item.labelKey!)
                      : item.label,
                  style: textTheme.bodySmall,
                ),
                if (item.count != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${item.count})',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget list(BuildContext context, List<GridItemModel> items) {
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 12,
      childAspectRatio: 0.8,
      padding: EdgeInsets.zero,
      children: items
          .map((item) => GridItemCard(
                item: item,
                onTap: getOnTapCallback(context, item.label),
              ))
          .toList(),
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
