import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/services/commands/command.dart';
import 'package:boojy_audio/audio_engine.dart';

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
  Future<void> execute(AudioEngine engine) async {
    executed = true;
    undone = false;
    executeCount++;
  }

  @override
  Future<void> undo(AudioEngine engine) async {
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
  Future<void> execute(AudioEngine engine) async {
    throw Exception('Execution failed');
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    throw Exception('Undo failed');
  }
}

void main() {
  // Note: UndoRedoManager is a singleton, so we need to clear it between tests
  // We also can't fully test execute/undo without a real AudioEngine
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

        expect(cmd.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
        expect(cmd.timestamp.isBefore(after.add(const Duration(seconds: 1))), isTrue);
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
