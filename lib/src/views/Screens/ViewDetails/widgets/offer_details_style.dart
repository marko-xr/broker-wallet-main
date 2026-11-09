import 'package:flutter/material.dart';

/// Screen-scoped layout typography using Broker Wallet's existing palette.
/// The app theme remains unchanged outside this explicitly redesigned screen.
abstract final class OfferDetailsStyle {
  static double scale(BuildContext context) =>
      (MediaQuery.sizeOf(context).width / 369).clamp(0.85, 1.2);

  static ThemeData theme(ThemeData base, {required double scale}) {
    final scheme = base.colorScheme;
    // Keep Broker Wallet's original font family and platform fallbacks.
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle style(TextStyle? inherited, double size, FontWeight weight) =>
        (inherited ?? const TextStyle()).copyWith(
          fontSize: size * scale,
          fontWeight: weight,
          height: 1.35,
          color: scheme.onSurface,
        );
    return base.copyWith(
      colorScheme: scheme,
      dividerColor: scheme.onSurface.withValues(alpha: 0.08),
      textTheme: text.copyWith(
        titleLarge: style(text.titleLarge, 17, FontWeight.w700),
        titleMedium: style(text.titleMedium, 12, FontWeight.w700),
        titleSmall: style(text.titleSmall, 11, FontWeight.w600),
        bodyMedium: style(text.bodyMedium, 10.5, FontWeight.w400),
        bodySmall: style(text.bodySmall, 9, FontWeight.w400),
        labelLarge: style(text.labelLarge, 12, FontWeight.w700),
        labelMedium: style(text.labelMedium, 10, FontWeight.w600),
        labelSmall: style(text.labelSmall, 9, FontWeight.w600),
      ),
    );
  }
}
