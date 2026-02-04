import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/clip_data.dart';

void main() {
  group('ClipData', () {
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

    group('endTime', () {
      test('calculates end time correctly', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 2.0,
          duration: 4.5,
        );

        expect(clip.endTime, 6.5);
      });

      test('returns startTime when duration is 0', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 3.0,
          duration: 0.0,
        );

        expect(clip.endTime, 3.0);
      });

      test('calculates end time for clip at start', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 0.0,
          duration: 10.0,
        );

        expect(clip.endTime, 10.0);
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

        expect(clip.endTime, 3600.0);
      });

      test('handles fractional times', () {
        final clip = ClipData(
          clipId: 1,
          trackId: 2,
          filePath: '/audio/drums.wav',
          startTime: 1.333,
          duration: 2.666,
        );

        expect(clip.endTime, closeTo(3.999, 0.001));
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

  group('PreviewClip', () {
    group('constructor', () {
      test('creates instance with all required fields', () {
        final preview = PreviewClip(
          fileName: 'drums.wav',
          filePath: '/path/to/drums.wav',
          startTime: 2.0,
          trackId: 3,
          mousePosition: const Offset(100.0, 200.0),
        );

        expect(preview.fileName, 'drums.wav');
        expect(preview.startTime, 2.0);
        expect(preview.trackId, 3);
        expect(preview.mousePosition, const Offset(100.0, 200.0));
      });

      test('handles zero values', () {
        final preview = PreviewClip(
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
        final preview = PreviewClip(
          fileName: 'sample.wav',
          filePath: '/path/to/sample.wav',
          startTime: 0.0,
          trackId: 1,
          mousePosition: const Offset(-10.0, -20.0),
        );

        expect(preview.mousePosition.dx, -10.0);
        expect(preview.mousePosition.dy, -20.0);
      });
    });
  });
}
