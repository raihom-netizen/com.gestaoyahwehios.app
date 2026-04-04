import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyDarkMode = 'darkMode';

/// Fornece ThemeMode persistido (SharedPreferences). Use em MaterialApp e no toggle de modo escuro.
class ThemeModeProvider extends ChangeNotifier {
  ThemeModeProvider() {
    _load();
  }

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDarkMode);
    _mode = ThemeMode.light;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == ThemeMode.system) {
      await prefs.remove(_keyDarkMode);
    } else {
      await prefs.setBool(_keyDarkMode, value == ThemeMode.dark);
    }
  }

  void toggleDark() {
    if (_mode == ThemeMode.dark) {
      setMode(ThemeMode.light);
    } else {
      setMode(ThemeMode.dark);
    }
  }
}

/// Fornece acesso ao [ThemeModeProvider] na árvore.
class ThemeModeScope extends InheritedNotifier<ThemeModeProvider> {
  const ThemeModeScope({super.key, required ThemeModeProvider notifier, required super.child});

  static ThemeModeProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeModeScope>()?.notifier;
  }
}
