import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/project_commands.dart';
import '../../mocks/mock_audio_engine.dart';

void main() {
  late MockAudioEngine mockEngine;

  setUp(() {
    mockEngine = MockAudioEngine();
  });

  group('SetTempoCommand', () {
    test('has correct description', () {
      final command = SetTempoCommand(
        newBpm: 140.0,
        oldBpm: 120.0,
      );

      expect(command.description, 'Change Tempo: 120 → 140 BPM');
    });

    test('description rounds fractional BPM', () {
      final command = SetTempoCommand(
        newBpm: 128.5,
        oldBpm: 120.3,
      );

      expect(command.description, 'Change Tempo: 120 → 129 BPM');
    });

    test('execute sets new tempo', () async {
      final command = SetTempoCommand(
        newBpm: 140.0,
        oldBpm: 120.0,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTempo'));
    });

    test('execute fires onTempoChanged callback', () async {
      double? changedBpm;

      final command = SetTempoCommand(
        newBpm: 140.0,
        oldBpm: 120.0,
        onTempoChanged: (bpm) => changedBpm = bpm,
      );

      await command.execute(mockEngine);

      expect(changedBpm, 140.0);
    });

    test('undo restores old tempo', () async {
      final command = SetTempoCommand(
        newBpm: 140.0,
        oldBpm: 120.0,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setTempo'));
    });

    test('undo fires onTempoChanged with old value', () async {
      double? changedBpm;

      final command = SetTempoCommand(
        newBpm: 140.0,
        oldBpm: 120.0,
        onTempoChanged: (bpm) => changedBpm = bpm,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(changedBpm, 120.0);
    });
  });

  group('SetCountInCommand', () {
    test('has correct description for singular bar', () {
      final command = SetCountInCommand(
        newBars: 1,
        oldBars: 2,
      );

      expect(command.description, 'Change Count-in: 2 → 1 bar');
    });

    test('has correct description for plural bars', () {
      final command = SetCountInCommand(
        newBars: 2,
        oldBars: 0,
      );

      expect(command.description, 'Change Count-in: 0 → 2 bars');
    });

    test('execute sets new count-in', () async {
      final command = SetCountInCommand(
        newBars: 2,
        oldBars: 0,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setCountInBars'));
    });

    test('execute fires onCountInChanged callback', () async {
      int? changedBars;

      final command = SetCountInCommand(
        newBars: 2,
        oldBars: 0,
        onCountInChanged: (bars) => changedBars = bars,
      );

      await command.execute(mockEngine);

      expect(changedBars, 2);
    });

    test('undo restores old count-in', () async {
      final command = SetCountInCommand(
        newBars: 2,
        oldBars: 0,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setCountInBars'));
    });

    test('undo fires onCountInChanged with old value', () async {
      int? changedBars;

      final command = SetCountInCommand(
        newBars: 2,
        oldBars: 0,
        onCountInChanged: (bars) => changedBars = bars,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(changedBars, 0);
    });
  });
}
