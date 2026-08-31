// lib/src/data/models/language_option_model.dart
import 'package:flutter/material.dart';

/// Model representing a supported language option
typedef LocaleOption = LanguageOption;

class LanguageOption {
  final Locale locale;
  final String labelKey; // ARB key, e.g. 'english', 'arabic'
  final String assetPath;

  LanguageOption({
    required this.locale,
    required this.labelKey,
    required this.assetPath,
  });
}
