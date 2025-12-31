import 'package:flutter/foundation.dart';
import 'app_colors.dart';

/// Manages the current theme state for the application.
/// Notifies listeners when the theme changes so widgets can rebuild.
class ThemeProvider extends ChangeNotifier {
  BoojyTheme _currentTheme = BoojyTheme.dark;

  /// The currently active theme
  BoojyTheme get currentTheme => _currentTheme;

  /// Get the color palette for the current theme
  BoojyColors get colors => BoojyColors(_currentTheme);

  /// Check if current theme is a dark variant
  bool get isDark =>
      _currentTheme == BoojyTheme.dark ||
      _currentTheme == BoojyTheme.highContrastDark;

  /// Check if current theme is a light variant
  bool get isLight =>
      _currentTheme == BoojyTheme.light ||
      _currentTheme == BoojyTheme.highContrastLight;

  /// Check if current theme is high contrast
  bool get isHighContrast =>
      _currentTheme == BoojyTheme.highContrastDark ||
      _currentTheme == BoojyTheme.highContrastLight;

  /// Set the current theme
  void setTheme(BoojyTheme theme) {
    if (_currentTheme != theme) {
      _currentTheme = theme;
      notifyListeners();
    }
  }

  /// Set theme from string key (for persistence)
  void setThemeFromKey(String key) {
    setTheme(BoojyThemeExtension.fromKey(key));
  }

  /// Get the current theme key for persistence
  String get themeKey => _currentTheme.key;

  /// Cycle to the next theme
  void cycleTheme() {
    const values = BoojyTheme.values;
    final currentIndex = values.indexOf(_currentTheme);
    final nextIndex = (currentIndex + 1) % values.length;
    setTheme(values[nextIndex]);
  }
}
