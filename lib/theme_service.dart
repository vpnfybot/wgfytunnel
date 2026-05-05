import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { light, dark }

extension AppThemePreferenceX on AppThemePreference {
  ThemeMode get themeMode {
    switch (this) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemePreference.light:
        return Icons.light_mode;
      case AppThemePreference.dark:
        return Icons.dark_mode;
    }
  }

  AppThemePreference get next {
    return AppThemePreference.values[
      (index + 1) % AppThemePreference.values.length
    ];
  }
}

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';

  AppThemePreference _preference = AppThemePreference.light;

  AppThemePreference get preference => _preference;
  ThemeMode get themeMode => _preference.themeMode;

  AppThemePreference get _defaultPreference {
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark
        ? AppThemePreference.dark
        : AppThemePreference.light;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);
    if (savedTheme == null) {
      _preference = _defaultPreference;
      return;
    }

    _preference = AppThemePreference.values.firstWhere(
      (value) => value.name == savedTheme,
      orElse: () => _defaultPreference,
    );
  }

  Future<void> setPreference(AppThemePreference preference) async {
    if (_preference == preference) {
      return;
    }

    _preference = preference;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, preference.name);
    notifyListeners();
  }
}