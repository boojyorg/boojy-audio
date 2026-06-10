import 'audio_engine_interface.dart';
import 'command.dart';

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
