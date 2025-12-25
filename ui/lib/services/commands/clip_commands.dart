import '../../audio_engine.dart';
import '../../models/midi_note_data.dart';
import 'command.dart';

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
  Future<void> execute(AudioEngine engine) async {
    // Note: This updates the clip position in the engine
    // The actual implementation depends on your engine API
    // For now, this is handled in Flutter state
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    // Restore previous position
  }

  @override
  String get description =>
      'Move clip: $clipName (${oldStartTime.toStringAsFixed(2)}s → ${newStartTime.toStringAsFixed(2)}s)';
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
  Future<void> execute(AudioEngine engine) async {
    engine.setClipStartTime(trackId, clipId, newStartTime);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    engine.setClipStartTime(trackId, clipId, oldStartTime);
  }

  @override
  String get description =>
      'Move audio clip: $clipName (${oldStartTime.toStringAsFixed(2)}s → ${newStartTime.toStringAsFixed(2)}s)';
}

/// Command to delete a MIDI clip
class DeleteMidiClipCommand extends Command {
  final MidiClipData clipData;

  DeleteMidiClipCommand({required this.clipData});

  @override
  Future<void> execute(AudioEngine engine) async {
    // Delete clip from engine
    // Note: Implement engine.deleteMidiClip() if not exists
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    // Recreate the clip with stored data
    // This requires storing all clip state
  }

  @override
  String get description => 'Delete MIDI clip: ${clipData.name}';
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
  Future<void> execute(AudioEngine engine) async {
    // Apply the "after" state
    onApplyState?.call(afterState);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
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
  Future<void> execute(AudioEngine engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description => 'Add note: ${addedNote.noteName}';
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
  Future<void> execute(AudioEngine engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description => noteCount == 1 ? 'Delete note' : 'Delete $noteCount notes';
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
  Future<void> execute(AudioEngine engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description => noteCount == 1 ? 'Move note' : 'Move $noteCount notes';
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
  Future<void> execute(AudioEngine engine) async {
    onApplyState?.call(clipAfter);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    onApplyState?.call(clipBefore);
  }

  @override
  String get description => noteCount == 1 ? 'Resize note' : 'Resize $noteCount notes';
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
    leftClipId = DateTime.now().millisecondsSinceEpoch;
    rightClipId = leftClipId + 1;
  }

  @override
  Future<void> execute(AudioEngine engine) async {
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

    // Create left clip (same start, shortened duration)
    final leftClip = originalClip.copyWith(
      clipId: leftClipId,
      duration: splitPointBeats,
      loopLength: splitPointBeats.clamp(0.25, originalClip.loopLength),
      notes: leftNotes,
      name: '${originalClip.name} (L)',
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
    );

    onSplit?.call(leftClip, rightClip);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    onUndo?.call(originalClip);
  }

  @override
  String get description => 'Split MIDI clip: ${originalClip.name}';
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
    leftClipId = DateTime.now().millisecondsSinceEpoch;
    rightClipId = leftClipId + 1;
  }

  @override
  Future<void> execute(AudioEngine engine) async {
    // The actual clip creation happens in the callback
    // because we need to interact with both the engine and the UI state.
    // Use the helper getters (leftDuration, rightStartTime, etc.) in the callback.
    onSplit?.call(leftClipId, rightClipId);
  }

  @override
  Future<void> undo(AudioEngine engine) async {
    onUndo?.call();
  }

  @override
  String get description => 'Split audio clip';

  // Helper getters for the callback to use
  double get leftDuration => splitPointSeconds - originalStartTime;
  double get rightStartTime => splitPointSeconds;
  double get rightDuration => originalDuration - leftDuration;
  double get rightOffset => originalOffset + leftDuration;
}
