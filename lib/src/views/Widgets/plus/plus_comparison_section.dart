import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/subscription/plus_benefit_catalog.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Free versus Plus as one grouped card of rows rather than a table or a stack
/// of separate cards, so it reads on a narrow phone, wraps long Arabic text and
/// survives large font scales without feeling heavy.
class PlusComparisonSection extends StatelessWidget {
  const PlusComparisonSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final items = PlusCatalog.comparison;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlusSectionTitle(l10n.translate('plusCompareTitle')),
        PlusCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: colors.outline.withValues(alpha: 0.15),
                  ),
                _ComparisonRow(item: items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.item});

  final PlusComparisonItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: colors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate(item.titleKey),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.translate(item.bodyKey),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ValueLine(
            label: l10n.translate('freePlanShort'),
            text: l10n.translate(item.freeKey),
            highlighted: false,
          ),
          const SizedBox(height: 6),
          _ValueLine(
            label: l10n.translate('plusPlanShort'),
            text: l10n.translate(item.plusKey),
            highlighted: true,
          ),
        ],
      ),
    );
  }
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({
    required this.label,
    required this.text,
    required this.highlighted,
  });

  final String label;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = highlighted ? colors.primary : colors.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primary.withValues(alpha: 0.08)
            : colors.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: accent.withValues(alpha: highlighted ? 1.0 : 0.65),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
          ),
          if (highlighted) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle_rounded, color: colors.primary, size: 20),
          ],
        ],
      ),
    );
  }
}
