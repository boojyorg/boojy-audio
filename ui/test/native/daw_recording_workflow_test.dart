import 'package:boojy_audio/controllers/recording_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';
import 'support/workflow_helpers.dart';

// Recording workflows through the real DAW screen and engine (see
// daw_workflow_test.dart).

void main() {
  if (skipWithoutNativeEngine('DAW recording workflows')) return;

  // Recording needs a real input, which the test machines don't have: the
  // engine's takes are stood in for by clips loaded where the recorder puts
  // them, and the DAW gets the result as stopping a recording hands it over.
  group('recording', () {
    /// A take of [seconds] on [trackId] at [start], as the recorder adds it
    /// (its audio is exactly as long as the take).
    int take(DawHarness h, int trackId, double start, double seconds) =>
        h.engine.loadAudioFileToTrack(
          h.writeClickWav('take_${trackId}_$start.wav', seconds: seconds),
          trackId,
          startTime: start,
        );

    Future<void> finishRecording(DawHarness h, List<int> takes) async {
      h.daw.handleRecordingComplete(
        RecordingResult(
          audioClipId: takes.first,
          audioTakes: {for (final id in takes) id: const <double>[]},
        ),
      );
      await h.settle();
    }

    testWidgets('two armed tracks each keep their take; one undo for both', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final timeline = h.daw.timelineKey.currentState!;
        final a = (await dropClip(h, 'a.wav')).trackId;
        final b = (await dropClip(h, 'b.wav')).trackId;
        expect(a, isNot(b));
        final takes = [take(h, a, 4, 1), take(h, b, 4, 1)];
        await finishRecording(h, takes);

        expect(
          timeline.clips.map((c) => c.clipId),
          containsAll(takes),
          reason: 'every take shows',
        );
        expect(h.daw.undoRedoManager.undoDescription, 'Record');
        h.expectScreenMatchesEngine(after: 'recording two tracks');

        await h.daw.performUndo();
        await h.settle();
        expect(timeline.clips.map((c) => c.clipId), isNot(contains(takes[0])));
        expect(timeline.clips.map((c) => c.clipId), isNot(contains(takes[1])));
        expect(timeline.clips, hasLength(2));
        h.expectScreenMatchesEngine(after: 'undoing the recording');

        await h.daw.performRedo();
        await h.settle();
        expect(timeline.clips.map((c) => c.clipId), containsAll(takes));
        h.expectScreenMatchesEngine(after: 'redoing the recording');
      } finally {
        await h.close();
      }
    });

    testWidgets('undoing a take brings back the repeating clip under it', (
      tester,
    ) async {
      final h = await DawHarness.start(tester);
      try {
        final timeline = h.daw.timelineKey.currentState!;
        final clip = await dropClip(h, 'loop.wav'); // 2 s, from 0
        await timeline.resizeAudioClip(
          clip,
          clip.withEdges(start: 0, end: 4, projectBpm: h.daw.tempo),
        );
        await h.settle();
        final repeating = timeline.clips.single;
        expect(repeating.isLooped, isTrue);

        // A take from 1 s to 2.5 s cuts it in two.
        final id = take(h, clip.trackId, 1, 1.5);
        await finishRecording(h, [id]);
        expect(timeline.clips, hasLength(3));
        h.expectScreenMatchesEngine(after: 'recording over it');

        await h.daw.performUndo();
        await h.settle();
        final back = timeline.clips.single;
        expect(back.clipId, repeating.clipId);
        expect(
          (back.offset, back.duration, back.loopStart, back.loopLength),
          (
            repeating.offset,
            repeating.duration,
            repeating.loopStart,
            repeating.loopLength,
          ),
        );
        h.expectScreenMatchesEngine(after: 'undoing the take');

        await h.daw.performRedo();
        await h.settle();
        expect(timeline.clips, hasLength(3));
        h.expectScreenMatchesEngine(after: 'redoing the take');
      } finally {
        await h.close();
      }
    });
  });
}
