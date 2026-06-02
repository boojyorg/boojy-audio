import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/services/commands/command.dart';
import 'package:boojy_audio/services/commands/audio_engine_interface.dart';
import '../mocks/mock_audio_engine.dart';

/// A mock command for testing that tracks execution
class MockCommand extends Command {
  final String _description;
  bool executed = false;
  bool undone = false;
  int executeCount = 0;
  int undoCount = 0;

  MockCommand(this._description);

  @override
  String get description => _description;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    executed = true;
    undone = false;
    executeCount++;
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    undone = true;
    executeCount--;
    undoCount++;
  }
}

/// A command that throws during execution
class FailingCommand extends Command {
  @override
  String get description => 'Failing Command';

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    throw Exception('Execution failed');
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    throw Exception('Undo failed');
  }
}

/// Executes fine but throws on undo — exercises the undo() failure path.
class ThrowOnUndoCommand extends Command {
  @override
  String get description => 'Throw On Undo';

  @override
  Future<void> execute(AudioEngineInterface engine) async {}

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    throw Exception('undo failed');
  }
}

/// First execute succeeds; the redo re-execute throws — exercises redo()'s
/// failure path (the command is already on the redo stack at that point).
class ThrowOnRedoCommand extends Command {
  bool _executedOnce = false;

  @override
  String get description => 'Throw On Redo';

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    if (_executedOnce) throw Exception('redo failed');
    _executedOnce = true;
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {}
}

void main() {
  // Note: UndoRedoManager is a singleton, so we need to clear it between tests
  // We also can't fully test execute/undo without a real AudioEngineInterface
  // These tests focus on the state management logic

  group('UndoRedoManager', () {
    late UndoRedoManager manager;

    setUp(() {
      manager = UndoRedoManager();
      manager.clear(); // Reset state between tests
    });

    group('initial state', () {
      test('starts with empty undo stack', () {
        expect(manager.canUndo, isFalse);
      });

      test('starts with empty redo stack', () {
        expect(manager.canRedo, isFalse);
      });

      test('undoDescription is null when empty', () {
        expect(manager.undoDescription, isNull);
      });

      test('redoDescription is null when empty', () {
        expect(manager.redoDescription, isNull);
      });

      test('undoHistory is empty when no commands', () {
        expect(manager.undoHistory, isEmpty);
      });

      test('redoHistory is empty when no commands', () {
        expect(manager.redoHistory, isEmpty);
      });
    });

    group('stats', () {
      test('returns correct initial stats', () {
        final stats = manager.stats;

        expect(stats['undoCount'], 0);
        expect(stats['redoCount'], 0);
        expect(stats['maxSize'], isPositive); // From UserSettings
      });
    });

    group('clear', () {
      test('clears undo and redo stacks', () {
        // We can't add commands without an engine, but we can verify clear works
        manager.clear();

        expect(manager.canUndo, isFalse);
        expect(manager.canRedo, isFalse);
        expect(manager.undoHistory, isEmpty);
        expect(manager.redoHistory, isEmpty);
      });
    });

    group('without engine initialized', () {
      test('undo returns false without engine', () async {
        final result = await manager.undo();
        expect(result, isFalse);
      });

      test('redo returns false without engine', () async {
        final result = await manager.redo();
        expect(result, isFalse);
      });
    });

    // Regression: a command whose undo/redo throws must NOT be silently
    // dropped from the stacks (C66/C86). The manager peeks rather than pops,
    // so a failed undo leaves the command available to retry.
    group('throwing command does not corrupt history', () {
      late MockAudioEngine engine;

      setUp(() {
        engine = MockAudioEngine();
        manager.initialize(engine);
      });

      test('failed undo keeps the command on the undo stack', () async {
        await manager.execute(ThrowOnUndoCommand());
        expect(manager.canUndo, isTrue);

        final result = await manager.undo();

        expect(result, isFalse, reason: 'undo threw → should report failure');
        expect(manager.canUndo, isTrue, reason: 'command must be retained');
        expect(manager.canRedo, isFalse, reason: 'must not move to redo stack');
      });

      test('failed redo keeps the command on the redo stack', () async {
        final cmd = ThrowOnRedoCommand();
        await manager.execute(cmd); // first execute succeeds
        await manager.undo(); // undo succeeds → command now on redo stack
        expect(manager.canRedo, isTrue);

        final result = await manager.redo(); // re-execute throws

        expect(result, isFalse, reason: 'redo threw → should report failure');
        expect(manager.canRedo, isTrue, reason: 'command must be retained');
        expect(manager.canUndo, isFalse, reason: 'must not move to undo stack');
      });
    });
  });

  group('Command', () {
    group('MockCommand', () {
      test('tracks execution state', () {
        final cmd = MockCommand('Test Command');

        expect(cmd.executed, isFalse);
        expect(cmd.undone, isFalse);
        expect(cmd.description, 'Test Command');
      });

      test('has timestamp', () {
        final before = DateTime.now();
        final cmd = MockCommand('Test');
        final after = DateTime.now();

        expect(
          cmd.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
        expect(
          cmd.timestamp.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      });
    });
  });

  group('CompositeCommand', () {
    test('has description', () {
      final composite = CompositeCommand([], 'Batch Operation');
      expect(composite.description, 'Batch Operation');
    });

    test('contains multiple commands', () {
      final cmd1 = MockCommand('Command 1');
      final cmd2 = MockCommand('Command 2');
      final cmd3 = MockCommand('Command 3');

      final composite = CompositeCommand([cmd1, cmd2, cmd3], 'Batch');

      expect(composite.commands.length, 3);
      expect(composite.commands[0], cmd1);
      expect(composite.commands[1], cmd2);
      expect(composite.commands[2], cmd3);
    });

    test('has timestamp', () {
      final composite = CompositeCommand([], 'Test');
      expect(composite.timestamp, isNotNull);
    });
  });
}
