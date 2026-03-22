import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/theme/app_colors.dart';

void main() {
  group('BoojyColors', () {
    // -------------------------------------------------------
    // 1. All 4 themes have all color tokens defined
    // -------------------------------------------------------
    for (final theme in BoojyTheme.values) {
      test('${theme.displayName} theme exposes all color tokens without throwing', () {
        final colors = BoojyColors(theme);

        // Background tokens
        expect(colors.editor, isA<Color>());
        expect(colors.darkest, isA<Color>());
        expect(colors.dark, isA<Color>());
        expect(colors.standard, isA<Color>());
        expect(colors.elevated, isA<Color>());
        expect(colors.surface, isA<Color>());
        expect(colors.divider, isA<Color>());
        expect(colors.hover, isA<Color>());

        // Text tokens
        expect(colors.textPrimary, isA<Color>());
        expect(colors.textSecondary, isA<Color>());
        expect(colors.textMuted, isA<Color>());

        // Accent tokens
        expect(colors.accent, isA<Color>());
        expect(colors.accentHover, isA<Color>());
      });
    }

    // -------------------------------------------------------
    // 2. Dark theme specific hex values
    // -------------------------------------------------------
    test('dark theme has expected specific color values', () {
      final colors = BoojyColors(BoojyTheme.dark);

      expect(colors.editor, const Color(0xFF040412));
      expect(colors.dark, const Color(0xFF2C2C32));
      expect(colors.darkest, const Color(0xFF13151C));
      expect(colors.textPrimary, const Color(0xFFE8EAF0));
      expect(colors.accent, const Color(0xFF40B3E8));
    });

    // -------------------------------------------------------
    // 3. Semantic colors are theme-independent
    // -------------------------------------------------------
    test('semantic colors are identical across all themes', () {
      final allColors = BoojyTheme.values.map((t) => BoojyColors(t)).toList();

      for (final colors in allColors) {
        expect(colors.success, const Color(0xFF4CAF50));
        expect(colors.warning, const Color(0xFFFFC107));
        expect(colors.error, const Color(0xFFFF5722));
      }
    });

    // -------------------------------------------------------
    // 4. Background color overrides work
    // -------------------------------------------------------
    test('overrides map replaces background defaults', () {
      const overrideColor = Color(0xFFABCDEF);
      final colors = BoojyColors(
        BoojyTheme.dark,
        overrides: {'editor': overrideColor},
      );

      expect(colors.editor, overrideColor);
      // Non-overridden tokens still return defaults
      expect(colors.dark, const Color(0xFF2C2C32));
    });

    // -------------------------------------------------------
    // 5. Text overrides use text_ prefix
    // -------------------------------------------------------
    test('text overrides use text_ prefix', () {
      const overrideColor = Color(0xFF112233);
      final colors = BoojyColors(
        BoojyTheme.dark,
        overrides: {'text_primary': overrideColor},
      );

      expect(colors.textPrimary, overrideColor);
      // Other text tokens unaffected
      expect(colors.textSecondary, const Color(0xFF9B9EB0));
    });

    // -------------------------------------------------------
    // 6. Accent overrides use accent_ prefix
    // -------------------------------------------------------
    test('accent overrides use accent_ prefix', () {
      const overrideColor = Color(0xFF445566);
      final colors = BoojyColors(
        BoojyTheme.dark,
        overrides: {'accent_primary': overrideColor},
      );

      expect(colors.accent, overrideColor);
      // Hover accent unaffected
      expect(colors.accentHover, const Color(0xFF5CC3F0));
    });
  });
}
