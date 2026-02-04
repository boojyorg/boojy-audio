import 'package:flutter/foundation.dart';

import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
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

/// Command to move an audio clip on the timeline
class MoveAudioClipCommand extends Command {
  final int trackId;
  final int clipId;
  final String clipName;
  final double newStartTime;
  final double oldStartTime;

  MoveAudioClipCommand({
    required this.trackId,
    required this.clipId,
    required this.clipName,
    required this.newStartTime,
    required this.oldStartTime,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setClipStartTime(trackId, clipId, newStartTime);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setClipStartTime(trackId, clipId, oldStartTime);
  }

  @override
  String get description =>
      'Move Audio Clip: $clipName (${oldStartTime.toStringAsFixed(2)}s → ${newStartTime.toStringAsFixed(2)}s)';
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
  String get description => noteCount == 1 ? 'Delete Note' : 'Delete $noteCount Notes';
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
  String get description => noteCount == 1 ? 'Move Note' : 'Move $noteCount Notes';
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
  String get description => noteCount == 1 ? 'Resize Note' : 'Resize $noteCount Notes';
}

/// Command to split a MIDI clip at the playhead position
/// Creates two clips: one before the split point, one after
class SplitMidiClipCommand extends Command {
  final MidiClipData originalClip;
  final double splitPointBeats; // Split position relative to clip start (in beats)
  final void Function(MidiClipData leftClip, MidiClipData rightClip)? onSplit;
  final void Function(MidiClipData originalClip)? onUndo;

  // Generated clip IDs for the split clips
  late final int leftClipId;
  late final int rightClipId;

  SplitMidiClipCommand({
    required this.originalClip,
    required this.splitPointBeats,
    this.onSplit,
    this.onUndo,
  }) {
    leftClipId = _generateUniqueClipId();
    rightClipId = _generateUniqueClipId();
  }

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Split notes into two groups based on the split point
    final leftNotes = <MidiNoteData>[];
    final rightNotes = <MidiNoteData>[];

    for (final note in originalClip.notes) {
      if (note.endTime <= splitPointBeats) {
        // Note is entirely in the left clip
        leftNotes.add(note);
      } else if (note.startTime >= splitPointBeats) {
        // Note is entirely in the right clip - adjust its start time
        rightNotes.add(note.copyWith(
          startTime: note.startTime - splitPointBeats,
          id: '${note.note}_${note.startTime - splitPointBeats}_${DateTime.now().microsecondsSinceEpoch}',
        ));
      } else {
        // Note straddles the split point - truncate it to the left clip
        leftNotes.add(note.copyWith(
          duration: splitPointBeats - note.startTime,
        ));
      }
    }

    // Slice automation at the split point
    final leftAutomation = originalClip.automation.sliceLeft(splitPointBeats);
    final rightAutomation = originalClip.automation.sliceRight(splitPointBeats);

    // Create left clip (same start, shortened duration)
    final leftClip = originalClip.copyWith(
      clipId: leftClipId,
      duration: splitPointBeats,
      loopLength: splitPointBeats.clamp(0.25, originalClip.loopLength),
      notes: leftNotes,
      name: '${originalClip.name} (L)',
      automation: leftAutomation,
    );

    // Create right clip (starts at split point, remaining duration)
    final rightDuration = originalClip.duration - splitPointBeats;
    final rightClip = originalClip.copyWith(
      clipId: rightClipId,
      startTime: originalClip.startTime + splitPointBeats,
      duration: rightDuration,
      loopLength: rightDuration.clamp(0.25, originalClip.loopLength),
      notes: rightNotes,
      name: '${originalClip.name} (R)',
      automation: rightAutomation,
    );

    onSplit?.call(leftClip, rightClip);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onUndo?.call(originalClip);
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
  final double splitPointSeconds; // Split position in seconds from timeline start

  final void Function(int leftClipId, int rightClipId)? onSplit;
  final void Function()? onUndo;

  // Generated clip IDs for the split clips
  late final int leftClipId;
  late final int rightClipId;

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
    // The actual clip creation happens in the callback
    // because we need to interact with both the engine and the UI state.
    // Use the helper getters (leftDuration, rightStartTime, etc.) in the callback.
    onSplit?.call(leftClipId, rightClipId);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
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
  final void Function(int clipId, double duration, List<double> peaks)? onClipAdded;

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
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = engine.getWaveformPeaks(_createdClipId!, peakResolution);
      engine.setClipStartTime(trackId, _createdClipId!, startTime);
      onClipAdded?.call(_createdClipId!, duration, peaks);
    }
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_createdClipId != null && _createdClipId! >= 0) {
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

  DeleteAudioClipCommand({
    required this.clipData,
    this.onClipRemoved,
    this.onClipRestored,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    // Remove from engine (stops playback)
    debugPrint('🗑️ [DeleteAudioClipCommand] Executing delete for clip ${clipData.clipId} on track ${clipData.trackId}');
    engine.removeAudioClip(clipData.trackId, clipData.clipId);
    // Remove from UI
    onClipRemoved?.call(clipData.clipId);
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
      // Restore with new clip ID from engine
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
    final newClip = originalClip.copyWith(
      clipId: _duplicatedClipId,
      startTime: newStartTime,
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
  final void Function(int clipId, double duration, double? offset, double? startTime)? onClipResized;

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
    // Update engine position if startTime changed (left edge trim)
    if (newStartTime != null) {
      engine.setClipStartTime(trackId, clipId, newStartTime!);
    }
    onClipResized?.call(clipId, newDuration, newOffset, newStartTime);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    // Restore engine position if startTime changed
    if (oldStartTime != null) {
      engine.setClipStartTime(trackId, clipId, oldStartTime!);
    }
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
  final void Function(MidiClipData newClip, String sharedPatternId)? onClipDuplicated;

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
    _sharedPatternId = originalClip.patternId ?? 'pattern_${originalClip.clipId}';

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
    debugPrint('🗑️ [DeleteMidiClipCommand] Executing delete for clip ${clipData.clipId} on track ${clipData.trackId}');
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
    _applyState(engine, audioClipsBefore, audioClipsAfter,
        midiClipsBefore, midiClipsAfter);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    _applyState(engine, audioClipsAfter, audioClipsBefore,
        midiClipsAfter, midiClipsBefore);
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
