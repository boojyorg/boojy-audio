import '../../audio_engine.dart';
import 'command.dart';

/// Command to add an effect to a track
class AddEffectCommand extends Command {
  final int trackId;
  final String trackName;
  final String effectType; // Built-in effect type or VST3 path
  final String effectName;
  final bool isVst3;

  int? _createdEffectId;

  /// Callback to notify UI when effect is added (provides effectId)
  final void Function(int effectId)? onEffectAdded;

  /// Callback to notify UI when effect is removed (undo)
  final void Function(int effectId)? onEffectRemoved;

  AddEffectCommand({
    required this.trackId,
    required this.trackName,
    required this.effectType,
    required this.effectName,
    required this.isVst3,
    this.onEffectAdded,
    this.onEffectRemoved,
  });

  /// Get the created effect ID (available after execute)
  int? get createdEffectId => _createdEffectId;

  @override
  Future<void> execute(AudioEngine engine) async {
    if (isVst3) {
      _createdEffectId = engine.addVst3EffectToTrack(trackId, effectType);
    } else {
      _createdEffectId = engine.addEffectToTrack(trackId, effectType);
    }
    if (_createdEffectId != null && _createdEffectId! >= 0) {
      onEffectAdded?.call(_createdEffectId!);
    }
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    if (_createdEffectId != null && _createdEffectId! >= 0) {
      engine.removeEffectFromTrack(trackId, _createdEffectId!);
      onEffectRemoved?.call(_createdEffectId!);
    }
  }

  @override
  String get description => 'Add Effect: $effectName';
}

/// Command to remove an effect from a track
class RemoveEffectCommand extends Command {
  final int trackId;
  final String trackName;
  final int effectId;
  final String effectName;
  final String effectType; // For re-adding on undo
  final bool isVst3;
  final int effectIndex; // Position in chain for proper restoration

  /// Callback to notify UI when effect is removed
  final void Function(int effectId)? onEffectRemoved;

  /// Callback to notify UI when effect is re-added (undo)
  final void Function(int effectId)? onEffectAdded;

  int? _restoredEffectId;

  RemoveEffectCommand({
    required this.trackId,
    required this.trackName,
    required this.effectId,
    required this.effectName,
    required this.effectType,
    required this.isVst3,
    required this.effectIndex,
    this.onEffectRemoved,
    this.onEffectAdded,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.removeEffectFromTrack(trackId, effectId);
    onEffectRemoved?.call(effectId);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    // Re-add the effect
    if (isVst3) {
      _restoredEffectId = engine.addVst3EffectToTrack(trackId, effectType);
    } else {
      _restoredEffectId = engine.addEffectToTrack(trackId, effectType);
    }
    if (_restoredEffectId != null && _restoredEffectId! >= 0) {
      onEffectAdded?.call(_restoredEffectId!);
    }
  }

  @override
  String get description => 'Remove Effect: $effectName';
}

/// Command to toggle effect bypass
class BypassEffectCommand extends Command {
  final int effectId;
  final String effectName;
  final bool newBypassed;
  final bool oldBypassed;

  BypassEffectCommand({
    required this.effectId,
    required this.effectName,
    required this.newBypassed,
    required this.oldBypassed,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setEffectBypass(effectId, bypassed: newBypassed);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setEffectBypass(effectId, bypassed: oldBypassed);
  }

  @override
  String get description =>
      '${newBypassed ? 'Bypass' : 'Enable'} Effect: $effectName';
}

/// Command to reorder effects in chain
class ReorderEffectsCommand extends Command {
  final int trackId;
  final String trackName;
  final List<int> newOrder;
  final List<int> oldOrder;

  ReorderEffectsCommand({
    required this.trackId,
    required this.trackName,
    required this.newOrder,
    required this.oldOrder,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.reorderTrackEffects(trackId, newOrder);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.reorderTrackEffects(trackId, oldOrder);
  }

  @override
  String get description => 'Reorder Effects: $trackName';
}

/// Command to change an effect parameter value
class SetEffectParameterCommand extends Command {
  final int effectId;
  final String effectName;
  final int paramIndex;
  final String paramName;
  final double newValue;
  final double oldValue;

  SetEffectParameterCommand({
    required this.effectId,
    required this.effectName,
    required this.paramIndex,
    required this.paramName,
    required this.newValue,
    required this.oldValue,
  });

  @override
  Future<void> execute(AudioEngine engine) async {
    engine.setVst3ParameterValue(effectId, paramIndex, newValue);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setVst3ParameterValue(effectId, paramIndex, oldValue);
  }

  @override
  String get description =>
      'Change $effectName: $paramName (${oldValue.toStringAsFixed(2)} → ${newValue.toStringAsFixed(2)})';
}
