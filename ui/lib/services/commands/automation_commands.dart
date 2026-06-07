import '../../controllers/automation_controller.dart';
import '../../models/track_automation_data.dart';
import 'audio_engine_interface.dart';
import 'command.dart';

/// Command to add a track automation point (tap/slice/duplicate in the lane).
class AddAutomationPointCommand extends Command {
  final AutomationController controller;
  final int trackId;
  final AutomationParameter parameter;
  final AutomationPoint point;

  /// Called after every apply (execute/undo) so the owner can re-sync the
  /// engine curve and refresh dependent UI.
  final void Function(int trackId)? onLaneChanged;

  AddAutomationPointCommand({
    required this.controller,
    required this.trackId,
    required this.parameter,
    required this.point,
    this.onLaneChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    controller.addPoint(trackId, parameter, point);
    onLaneChanged?.call(trackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    controller.removePoint(trackId, parameter, point.id);
    onLaneChanged?.call(trackId);
  }

  @override
  String get description => 'Add ${parameter.displayName} Automation Point';
}

/// Command to move a track automation point (committed at drag end with the
/// pre-drag point captured at drag start — not per drag tick).
class MoveAutomationPointCommand extends Command {
  final AutomationController controller;
  final int trackId;
  final AutomationParameter parameter;
  final AutomationPoint oldPoint;
  final AutomationPoint newPoint;
  final void Function(int trackId)? onLaneChanged;

  MoveAutomationPointCommand({
    required this.controller,
    required this.trackId,
    required this.parameter,
    required this.oldPoint,
    required this.newPoint,
    this.onLaneChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    controller.updatePoint(trackId, parameter, oldPoint.id, newPoint);
    onLaneChanged?.call(trackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    controller.updatePoint(trackId, parameter, oldPoint.id, oldPoint);
    onLaneChanged?.call(trackId);
  }

  @override
  String get description => 'Move ${parameter.displayName} Automation Point';
}

/// Command to delete a track automation point (eraser click/drag).
class RemoveAutomationPointCommand extends Command {
  final AutomationController controller;
  final int trackId;
  final AutomationParameter parameter;
  final AutomationPoint point; // captured before removal, restored on undo
  final void Function(int trackId)? onLaneChanged;

  RemoveAutomationPointCommand({
    required this.controller,
    required this.trackId,
    required this.parameter,
    required this.point,
    this.onLaneChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    controller.removePoint(trackId, parameter, point.id);
    onLaneChanged?.call(trackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    controller.addPoint(trackId, parameter, point);
    onLaneChanged?.call(trackId);
  }

  @override
  String get description => 'Delete ${parameter.displayName} Automation Point';
}

/// Command to clear every point on a lane (the reset button in the strip's
/// automation section). The points are snapshotted before clearing so undo
/// restores them with their original ids.
class ClearAutomationLaneCommand extends Command {
  final AutomationController controller;
  final int trackId;
  final AutomationParameter parameter;
  final List<AutomationPoint> points; // captured before clearing
  final void Function(int trackId)? onLaneChanged;

  ClearAutomationLaneCommand({
    required this.controller,
    required this.trackId,
    required this.parameter,
    required this.points,
    this.onLaneChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    controller.clearLane(trackId, parameter);
    onLaneChanged?.call(trackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    for (final point in points) {
      controller.addPoint(trackId, parameter, point);
    }
    onLaneChanged?.call(trackId);
  }

  @override
  String get description => 'Clear ${parameter.displayName} Automation';
}
