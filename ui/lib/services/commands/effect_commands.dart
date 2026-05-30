import 'audio_engine_interface.dart';
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
  Future<void> execute(AudioEngineInterface engine) async {
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
  Future<void> undo(AudioEngineInterface engine) async {
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

  /// Effect ids of the rest of the chain, in order, excluding this effect.
  /// Used to restore the removed effect to its original position on undo —
  /// re-adding appends to the end, so we rebuild the order with the restored
  /// id slotted back in at [effectIndex]. Empty means "don't reorder".
  final List<int> siblingEffectIds;

  /// Callback to notify UI when effect is removed
  final void Function(int effectId)? onEffectRemoved;

  /// Callback to notify UI when effect is re-added (undo)
  final void Function(int effectId)? onEffectAdded;

  /// The id currently live in the engine for this effect. Starts as [effectId];
  /// after undo re-creates the effect the engine assigns a *new* id, so we track
  /// it here and re-execute (redo) against the live id, not the stale original.
  late int _currentEffectId = effectId;

  RemoveEffectCommand({
    required this.trackId,
    required this.trackName,
    required this.effectId,
    required this.effectName,
    required this.effectType,
    required this.isVst3,
    required this.effectIndex,
    this.siblingEffectIds = const [],
    this.onEffectRemoved,
    this.onEffectAdded,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.removeEffectFromTrack(trackId, _currentEffectId);
    onEffectRemoved?.call(_currentEffectId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Re-add the effect (the engine appends it to the end of the chain and
    // assigns a new id).
    final int restored = isVst3
        ? engine.addVst3EffectToTrack(trackId, effectType)
        : engine.addEffectToTrack(trackId, effectType);
    if (restored < 0) return;
    _currentEffectId = restored;

    // Restore the original chain position: rebuild the order with the restored
    // id slotted back in at [effectIndex]. Skips cleanly when we have no sibling
    // context (the effect was the only one, or position is irrelevant).
    if (siblingEffectIds.isNotEmpty) {
      final idx = effectIndex.clamp(0, siblingEffectIds.length);
      final order = List<int>.from(siblingEffectIds)..insert(idx, restored);
      engine.reorderTrackEffects(trackId, order);
    }

    onEffectAdded?.call(restored);
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
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setEffectBypass(effectId, bypassed: newBypassed);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
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
  Future<void> execute(AudioEngineInterface engine) async {
    engine.reorderTrackEffects(trackId, newOrder);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
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
  final bool isBuiltIn;
  final void Function(int effectId, String paramName, double value)?
  onParameterChanged;

  SetEffectParameterCommand({
    required this.effectId,
    required this.effectName,
    required this.paramIndex,
    required this.paramName,
    required this.newValue,
    required this.oldValue,
    this.isBuiltIn = false,
    this.onParameterChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    if (isBuiltIn) {
      engine.setEffectParameter(effectId, paramName, newValue);
    } else {
      engine.setVst3ParameterValue(effectId, paramIndex, newValue);
    }
    onParameterChanged?.call(effectId, paramName, newValue);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (isBuiltIn) {
      engine.setEffectParameter(effectId, paramName, oldValue);
    } else {
      engine.setVst3ParameterValue(effectId, paramIndex, oldValue);
    }
    onParameterChanged?.call(effectId, paramName, oldValue);
  }

  @override
  String get description =>
      'Change $effectName: $paramName (${oldValue.toStringAsFixed(2)} → ${newValue.toStringAsFixed(2)})';
}
