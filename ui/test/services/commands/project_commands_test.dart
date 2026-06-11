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
      final command = SetTempoCommand(newBpm: 140.0, oldBpm: 120.0);

      expect(command.description, 'Change Tempo: 120 → 140 BPM');
    });

    test('description rounds fractional BPM', () {
      final command = SetTempoCommand(newBpm: 128.5, oldBpm: 120.3);

      expect(command.description, 'Change Tempo: 120 → 129 BPM');
    });

    test('execute sets new tempo', () async {
      final command = SetTempoCommand(newBpm: 140.0, oldBpm: 120.0);

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
      final command = SetTempoCommand(newBpm: 140.0, oldBpm: 120.0);

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
      final command = SetCountInCommand(newBars: 1, oldBars: 2);

      expect(command.description, 'Change Count-in: 2 → 1 bar');
    });

    test('has correct description for plural bars', () {
      final command = SetCountInCommand(newBars: 2, oldBars: 0);

      expect(command.description, 'Change Count-in: 0 → 2 bars');
    });

    test('execute sets new count-in', () async {
      final command = SetCountInCommand(newBars: 2, oldBars: 0);

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
      final command = SetCountInCommand(newBars: 2, oldBars: 0);

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

  group('SetTimeSignatureCommand', () {
    test('has correct description', () {
      final command = SetTimeSignatureCommand(
        newNumerator: 7,
        oldNumerator: 4,
        newDenominator: 8,
        oldDenominator: 4,
        onChanged: (_, __) {},
      );

      expect(command.description, 'Change Time Signature: 4/4 → 7/8');
    });

    test('execute fires onChanged with the new signature', () async {
      int? num;
      int? den;

      final command = SetTimeSignatureCommand(
        newNumerator: 7,
        oldNumerator: 4,
        newDenominator: 8,
        oldDenominator: 4,
        onChanged: (n, d) {
          num = n;
          den = d;
        },
      );

      await command.execute(mockEngine);

      expect(num, 7);
      expect(den, 8);
    });

    test('undo fires onChanged with the old signature', () async {
      int? num;
      int? den;

      final command = SetTimeSignatureCommand(
        newNumerator: 7,
        oldNumerator: 4,
        newDenominator: 8,
        oldDenominator: 4,
        onChanged: (n, d) {
          num = n;
          den = d;
        },
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(num, 4);
      expect(den, 4);
    });
  });

  group('SetTrackColorCommand', () {
    test('has correct description', () {
      final command = SetTrackColorCommand(
        trackId: 1,
        newColorArgb: 0xFFFF0000,
        oldColorArgb: 0xFF00FF00,
        onColorChanged: (_, __) {},
      );

      expect(command.description, 'Change Track Colour');
    });

    test('execute applies the new colour', () async {
      int? trackId;
      int? argb;

      final command = SetTrackColorCommand(
        trackId: 5,
        newColorArgb: 0xFFFF0000,
        oldColorArgb: 0xFF00FF00,
        onColorChanged: (id, c) {
          trackId = id;
          argb = c;
        },
      );

      await command.execute(mockEngine);

      expect(trackId, 5);
      expect(argb, 0xFFFF0000);
    });

    test('undo restores the old colour', () async {
      int? argb = -1;

      final command = SetTrackColorCommand(
        trackId: 5,
        newColorArgb: 0xFFFF0000,
        oldColorArgb: 0xFF00FF00,
        onColorChanged: (_, c) => argb = c,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(argb, 0xFF00FF00);
    });

    test('undo clears the override when there was none before', () async {
      int? argb = 0xDEADBEEF;

      final command = SetTrackColorCommand(
        trackId: 5,
        newColorArgb: 0xFFFF0000,
        oldColorArgb: null,
        onColorChanged: (_, c) => argb = c,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(argb, isNull); // null = revert to the auto colour
    });
  });

  group('SetTrackIconCommand', () {
    test('has correct description', () {
      final command = SetTrackIconCommand(
        trackId: 1,
        newIconKey: 'guitar',
        oldIconKey: 'mic',
        onIconChanged: (_, __) {},
      );

      expect(command.description, 'Change Track Icon');
    });

    test('execute applies the new icon key', () async {
      int? trackId;
      String? iconKey;

      final command = SetTrackIconCommand(
        trackId: 5,
        newIconKey: 'guitar',
        oldIconKey: 'mic',
        onIconChanged: (id, key) {
          trackId = id;
          iconKey = key;
        },
      );

      await command.execute(mockEngine);

      expect(trackId, 5);
      expect(iconKey, 'guitar');
    });

    test('undo restores the old icon key', () async {
      String? iconKey;

      final command = SetTrackIconCommand(
        trackId: 5,
        newIconKey: 'guitar',
        oldIconKey: 'mic',
        onIconChanged: (_, key) => iconKey = key,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(iconKey, 'mic');
    });

    test('undo clears the override when there was none before', () async {
      String? iconKey = 'sentinel';

      final command = SetTrackIconCommand(
        trackId: 5,
        newIconKey: 'guitar',
        oldIconKey: null,
        onIconChanged: (_, key) => iconKey = key,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(iconKey, isNull); // null = revert to the auto icon
    });

    test('survives undo -> redo (re-execute applies the new key)', () async {
      final applied = <String?>[];

      final command = SetTrackIconCommand(
        trackId: 5,
        newIconKey: 'guitar',
        oldIconKey: null,
        onIconChanged: (_, key) => applied.add(key),
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);
      await command.execute(mockEngine); // redo re-runs execute

      expect(applied, ['guitar', null, 'guitar']);
    });
  });
}
