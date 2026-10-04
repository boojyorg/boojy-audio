import 'dart:math' as math;

import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/services/state_consistency.dart';
import 'package:boojy_audio/widgets/audio_editor/operations/parameter_operations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

// Workflow tests through the real DAW screen and engine (no window). Each
// does what Tyr does, through the methods the buttons call, and checks after
// every step that the screen shows what the engine plays. These are where
// the loop toggle and tempo-to-warp wiring bugs lived.

void main() {
  if (!isNativeEngineAvailable) {
    test('DAW workflows (native engine)', () {}, skip: true);
    return;
  }

  /// Drop a 2 s click file onto the empty arrangement; returns its clip.
  Future<ClipData> dropClip(DawHarness h, String name) async {
    await h.daw.onAudioFileDroppedOnEmpty(h.writeClickWav(name));
    await h.settle();
    return h.daw.timelineKey.currentState!.clips.last;
  }

  /// Warp a clip at [bpm], as the audio editor does.
  Future<ClipData> warp(DawHarness h, ClipData clip, double bpm) async {
    final edit = AudioClipEditData(bpm: bpm, syncEnabled: true);
    pushAudioClipEdits(h.engine, clip.trackId, clip.clipId, edit);
    final warped = clip.copyWith(editData: edit);
    h.daw.timelineKey.currentState!.updateClip(warped);
    await h.settle();
    return warped;
  }

  /// Edit a clip through the undo step, as the audio editor does.
  Future<ClipData> editClip(
    DawHarness h,
    ClipData clip,
    AudioClipEditData edit,
  ) async {
    await h.daw.undoRedoManager.execute(
      AudioClipEditCommand(
        beforeState: clip.editData ?? const AudioClipEditData(),
        afterState: edit,
        clipData: clip,
        actionDescription: 'Edit clip',
        onApplyState: (state, data) => h.daw.timelineKey.currentState!
            .updateClip(data.copyWith(editData: state)),
      ),
    );
    await h.settle();
    return h.daw.timelineKey.currentState!.clips.firstWhere(
      (c) => c.clipId == clip.clipId,
    );
  }

  double engineStretch(DawHarness h, int clipId) => EngineSnapshot.read(
    h.engine,
  ).audioClips.firstWhere((c) => c.clipId == clipId).stretchFactor;

  testWidgets('a warped clip follows tempo changes, dragged or typed', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      final clip = await warp(h, await dropClip(h, 'loop.wav'), 150);
      expect(engineStretch(h, clip.clipId), closeTo(120 / 150, 1e-3));
      h.expectScreenMatchesEngine(after: 'warping at 150 BPM');

      await h.daw.onTempoChanged(170);
      await h.settle();
      expect(engineStretch(h, clip.clipId), closeTo(170 / 150, 1e-3));
      h.expectScreenMatchesEngine(after: 'typing 170 BPM');

      // A drag re-stretches once, on release.
      h.daw.onTempoDragStart();
      await h.daw.onTempoChanged(140);
      await h.daw.onTempoChanged(97);
      await h.daw.onTempoDragEnd();
      await h.settle();
      expect(engineStretch(h, clip.clipId), closeTo(97 / 150, 1e-3));
      h.expectScreenMatchesEngine(after: 'dragging the tempo to 97 BPM');

      await h.daw.undoRedoManager.undo();
      await h.settle();
      expect(h.daw.tempo, 170);
      expect(engineStretch(h, clip.clipId), closeTo(170 / 150, 1e-3));
      h.expectScreenMatchesEngine(after: 'undoing the drag');
    } finally {
      await h.close();
    }
  });

  testWidgets('loop turned on and off while playing takes effect at once', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h, 'loop.wav');
      h.daw.uiLayout.setLoopRegion(0, 2); // beats 0–2: the first second
      expect(h.daw.uiLayout.loopPlaybackEnabled, isFalse);

      h.daw.playWithLoopCheck();
      await h.settleUntil(
        () => h.daw.playheadPosition > 0.2,
        what: 'playback to start',
      );

      // Loop on mid-song, inside the loop: playback must keep jumping back
      // at 1 s instead of running on (it used to wait for the next Play).
      h.daw.toggleLoop();
      var furthest = 0.0;
      var jumpedBack = false;
      var last = h.daw.playheadPosition;
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(milliseconds: 2500)) {
        await h.settle(frames: 1, ms: 20);
        final now = h.daw.playheadPosition;
        if (now < last - 0.5) jumpedBack = true;
        furthest = math.max(furthest, now);
        last = now;
      }
      expect(jumpedBack, isTrue, reason: 'loop on: playback jumps back');
      expect(furthest, lessThan(1.3), reason: 'loop on: never far past 1 s');

      // Loop off mid-loop: the song carries on past the loop end.
      h.daw.toggleLoop();
      await h.settleUntil(
        () => h.daw.playheadPosition > 1.5,
        what: 'playback to run past the loop end once loop is off',
        timeout: const Duration(seconds: 5),
      );
      h.expectScreenMatchesEngine(after: 'looping');
    } finally {
      await h.close();
    }
  });

  testWidgets(
    'Duplicate Track copies audio and MIDI clips; undo removes them',
    (tester) async {
      final h = await DawHarness.start(tester);
      try {
        final audio = await dropClip(h, 'drums.wav');

        await tester.tap(find.text('MIDI').first);
        await h.settle();
        final manager = h.daw.midiPlaybackManager!;
        final midi = manager.midiClips.single;
        h.daw.midiClipController.updateClip(
          midi.copyWith(
            notes: [
              MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
              MidiNoteData(note: 64, velocity: 100, startTime: 2, duration: 1),
            ],
          ),
          h.daw.playheadPosition,
        );
        await h.settle();
        h.expectScreenMatchesEngine(after: 'adding an audio and a MIDI track');

        TrackData track(int id) =>
            TrackData.fromCSV(h.engine.getTrackInfo(id))!;
        await h.daw.onDuplicateTrackRequested(track(audio.trackId));
        await h.daw.onDuplicateTrackRequested(track(midi.trackId));
        await h.settle();

        final clips = h.daw.timelineKey.currentState!.clips;
        expect(clips, hasLength(2), reason: 'the audio copy is on screen');
        expect(clips.map((c) => c.clipId).toSet(), hasLength(2));
        expect(manager.midiClips, hasLength(2), reason: 'the MIDI copy too');
        expect(manager.midiClips.last.notes, hasLength(2));
        h.expectScreenMatchesEngine(after: 'duplicating both tracks');

        await h.daw.undoRedoManager.undo();
        await h.daw.undoRedoManager.undo();
        await h.settle();
        expect(h.daw.timelineKey.currentState!.clips, hasLength(1));
        expect(manager.midiClips, hasLength(1));
        h.expectScreenMatchesEngine(after: 'undoing both duplicates');
      } finally {
        await h.close();
      }
    },
  );

  testWidgets('save and reopen keep warped and duplicated tracks', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      final clip = await warp(h, await dropClip(h, 'loop.wav'), 150);
      await h.daw.onDuplicateTrackRequested(
        TrackData.fromCSV(h.engine.getTrackInfo(clip.trackId))!,
      );
      await h.daw.onTempoChanged(140);
      await h.settle();
      h.expectScreenMatchesEngine(after: 'warping, duplicating, 140 BPM');

      final path = '${h.tempDir.path}/Song.audio';
      await h.realTime(() => h.daw.saveProjectToPath(path));
      await h.settleUntil(() => !h.daw.isLoading, what: 'the save');

      h.daw.executeNewProject();
      await h.settle();
      expect(h.daw.timelineKey.currentState!.clips, isEmpty);

      await h.realTime(() => h.daw.openRecentProject(path));
      await h.settleUntil(
        () => h.daw.timelineKey.currentState!.clips.length == 2,
        what: 'the reopened project to show both clips',
      );
      await h.settle();
      expect(h.daw.tempo, 140);
      for (final reopened in h.daw.timelineKey.currentState!.clips) {
        expect(reopened.editData?.syncEnabled, isTrue);
        expect(engineStretch(h, reopened.clipId), closeTo(140 / 150, 1e-3));
      }
      h.expectScreenMatchesEngine(after: 'reopening');
    } finally {
      await h.close();
    }
  });

  // Bugs the stress test found (daw_stress_test.dart), each pinned here by
  // name so a change to the random action mix can't lose them.
  group('found by the stress test', () {
    testWidgets('undoing a file drop takes its clip too; redo brings it back', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        await dropClip(h, 'take.wav');
        await h.daw.performUndo();
        await h.settle();
        expect(h.daw.timelineKey.currentState!.clips, isEmpty);
        h.expectScreenMatchesEngine(after: 'undoing the drop');
        await h.daw.performRedo();
        await h.settle();
        expect(h.daw.timelineKey.currentState!.clips, hasLength(1));
        h.expectScreenMatchesEngine(after: 'redoing the drop');
      } finally {
        await h.close();
      }
    });

    testWidgets('undoing Add MIDI Track takes its starting clip too', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        await tester.tap(find.text('MIDI').first);
        await h.settle();
        expect(h.daw.midiPlaybackManager!.midiClips, hasLength(1));
        await h.daw.performUndo();
        await h.settle();
        expect(h.daw.midiPlaybackManager!.midiClips, isEmpty);
        h.expectScreenMatchesEngine(after: 'undoing Add MIDI Track');
      } finally {
        await h.close();
      }
    });

    testWidgets('a drawn MIDI clip reaches the engine straight away', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        await tester.tap(find.text('MIDI').first);
        await h.settle();
        final trackId = h.daw.midiPlaybackManager!.midiClips.single.trackId;
        await h.daw.createMidiClipWithParams(trackId, 8, 4);
        await h.settle();
        h.expectScreenMatchesEngine(after: 'drawing a MIDI clip');
      } finally {
        await h.close();
      }
    });

    testWidgets('undoing a MIDI clip drawn over another brings that one back', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        await tester.tap(find.text('MIDI').first);
        await h.settle();
        final manager = h.daw.midiPlaybackManager!;
        final covered = manager.midiClips.single;
        await h.daw.createMidiClipWithParams(
          covered.trackId,
          covered.startTime,
          covered.duration,
        );
        await h.settle();
        expect(manager.midiClips.map((c) => c.clipId), isNot([covered.clipId]));
        await h.daw.performUndo();
        await h.settle();
        expect(manager.midiClips.map((c) => c.clipId), [covered.clipId]);
        h.expectScreenMatchesEngine(after: 'undoing the drawn clip');
      } finally {
        await h.close();
      }
    });

    testWidgets('undoing Delete Track brings the clips back with their edits', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final clip = await dropClip(h, 'take.wav');
        const edit = AudioClipEditData(reversed: true, transposeSemitones: 3);
        await h.daw.undoRedoManager.execute(
          AudioClipEditCommand(
            beforeState: const AudioClipEditData(),
            afterState: edit,
            clipData: clip,
            actionDescription: 'Edit clip',
            onApplyState: (state, data) => h.daw.timelineKey.currentState!
                .updateClip(data.copyWith(editData: state)),
          ),
        );
        await h.settle();
        await h.daw.onDeleteTrackRequested(
          TrackData.fromCSV(h.engine.getTrackInfo(clip.trackId))!,
        );
        await h.settle();
        await h.daw.performUndo();
        await h.settle();
        h.expectScreenMatchesEngine(after: 'undoing Delete Track');
        // The clip came back under its old id, so the edit's undo finds it.
        await h.daw.performUndo();
        await h.settle();
        expect(
          h.daw.timelineKey.currentState!.clips.single.editData?.reversed,
          isNot(isTrue),
        );
        h.expectScreenMatchesEngine(after: 'then undoing the edit');
      } finally {
        await h.close();
      }
    });

    testWidgets(
      'redoing a file drop, then an edit to its clip, finds the clip',
      (tester) async {
        final h = await DawHarness.start(tester);
        try {
          final clip = await dropClip(h, 'take.wav');
          await editClip(h, clip, const AudioClipEditData(reversed: true));
          await h.daw.performUndo();
          await h.daw.performUndo();
          await h.settle();
          await h.daw.performRedo();
          await h.daw.performRedo();
          await h.settle();
          final redone = h.daw.timelineKey.currentState!.clips.single;
          expect(redone.clipId, clip.clipId);
          expect(redone.editData?.reversed, isTrue);
          h.expectScreenMatchesEngine(after: 'redoing the drop and the edit');
        } finally {
          await h.close();
        }
      },
    );

    testWidgets('undoing a copy dropped over a clip brings that clip back', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final first = await dropClip(h, 'take.wav');
        h.daw.onAudioClipCopied(first, first.startTime + first.duration);
        await h.settle();
        final timeline = h.daw.timelineKey.currentState!;
        final copy = timeline.clips.firstWhere((c) => c.clipId != first.clipId);
        // A second copy right on top of the first clip covers it completely.
        h.daw.onAudioClipCopied(copy, first.startTime);
        await h.settle();
        expect(
          timeline.clips.map((c) => c.clipId),
          isNot(contains(first.clipId)),
        );
        await h.daw.performUndo();
        await h.settle();
        final back = timeline.clips.firstWhere((c) => c.clipId == first.clipId);
        expect(back.duration, closeTo(first.duration, 1e-6));
        h.expectScreenMatchesEngine(after: 'undoing the covering copy');
      } finally {
        await h.close();
      }
    });

    testWidgets('redoing a MIDI clip copy brings back the same clip', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        await tester.tap(find.text('MIDI').first);
        await h.settle();
        final manager = h.daw.midiPlaybackManager!;
        final source = manager.midiClips.single;
        h.daw.onMidiClipCopied(source, source.startTime + source.duration);
        await h.settle();
        final copyId = manager.midiClips.last.clipId;
        await h.daw.performUndo();
        await h.settle();
        await h.daw.performRedo();
        await h.settle();
        expect(manager.midiClips.map((c) => c.clipId), contains(copyId));
        h.expectScreenMatchesEngine(after: 'redoing the copy');
      } finally {
        await h.close();
      }
    });

    testWidgets(
      'splitting an edited audio clip keeps the edits on both halves',
      (tester) async {
        final h = await DawHarness.start(tester);
        try {
          final clip = await dropClip(h, 'take.wav');
          const edit = AudioClipEditData(reversed: true, transposeSemitones: 3);
          final edited = await editClip(h, clip, edit);
          final timeline = h.daw.timelineKey.currentState!;
          timeline.runAudioSplit(edited, edited.startTime + 1);
          await h.settle();
          expect(timeline.clips, hasLength(2));
          h.expectScreenMatchesEngine(after: 'splitting');
          final rightId = timeline.clips.last.clipId;
          await h.daw.performUndo();
          await h.settle();
          await h.daw.performRedo();
          await h.settle();
          expect(timeline.clips.map((c) => c.clipId), contains(rightId));
          h.expectScreenMatchesEngine(after: 'undoing and redoing the split');
        } finally {
          await h.close();
        }
      },
    );

    testWidgets('a repeating MIDI clip keeps its length through reopen', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        await tester.tap(find.text('MIDI').first);
        await h.settle();
        final manager = h.daw.midiPlaybackManager!;
        final clip = manager.midiClips.single.copyWith(
          duration: 8, // extended to repeat its 4-beat loop
          loopLength: 4,
          canRepeat: true,
          notes: [
            MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
          ],
        );
        h.daw.midiClipController.updateClip(clip, h.daw.playheadPosition);
        await h.daw.onTempoChanged(140);
        await h.settle();
        h.expectScreenMatchesEngine(after: 'extending the clip at 140 BPM');

        final path = '${h.tempDir.path}/Loop.audio';
        await h.realTime(() => h.daw.saveProjectToPath(path));
        await h.settleUntil(() => !h.daw.isLoading, what: 'the save');
        h.daw.executeNewProject();
        await h.settle();
        await h.realTime(() => h.daw.openRecentProject(path));
        await h.settleUntil(
          () => manager.midiClips.isNotEmpty,
          what: 'the reopened MIDI clip',
        );
        await h.settle();
        final reopened = manager.midiClips.single;
        expect(reopened.duration, closeTo(8, 1e-6));
        expect(reopened.loopLength, closeTo(4, 1e-6));
        h.expectScreenMatchesEngine(after: 'reopening');
      } finally {
        await h.close();
      }
    });
  });
}
