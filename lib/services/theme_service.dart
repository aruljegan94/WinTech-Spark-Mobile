import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeService {
  static const String _boxName = 'app_preferences';
  static const String _keyThemeMode = 'theme_mode';

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get isDark => themeModeNotifier.value == ThemeMode.dark;

  static Future<void> init() async {
    final box = await Hive.openBox(_boxName);
    final savedMode = box.get(_keyThemeMode, defaultValue: 'dark');
    themeModeNotifier.value =
        savedMode == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  static Future<void> toggleTheme() async {
    final newMode = themeModeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setTheme(newMode);
  }

  static Future<void> setTheme(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final box = Hive.box(_boxName);
    await box.put(_keyThemeMode, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}
