import 'package:flutter/material.dart';

class AppTypography {
  static const String fontFamily = 'Montserrat'; // Or your custom font

  static const TextStyle heading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Color(0xFF141918),
  );

  static const TextTheme textTheme = TextTheme(
    titleLarge: heading,
    bodyLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      color: Color(0xFF141918),
    ),
    bodyMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      color: Color(0xFF617770),
    ),
  );

  static final TextTheme textThemeDark = TextTheme(
    titleLarge: heading.copyWith(color: Colors.white),
    bodyLarge: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      color: Colors.white,
    ),
    bodyMedium: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      color: Color(0xFFEBEFEF),
    ),
  );
}
