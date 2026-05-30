import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/send_commands.dart';
import '../../mocks/mock_audio_engine.dart';

void main() {
  late MockAudioEngine mockEngine;

  setUp(() {
    mockEngine = MockAudioEngine();
  });

  group('AddSendCommand', () {
    test('execute adds a send', () async {
      final command = AddSendCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Track 1',
        returnTrackId: 5,
        returnLabel: 'Reverb',
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('addSend'));
    });

    test('undo removes the send', () async {
      final command = AddSendCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Track 1',
        returnTrackId: 5,
        returnLabel: 'Reverb',
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('removeSend'));
    });

    test('has correct description', () {
      final command = AddSendCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Track 1',
        returnTrackId: 5,
        returnLabel: 'Reverb',
      );

      expect(command.description, 'Add Send: Reverb → Track 1');
    });
  });

  group('SetSendAmountCommand', () {
    test('execute sets new amount, undo restores old', () async {
      final command = SetSendAmountCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Track 1',
        returnTrackId: 5,
        returnLabel: 'Reverb',
        newAmountDb: -6.0,
        oldAmountDb: -20.0,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(mockEngine.calls.where((c) => c == 'setSendAmount').length, 2);
    });
  });

  group('RemoveSendCommand', () {
    test('execute removes, undo re-adds at previous amount', () async {
      final command = RemoveSendCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Track 1',
        returnTrackId: 5,
        returnLabel: 'Reverb',
        previousAmountDb: -12.0,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('removeSend'));
      expect(mockEngine.calls, contains('addSend'));
    });

    test('redo (re-execute) removes the same send again', () async {
      final command = RemoveSendCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Track 1',
        returnTrackId: 5,
        returnLabel: 'Reverb',
        previousAmountDb: -12.0,
      );

      // execute → undo → redo. Sends are keyed by (source, return), which are
      // stable, so redo correctly targets the same send.
      await command.execute(mockEngine);
      await command.undo(mockEngine);
      await command.execute(mockEngine);

      expect(mockEngine.calls.where((c) => c == 'removeSend').length, 2);
    });
  });

  group('RemoveReturnCommand', () {
    test('execute removes the return, undo recreates it', () async {
      final command = RemoveReturnCommand(
        returnTrackId: 5,
        returnLabel: 'Reverb',
        effectType: 'reverb',
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('removeReturn'));
      expect(mockEngine.calls, contains('createReturnWithEffect'));
    });

    // Regression test for the stale-id-on-redo bug (M-9): undo recreates the
    // return with a *new* engine id, so redo must target that new id — not the
    // original one, which no longer exists (the orphaned return would keep
    // routing audio while the UI shows it gone).
    test(
      'redo targets the recreated return id, not the stale original',
      () async {
        final command = RemoveReturnCommand(
          returnTrackId: 5,
          returnLabel: 'Reverb',
          effectType: 'reverb',
        );

        await command.execute(mockEngine); // removes 5
        await command.undo(mockEngine); // recreates with a fresh id (1)
        await command.execute(mockEngine); // redo: must remove the recreated id

        final recreatedId = mockEngine.removedReturnIds.last;
        expect(mockEngine.removedReturnIds.first, 5);
        // The redo must NOT remove the stale original id again.
        expect(recreatedId, isNot(5));
        // It must match the id handed back by createReturnWithEffect on undo.
        expect(recreatedId, 1);
      },
    );
  });
}
