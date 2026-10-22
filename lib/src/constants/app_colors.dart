//Broker_wallet/lib/src/constants/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF02957D); // Main color
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFF6F6F8);
  static const Color card = Color(0xFFEBEFEF);
  static const Color textPrimary = Color(0xFF141918);
  static const Color textSecondary = Color(0xFF617770);
  static const Color white = Color(0xFFFFFFFF);
  static const Color tilePrimary = Color.fromARGB(255, 230, 237, 235);
  static const Color tileSecondary = Color.fromARGB(255, 206, 212, 212);

  // Dark theme variants
  static const Color darkBackground = Color(0xFF141918);
  static const Color darkSurface = Color(0xFF22292F);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);

  // Box Decoration colors
  static const Color boxDecoration = Color(0xFFF0F0F0);
  static const Color boxDecorationDark = Color(0xFF22292F);

  // Login / Signup input fields only (read through AuthInputStyle).
  // Contrast is measured against the field fill (surface / darkSurface):
  // borders and icons >= 3:1, hint and label text >= 4.5:1.
  static const Color authInputBorder = Color(0xFF7F8A86);
  static const Color authInputBorderDark = Color(0xFF76817C);
  static const Color authInputFocusedBorder = primary;
  static const Color authInputIcon = Color(0xFF6B7773);
  static const Color authInputIconDark = Color(0xFF8E9994);
  static const Color authInputFocusedIcon = primary;
  static const Color authInputHint = Color(0xFF66726D);
  static const Color authInputHintDark = Color(0xFF9AA5A0);
  static const Color authInputLabel = Color(0xFF55655F);
  static const Color authInputLabelDark = Color(0xFFEBEFEF);
}

/// Resolves the Login / Signup field colors and border width for the current
/// theme. Style values only: it adds no widget and changes no layout.
class AuthInputStyle {
  const AuthInputStyle._();

  static const double borderWidth = 1.0;

  static bool _isDark(ColorScheme colors) =>
      colors.brightness == Brightness.dark;

  static Color border(
    ColorScheme colors, {
    required bool focused,
    required bool hasError,
  }) {
    if (hasError) return colors.error;
    if (focused) return AppColors.authInputFocusedBorder;
    return _isDark(colors)
        ? AppColors.authInputBorderDark
        : AppColors.authInputBorder;
  }

  static Color icon(
    ColorScheme colors, {
    required bool focused,
    required bool hasError,
  }) {
    if (hasError) return colors.error;
    if (focused) return AppColors.authInputFocusedIcon;
    return _isDark(colors)
        ? AppColors.authInputIconDark
        : AppColors.authInputIcon;
  }

  static Color hint(ColorScheme colors) =>
      _isDark(colors) ? AppColors.authInputHintDark : AppColors.authInputHint;

  static Color label(ColorScheme colors) => _isDark(colors)
      ? AppColors.authInputLabelDark
      : AppColors.authInputLabel;
}
