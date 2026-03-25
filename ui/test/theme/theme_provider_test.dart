import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/theme/app_colors.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
  group('ThemeProvider', () {
    late ThemeProvider provider;

    setUp(() {
      provider = ThemeProvider();
    });

    test('defaults to dark theme', () {
      expect(provider.currentTheme, equals(BoojyTheme.dark));
      expect(provider.isDark, isTrue);
      expect(provider.isLight, isFalse);
    });

    test('setTheme changes theme', () {
      provider.setTheme(BoojyTheme.light);
      expect(provider.currentTheme, equals(BoojyTheme.light));
      expect(provider.isLight, isTrue);
    });

    test('setTheme notifies listeners', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.setTheme(BoojyTheme.light);
      expect(notified, isTrue);
    });

    test('setTheme does not notify if same theme', () {
      var count = 0;
      provider.addListener(() => count++);
      provider.setTheme(BoojyTheme.dark); // same as default
      expect(count, equals(0));
    });

    test('cycleTheme cycles through all themes', () {
      expect(provider.currentTheme, equals(BoojyTheme.dark));
      provider.cycleTheme();
      expect(provider.currentTheme, equals(BoojyTheme.highContrastDark));
      provider.cycleTheme();
      expect(provider.currentTheme, equals(BoojyTheme.light));
      provider.cycleTheme();
      expect(provider.currentTheme, equals(BoojyTheme.highContrastLight));
      provider.cycleTheme();
      expect(provider.currentTheme, equals(BoojyTheme.dark)); // wraps
    });

    test('themeKey returns correct key', () {
      expect(provider.themeKey, equals('dark'));
      provider.setTheme(BoojyTheme.light);
      expect(provider.themeKey, equals('light'));
    });

    test('setThemeFromKey restores theme', () {
      provider.setThemeFromKey('highContrastDark');
      expect(provider.currentTheme, equals(BoojyTheme.highContrastDark));
    });
  });

  group('ThemeProvider color overrides', () {
    late ThemeProvider provider;

    setUp(() {
      provider = ThemeProvider();
    });

    test('hasOverrides is false by default', () {
      expect(provider.hasOverrides, isFalse);
    });

    test('setColorOverride adds override', () {
      provider.setColorOverride('dark', const Color(0xFF111111));
      expect(provider.hasOverrides, isTrue);
      expect(provider.colorOverrides['dark'], equals(const Color(0xFF111111)));
    });

    test('setColorOverride notifies listeners', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.setColorOverride('dark', const Color(0xFF111111));
      expect(notified, isTrue);
    });

    test('override is applied to colors', () {
      final defaultDark = provider.colors.dark;
      const override = Color(0xFF111111);
      provider.setColorOverride('dark', override);
      expect(provider.colors.dark, equals(override));
      expect(provider.colors.dark, isNot(equals(defaultDark)));
    });

    test('clearOverrides removes all overrides', () {
      provider.setColorOverride('dark', const Color(0xFF111111));
      provider.setColorOverride('editor', const Color(0xFF222222));
      expect(provider.hasOverrides, isTrue);
      provider.clearOverrides();
      expect(provider.hasOverrides, isFalse);
    });

    test('applyPreset replaces all overrides', () {
      provider.setColorOverride('dark', const Color(0xFF111111));
      provider.applyPreset({
        'editor': const Color(0xFF333333),
        'surface': const Color(0xFF444444),
      });
      expect(provider.colorOverrides.containsKey('dark'), isFalse);
      expect(
        provider.colorOverrides['editor'],
        equals(const Color(0xFF333333)),
      );
      expect(
        provider.colorOverrides['surface'],
        equals(const Color(0xFF444444)),
      );
    });

    test('text override uses text_ prefix', () {
      provider.setColorOverride('text_primary', const Color(0xFFFFFFFF));
      expect(provider.colors.textPrimary, equals(const Color(0xFFFFFFFF)));
    });

    test('accent override uses accent_ prefix', () {
      provider.setColorOverride('accent_primary', const Color(0xFFFF0000));
      expect(provider.colors.accent, equals(const Color(0xFFFF0000)));
    });

    test('non-overridden colors use theme defaults', () {
      provider.setColorOverride('dark', const Color(0xFF111111));
      // editor should still be the default
      const defaultColors = BoojyColors(BoojyTheme.dark);
      expect(provider.colors.editor, equals(defaultColors.editor));
    });
  });
}
