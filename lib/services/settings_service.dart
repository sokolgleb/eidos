import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _themeModeKey = 'theme_mode';
  static const _languageKey = 'language';
  static const _defaultViewModeKey = 'default_view_mode';

  /// Returns the saved ThemeMode (defaults to system).
  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey);
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  /// Returns the saved language code (null = system default).
  static Future<String?> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey);
  }

  static Future<void> setLanguage(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_languageKey);
    } else {
      await prefs.setString(_languageKey, code);
    }
  }

  /// Default view mode: true = show original first, false = show annotated.
  static Future<bool> getDefaultShowOriginal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultViewModeKey) ?? false;
  }

  static Future<void> setDefaultShowOriginal(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultViewModeKey, value);
  }
}
