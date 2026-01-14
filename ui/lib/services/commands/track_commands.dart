import 'audio_engine_interface.dart';
import 'command.dart';

/// Command to create a new track
class CreateTrackCommand extends Command {
  final String trackType;
  final String trackName;
  int? _createdTrackId;

  CreateTrackCommand({
    required this.trackType,
    required this.trackName,
  });

  /// Get the ID of the created track (after execute)
  int? get createdTrackId => _createdTrackId;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    _createdTrackId = engine.createTrack(trackType, trackName);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_createdTrackId != null && _createdTrackId! >= 0) {
      engine.deleteTrack(_createdTrackId!);
    }
  }

  String get _trackTypeDisplay => trackType == 'midi' ? 'MIDI' : 'Audio';

  @override
  String get description => 'Create $_trackTypeDisplay Track';
}

/// Command to delete a track
class DeleteTrackCommand extends Command {
  final int trackId;
  final String trackName;
  final String trackType;

  // Store track state for undo
  double? _volumeDb;
  double? _pan;
  bool? _mute;
  bool? _solo;

  DeleteTrackCommand({
    required this.trackId,
    required this.trackName,
    required this.trackType,
    double? volumeDb,
    double? pan,
    bool? mute,
    bool? solo,
  })  : _volumeDb = volumeDb,
        _pan = pan,
        _mute = mute,
        _solo = solo;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Store current state before deletion
    final info = engine.getTrackInfo(trackId);
    if (info.isNotEmpty && !info.startsWith('Error')) {
      final parts = info.split(',');
      if (parts.length >= 7) {
        _volumeDb = double.tryParse(parts[3]);
        _pan = double.tryParse(parts[4]);
        _mute = parts[5] == 'true' || parts[5] == '1';
        _solo = parts[6] == 'true' || parts[6] == '1';
      }
    }

    engine.deleteTrack(trackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Recreate the track
    final newTrackId = engine.createTrack(trackType, trackName);

    // Restore state
    if (newTrackId >= 0) {
      if (_volumeDb != null) engine.setTrackVolume(newTrackId, _volumeDb!);
      if (_pan != null) engine.setTrackPan(newTrackId, _pan!);
      if (_mute != null) engine.setTrackMute(newTrackId, mute: _mute!);
      if (_solo != null) engine.setTrackSolo(newTrackId, solo: _solo!);
    }
  }

  @override
  String get description => 'Delete Track: $trackName';
}

/// Command to duplicate a track
class DuplicateTrackCommand extends Command {
  final int sourceTrackId;
  final String sourceTrackName;
  int? _duplicatedTrackId;

  DuplicateTrackCommand({
    required this.sourceTrackId,
    required this.sourceTrackName,
  });

  /// Get the ID of the duplicated track (after execute)
  int? get duplicatedTrackId => _duplicatedTrackId;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    _duplicatedTrackId = engine.duplicateTrack(sourceTrackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_duplicatedTrackId != null && _duplicatedTrackId! >= 0) {
      engine.deleteTrack(_duplicatedTrackId!);
    }
  }

  @override
  String get description => 'Duplicate Track: $sourceTrackName';
}

/// Command to rename a track
class RenameTrackCommand extends Command {
  final int trackId;
  final String oldName;
  final String newName;

  /// Callback to update UI state after rename
  final void Function(int trackId, String name)? onTrackRenamed;

  RenameTrackCommand({
    required this.trackId,
    required this.oldName,
    required this.newName,
    this.onTrackRenamed,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTrackName(trackId, newName);
    onTrackRenamed?.call(trackId, newName);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setTrackName(trackId, oldName);
    onTrackRenamed?.call(trackId, oldName);
  }

  @override
  String get description => 'Rename Track: $oldName → $newName';
}

/// Command to reorder tracks (drag-and-drop)
class ReorderTrackCommand extends Command {
  final int trackId;
  final String trackName;
  final int oldIndex;
  final int newIndex;

  /// Callback to update UI state after reorder
  final void Function(int oldIndex, int newIndex)? onTrackReordered;

  ReorderTrackCommand({
    required this.trackId,
    required this.trackName,
    required this.oldIndex,
    required this.newIndex,
    this.onTrackReordered,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Track reordering is UI-only state (not in audio engine)
    onTrackReordered?.call(oldIndex, newIndex);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Reverse the reorder
    onTrackReordered?.call(newIndex, oldIndex);
  }

  @override
  String get description => 'Reorder Track: $trackName';
}

/// Command to arm/disarm a track for recording
class ArmTrackCommand extends Command {
  final int trackId;
  final String trackName;
  final bool newArmed;
  final bool oldArmed;

  ArmTrackCommand({
    required this.trackId,
    required this.trackName,
    required this.newArmed,
    required this.oldArmed,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTrackArmed(trackId, armed: newArmed);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setTrackArmed(trackId, armed: oldArmed);
  }

  @override
  String get description =>
      '${newArmed ? 'Arm' : 'Disarm'} Track: $trackName';
}
