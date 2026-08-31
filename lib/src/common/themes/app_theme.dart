import 'package:flutter/material.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/constants/app_typography.dart';

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      surface: AppColors.surface,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: AppTypography.fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      iconTheme: IconThemeData(color: AppColors.primary),
      elevation: 0,
      titleTextStyle: AppTypography.heading,
      centerTitle: false,
    ),
    textTheme: AppTypography.textTheme,
    iconTheme: const IconThemeData(color: AppColors.primary),
  );

  static final ThemeData darkTheme = ThemeData(
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      surface: AppColors.darkSurface,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimaryDark,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    fontFamily: AppTypography.fontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      iconTheme: const IconThemeData(color: AppColors.primary),
      elevation: 0,
      titleTextStyle: AppTypography.heading.copyWith(color: Colors.white),
      centerTitle: false,
    ),
    textTheme: AppTypography.textThemeDark,
    iconTheme: const IconThemeData(color: AppColors.primary),
  );
}
