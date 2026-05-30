import 'package:boojy_audio/models/midi_note_data.dart';
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

    test('roundtrips time signature through JSON', () {
      const original = UILayoutData(
        timeSignatureNumerator: 6,
        timeSignatureDenominator: 8,
      );

      final restored = UILayoutData.fromJson(original.toJson());

      expect(restored.timeSignatureNumerator, 6);
      expect(restored.timeSignatureDenominator, 8);
    });

    test('roundtrips MIDI clip UI metadata (not notes) through JSON', () {
      final clip = MidiClipData(
        clipId: 99, // not authoritative — engine owns ids
        trackId: 4,
        startTime: 8.0,
        duration: 16.0,
        loopLength: 8.0,
        name: 'Bassline',
        color: const Color(0xFF8E24AA),
        isMuted: true,
        canRepeat: false,
        contentStartOffset: 2.0,
        patternId: 'pattern-7',
        notes: [
          MidiNoteData(note: 36, velocity: 100, startTime: 0, duration: 1),
        ],
      );

      final layout = UILayoutData(midiClips: [clip]);
      final restored = UILayoutData.fromJson(layout.toJson());

      expect(restored.midiClips, isNotNull);
      expect(restored.midiClips!.length, 1);
      final m = restored.midiClips!.first;
      expect(m.trackId, 4);
      expect(m.startTime, 8.0);
      expect(m.name, 'Bassline');
      expect(m.color?.toARGB32(), 0xFF8E24AA);
      expect(m.isMuted, isTrue);
      expect(m.canRepeat, isFalse);
      expect(m.contentStartOffset, 2.0);
      expect(m.patternId, 'pattern-7');
      expect(m.loopLength, 8.0);
      // Notes are engine-owned and intentionally NOT persisted in ui_layout.
      expect(m.notes, isEmpty);
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
