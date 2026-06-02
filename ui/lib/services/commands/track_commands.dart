import 'audio_engine_interface.dart';
import 'command.dart';

/// Command to create a new track
class CreateTrackCommand extends Command {
  final String trackType;
  final String trackName;
  int? _createdTrackId;

  CreateTrackCommand({required this.trackType, required this.trackName});

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

/// One captured effect in a track's FX chain, snapshotted before deletion so the
/// whole chain can be rebuilt — in order — on undo. Built-in effects round-trip
/// through their parameter setters; VST3 plugins (including instruments like
/// Serum) round-trip through their plugin path + opaque state blob.
sealed class _EffectSnapshot {}

/// A built-in effect: rebuilt via `addEffectToTrack` + per-param setters.
class _BuiltinEffectSnapshot extends _EffectSnapshot {
  final String
  type; // "eq", "compressor", "reverb", "delay", "chorus", "limiter"
  final bool bypassed;
  final Map<String, double> params;

  _BuiltinEffectSnapshot({
    required this.type,
    required this.bypassed,
    required this.params,
  });
}

/// A VST3 plugin: rebuilt via `addVst3EffectToTrack(path)` + `setVst3State`.
/// [name] is carried so the restored plugin can be re-registered with the UI's
/// plugin manager (so its editor/param panel and the track's plugin-count chip
/// reappear).
class _Vst3EffectSnapshot extends _EffectSnapshot {
  final String path;
  final String name;
  final String stateBase64;
  final bool bypassed;

  _Vst3EffectSnapshot({
    required this.path,
    required this.name,
    required this.stateBase64,
    required this.bypassed,
  });
}

/// A VST3 plugin that undo successfully reloaded onto the recreated track,
/// reported back so the caller can re-register it with the UI plugin manager.
typedef RestoredVst3 = ({int effectId, String path, String name});

/// Command to delete a track, with full content restore on undo.
///
/// Previously undo recreated an empty mixer-settings-only shell: clips, MIDI,
/// effects, and sends were shredded (C68/C76/C97), and redo targeted the stale
/// original engine id so the restored track never went away (C62). Now:
///
/// - **Engine-side state** (mixer, sends, the full FX chain — built-in effects
///   *and* VST3 plugins/instruments with their state) is snapshotted in
///   [execute] and rebuilt, in chain order, in [undo] by this command.
/// - **UI/manager state** (MIDI + audio clips, controller, selection) is
///   restored by [onRestoreUi], a callback supplied by the DAW layer where the
///   playback managers live. [onCleanup] runs the post-delete UI teardown.
/// - Restored VST3 plugins are reported via [onVst3Restored] so the DAW layer
///   can re-register them with the UI plugin manager (editor + count chip).
/// - The engine id created on undo is tracked in [_currentTrackId] so redo
///   deletes the *live* track, not the gone original (C62).
///
/// Remaining documented limitations (surfaced via [onNotice]): tweaked
/// built-in-*synth* parameters (a fresh default synth is recreated with the
/// track — `get_synth_parameters` is an engine stub) and the track's exact
/// position in the list / group nesting. A VST3 plugin that can't be reloaded
/// (moved or uninstalled since the delete) is also surfaced via [onNotice].
class DeleteTrackCommand extends Command {
  final int trackId;
  final String trackName;
  final String trackType;

  // Mixer state captured up-front by the caller (read before the track is gone).
  double? _volumeDb;
  double? _pan;
  bool? _mute;
  bool? _solo;
  final bool? _armed;

  /// Post-delete UI teardown (close plugin windows, drop clips from managers,
  /// refresh). Called with the live track id (original on first delete, the
  /// recreated id on redo).
  final void Function(int trackId)? onCleanup;

  /// Restore UI/manager-side content onto the freshly recreated track. Receives
  /// the *new* engine track id; the DAW layer re-stamps and re-adds the clips it
  /// snapshotted before deletion.
  final void Function(int newTrackId)? onRestoreUi;

  /// Report VST3 plugins that undo reloaded onto the recreated track, so the DAW
  /// layer can re-register them with the UI plugin manager. Receives the new
  /// track id and the reloaded plugins (with their fresh engine effect ids).
  final void Function(int newTrackId, List<RestoredVst3> restored)?
  onVst3Restored;

  /// Surface a user-facing notice (e.g. "a plugin couldn't be reloaded").
  final void Function(String message)? onNotice;

  // Captured at execute() time (engine-side).
  List<({int returnId, double amountDb})> _sends = const [];
  List<_EffectSnapshot> _effects = const [];

  /// Live engine id for redo. Starts as [trackId]; undo recreates the track and
  /// the engine assigns a new id, tracked here so redo deletes the right one.
  late int _currentTrackId = trackId;

  DeleteTrackCommand({
    required this.trackId,
    required this.trackName,
    required this.trackType,
    double? volumeDb,
    double? pan,
    bool? mute,
    bool? solo,
    bool? armed,
    this.onCleanup,
    this.onRestoreUi,
    this.onVst3Restored,
    this.onNotice,
  }) : _volumeDb = volumeDb,
       _pan = pan,
       _mute = mute,
       _solo = solo,
       _armed = armed;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Runs for both the initial delete and redo. `_currentTrackId` is the live
    // track: `trackId` first time, the recreated id after an undo (C62) — so we
    // snapshot from and delete the right one, never the stale original.
    final liveId = _currentTrackId;

    // Mixer state: prefer the values passed in; fall back to a live read.
    final info = engine.getTrackInfo(liveId);
    if (info.isNotEmpty && !info.startsWith('Error')) {
      final parts = info.split(',');
      if (parts.length >= 7) {
        _volumeDb ??= double.tryParse(parts[3]);
        _pan ??= double.tryParse(parts[4]);
        _mute ??= parts[5] == 'true' || parts[5] == '1';
        _solo ??= parts[6] == 'true' || parts[6] == '1';
      }
    }

    // Snapshot sends ("targetId,amountDb,name;..." — amount already in dB).
    _sends = _parseSends(engine.getTrackSends(liveId));

    // Snapshot the whole FX chain (built-in effects + VST3 plugins) in order, so
    // undo can rebuild it exactly — instruments stay ahead of their effects.
    _effects = _snapshotEffects(engine, liveId);

    engine.deleteTrack(liveId);
    onCleanup?.call(liveId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    final newTrackId = engine.createTrack(trackType, trackName);
    if (newTrackId < 0) return;
    _currentTrackId = newTrackId;

    // Mixer
    if (_volumeDb != null) engine.setTrackVolume(newTrackId, _volumeDb!);
    if (_pan != null) engine.setTrackPan(newTrackId, _pan!);
    if (_mute != null) engine.setTrackMute(newTrackId, mute: _mute!);
    if (_solo != null) engine.setTrackSolo(newTrackId, solo: _solo!);
    if (_armed != null) engine.setTrackArmed(newTrackId, armed: _armed);

    // Rebuild the FX chain in original order. Built-in effects round-trip via
    // their param setters; VST3 plugins via path + opaque state blob. Keeping
    // one ordered pass preserves interleaving (e.g. instrument before its EQ).
    final restoredVst3 = <RestoredVst3>[];
    var anyVst3Failed = false;
    for (final fx in _effects) {
      switch (fx) {
        case final _BuiltinEffectSnapshot b:
          final effectId = engine.addEffectToTrack(newTrackId, b.type);
          if (effectId < 0) continue;
          b.params.forEach((name, value) {
            engine.setEffectParameter(effectId, name, value);
          });
          if (b.bypassed) engine.setEffectBypass(effectId, bypassed: true);
        case final _Vst3EffectSnapshot v:
          final effectId = engine.addVst3EffectToTrack(newTrackId, v.path);
          if (effectId < 0) {
            // Plugin moved or uninstalled since the delete — can't reload.
            anyVst3Failed = true;
            continue;
          }
          if (v.stateBase64.isNotEmpty && !v.stateBase64.startsWith('Error')) {
            engine.setVst3State(effectId, v.stateBase64);
          }
          if (v.bypassed) engine.setEffectBypass(effectId, bypassed: true);
          restoredVst3.add((effectId: effectId, path: v.path, name: v.name));
      }
    }
    // Hand reloaded plugins back so the UI plugin manager can re-register them.
    if (restoredVst3.isNotEmpty) {
      onVst3Restored?.call(newTrackId, restoredVst3);
    }

    // Sends (target return tracks still exist — only this track was deleted).
    for (final send in _sends) {
      engine.addSend(newTrackId, send.returnId, send.amountDb);
    }

    // UI/manager-side content (clips, controller, selection).
    onRestoreUi?.call(newTrackId);

    if (anyVst3Failed) {
      onNotice?.call(
        'Track "$trackName" restored, but a plugin couldn\'t be reloaded — '
        'it may have been moved or uninstalled.',
      );
    }
  }

  /// Parse "targetId,amountDb,name;targetId,amountDb,name" into send specs.
  static List<({int returnId, double amountDb})> _parseSends(String csv) {
    if (csv.isEmpty) return const [];
    final result = <({int returnId, double amountDb})>[];
    for (final entry in csv.split(';')) {
      if (entry.isEmpty) continue;
      final parts = entry.split(',');
      if (parts.length < 2) continue;
      final returnId = int.tryParse(parts[0]);
      final amountDb = double.tryParse(parts[1]);
      if (returnId != null && amountDb != null) {
        result.add((returnId: returnId, amountDb: amountDb));
      }
    }
    return result;
  }

  /// Snapshot the track's full FX chain (in order) via getTrackEffects +
  /// getEffectInfo. Built-in effects capture their params; VST3 plugins capture
  /// their plugin path + opaque state blob so undo can fully reload them.
  List<_EffectSnapshot> _snapshotEffects(
    AudioEngineInterface engine,
    int liveId,
  ) {
    final idsCsv = engine.getTrackEffects(liveId);
    if (idsCsv.isEmpty) return const [];
    final snapshots = <_EffectSnapshot>[];
    for (final idStr in idsCsv.split(',')) {
      final effectId = int.tryParse(idStr.trim());
      if (effectId == null) continue;
      final info = engine.getEffectInfo(effectId);

      // VST3 is formatted "type:vst3,bypassed:X,name:NAME,path:PATH" with path
      // last (it may contain commas). Pull path/name off by marker, not split.
      if (info.startsWith('type:vst3')) {
        final vst3 = _parseVst3Info(engine, effectId, info);
        if (vst3 != null) snapshots.add(vst3);
        continue;
      }

      // Built-in: "type:eq,bypassed:0,low_freq:..,low_gain:..,.."
      final fields = <String, String>{};
      for (final pair in info.split(',')) {
        final kv = pair.split(':');
        if (kv.length == 2) fields[kv[0].trim()] = kv[1].trim();
      }
      final type = fields['type'];
      if (type == null) continue;
      final bypassed = fields['bypassed'] == '1';
      final params = <String, double>{};
      fields.forEach((key, value) {
        if (key == 'type' || key == 'bypassed') return;
        final v = double.tryParse(value);
        if (v != null) params[key] = v;
      });
      snapshots.add(
        _BuiltinEffectSnapshot(type: type, bypassed: bypassed, params: params),
      );
    }
    return snapshots;
  }

  /// Parse a VST3 getEffectInfo string + read its state blob. Returns null if no
  /// usable plugin path is present.
  _Vst3EffectSnapshot? _parseVst3Info(
    AudioEngineInterface engine,
    int effectId,
    String info,
  ) {
    // path: is last, so everything after the marker is the path (may contain ',').
    const pathMarker = ',path:';
    final pathIdx = info.indexOf(pathMarker);
    if (pathIdx < 0) return null;
    final path = info.substring(pathIdx + pathMarker.length);
    if (path.isEmpty) return null;

    // name: is the field just before path:, so it runs to the path marker.
    final head = info.substring(0, pathIdx); // "type:vst3,bypassed:X,name:NAME"
    var name = '';
    var beforeName = head;
    const nameMarker = ',name:';
    final nameIdx = head.indexOf(nameMarker);
    if (nameIdx >= 0) {
      name = head.substring(nameIdx + nameMarker.length);
      beforeName = head.substring(0, nameIdx); // "type:vst3,bypassed:X"
    }
    final bypassed = beforeName.contains('bypassed:1');

    final state = engine.getVst3State(effectId);
    return _Vst3EffectSnapshot(
      path: path,
      name: name,
      stateBase64: state,
      bypassed: bypassed,
    );
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
  String get description => '${newArmed ? 'Arm' : 'Disarm'} Track: $trackName';
}
