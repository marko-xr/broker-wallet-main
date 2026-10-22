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

  // Approved text-field styling, shared by Login / Signup and the entity forms
  // (read through AppInputStyle). Contrast is measured against the field fill
  // (surface / darkSurface): borders and icons >= 3:1, hint and label text
  // >= 4.5:1.
  static const Color inputBorder = Color(0xFF7F8A86);
  static const Color inputBorderDark = Color(0xFF76817C);
  static const Color inputFocusedBorder = primary;
  static const Color inputIcon = Color(0xFF6B7773);
  static const Color inputIconDark = Color(0xFF8E9994);
  static const Color inputFocusedIcon = primary;
  static const Color inputHint = Color(0xFF66726D);
  static const Color inputHintDark = Color(0xFF9AA5A0);
  static const Color inputLabel = Color(0xFF55655F);
  static const Color inputLabelDark = Color(0xFFEBEFEF);
}

/// Resolves the approved text-field colors and border width for the current
/// theme. Style values only: it adds no widget and changes no layout.
class AppInputStyle {
  const AppInputStyle._();

  static const double borderWidth = 1.0;
  static const double fieldRadius = 10;

  static bool _isDark(ColorScheme colors) =>
      colors.brightness == Brightness.dark;

  static Color border(
    ColorScheme colors, {
    required bool focused,
    bool hasError = false,
  }) {
    if (hasError) return colors.error;
    if (focused) return AppColors.inputFocusedBorder;
    return _isDark(colors) ? AppColors.inputBorderDark : AppColors.inputBorder;
  }

  static Color icon(
    ColorScheme colors, {
    required bool focused,
    bool hasError = false,
  }) {
    if (hasError) return colors.error;
    if (focused) return AppColors.inputFocusedIcon;
    return _isDark(colors) ? AppColors.inputIconDark : AppColors.inputIcon;
  }

  static Color hint(ColorScheme colors) =>
      _isDark(colors) ? AppColors.inputHintDark : AppColors.inputHint;

  static Color label(ColorScheme colors) =>
      _isDark(colors) ? AppColors.inputLabelDark : AppColors.inputLabel;

  /// The single field outline. Use it as a `foregroundDecoration` on the
  /// field's existing box: it paints over that box, so it adds no size.
  static BoxDecoration outline(
    ColorScheme colors, {
    required bool focused,
    bool hasError = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(fieldRadius),
      border: Border.all(
        color: border(colors, focused: focused, hasError: hasError),
        width: borderWidth,
      ),
    );
  }
}

/// Lets a field's State repaint its [AppInputStyle.outline] when it gains or
/// loses focus. Pass [inputFocusNode] to the field's TextField; it only
/// observes focus and changes no focus behaviour.
mixin InputFocusOutlineMixin<T extends StatefulWidget> on State<T> {
  final FocusNode inputFocusNode = FocusNode();

  bool get inputFocused => inputFocusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    inputFocusNode.addListener(_repaintOutline);
  }

  void _repaintOutline() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    inputFocusNode.dispose();
    super.dispose();
  }
}

/// Login / Signup entry point to [AppInputStyle]; the values are the same.
class AuthInputStyle {
  const AuthInputStyle._();

  static const double borderWidth = AppInputStyle.borderWidth;

  static Color border(
    ColorScheme colors, {
    required bool focused,
    required bool hasError,
  }) =>
      AppInputStyle.border(colors, focused: focused, hasError: hasError);

  static Color icon(
    ColorScheme colors, {
    required bool focused,
    required bool hasError,
  }) =>
      AppInputStyle.icon(colors, focused: focused, hasError: hasError);

  static Color hint(ColorScheme colors) => AppInputStyle.hint(colors);

  static Color label(ColorScheme colors) => AppInputStyle.label(colors);
}
