import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import 'commands/command.dart';
import 'user_settings.dart';

/// Global undo/redo manager for the DAW
/// Uses the Command pattern to track and reverse actions
class UndoRedoManager extends ChangeNotifier {
  static final UndoRedoManager _instance = UndoRedoManager._internal();
  factory UndoRedoManager() => _instance;
  UndoRedoManager._internal();

  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];

  /// Maximum history size (configurable via UserSettings)
  int get maxHistorySize => UserSettings().undoLimit;

  AudioEngine? _engine;

  /// Initialize with audio engine reference
  void initialize(AudioEngine engine) {
    _engine = engine;
  }

  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  /// Get description of next undo action
  String? get undoDescription =>
      _undoStack.isNotEmpty ? _undoStack.last.description : null;

  /// Get description of next redo action
  String? get redoDescription =>
      _redoStack.isNotEmpty ? _redoStack.last.description : null;

  /// Get the undo history (most recent first)
  List<String> get undoHistory =>
      _undoStack.reversed.map((cmd) => cmd.description).toList();

  /// Get the redo history (most recent first)
  List<String> get redoHistory =>
      _redoStack.reversed.map((cmd) => cmd.description).toList();

  /// Execute a command and add it to the undo stack
  Future<void> execute(Command command) async {
    if (_engine == null) {
      return;
    }

    try {
      await command.execute(_engine!);

      // Add to undo stack
      _undoStack.add(command);

      // Clear redo stack (new action invalidates redo history)
      _redoStack.clear();

      // Limit history size
      while (_undoStack.length > maxHistorySize) {
        _undoStack.removeAt(0);
      }

      notifyListeners();
    } catch (e) {
    }
  }

  /// Execute a command without adding to history (for internal use)
  /// Useful when you want to batch multiple small changes
  Future<void> executeWithoutHistory(Command command) async {
    if (_engine == null) return;
    await command.execute(_engine!);
  }

  /// Undo the last action
  Future<bool> undo() async {
    if (!canUndo || _engine == null) {
      return false;
    }

    try {
      final command = _undoStack.removeLast();
      await command.undo(_engine!);

      // Move to redo stack
      _redoStack.add(command);

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Redo the last undone action
  Future<bool> redo() async {
    if (!canRedo || _engine == null) {
      return false;
    }

    try {
      final command = _redoStack.removeLast();
      await command.execute(_engine!);

      // Move back to undo stack
      _undoStack.add(command);

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear all history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// Get current history stats
  Map<String, int> get stats => {
        'undoCount': _undoStack.length,
        'redoCount': _redoStack.length,
        'maxSize': maxHistorySize,
      };
}
