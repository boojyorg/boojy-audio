import '../../audio_engine.dart';
import 'command.dart';

/// Command to change track volume
class SetVolumeCommand extends Command {
  final int trackId;
  final String trackName;
  final double newVolumeDb;
  final double oldVolumeDb;

  SetVolumeCommand({
    required this.trackId,
    required this.trackName,
    required this.newVolumeDb,
    required this.oldVolumeDb,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setTrackVolume(trackId, newVolumeDb);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setTrackVolume(trackId, oldVolumeDb);
  }

  @override
  String get description =>
      'Set volume: $trackName (${oldVolumeDb.toStringAsFixed(1)} → ${newVolumeDb.toStringAsFixed(1)} dB)';
}

/// Command to change track pan
class SetPanCommand extends Command {
  final int trackId;
  final String trackName;
  final double newPan;
  final double oldPan;

  SetPanCommand({
    required this.trackId,
    required this.trackName,
    required this.newPan,
    required this.oldPan,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setTrackPan(trackId, newPan);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setTrackPan(trackId, oldPan);
  }

  @override
  String get description {
    String panStr(double p) {
      if (p < -0.01) return '${(p * 100).round()}L';
      if (p > 0.01) return '${(p * 100).round()}R';
      return 'C';
    }
    return 'Set pan: $trackName (${panStr(oldPan)} → ${panStr(newPan)})';
  }
}

/// Command to toggle track mute
class SetMuteCommand extends Command {
  final int trackId;
  final String trackName;
  final bool newMute;
  final bool oldMute;

  SetMuteCommand({
    required this.trackId,
    required this.trackName,
    required this.newMute,
    required this.oldMute,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setTrackMute(trackId, mute: newMute);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setTrackMute(trackId, mute: oldMute);
  }

  @override
  String get description =>
      '${newMute ? 'Mute' : 'Unmute'} track: $trackName';
}

/// Command to toggle track solo
class SetSoloCommand extends Command {
  final int trackId;
  final String trackName;
  final bool newSolo;
  final bool oldSolo;

  SetSoloCommand({
    required this.trackId,
    required this.trackName,
    required this.newSolo,
    required this.oldSolo,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setTrackSolo(trackId, solo: newSolo);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setTrackSolo(trackId, solo: oldSolo);
  }

  @override
  String get description =>
      '${newSolo ? 'Solo' : 'Unsolo'} track: $trackName';
}
