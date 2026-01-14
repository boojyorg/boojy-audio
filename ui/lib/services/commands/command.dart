import 'audio_engine_interface.dart';

/// Base abstract class for all undoable commands.
/// Uses [AudioEngineInterface] to allow testing with mock implementations.
abstract class Command {
  /// Execute the command
  Future<void> execute(AudioEngineInterface engine);

  /// Undo the command (reverse the action)
  Future<void> undo(AudioEngineInterface engine);

  /// Human-readable description for undo history UI
  String get description;

  /// Optional: timestamp when command was executed
  final DateTime timestamp = DateTime.now();
}

/// A composite command that groups multiple commands into a single undo step
class CompositeCommand extends Command {
  final List<Command> commands;
  final String _description;

  CompositeCommand(this.commands, this._description);

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    for (final cmd in commands) {
      await cmd.execute(engine);
    }
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Undo in reverse order
    for (final cmd in commands.reversed) {
      await cmd.undo(engine);
    }
  }

  @override
  String get description => _description;
}
