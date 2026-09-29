import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/audio_input_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // Covers the parts of the input choice that need no microphone: CI runners
  // have no input devices, so device lookup itself is tested in Rust
  // (`audio_input::tests`) and by hand.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Audio input choice (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Audio input choice (native engine)', () {
    late AudioEngine engine;

    setUp(() async {
      engine = await createInitializedEngine();
    });

    tearDown(() {
      // The engine is shared across tests: back to the default choice.
      engine.setAudioInputChoice('');
    });

    test('Off reports off and opens nothing', () {
      expect(
        engine.setAudioInputChoice(kAudioInputOff),
        isNot(startsWith('Error')),
      );

      final status = engine.getAudioInputStatus();
      expect(status.isOff, isTrue);
      expect(status.channelCount, 0);
      expect(status.deviceName, isEmpty);
    });

    test('recording with input off leaves no empty audio clip', () async {
      final trackId = engine.createTrack('audio', 'Vocal');
      engine.setTrackArmed(trackId, armed: true);
      engine.setAudioInputChoice(kAudioInputOff);
      engine.setCountInBars(0);

      engine.startRecording();
      // Let the audio thread run so the recorder has frames to keep.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final clipId = engine.stopRecording();
      engine.transportStop();

      expect(
        clipId,
        lessThan(0),
        reason: 'no input was open, so no audio clip',
      );
    });
  });
}
