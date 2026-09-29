import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // The engine reports track types capitalised ("Audio", "MIDI") while the UI
  // creates them lowercase ("audio", "midi"). Recording compared the parsed type
  // against lowercase literals, so an armed audio track never matched and every
  // audio take was dropped in the UI. These tests pin the contract against the
  // real engine instead of hand-written CSV fixtures.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Track type contract (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Track type contract (native engine)', () {
    late AudioEngine engine;

    setUp(() async {
      engine = await createInitializedEngine();
    });

    TrackData parsed(int trackId) {
      final track = TrackData.fromCSV(engine.getTrackInfo(trackId));
      expect(track, isNotNull, reason: 'engine track info must parse');
      return track!;
    }

    test('an armed audio track reads as audio', () {
      final trackId = engine.createTrack('audio', 'Vocal');
      engine.setTrackArmed(trackId, armed: true);

      final track = parsed(trackId);
      expect(track.isAudio, isTrue, reason: 'engine type was "${track.type}"');
      expect(track.isMidi, isFalse);
      expect(track.armed, isTrue);
    });

    test('an armed MIDI track reads as MIDI', () {
      final trackId = engine.createTrack('midi', 'Keys');
      engine.setTrackArmed(trackId, armed: true);

      final track = parsed(trackId);
      expect(track.isMidi, isTrue, reason: 'engine type was "${track.type}"');
      expect(track.isAudio, isFalse);
      expect(track.armed, isTrue);
    });
  });
}
