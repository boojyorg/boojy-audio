import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/controllers/midi_clip_controller.dart';
import 'package:boojy_audio/models/midi_note_data.dart';

void main() {
  group('MidiClipController', () {
    late MidiClipController controller;

    setUp(() {
      controller = MidiClipController();
    });

    tearDown(() {
      controller.dispose();
    });

    group('tempo conversion', () {
      test('default tempo is 120 BPM', () {
        expect(controller.tempo, 120.0);
      });

      test('setTempo updates tempo', () {
        controller.setTempo(140.0);
        expect(controller.tempo, 140.0);
      });

      test('setTempo clamps to minimum 20 BPM', () {
        controller.setTempo(10.0);
        expect(controller.tempo, 20.0);
      });

      test('setTempo clamps to maximum 300 BPM', () {
        controller.setTempo(400.0);
        expect(controller.tempo, 300.0);
      });

      test('secondsToBeats converts correctly at 120 BPM', () {
        controller.setTempo(120.0);
        // At 120 BPM, 1 second = 2 beats
        expect(controller.secondsToBeats(1.0), 2.0);
        expect(controller.secondsToBeats(0.5), 1.0);
        expect(controller.secondsToBeats(2.0), 4.0);
      });

      test('secondsToBeats converts correctly at 60 BPM', () {
        controller.setTempo(60.0);
        // At 60 BPM, 1 second = 1 beat
        expect(controller.secondsToBeats(1.0), 1.0);
        expect(controller.secondsToBeats(2.0), 2.0);
      });

      test('secondsToBeats converts correctly at 180 BPM', () {
        controller.setTempo(180.0);
        // At 180 BPM, 1 second = 3 beats
        expect(controller.secondsToBeats(1.0), 3.0);
        expect(controller.secondsToBeats(2.0), 6.0);
      });

      test('beatsToSeconds converts correctly at 120 BPM', () {
        controller.setTempo(120.0);
        // At 120 BPM, 1 beat = 0.5 seconds
        expect(controller.beatsToSeconds(2.0), 1.0);
        expect(controller.beatsToSeconds(1.0), 0.5);
        expect(controller.beatsToSeconds(4.0), 2.0);
      });

      test('beatsToSeconds converts correctly at 60 BPM', () {
        controller.setTempo(60.0);
        // At 60 BPM, 1 beat = 1 second
        expect(controller.beatsToSeconds(1.0), 1.0);
        expect(controller.beatsToSeconds(2.0), 2.0);
      });

      test('secondsToBeats and beatsToSeconds are inverses', () {
        controller.setTempo(137.5); // Arbitrary tempo
        const originalSeconds = 3.7;
        final beats = controller.secondsToBeats(originalSeconds);
        final backToSeconds = controller.beatsToSeconds(beats);
        expect(backToSeconds, closeTo(originalSeconds, 0.0001));
      });
    });

    group('clipboard operations', () {
      test('clipboard is initially null', () {
        expect(controller.clipboardClip, isNull);
      });

      test('copyToClipboard stores clip', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 1,
          startTime: 0.0,
          duration: 4.0,
          name: 'Test Clip',
        );

        controller.copyToClipboard(clip);

        expect(controller.clipboardClip, isNotNull);
        expect(controller.clipboardClip!.clipId, 1);
        expect(controller.clipboardClip!.name, 'Test Clip');
      });

      test('clearClipboard removes clip', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 1,
          startTime: 0.0,
          duration: 4.0,
          name: 'Test Clip',
        );

        controller.copyToClipboard(clip);
        expect(controller.clipboardClip, isNotNull);

        controller.clearClipboard();
        expect(controller.clipboardClip, isNull);
      });

      test('clear removes clipboard', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 1,
          startTime: 0.0,
          duration: 4.0,
          name: 'Test Clip',
        );

        controller.copyToClipboard(clip);
        controller.clear();

        expect(controller.clipboardClip, isNull);
      });
    });

    group('clip creation', () {
      test('createDefaultClip creates clip with correct defaults', () {
        final clip = controller.createDefaultClip(trackId: 5);

        expect(clip.trackId, 5);
        expect(clip.startTime, 0.0);
        expect(clip.duration, 4.0);
        expect(clip.loopLength, 4.0);
        expect(clip.name, 'New MIDI Clip');
        expect(clip.notes, isEmpty);
        expect(clip.clipId, isPositive);
      });

      test('createDefaultClip respects custom parameters', () {
        final clip = controller.createDefaultClip(
          trackId: 3,
          startTimeBeats: 8.0,
          durationBeats: 16.0,
          name: 'Custom Clip',
        );

        expect(clip.trackId, 3);
        expect(clip.startTime, 8.0);
        expect(clip.duration, 16.0);
        expect(clip.loopLength, 16.0);
        expect(clip.name, 'Custom Clip');
      });

      test('createClipWithParams creates clip with all parameters', () {
        final notes = [
          MidiNoteData(note: 60, velocity: 100, startTime: 0.0, duration: 1.0),
          MidiNoteData(note: 64, velocity: 80, startTime: 1.0, duration: 1.0),
        ];

        final clip = controller.createClipWithParams(
          trackId: 2,
          startTimeBeats: 4.0,
          durationBeats: 8.0,
          loopLengthBeats: 4.0,
          name: 'Detailed Clip',
          notes: notes,
        );

        expect(clip.trackId, 2);
        expect(clip.startTime, 4.0);
        expect(clip.duration, 8.0);
        expect(clip.loopLength, 4.0);
        expect(clip.name, 'Detailed Clip');
        expect(clip.notes.length, 2);
      });

      test('createClipWithParams uses duration as loopLength when not specified', () {
        final clip = controller.createClipWithParams(
          trackId: 1,
          startTimeBeats: 0.0,
          durationBeats: 8.0,
        );

        expect(clip.loopLength, 8.0);
      });

      test('each created clip has unique ID when created with delay', () async {
        final clip1 = controller.createDefaultClip(trackId: 1);
        await Future.delayed(const Duration(milliseconds: 2));
        final clip2 = controller.createDefaultClip(trackId: 1);
        await Future.delayed(const Duration(milliseconds: 2));
        final clip3 = controller.createDefaultClip(trackId: 1);

        final ids = {clip1.clipId, clip2.clipId, clip3.clipId};
        // All IDs should be unique (set size equals list size)
        expect(ids.length, 3);
      });
    });

    group('getters without initialization', () {
      test('selectedClipId returns null when not initialized', () {
        expect(controller.selectedClipId, isNull);
      });

      test('currentEditingClip returns null when not initialized', () {
        expect(controller.currentEditingClip, isNull);
      });

      test('midiClips returns empty list when not initialized', () {
        expect(controller.midiClips, isEmpty);
      });
    });

    group('notifyListeners', () {
      test('copyToClipboard notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.copyToClipboard(MidiClipData(
          clipId: 1,
          trackId: 1,
          startTime: 0.0,
          duration: 4.0,
          name: 'Test',
        ));

        expect(notified, isTrue);
      });

      test('clearClipboard notifies listeners', () {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.copyToClipboard(MidiClipData(
          clipId: 1,
          trackId: 1,
          startTime: 0.0,
          duration: 4.0,
          name: 'Test',
        ));
        controller.clearClipboard();

        expect(notifyCount, 2);
      });

      test('clear notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.clear();

        expect(notified, isTrue);
      });
    });
  });

  group('MidiClipData', () {
    test('endTime is calculated correctly', () {
      final clip = MidiClipData(
        clipId: 1,
        trackId: 1,
        startTime: 4.0,
        duration: 8.0,
        name: 'Test',
      );

      expect(clip.endTime, 12.0);
    });

    test('copyWith preserves unchanged values', () {
      final original = MidiClipData(
        clipId: 100,
        trackId: 5,
        startTime: 8.0,
        duration: 16.0,
        loopLength: 4.0,
        name: 'Original',
        notes: [
          MidiNoteData(note: 60, velocity: 100, startTime: 0.0, duration: 1.0),
        ],
      );

      final copied = original.copyWith(name: 'Copied');

      expect(copied.clipId, 100);
      expect(copied.trackId, 5);
      expect(copied.startTime, 8.0);
      expect(copied.duration, 16.0);
      expect(copied.loopLength, 4.0);
      expect(copied.name, 'Copied');
      expect(copied.notes.length, 1);
    });

    test('copyWith can change multiple fields', () {
      final original = MidiClipData(
        clipId: 1,
        trackId: 1,
        startTime: 0.0,
        duration: 4.0,
        name: 'Original',
      );

      final copied = original.copyWith(
        clipId: 2,
        startTime: 8.0,
        duration: 16.0,
        name: 'Modified',
      );

      expect(copied.clipId, 2);
      expect(copied.trackId, 1); // unchanged
      expect(copied.startTime, 8.0);
      expect(copied.duration, 16.0);
      expect(copied.name, 'Modified');
    });
  });
}
