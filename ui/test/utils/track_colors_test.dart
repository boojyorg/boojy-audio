import 'package:boojy_audio/utils/track_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackColors palette invariant', () {
    // Defaults may ONLY be colours the user can pick: a default the 16-colour
    // picker can't reproduce reads as a bug (v0.6 dogfood A8).
    test('the add-track type colours are in manualPalette', () {
      expect(TrackColors.manualPalette, contains(TrackColors.midiTypeColor));
      expect(TrackColors.manualPalette, contains(TrackColors.audioTypeColor));
    });

    test('every palette colour is in manualPalette', () {
      for (final color in TrackColors.palette) {
        expect(
          TrackColors.manualPalette,
          contains(color),
          reason: 'palette colour $color is not in manualPalette',
        );
      }
    });

    test('masterColor is in manualPalette', () {
      expect(TrackColors.manualPalette, contains(TrackColors.masterColor));
    });
  });
}
