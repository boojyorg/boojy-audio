import '../../audio_engine.dart';
import 'command.dart';

/// Command to change project tempo (BPM)
class SetTempoCommand extends Command {
  final double newBpm;
  final double oldBpm;

  /// Callback to update UI state after tempo change
  final void Function(double bpm)? onTempoChanged;

  SetTempoCommand({
    required this.newBpm,
    required this.oldBpm,
    this.onTempoChanged,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setTempo(newBpm);
    onTempoChanged?.call(newBpm);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setTempo(oldBpm);
    onTempoChanged?.call(oldBpm);
  }

  @override
  String get description =>
      'Change Tempo: ${oldBpm.round()} → ${newBpm.round()} BPM';
}

/// Command to change count-in bars
class SetCountInCommand extends Command {
  final int newBars;
  final int oldBars;

  /// Callback to update UI state after count-in change
  final void Function(int bars)? onCountInChanged;

  SetCountInCommand({
    required this.newBars,
    required this.oldBars,
    this.onCountInChanged,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setCountInBars(newBars);
    onCountInChanged?.call(newBars);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setCountInBars(oldBars);
    onCountInChanged?.call(oldBars);
  }

  @override
  String get description =>
      'Change Count-in: $oldBars → $newBars ${newBars == 1 ? 'bar' : 'bars'}';
}
