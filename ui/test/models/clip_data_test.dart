import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';

import '../helpers/clip_audio.dart';

void main() {
  group('ClipData', () {
    group('timelineSeconds', () {
      test('a warped clip fills its own beats at any project tempo', () {
        // 4 bars at 150 BPM: 6.4 s of audio, always 16 beats on the timeline.
        final clip = ClipData(
          clipId: 1,
          trackId: 1,
          filePath: '/a.wav',
          startTime: 0,
          duration: 6.4,
          editData: const AudioClipEditData(bpm: 150, syncEnabled: true),
        );
        for (final bpm in [97.0, 120.0, 150.0, 170.0]) {
          final beats = clip.timelineSeconds(clip.duration, bpm) * bpm / 60;
          expect(beats, closeTo(16, 1e-9), reason: 'at $bpm BPM');
        }
      });

      test('an unwarped clip keeps its length in seconds', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 1,
          filePath: '/a.wav',
          startTime: 0,
          duration: 6.4,
        );
        expect(clip.timelineSeconds(6.4, 97), 6.4);
      });
    });

    group('constructor', () {
      test('creates instance with required fields', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 0.0,
          duration: 4.5,
        );

        expect(clip.clipId, 1);
        expect(clip.trackId, 2);
        expect(clip.filePath, '/audio/drums.wav');
        expect(clip.startTime, 0.0);
        expect(clip.duration, 4.5);
      });

      test('uses default values for optional fields', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 0.0,
          duration: 4.5,
        );

        expect(clip.offset, 0.0);
        expect(clip.waveformPeaks, isEmpty);
        expect(clip.color, isNull);
      });

      test('creates instance with all fields', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
          offset: 0.5,
          waveformPeaks: [0.1, 0.5, 0.8, 0.3],
          color: Colors.blue,
        );

        expect(clip.offset, 0.5);
        expect(clip.waveformPeaks, [0.1, 0.5, 0.8, 0.3]);
        expect(clip.color, Colors.blue);
      });
    });

    group('fileName', () {
      test('extracts file name from path', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/Users/test/Music/drums.wav',
          startTime: 0.0,
          duration: 4.5,
        );

        expect(clip.fileName, 'drums.wav');
      });

      test('extracts file name from nested path', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/deep/nested/path/to/audio/beat.mp3',
          startTime: 0.0,
          duration: 4.5,
        );

        expect(clip.fileName, 'beat.mp3');
      });

      test('handles file name only (no path)', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: 'sample.wav',
          startTime: 0.0,
          duration: 4.5,
        );

        expect(clip.fileName, 'sample.wav');
      });

      test('handles empty file path', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '',
          startTime: 0.0,
          duration: 4.5,
        );

        expect(clip.fileName, '');
      });
    });

    group('timelineEnd', () {
      test('a warped clip ends where its stretched length does', () {
        // 6.4 s of 150 BPM audio warped to 120 BPM fills 8 s.
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 6.4,
          editData: const AudioClipEditData(bpm: 150, syncEnabled: true),
        );

        expect(clip.timelineLength(120), closeTo(8.0, 1e-9));
        expect(clip.timelineEnd(120), closeTo(10.0, 1e-9));
      });

      test('calculates end time correctly', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        expect(clip.timelineEnd(120), 6.5);
      });

      test('returns startTime when duration is 0', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 3.0,
          duration: 0.0,
        );

        expect(clip.timelineEnd(120), 3.0);
      });

      test('calculates end time for clip at start', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 0.0,
          duration: 10.0,
        );

        expect(clip.timelineEnd(120), 10.0);
      });
    });

    group('copyWith', () {
      test('copies all fields when none specified', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
          offset: 0.5,
          waveformPeaks: [0.1, 0.5],
          color: Colors.red,
        );

        final copy = original.copyWith();

        expect(copy.clipId, original.clipId);
        expect(copy.trackId, original.trackId);
        expect(copy.filePath, original.filePath);
        expect(copy.startTime, original.startTime);
        expect(copy.duration, original.duration);
        expect(copy.offset, original.offset);
        expect(copy.waveformPeaks, original.waveformPeaks);
        expect(copy.color, original.color);
      });

      test('updates clipId only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        final copy = original.copyWith(clipId: 99);

        expect(copy.clipId, 99);
        expect(copy.trackId, 2);
        expect(copy.filePath, '/audio/drums.wav');
      });

      test('updates trackId only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        final copy = original.copyWith(trackId: 5);

        expect(copy.clipId, 1);
        expect(copy.trackId, 5);
      });

      test('updates filePath only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        final copy = original.copyWith(filePath: '/new/path.wav');

        expect(copy.filePath, '/new/path.wav');
        expect(copy.clipId, 1);
      });

      test('updates startTime only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        final copy = original.copyWith(startTime: 8.0);

        expect(copy.startTime, 8.0);
        expect(copy.duration, 4.5);
      });

      test('updates duration only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        final copy = original.copyWith(duration: 10.0);

        expect(copy.duration, 10.0);
        expect(copy.startTime, 2.0);
      });

      test('updates offset only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
          offset: 0.0,
        );

        final copy = original.copyWith(offset: 1.5);

        expect(copy.offset, 1.5);
      });

      test('updates waveformPeaks only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
          waveformPeaks: [0.1, 0.2],
        );

        final copy = original.copyWith(waveformPeaks: [0.5, 0.6, 0.7]);

        expect(copy.waveformPeaks, [0.5, 0.6, 0.7]);
      });

      test('updates color only', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
          color: Colors.blue,
        );

        final copy = original.copyWith(color: Colors.green);

        expect(copy.color, Colors.green);
      });

      test('updates multiple fields', () {
        final original = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        final copy = original.copyWith(
          startTime: 10.0,
          duration: 8.0,
          trackId: 5,
        );

        expect(copy.startTime, 10.0);
        expect(copy.duration, 8.0);
        expect(copy.trackId, 5);
        expect(copy.clipId, 1); // unchanged
        expect(copy.filePath, '/audio/drums.wav'); // unchanged
      });
    });

    group('edge cases', () {
      test('handles very long duration', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/long.wav',
          startTime: 0.0,
          duration: 3600.0, // 1 hour
        );

        expect(clip.timelineEnd(120), 3600.0);
      });

      test('handles fractional times', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 1.333,
          duration: 2.666,
        );

        expect(clip.timelineEnd(120), closeTo(3.999, 0.001));
      });

      test('handles empty waveform peaks', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 0.0,
          duration: 4.5,
          waveformPeaks: [],
        );

        expect(clip.waveformPeaks, isEmpty);
      });

      test('handles large waveform peaks array', () {
        final peaks = List.generate(10000, (i) => i / 10000.0);
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 0.0,
          duration: 4.5,
          waveformPeaks: peaks,
        );

        expect(clip.waveformPeaks.length, 10000);
      });
    });
  });

  group('repeating clips', () {
    ClipData clip({
      double offset = 0.5,
      double duration = 3.5,
      double loopLength = 1.0,
      double loopStart = 0.0,
      bool canRepeat = true,
      bool reversed = false,
    }) => ClipData(
      clipId: 1,
      trackId: 1,
      filePath: '/a.wav',
      startTime: 10.0,
      duration: duration,
      offset: offset,
      loopLength: loopLength,
      loopStart: loopStart,
      canRepeat: canRepeat,
      editData: AudioClipEditData(reversed: reversed),
    );

    test('a clip repeats when longer than its loop or starting into it', () {
      expect(clip().isLooped, isTrue);
      expect(clip(duration: 1.0).isLooped, isFalse);
      expect(clip(duration: 0.75, loopStart: 0.5).isLooped, isTrue);
      expect(clip(canRepeat: false).isLooped, isFalse);
      // Float noise from beat/second conversions doesn't count.
      expect(clip(duration: 1.0 + 1e-12).isLooped, isFalse);
    });

    test('the engine is told the loop only when the clip can repeat', () {
      expect(clip().engineLoopLength, 1.0);
      expect(clip(canRepeat: false).engineLoopLength, 0.0);
    });

    test('splitting mid-loop: the right piece carries the pattern on', () {
      final s = clip().splitAt(12.25, 120); // 2.25 s in: a quarter into pass 3
      expect(s.leftOffset, 0.5);
      expect(s.leftDuration, 2.25);
      expect(s.leftLoopStart, 0.0);
      expect(s.rightOffset, 0.5);
      expect(s.rightDuration, 1.25);
      expect(s.rightLoopStart, closeTo(0.25, 1e-9));
    });

    test('a piece inside one pass keeps its place in the loop', () {
      // Cut 0.25 s in, starting half way into a 1 s loop.
      final s = clip(loopStart: 0.5).splitAt(10.25, 120);
      expect((s.leftOffset, s.leftLoopStart), (0.5, 0.5));
      expect(s.rightLoopStart, closeTo(0.75, 1e-9));
      final r = clip(loopStart: 0.5, reversed: true).splitAt(10.25, 120);
      expect((r.leftOffset, r.leftLoopStart), (0.5, 0.5));
    });

    test('a cut on a loop boundary starts the right piece at the top', () {
      final s = clip().splitAt(12.0, 120);
      expect(s.rightLoopStart, 0.0);
      expect(s.rightOffset, 0.5, reason: 'still longer than the loop');
    });

    test('a clip that does not repeat yet: pieces keep their audio', () {
      final whole = clip(duration: 1.0, loopLength: 4.0);
      final s = whole.splitAt(10.25, 120);
      expect((s.leftOffset, s.leftLoopStart), (0.5, 0.0));
      // The right piece enters the loop a quarter second in, so stretching
      // it later repeats the same loop.
      expect((s.rightOffset, s.rightLoopStart), (0.5, 0.25));
      final r = clip(duration: 1.0, loopLength: 4.0, reversed: true);
      final rs = r.splitAt(10.25, 120);
      // Reversed, the left piece plays the window's end: 1.5 s back to 1.25.
      final left = r.copyWith(
        offset: rs.leftOffset,
        duration: rs.leftDuration,
        loopStart: rs.leftLoopStart,
      );
      expect(audioAt(left, 0.1), closeTo(audioAt(r, 0.1), 1e-9));
      expect(audioAt(left, 0.1), closeTo(1.4, 1e-9));
    });

    test('a clip that can not repeat splits its own window', () {
      final s = clip(duration: 1.0, canRepeat: false).splitAt(10.25, 120);
      expect((s.leftOffset, s.rightOffset), (0.5, 0.75));
      expect((s.leftLoopStart, s.rightLoopStart), (0.0, 0.0));
      final r = clip(
        duration: 1.0,
        canRepeat: false,
        reversed: true,
      ).splitAt(10.25, 120);
      expect((r.leftOffset, r.rightOffset), (1.25, 0.5));
    });

    test('loop start is saved with the project', () {
      final back = ClipData.fromJson(clip(loopStart: 0.25).toJson());
      expect(back.loopStart, 0.25);
      expect(ClipData.fromJson(clip().toJson()).loopStart, 0.0);
    });
  });

  group('moving edges', () {
    ClipData clip({
      double offset = 0.0,
      double duration = 4.0,
      double? loopLength,
      double loopStart = 0.0,
      bool canRepeat = true,
      bool reversed = false,
      bool warped = false,
    }) => ClipData(
      clipId: 1,
      trackId: 1,
      filePath: '/a.wav',
      startTime: 10.0,
      duration: duration,
      offset: offset,
      loopLength: loopLength ?? duration,
      loopStart: loopStart,
      canRepeat: canRepeat,
      // 240 BPM audio warped to 120 BPM plays at half speed.
      editData: AudioClipEditData(
        reversed: reversed,
        bpm: 240,
        syncEnabled: warped,
      ),
    );

    test('a reversed clip loses the end of its audio from its left edge', () {
      for (final canRepeat in [true, false]) {
        final r = clip(reversed: true, canRepeat: canRepeat);
        final trimmed = r.withEdges(start: 11, end: 14, projectBpm: 120);
        expect(trimmed.startTime, 11);
        expect(trimmed.duration, 3);
        // What played at 12 s still does: 2 s into a 4 s reversed clip.
        expect(audioAt(trimmed, 1.0), closeTo(2.0, 1e-9));
        expect(audioAt(r, 2.0), closeTo(2.0, 1e-9));
      }
    });

    test(
      'a reversed clip loses the start of its audio from its right edge',
      () {
        for (final canRepeat in [true, false]) {
          final r = clip(reversed: true, canRepeat: canRepeat);
          final trimmed = r.withEdges(start: 10, end: 13, projectBpm: 120);
          expect(trimmed.offset, closeTo(1.0, 1e-9), reason: '$canRepeat');
          expect(audioAt(trimmed, 0.5), closeTo(3.5, 1e-9));
        }
      },
    );

    test('dragging an edge back out brings the clip back', () {
      for (final reversed in [false, true]) {
        for (final canRepeat in [true, false]) {
          final c = clip(reversed: reversed, canRepeat: canRepeat);
          final back = c
              .withEdges(start: 11.5, end: 13, projectBpm: 120)
              .withEdges(start: 10, end: 14, projectBpm: 120);
          final what = 'reversed $reversed, repeat $canRepeat';
          expect(back.startTime, 10, reason: what);
          expect(back.duration, closeTo(4, 1e-9), reason: what);
          expect(back.offset, closeTo(0, 1e-9), reason: what);
          expect(back.loopStart, 0, reason: what);
        }
      }
    });

    test('a repeating clip keeps its pattern when its left edge moves', () {
      // A 1 s loop repeated four times.
      final c = clip(duration: 4, loopLength: 1, offset: 0.5);
      final trimmed = c.withEdges(start: 10.25, end: 14, projectBpm: 120);
      expect(trimmed.offset, 0.5, reason: 'the loop stays put');
      expect(trimmed.loopStart, closeTo(0.25, 1e-9));
      for (final t in [10.3, 11.6, 13.95]) {
        expect(
          audioAt(trimmed, t - trimmed.startTime),
          closeTo(audioAt(c, t - c.startTime), 1e-9),
        );
      }
    });

    test('with Loop on, the left edge dragged out repeats backwards', () {
      final c = clip(duration: 4);
      final out = c.withEdges(start: 9, end: 14, projectBpm: 120);
      expect(out.startTime, 9);
      expect(out.duration, 5);
      expect(out.loopStart, closeTo(3, 1e-9));
      // The extra second is the audio's last second; the rest hasn't moved.
      expect(audioAt(out, 0.5), closeTo(3.5, 1e-9));
      expect(audioAt(out, 2.5), closeTo(1.5, 1e-9));
    });

    test('with Loop off, edges stop at the ends of the audio', () {
      final c = clip(offset: 1, duration: 2, canRepeat: false);
      final out = c.withEdges(
        start: 8,
        end: 16,
        projectBpm: 120,
        audioSeconds: 5,
      );
      expect(out.startTime, 9, reason: 'only 1 s of audio before it');
      expect((out.offset, out.duration), (0.0, 5.0));
      // Reversed, the left edge uncovers the audio after the window.
      final r = clip(offset: 1, duration: 2, canRepeat: false, reversed: true);
      final rOut = r.withEdges(
        start: 8,
        end: 16,
        projectBpm: 120,
        audioSeconds: 5,
      );
      expect(rOut.startTime, 8, reason: '2 s of audio after the window');
      expect((rOut.offset, rOut.duration), (0.0, 5.0));
    });

    test("a warped clip moves by its own seconds, not the timeline's", () {
      // Warped to half speed, 1 s on the timeline is 0.5 s of audio.
      final c = clip(warped: true, canRepeat: false);
      final trimmed = c.withEdges(start: 11, end: 18, projectBpm: 120);
      expect(trimmed.offset, closeTo(0.5, 1e-9));
      expect(trimmed.duration, closeTo(3.5, 1e-9));
      expect(trimmed.timelineEnd(120), closeTo(18, 1e-9));
    });

    test('turning Loop off keeps a clip that starts into its loop', () {
      for (final reversed in [false, true]) {
        final c = clip(
          offset: 0.5,
          duration: 1,
          loopLength: 2,
          loopStart: 0.75,
          reversed: reversed,
        );
        final off = c.copyWith(canRepeat: false).asOneWindow();
        for (final x in [0.1, 0.5, 0.9]) {
          expect(
            audioAt(off, x),
            closeTo(audioAt(c, x), 1e-9),
            reason: 'reversed $reversed at $x',
          );
        }
      }
    });

    test('whatever moves, the audio under what stays never changes', () {
      final random = math.Random(7);
      double between(double a, double b) => a + random.nextDouble() * (b - a);
      for (var i = 0; i < 2000; i++) {
        final loopLength = between(0.5, 3);
        final canRepeat = random.nextBool();
        final duration = between(0.2, canRepeat ? 6 : 4);
        final c = clip(
          offset: between(0, 2),
          duration: duration,
          loopLength: loopLength,
          loopStart: canRepeat && random.nextBool()
              ? between(0, loopLength)
              : 0.0,
          canRepeat: canRepeat,
          reversed: random.nextBool(),
          warped: random.nextBool(),
        );
        final end = c.timelineEnd(120);
        final start = between(c.startTime - 2, end - 0.1);
        final moved = c.withEdges(
          start: start,
          end: between(start + 0.05, end + 2),
          projectBpm: 120,
          audioSeconds: 10,
        );
        final stretch = c.editData!.stretchAt(120);
        final from = math.max(c.startTime, moved.startTime);
        final to = math.min(end, moved.timelineEnd(120));
        for (var k = 0; k < 8 && to > from; k++) {
          final t = between(from, to);
          expect(
            audioAt(moved, (t - moved.startTime) * stretch),
            closeTo(audioAt(c, (t - c.startTime) * stretch), 1e-6),
            reason: 'case $i at $t: $c → $moved',
          );
        }
      }
    });
  });

  group('PreviewClip', () {
    group('constructor', () {
      test('creates instance with all required fields', () {
        const preview = PreviewClip(
          fileName: 'drums.wav',
          filePath: '/path/to/drums.wav',
          startTime: 2.0,
          trackId: 3,
          mousePosition: Offset(100.0, 200.0),
        );

        expect(preview.fileName, 'drums.wav');
        expect(preview.startTime, 2.0);
        expect(preview.trackId, 3);
        expect(preview.mousePosition, const Offset(100.0, 200.0));
      });

      test('handles zero values', () {
        const preview = PreviewClip(
          fileName: 'sample.wav',
          filePath: '/path/to/sample.wav',
          startTime: 0.0,
          trackId: 0,
          mousePosition: Offset.zero,
        );

        expect(preview.startTime, 0.0);
        expect(preview.trackId, 0);
        expect(preview.mousePosition, Offset.zero);
      });

      test('handles negative mouse position', () {
        const preview = PreviewClip(
          fileName: 'sample.wav',
          filePath: '/path/to/sample.wav',
          startTime: 0.0,
          trackId: 1,
          mousePosition: Offset(-10.0, -20.0),
        );

        expect(preview.mousePosition.dx, -10.0);
        expect(preview.mousePosition.dy, -20.0);
      });
    });
  });
}
