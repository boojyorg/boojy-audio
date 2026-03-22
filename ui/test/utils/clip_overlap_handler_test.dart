import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/utils/clip_overlap_handler.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';

// Helper to create audio clips
ClipData _audioClip({
  int clipId = 1,
  int trackId = 0,
  double startTime = 0,
  double duration = 4,
}) {
  return ClipData(
    clipId: clipId,
    trackId: trackId,
    filePath: 'test.wav',
    startTime: startTime,
    duration: duration,
    waveformPeaks: const [],
  );
}

// Helper to create MIDI clips
MidiClipData _midiClip({
  int clipId = 1,
  int trackId = 0,
  double startTime = 0,
  double duration = 4,
  String name = 'Test',
}) {
  return MidiClipData(
    clipId: clipId,
    trackId: trackId,
    startTime: startTime,
    duration: duration,
    notes: const [],
    name: name,
  );
}

void main() {
  group('ClipOverlapHandler.resolveAudioOverlaps', () {
    test('no overlaps returns empty result', () {
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 10,
        newEnd: 14,
        existingClips: [_audioClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.hasChanges, isFalse);
    });

    test('ignores clips on different tracks', () {
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 0,
        newEnd: 4,
        existingClips: [_audioClip(trackId: 1, startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.hasChanges, isFalse);
    });

    test('excludes specified clip', () {
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 0,
        newEnd: 4,
        existingClips: [_audioClip(clipId: 5, startTime: 0, duration: 4)],
        trackId: 0,
        excludeClipId: 5,
      );
      expect(result.hasChanges, isFalse);
    });

    test('Case 1: complete cover — deletes existing', () {
      // New clip (0-8) completely covers existing (2-6)
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 0,
        newEnd: 8,
        existingClips: [_audioClip(startTime: 2, duration: 4)],
        trackId: 0,
      );
      expect(result.removals.length, equals(1));
      expect(result.removals.first.startTime, equals(2));
    });

    test('Case 2: overlaps end — trims existing', () {
      // Existing (0-4), new starts at 2 → trim existing to (0-2)
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 2,
        newEnd: 6,
        existingClips: [_audioClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.updates.length, equals(1));
      expect(result.updates.first.updated.duration, equals(2));
    });

    test('Case 2: overlaps end — deletes if trimmed too small', () {
      // Existing (0-4), new starts at 0.1 → trimmed to 0.1s < minClipSize
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 0.1,
        newEnd: 6,
        existingClips: [_audioClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.removals.length, equals(1));
    });

    test('Case 3: overlaps start — trims existing start', () {
      // Existing (0-4), new ends at 2 → existing becomes (2-4)
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: -2,
        newEnd: 2,
        existingClips: [_audioClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.updates.length, equals(1));
      expect(result.updates.first.updated.startTime, equals(2));
      expect(result.updates.first.updated.duration, equals(2));
    });

    test('Case 4: inside existing — splits into two', () {
      // Existing (0-10), new (3-7) → partA(0-3) + partB(7-10)
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 3,
        newEnd: 7,
        existingClips: [_audioClip(startTime: 0, duration: 10)],
        trackId: 0,
      );
      expect(result.splits.length, equals(1));
      final split = result.splits.first;
      expect(split.partA, isNotNull);
      expect(split.partA!.duration, closeTo(3, 0.01));
      expect(split.partBTemplate, isNotNull);
      expect(split.partBTemplate!.startTime, closeTo(7, 0.01));
      expect(split.partBTemplate!.duration, closeTo(3, 0.01));
    });

    test('handles multiple overlapping clips', () {
      final result = ClipOverlapHandler.resolveAudioOverlaps(
        newStart: 0,
        newEnd: 20,
        existingClips: [
          _audioClip(clipId: 1, startTime: 2, duration: 4),
          _audioClip(clipId: 2, startTime: 8, duration: 4),
          _audioClip(clipId: 3, startTime: 14, duration: 4),
        ],
        trackId: 0,
      );
      // All 3 clips are completely covered
      expect(result.removals.length, equals(3));
    });
  });

  group('ClipOverlapHandler.resolveMidiOverlaps', () {
    test('no overlaps returns empty result', () {
      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: 10,
        newEnd: 14,
        existingClips: [_midiClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.hasChanges, isFalse);
    });

    test('Case 1: complete cover — deletes existing', () {
      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: 0,
        newEnd: 8,
        existingClips: [_midiClip(startTime: 2, duration: 4)],
        trackId: 0,
      );
      expect(result.removals.length, equals(1));
    });

    test('Case 2: overlaps end — trims existing', () {
      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: 2,
        newEnd: 6,
        existingClips: [_midiClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.updates.length, equals(1));
      expect(result.updates.first.updated.duration, equals(2));
    });

    test('Case 3: overlaps start — trims existing start', () {
      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: -2,
        newEnd: 2,
        existingClips: [_midiClip(startTime: 0, duration: 4)],
        trackId: 0,
      );
      expect(result.updates.length, equals(1));
      expect(result.updates.first.updated.startTime, equals(2));
    });

    test('Case 4: inside existing — splits into two', () {
      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: 3,
        newEnd: 7,
        existingClips: [_midiClip(startTime: 0, duration: 10)],
        trackId: 0,
      );
      expect(result.splits.length, equals(1));
      expect(result.splits.first.partA, isNotNull);
      expect(result.splits.first.partB, isNotNull);
    });

    test('MIDI split creates two parts with correct times', () {
      final clip = MidiClipData(
        clipId: 1,
        trackId: 0,
        startTime: 0,
        duration: 10,
        notes: [
          MidiNoteData(startTime: 1, duration: 1, note: 60, velocity: 100),
          MidiNoteData(startTime: 5, duration: 1, note: 64, velocity: 100),
          MidiNoteData(startTime: 8, duration: 1, note: 67, velocity: 100),
        ],
        name: 'Test',
      );

      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: 3,
        newEnd: 7,
        existingClips: [clip],
        trackId: 0,
      );

      expect(result.splits.length, equals(1));
      final split = result.splits.first;
      // PartA covers beat 0-3
      expect(split.partA, isNotNull);
      expect(split.partA!.duration, closeTo(3, 0.01));
      expect(split.partA!.name, equals('Test (L)'));
      // PartB covers beat 7-10
      expect(split.partB, isNotNull);
      expect(split.partB!.startTime, closeTo(7, 0.01));
      expect(split.partB!.duration, closeTo(3, 0.01));
      expect(split.partB!.name, equals('Test (R)'));
    });

    test('ignores clips on different tracks', () {
      final result = ClipOverlapHandler.resolveMidiOverlaps(
        newStart: 0,
        newEnd: 4,
        existingClips: [_midiClip(trackId: 1)],
        trackId: 0,
      );
      expect(result.hasChanges, isFalse);
    });
  });

  group('AudioOverlapResult', () {
    test('hasChanges is false when empty', () {
      const result = AudioOverlapResult();
      expect(result.hasChanges, isFalse);
    });

    test('hasChanges is true with removals', () {
      final result = AudioOverlapResult(
        removals: [_audioClip()],
      );
      expect(result.hasChanges, isTrue);
    });
  });

  group('MidiOverlapResult', () {
    test('hasChanges is false when empty', () {
      const result = MidiOverlapResult();
      expect(result.hasChanges, isFalse);
    });

    test('hasChanges is true with removals', () {
      final result = MidiOverlapResult(
        removals: [_midiClip()],
      );
      expect(result.hasChanges, isTrue);
    });
  });
}
