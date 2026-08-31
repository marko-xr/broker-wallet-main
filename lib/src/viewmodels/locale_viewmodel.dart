// lib/src/viewmodels/locale_viewmodel.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;

class LocaleViewModel extends ChangeNotifier {
  // Key to store the language code in SharedPreferences
  static const String _languageCodeKey = 'languageCode';

  // Default value (will be overridden by saved preference or device locale)
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LocaleViewModel() {
    // Load the saved locale when the ViewModel is created
    _loadLocale();
  }

  /// Loads the saved language preference from SharedPreferences.
  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();

    // Get the saved language code (null if not saved)
    final savedLanguageCode = prefs.getString(_languageCodeKey);

    // Supported languages in this app
    final supported = {'en', 'ar'};

    String effectiveCode;

    if (savedLanguageCode != null && supported.contains(savedLanguageCode)) {
      // Use the explicitly saved preference
      effectiveCode = savedLanguageCode;
    } else {
      // No saved preference — detect device language and use it if supported.
      final deviceCode = ui.PlatformDispatcher.instance.locale.languageCode;
      if (supported.contains(deviceCode)) {
        effectiveCode = deviceCode;
      } else {
        // Fallback to English if device language isn't supported
        effectiveCode = 'en';
      }
    }

    _locale = Locale(effectiveCode);
    notifyListeners();
  }

  /// Clear saved language preference (useful for debugging or reset flows)
  Future<void> clearSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_languageCodeKey);
      _locale = const Locale('en');
      notifyListeners();
    } catch (e) {}
  }

  /// Sets the new locale and saves it to SharedPreferences.
  Future<void> setLocale(Locale newLocale) async {
    if (_locale.languageCode == newLocale.languageCode) return;

    _locale = newLocale;

    // Notify listeners IMMEDIATELY for instant UI update
    notifyListeners();

    // Save the new language preference asynchronously (non-blocking)
    _saveLocaleAsync(newLocale);
  }

  /// Save locale preference asynchronously without blocking UI updates
  void _saveLocaleAsync(Locale locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageCodeKey, locale.languageCode);
    } catch (e) {}
  }
}
