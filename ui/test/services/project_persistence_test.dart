import 'package:boojy_audio/models/project_view_state.dart';
import 'package:boojy_audio/services/project_persistence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UILayoutData', () {
    test('roundtrips all persisted fields through JSON', () {
      const original = UILayoutData(
        libraryWidth: 240,
        mixerWidth: 420,
        bottomHeight: 300,
        libraryCollapsed: true,
        mixerCollapsed: false,
        bottomCollapsed: true,
        viewState: ProjectViewState(
          horizontalScroll: 120,
          verticalScroll: 0,
          zoom: 30,
          libraryVisible: false,
          mixerVisible: true,
          editorVisible: true,
          virtualPianoVisible: false,
          selectedTrackId: 3,
          playheadPosition: 4.5,
        ),
        automationData: {
          'tracks': {
            '1': {'volume': []},
          },
        },
        trackColors: {1: 0xFF112233, 2: 0xFF445566},
        loopEnabled: true,
        loopStartBeats: 0,
        loopEndBeats: 16,
      );

      final restored = UILayoutData.fromJson(original.toJson());

      expect(restored.libraryWidth, 240);
      expect(restored.mixerWidth, 420);
      expect(restored.bottomHeight, 300);
      expect(restored.libraryCollapsed, isTrue);
      expect(restored.mixerCollapsed, isFalse);
      expect(restored.bottomCollapsed, isTrue);
      expect(restored.viewState?.horizontalScroll, 120);
      expect(restored.viewState?.selectedTrackId, 3);
      expect(restored.automationData, isNotNull);
      expect(restored.trackColors, {1: 0xFF112233, 2: 0xFF445566});
      expect(restored.loopEnabled, isTrue);
      expect(restored.loopStartBeats, 0);
      expect(restored.loopEndBeats, 16);
    });
  });

  group('ProjectPersistence.collect', () {
    test('includes track color overrides as ARGB ints', () {
      final layout = ProjectPersistence.collect(
        libraryWidth: 200,
        mixerWidth: 380,
        bottomHeight: 250,
        libraryCollapsed: false,
        mixerCollapsed: false,
        bottomCollapsed: true,
        loopEnabled: false,
        loopStartBeats: 0,
        loopEndBeats: 4,
        trackColorOverrides: {5: const Color(0xFF00BCD4)},
      );

      expect(layout.trackColors, {5: 0xFF00BCD4});
    });

    test('omits empty track color map', () {
      final layout = ProjectPersistence.collect(
        libraryWidth: 200,
        mixerWidth: 380,
        bottomHeight: 250,
        libraryCollapsed: false,
        mixerCollapsed: false,
        bottomCollapsed: true,
        loopEnabled: false,
        loopStartBeats: 0,
        loopEndBeats: 4,
        trackColorOverrides: const {},
      );

      expect(layout.trackColors, isNull);
    });
  });
}
