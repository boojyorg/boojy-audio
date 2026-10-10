import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/services/state_consistency.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor_controls_bar.dart';
import 'package:boojy_audio/widgets/export_dialog.dart';
import 'package:boojy_audio/widgets/audio_editor/operations/parameter_operations.dart';
import 'package:boojy_audio/widgets/shared/editors/unified_nav_bar.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/clip_audio.dart';
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

  /// Edit a clip as the audio editor does: the change, then one undo step.
  Future<ClipData> editClip(
    DawHarness h,
    ClipData clip,
    AudioClipEditData edit,
  ) async {
    h.daw.onAudioClipEdited(clip.copyWith(editData: edit));
    await h.daw.onAudioClipEditFinished('Edit clip');
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

  testWidgets('export writes a repeating clip and reads back the result', (
    tester,
  ) async {
    // Found by Tyr: every export said "Couldn't export" although the file was
    // written (the screen read 'format', the engine sends
    // 'format_description').
    final h = await DawHarness.start(tester);
    try {
      final clip = await dropClip(h, 'loop.wav');
      h.engine.setClipDuration(clip.trackId, clip.clipId, clip.duration * 2);
      final out = '${Directory.systemTemp.createTempSync('export').path}/a.wav';
      var json = '';
      await h.realTime(() async {
        json = h.engine.exportWavWithOptions(outputPath: out);
      });
      final result = ExportResult.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(result.format, 'WAV 16-bit');
      expect(File(out).existsSync(), isTrue);
      // Two passes of the loop plus the one-second tail.
      expect(result.duration, closeTo(clip.duration * 2 + 1, 0.01));
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

  group('Audio Editor undo', () {
    /// What an undo step must put back: how the clip sounds and repeats.
    Object shape(ClipData c) => (
      c.offset,
      c.duration,
      c.loopStart,
      c.loopLength,
      c.canRepeat,
      c.editData,
    );

    /// Drop a clip, stretch it to two passes and open the editor on it.
    Future<(ClipData, AudioEditorControlsBar Function())> openStretched(
      WidgetTester tester,
      DawHarness h,
    ) async {
      final clip = await dropClip(h, 'loop.wav');
      final timeline = h.daw.timelineKey.currentState!;
      await timeline.resizeAudioClip(
        clip,
        clip.withEdges(
          start: clip.startTime,
          end: clip.startTime + clip.timelineSeconds(clip.loopLength * 2, 120),
          projectBpm: h.daw.tempo,
        ),
      );
      await h.settle();
      final callbacks = tester
          .widget<TimelineView>(find.byType(TimelineView))
          .audioClipCallbacks;
      final stretched = timeline.clips.single;
      callbacks.onSelected!(stretched.clipId, stretched);
      callbacks.onOpenEditor!();
      await h.settle();
      return (
        stretched,
        () => tester.widget<AudioEditorControlsBar>(
          find.byType(AudioEditorControlsBar),
        ),
      );
    }

    testWidgets('each loop change is one undo step that puts the clip back', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final (_, bar) = await openStretched(tester, h);
        final timeline = h.daw.timelineKey.currentState!;
        final steps = <(String, VoidCallback)>[
          ('Change loop length', () => bar().onLengthChanged!(2.0)),
          ('Move loop start', () => bar().onStartChanged!(1.0)),
          ('Turn loop off', () => bar().onLoopToggle!()),
          ('Turn loop on', () => bar().onLoopToggle!()),
        ];
        final shapes = [shape(timeline.clips.single)];
        for (final (what, change) in steps) {
          change();
          await h.settle();
          expect(h.daw.undoRedoManager.undoDescription, what);
          shapes.add(shape(timeline.clips.single));
          expect(shapes.last, isNot(shapes[shapes.length - 2]), reason: what);
          h.expectScreenMatchesEngine(after: what);
        }
        for (var i = steps.length - 1; i >= 0; i--) {
          await h.daw.performUndo();
          await h.settle();
          expect(shape(timeline.clips.single), shapes[i], reason: 'undo $i');
          h.expectScreenMatchesEngine(after: 'undoing ${steps[i].$1}');
        }
        for (var i = 0; i < steps.length; i++) {
          await h.daw.performRedo();
          await h.settle();
          expect(shape(timeline.clips.single), shapes[i + 1]);
          h.expectScreenMatchesEngine(after: 'redoing ${steps[i].$1}');
        }
      } finally {
        await h.close();
      }
    });

    testWidgets('Loop off ends a repeating clip where its audio does', (
      tester,
    ) async {
      // Found by the stress test: the clip kept its repeats' length and
      // played silence, and a trim could then cut it to nothing.
      final h = await DawHarness.start(tester);
      try {
        final (clip, bar) = await openStretched(tester, h);
        bar().onLoopToggle!();
        await h.settle();
        final timeline = h.daw.timelineKey.currentState!;
        final off = timeline.clips.single;
        expect(off.canRepeat, isFalse);
        expect(off.duration, closeTo(clip.loopLength, 1e-9), reason: '2 s');
        h.expectScreenMatchesEngine(after: 'turning Loop off');

        await h.daw.performUndo();
        await h.settle();
        expect(shape(timeline.clips.single), shape(clip));
        h.expectScreenMatchesEngine(after: 'undoing Loop off');
      } finally {
        await h.close();
      }
    });

    testWidgets('a loop drag is one undo step, made when it ends', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final (clip, bar) = await openStretched(tester, h);
        final manager = h.daw.undoRedoManager;
        final steps = manager.undoHistory.length;

        bar().onLengthDragStart!();
        for (final beats in [3.0, 2.5, 2.0]) {
          bar().onLengthChanged!(beats);
          await h.settle();
        }
        expect(manager.undoHistory, hasLength(steps), reason: 'mid-drag');
        bar().onLengthDragEnd!();
        await h.settle();
        expect(manager.undoHistory, hasLength(steps + 1));

        // The ruler's loop edges, likewise.
        final nav = tester.widget<UnifiedNavBar>(
          find.descendant(
            of: find.byType(AudioEditor),
            matching: find.byType(UnifiedNavBar),
          ),
        );
        nav.callbacks.onLoopRegionChanged!(0, 1.5);
        nav.callbacks.onLoopRegionChanged!(0, 1.0);
        await h.settle();
        nav.callbacks.onLoopRegionDragEnd!();
        await h.settle();
        expect(manager.undoHistory, hasLength(steps + 2));
        expect(manager.undoDescription, 'Change loop region');

        await h.daw.performUndo();
        await h.daw.performUndo();
        await h.settle();
        final now = h.daw.timelineKey.currentState!.clips.single;
        expect(shape(now), shape(clip));
        h.expectScreenMatchesEngine(after: 'undoing both drags');
      } finally {
        await h.close();
      }
    });

    testWidgets('undo works with the editor closed', (tester) async {
      final h = await DawHarness.start(tester);
      try {
        final (clip, bar) = await openStretched(tester, h);
        bar().onGainChanged!(-6);
        await h.settle();
        bar().onLengthChanged!(1.0);
        await h.settle();
        final callbacks = tester
            .widget<TimelineView>(find.byType(TimelineView))
            .audioClipCallbacks;
        callbacks.onSelected!(null, null);
        await h.settle();
        expect(find.byType(AudioEditor), findsNothing);

        await h.daw.performUndo();
        await h.daw.performUndo();
        await h.settle();
        final now = h.daw.timelineKey.currentState!.clips.single;
        expect(shape(now), shape(clip));
        h.expectScreenMatchesEngine(after: 'undoing with the editor closed');
      } finally {
        await h.close();
      }
    });

    testWidgets('the editor follows a trim made while it is open', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final (clip, bar) = await openStretched(tester, h);
        bar().onLengthChanged!(2.0); // repeat the first half: 1 s
        await h.settle();
        final timeline = h.daw.timelineKey.currentState!;
        final looped = timeline.clips.single;

        // Trim the left edge in by half a second: the loop's phase moves,
        // so the editor's region moves with it.
        await timeline.resizeAudioClip(
          looped,
          looped.withEdges(
            start: looped.startTime + 0.5,
            end: looped.timelineEnd(h.daw.tempo),
            projectBpm: h.daw.tempo,
          ),
        );
        await h.settle();
        final trimmed = timeline.clips.single;
        final editor = tester.widget<AudioEditor>(find.byType(AudioEditor));
        expect(identical(editor.clipData, trimmed), isTrue);
        expect(
          bar().startOffsetBeats,
          closeTo(trimmed.loopWindowStart * h.daw.tempo / 60, 1e-9),
        );
        expect(
          bar().lengthBeats,
          closeTo(trimmed.loopLength * h.daw.tempo / 60, 1e-9),
        );
        expect(clip.clipId, trimmed.clipId);
      } finally {
        await h.close();
      }
    });
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
        await editClip(h, clip, edit);
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

    testWidgets(
      'splitting a reversed or warped clip keeps what each part played',
      (tester) async {
        final h = await DawHarness.start(tester);
        try {
          final timeline = h.daw.timelineKey.currentState!;
          // A 2 s clip, split 0.5 s in. Reversed, the first 0.5 s on the
          // timeline is the file's last 0.5 s, so the left half keeps that.
          // Warped from 60 to 120 BPM (twice as fast), 0.5 s on the
          // timeline is the file's first 1 s. Each right half enters the
          // clip's loop where the cut is, so the loop stays put.
          final cases = [
            (
              'reversed',
              const AudioClipEditData(reversed: true),
              (left: (1.5, 0.0, 0.5), right: (0.0, 0.5, 1.5)),
            ),
            (
              'warped',
              const AudioClipEditData(syncEnabled: true, bpm: 60),
              (left: (0.0, 0.0, 1.0), right: (0.0, 1.0, 1.0)),
            ),
          ];
          for (final (what, edit, want) in cases) {
            final clip = await editClip(
              h,
              await dropClip(h, '$what.wav'),
              edit,
            );
            timeline.runAudioSplit(clip, clip.startTime + 0.5);
            await h.settle();
            final halves =
                timeline.clips.where((c) => c.trackId == clip.trackId).toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));
            (double, double, double) window(ClipData c) =>
                (c.offset, c.loopStart, c.duration);
            expect(halves.map(window).toList(), [
              want.left,
              want.right,
            ], reason: '$what: (offset, loop start, length) of each half');
            h.expectScreenMatchesEngine(after: 'splitting the $what clip');
          }
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
