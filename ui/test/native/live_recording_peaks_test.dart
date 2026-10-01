import 'package:boojy_audio/audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // The live waveform: while recording, the engine publishes one peak per
  // 10 ms, and the UI fetches only the new ones. Works with the input off
  // (the recorder still runs), so CI needs no microphone.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Live recording peaks (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Live recording peaks (native engine)', () {
    late AudioEngine engine;

    setUp(() async {
      engine = await createInitializedEngine();
      engine.clearAllTracks();
      engine.setCountInBars(0);
    });

    tearDown(() {
      engine.transportStop();
      engine.clearAllTracks();
    });

    Future<void> recordFor(Duration duration) async {
      engine.startRecording();
      await Future<void>.delayed(duration);
    }

    test('peaks arrive about 100 a second while recording', () async {
      await recordFor(const Duration(milliseconds: 500));
      final peaks = engine.getLiveRecordingPeaks(0);
      engine.stopRecording();

      expect(peaks.total, inInclusiveRange(20, 80));
      expect(peaks.left.length, peaks.total);
      expect(peaks.right.length, peaks.total);
    });

    test('asking from the end returns only what is new', () async {
      await recordFor(const Duration(milliseconds: 200));
      final first = engine.getLiveRecordingPeaks(0);
      final again = engine.getLiveRecordingPeaks(first.total);
      engine.stopRecording();

      expect(again.total, greaterThanOrEqualTo(first.total));
      expect(again.left.length, again.total - first.total);
    });

    test('a new take starts from zero', () async {
      await recordFor(const Duration(milliseconds: 400));
      final firstTake = engine.getLiveRecordingPeaks(0).total;
      engine.stopRecording();
      engine.transportStop();

      engine.startRecording();
      final secondTake = engine.getLiveRecordingPeaks(0).total;
      engine.stopRecording();

      expect(firstTake, greaterThan(10));
      expect(secondTake, lessThan(firstTake));
    });
  });
}
