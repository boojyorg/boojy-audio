import 'package:boojy_audio/utils/track_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackColors palette invariant', () {
    // Defaults may ONLY be colours the user can pick: a default the 16-colour
    // picker can't reproduce reads as a bug (v0.6 dogfood A8).
    test('every categoryColors value is in manualPalette', () {
      for (final entry in TrackColors.categoryColors.entries) {
        expect(
          TrackColors.manualPalette,
          contains(entry.value),
          reason: 'categoryColors[${entry.key}] is not a manualPalette colour',
        );
      }
    });

    test('every legacy palette colour is in manualPalette', () {
      for (final color in TrackColors.palette) {
        expect(
          TrackColors.manualPalette,
          contains(color),
          reason: 'legacy palette colour $color is not in manualPalette',
        );
      }
    });

    test('masterColor is in manualPalette', () {
      expect(TrackColors.manualPalette, contains(TrackColors.masterColor));
    });
  });
}
