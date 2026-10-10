import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/controllers/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // Recording ignores the loop: the take runs straight on until Stop. The
  // loop's jump back used to keep running while recording, so the backing
  // replayed the loop while the take kept growing past it, and the playhead
  // showed negative times. Works with the input off (the recorder still
  // runs), so CI needs no microphone.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Recording ignores the loop (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Recording ignores the loop (native engine)', () {
    late AudioEngine engine;
    late PlaybackController controller;

    setUp(() async {
      engine = await createInitializedEngine();
      engine.clearAllTracks();
      engine.setCountInBars(0);
      engine.transportSeek(0);
      controller = PlaybackController()..initialize(engine);
    });

    tearDown(() {
      controller.dispose();
      engine.transportStop();
      engine.transportSeek(0);
      engine.clearAllTracks();
    });

    /// Play a one-beat loop (0–0.5 s at 120 BPM).
    void playShortLoop() =>
        controller.playLoop(loopStartBeats: 0, loopEndBeats: 1, tempo: 120);

    test('playing with loop on still jumps back', () async {
      playShortLoop();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(controller.playheadPosition, lessThan(0.5));
    });

    test('recording during a loop runs straight past its end', () async {
      playShortLoop();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // As the DAW starts a take while playing (Play → Record).
      engine.startRecording();
      controller.startPlayheadPolling();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final position = controller.playheadPosition;
      engine.stopRecording();
      expect(position, greaterThan(0.5), reason: 'no jump back');
    });
  });
}
