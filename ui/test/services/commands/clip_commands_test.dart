import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/clip_commands.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/utils/clip_overlap_handler.dart';
import '../../mocks/mock_audio_engine.dart';

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

    test(
      'callback receives duplicated clip with new clipId and startTime',
      () async {
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
      },
    );

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
      final command = DeleteMidiClipFromArrangementCommand(clipData: testClip);

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
      final command = CreateMidiClipCommand(clipData: testClip);

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

  group('DeleteAudioClipCommand', () {
    ClipData makeClip() => ClipData(
      clipId: 42,
      trackId: 3,
      filePath: '/audio/loop.wav',
      startTime: 2.0,
      duration: 4.0,
    );

    test('execute removes the clip, undo reloads it', () async {
      int? restoredId;
      final command = DeleteAudioClipCommand(
        clipData: makeClip(),
        onClipRestored: (clip) => restoredId = clip.clipId,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('removeAudioClip'));
      expect(mockEngine.calls, contains('loadAudioFileToTrack'));
      // Undo reloads from disk → engine hands back a fresh clip id.
      expect(restoredId, isNotNull);
    });

    // Regression test for the stale-id-on-redo bug (M-10): undo reloads the
    // clip and the engine assigns a *new* id, so redo must remove that new id —
    // not the stale original, which would leave the restored clip playing.
    test('redo targets the reloaded clip id, not the stale original', () async {
      final command = DeleteAudioClipCommand(clipData: makeClip());

      await command.execute(mockEngine); // removes 42
      await command.undo(mockEngine); // reloads with a fresh id
      await command.execute(mockEngine); // redo: must remove the reloaded id

      expect(mockEngine.removedClipIds.first, 42);
      expect(mockEngine.removedClipIds.last, isNot(42));
    });
  });

  // H-11: dragging a clip over a neighbour must be fully undoable — both the
  // moved clip and the overwritten neighbour return on one Ctrl+Z. These tests
  // drive the command layer against a simulated UI clip list (the timeline's
  // stateful `clips`) + the mock engine, covering execute / undo / redo.
  group('H-11 audio move + overlap undo', () {
    // A stand-in for the timeline's stateful `clips` list.
    late List<ClipData> ui;

    ClipData clip(int id, double start, double dur, {double offset = 0.0}) =>
        ClipData(
          clipId: id,
          trackId: 1,
          filePath: 'a.wav',
          startTime: start,
          duration: dur,
          offset: offset,
        );

    // UI callbacks that mutate `ui` the way the gesture handler wires them.
    void uiRemove(int id) => ui.removeWhere((c) => c.clipId == id);
    void uiUpdate(ClipData c) {
      final i = ui.indexWhere((e) => e.clipId == c.clipId);
      if (i >= 0) {
        ui[i] = c;
      } else {
        ui.add(c);
      }
    }

    void uiAdd(ClipData c) => ui.add(c);

    setUp(() {
      ui = [];
    });

    test('simple move: undo and redo move the clip in the UI list', () async {
      ui = [clip(1, 5.0, 4.0)];
      final cmd = MoveAudioClipCommand(
        trackId: 1,
        clipId: 1,
        clipName: 'a',
        oldStartTime: 5.0,
        newStartTime: 9.0,
        onClipMoved: (id, start) {
          final i = ui.indexWhere((c) => c.clipId == id);
          if (i >= 0) ui[i] = ui[i].copyWith(startTime: start);
        },
      );

      await cmd.execute(mockEngine);
      expect(ui.single.startTime, 9.0); // moved in the UI, not just the engine

      await cmd.undo(mockEngine);
      expect(ui.single.startTime, 5.0); // ← the bug: previously stayed at 9.0

      await cmd.execute(mockEngine);
      expect(ui.single.startTime, 9.0);
    });

    test('complete-cover removal is restored on undo (redo-safe)', () async {
      final neighbour = clip(200, 0.0, 4.0);
      ui = [neighbour];
      final result = AudioOverlapResult(removals: [neighbour]);
      final cmd = ResolveAudioOverlapCommand(
        result: result,
        uiRemoveClip: uiRemove,
        uiUpdateClip: uiUpdate,
        uiAddClip: uiAdd,
      );

      await cmd.execute(mockEngine);
      expect(ui, isEmpty); // neighbour deleted
      expect(mockEngine.removedClipIds, [200]);

      await cmd.undo(mockEngine);
      expect(ui.length, 1); // neighbour restored
      final restoredId = ui.single.clipId;
      expect(restoredId, isNot(200)); // engine assigned a fresh id on reload
      expect(ui.single.startTime, 0.0);

      // Redo must remove the *reloaded* id, not the stale 200.
      await cmd.execute(mockEngine);
      expect(ui, isEmpty);
      expect(mockEngine.removedClipIds.last, restoredId);
    });

    test(
      'trim (update) is restored on undo with full offset/duration',
      () async {
        final original = clip(200, 0.0, 4.0, offset: 0.0);
        final trimmed = original.copyWith(duration: 2.0); // end-trimmed
        ui = [original];
        final result = AudioOverlapResult(
          updates: [AudioClipUpdate(original: original, updated: trimmed)],
        );
        final cmd = ResolveAudioOverlapCommand(
          result: result,
          uiRemoveClip: uiRemove,
          uiUpdateClip: uiUpdate,
          uiAddClip: uiAdd,
        );

        await cmd.execute(mockEngine);
        expect(ui.single.duration, 2.0);

        await cmd.undo(mockEngine);
        expect(ui.single.duration, 4.0); // restored
        expect(ui.single.offset, 0.0);
        expect(ui.single.clipId, 200); // trims keep the id (resized in place)
      },
    );

    test('split is restored on undo and re-applied on redo', () async {
      // Drop a clip inside a 6s neighbour → split into partA (0..2) + partB (4..6).
      final original = clip(200, 0.0, 6.0);
      final partA = original.copyWith(duration: 2.0);
      final partBTemplate = original.copyWith(
        clipId: -1,
        startTime: 4.0,
        duration: 2.0,
        offset: 4.0,
      );
      ui = [original];
      final result = AudioOverlapResult(
        splits: [
          AudioSplitOperation(
            original: original,
            partA: partA,
            partBTemplate: partBTemplate,
          ),
        ],
      );
      final cmd = ResolveAudioOverlapCommand(
        result: result,
        uiRemoveClip: uiRemove,
        uiUpdateClip: uiUpdate,
        uiAddClip: uiAdd,
      );

      await cmd.execute(mockEngine);
      expect(ui.length, 2); // partA (original trimmed) + partB (new)
      expect(ui.firstWhere((c) => c.clipId == 200).duration, 2.0); // partA
      final partB = ui.firstWhere((c) => c.clipId != 200);
      expect(partB.startTime, 4.0);
      expect(partB.duration, 2.0);

      await cmd.undo(mockEngine);
      expect(ui.length, 1); // back to the single original
      expect(ui.single.clipId, 200);
      expect(ui.single.duration, 6.0);

      await cmd.execute(mockEngine);
      expect(ui.length, 2); // re-split cleanly
    });
  });

  group('H-11 MIDI move + overlap undo', () {
    late List<MidiClipData> ui;

    MidiClipData mclip(int id, double start, double dur) => MidiClipData(
      clipId: id,
      trackId: 2,
      startTime: start,
      duration: dur,
      name: 'm$id',
      notes: const [],
    );

    ResolveMidiOverlapCommand build(MidiOverlapResult result) =>
        ResolveMidiOverlapCommand(
          result: result,
          tempo: 120.0,
          deleteClip: (id, _) => ui.removeWhere((c) => c.clipId == id),
          addClip: (c) {
            ui.removeWhere(
              (e) => e.clipId == c.clipId,
            ); // upsert, like the manager
            ui.add(c);
          },
          updateClipInPlace: (c) {
            final i = ui.indexWhere((e) => e.clipId == c.clipId);
            if (i >= 0) ui[i] = c;
          },
          rescheduleClip: (_, __) {},
        );

    setUp(() {
      ui = [];
    });

    test('complete-cover removal is restored on undo', () async {
      final neighbour = mclip(200, 0.0, 4.0);
      ui = [neighbour];
      final cmd = build(MidiOverlapResult(removals: [neighbour]));

      await cmd.execute(mockEngine);
      expect(ui, isEmpty);

      await cmd.undo(mockEngine);
      expect(ui.single.clipId, 200);
      expect(ui.single.duration, 4.0);
    });

    test('split is restored on undo and re-applied on redo', () async {
      final original = mclip(200, 0.0, 6.0);
      final partA = original.copyWith(clipId: 201, duration: 2.0);
      final partB = original.copyWith(
        clipId: 202,
        startTime: 4.0,
        duration: 2.0,
      );
      ui = [original];
      final cmd = build(
        MidiOverlapResult(
          splits: [
            MidiSplitOperation(original: original, partA: partA, partB: partB),
          ],
        ),
      );

      await cmd.execute(mockEngine);
      expect(ui.map((c) => c.clipId).toSet(), {201, 202}); // split parts only

      await cmd.undo(mockEngine);
      expect(ui.single.clipId, 200); // original restored
      expect(ui.single.duration, 6.0);

      await cmd.execute(mockEngine);
      expect(ui.map((c) => c.clipId).toSet(), {201, 202}); // re-split cleanly
    });
  });
}
