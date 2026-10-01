import 'package:boojy_audio/controllers/recording_controller.dart';
import 'package:boojy_audio/models/audio_input_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // Record → New Audio Track arms the track in the engine a moment before the
  // UI's track list knows. The take used to be thrown away on stop because
  // the controller asked that stale list whether an audio track was armed.
  // Needs a real input, so it skips where none opens (CI).
  if (!isNativeEngineAvailable) {
    test('Record into a new audio track (native engine)', () {}, skip: true);
    return;
  }

  test('a take on a track the UI does not know is armed yet is kept', () async {
    final engine = await createInitializedEngine();
    engine.clearAllTracks();
    engine.setAudioInputChoice('');
    engine.setCountInBars(0);
    final track = engine.createTrack('audio', 'Audio 1'); // armed by default

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final health = engine.getAudioInputHealth().state;
    if (health == InputHealthState.failed || health == InputHealthState.off) {
      markTestSkipped('no audio input on this machine');
      engine.clearAllTracks();
      engine.setAudioInputChoice(kAudioInputOff);
      return;
    }

    final controller = RecordingController()
      ..initialize(engine)
      ..hasArmedAudioTracks = () => false; // the stale UI view
    controller.startRecording(isAlreadyPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final result = controller.stopRecording();
    engine.transportStop();
    controller.dispose();

    expect(result.audioClipId, isNotNull, reason: 'the take was discarded');
    final info = engine.getAllAudioClipsInfo();
    expect(info, contains('${result.audioClipId},$track,'));

    engine.clearAllTracks();
    engine.setAudioInputChoice(kAudioInputOff);
  });
}
