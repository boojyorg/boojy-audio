import 'package:flutter/material.dart';
import '../../../utils/logger.dart';
import '../../../models/clip_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/midi_event.dart';
import '../../../services/commands/command.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../utils/clip_overlap_handler.dart';
import '../../../widgets/capture_midi_dialog.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import '../../../widgets/shared/boojy_notice.dart';

/// Mixin containing clip-related methods for DAWScreen.
/// Handles MIDI and audio clip selection, creation, duplication, split, quantize, delete.
mixin DAWClipMixin
    on
        State<DAWScreen>,
        DAWScreenStateMixin,
        DAWRecordingMixin,
        DAWUIMixin,
        DAWTrackMixin {
  // ============================================
  // CLIP COPY/DUPLICATE
  // ============================================

  /// Handle MIDI clip copy (Alt+drag)
  void onMidiClipCopied(MidiClipData sourceClip, double newStartTime) {
    Log.d(
      '[OVERLAP] onMidiClipCopied: clip ${sourceClip.clipId} "${sourceClip.name}" → newStart=${newStartTime.toStringAsFixed(3)} beats, track ${sourceClip.trackId}',
    );
    // Use undo/redo manager for arrangement operations
    final command = DuplicateMidiClipCommand(
      originalClip: sourceClip,
      newStartTime: newStartTime,
      onClipDuplicated: (newClip) {
        // Resolve overlaps at the copy's position
        // Note: source clip is NOT excluded — if the copy overlaps the source,
        // the source should be trimmed (standard DAW behavior).
        final overlapResult = ClipOverlapHandler.resolveMidiOverlaps(
          newStart: newStartTime,
          newEnd: newStartTime + sourceClip.duration,
          existingClips: List<MidiClipData>.from(
            midiPlaybackManager?.midiClips ?? [],
          ),
          trackId: sourceClip.trackId,
        );
        ClipOverlapHandler.applyMidiResult(
          result: overlapResult,
          deleteClip: (cId, tId) => midiClipController.deleteClip(cId, tId),
          updateClipInPlace: (clip) =>
              midiPlaybackManager?.updateClipInPlace(clip),
          rescheduleClip: (clip, t) =>
              midiPlaybackManager?.rescheduleClip(clip, t),
          addClip: (clip) => midiPlaybackManager?.addRecordedClip(clip),
          tempo: tempo,
        );

        // Add new clip to manager and schedule for playback
        midiPlaybackManager?.addRecordedClip(newClip);
        midiClipController.updateClip(newClip, playheadPosition);
        // Select the new clip
        midiPlaybackManager?.selectClip(newClip.clipId, newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId) {
        // Find the clip to get track ID
        final clip = midiPlaybackManager?.midiClips.firstWhere(
          (c) => c.clipId == clipId,
          orElse: () => sourceClip,
        );
        midiClipController.deleteClip(
          clipId,
          clip?.trackId ?? sourceClip.trackId,
        );
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  /// Handle audio clip copy (Alt+drag)
  void onAudioClipCopied(ClipData sourceClip, double newStartTime) {
    Log.d(
      '[OVERLAP] onAudioClipCopied: clip ${sourceClip.clipId} → newStart=${newStartTime.toStringAsFixed(3)}s, track ${sourceClip.trackId}',
    );
    final command = DuplicateAudioClipCommand(
      originalClip: sourceClip,
      newStartTime: newStartTime,
      onClipDuplicated: (newClip) {
        // Resolve overlaps at the copy's position
        // Note: source clip is NOT excluded — if the copy overlaps the source,
        // the source should be trimmed (standard DAW behavior).
        final overlapResult = ClipOverlapHandler.resolveAudioOverlaps(
          newStart: newStartTime,
          newEnd: newStartTime + sourceClip.duration,
          existingClips: List<ClipData>.from(
            timelineKey.currentState?.clips ?? [],
          ),
          trackId: sourceClip.trackId,
        );
        ClipOverlapHandler.applyAudioResult(
          result: overlapResult,
          engineRemoveClip: (tId, cId) =>
              audioEngine?.removeAudioClip(tId, cId),
          engineSetStartTime: (tId, cId, s) =>
              audioEngine?.setClipStartTime(tId, cId, s),
          engineSetOffset: (tId, cId, o) =>
              audioEngine?.setClipOffset(tId, cId, o),
          engineSetDuration: (tId, cId, d) =>
              audioEngine?.setClipDuration(tId, cId, d),
          engineDuplicateClip: (tId, cId, s) =>
              audioEngine?.duplicateAudioClip(tId, cId, s) ?? -1,
          uiRemoveClip: (cId) => timelineKey.currentState?.removeClip(cId),
          uiUpdateClip: (clip) => timelineKey.currentState?.updateClip(clip),
          uiAddClip: (clip) => timelineKey.currentState?.addClip(clip),
        );
        // Add the copy to timeline
        timelineKey.currentState?.addClip(newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId) {
        // Remove from timeline view's clip list
        timelineKey.currentState?.removeClip(clipId);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  /// Duplicate currently selected clip
  void duplicateSelectedClip() {
    // Try the currently-editing MIDI clip first.
    final midiClip = midiPlaybackManager?.currentEditingClip;
    if (midiClip != null) {
      final newStartTime = midiClip.startTime + midiClip.duration;
      onMidiClipCopied(midiClip, newStartTime);
      return;
    }

    // Fall back to the selected audio clip in the arrangement (mirrors
    // quantizeSelectedClip's fallback pattern).
    final audioClip = timelineKey.currentState?.selectedAudioClip;
    if (audioClip != null) {
      timelineKey.currentState?.duplicateAudioClip(audioClip);
      return;
    }

    Notices.info('Select a clip to duplicate');
  }

  // ============================================
  // CLIP SPLIT
  // ============================================

  /// The one true MIDI split: an undoable [SplitMidiClipCommand] driven by
  /// engine+manager primitives. Wired to `MidiClipCallbacks.onSplit` (so the
  /// slice tool and right-click menu use it) and called directly by the Cmd+E
  /// path below. It must never route through `onMidiClipCopied`/`_deleteMidiClip`
  /// — those push their own nested commands, reassign clip ids, and run overlap
  /// trimming, which silently destroyed the right region on undo.
  void onMidiClipSplit(MidiClipData clip, double splitPointBeats) {
    // Split point must fall strictly inside the clip.
    if (splitPointBeats <= 0 || splitPointBeats >= clip.duration) return;

    final command = SplitMidiClipCommand(
      originalClip: clip,
      splitPointBeats: splitPointBeats,
      // Remove from the Dart store AND the engine.
      deleteClip: (cId, tId) => midiClipController.deleteClip(cId, tId),
      // Add to the store AND schedule in the engine (id preserved).
      addClip: (c) {
        midiPlaybackManager?.addRecordedClip(c);
        midiPlaybackManager?.updateClip(c, tempo, 0);
      },
      selectClip: (c) => midiPlaybackManager?.selectClip(c.clipId, c),
    );

    undoRedoManager.execute(command);
    if (mounted) setState(() {});
  }

  /// Split selected clip at playhead position
  void splitSelectedClipAtPlayhead() {
    // Split at playhead position
    final splitPosition = playheadPosition;

    // Try MIDI clip first — route through the unified undoable split.
    final selectedMidi = midiPlaybackManager?.currentEditingClip;
    if (midiPlaybackManager?.selectedClipId != null && selectedMidi != null) {
      final playheadBeats = midiClipController.secondsToBeats(splitPosition);
      if (playheadBeats > selectedMidi.startTime &&
          playheadBeats < selectedMidi.endTime) {
        onMidiClipSplit(selectedMidi, playheadBeats - selectedMidi.startTime);
        return;
      }
    }

    // Try audio clip if no MIDI clip or MIDI split failed
    final audioSplit =
        timelineKey.currentState?.splitSelectedAudioClipAtPlayhead(
          splitPosition,
        ) ??
        false;
    if (audioSplit) return;

    // Neither worked
    Notices.info('Select a clip and put the playhead inside it to split');
  }

  // ============================================
  // CLIP QUANTIZE
  // ============================================

  /// Quantize selected clip to grid
  void quantizeSelectedClip() {
    // Default grid size: 1 beat (quarter note)
    const gridSizeBeats = 1.0;
    final beatsPerSecond = tempo / 60.0;
    final gridSizeSeconds = gridSizeBeats / beatsPerSecond;

    // Try MIDI clip first
    if (midiPlaybackManager?.selectedClipId != null) {
      final success = midiClipController.quantizeSelectedClip(gridSizeBeats);
      if (success) return;
    }

    // Try audio clip
    final audioQuantized =
        timelineKey.currentState?.quantizeSelectedAudioClip(gridSizeSeconds) ??
        false;
    if (audioQuantized) return;

    // Neither worked
    Notices.info('Select a clip to quantize');
  }

  // ============================================
  // CLIP SELECTION
  // ============================================

  /// Select all clips in the timeline view
  void selectAllClips() {
    timelineKey.currentState?.selectAllClips();
  }

  // ============================================
  // BOUNCE MIDI TO AUDIO
  // ============================================

  // ============================================
  // JOIN CLIPS
  // ============================================

  /// Join multiple selected MIDI clips on one track into a single clip.
  ///
  /// Loops are unrolled into literal notes first (via
  /// [MidiClipData.unrolledNotes]) so the joined clip sounds identical to the
  /// clips it replaces; gaps between clips stay as empty space. The whole
  /// operation is one undo step.
  void joinSelectedClips() {
    final timelineState = timelineKey.currentState;
    if (timelineState == null) return;

    final selectedMidiClips = timelineState.selectedMidiClips;
    final selectedAudioCount = timelineState.selectedAudioClipIds.length;

    // Join works on one clip type at a time; refuse a mixed selection honestly
    // rather than silently ignoring part of it.
    if (selectedMidiClips.isNotEmpty && selectedAudioCount > 0) {
      Notices.info('Select only MIDI clips or only audio clips to join');
      return;
    }
    // Audio-only selection → render-and-bounce path.
    if (selectedMidiClips.isEmpty && selectedAudioCount >= 1) {
      joinSelectedAudioClips();
      return;
    }

    if (selectedMidiClips.length < 2) {
      Notices.info('Select 2 or more MIDI clips to join');
      return;
    }

    // Ensure all clips are on the same track
    final trackIds = selectedMidiClips.map((c) => c.trackId).toSet();
    if (trackIds.length > 1) {
      Notices.info('Clips must be on the same track to join');
      return;
    }

    final trackId = trackIds.first;

    // Sort clips by start time
    final sortedClips = List<MidiClipData>.from(selectedMidiClips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Calculate joined clip bounds
    final firstClipStart = sortedClips.first.startTime;
    final lastClipEnd = sortedClips
        .map((c) => c.endTime)
        .reduce((a, b) => a > b ? a : b);
    final totalDuration = lastClipEnd - firstClipStart;

    // Merge all notes, unrolling each clip's loops/offset into literal notes
    // positioned relative to the joined clip's start
    final mergedNotes = <MidiNoteData>[];
    for (final clip in sortedClips) {
      final clipOffset = clip.startTime - firstClipStart;
      for (final note in clip.unrolledNotes()) {
        mergedNotes.add(note.copyWith(startTime: note.startTime + clipOffset));
      }
    }
    mergedNotes.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Create the joined clip — named after the first clip, standalone
    // (joining breaks any pattern link, the merged content is new material)
    final joinedClip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: firstClipStart,
      duration: totalDuration,
      loopLength: totalDuration,
      notes: mergedNotes,
      name: sortedClips.first.name,
      color: sortedClips.first.color,
    );

    // Route the whole operation through one undo step: delete each original
    // clip, then create the joined one. Undo reverses both (restoring the
    // originals), so Cmd+Z no longer undoes some unrelated earlier action.
    final commands = <Command>[
      for (final clip in sortedClips)
        DeleteMidiClipFromArrangementCommand(
          clipData: clip,
          onClipRemoved: (cId, tId) {
            midiClipController.deleteClip(cId, tId);
            if (mounted) setState(() {});
          },
          onClipRestored: (restoredClip) {
            midiPlaybackManager?.addRecordedClip(restoredClip);
            midiClipController.updateClip(restoredClip, playheadPosition);
            midiPlaybackManager?.selectClip(restoredClip.clipId, restoredClip);
            if (mounted) setState(() {});
          },
        ),
      CreateMidiClipCommand(
        clipData: joinedClip,
        onClipCreated: (clip) {
          midiClipController.addClip(clip);
          midiClipController.updateClip(clip, playheadPosition);
          midiPlaybackManager?.selectClip(clip.clipId, clip);
          if (mounted) setState(() {});
        },
        onClipRemoved: (cId, tId) {
          midiClipController.deleteClip(cId, tId);
          if (mounted) setState(() {});
        },
      ),
    ];

    undoRedoManager.execute(
      CompositeCommand(commands, 'Join ${sortedClips.length} clips'),
    );

    timelineState.clearClipSelection();
  }

  /// Join multiple selected audio clips on one track into a single clip.
  ///
  /// The engine renders the selection into one WAV (baking each clip's
  /// gain/pitch/warp/reverse; gaps become silence; no track FX printed) and the
  /// originals are replaced by it as one undo step. Undo restores the originals
  /// with their edits intact. Refuses cross-track selections.
  void joinSelectedAudioClips() {
    final timelineState = timelineKey.currentState;
    if (timelineState == null) return;

    final ids = timelineState.selectedAudioClipIds;
    final selected = timelineState.clips
        .where((c) => ids.contains(c.clipId))
        .toList();

    if (selected.length < 2) {
      Notices.info('Select 2 or more audio clips to join');
      return;
    }

    final trackIds = selected.map((c) => c.trackId).toSet();
    if (trackIds.length > 1) {
      Notices.info('Clips must be on the same track to join');
      return;
    }
    final trackId = trackIds.first;

    final command = JoinAudioClipsCommand(
      clips: selected,
      trackId: trackId,
      onOriginalsRemoved: (clipIds) {
        for (final id in clipIds) {
          timelineState.removeClip(id);
        }
        if (mounted) setState(() {});
      },
      onJoinedClipCreated: (joined) {
        timelineState.addClip(joined);
        if (mounted) setState(() {});
      },
      onJoinedClipRemoved: (id) {
        timelineState.removeClip(id);
        if (mounted) setState(() {});
      },
      onOriginalsRestored: (restored) {
        for (final clip in restored) {
          timelineState.addClip(clip);
        }
        if (mounted) setState(() {});
      },
    );

    undoRedoManager.execute(command);
    timelineState.clearClipSelection();
  }

  // ============================================
  // CLIP DELETION
  // ============================================

  /// Delete a single MIDI clip
  void deleteMidiClip(int clipId, int trackId) {
    // Find the clip data for undo
    final clip = midiPlaybackManager?.midiClips.firstWhere(
      (c) => c.clipId == clipId,
      orElse: () => MidiClipData(
        clipId: clipId,
        trackId: trackId,
        startTime: 0,
        duration: 4,
        name: 'Deleted Clip',
      ),
    );

    final command = DeleteMidiClipFromArrangementCommand(
      clipData: clip!,
      onClipRemoved: (cId, tId) {
        midiClipController.deleteClip(cId, tId);
        if (mounted) setState(() {});
      },
      onClipRestored: (restoredClip) {
        midiPlaybackManager?.addRecordedClip(restoredClip);
        midiClipController.updateClip(restoredClip, playheadPosition);
        midiPlaybackManager?.selectClip(restoredClip.clipId, restoredClip);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  /// Batch delete multiple MIDI clips (eraser tool - single undo action)
  void deleteMidiClipsBatch(List<(int clipId, int trackId)> clipsToDelete) {
    if (clipsToDelete.isEmpty) return;

    // Build individual delete commands for each clip
    final commands = <Command>[];
    for (final (clipId, trackId) in clipsToDelete) {
      final clip = midiPlaybackManager?.midiClips.firstWhere(
        (c) => c.clipId == clipId,
        orElse: () => MidiClipData(
          clipId: clipId,
          trackId: trackId,
          startTime: 0,
          duration: 4,
          name: 'Deleted Clip',
        ),
      );

      if (clip != null) {
        commands.add(
          DeleteMidiClipFromArrangementCommand(
            clipData: clip,
            onClipRemoved: (cId, tId) {
              midiClipController.deleteClip(cId, tId);
            },
            onClipRestored: (restoredClip) {
              midiPlaybackManager?.addRecordedClip(restoredClip);
              midiClipController.updateClip(restoredClip, playheadPosition);
            },
          ),
        );
      }
    }

    if (commands.isEmpty) return;

    // Wrap in CompositeCommand for single undo action
    final compositeCommand = CompositeCommand(
      commands,
      'Delete ${clipsToDelete.length} MIDI clip${clipsToDelete.length > 1 ? 's' : ''}',
    );
    undoRedoManager.execute(compositeCommand);
    if (mounted) setState(() {});
  }

  /// Batch delete multiple audio clips (eraser tool - single undo action)
  void deleteAudioClipsBatch(List<ClipData> clipsToDelete) {
    if (clipsToDelete.isEmpty) return;

    // Build individual delete commands for each clip
    final commands = <Command>[];
    for (final clip in clipsToDelete) {
      commands.add(
        DeleteAudioClipCommand(
          clipData: clip,
          onClipRemoved: (clipId) {
            timelineKey.currentState?.removeClip(clipId);
          },
          onClipRestored: (restoredClip) {
            timelineKey.currentState?.addClip(restoredClip);
          },
        ),
      );
    }

    if (commands.isEmpty) return;

    // Wrap in CompositeCommand for single undo action
    final compositeCommand = CompositeCommand(
      commands,
      'Delete ${clipsToDelete.length} audio clip${clipsToDelete.length > 1 ? 's' : ''}',
    );
    undoRedoManager.execute(compositeCommand);
    if (mounted) setState(() {});
  }

  // ============================================
  // CLIP CREATION
  // ============================================

  /// Create a MIDI clip on a track (drag-to-create)
  Future<void> onCreateClipOnTrack(
    int trackId,
    double startBeats,
    double durationBeats,
  ) async {
    // Create the clip first — its command callback selects it — then select
    // the track. Selecting the track before the clip existed cleared the clip
    // selection and raced the create command (visible flicker, bug-hunt #21).
    await createMidiClipWithParams(trackId, startBeats, durationBeats);
    onTrackSelected(trackId, autoSelectClip: true);
    // Creating a clip is deliberate (double-click / drag on empty track
    // space): open the editor on it. Selecting alone never does.
    if (mounted) setState(() => uiLayout.isEditorPanelVisible = true);
  }

  /// Create a MIDI clip with custom start position and duration
  Future<void> createMidiClipWithParams(
    int trackId,
    double startBeats,
    double durationBeats,
  ) async {
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: startBeats,
      duration: durationBeats,
      loopLength:
          durationBeats, // Loop length matches arrangement length initially
      name: generateClipName(trackId),
      notes: [],
    );

    // Use undo/redo for clip creation
    final command = CreateMidiClipCommand(
      clipData: clip,
      onClipCreated: (newClip) {
        // Resolve overlaps at the new clip's position
        final overlapResult = ClipOverlapHandler.resolveMidiOverlaps(
          newStart: startBeats,
          newEnd: startBeats + durationBeats,
          existingClips: List<MidiClipData>.from(
            midiPlaybackManager?.midiClips ?? [],
          ),
          trackId: trackId,
        );
        ClipOverlapHandler.applyMidiResult(
          result: overlapResult,
          deleteClip: (cId, tId) => midiClipController.deleteClip(cId, tId),
          updateClipInPlace: (c) => midiPlaybackManager?.updateClipInPlace(c),
          rescheduleClip: (c, t) => midiPlaybackManager?.rescheduleClip(c, t),
          addClip: (c) => midiPlaybackManager?.addRecordedClip(c),
          tempo: tempo,
        );
        midiPlaybackManager?.addRecordedClip(newClip);
        midiPlaybackManager?.selectClip(newClip.clipId, newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId, tId) {
        midiClipController.deleteClip(clipId, tId);
        if (mounted) setState(() {});
      },
    );
    await undoRedoManager.execute(command);
  }

  // ============================================
  // CAPTURE MIDI
  // ============================================

  /// Capture MIDI from the buffer and create a clip
  Future<void> captureMidi() async {
    if (audioEngine == null) return;

    // Check if we have a selected track
    if (selectedTrackId == null) {
      Notices.info('Select a MIDI track first');
      return;
    }

    // Show capture dialog
    final capturedEvents = await CaptureMidiDialog.show(
      context,
      midiCaptureBuffer,
    );

    if (capturedEvents == null || capturedEvents.isEmpty) {
      return;
    }

    // Convert captured events to MIDI notes
    final notes = <MidiNoteData>[];
    final Map<int, MidiEvent> activeNotes = {};

    for (final event in capturedEvents) {
      if (event.isNoteOn) {
        // Store note-on event
        activeNotes[event.note] = event;
      } else {
        // Find matching note-on and create MidiNoteData
        final noteOn = activeNotes.remove(event.note);
        if (noteOn != null) {
          final duration = event.beatsFromStart - noteOn.beatsFromStart;
          notes.add(
            MidiNoteData(
              note: event.note,
              velocity: noteOn.velocity,
              startTime: noteOn.beatsFromStart,
              duration: duration.clamp(
                0.1,
                double.infinity,
              ), // Min duration of 0.1 beats
            ),
          );
        }
      }
    }

    // Handle any notes that didn't get a note-off (sustained notes)
    for (final noteOn in activeNotes.values) {
      notes.add(
        MidiNoteData(
          note: noteOn.note,
          velocity: noteOn.velocity,
          startTime: noteOn.beatsFromStart,
          duration: 1.0, // Default 1 beat duration for sustained notes
        ),
      );
    }

    if (notes.isEmpty) {
      Notices.info('Nothing to capture yet: play some notes first');
      return;
    }

    // Calculate clip duration based on last note
    final lastNote = notes.reduce(
      (a, b) => (a.startTime + a.duration) > (b.startTime + b.duration) ? a : b,
    );
    final clipDuration = (lastNote.startTime + lastNote.duration)
        .ceilToDouble();

    // Create the clip
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: selectedTrackId!,
      startTime:
          playheadPosition / 60.0 * tempo, // Current playhead position in beats
      duration: clipDuration,
      loopLength: clipDuration,
      name: generateClipName(selectedTrackId!),
      notes: notes,
    );

    midiPlaybackManager?.addRecordedClip(clip);
  }

  // ============================================
  // UNDO/REDO
  // ============================================

  /// Perform undo
  Future<void> performUndo() async {
    final success = await undoRedoManager.undo();
    if (success && mounted) {
      refreshTrackWidgets();
    }
  }

  /// Perform redo
  Future<void> performRedo() async {
    final success = await undoRedoManager.redo();
    if (success && mounted) {
      refreshTrackWidgets();
    }
  }
}
