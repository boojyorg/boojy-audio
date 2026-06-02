import '../../models/clip_data.dart';
import '../../utils/logger.dart';
import '../../models/midi_note_data.dart';
import '../../utils/clip_overlap_handler.dart';
import 'audio_engine_interface.dart';
import 'command.dart';

/// Counter for generating unique clip IDs
int _clipIdCounter = 0;

/// Generate a unique clip ID that won't collide even in rapid succession
int _generateUniqueClipId() {
  _clipIdCounter++;
  return DateTime.now().microsecondsSinceEpoch + _clipIdCounter;
}

/// Command to move a MIDI clip on the timeline
class MoveMidiClipCommand extends Command {
  final int clipId;
  final String clipName;
  final double newStartTime;
  final double oldStartTime;
  final int? newTrackId;
  final int? oldTrackId;

  MoveMidiClipCommand({
    required this.clipId,
    required this.clipName,
    required this.newStartTime,
    required this.oldStartTime,
    this.newTrackId,
    this.oldTrackId,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Note: This updates the clip position in the engine
    // The actual implementation depends on your engine API
    // For now, this is handled in Flutter state
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Restore previous position
  }

  @override
  String get description =>
      'Move Clip: $clipName (${oldStartTime.toStringAsFixed(2)}s → ${newStartTime.toStringAsFixed(2)}s)';
}

/// Command to move an audio clip on the timeline.
///
/// `onClipMoved(clipId, startTime)` syncs the on-screen clip list on
/// execute/undo/redo. Without it the engine position changes but the timeline's
/// stateful `clips` list does not, so an undone move leaves the clip stuck at
/// the moved position (the bug this callback fixes — mirrors the MIDI move
/// command's `onClipMoved`).
class MoveAudioClipCommand extends Command {
  final int trackId;
  final int clipId;
  final String clipName;
  final double newStartTime;
  final double oldStartTime;
  final void Function(int clipId, double startTime)? onClipMoved;

  MoveAudioClipCommand({
    required this.trackId,
    required this.clipId,
    required this.clipName,
    required this.newStartTime,
    required this.oldStartTime,
    this.onClipMoved,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setClipStartTime(trackId, clipId, newStartTime);
    onClipMoved?.call(clipId, newStartTime);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setClipStartTime(trackId, clipId, oldStartTime);
    onClipMoved?.call(clipId, oldStartTime);
  }

  @override
  String get description =>
      'Move Audio Clip: $clipName (${oldStartTime.toStringAsFixed(2)}s → ${newStartTime.toStringAsFixed(2)}s)';
}

/// Undoable wrapper for "new clip wins" audio overlap resolution.
///
/// When a clip is moved (or created) over its neighbours, [ClipOverlapHandler]
/// resolves the overlap by deleting / trimming / splitting them. Previously that
/// destruction was applied directly to the engine + UI, *outside* any command,
/// so it could not be undone (bug H-11). This command performs exactly that
/// destruction in `execute` and inverts it in `undo`, using the full before-state
/// the overlap result already carries.
///
/// Engine reloads/duplicates assign *new* clip ids, so the live id of every clip
/// this command removes or creates is tracked across execute/undo cycles —
/// otherwise a redo would target a stale id and silently no-op (the same hazard
/// [DeleteAudioClipCommand] guards against).
class ResolveAudioOverlapCommand extends Command {
  final AudioOverlapResult result;

  /// Remove a clip from the UI clip list by id.
  final void Function(int clipId)? uiRemoveClip;

  /// Update an existing clip in the UI clip list (matched by `clip.clipId`).
  final void Function(ClipData clip)? uiUpdateClip;

  /// Add a clip to the UI clip list.
  final void Function(ClipData clip)? uiAddClip;

  // Live engine ids, updated whenever a clip is reloaded/duplicated.
  late final List<int> _removalIds = result.removals
      .map((c) => c.clipId)
      .toList();
  late final List<int> _splitOriginalIds = result.splits
      .map((s) => s.original.clipId)
      .toList();
  late final List<int?> _splitPartBIds = List<int?>.filled(
    result.splits.length,
    null,
  );

  ResolveAudioOverlapCommand({
    required this.result,
    this.uiRemoveClip,
    this.uiUpdateClip,
    this.uiAddClip,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Removals: delete fully-covered neighbours.
    for (var i = 0; i < result.removals.length; i++) {
      final clip = result.removals[i];
      engine.removeAudioClip(clip.trackId, _removalIds[i]);
      uiRemoveClip?.call(_removalIds[i]);
    }

    // Updates: trims (id is stable — the clip is resized in place).
    for (final u in result.updates) {
      final c = u.updated;
      engine.setClipStartTime(c.trackId, c.clipId, c.startTime);
      engine.setClipOffset(c.trackId, c.clipId, c.offset);
      engine.setClipDuration(c.trackId, c.clipId, c.duration);
      uiUpdateClip?.call(c);
    }

    // Splits: duplicate Part B BEFORE modifying the original (the duplicate
    // copies the original's full state), then trim or remove the original.
    for (var i = 0; i < result.splits.length; i++) {
      final s = result.splits[i];
      final origId = _splitOriginalIds[i];
      final tmpl = s.partBTemplate;
      if (tmpl != null) {
        final partBId = engine.duplicateAudioClip(
          s.original.trackId,
          origId,
          tmpl.startTime,
        );
        if (partBId > 0) {
          engine.setClipOffset(s.original.trackId, partBId, tmpl.offset);
          engine.setClipDuration(s.original.trackId, partBId, tmpl.duration);
          _splitPartBIds[i] = partBId;
          uiAddClip?.call(tmpl.copyWith(clipId: partBId));
        }
      }
      final partA = s.partA;
      if (partA != null) {
        engine.setClipDuration(s.original.trackId, origId, partA.duration);
        uiUpdateClip?.call(partA.copyWith(clipId: origId));
      } else {
        engine.removeAudioClip(s.original.trackId, origId);
        uiRemoveClip?.call(origId);
      }
    }
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Invert in reverse order: splits, then updates, then removals.
    for (var i = result.splits.length - 1; i >= 0; i--) {
      final s = result.splits[i];
      final origId = _splitOriginalIds[i];

      // Remove the Part B we created.
      final partBId = _splitPartBIds[i];
      if (partBId != null) {
        engine.removeAudioClip(s.original.trackId, partBId);
        uiRemoveClip?.call(partBId);
        _splitPartBIds[i] = null;
      }

      if (s.partA != null) {
        // Original was trimmed in place → restore it fully.
        engine.setClipStartTime(
          s.original.trackId,
          origId,
          s.original.startTime,
        );
        engine.setClipOffset(s.original.trackId, origId, s.original.offset);
        engine.setClipDuration(s.original.trackId, origId, s.original.duration);
        uiUpdateClip?.call(s.original.copyWith(clipId: origId));
      } else {
        // Original was removed → reload it (engine assigns a new id).
        final newId = engine.loadAudioFileToTrack(
          s.original.filePath,
          s.original.trackId,
          startTime: s.original.startTime,
        );
        if (newId >= 0) {
          engine.setClipOffset(s.original.trackId, newId, s.original.offset);
          engine.setClipDuration(
            s.original.trackId,
            newId,
            s.original.duration,
          );
          _splitOriginalIds[i] = newId;
          uiAddClip?.call(s.original.copyWith(clipId: newId));
        }
      }
    }

    for (var i = result.updates.length - 1; i >= 0; i--) {
      final o = result.updates[i].original;
      engine.setClipStartTime(o.trackId, o.clipId, o.startTime);
      engine.setClipOffset(o.trackId, o.clipId, o.offset);
      engine.setClipDuration(o.trackId, o.clipId, o.duration);
      uiUpdateClip?.call(o);
    }

    for (var i = result.removals.length - 1; i >= 0; i--) {
      final clip = result.removals[i];
      final newId = engine.loadAudioFileToTrack(
        clip.filePath,
        clip.trackId,
        startTime: clip.startTime,
      );
      if (newId >= 0) {
        engine.setClipOffset(clip.trackId, newId, clip.offset);
        engine.setClipDuration(clip.trackId, newId, clip.duration);
        _removalIds[i] = newId;
        uiAddClip?.call(clip.copyWith(clipId: newId));
      } else {
        uiAddClip?.call(clip);
      }
    }
  }

  @override
  String get description => 'Resolve clip overlap';
}

/// Undoable wrapper for "new clip wins" MIDI overlap resolution — the MIDI
/// counterpart of [ResolveAudioOverlapCommand] (bug H-11).
///
/// `execute` performs exactly what `ClipOverlapHandler.applyMidiResult` did
/// (delete fully-covered neighbours, trim partial overlaps, split clips the new
/// region lands inside), and `undo` inverts it from the full before-state the
/// result carries. MIDI clip ids are stable across delete/re-add
/// (`MidiPlaybackManager.addRecordedClip` preserves `clipId`) and split parts
/// carry pre-assigned ids, so execute/undo/redo all round-trip cleanly.
class ResolveMidiOverlapCommand extends Command {
  final MidiOverlapResult result;
  final double tempo;

  final void Function(int clipId, int trackId)? deleteClip;
  final void Function(MidiClipData clip)? updateClipInPlace;
  final void Function(MidiClipData clip, double tempo)? rescheduleClip;
  final void Function(MidiClipData clip)? addClip;

  ResolveMidiOverlapCommand({
    required this.result,
    required this.tempo,
    this.deleteClip,
    this.updateClipInPlace,
    this.rescheduleClip,
    this.addClip,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    for (final clip in result.removals) {
      deleteClip?.call(clip.clipId, clip.trackId);
    }
    for (final s in result.splits) {
      deleteClip?.call(s.original.clipId, s.original.trackId);
    }
    for (final u in result.updates) {
      updateClipInPlace?.call(u.updated);
      rescheduleClip?.call(u.updated, tempo);
    }
    for (final s in result.splits) {
      final a = s.partA;
      if (a != null) {
        addClip?.call(a);
        rescheduleClip?.call(a, tempo);
      }
      final b = s.partB;
      if (b != null) {
        addClip?.call(b);
        rescheduleClip?.call(b, tempo);
      }
    }
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Remove the split parts we created.
    for (final s in result.splits) {
      final a = s.partA;
      if (a != null) deleteClip?.call(a.clipId, a.trackId);
      final b = s.partB;
      if (b != null) deleteClip?.call(b.clipId, b.trackId);
    }
    // Re-add the originals we split.
    for (final s in result.splits) {
      addClip?.call(s.original);
      rescheduleClip?.call(s.original, tempo);
    }
    // Restore trimmed clips to their original state.
    for (final u in result.updates) {
      updateClipInPlace?.call(u.original);
      rescheduleClip?.call(u.original, tempo);
    }
    // Re-add fully-removed clips.
    for (final clip in result.removals) {
      addClip?.call(clip);
      rescheduleClip?.call(clip, tempo);
    }
  }

  @override
  String get description => 'Resolve MIDI clip overlap';
}

/// Command to delete a MIDI clip
class DeleteMidiClipCommand extends Command {
  final MidiClipData clipData;

  DeleteMidiClipCommand({required this.clipData});

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Delete clip from engine
    // Note: Implement engine.deleteMidiClip() if not exists
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Recreate the clip with stored data
    // This requires storing all clip state
  }

  @override
  String get description => 'Delete MIDI Clip: ${clipData.name}';
}

/// Snapshot-based command for MIDI clip note changes
/// Stores before/after state of the entire clip for undo/redo
class MidiClipSnapshotCommand extends Command {
  final MidiClipData beforeState;
  final MidiClipData afterState;
  final String _description;

  // Callback to apply state changes back to the UI
  final void Function(MidiClipData)? onApplyState;

  MidiClipSnapshotCommand({
    required this.beforeState,
    required this.afterState,
    required String actionDescription,
    this.onApplyState,
  }) : _description = actionDescription;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Apply the "after" state
    onApplyState?.call(afterState);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Apply the "before" state
    onApplyState?.call(beforeState);
  }

  @override
  String get description => _description;
}

/// Command to add a single MIDI note
class AddMidiNoteCommand extends Command {
  final MidiClipData clipBefore;
  final MidiClipData clipAfter;
  final MidiNoteData addedNote;
  final void Function(MidiClipData)? onApplyState;

  AddMidiNoteCommand({
    required this.clipBefore,
    required this.clipAfter,
    required this.addedNote,
    this.onApplyState,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description => 'Add Note: ${addedNote.noteName}';
}

/// Command to delete MIDI note(s)
class DeleteMidiNotesCommand extends Command {
  final MidiClipData clipBefore;
  final MidiClipData clipAfter;
  final int noteCount;
  final void Function(MidiClipData)? onApplyState;

  DeleteMidiNotesCommand({
    required this.clipBefore,
    required this.clipAfter,
    required this.noteCount,
    this.onApplyState,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description =>
      noteCount == 1 ? 'Delete Note' : 'Delete $noteCount Notes';
}

/// Command to move MIDI note(s)
class MoveMidiNotesCommand extends Command {
  final MidiClipData clipBefore;
  final MidiClipData clipAfter;
  final int noteCount;
  final void Function(MidiClipData)? onApplyState;

  MoveMidiNotesCommand({
    required this.clipBefore,
    required this.clipAfter,
    required this.noteCount,
    this.onApplyState,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description =>
      noteCount == 1 ? 'Move Note' : 'Move $noteCount Notes';
}

/// Command to resize MIDI note(s)
class ResizeMidiNotesCommand extends Command {
  final MidiClipData clipBefore;
  final MidiClipData clipAfter;
  final int noteCount;
  final void Function(MidiClipData)? onApplyState;

  ResizeMidiNotesCommand({
    required this.clipBefore,
    required this.clipAfter,
    required this.noteCount,
    this.onApplyState,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description =>
      noteCount == 1 ? 'Resize Note' : 'Resize $noteCount Notes';
}

/// Command to split a MIDI clip at the playhead position
/// Creates two clips: one before the split point, one after
/// Splits a MIDI clip into two halves at [splitPointBeats], undoably.
///
/// IMPORTANT — primitive contract. This command works on the clip store
/// *directly* through [deleteClip] / [addClip] / [selectClip]. It must NOT be
/// wired to the heavyweight `onCopied` / `onDeleted` arrangement callbacks:
/// those each push their *own* undo command, reassign the clip id, and run
/// overlap-resolution that trims neighbours — so feeding a split through them
/// nests commands, desyncs the ids this command tracks, and destroys the right
/// region on undo (the data-loss bug this rewrite fixes). The injected
/// primitives are the same low-level engine+manager ops used by recording:
///   * [deleteClip] removes a clip from the Dart store AND the engine.
///   * [addClip] adds a clip (preserving its id) AND schedules it in the engine.
///   * [selectClip] selects a clip for editing (optional).
class SplitMidiClipCommand extends Command {
  final MidiClipData originalClip;
  final double
  splitPointBeats; // Split position relative to clip start (in beats)

  /// Remove a clip from the Dart store and the engine (by id + track).
  final void Function(int clipId, int trackId)? deleteClip;

  /// Add a clip to the Dart store and schedule it in the engine (id preserved).
  final void Function(MidiClipData clip)? addClip;

  /// Select a clip for editing (optional — UX nicety, not correctness).
  final void Function(MidiClipData clip)? selectClip;

  // Generated clip IDs for the split clips.
  late final int leftClipId;
  late final int rightClipId;

  // The two halves, computed once so execute and redo apply identical data.
  late final MidiClipData _leftClip;
  late final MidiClipData _rightClip;

  SplitMidiClipCommand({
    required this.originalClip,
    required this.splitPointBeats,
    this.deleteClip,
    this.addClip,
    this.selectClip,
  }) {
    leftClipId = _generateUniqueClipId();
    rightClipId = _generateUniqueClipId();
    _computeHalves();
  }

  void _computeHalves() {
    // Split notes into two groups based on the split point.
    final leftNotes = <MidiNoteData>[];
    final rightNotes = <MidiNoteData>[];

    for (final note in originalClip.notes) {
      if (note.endTime <= splitPointBeats) {
        // Note is entirely in the left clip
        leftNotes.add(note);
      } else if (note.startTime >= splitPointBeats) {
        // Note is entirely in the right clip - adjust its start time
        rightNotes.add(
          note.copyWith(
            startTime: note.startTime - splitPointBeats,
            id: '${note.note}_${note.startTime - splitPointBeats}_${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
      } else {
        // Note straddles the split point - truncate it to the left clip
        leftNotes.add(
          note.copyWith(duration: splitPointBeats - note.startTime),
        );
      }
    }

    // Slice automation at the split point
    final leftAutomation = originalClip.automation.sliceLeft(splitPointBeats);
    final rightAutomation = originalClip.automation.sliceRight(splitPointBeats);

    // Left clip (same start, shortened duration)
    _leftClip = originalClip.copyWith(
      clipId: leftClipId,
      duration: splitPointBeats,
      loopLength: splitPointBeats.clamp(0.25, originalClip.loopLength),
      notes: leftNotes,
      name: '${originalClip.name} (L)',
      automation: leftAutomation,
    );

    // Right clip (starts at split point, remaining duration)
    final rightDuration = originalClip.duration - splitPointBeats;
    _rightClip = originalClip.copyWith(
      clipId: rightClipId,
      startTime: originalClip.startTime + splitPointBeats,
      duration: rightDuration,
      loopLength: rightDuration.clamp(0.25, originalClip.loopLength),
      notes: rightNotes,
      name: '${originalClip.name} (R)',
      automation: rightAutomation,
    );
  }

  MidiClipData get leftClip => _leftClip;
  MidiClipData get rightClip => _rightClip;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Replace the original with its two halves.
    deleteClip?.call(originalClip.clipId, originalClip.trackId);
    addClip?.call(_leftClip);
    addClip?.call(_rightClip);
    selectClip?.call(_rightClip); // right half = continued-editing focus
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Remove BOTH halves, then restore the original intact (full right region).
    deleteClip?.call(leftClipId, originalClip.trackId);
    deleteClip?.call(rightClipId, originalClip.trackId);
    addClip?.call(originalClip);
    selectClip?.call(originalClip);
  }

  @override
  String get description => 'Split MIDI Clip: ${originalClip.name}';
}

/// Command to split an audio clip at the playhead position
/// Creates two clips using offset for non-destructive editing
class SplitAudioClipCommand extends Command {
  final int originalClipId;
  final int originalTrackId;
  final String originalFilePath;
  final double originalStartTime;
  final double originalDuration;
  final double originalOffset;
  final List<double> originalWaveformPeaks;
  final double
  splitPointSeconds; // Split position in seconds from timeline start

  // The engine assigns the right clip's id when it is created in execute();
  // the UI uses it to add the right clip to its list and to remove it on undo.
  final void Function(int rightEngineClipId)? onSplit;
  final void Function()? onUndo;

  // Generated clip IDs for the split clips (fallbacks when no engine is present,
  // e.g. headless tests / web stub).
  late final int leftClipId;
  late final int rightClipId;

  // Engine id of the right clip, assigned in execute(). Null until split runs.
  int? _rightEngineClipId;

  SplitAudioClipCommand({
    required this.originalClipId,
    required this.originalTrackId,
    required this.originalFilePath,
    required this.originalStartTime,
    required this.originalDuration,
    required this.originalOffset,
    required this.originalWaveformPeaks,
    required this.splitPointSeconds,
    this.onSplit,
    this.onUndo,
  }) {
    leftClipId = _generateUniqueClipId();
    rightClipId = _generateUniqueClipId();
  }

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // C64: trim the original (left) clip in the engine to the split point.
    // Previously only the UI clip was shortened, so the engine kept playing the
    // full pre-split length, overlapping the right region.
    engine.setClipDuration(originalTrackId, originalClipId, leftDuration);

    // Register the right clip in the engine so it plays the post-split region
    // (offset into the source file + remaining duration). The engine assigns a
    // new id which becomes the right clip's id in the UI.
    final rid = engine.loadAudioFileToTrack(
      originalFilePath,
      originalTrackId,
      startTime: rightStartTime,
    );
    if (rid >= 0) {
      engine.setClipOffset(originalTrackId, rid, rightOffset);
      engine.setClipDuration(originalTrackId, rid, rightDuration);
      _rightEngineClipId = rid;
    }
    onSplit?.call(_rightEngineClipId ?? rightClipId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // C63: remove the right clip from the engine so it stops sounding.
    if (_rightEngineClipId != null && _rightEngineClipId! >= 0) {
      engine.removeAudioClip(originalTrackId, _rightEngineClipId!);
    }
    // C64: restore the original (left) clip to its full pre-split duration.
    engine.setClipDuration(originalTrackId, originalClipId, originalDuration);
    onUndo?.call();
  }

  @override
  String get description => 'Split Audio Clip';

  // Helper getters for the callback to use
  double get leftDuration => splitPointSeconds - originalStartTime;
  double get rightStartTime => splitPointSeconds;
  double get rightDuration => originalDuration - leftDuration;
  double get rightOffset => originalOffset + leftDuration;
}

/// Command to add an audio clip to a track
class AddAudioClipCommand extends Command {
  final int trackId;
  final String filePath;
  final double startTime;
  final String clipName;

  int? _createdClipId;

  /// Callback to add clip to UI state (provides clipId, duration, peaks)
  final void Function(int clipId, double duration, List<double> peaks)?
  onClipAdded;

  /// Callback to remove clip from UI state (undo)
  final void Function(int clipId)? onClipRemoved;

  AddAudioClipCommand({
    required this.trackId,
    required this.filePath,
    required this.startTime,
    required this.clipName,
    this.onClipAdded,
    this.onClipRemoved,
  });

  /// Get the created clip ID (available after execute)
  int? get createdClipId => _createdClipId;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    _createdClipId = engine.loadAudioFileToTrack(filePath, trackId);
    if (_createdClipId != null && _createdClipId! >= 0) {
      final duration = engine.getClipDuration(_createdClipId!);
      // Quick low-res waveform for immediate display; the timeline upgrades it
      // to full resolution a frame later (see scheduleWaveformUpgrade).
      final peaks = engine.getWaveformPeaks(_createdClipId!, 1000);
      engine.setClipStartTime(trackId, _createdClipId!, startTime);
      onClipAdded?.call(_createdClipId!, duration, peaks);
    }
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_createdClipId != null && _createdClipId! >= 0) {
      engine.removeAudioClip(trackId, _createdClipId!);
      onClipRemoved?.call(_createdClipId!);
    }
  }

  @override
  String get description => 'Add Clip: $clipName';
}

/// Command to delete an audio clip
class DeleteAudioClipCommand extends Command {
  final ClipData clipData;

  /// Callback to remove clip from UI state
  final void Function(int clipId)? onClipRemoved;

  /// Callback to restore clip to UI state (undo)
  final void Function(ClipData clip)? onClipRestored;

  /// The id currently live in the engine for this clip. Starts as
  /// [ClipData.clipId]; undo reloads the file and the engine assigns a *new*
  /// id, so we track it here and re-execute (redo) against the live id, not the
  /// stale original (which would no-op, leaving the clip audible after redo).
  late int _currentClipId = clipData.clipId;

  DeleteAudioClipCommand({
    required this.clipData,
    this.onClipRemoved,
    this.onClipRestored,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Remove from engine (stops playback)
    Log.d(
      '[DeleteAudioClipCommand] Executing delete for clip $_currentClipId on track ${clipData.trackId}',
    );
    engine.removeAudioClip(clipData.trackId, _currentClipId);
    // Remove from UI
    onClipRemoved?.call(_currentClipId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Reload the audio file from disk at the original position
    final newClipId = engine.loadAudioFileToTrack(
      clipData.filePath,
      clipData.trackId,
      startTime: clipData.startTime,
    );

    if (newClipId >= 0) {
      // `loadAudioFileToTrack` restores the clip at full length / zero offset.
      // Re-apply the saved trim so an already-trimmed clip (e.g. one removed by
      // overlap resolution) comes back exactly as it was, not un-trimmed.
      engine.setClipOffset(clipData.trackId, newClipId, clipData.offset);
      engine.setClipDuration(clipData.trackId, newClipId, clipData.duration);
      // Restore with new clip ID from engine, and track it so a subsequent
      // redo removes the right clip.
      _currentClipId = newClipId;
      final restoredClip = clipData.copyWith(clipId: newClipId);
      onClipRestored?.call(restoredClip);
    } else {
      // Fallback: restore to UI with original ID (won't play but visible)
      onClipRestored?.call(clipData);
    }
  }

  @override
  String get description => 'Delete Clip: ${clipData.fileName}';
}

/// Command to duplicate an audio clip
class DuplicateAudioClipCommand extends Command {
  final ClipData originalClip;
  final double newStartTime;

  int? _duplicatedClipId;

  /// Callback to add duplicated clip to UI state
  final void Function(ClipData newClip)? onClipDuplicated;

  /// Callback to remove duplicated clip (undo)
  final void Function(int clipId)? onClipRemoved;

  DuplicateAudioClipCommand({
    required this.originalClip,
    required this.newStartTime,
    this.onClipDuplicated,
    this.onClipRemoved,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Call engine API to duplicate the clip - this registers it for playback
    final newClipId = engine.duplicateAudioClip(
      originalClip.trackId,
      originalClip.clipId,
      newStartTime,
    );

    if (newClipId < 0) {
      // Fallback to local-only ID if engine call fails
      _duplicatedClipId = _generateUniqueClipId();
    } else {
      _duplicatedClipId = newClipId;
    }

    // Deep copy automation so duplicated clip has independent automation
    // Preserve editData (warp, gain, transpose settings)
    final newClip = originalClip.copyWith(
      clipId: _duplicatedClipId,
      startTime: newStartTime,
      editData: originalClip.editData,
      automation: originalClip.automation.deepCopy(),
    );
    onClipDuplicated?.call(newClip);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_duplicatedClipId != null) {
      // Remove from engine
      engine.removeAudioClip(originalClip.trackId, _duplicatedClipId!);
      // Remove from UI
      onClipRemoved?.call(_duplicatedClipId!);
    }
  }

  @override
  String get description => 'Duplicate Clip: ${originalClip.fileName}';
}

/// Command to resize/trim an audio clip (change duration, offset, and optionally startTime for left edge trim)
class ResizeAudioClipCommand extends Command {
  final int trackId;
  final int clipId;
  final String clipName;
  final double oldDuration;
  final double newDuration;
  final double? oldOffset;
  final double? newOffset;
  final double? oldStartTime;
  final double? newStartTime;

  /// Callback to update clip in UI state
  final void Function(
    int clipId,
    double duration,
    double? offset,
    double? startTime,
  )?
  onClipResized;

  ResizeAudioClipCommand({
    required this.trackId,
    required this.clipId,
    required this.clipName,
    required this.oldDuration,
    required this.newDuration,
    this.oldOffset,
    this.newOffset,
    this.oldStartTime,
    this.newStartTime,
    this.onClipResized,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Sync all changed properties to the engine
    if (newStartTime != null) {
      engine.setClipStartTime(trackId, clipId, newStartTime!);
    }
    if (newOffset != null) {
      engine.setClipOffset(trackId, clipId, newOffset!);
    }
    engine.setClipDuration(trackId, clipId, newDuration);
    onClipResized?.call(clipId, newDuration, newOffset, newStartTime);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Restore all properties to the engine
    if (oldStartTime != null) {
      engine.setClipStartTime(trackId, clipId, oldStartTime!);
    }
    if (oldOffset != null) {
      engine.setClipOffset(trackId, clipId, oldOffset!);
    }
    engine.setClipDuration(trackId, clipId, oldDuration);
    onClipResized?.call(clipId, oldDuration, oldOffset, oldStartTime);
  }

  @override
  String get description => 'Resize Clip: $clipName';
}

/// Command to rename a clip
class RenameClipCommand extends Command {
  final int clipId;
  final String oldName;
  final String newName;

  /// Callback to update clip name in UI state
  final void Function(int clipId, String name)? onClipRenamed;

  RenameClipCommand({
    required this.clipId,
    required this.oldName,
    required this.newName,
    this.onClipRenamed,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onClipRenamed?.call(clipId, newName);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onClipRenamed?.call(clipId, oldName);
  }

  @override
  String get description => 'Rename Clip: $oldName → $newName';
}

/// Command to duplicate a MIDI clip in the arrangement view
/// Creates a linked instance that shares the same patternId
class DuplicateMidiClipCommand extends Command {
  final MidiClipData originalClip;
  final double newStartTime;

  int? _duplicatedClipId;
  String? _sharedPatternId;

  /// Callback to add duplicated clip AND update original's patternId if needed
  /// Parameters: (newClip, sharedPatternId)
  final void Function(MidiClipData newClip, String sharedPatternId)?
  onClipDuplicated;

  /// Callback to remove duplicated clip (undo)
  final void Function(int clipId)? onClipRemoved;

  DuplicateMidiClipCommand({
    required this.originalClip,
    required this.newStartTime,
    this.onClipDuplicated,
    this.onClipRemoved,
  });

  /// Get the duplicated clip ID (available after execute)
  int? get duplicatedClipId => _duplicatedClipId;

  /// Get the shared pattern ID (available after execute)
  String? get sharedPatternId => _sharedPatternId;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    _duplicatedClipId = _generateUniqueClipId();

    // Generate patternId if original doesn't have one
    // This creates a shared pattern ID for linking clips together
    _sharedPatternId =
        originalClip.patternId ?? 'pattern_${originalClip.clipId}';

    // Deep copy automation so duplicated clip has independent automation
    final newClip = originalClip.copyWith(
      clipId: _duplicatedClipId,
      startTime: newStartTime,
      patternId: _sharedPatternId,
      automation: originalClip.automation.deepCopy(),
    );
    onClipDuplicated?.call(newClip, _sharedPatternId!);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_duplicatedClipId != null) {
      onClipRemoved?.call(_duplicatedClipId!);
    }
  }

  @override
  String get description => 'Duplicate MIDI Clip: ${originalClip.name}';
}

/// Command to delete a MIDI clip from the arrangement view
class DeleteMidiClipFromArrangementCommand extends Command {
  final MidiClipData clipData;

  /// Callback to remove clip from UI state
  final void Function(int clipId, int trackId)? onClipRemoved;

  /// Callback to restore clip to UI state (undo)
  final void Function(MidiClipData clip)? onClipRestored;

  DeleteMidiClipFromArrangementCommand({
    required this.clipData,
    this.onClipRemoved,
    this.onClipRestored,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Remove from engine (stops playback)
    Log.d(
      '[DeleteMidiClipCommand] Executing delete for clip ${clipData.clipId} on track ${clipData.trackId}',
    );
    engine.removeMidiClip(clipData.trackId, clipData.clipId);
    // Remove from UI
    onClipRemoved?.call(clipData.clipId, clipData.trackId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onClipRestored?.call(clipData);
  }

  @override
  String get description => 'Delete MIDI Clip: ${clipData.name}';
}

/// Command to move a MIDI clip position in the arrangement
class MoveMidiClipPositionCommand extends Command {
  final MidiClipData originalClip;
  final double newStartTime;
  final double oldStartTime;

  /// Callback to update clip position in UI state
  final void Function(int clipId, double startTime)? onClipMoved;

  MoveMidiClipPositionCommand({
    required this.originalClip,
    required this.newStartTime,
    required this.oldStartTime,
    this.onClipMoved,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onClipMoved?.call(originalClip.clipId, newStartTime);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onClipMoved?.call(originalClip.clipId, oldStartTime);
  }

  @override
  String get description => 'Move MIDI Clip: ${originalClip.name}';
}

/// Command to create a new MIDI clip in the arrangement
class CreateMidiClipCommand extends Command {
  final MidiClipData clipData;

  /// Callback to add clip to UI state
  final void Function(MidiClipData clip)? onClipCreated;

  /// Callback to remove clip from UI state (undo)
  final void Function(int clipId, int trackId)? onClipRemoved;

  CreateMidiClipCommand({
    required this.clipData,
    this.onClipCreated,
    this.onClipRemoved,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onClipCreated?.call(clipData);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onClipRemoved?.call(clipData.clipId, clipData.trackId);
  }

  @override
  String get description => 'Create MIDI Clip: ${clipData.name}';
}

/// Command for recording completion with overlap trimming.
/// Stores before/after snapshots of all clips on the affected track(s).
/// Handles both MIDI and audio clips, syncing UI and engine state.
class RecordingCompleteCommand extends Command {
  /// Track IDs affected by this recording
  final int? midiTrackId;
  final int? audioTrackId;

  /// MIDI clip snapshots (all clips on the track before/after recording)
  final List<MidiClipData> midiClipsBefore;
  final List<MidiClipData> midiClipsAfter;

  /// Audio clip snapshots (all clips on the track before/after recording)
  final List<ClipData> audioClipsBefore;
  final List<ClipData> audioClipsAfter;

  /// Callbacks to apply MIDI clip state to UI (midiPlaybackManager)
  final void Function(int trackId, List<MidiClipData> clips)? onApplyMidiState;

  /// Callbacks to apply audio clip state to UI (timelineState)
  final void Function(int trackId, List<ClipData> clips)? onApplyAudioState;

  /// Skip the first execute() since work was already done by handleRecordingComplete
  bool _isFirstExecute = true;

  RecordingCompleteCommand({
    this.midiTrackId,
    this.audioTrackId,
    this.midiClipsBefore = const [],
    this.midiClipsAfter = const [],
    this.audioClipsBefore = const [],
    this.audioClipsAfter = const [],
    this.onApplyMidiState,
    this.onApplyAudioState,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    if (_isFirstExecute) {
      _isFirstExecute = false;
      return; // Work already done by handleRecordingComplete
    }
    _applyState(
      engine,
      audioClipsBefore,
      audioClipsAfter,
      midiClipsBefore,
      midiClipsAfter,
    );
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    _applyState(
      engine,
      audioClipsAfter,
      audioClipsBefore,
      midiClipsAfter,
      midiClipsBefore,
    );
  }

  void _applyState(
    AudioEngineInterface engine,
    List<ClipData> fromAudioClips,
    List<ClipData> toAudioClips,
    List<MidiClipData> fromMidiClips,
    List<MidiClipData> toMidiClips,
  ) {
    // Sync audio clips with engine
    if (audioTrackId != null) {
      final fromIds = fromAudioClips.map((c) => c.clipId).toSet();
      final toIds = toAudioClips.map((c) => c.clipId).toSet();

      // Remove clips that are in "from" but not in "to"
      for (final id in fromIds.difference(toIds)) {
        engine.removeAudioClip(audioTrackId!, id);
      }

      // Add clips that are in "to" but not in "from"
      for (final clip in toAudioClips) {
        if (!fromIds.contains(clip.clipId)) {
          engine.addExistingClipToTrack(
            clip.clipId,
            audioTrackId!,
            clip.startTime,
            offset: clip.offset,
            duration: clip.duration,
          );
        }
      }

      // Update positions/durations for clips that exist in both
      for (final clip in toAudioClips) {
        if (fromIds.contains(clip.clipId)) {
          engine.setClipStartTime(audioTrackId!, clip.clipId, clip.startTime);
        }
      }

      // Apply to UI
      onApplyAudioState?.call(audioTrackId!, toAudioClips);
    }

    // Apply MIDI state to UI (engine sync handled by midiPlaybackManager)
    if (midiTrackId != null) {
      onApplyMidiState?.call(midiTrackId!, toMidiClips);
    }
  }

  @override
  String get description => 'Record';
}
