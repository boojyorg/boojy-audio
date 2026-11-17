import 'dart:math' as math;

import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor_controls_bar.dart';
import 'package:boojy_audio/widgets/audio_editor/operations/parameter_operations.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/clip_audio.dart';
import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';
import 'support/workflow_helpers.dart';

// Audio clip workflows (warp, loop, trim, save and reopen) through the real
// DAW screen and engine (see daw_workflow_test.dart).

void main() {
  if (!isNativeEngineAvailable) {
    test('DAW clip workflows (native engine)', () {}, skip: true);
    return;
  }

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

  testWidgets('an editor change keeps a clip stretched since it opened', (
    tester,
  ) async {
    // Found by Tyr: open the editor on a clip, stretch the clip to repeat,
    // press Reverse, and it went back to one pass (the editor sent back its
    // copy of the clip from when it opened, old length and all).
    final h = await DawHarness.start(tester);
    try {
      final clip = await dropClip(h, 'loop.wav');
      final callbacks = tester
          .widget<TimelineView>(find.byType(TimelineView))
          .audioClipCallbacks;
      callbacks.onSelected!(clip.clipId, clip);
      callbacks.onOpenEditor!();
      await h.settle();

      final timeline = h.daw.timelineKey.currentState!;
      final twice = clip.loopLength * 2;
      await timeline.resizeAudioClip(
        clip,
        clip.withEdges(
          start: clip.startTime,
          end: clip.startTime + clip.timelineSeconds(twice, h.daw.tempo),
          projectBpm: h.daw.tempo,
        ),
      );
      await h.settle();

      final editor =
          tester.state(find.byType(AudioEditor)) as ParameterOperationsMixin;
      editor.toggleReverse();
      await h.settle();

      final now = timeline.clips.firstWhere((c) => c.clipId == clip.clipId);
      expect(now.duration, closeTo(twice, 1e-9), reason: 'still two passes');
      expect(now.isLooped, isTrue);
      expect(now.editData?.reversed, isTrue);
      h.expectScreenMatchesEngine(after: 'reversing in the editor');
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

  testWidgets('trimming keeps the audio under what stays, however it plays', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      final timeline = h.daw.timelineKey.currentState!;
      ClipData current(int id) =>
          timeline.clips.firstWhere((c) => c.clipId == id);
      // What a clip plays at [t] seconds on the timeline.
      double at(ClipData c, double t) => audioAt(
        c,
        (t - c.startTime) * (c.editData?.stretchAt(h.daw.tempo) ?? 1.0),
      );
      final edits = [
        ('plain', const AudioClipEditData()),
        ('reversed', const AudioClipEditData(reversed: true)),
        ('warped', const AudioClipEditData(syncEnabled: true, bpm: 60)),
        (
          'reversed and warped',
          const AudioClipEditData(reversed: true, syncEnabled: true, bpm: 60),
        ),
      ];
      for (final (what, edit) in edits) {
        for (final loop in [true, false]) {
          final name = '$what, Loop ${loop ? 'on' : 'off'}';
          var clip = await editClip(h, await dropClip(h, '$name.wav'), edit);
          if (!loop) {
            clip = clip.copyWith(canRepeat: false);
            timeline.updateClip(clip);
            pushAudioClipLoop(h.engine, clip);
          }
          final original = clip;
          final start = clip.startTime;
          final end = clip.timelineEnd(h.daw.tempo);
          final quarter = (end - start) / 4;

          // Each edge dragged in by a quarter.
          await timeline.resizeAudioClip(
            clip,
            timeline.audioClipWithEdges(clip, start: start + quarter),
          );
          await h.settle();
          clip = current(clip.clipId);
          await timeline.resizeAudioClip(
            clip,
            timeline.audioClipWithEdges(clip, end: end - quarter),
          );
          await h.settle();
          clip = current(clip.clipId);
          expect(clip.startTime, closeTo(start + quarter, 1e-9), reason: name);
          expect(clip.timelineEnd(h.daw.tempo), closeTo(end - quarter, 1e-9));
          for (final t in [0.3, 0.5, 0.7]) {
            final time = start + (end - start) * t;
            expect(
              at(clip, time),
              closeTo(at(original, time), 1e-6),
              reason: '$name at $time',
            );
          }
          h.expectScreenMatchesEngine(after: 'trimming the $name clip');

          if (!loop) {
            // Dragged out again, the edges stop at the ends of the audio.
            await timeline.resizeAudioClip(
              clip,
              timeline.audioClipWithEdges(clip, end: end + 5),
            );
            await h.settle();
            expect(
              current(clip.clipId).timelineEnd(h.daw.tempo),
              closeTo(end, 1e-6),
              reason: name,
            );
            await h.daw.undoRedoManager.undo();
          }

          // Undo puts the clip back as it was.
          await h.daw.undoRedoManager.undo();
          await h.daw.undoRedoManager.undo();
          await h.settle();
          clip = current(clip.clipId);
          expect(
            (clip.startTime, clip.offset, clip.duration, clip.loopStart),
            (original.startTime, original.offset, original.duration, 0.0),
            reason: name,
          );
          h.expectScreenMatchesEngine(after: 'undoing the $name trims');
        }
      }
    } finally {
      await h.close();
    }
  });

  testWidgets('a clip shorter than the trim minimum can still be dragged', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      final timeline = h.daw.timelineKey.currentState!;
      var clip = await dropClip(h, 'short.wav');
      // An overlap can leave a remainder this short.
      await timeline.resizeAudioClip(
        clip,
        clip.withEdges(
          start: clip.startTime,
          end: clip.startTime + 0.05,
          projectBpm: h.daw.tempo,
        ),
      );
      await h.settle();
      clip = timeline.clips.firstWhere((c) => c.clipId == clip.clipId);
      final inLeft = timeline.audioClipWithEdges(
        clip,
        start: clip.startTime + 0.02,
      );
      final inRight = timeline.audioClipWithEdges(
        clip,
        end: clip.timelineEnd(h.daw.tempo) - 0.02,
      );
      expect(inLeft.duration, closeTo(0.05, 1e-9), reason: 'not further in');
      expect(inRight.duration, closeTo(0.05, 1e-9), reason: 'not further in');
      final out = timeline.audioClipWithEdges(
        clip,
        end: clip.timelineEnd(h.daw.tempo) + 0.5,
      );
      expect(out.duration, closeTo(0.55, 1e-9));
    } finally {
      await h.close();
    }
  });

  testWidgets("the Audio Editor's loop Start picks which part repeats", (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      final timeline = h.daw.timelineKey.currentState!;
      final clip = await dropClip(h, 'loop.wav'); // 2 s at 120 BPM: 4 beats
      final callbacks = tester
          .widget<TimelineView>(find.byType(TimelineView))
          .audioClipCallbacks;
      callbacks.onSelected!(clip.clipId, clip);
      callbacks.onOpenEditor!();
      await h.settle();
      AudioEditorControlsBar bar() => tester.widget<AudioEditorControlsBar>(
        find.byType(AudioEditorControlsBar),
      );

      // On a new clip the region is the whole file. Start moves its
      // beginning and keeps its end: beats 2–4 (0.5–2.0 s of the file).
      bar().onStartChanged!(1.0);
      await h.settle();
      expect(bar().startOffsetBeats, closeTo(1.0, 1e-9));
      expect(bar().lengthBeats, closeTo(3.0, 1e-9));
      var now = timeline.clips.firstWhere((c) => c.clipId == clip.clipId);
      expect(now.loopWindowStart, closeTo(0.5, 1e-9));
      expect(now.loopLength, closeTo(1.5, 1e-9));
      h.expectScreenMatchesEngine(after: 'moving the loop Start');

      // Then repeat just the second beat (0.5–1.0 s of the file).
      bar().onLengthChanged!(1.0);
      await h.settle();

      now = timeline.clips.firstWhere((c) => c.clipId == clip.clipId);
      expect(now.loopLength, closeTo(0.5, 1e-9));
      expect(now.loopWindowStart, closeTo(0.5, 1e-9));
      for (final x in [0.1, 0.6, 1.1, 1.6]) {
        expect(audioAt(now, x), closeTo(0.6, 1e-9), reason: 'at $x s');
      }
      h.expectScreenMatchesEngine(after: 'moving the loop Start');
    } finally {
      await h.close();
    }
  });
}
