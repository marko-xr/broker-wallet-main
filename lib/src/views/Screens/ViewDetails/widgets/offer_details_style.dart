import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Typography and control styling shared by Broker Wallet Details screens.
abstract final class OfferDetailsStyle {
  static double scale(BuildContext context) =>
      (MediaQuery.sizeOf(context).width / 369).clamp(0.85, 1.2);

  static double toolbarHeight(BuildContext context, double scale) {
    final text = MediaQuery.textScalerOf(context);
    return (48 * scale).clamp(48.0, double.infinity) +
        (text.scale(44 * scale) - 44 * scale).clamp(0.0, double.infinity);
  }

  // Keep the brand fill. The existing dark foreground reads clearly on it.
  static const primaryButtonForeground = AppColors.textPrimary;

  // Opaque stops keep the green gradient and its contrast in both themes.
  static List<Color> rentBadgeGradient(ColorScheme colors) => [
        colors.primary,
        Color.alphaBlend(
            colors.onPrimary.withValues(alpha: 0.08), colors.primary),
      ];

  static Color accentText(ColorScheme colors, Color background) {
    final base = background.computeLuminance();
    for (var step = 0; step < 10; step++) {
      final candidate =
          Color.lerp(colors.primary, colors.onSurface, step / 10)!;
      final light = candidate.computeLuminance();
      final contrast = light > base
          ? (light + 0.05) / (base + 0.05)
          : (base + 0.05) / (light + 0.05);
      if (contrast >= 4.5) return candidate;
    }
    return colors.onSurface;
  }

  static ThemeData theme(ThemeData base, {required double scale}) {
    final scheme = base.colorScheme;
    // Keep Broker Wallet's original font family and platform fallbacks.
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle style(TextStyle? inherited, double size, FontWeight weight) =>
        (inherited ?? const TextStyle()).copyWith(
          fontSize: size * scale.clamp(1.0, double.infinity),
          fontWeight: weight,
          height: 1.35,
          color: scheme.onSurface,
        );
    return base.copyWith(
      colorScheme: scheme,
      dividerColor: scheme.onSurface.withValues(alpha: 0.08),
      textTheme: text.copyWith(
        titleLarge: style(text.titleLarge, 17, FontWeight.w700),
        titleMedium: style(text.titleMedium, 14, FontWeight.w700),
        titleSmall: style(text.titleSmall, 13, FontWeight.w600),
        bodyMedium: style(text.bodyMedium, 13, FontWeight.w400),
        bodySmall: style(text.bodySmall, 12, FontWeight.w400),
        labelLarge: style(text.labelLarge, 12, FontWeight.w700),
        labelMedium: style(text.labelMedium, 12, FontWeight.w600),
        labelSmall: style(text.labelSmall, 12, FontWeight.w600),
      ),
    );
  }
}
