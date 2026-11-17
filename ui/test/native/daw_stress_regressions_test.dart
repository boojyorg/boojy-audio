import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';
import 'support/workflow_helpers.dart';

// Workflow tests through the real DAW screen and engine (see
// daw_workflow_test.dart).

void main() {
  if (!isNativeEngineAvailable) {
    test('DAW stress regressions (native engine)', () {}, skip: true);
    return;
  }

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
