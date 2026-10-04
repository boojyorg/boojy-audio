import 'dart:math' as math;

import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/services/state_consistency.dart';
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
}
