import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_localizations.dart';

class LanguageService extends ChangeNotifier {
  static const String _languageKey = 'app_language';
  AppLanguage _language = AppLanguage.ru;

  AppLanguage get language => _language;
  Locale get locale => Locale(_language.name);

  LanguageService() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString(_languageKey);
    if (savedLang != null) {
      _language = savedLang == 'ru' ? AppLanguage.ru : AppLanguage.en;
      notifyListeners();
    } else {
      // Auto-detect on first launch
      await _detectLanguage();
    }
  }

  Future<void> _detectLanguage() async {
    final localeName = Platform.localeName.toLowerCase();
    if (localeName.startsWith('ru')) {
      _language = AppLanguage.ru;
    } else {
      _language = AppLanguage.en;
    }
    await _saveLanguage();
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    await _saveLanguage();
    notifyListeners();
  }

  Future<void> toggleLanguage() async {
    final newLang = _language == AppLanguage.ru ? AppLanguage.en : AppLanguage.ru;
    await setLanguage(newLang);
  }

  Future<void> _saveLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, _language.name);
  }
}
