import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Manages the current theme state for the application.
/// Notifies listeners when the theme changes so widgets can rebuild.
class ThemeProvider extends ChangeNotifier {
  BoojyTheme _currentTheme = BoojyTheme.dark;
  final Map<String, Color> _colorOverrides = {};

  /// The currently active theme
  BoojyTheme get currentTheme => _currentTheme;

  /// Get the color palette for the current theme (with overrides applied)
  BoojyColors get colors =>
      BoojyColors(_currentTheme, overrides: _colorOverrides);

  /// Current color overrides (read-only view)
  Map<String, Color> get colorOverrides => Map.unmodifiable(_colorOverrides);

  /// Set a single color override
  void setColorOverride(String token, Color color) {
    _colorOverrides[token] = color;
    notifyListeners();
  }

  /// Apply a preset palette (bulk override)
  void applyPreset(Map<String, Color> preset) {
    _colorOverrides.clear();
    _colorOverrides.addAll(preset);
    notifyListeners();
  }

  /// Clear all overrides (revert to theme defaults)
  void clearOverrides() {
    _colorOverrides.clear();
    notifyListeners();
  }

  /// Check if any overrides are active
  bool get hasOverrides => _colorOverrides.isNotEmpty;

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
