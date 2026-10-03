import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/widgets/audio_editor/operations/parameter_operations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/mock_audio_engine.dart';

/// A 150 BPM clip with warp on or off.
ClipData _clip(int id, {required bool warp}) => ClipData(
  clipId: id,
  trackId: 1,
  filePath: '/clips/loop.wav',
  startTime: 0,
  duration: 6.4,
  editData: AudioClipEditData(bpm: 150, syncEnabled: warp),
);

void main() {
  group('pushWarpForTempo', () {
    test('re-stretches every warped clip to the current tempo', () {
      final engine = MockAudioEngine()..tempo = 120;
      final clips = [_clip(1, warp: true), _clip(2, warp: false)];

      pushWarpForTempo(engine, clips);
      engine.tempo = 170;
      pushWarpForTempo(engine, clips);

      // Only the warped clip is touched, and each time at the tempo then.
      expect(engine.warpCalls.map((c) => c.clipId), [1, 1]);
      expect(engine.warpCalls[0].stretch, closeTo(120 / 150, 1e-9));
      expect(engine.warpCalls[1].stretch, closeTo(170 / 150, 1e-9));
    });
  });

  group('pushAudioClipEdits', () {
    test('sends the stretch for the engine tempo, not a stored one', () {
      final engine = MockAudioEngine()..tempo = 97;
      pushAudioClipEdits(
        engine,
        1,
        7,
        const AudioClipEditData(bpm: 150, syncEnabled: true),
      );
      expect(engine.warpCalls.single.enabled, isTrue);
      expect(engine.warpCalls.single.stretch, closeTo(97 / 150, 1e-9));
      expect(
        engine.calls,
        containsAll(['setAudioClipGain', 'setAudioClipReverse']),
      );
    });
  });

  group('AudioClipEditCommand', () {
    test('undo puts the engine back, not just the editor', () async {
      final engine = MockAudioEngine()..tempo = 120;
      AudioClipEditData? shown;
      final command = AudioClipEditCommand(
        beforeState: const AudioClipEditData(bpm: 150),
        afterState: const AudioClipEditData(bpm: 150, syncEnabled: true),
        clipData: _clip(3, warp: false),
        actionDescription: 'Enable warp',
        onApplyState: (state, _) => shown = state,
      );

      await command.execute(engine);
      await command.undo(engine);

      expect(shown?.syncEnabled, isFalse);
      expect(engine.warpCalls.map((c) => c.enabled), [true, false]);
    });
  });
}
