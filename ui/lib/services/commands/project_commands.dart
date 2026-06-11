import 'audio_engine_interface.dart';
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
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setTempo(newBpm);
    onTempoChanged?.call(newBpm);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
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
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setCountInBars(newBars);
    onCountInChanged?.call(newBars);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setCountInBars(oldBars);
    onCountInChanged?.call(oldBars);
  }

  @override
  String get description =>
      'Change Count-in: $oldBars → $newBars ${newBars == 1 ? 'bar' : 'bars'}';
}

/// Command to change the project time signature.
/// The engine call + UI metadata update both happen inside [onChanged], so this
/// command stays independent of the concrete engine (`setTimeSignature` is not
/// on the mockable [AudioEngineInterface]). Only the numerator reaches the
/// engine today; the denominator is UI metadata.
class SetTimeSignatureCommand extends Command {
  final int newNumerator;
  final int oldNumerator;
  final int newDenominator;
  final int oldDenominator;

  /// Applies a (numerator, denominator) to the engine + UI metadata.
  final void Function(int numerator, int denominator) onChanged;

  SetTimeSignatureCommand({
    required this.newNumerator,
    required this.oldNumerator,
    required this.newDenominator,
    required this.oldDenominator,
    required this.onChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onChanged(newNumerator, newDenominator);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onChanged(oldNumerator, oldDenominator);
  }

  @override
  String get description =>
      'Change Time Signature: $oldNumerator/$oldDenominator → $newNumerator/$newDenominator';
}

/// Command to change a track's colour override (UI-only, persisted in
/// `ui_layout.json`). Colours are passed as ARGB ints so this stays free of
/// Flutter imports; a null value means "no override" (revert to the
/// auto-assigned colour).
class SetTrackColorCommand extends Command {
  final int trackId;
  final int newColorArgb;
  final int? oldColorArgb;

  /// Applies a colour to the track (null clears the override).
  final void Function(int trackId, int? colorArgb) onColorChanged;

  SetTrackColorCommand({
    required this.trackId,
    required this.newColorArgb,
    required this.oldColorArgb,
    required this.onColorChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onColorChanged(trackId, newColorArgb);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onColorChanged(trackId, oldColorArgb);
  }

  @override
  String get description => 'Change Track Colour';
}

/// Command to change a track's icon override (UI-only, persisted in
/// `ui_layout.json`). Icons are stable string keys from
/// `utils/track_icons.dart` (e.g. 'mic', 'piano'); a null value means
/// "no override" (revert to the auto-detected icon).
class SetTrackIconCommand extends Command {
  final int trackId;
  final String newIconKey;
  final String? oldIconKey;

  /// Applies an icon key to the track (null clears the override).
  final void Function(int trackId, String? iconKey) onIconChanged;

  SetTrackIconCommand({
    required this.trackId,
    required this.newIconKey,
    required this.oldIconKey,
    required this.onIconChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onIconChanged(trackId, newIconKey);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onIconChanged(trackId, oldIconKey);
  }

  @override
  String get description => 'Change Track Icon';
}
