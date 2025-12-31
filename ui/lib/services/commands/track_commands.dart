import '../../audio_engine.dart';
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
  Future<void> execute(AudioEngine engine) async {
    _createdTrackId = engine.createTrack(trackType, trackName);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    if (_createdTrackId != null && _createdTrackId! >= 0) {
      engine.deleteTrack(_createdTrackId!);
    }
  }

  @override
  String get description => 'Create $trackType track: $trackName';
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
  Future<void> execute(AudioEngine engine) async {
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
  Future<void> undo(AudioEngine engine) async {
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
  String get description => 'Delete track: $trackName';
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
  Future<void> execute(AudioEngine engine) async {
    _duplicatedTrackId = engine.duplicateTrack(sourceTrackId);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    if (_duplicatedTrackId != null && _duplicatedTrackId! >= 0) {
      engine.deleteTrack(_duplicatedTrackId!);
    }
  }

  @override
  String get description => 'Duplicate track: $sourceTrackName';
}
