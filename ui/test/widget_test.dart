import 'package:flutter_test/flutter_test.dart';

import 'package:boojy_audio/theme/app_colors.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
  group('ThemeProvider', () {
    test('defaults to dark mode', () {
      final provider = ThemeProvider();
      expect(provider.isDark, isTrue);
    });

    test('setTheme switches mode', () {
      final provider = ThemeProvider();
      expect(provider.isDark, isTrue);
      provider.setTheme(BoojyTheme.light);
      expect(provider.isDark, isFalse);
      expect(provider.isLight, isTrue);
      provider.setTheme(BoojyTheme.dark);
      expect(provider.isDark, isTrue);
    });

    test('colors are non-null', () {
      final provider = ThemeProvider();
      expect(provider.colors, isNotNull);
      expect(provider.colors.standard, isNotNull);
      expect(provider.colors.accent, isNotNull);
    });
  });
}
