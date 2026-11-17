import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/widgets/editor_panel.dart';
import 'package:boojy_audio/widgets/piano_roll.dart';
import 'package:boojy_audio/widgets/piano_roll/operations/note_operations.dart';
import 'package:boojy_audio/widgets/piano_roll/piano_roll_controls_bar.dart';
import 'package:boojy_audio/widgets/shared/editors/unified_nav_bar.dart';
import 'package:boojy_audio/widgets/timeline/timeline_models.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

// Piano Roll undo through the real DAW screen and engine (see
// daw_workflow_test.dart).

void main() {
  if (!isNativeEngineAvailable) {
    test('DAW Piano Roll undo (native engine)', () {}, skip: true);
    return;
  }

  group('Piano Roll undo', () {
    /// What an undo step must put back: where the loop is, how the clip
    /// repeats, and its notes.
    Object shape(MidiClipData c) => (
      c.contentStartOffset,
      c.loopLength,
      c.duration,
      c.canRepeat,
      c.notes.length,
    );

    MidiClipData clipNow(DawHarness h, int clipId) => h
        .daw
        .midiPlaybackManager!
        .midiClips
        .firstWhere((c) => c.clipId == clipId);

    MidiClipCallbacks midiCallbacks(WidgetTester tester) => tester
        .widget<TimelineView>(find.byType(TimelineView))
        .midiClipCallbacks;

    NoteOperationsMixin roll(WidgetTester tester) =>
        tester.state(find.byType(PianoRoll)) as NoteOperationsMixin;

    PianoRollControlsBar bar(WidgetTester tester) =>
        tester.widget<PianoRollControlsBar>(find.byType(PianoRollControlsBar));

    /// Add a MIDI track, give its clip a 4-bar loop and one note, and open
    /// it in the Piano Roll.
    Future<MidiClipData> openPianoRoll(
      WidgetTester tester,
      DawHarness h, {
      double loopStart = 0,
      double loopLength = 16,
      double duration = 16,
    }) async {
      await tester.tap(find.text('MIDI').first);
      await h.settle();
      final manager = h.daw.midiPlaybackManager!;
      h.daw.midiClipController.updateClip(
        manager.midiClips.single.copyWith(
          contentStartOffset: loopStart,
          loopLength: loopLength,
          duration: duration,
          notes: [
            MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
          ],
        ),
        0,
      );
      await h.settle();
      final clip = manager.midiClips.single;
      midiCallbacks(tester).onSelected!(clip.clipId, clip);
      midiCallbacks(tester).onOpenEditor!();
      await h.settle();
      if (find.byType(PianoRoll).evaluate().isEmpty) {
        await tester.tap(
          find.descendant(
            of: find.byType(EditorPanel),
            matching: find.text('MIDI'),
          ),
        );
        await h.settle();
      }
      expect(find.byType(PianoRoll), findsOneWidget);
      return clip;
    }

    testWidgets('each loop change is one undo step that puts the clip back', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final clip = await openPianoRoll(tester, h);
        final steps = <(String, VoidCallback)>[
          ('Change loop length', () => bar(tester).onLoopLengthChanged!(8)),
          ('Move loop start', () => bar(tester).onLoopStartChanged!(4)),
          ('Turn loop off', () => bar(tester).onLoopToggle!()),
          ('Turn loop on', () => bar(tester).onLoopToggle!()),
        ];
        final shapes = [shape(clip)];
        for (final (what, change) in steps) {
          change();
          await h.settle();
          expect(h.daw.undoRedoManager.undoDescription, what);
          shapes.add(shape(clipNow(h, clip.clipId)));
          expect(shapes.last, isNot(shapes[shapes.length - 2]), reason: what);
          h.expectScreenMatchesEngine(after: what);
        }
        for (var i = steps.length - 1; i >= 0; i--) {
          await h.daw.performUndo();
          await h.settle();
          expect(shape(clipNow(h, clip.clipId)), shapes[i], reason: 'undo $i');
          // The open Piano Roll shows the loop that was put back.
          final now = clipNow(h, clip.clipId);
          expect(bar(tester).loopStartBeats, now.contentStartOffset);
          expect(bar(tester).loopLengthBeats, now.loopLength);
          h.expectScreenMatchesEngine(after: 'undoing ${steps[i].$1}');
        }
        for (var i = 0; i < steps.length; i++) {
          await h.daw.performRedo();
          await h.settle();
          expect(shape(clipNow(h, clip.clipId)), shapes[i + 1]);
          h.expectScreenMatchesEngine(after: 'redoing ${steps[i].$1}');
        }
      } finally {
        await h.close();
      }
    });

    testWidgets("Start moves the loop's beginning and keeps its end", (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final clip = await openPianoRoll(tester, h);
        bar(tester).onLoopStartChanged!(4);
        await h.settle();
        final moved = clipNow(h, clip.clipId);
        expect(moved.contentStartOffset, 4);
        expect(moved.loopLength, 12, reason: 'the end stays at beat 16');
        expect(bar(tester).loopLengthBeats, 12);
        h.expectScreenMatchesEngine(after: 'moving the loop start');
      } finally {
        await h.close();
      }
    });

    testWidgets('dragging Start out and back keeps the clip repeating', (
      tester,
    ) async {
      // Review of #205: once the loop covered the whole clip mid-drag, the
      // clip counted as not repeating and its arrangement length followed
      // the loop back down, losing the repeats.
      final h = await DawHarness.start(tester);
      try {
        final clip = await openPianoRoll(
          tester,
          h,
          loopStart: 8,
          loopLength: 8,
          duration: 16,
        );
        final steps = h.daw.undoRedoManager.undoHistory.length;
        bar(tester).onLoopStartDragStart!();
        for (final beats in [4.0, 0.0, 4.0, 8.0]) {
          bar(tester).onLoopStartChanged!(beats);
          await h.settle();
        }
        bar(tester).onLoopStartDragEnd!();
        await h.settle();
        expect(shape(clipNow(h, clip.clipId)), shape(clip));
        expect(
          h.daw.undoRedoManager.undoHistory,
          hasLength(steps),
          reason: 'a drag that ends where it began is no undo step',
        );
        h.expectScreenMatchesEngine(after: 'dragging Start out and back');
      } finally {
        await h.close();
      }
    });

    testWidgets('a typed Start is not moved by a coarse grid', (tester) async {
      // Review of #205: the grid size was used as the shortest loop, so on
      // a 1-bar grid Start = 0.25 on a 1-beat loop became 0 and the loop
      // grew to 4 beats, moving the end Start promises to keep.
      final h = await DawHarness.start(tester);
      try {
        final clip = await openPianoRoll(tester, h, loopLength: 1, duration: 1);
        bar(tester).onGridDivisionChanged!(4.0);
        if (bar(tester).snapEnabled) bar(tester).onSnapToggle!();
        await h.settle();
        bar(tester).onLoopStartChanged!(0.25);
        await h.settle();
        final now = clipNow(h, clip.clipId);
        expect(now.contentStartOffset, 0.25);
        expect(now.loopLength, 0.75, reason: 'the end stays at beat 1');
        h.expectScreenMatchesEngine(after: 'typing Start on a coarse grid');
      } finally {
        await h.close();
      }
    });

    testWidgets('a loop drag is one undo step, made when it ends', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final clip = await openPianoRoll(tester, h);
        final manager = h.daw.undoRedoManager;
        final steps = manager.undoHistory.length;

        bar(tester).onLoopLengthDragStart!();
        for (final beats in [12.0, 10.0, 8.0]) {
          bar(tester).onLoopLengthChanged!(beats);
          await h.settle();
        }
        expect(manager.undoHistory, hasLength(steps), reason: 'mid-drag');
        bar(tester).onLoopLengthDragEnd!();
        await h.settle();
        expect(manager.undoHistory, hasLength(steps + 1));
        expect(manager.undoDescription, 'Change loop length');

        // The ruler's loop edges, likewise.
        final nav = tester.widget<UnifiedNavBar>(
          find.descendant(
            of: find.byType(PianoRoll),
            matching: find.byType(UnifiedNavBar),
          ),
        );
        nav.callbacks.onLoopRegionChanged!(0, 6);
        nav.callbacks.onLoopRegionChanged!(0, 4);
        await h.settle();
        expect(manager.undoHistory, hasLength(steps + 1), reason: 'mid-drag');
        nav.callbacks.onLoopRegionDragEnd!();
        await h.settle();
        expect(manager.undoHistory, hasLength(steps + 2));
        expect(manager.undoDescription, 'Change loop region');

        await h.daw.performUndo();
        await h.daw.performUndo();
        await h.settle();
        expect(shape(clipNow(h, clip.clipId)), shape(clip));
        h.expectScreenMatchesEngine(after: 'undoing both drags');
      } finally {
        await h.close();
      }
    });

    testWidgets('undo works with the editor panel closed', (tester) async {
      final h = await DawHarness.start(tester);
      try {
        final clip = await openPianoRoll(tester, h);
        roll(tester).deleteNote(clip.notes.single);
        await h.settle();
        expect(clipNow(h, clip.clipId).notes, isEmpty);
        tester
            .widget<EditorPanel>(find.byType(EditorPanel))
            .callbacks
            .onClosePanel!();
        await h.settle();
        expect(find.byType(PianoRoll), findsNothing);

        await h.daw.performUndo();
        await h.settle();
        expect(clipNow(h, clip.clipId).notes, hasLength(1));
        h.expectScreenMatchesEngine(after: 'undoing with the panel closed');
      } finally {
        await h.close();
      }
    });

    testWidgets('undo after switching clips keeps the Piano Roll on the '
        'selected clip', (tester) async {
      final h = await DawHarness.start(tester);
      try {
        final a = await openPianoRoll(tester, h);
        await h.daw.createMidiClipWithParams(a.trackId, 32, 4);
        await h.settle();
        final b = h.daw.midiPlaybackManager!.midiClips.firstWhere(
          (c) => c.clipId != a.clipId,
        );
        midiCallbacks(tester).onSelected!(a.clipId, clipNow(h, a.clipId));
        await h.settle();
        roll(tester).deleteNote(clipNow(h, a.clipId).notes.single);
        await h.settle();
        midiCallbacks(tester).onSelected!(b.clipId, clipNow(h, b.clipId));
        await h.settle();

        await h.daw.performUndo();
        await h.settle();
        expect(clipNow(h, a.clipId).notes, hasLength(1));
        expect(roll(tester).currentClip?.clipId, b.clipId);
        expect(clipNow(h, b.clipId).notes, isEmpty);
        h.expectScreenMatchesEngine(after: 'undoing after switching clips');
      } finally {
        await h.close();
      }
    });
  });
}
