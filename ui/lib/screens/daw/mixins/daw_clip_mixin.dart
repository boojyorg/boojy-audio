import 'package:flutter/material.dart';
import '../../../models/clip_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/midi_event.dart';
import '../../../services/commands/command.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../utils/clip_overlap_handler.dart';
import '../../../theme/theme_extension.dart';
import '../../../widgets/capture_midi_dialog.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';

/// Mixin containing clip-related methods for DAWScreen.
/// Handles MIDI and audio clip selection, creation, duplication, split, quantize, delete.
mixin DAWClipMixin on State<DAWScreen>, DAWScreenStateMixin, DAWRecordingMixin, DAWUIMixin, DAWTrackMixin {
  // ============================================
  // MIDI CLIP SELECTION
  // ============================================

  /// Handle MIDI clip selection
  void onMidiClipSelected(int? clipId, MidiClipData? clipData) {
    final trackId = midiClipController.selectClip(clipId, clipData);
    if (clipId != null && clipData != null) {
      // Don't auto-open editor panel - let user control visibility via View menu or double-click
      selectedTrackId = trackId ?? clipData.trackId;
    }
  }

  /// Handle MIDI clip update
  void onMidiClipUpdated(MidiClipData updatedClip) {
    midiClipController.updateClip(updatedClip, playheadPosition);

    // Propagate changes to all linked clips (same patternId)
    midiPlaybackManager?.updateLinkedClips(updatedClip, tempo);

    // Auto-update arrangement loop region to follow content
    updateArrangementLoopToContent();
  }

  // ============================================
  // CLIP COPY/DUPLICATE
  // ============================================

  /// Handle MIDI clip copy (Alt+drag)
  void onMidiClipCopied(MidiClipData sourceClip, double newStartTime) {
    debugPrint('[OVERLAP] onMidiClipCopied: clip ${sourceClip.clipId} "${sourceClip.name}" → newStart=${newStartTime.toStringAsFixed(3)} beats, track ${sourceClip.trackId}');
    // Use undo/redo manager for arrangement operations
    final command = DuplicateMidiClipCommand(
      originalClip: sourceClip,
      newStartTime: newStartTime,
      onClipDuplicated: (newClip, sharedPatternId) {
        // Update original clip's patternId if it was null (first duplication)
        if (sourceClip.patternId == null) {
          final updatedOriginal = sourceClip.copyWith(patternId: sharedPatternId);
          midiPlaybackManager?.updateClipInPlace(updatedOriginal);
        }

        // Resolve overlaps at the copy's position
        // Note: source clip is NOT excluded — if the copy overlaps the source,
        // the source should be trimmed (standard DAW behavior).
        final overlapResult = ClipOverlapHandler.resolveMidiOverlaps(
          newStart: newStartTime,
          newEnd: newStartTime + sourceClip.duration,
          existingClips: List<MidiClipData>.from(midiPlaybackManager?.midiClips ?? []),
          trackId: sourceClip.trackId,
        );
        ClipOverlapHandler.applyMidiResult(
          result: overlapResult,
          deleteClip: (cId, tId) => midiClipController.deleteClip(cId, tId),
          updateClipInPlace: (clip) => midiPlaybackManager?.updateClipInPlace(clip),
          rescheduleClip: (clip, t) => midiPlaybackManager?.rescheduleClip(clip, t),
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
        midiClipController.deleteClip(clipId, clip?.trackId ?? sourceClip.trackId);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  /// Handle audio clip copy (Alt+drag)
  void onAudioClipCopied(ClipData sourceClip, double newStartTime) {
    debugPrint('[OVERLAP] onAudioClipCopied: clip ${sourceClip.clipId} → newStart=${newStartTime.toStringAsFixed(3)}s, track ${sourceClip.trackId}');
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
          existingClips: List<ClipData>.from(timelineKey.currentState?.clips ?? []),
          trackId: sourceClip.trackId,
        );
        ClipOverlapHandler.applyAudioResult(
          result: overlapResult,
          engineRemoveClip: (tId, cId) => audioEngine?.removeAudioClip(tId, cId),
          engineSetStartTime: (tId, cId, s) => audioEngine?.setClipStartTime(tId, cId, s),
          engineSetOffset: (tId, cId, o) => audioEngine?.setClipOffset(tId, cId, o),
          engineSetDuration: (tId, cId, d) => audioEngine?.setClipDuration(tId, cId, d),
          engineDuplicateClip: (tId, cId, s) => audioEngine?.duplicateAudioClip(tId, cId, s) ?? -1,
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
    final clip = midiPlaybackManager?.currentEditingClip;
    if (clip == null) return;

    // Place duplicate immediately after original
    final newStartTime = clip.startTime + clip.duration;
    onMidiClipCopied(clip, newStartTime);
  }

  // ============================================
  // CLIP SPLIT
  // ============================================

  /// Split selected clip at playhead position
  void splitSelectedClipAtPlayhead() {
    // Split at playhead position
    final splitPosition = playheadPosition;

    // Try MIDI clip first
    if (midiPlaybackManager?.selectedClipId != null) {
      final success = midiClipController.splitSelectedClipAtPlayhead(splitPosition);
      if (success && mounted) {
        setState(() {
          statusMessage = 'Split MIDI clip at playhead';
        });
        return;
      }
    }

    // Try audio clip if no MIDI clip or MIDI split failed
    final audioSplit = timelineKey.currentState?.splitSelectedAudioClipAtPlayhead(splitPosition) ?? false;
    if (audioSplit && mounted) {
      setState(() {
        statusMessage = 'Split audio clip at playhead';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        statusMessage = 'Cannot split: select a clip and place playhead within it';
      });
    }
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
      if (success && mounted) {
        setState(() {
          statusMessage = 'Quantized MIDI clip to grid';
        });
        return;
      }
    }

    // Try audio clip
    final audioQuantized = timelineKey.currentState?.quantizeSelectedAudioClip(gridSizeSeconds) ?? false;
    if (audioQuantized && mounted) {
      setState(() {
        statusMessage = 'Quantized audio clip to grid';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        statusMessage = 'Cannot quantize: select a clip first';
      });
    }
  }

  // ============================================
  // CLIP SELECTION
  // ============================================

  /// Select all clips in the timeline view
  void selectAllClips() {
    timelineKey.currentState?.selectAllClips();
    if (mounted) {
      setState(() {
        statusMessage = 'Selected all clips';
      });
    }
  }

  // ============================================
  // BOUNCE MIDI TO AUDIO
  // ============================================

  /// Bounce MIDI to Audio - renders MIDI through instrument to audio file
  /// NOTE: This is a placeholder that shows planned feature message.
  void bounceMidiToAudio() {
    final selectedClipId = midiPlaybackManager?.selectedClipId;
    final selectedClip = midiPlaybackManager?.currentEditingClip;

    if (selectedClipId == null || selectedClip == null) {
      setState(() {
        statusMessage = 'Select a MIDI clip to bounce to audio';
      });
      return;
    }

    // Show dialog explaining this is a planned feature
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bounce MIDI to Audio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selected clip: ${selectedClip.name}'),
            const SizedBox(height: 12),
            Text(
              'This feature will render the MIDI clip through its instrument '
              'to create an audio file.\n\n'
              'Coming soon in a future update.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // CONSOLIDATE CLIPS
  // ============================================

  /// Consolidate multiple selected MIDI clips into a single clip
  void consolidateSelectedClips() {
    final timelineState = timelineKey.currentState;
    if (timelineState == null) return;

    // Get selected MIDI clips
    final selectedMidiClips = timelineState.selectedMidiClips;

    if (selectedMidiClips.length < 2) {
      setState(() {
        statusMessage = 'Select 2 or more MIDI clips to consolidate';
      });
      return;
    }

    // Ensure all clips are on the same track
    final trackIds = selectedMidiClips.map((c) => c.trackId).toSet();
    if (trackIds.length > 1) {
      setState(() {
        statusMessage = 'Cannot consolidate clips from different tracks';
      });
      return;
    }

    final trackId = trackIds.first;

    // Sort clips by start time
    final sortedClips = List<MidiClipData>.from(selectedMidiClips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Calculate consolidated clip bounds
    final firstClipStart = sortedClips.first.startTime;
    final lastClipEnd = sortedClips.map((c) => c.endTime).reduce((a, b) => a > b ? a : b);
    final totalDuration = lastClipEnd - firstClipStart;

    // Merge all notes with adjusted timing
    final mergedNotes = <MidiNoteData>[];
    for (final clip in sortedClips) {
      final clipOffset = clip.startTime - firstClipStart;
      for (final note in clip.notes) {
        mergedNotes.add(note.copyWith(
          startTime: note.startTime + clipOffset,
          id: '${note.note}_${note.startTime + clipOffset}_${DateTime.now().microsecondsSinceEpoch}',
        ));
      }
    }

    // Sort notes by start time
    mergedNotes.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Create consolidated clip
    final consolidatedClip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: firstClipStart,
      duration: totalDuration,
      loopLength: totalDuration,
      notes: mergedNotes,
      name: 'Consolidated',
      color: sortedClips.first.color,
    );

    // Delete original clips
    for (final clip in sortedClips) {
      midiClipController.deleteClip(clip.clipId, clip.trackId);
    }

    // Add consolidated clip
    midiClipController.addClip(consolidatedClip);
    midiClipController.updateClip(consolidatedClip, playheadPosition);

    // Select the new consolidated clip
    midiPlaybackManager?.selectClip(consolidatedClip.clipId, consolidatedClip);
    timelineState.clearClipSelection();

    setState(() {
      statusMessage = 'Consolidated ${sortedClips.length} clips into one';
    });
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
        commands.add(DeleteMidiClipFromArrangementCommand(
          clipData: clip,
          onClipRemoved: (cId, tId) {
            midiClipController.deleteClip(cId, tId);
          },
          onClipRestored: (restoredClip) {
            midiPlaybackManager?.addRecordedClip(restoredClip);
            midiClipController.updateClip(restoredClip, playheadPosition);
          },
        ));
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
      commands.add(DeleteAudioClipCommand(
        clipData: clip,
        onClipRemoved: (clipId) {
          timelineKey.currentState?.removeClip(clipId);
        },
        onClipRestored: (restoredClip) {
          timelineKey.currentState?.addClip(restoredClip);
        },
      ));
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
  void onCreateClipOnTrack(int trackId, double startBeats, double durationBeats) {
    // Create a new MIDI clip on the specified track
    createMidiClipWithParams(trackId, startBeats, durationBeats);

    // Select the track
    onTrackSelected(trackId);
  }

  /// Create a MIDI clip with custom start position and duration
  void createMidiClipWithParams(int trackId, double startBeats, double durationBeats) {
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: startBeats,
      duration: durationBeats,
      loopLength: durationBeats, // Loop length matches arrangement length initially
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
          existingClips: List<MidiClipData>.from(midiPlaybackManager?.midiClips ?? []),
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
    undoRedoManager.execute(command);
  }

  // ============================================
  // CAPTURE MIDI
  // ============================================

  /// Capture MIDI from the buffer and create a clip
  Future<void> captureMidi() async {
    if (audioEngine == null) return;

    // Check if we have a selected track
    if (selectedTrackId == null) {
      playbackController.setStatusMessage('Please select a MIDI track first');
      return;
    }

    // Show capture dialog
    final capturedEvents = await CaptureMidiDialog.show(context, midiCaptureBuffer);

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
          notes.add(MidiNoteData(
            note: event.note,
            velocity: noteOn.velocity,
            startTime: noteOn.beatsFromStart,
            duration: duration.clamp(0.1, double.infinity), // Min duration of 0.1 beats
          ));
        }
      }
    }

    // Handle any notes that didn't get a note-off (sustained notes)
    for (final noteOn in activeNotes.values) {
      notes.add(MidiNoteData(
        note: noteOn.note,
        velocity: noteOn.velocity,
        startTime: noteOn.beatsFromStart,
        duration: 1.0, // Default 1 beat duration for sustained notes
      ));
    }

    if (notes.isEmpty) {
      playbackController.setStatusMessage('No complete MIDI notes captured');
      return;
    }

    // Calculate clip duration based on last note
    final lastNote = notes.reduce((a, b) =>
      (a.startTime + a.duration) > (b.startTime + b.duration) ? a : b
    );
    final clipDuration = (lastNote.startTime + lastNote.duration).ceilToDouble();

    // Create the clip
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: selectedTrackId!,
      startTime: playheadPosition / 60.0 * tempo, // Current playhead position in beats
      duration: clipDuration,
      loopLength: clipDuration,
      name: generateClipName(selectedTrackId!),
      notes: notes,
    );

    midiPlaybackManager?.addRecordedClip(clip);
    playbackController.setStatusMessage('Captured ${notes.length} MIDI notes');
  }

  // ============================================
  // UNDO/REDO
  // ============================================

  /// Perform undo
  Future<void> performUndo() async {
    final success = await undoRedoManager.undo();
    if (success && mounted) {
      setState(() {
        statusMessage = 'Undo - ${undoRedoManager.redoDescription ?? "Action"}';
      });
      refreshTrackWidgets();
    }
  }

  /// Perform redo
  Future<void> performRedo() async {
    final success = await undoRedoManager.redo();
    if (success && mounted) {
      setState(() {
        statusMessage = 'Redo - ${undoRedoManager.undoDescription ?? "Action"}';
      });
      refreshTrackWidgets();
    }
  }
}
