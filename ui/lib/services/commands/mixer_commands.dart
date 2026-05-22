import 'audio_engine_interface.dart';
import 'command.dart';

/// Command to change track volume
class SetVolumeCommand extends Command {
  final int trackId;
  final String trackName;
  final double newVolumeDb;
  final double oldVolumeDb;
  final void Function(int trackId, double volumeDb)? onVolumeChanged;

  SetVolumeCommand({
    required this.trackId,
    required this.trackName,
    required this.newVolumeDb,
    required this.oldVolumeDb,
    this.onVolumeChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTrackVolume(trackId, newVolumeDb);
    onVolumeChanged?.call(trackId, newVolumeDb);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setTrackVolume(trackId, oldVolumeDb);
    onVolumeChanged?.call(trackId, oldVolumeDb);
  }

  @override
  String get description =>
      'Set Volume: $trackName (${oldVolumeDb.toStringAsFixed(1)} → ${newVolumeDb.toStringAsFixed(1)} dB)';
}

/// Command to change track pan
class SetPanCommand extends Command {
  final int trackId;
  final String trackName;
  final double newPan;
  final double oldPan;
  final void Function(int trackId, double pan)? onPanChanged;

  SetPanCommand({
    required this.trackId,
    required this.trackName,
    required this.newPan,
    required this.oldPan,
    this.onPanChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTrackPan(trackId, newPan);
    onPanChanged?.call(trackId, newPan);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setTrackPan(trackId, oldPan);
    onPanChanged?.call(trackId, oldPan);
  }

  @override
  String get description {
    String panStr(double p) {
      if (p < -0.01) return '${(p * 100).round()}L';
      if (p > 0.01) return '${(p * 100).round()}R';
      return 'C';
    }

    return 'Set Pan: $trackName (${panStr(oldPan)} → ${panStr(newPan)})';
  }
}

/// Command to toggle track mute
class SetMuteCommand extends Command {
  final int trackId;
  final String trackName;
  final bool newMute;
  final bool oldMute;
  final void Function(int trackId, {required bool muted})? onMuteChanged;

  SetMuteCommand({
    required this.trackId,
    required this.trackName,
    required this.newMute,
    required this.oldMute,
    this.onMuteChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTrackMute(trackId, mute: newMute);
    onMuteChanged?.call(trackId, muted: newMute);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setTrackMute(trackId, mute: oldMute);
    onMuteChanged?.call(trackId, muted: oldMute);
  }

  @override
  String get description => '${newMute ? 'Mute' : 'Unmute'} Track: $trackName';
}

/// Command to toggle track solo
class SetSoloCommand extends Command {
  final int trackId;
  final String trackName;
  final bool newSolo;
  final bool oldSolo;
  final void Function(int trackId, {required bool soloed})? onSoloChanged;

  SetSoloCommand({
    required this.trackId,
    required this.trackName,
    required this.newSolo,
    required this.oldSolo,
    this.onSoloChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTrackSolo(trackId, solo: newSolo);
    onSoloChanged?.call(trackId, soloed: newSolo);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setTrackSolo(trackId, solo: oldSolo);
    onSoloChanged?.call(trackId, soloed: oldSolo);
  }

  @override
  String get description => '${newSolo ? 'Solo' : 'Unsolo'} Track: $trackName';
}
