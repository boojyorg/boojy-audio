import 'audio_engine_interface.dart';
import 'command.dart';

/// Undoable sample load on a sampler track.
///
/// Execute loads [newPath]. Undo restores the previous sample (re-loading
/// [oldPath] and re-applying the parameter snapshot taken before the load —
/// loading resets loop points), or unloads entirely when this was the first
/// load, returning the editor to its empty drop-zone state.
class LoadSampleCommand extends Command {
  final int trackId;
  final String newPath;
  final int newRootNote;

  /// Path of the sample loaded before this command, null for a first load.
  final String? oldPath;

  /// Engine param key -> value snapshot taken before the load (root_note,
  /// loop points, etc.), re-applied on undo so the old sample comes back
  /// exactly as it was.
  final Map<String, String> oldParams;

  /// Refresh the editor UI after the engine sample changes.
  final void Function()? onApplied;

  LoadSampleCommand({
    required this.trackId,
    required this.newPath,
    required this.newRootNote,
    required this.oldPath,
    required this.oldParams,
    this.onApplied,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.loadSampleForTrack(trackId, newPath, newRootNote);
    onApplied?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    final previous = oldPath;
    if (previous == null) {
      engine.unloadSampleForTrack(trackId);
    } else {
      final rootNote = int.tryParse(oldParams['root_note'] ?? '') ?? 60;
      engine.loadSampleForTrack(trackId, previous, rootNote);
      // Loading reset the loop points and envelope — restore the snapshot.
      for (final entry in oldParams.entries) {
        engine.setSamplerParameter(trackId, entry.key, entry.value);
      }
    }
    onApplied?.call();
  }

  @override
  String get description => 'Load sample ${newPath.split('/').last}';
}

/// Undoable change to a single sampler parameter (attack, release, root note,
/// loop points, reverse, volume, …). Values are passed as strings because the
/// engine's `setSamplerParameter` takes a stringified value, matching how the
/// editor's live setters format them.
///
/// One command represents one gesture: for sliders and loop-handle drags the
/// editor captures the pre-drag value on gesture start and commits a single
/// command on gesture end, so a drag is one undo step rather than dozens.
class SetSamplerParameterCommand extends Command {
  final int trackId;
  final String paramName;
  final String oldValue;
  final String newValue;

  /// Re-sync the editor's local snapshot after the engine value changes,
  /// so the on-screen control reflects an undo/redo.
  final void Function()? onApplied;

  SetSamplerParameterCommand({
    required this.trackId,
    required this.paramName,
    required this.oldValue,
    required this.newValue,
    this.onApplied,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setSamplerParameter(trackId, paramName, newValue);
    onApplied?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setSamplerParameter(trackId, paramName, oldValue);
    onApplied?.call();
  }

  @override
  String get description => 'Change sampler $paramName ($oldValue → $newValue)';
}
