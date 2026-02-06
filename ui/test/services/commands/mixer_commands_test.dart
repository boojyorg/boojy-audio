import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/mixer_commands.dart';
import '../../mocks/mock_audio_engine.dart';

void main() {
  late MockAudioEngine mockEngine;

  setUp(() {
    mockEngine = MockAudioEngine();
  });

  group('SetVolumeCommand', () {
    test('has correct description', () {
      final command = SetVolumeCommand(
        trackId: 1,
        trackName: 'Track 1',
        newVolumeDb: -6.0,
        oldVolumeDb: 0.0,
      );

      expect(command.description, 'Set Volume: Track 1 (0.0 → -6.0 dB)');
    });

    test('execute sets new volume', () async {
      final command = SetVolumeCommand(
        trackId: 1,
        trackName: 'Track 1',
        newVolumeDb: -6.0,
        oldVolumeDb: 0.0,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTrackVolume'));
    });

    test('undo restores old volume', () async {
      final command = SetVolumeCommand(
        trackId: 1,
        trackName: 'Track 1',
        newVolumeDb: -6.0,
        oldVolumeDb: 0.0,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setTrackVolume'));
    });
  });

  group('SetPanCommand', () {
    test('has correct description for left pan', () {
      final command = SetPanCommand(
        trackId: 1,
        trackName: 'Track 1',
        newPan: -0.5,
        oldPan: 0.0,
      );

      expect(command.description, 'Set Pan: Track 1 (C → -50L)');
    });

    test('has correct description for right pan', () {
      final command = SetPanCommand(
        trackId: 1,
        trackName: 'Track 1',
        newPan: 0.75,
        oldPan: -0.25,
      );

      expect(command.description, 'Set Pan: Track 1 (-25L → 75R)');
    });

    test('has correct description for center pan', () {
      final command = SetPanCommand(
        trackId: 1,
        trackName: 'Track 1',
        newPan: 0.0,
        oldPan: 0.5,
      );

      expect(command.description, 'Set Pan: Track 1 (50R → C)');
    });

    test('execute sets new pan', () async {
      final command = SetPanCommand(
        trackId: 1,
        trackName: 'Track 1',
        newPan: -0.5,
        oldPan: 0.0,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTrackPan'));
    });

    test('undo restores old pan', () async {
      final command = SetPanCommand(
        trackId: 1,
        trackName: 'Track 1',
        newPan: -0.5,
        oldPan: 0.0,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setTrackPan'));
    });
  });

  group('SetMuteCommand', () {
    test('has correct description when muting', () {
      final command = SetMuteCommand(
        trackId: 1,
        trackName: 'Track 1',
        newMute: true,
        oldMute: false,
      );

      expect(command.description, 'Mute Track: Track 1');
    });

    test('has correct description when unmuting', () {
      final command = SetMuteCommand(
        trackId: 1,
        trackName: 'Track 1',
        newMute: false,
        oldMute: true,
      );

      expect(command.description, 'Unmute Track: Track 1');
    });

    test('execute sets mute state', () async {
      final command = SetMuteCommand(
        trackId: 1,
        trackName: 'Track 1',
        newMute: true,
        oldMute: false,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTrackMute'));
    });

    test('undo restores previous mute state', () async {
      final command = SetMuteCommand(
        trackId: 1,
        trackName: 'Track 1',
        newMute: true,
        oldMute: false,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setTrackMute'));
    });
  });

  group('SetSoloCommand', () {
    test('has correct description when soloing', () {
      final command = SetSoloCommand(
        trackId: 1,
        trackName: 'Track 1',
        newSolo: true,
        oldSolo: false,
      );

      expect(command.description, 'Solo Track: Track 1');
    });

    test('has correct description when unsoloing', () {
      final command = SetSoloCommand(
        trackId: 1,
        trackName: 'Track 1',
        newSolo: false,
        oldSolo: true,
      );

      expect(command.description, 'Unsolo Track: Track 1');
    });

    test('execute sets solo state', () async {
      final command = SetSoloCommand(
        trackId: 1,
        trackName: 'Track 1',
        newSolo: true,
        oldSolo: false,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTrackSolo'));
    });

    test('undo restores previous solo state', () async {
      final command = SetSoloCommand(
        trackId: 1,
        trackName: 'Track 1',
        newSolo: true,
        oldSolo: false,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setTrackSolo'));
    });
  });
}
