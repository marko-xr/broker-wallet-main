// lib/src/viewmodels/theme_viewmodel.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeViewModel extends ChangeNotifier {
  // Key for storing the theme preference
  static const String _themeKey = 'themeMode';

  // Default to light mode
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  ThemeViewModel() {
    // Load the saved theme when the ViewModel is created
    _loadTheme();
  }

  /// Loads the saved theme from SharedPreferences.
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    // Read the saved theme string, default to 'light' if not found
    final savedTheme = prefs.getString(_themeKey) ?? 'light';

    // Convert the string back to a ThemeMode enum
    _themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Sets the new theme mode and saves it to SharedPreferences.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return; // No change needed

    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    // Save the theme as a string ('light' or 'dark')
    await prefs.setString(_themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  /// Toggles the theme between light and dark.
  void toggleTheme() {
    setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
