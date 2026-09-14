// lib/src/widgets/settings_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SettingsTile extends StatelessWidget {
  final String iconAsset;
  final bool isSvg;

  /// Used when [isSvg] is false and a Material icon should be shown instead
  /// (e.g. for rows that don't have a dedicated SVG asset yet). Falls back
  /// to a generic icon when omitted.
  final IconData? materialIcon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool hasSwitch;
  final bool switchValue;
  final ValueChanged<bool>? onSwitch;
  final String? switchLabel;
  final bool hasTrailing;
  final Widget? trailingWidget;

  /// Visually distinguishes destructive/security-sensitive rows (e.g.
  /// Delete Account) using the theme's error color instead of primary.
  final bool destructive;

  /// True when this tile is rendered as one row inside a shared
  /// [SettingsSectionCard]. In that mode the tile draws no outer margin,
  /// background or rounded corners of its own — the section card owns the
  /// background/border radius/clipping and dividers are drawn between rows
  /// by the card, not by the tile. Defaults to false so any standalone use
  /// keeps its original self-contained card look.
  final bool grouped;

  const SettingsTile({
    super.key,
    required this.iconAsset,
    this.isSvg = false,
    this.materialIcon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.hasSwitch = false,
    this.switchValue = false,
    this.onSwitch,
    this.switchLabel,
    this.hasTrailing = false,
    this.trailingWidget,
    this.destructive = false,
    this.grouped = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final accentColor = destructive ? colors.error : colors.primary;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    final trailingContent = hasSwitch
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (switchLabel != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Text(
                    switchLabel!,
                    style: texts.bodySmall!.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: switchValue,
                  onChanged: onSwitch,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          )
        : hasTrailing
            ? trailingWidget
            : Icon(
                isRtl ? Icons.chevron_right : Icons.chevron_right,
                color: colors.onSurface.withValues(alpha: 0.4),
              );

    final rowContent = Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: isSvg
                  ? SvgPicture.asset(
                      iconAsset,
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        accentColor,
                        BlendMode.srcIn,
                      ),
                    )
                  : Icon(
                      materialIcon ?? Icons.error,
                      color: accentColor,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texts.titleMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: destructive ? colors.error : null,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.bodySmall!.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingContent != null) ...[
            const SizedBox(width: 16),
            trailingContent,
          ],
        ],
      ),
    );

    // Grouped rows live inside a shared SettingsSectionCard, which already
    // supplies the Material ancestor, background, rounded corners and
    // clipping — the row itself only needs the tap ripple.
    if (grouped) {
      return InkWell(
        onTap: onTap,
        child: rowContent,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: rowContent,
        ),
      ),
    );
  }
}
