import 'package:flutter/material.dart';

/// Available themes for Boojy Audio
enum BoojyTheme {
  dark,
  highContrastDark,
  light,
  highContrastLight,
}

/// Extension to get display names for themes
extension BoojyThemeExtension on BoojyTheme {
  String get displayName {
    switch (this) {
      case BoojyTheme.dark:
        return 'Dark';
      case BoojyTheme.highContrastDark:
        return 'High Contrast Dark';
      case BoojyTheme.light:
        return 'Light';
      case BoojyTheme.highContrastLight:
        return 'High Contrast Light';
    }
  }

  String get key {
    switch (this) {
      case BoojyTheme.dark:
        return 'dark';
      case BoojyTheme.highContrastDark:
        return 'highContrastDark';
      case BoojyTheme.light:
        return 'light';
      case BoojyTheme.highContrastLight:
        return 'highContrastLight';
    }
  }

  static BoojyTheme fromKey(String key) {
    switch (key) {
      case 'dark':
        return BoojyTheme.dark;
      case 'highContrastDark':
        return BoojyTheme.highContrastDark;
      case 'light':
        return BoojyTheme.light;
      case 'highContrastLight':
        return BoojyTheme.highContrastLight;
      default:
        return BoojyTheme.dark;
    }
  }
}

/// Centralized color definitions for Boojy Audio
/// All UI colors should be accessed through this class via the ThemeProvider
class BoojyColors {
  final BoojyTheme theme;

  const BoojyColors(this.theme);

  // ============================================
  // BACKGROUND COLORS
  // ============================================

  /// Deepest background color (e.g., main app background)
  Color get darkest => _getBackgroundColor('darkest');

  /// Dark background (main panel backgrounds)
  Color get dark => _getBackgroundColor('dark');

  /// Standard background (panel backgrounds)
  Color get standard => _getBackgroundColor('standard');

  /// Elevated surfaces (cards, floating panels)
  Color get elevated => _getBackgroundColor('elevated');

  /// Interactive surface background
  Color get surface => _getBackgroundColor('surface');

  /// Borders and separators
  Color get divider => _getBackgroundColor('divider');

  /// Hover state background
  Color get hover => _getBackgroundColor('hover');

  // ============================================
  // TEXT COLORS
  // ============================================

  /// Primary text color
  Color get textPrimary => _getTextColor('primary');

  /// Secondary text color
  Color get textSecondary => _getTextColor('secondary');

  /// Muted/disabled text color
  Color get textMuted => _getTextColor('muted');

  // ============================================
  // ACCENT COLORS
  // ============================================

  /// Primary accent color (Boojy Blue)
  Color get accent => _getAccentColor('primary');

  /// Accent hover state
  Color get accentHover => _getAccentColor('hover');

  // ============================================
  // SEMANTIC COLORS (Theme-independent)
  // ============================================

  /// Success/positive indicator (green)
  Color get success => const Color(0xFF4CAF50);

  /// Warning indicator (yellow/amber)
  Color get warning => const Color(0xFFFFC107);

  /// Error/destructive indicator (red)
  Color get error => const Color(0xFFFF5722);

  // ============================================
  // COMPONENT-SPECIFIC COLORS
  // ============================================

  /// Level meter green (low levels)
  Color get meterGreen => const Color(0xFF4CAF50);

  /// Level meter yellow (mid levels)
  Color get meterYellow => const Color(0xFFFFC107);

  /// Level meter red (high/clipping levels)
  Color get meterRed => const Color(0xFFFF5722);

  /// Solo button active state - Blue
  Color get soloActive => const Color(0xFF3B82F6);

  /// Mute button active state - Yellow/Amber
  Color get muteActive => const Color(0xFFFACC15);

  /// Record button active state - Red
  Color get recordActive => const Color(0xFFEF4444);

  /// Inactive button background
  Color get buttonInactive => const Color(0xFF909090);

  /// Piano white key
  Color get pianoWhiteKey => const Color(0xFFF5F5F5);

  /// Piano black key
  Color get pianoBlackKey => const Color(0xFF2A2A2A);

  /// Playhead color
  Color get playhead => const Color(0xFFFF5252);

  /// Selection highlight
  Color get selection => accent.withValues(alpha: 0.3);

  /// Grid lines
  Color get gridLine => divider.withValues(alpha: 0.5);

  /// Waveform color
  Color get waveform => accent;

  // ============================================
  // PRIVATE HELPER METHODS
  // ============================================

  Color _getBackgroundColor(String token) {
    switch (theme) {
      case BoojyTheme.dark:
        return _darkBackgrounds[token]!;
      case BoojyTheme.highContrastDark:
        return _highContrastDarkBackgrounds[token]!;
      case BoojyTheme.light:
        return _lightBackgrounds[token]!;
      case BoojyTheme.highContrastLight:
        return _highContrastLightBackgrounds[token]!;
    }
  }

  Color _getTextColor(String token) {
    switch (theme) {
      case BoojyTheme.dark:
        return _darkText[token]!;
      case BoojyTheme.highContrastDark:
        return _highContrastDarkText[token]!;
      case BoojyTheme.light:
        return _lightText[token]!;
      case BoojyTheme.highContrastLight:
        return _highContrastLightText[token]!;
    }
  }

  Color _getAccentColor(String token) {
    switch (theme) {
      case BoojyTheme.dark:
      case BoojyTheme.highContrastDark:
        return _darkAccent[token]!;
      case BoojyTheme.light:
        return _lightAccent[token]!;
      case BoojyTheme.highContrastLight:
        return _highContrastLightAccent[token]!;
    }
  }

  // ============================================
  // THEME COLOR PALETTES
  // ============================================

  // --- DARK THEME ---
  static const Map<String, Color> _darkBackgrounds = {
    'darkest': Color(0xFF1A1A1A),
    'dark': Color(0xFF222222),
    'standard': Color(0xFF2A2A2A),
    'elevated': Color(0xFF333333),
    'surface': Color(0xFF3B3B3B),
    'divider': Color(0xFF444444),
    'hover': Color(0xFF505050),
  };

  static const Map<String, Color> _darkText = {
    'primary': Color(0xFFEBEBEB),
    'secondary': Color(0xFFA0A0A0),
    'muted': Color(0xFF707070),
  };

  static const Map<String, Color> _darkAccent = {
    'primary': Color(0xFF38BDF8), // Boojy Blue
    'hover': Color(0xFF5CCBFA),
  };

  // --- HIGH CONTRAST DARK THEME ---
  static const Map<String, Color> _highContrastDarkBackgrounds = {
    'darkest': Color(0xFF000000),
    'dark': Color(0xFF0A0A0A),
    'standard': Color(0xFF141414),
    'elevated': Color(0xFF1E1E1E),
    'surface': Color(0xFF282828),
    'divider': Color(0xFF3C3C3C),
    'hover': Color(0xFF4A4A4A),
  };

  static const Map<String, Color> _highContrastDarkText = {
    'primary': Color(0xFFFFFFFF),
    'secondary': Color(0xFFC0C0C0),
    'muted': Color(0xFF808080),
  };

  // --- LIGHT THEME ---
  static const Map<String, Color> _lightBackgrounds = {
    'darkest': Color(0xFFFFFFFF),
    'dark': Color(0xFFF5F5F5),
    'standard': Color(0xFFEBEBEB),
    'elevated': Color(0xFFE0E0E0),
    'surface': Color(0xFFD5D5D5),
    'divider': Color(0xFFC0C0C0),
    'hover': Color(0xFFB0B0B0),
  };

  static const Map<String, Color> _lightText = {
    'primary': Color(0xFF1A1A1A),
    'secondary': Color(0xFF4A4A4A),
    'muted': Color(0xFF707070),
  };

  static const Map<String, Color> _lightAccent = {
    'primary': Color(0xFF0284C7),
    'hover': Color(0xFF0369A1),
  };

  // --- HIGH CONTRAST LIGHT THEME ---
  static const Map<String, Color> _highContrastLightBackgrounds = {
    'darkest': Color(0xFFFFFFFF),
    'dark': Color(0xFFFAFAFA),
    'standard': Color(0xFFF0F0F0),
    'elevated': Color(0xFFE5E5E5),
    'surface': Color(0xFFDADADA),
    'divider': Color(0xFFB0B0B0),
    'hover': Color(0xFF9A9A9A),
  };

  static const Map<String, Color> _highContrastLightText = {
    'primary': Color(0xFF000000),
    'secondary': Color(0xFF2A2A2A),
    'muted': Color(0xFF505050),
  };

  static const Map<String, Color> _highContrastLightAccent = {
    'primary': Color(0xFF0369A1),
    'hover': Color(0xFF075985),
  };
}
