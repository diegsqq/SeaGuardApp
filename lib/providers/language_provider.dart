import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale;

  LanguageProvider(this._locale);

  Locale get locale => _locale;

  Future<void> setLanguage(String langCode) async {
    _locale = Locale(langCode);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', langCode);
  }
}