import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class AppLocalizations {
  final Locale locale;
  late Map<String, String> _localizedStrings;

  // Static cache for all languages - preloaded at app startup
  static final Map<String, Map<String, String>> _cachedStrings = {};
  static bool _isInitialized = false;

  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  // Preload all supported languages at app startup
  static Future<void> preloadAllLanguages({
    Duration warnAfter = const Duration(seconds: 3),
  }) async {
    if (_isInitialized) return;

    final supportedLanguages = ['en', 'ar'];
    final stopwatch = Stopwatch()..start();

    final preloadFutures = supportedLanguages.map((languageCode) async {
      try {
        final jsonString = await rootBundle
            .loadString('lib/src/common/localization/app_$languageCode.arb');
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        _cachedStrings[languageCode] =
            jsonMap.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        // Set empty map to prevent crashes
        _cachedStrings[languageCode] = {};
      }
    });

    await Future.wait(preloadFutures);

    stopwatch.stop();
    if (stopwatch.elapsed > warnAfter) {}

    _isInitialized = true;
  }

  // Getter for testing - to check if languages are preloaded
  static bool get isInitialized => _isInitialized;

  // Getter for testing - to check cached languages count
  static int get cachedLanguagesCount => _cachedStrings.length;

  Future<bool> load() async {
    // If cache is available, use it immediately (synchronous)
    if (_cachedStrings.containsKey(locale.languageCode)) {
      _localizedStrings = _cachedStrings[locale.languageCode]!;
      return true;
    }

    // Fallback: Load async if cache not ready yet (during app startup)
    // This ensures app doesn't crash if preloading hasn't finished
    try {
      String jsonString = await rootBundle.loadString(
          'lib/src/common/localization/app_${locale.languageCode}.arb');
      Map<String, dynamic> jsonMap = json.decode(jsonString);
      _localizedStrings =
          jsonMap.map((key, value) => MapEntry(key, value.toString()));

      // Cache it for next time
      _cachedStrings[locale.languageCode] = _localizedStrings;
      return true;
    } catch (e) {
      // Set empty map to prevent crashes
      _localizedStrings = {};
      return false;
    }
  }

  String translate(String key) {
    // Return the localized value for the current locale if present.
    if (_localizedStrings.containsKey(key)) return _localizedStrings[key]!;

    // Fallback: prefer English if the current locale doesn't contain the key.
    final en = _cachedStrings['en'];
    if (en != null && en.containsKey(key)) return en[key]!;

    // Last-resort: try any cached language that contains the key.
    for (final map in _cachedStrings.values) {
      if (map.containsKey(key)) return map[key]!;
    }

    return '** $key not found';
  }

  // Convenience typed getters make call sites simpler and avoid repeated
  // string literals. Add commonly used keys here.
  String get appName => translate('appName');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localization = AppLocalizations(locale);
    await localization.load();
    return localization;
  }

  @override
  bool shouldReload(LocalizationsDelegate<AppLocalizations> old) =>
      true; // Changed to true for instant switching
}
