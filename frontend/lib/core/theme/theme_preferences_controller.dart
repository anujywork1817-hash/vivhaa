import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Named steps rather than a raw double — keeps the Preferences screen's
/// options exhaustive/enum-safe instead of an arbitrary slider value that
/// would need its own persistence-migration story later.
enum AppFontSize {
  small(0.88, 'Small'),
  medium(1.0, 'Default'),
  large(1.15, 'Large'),
  extraLarge(1.3, 'Extra Large');

  final double scale;
  final String label;
  const AppFontSize(this.scale, this.label);
}

class ThemePreferences {
  final ThemeMode themeMode;
  final AppFontSize fontSize;

  const ThemePreferences({
    this.themeMode = ThemeMode.system,
    this.fontSize = AppFontSize.medium,
  });

  ThemePreferences copyWith({ThemeMode? themeMode, AppFontSize? fontSize}) => ThemePreferences(
        themeMode: themeMode ?? this.themeMode,
        fontSize: fontSize ?? this.fontSize,
      );
}

/// Persists the user's theme-mode and font-size choices across app
/// restarts — read once at startup, written on every change.
class ThemePreferencesController extends StateNotifier<ThemePreferences> {
  static const _themeModeKey = 'pref_theme_mode';
  static const _fontSizeKey = 'pref_font_size';

  ThemePreferencesController() : super(const ThemePreferences()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_themeModeKey);
    final fontSizeIndex = prefs.getInt(_fontSizeKey);
    state = ThemePreferences(
      themeMode: themeModeIndex != null && themeModeIndex < ThemeMode.values.length
          ? ThemeMode.values[themeModeIndex]
          : ThemeMode.system,
      fontSize: fontSizeIndex != null && fontSizeIndex < AppFontSize.values.length
          ? AppFontSize.values[fontSizeIndex]
          : AppFontSize.medium,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<void> setFontSize(AppFontSize size) async {
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fontSizeKey, size.index);
  }
}

final themePreferencesProvider =
    StateNotifierProvider<ThemePreferencesController, ThemePreferences>((ref) {
  return ThemePreferencesController();
});
