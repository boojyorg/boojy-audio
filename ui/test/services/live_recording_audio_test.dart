import 'package:boojy_audio/models/live_peaks.dart';
import 'package:boojy_audio/services/live_recording_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

LivePeaksChunk chunk(int total, List<(double, double)> peaks) => LivePeaksChunk(
  total: total,
  left: [for (final p in peaks) p.$1],
  right: [for (final p in peaks) p.$2],
);

void main() {
  group('LivePeaksChunk.parse', () {
    test('reads the total and left/right pairs', () {
      final c = LivePeaksChunk.parse('3|0.100,0.200,0.300,0.400');
      expect(c.total, 3);
      expect(c.left, [0.1, 0.3]);
      expect(c.right, [0.2, 0.4]);
    });

    test('no new peaks yet', () {
      final c = LivePeaksChunk.parse('7|');
      expect(c.total, 7);
      expect(c.left, isEmpty);
    });

    test('garbage is empty', () {
      expect(LivePeaksChunk.parse('Error').total, 0);
      expect(LivePeaksChunk.parse('').left, isEmpty);
    });
  });

  group('LiveRecordingNotifier audio takes', () {
    late LiveRecordingNotifier notifier;

    setUp(() {
      notifier = LiveRecordingNotifier();
      notifier.startAudio(
        startSeconds: 2.0,
        tracks: [
          (trackId: 1, channel: 0, name: 'Vocal'),
          (trackId: 2, channel: 1, name: 'Guitar'),
        ],
      );
    });

    test('no clip until the first peak arrives', () {
      expect(notifier.buildLiveAudioClips(), isEmpty);
    });

    test('one growing clip per armed audio track', () {
      notifier.addPeaks(chunk(2, [(0.5, 0.1), (0.25, 0.2)]));
      final clips = notifier.buildLiveAudioClips();

      expect(clips.map((c) => c.trackId), [1, 2]);
      expect(clips.first.startTime, 2.0);
      expect(clips.first.duration, closeTo(0.02, 1e-9));
      expect(clips.map((c) => c.clipId).toSet().length, 2);
      expect(
        clips.every((c) => LiveRecordingNotifier.isLiveAudioClipId(c.clipId)),
        isTrue,
      );
    });

    test('each track draws its own input channel as min/max pairs', () {
      notifier.addPeaks(chunk(1, [(0.5, 0.1)]));
      final clips = notifier.buildLiveAudioClips();
      expect(clips[0].waveformPeaks, [-0.5, 0.5]); // In 1 = left
      expect(clips[1].waveformPeaks, [-0.1, 0.1]); // In 2 = right
    });

    test('new peaks append and are asked for from where we left off', () {
      notifier.addPeaks(chunk(1, [(0.5, 0.1)]));
      notifier.addPeaks(chunk(3, [(0.2, 0.2), (0.3, 0.3)]));
      expect(notifier.peaksFetched, 3);
      expect(
        notifier.buildLiveAudioClips().first.duration,
        closeTo(0.03, 1e-9),
      );
    });

    test('a smaller engine total means a new take: start over', () {
      notifier.addPeaks(chunk(3, [(0.5, 0.1), (0.5, 0.1), (0.5, 0.1)]));
      notifier.addPeaks(chunk(1, [(0.9, 0.9)]));
      final clip = notifier.buildLiveAudioClips().first;
      expect(clip.waveformPeaks, [-0.9, 0.9]);
    });

    test('clear removes the live clips', () {
      notifier.addPeaks(chunk(1, [(0.5, 0.1)]));
      notifier.clear();
      expect(notifier.isRecordingAudio, isFalse);
      expect(notifier.buildLiveAudioClips(), isEmpty);
    });
  });
}
