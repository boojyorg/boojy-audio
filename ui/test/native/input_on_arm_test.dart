import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/audio_input_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // Arming an audio track opens the input so the meter moves and you hear
  // yourself before recording; disarming closes it. CI runners have no
  // microphone, so "open" there reads as failed: either way it isn't closed.
  // Locally this briefly opens the real default input.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Input opens on arm (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Input opens on arm (native engine)', () {
    late AudioEngine engine;

    InputHealthState health() => engine.getAudioInputHealth().state;

    setUp(() async {
      engine = await createInitializedEngine();
      engine.clearAllTracks();
      engine.setAudioInputChoice(''); // system default
    });

    tearDown(() {
      engine.clearAllTracks();
      engine.setAudioInputChoice(kAudioInputOff); // harness default
    });

    test('nothing armed keeps the input closed', () {
      expect(health(), InputHealthState.closed);
    });

    test('arming an audio track opens the input, disarming closes it', () {
      final trackId = engine.createTrack('audio', 'Vocal');
      engine.setTrackArmed(trackId, armed: true);
      expect(
        health(),
        isNot(anyOf(InputHealthState.closed, InputHealthState.unknown)),
      );

      engine.setTrackArmed(trackId, armed: false);
      expect(health(), InputHealthState.closed);
    });

    test('arming a MIDI track leaves the input closed', () {
      final trackId = engine.createTrack('midi', 'Keys');
      engine.setTrackArmed(trackId, armed: true);
      expect(health(), InputHealthState.closed);
    });

    test('deleting the armed audio track closes the input', () {
      final trackId = engine.createTrack('audio', 'Vocal');
      engine.setTrackArmed(trackId, armed: true);
      engine.deleteTrack(trackId);
      expect(health(), InputHealthState.closed);
    });

    test('input off reports off as soon as you arm', () {
      engine.setAudioInputChoice(kAudioInputOff);
      final trackId = engine.createTrack('audio', 'Vocal');
      engine.setTrackArmed(trackId, armed: true);
      expect(health(), InputHealthState.off);
    });

    test('stopping a take keeps the input open while still armed', () async {
      final trackId = engine.createTrack('audio', 'Vocal');
      engine.setTrackArmed(trackId, armed: true);
      engine.setCountInBars(0);

      engine.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      engine.stopRecording();
      engine.transportStop();

      expect(health(), isNot(InputHealthState.closed));
      engine.setTrackArmed(trackId, armed: false);
      expect(health(), InputHealthState.closed);
    });
  });
}
