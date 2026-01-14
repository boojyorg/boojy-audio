import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/clip_commands.dart';
import 'package:boojy_audio/services/commands/audio_engine_interface.dart';
import 'package:boojy_audio/models/midi_note_data.dart';

/// Mock AudioEngine for testing commands.
/// Implements the interface but with no-op implementations.
class MockAudioEngine implements AudioEngineInterface {
  @override
  void setClipStartTime(int trackId, int clipId, double startTime) {}

  @override
  int loadAudioFileToTrack(String filePath, int trackId, {double startTime = 0.0}) => 1;

  @override
  double getClipDuration(int clipId) => 4.0;

  @override
  List<double> getWaveformPeaks(int clipId, int resolution) => [];

  @override
  void removeAudioClip(int trackId, int clipId) {}

  @override
  int duplicateAudioClip(int trackId, int clipId, double startTime) => clipId + 1000;

  @override
  int createTrack(String trackType, String name) => 1;

  @override
  void deleteTrack(int trackId) {}

  @override
  int duplicateTrack(int sourceTrackId) => sourceTrackId + 1000;

  @override
  String getTrackInfo(int trackId) => '';

  @override
  void setTrackName(int trackId, String name) {}

  @override
  void setTrackVolume(int trackId, double volumeDb) {}

  @override
  void setTrackPan(int trackId, double pan) {}

  @override
  void setTrackMute(int trackId, {required bool mute}) {}

  @override
  void setTrackSolo(int trackId, {required bool solo}) {}

  @override
  void setTrackArmed(int trackId, {required bool armed}) {}

  @override
  int addEffectToTrack(int trackId, String effectType) => 1;

  @override
  int addVst3EffectToTrack(int trackId, String effectPath) => 1;

  @override
  void removeEffectFromTrack(int trackId, int effectId) {}

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) {}

  @override
  void reorderTrackEffects(int trackId, List<int> order) {}

  @override
  void setVst3ParameterValue(int effectId, int paramIndex, double value) {}

  @override
  void setTempo(double bpm) {}

  @override
  void setCountInBars(int bars) {}
}

void main() {
  late MockAudioEngine mockEngine;

  setUp(() {
    mockEngine = MockAudioEngine();
  });

  group('DuplicateMidiClipCommand', () {
    late MidiClipData testClip;

    setUp(() {
      testClip = MidiClipData(
        clipId: 100,
        trackId: 1,
        startTime: 0.0,
        duration: 4.0,
        name: 'Test Clip',
        notes: [
          MidiNoteData(note: 60, velocity: 100, startTime: 0.0, duration: 1.0),
          MidiNoteData(note: 64, velocity: 80, startTime: 1.0, duration: 1.0),
        ],
      );
    });

    test('has correct description', () {
      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
      );

      expect(command.description, 'Duplicate MIDI Clip: Test Clip');
    });

    test('duplicatedClipId is null before execute', () {
      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
      );

      expect(command.duplicatedClipId, isNull);
    });

    test('sharedPatternId is null before execute', () {
      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
      );

      expect(command.sharedPatternId, isNull);
    });

    test('callback receives duplicated clip with new clipId and startTime', () async {
      MidiClipData? duplicatedClip;
      String? receivedPatternId;

      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {
          duplicatedClip = clip;
          receivedPatternId = patternId;
        },
      );

      await command.execute(mockEngine);

      expect(duplicatedClip, isNotNull);
      expect(duplicatedClip!.clipId, isNot(testClip.clipId));
      expect(duplicatedClip!.startTime, 4.0);
      expect(duplicatedClip!.trackId, testClip.trackId);
      expect(duplicatedClip!.duration, testClip.duration);
      expect(duplicatedClip!.notes.length, testClip.notes.length);
      expect(receivedPatternId, isNotNull);
    });

    test('generates patternId if original has none', () async {
      String? receivedPatternId;

      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {
          receivedPatternId = patternId;
        },
      );

      await command.execute(mockEngine);

      expect(receivedPatternId, isNotNull);
      expect(receivedPatternId, startsWith('pattern_'));
      expect(receivedPatternId, contains('${testClip.clipId}'));
    });

    test('preserves existing patternId', () async {
      final clipWithPattern = testClip.copyWith(patternId: 'existing_pattern');
      String? receivedPatternId;

      final command = DuplicateMidiClipCommand(
        originalClip: clipWithPattern,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {
          receivedPatternId = patternId;
        },
      );

      await command.execute(mockEngine);

      expect(receivedPatternId, 'existing_pattern');
    });

    test('sets patternId on duplicated clip', () async {
      MidiClipData? duplicatedClip;

      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {
          duplicatedClip = clip;
        },
      );

      await command.execute(mockEngine);

      expect(duplicatedClip!.patternId, isNotNull);
    });

    test('undo calls onClipRemoved with duplicated clipId', () async {
      int? removedClipId;

      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {},
        onClipRemoved: (clipId) {
          removedClipId = clipId;
        },
      );

      await command.execute(mockEngine);
      final duplicatedId = command.duplicatedClipId;

      await command.undo(mockEngine);

      expect(removedClipId, duplicatedId);
    });

    test('duplicatedClipId is available after execute', () async {
      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {},
      );

      expect(command.duplicatedClipId, isNull);

      await command.execute(mockEngine);

      expect(command.duplicatedClipId, isNotNull);
      expect(command.duplicatedClipId, isNot(testClip.clipId));
    });

    test('sharedPatternId is available after execute', () async {
      final command = DuplicateMidiClipCommand(
        originalClip: testClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {},
      );

      expect(command.sharedPatternId, isNull);

      await command.execute(mockEngine);

      expect(command.sharedPatternId, isNotNull);
    });
  });

  group('DeleteMidiClipFromArrangementCommand', () {
    late MidiClipData testClip;

    setUp(() {
      testClip = MidiClipData(
        clipId: 200,
        trackId: 2,
        startTime: 4.0,
        duration: 8.0,
        name: 'Clip to Delete',
      );
    });

    test('has correct description', () {
      final command = DeleteMidiClipFromArrangementCommand(
        clipData: testClip,
      );

      expect(command.description, 'Delete MIDI Clip: Clip to Delete');
    });

    test('execute calls onClipRemoved with correct IDs', () async {
      int? removedClipId;
      int? removedTrackId;

      final command = DeleteMidiClipFromArrangementCommand(
        clipData: testClip,
        onClipRemoved: (clipId, trackId) {
          removedClipId = clipId;
          removedTrackId = trackId;
        },
      );

      await command.execute(mockEngine);

      expect(removedClipId, testClip.clipId);
      expect(removedTrackId, testClip.trackId);
    });

    test('undo calls onClipRestored with original clip data', () async {
      MidiClipData? restoredClip;

      final command = DeleteMidiClipFromArrangementCommand(
        clipData: testClip,
        onClipRemoved: (clipId, trackId) {},
        onClipRestored: (clip) {
          restoredClip = clip;
        },
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(restoredClip, isNotNull);
      expect(restoredClip!.clipId, testClip.clipId);
      expect(restoredClip!.trackId, testClip.trackId);
      expect(restoredClip!.startTime, testClip.startTime);
      expect(restoredClip!.duration, testClip.duration);
      expect(restoredClip!.name, testClip.name);
    });
  });

  group('MoveMidiClipPositionCommand', () {
    late MidiClipData testClip;

    setUp(() {
      testClip = MidiClipData(
        clipId: 300,
        trackId: 3,
        startTime: 8.0,
        duration: 4.0,
        name: 'Movable Clip',
      );
    });

    test('has correct description', () {
      final command = MoveMidiClipPositionCommand(
        originalClip: testClip,
        newStartTime: 16.0,
        oldStartTime: 8.0,
      );

      expect(command.description, 'Move MIDI Clip: Movable Clip');
    });

    test('execute calls onClipMoved with new position', () async {
      int? movedClipId;
      double? movedStartTime;

      final command = MoveMidiClipPositionCommand(
        originalClip: testClip,
        newStartTime: 16.0,
        oldStartTime: 8.0,
        onClipMoved: (clipId, startTime) {
          movedClipId = clipId;
          movedStartTime = startTime;
        },
      );

      await command.execute(mockEngine);

      expect(movedClipId, testClip.clipId);
      expect(movedStartTime, 16.0);
    });

    test('undo calls onClipMoved with old position', () async {
      int? movedClipId;
      double? movedStartTime;

      final command = MoveMidiClipPositionCommand(
        originalClip: testClip,
        newStartTime: 16.0,
        oldStartTime: 8.0,
        onClipMoved: (clipId, startTime) {
          movedClipId = clipId;
          movedStartTime = startTime;
        },
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(movedClipId, testClip.clipId);
      expect(movedStartTime, 8.0);
    });
  });

  group('CreateMidiClipCommand', () {
    late MidiClipData testClip;

    setUp(() {
      testClip = MidiClipData(
        clipId: 400,
        trackId: 4,
        startTime: 0.0,
        duration: 4.0,
        name: 'New Clip',
      );
    });

    test('has correct description', () {
      final command = CreateMidiClipCommand(
        clipData: testClip,
      );

      expect(command.description, 'Create MIDI Clip: New Clip');
    });

    test('execute calls onClipCreated with clip data', () async {
      MidiClipData? createdClip;

      final command = CreateMidiClipCommand(
        clipData: testClip,
        onClipCreated: (clip) {
          createdClip = clip;
        },
      );

      await command.execute(mockEngine);

      expect(createdClip, isNotNull);
      expect(createdClip!.clipId, testClip.clipId);
      expect(createdClip!.trackId, testClip.trackId);
      expect(createdClip!.startTime, testClip.startTime);
      expect(createdClip!.duration, testClip.duration);
    });

    test('undo calls onClipRemoved with correct IDs', () async {
      int? removedClipId;
      int? removedTrackId;

      final command = CreateMidiClipCommand(
        clipData: testClip,
        onClipCreated: (clip) {},
        onClipRemoved: (clipId, trackId) {
          removedClipId = clipId;
          removedTrackId = trackId;
        },
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(removedClipId, testClip.clipId);
      expect(removedTrackId, testClip.trackId);
    });
  });

  group('Command round-trip tests', () {
    test('duplicate then undo restores original state', () async {
      final originalClip = MidiClipData(
        clipId: 500,
        trackId: 5,
        startTime: 0.0,
        duration: 4.0,
        name: 'Original',
      );

      final clips = <int, MidiClipData>{originalClip.clipId: originalClip};

      final command = DuplicateMidiClipCommand(
        originalClip: originalClip,
        newStartTime: 4.0,
        onClipDuplicated: (clip, patternId) {
          clips[clip.clipId] = clip;
        },
        onClipRemoved: (clipId) {
          clips.remove(clipId);
        },
      );

      // Execute - should have 2 clips
      await command.execute(mockEngine);
      expect(clips.length, 2);

      // Undo - should be back to 1 clip
      await command.undo(mockEngine);
      expect(clips.length, 1);
      expect(clips.containsKey(originalClip.clipId), true);
    });

    test('delete then undo restores clip', () async {
      final clipToDelete = MidiClipData(
        clipId: 600,
        trackId: 6,
        startTime: 0.0,
        duration: 4.0,
        name: 'To Delete',
      );

      final clips = <int, MidiClipData>{clipToDelete.clipId: clipToDelete};

      final command = DeleteMidiClipFromArrangementCommand(
        clipData: clipToDelete,
        onClipRemoved: (clipId, trackId) {
          clips.remove(clipId);
        },
        onClipRestored: (clip) {
          clips[clip.clipId] = clip;
        },
      );

      // Execute - should be empty
      await command.execute(mockEngine);
      expect(clips.length, 0);

      // Undo - should restore clip
      await command.undo(mockEngine);
      expect(clips.length, 1);
      expect(clips[clipToDelete.clipId]?.name, 'To Delete');
    });

    test('create then undo removes clip', () async {
      final newClip = MidiClipData(
        clipId: 700,
        trackId: 7,
        startTime: 0.0,
        duration: 4.0,
        name: 'Created',
      );

      final clips = <int, MidiClipData>{};

      final command = CreateMidiClipCommand(
        clipData: newClip,
        onClipCreated: (clip) {
          clips[clip.clipId] = clip;
        },
        onClipRemoved: (clipId, trackId) {
          clips.remove(clipId);
        },
      );

      // Execute - should have 1 clip
      await command.execute(mockEngine);
      expect(clips.length, 1);

      // Undo - should be empty
      await command.undo(mockEngine);
      expect(clips.length, 0);
    });

    test('move then undo restores position', () async {
      final originalClip = MidiClipData(
        clipId: 800,
        trackId: 8,
        startTime: 0.0,
        duration: 4.0,
        name: 'Movable',
      );

      var currentStartTime = originalClip.startTime;

      final command = MoveMidiClipPositionCommand(
        originalClip: originalClip,
        newStartTime: 8.0,
        oldStartTime: 0.0,
        onClipMoved: (clipId, startTime) {
          currentStartTime = startTime;
        },
      );

      // Execute - should move to 8.0
      await command.execute(mockEngine);
      expect(currentStartTime, 8.0);

      // Undo - should be back to 0.0
      await command.undo(mockEngine);
      expect(currentStartTime, 0.0);
    });
  });
}
