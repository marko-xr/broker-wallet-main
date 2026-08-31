// lib/src/widgets/settings_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SettingsTile extends StatelessWidget {
  final String iconAsset;
  final bool isSvg;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool hasSwitch;
  final bool switchValue;
  final ValueChanged<bool>? onSwitch;
  final String? switchLabel;
  final bool hasTrailing;
  final Widget? trailingWidget;

  const SettingsTile({
    super.key,
    required this.iconAsset,
    this.isSvg = false,
    required this.title,
    this.subtitle,
    this.onTap,
    this.hasSwitch = false,
    this.switchValue = false,
    this.onSwitch,
    this.switchLabel,
    this.hasTrailing = false,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;

    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    final trailingContent = hasSwitch
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (switchLabel != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    switchLabel!,
                    style: texts.bodySmall!.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Switch(
                value: switchValue,
                onChanged: onSwitch,
              ),
            ],
          )
        : hasTrailing
            ? trailingWidget
            : Icon(
                Icons.chevron_right,
                color: colors.onSurface.withValues(alpha: 0.4),
              );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: isSvg
                        ? SvgPicture.asset(
                            iconAsset,
                            width: 28,
                            height: 28,
                            colorFilter: ColorFilter.mode(
                              colors.primary,
                              BlendMode.srcIn,
                            ),
                          )
                        : Icon(
                            Icons.error,
                            color: colors.primary,
                            size: 28,
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
          ),
        ),
      ),
    );
  }
}
