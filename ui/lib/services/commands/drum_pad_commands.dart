import 'audio_engine_interface.dart';
import 'command.dart';

/// Undoable change to a single drum-pad parameter (attack, decay, pitch,
/// reverse, pan, …). Values are passed as strings because the engine's
/// `setDrumPadParameter` takes a stringified value, matching how the editor's
/// live setters format them.
///
/// One command represents one gesture: for sliders/knobs the editor captures
/// the pre-drag value on drag-start and commits a single command on drag-end,
/// so a drag is one undo step rather than dozens.
class SetDrumPadParameterCommand extends Command {
  final int trackId;
  final int padIndex;
  final String paramName;
  final String oldValue;
  final String newValue;

  /// Re-sync the editor's local kit snapshot after the engine value changes,
  /// so the on-screen control reflects an undo/redo.
  final void Function()? onApplied;

  SetDrumPadParameterCommand({
    required this.trackId,
    required this.padIndex,
    required this.paramName,
    required this.oldValue,
    required this.newValue,
    this.onApplied,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setDrumPadParameter(trackId, padIndex, paramName, newValue);
    onApplied?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setDrumPadParameter(trackId, padIndex, paramName, oldValue);
    onApplied?.call();
  }

  @override
  String get description =>
      'Change drum pad $paramName ($oldValue → $newValue)';
}
