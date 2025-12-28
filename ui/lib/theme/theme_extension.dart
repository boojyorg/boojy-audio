import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_colors.dart';
import 'theme_provider.dart';

/// Extension on BuildContext for easy access to theme colors.
/// Usage: context.colors.accent, context.colors.textPrimary, etc.
extension ThemeContextExtension on BuildContext {
  /// Get the current color palette from the ThemeProvider
  BoojyColors get colors => Provider.of<ThemeProvider>(this, listen: true).colors;

  /// Get the ThemeProvider for theme switching
  ThemeProvider get themeProvider => Provider.of<ThemeProvider>(this, listen: false);

  /// Check if the current theme is dark
  bool get isDarkTheme => Provider.of<ThemeProvider>(this, listen: true).isDark;

  /// Check if the current theme is light
  bool get isLightTheme => Provider.of<ThemeProvider>(this, listen: true).isLight;
}
