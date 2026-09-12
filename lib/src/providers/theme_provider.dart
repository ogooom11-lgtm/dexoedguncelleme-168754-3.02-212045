import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إدارة وضع الثيم (فاتح / داكن / حسب النظام) مع حفظ الاختيار محلياً.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode_v1';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// تحميل سريع جداً (SharedPreferences محلي فقط).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_key)) {
        case 'dark':
          _mode = ThemeMode.dark;
          break;
        case 'light':
          _mode = ThemeMode.light;
          break;
        default:
          _mode = ThemeMode.system;
      }
      notifyListeners();
    } catch (_) {
      // نتجاهل أي خطأ في التخزين المحلي
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  /// تبديل بين الفاتح والداكن.
  void toggle() {
    setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
