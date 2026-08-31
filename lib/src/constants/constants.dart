import 'package:flutter/material.dart';

class AppTextStyles {
  // Font family
  static const String fontFamily = 'Inter'; // or your preferred font

  // Font sizes
  static const double headlineLarge = 24.0;
  static const double headlineMedium = 20.0;
  static const double headlineSmall = 18.0;
  static const double titleLarge = 18.0;
  static const double titleMedium = 16.0;
  static const double titleSmall = 14.0;
  static const double bodyLarge = 16.0;
  static const double bodyMedium = 14.0;
  static const double bodySmall = 12.0;
  static const double labelLarge = 14.0;
  static const double labelMedium = 12.0;
  static const double labelSmall = 11.0;

  // Common text styles
  static const TextStyle appBarTitle = TextStyle(
    fontSize: titleLarge,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: titleMedium,
    fontWeight: FontWeight.w500,
    fontFamily: fontFamily,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: bodyMedium,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );

  static const TextStyle chipText = TextStyle(
    fontSize: labelLarge,
    fontWeight: FontWeight.w500,
    fontFamily: fontFamily,
  );

  static const TextStyle bodyText = TextStyle(
    fontSize: bodyMedium,
    fontWeight: FontWeight.normal,
    fontFamily: fontFamily,
  );

  static const TextStyle hintText = TextStyle(
    color: Color(0xFFBDBDBD),
    fontSize: bodyMedium,
    fontWeight: FontWeight.normal,
    fontFamily: fontFamily,
  );

  static const TextStyle tabText = TextStyle(
    fontSize: bodyLarge,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
  );
}
