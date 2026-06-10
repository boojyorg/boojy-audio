import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';
import 'commands/audio_engine_interface.dart';
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

  /// Lock to prevent concurrent command execution (race condition protection)
  Completer<void>? _executionLock;

  /// Maximum history size (configurable via UserSettings)
  int get maxHistorySize => UserSettings().undoLimit;

  AudioEngineInterface? _engine;

  /// Initialize with audio engine reference
  void initialize(AudioEngineInterface engine) {
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

  /// Acquire execution lock to prevent concurrent operations
  Future<void> _acquireLock() async {
    // Wait for any existing operation to complete
    while (_executionLock != null && !_executionLock!.isCompleted) {
      await _executionLock!.future;
    }
    _executionLock = Completer<void>();
  }

  /// Release execution lock
  void _releaseLock() {
    _executionLock?.complete();
  }

  /// Execute a command and add it to the undo stack
  Future<void> execute(Command command) async {
    if (_engine == null) {
      return;
    }

    await _acquireLock();
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
      Log.e('UndoRedoManager: Error executing command: $e');
      // In debug, surface the error instead of letting the action die
      // silently — this is how the "listen outside build" class shipped
      // three times (the assert was swallowed right here). Release keeps
      // the old swallow-and-continue behavior.
      if (kDebugMode) rethrow;
    } finally {
      _releaseLock();
    }
  }

  /// Execute a command without adding to history (for internal use)
  /// Useful when you want to batch multiple small changes
  Future<void> executeWithoutHistory(Command command) async {
    if (_engine == null) return;
    await _acquireLock();
    try {
      await command.execute(_engine!);
    } finally {
      _releaseLock();
    }
  }

  /// Undo the last action.
  ///
  /// Failure contract is asymmetric by design: in RELEASE a failing command
  /// returns `false`; in DEBUG the error is rethrown (the Future completes
  /// with the error, so an `if (!await undo())` branch is never reached) —
  /// silent-swallow here is how the "listen outside build" class shipped
  /// three times. Returns `false` immediately when there is nothing to undo.
  Future<bool> undo() async {
    if (!canUndo || _engine == null) {
      return false;
    }

    await _acquireLock();
    try {
      // Peek, don't pop: if undo() throws we must leave the command on the
      // stack. Mutating the stacks only after a successful undo keeps history
      // intact instead of silently dropping the command.
      final command = _undoStack.last;
      await command.undo(_engine!);

      // Undo succeeded — move it to the redo stack.
      _undoStack.removeLast();
      _redoStack.add(command);

      notifyListeners();
      return true;
    } catch (e) {
      Log.e('UndoRedoManager: Error undoing command: $e');
      if (kDebugMode) rethrow; // see execute(): never die silently in debug
      return false;
    } finally {
      _releaseLock();
    }
  }

  /// Redo the last undone action.
  ///
  /// Same failure contract as [undo]: returns `false` in release, rethrows in
  /// debug (the returned Future completes with the error, not `false`).
  Future<bool> redo() async {
    if (!canRedo || _engine == null) {
      return false;
    }

    await _acquireLock();
    try {
      // Peek, don't pop (see undo()): a throwing execute() must leave the
      // command on the redo stack rather than losing it.
      final command = _redoStack.last;
      await command.execute(_engine!);

      // Redo succeeded — move it back to the undo stack.
      _redoStack.removeLast();
      _undoStack.add(command);

      notifyListeners();
      return true;
    } catch (e) {
      Log.e('UndoRedoManager: Error redoing command: $e');
      if (kDebugMode) rethrow; // see execute(): never die silently in debug
      return false;
    } finally {
      _releaseLock();
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
