// lib/src/viewmodels/language_viewmodel.dart
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/data/models/language_option_model.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';

/// ViewModel for the Select Language screen
class LanguageViewModel extends ChangeNotifier {
  final LocaleViewModel localeVM;

  /// Available language options
  final List<LanguageOption> options = [
    LanguageOption(
      locale: const Locale('en'),
      labelKey: 'english',
      assetPath: 'assets/icons/flag_us.svg',
    ),
    LanguageOption(
      locale: const Locale('ar'),
      labelKey: 'arabic',
      assetPath: 'assets/icons/flag_arab.svg',
    ),
  ];

  /// Currently selected locale
  Locale selected;

  LanguageViewModel({required this.localeVM}) : selected = localeVM.locale;

  /// Select a new locale
  void select(Locale locale) {
    selected = locale;
    notifyListeners();
  }

  /// Persist the selection back to the app-level LocaleViewModel
  void save() {
    localeVM.setLocale(selected);
  }
}
