import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor_controls_bar.dart';
import 'package:boojy_audio/widgets/shared/editors/unified_nav_bar.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';
import 'support/workflow_helpers.dart';

// Audio Editor undo through the real DAW screen and engine (see
// daw_workflow_test.dart).

void main() {
  if (skipWithoutNativeEngine('DAW Audio Editor undo')) return;

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
}
