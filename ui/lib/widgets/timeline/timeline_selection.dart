import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../constants/ui_constants.dart';
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import 'timeline_state.dart';
import '../timeline_view.dart';

/// Mixin containing clip selection methods for TimelineView.
/// Separates selection logic from main timeline code.
mixin TimelineSelectionMixin on State<TimelineView>, TimelineViewStateMixin {
  /// Get selected audio clip data (if any)
  ClipData? get selectedAudioClip {
    if (selectedAudioClipId == null) return null;
    try {
      return clips.firstWhere((c) => c.clipId == selectedAudioClipId);
    } catch (_) {
      return null;
    }
  }

  /// Select an audio clip by ID
  void selectAudioClip(int? clipId) {
    setState(() {
      selectedAudioClipId = clipId;
      // Also update multi-select
      selectedAudioClipIds.clear();
      if (clipId != null) {
        selectedAudioClipIds.add(clipId);
      }
      // Clear MIDI selection when selecting audio clip
      selectedMidiClipIds.clear();
    });

    // Notify parent about audio clip selection
    final selectedClip = selectedAudioClip;
    widget.onAudioClipSelected?.call(selectedAudioClipId, selectedClip);
  }

  /// Check if a MIDI clip is selected
  bool isMidiClipSelected(int clipId) => selectedMidiClipIds.contains(clipId);

  /// Check if an audio clip is selected
  bool isAudioClipSelected(int clipId) => selectedAudioClipIds.contains(clipId);

  /// Select a MIDI clip with multi-selection support
  /// - Normal click on unselected: Select only this clip (clear others)
  /// - Normal click on selected: Keep selection (for multi-drag) unless forceSelect is true
  /// - Shift+click: Toggle selection (add/remove)
  /// - forceSelect: If true, always select only this clip (used for tap-up after no drag)
  void selectMidiClipMulti(int clipId, {bool addToSelection = false, bool toggleSelection = false, bool forceSelect = false}) {
    setState(() {
      if (toggleSelection) {
        // Shift+click: Toggle this clip's selection
        if (selectedMidiClipIds.contains(clipId)) {
          selectedMidiClipIds.remove(clipId);
        } else {
          selectedMidiClipIds.add(clipId);
        }
      } else if (addToSelection) {
        // Add to selection
        selectedMidiClipIds.add(clipId);
      } else if (forceSelect || !selectedMidiClipIds.contains(clipId)) {
        // Normal click on unselected, OR tap completed (forceSelect): select only this clip
        selectedMidiClipIds.clear();
        selectedMidiClipIds.add(clipId);
      }
      // If clip is already selected and not forceSelect, keep multi-selection (for drag)
      // Only clear audio selection on regular clicks, not shift+click (cross-type selection)
      if (!toggleSelection) {
        selectedAudioClipIds.clear();
        selectedAudioClipId = null;
      }
    });
  }

  /// Select an audio clip with multi-selection support
  /// - Normal click on unselected: Select only this clip (clear others)
  /// - Normal click on selected: Keep selection (for multi-drag) unless forceSelect is true
  /// - Shift+click: Toggle selection (add/remove)
  /// - forceSelect: If true, always select only this clip (used for tap-up after no drag)
  void selectAudioClipMulti(int clipId, {bool addToSelection = false, bool toggleSelection = false, bool forceSelect = false}) {
    setState(() {
      if (toggleSelection) {
        // Shift+click: Toggle this clip's selection
        if (selectedAudioClipIds.contains(clipId)) {
          selectedAudioClipIds.remove(clipId);
          if (selectedAudioClipId == clipId) {
            selectedAudioClipId = selectedAudioClipIds.isEmpty ? null : selectedAudioClipIds.first;
          }
        } else {
          selectedAudioClipIds.add(clipId);
          selectedAudioClipId = clipId;
        }
      } else if (addToSelection) {
        // Add to selection
        selectedAudioClipIds.add(clipId);
        selectedAudioClipId = clipId;
      } else if (forceSelect || !selectedAudioClipIds.contains(clipId)) {
        // Normal click on unselected, OR tap completed (forceSelect): select only this clip
        selectedAudioClipIds.clear();
        selectedAudioClipIds.add(clipId);
        selectedAudioClipId = clipId;
      }
      // If clip is already selected and not forceSelect, keep multi-selection (for drag)
      // Only clear MIDI selection on regular clicks, not shift+click (cross-type selection)
      if (!toggleSelection) {
        selectedMidiClipIds.clear();
      }
    });

    // Notify parent about audio clip selection
    final selectedClip = selectedAudioClip;
    widget.onAudioClipSelected?.call(selectedAudioClipId, selectedClip);
  }

  /// Clear all clip selections
  void clearClipSelection() {
    setState(() {
      selectedMidiClipIds.clear();
      selectedAudioClipIds.clear();
      selectedAudioClipId = null;
    });
  }

  /// Select all clips (both MIDI and audio)
  void selectAllClips() {
    setState(() {
      // Select all MIDI clips
      selectedMidiClipIds.clear();
      for (final clip in widget.midiClips) {
        selectedMidiClipIds.add(clip.clipId);
      }

      // Select all audio clips
      selectedAudioClipIds.clear();
      for (final clip in clips) {
        selectedAudioClipIds.add(clip.clipId);
      }
    });
  }

  /// Get all selected MIDI clips data
  List<MidiClipData> get selectedMidiClips {
    return widget.midiClips.where((c) => selectedMidiClipIds.contains(c.clipId)).toList();
  }

  /// Get all selected audio clips data
  List<ClipData> get selectedAudioClips {
    return clips.where((c) => selectedAudioClipIds.contains(c.clipId)).toList();
  }

  /// Deselect all clips (audio and MIDI) and notify parent
  void deselectAllClips() {
    setState(() {
      selectedAudioClipIds.clear();
      selectedMidiClipIds.clear();
      selectedAudioClipId = null;
    });

    // Notify parent to clear MIDI clip selection (for piano roll)
    widget.onMidiClipSelected?.call(null, null);
  }

  /// Update selection based on box selection rectangle.
  /// Called during drag to provide live selection feedback.
  void updateBoxSelection() {
    if (!isBoxSelecting || boxSelectionStart == null || boxSelectionEnd == null) return;

    // Skip if box is too small (essentially a click, not a drag)
    // Use 10px minimum to avoid accidental selection during click
    final boxWidth = (boxSelectionEnd!.dx - boxSelectionStart!.dx).abs();
    final boxHeight = (boxSelectionEnd!.dy - boxSelectionStart!.dy).abs();
    if (boxWidth < 10 && boxHeight < 10) return;

    // Box selection coordinates are already in absolute content space (pixels)
    // Convert to beat range (X axis)
    final minX = math.min(boxSelectionStart!.dx, boxSelectionEnd!.dx);
    final maxX = math.max(boxSelectionStart!.dx, boxSelectionEnd!.dx);

    final minBeats = minX / pixelsPerBeat;
    final maxBeats = maxX / pixelsPerBeat;

    // Calculate Y bounds of selection rectangle in CONTENT coordinates
    // (stored Y is in visible space, add vertical scroll offset to get content space)
    final verticalOffset = widget.verticalScrollController?.hasClients == true
        ? widget.verticalScrollController!.offset
        : 0.0;
    final minY = math.min(boxSelectionStart!.dy, boxSelectionEnd!.dy) + verticalOffset;
    final maxY = math.max(boxSelectionStart!.dy, boxSelectionEnd!.dy) + verticalOffset;

    // Use regularTracks (non-Master) to match visual layout
    final regularTracks = tracks.where((t) => t.type != 'Master').toList();

    // Helper to check if a track is within Y bounds
    bool isTrackInYRange(int trackId) {
      final trackIndex = regularTracks.indexWhere((t) => t.id == trackId);
      if (trackIndex < 0) return false;

      double trackTop = 0.0;
      for (int i = 0; i < trackIndex; i++) {
        trackTop += widget.clipHeights[regularTracks[i].id] ?? UIConstants.defaultClipHeight;
        // Include automation height if visible for this track
        if (widget.automationVisibleTrackId == regularTracks[i].id) {
          trackTop += widget.automationHeights[regularTracks[i].id] ?? UIConstants.defaultAutomationHeight;
        }
      }
      // Only use clip height for hit testing (clips are in clip area only)
      final trackHeight = widget.clipHeights[regularTracks[trackIndex].id] ?? UIConstants.defaultClipHeight;
      final trackBottom = trackTop + trackHeight;

      // Check if track overlaps with selection Y range
      return trackTop < maxY && trackBottom > minY;
    }

    // Clear and rebuild selection (preserve shift behavior handled at start)
    final newMidiSelection = <int>{};
    final newAudioSelection = <int>{};

    // Check all MIDI clips (both X and Y overlap)
    for (final clip in widget.midiClips) {
      final clipStart = clip.startTime;
      final clipEnd = clip.startTime + clip.duration;

      // Check if clip overlaps with selection rectangle (both X and Y)
      if (clipStart < maxBeats && clipEnd > minBeats && isTrackInYRange(clip.trackId)) {
        newMidiSelection.add(clip.clipId);
      }
    }

    // Check all audio clips (both X and Y overlap)
    final beatsPerSecond = widget.tempo / 60.0;
    for (final clip in clips) {
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;

      if (clipStartBeats < maxBeats && clipEndBeats > minBeats && isTrackInYRange(clip.trackId)) {
        newAudioSelection.add(clip.clipId);
      }
    }

    // Update selection state
    setState(() {
      // If shift was held at START, merge initial selection with current box intersection
      // Otherwise, replace selection with current box intersection
      if (boxSelectionShiftHeld) {
        // Additive mode: initial selection + current box intersection
        selectedMidiClipIds
          ..clear()
          ..addAll(boxSelectionInitialMidiIds)
          ..addAll(newMidiSelection);
        selectedAudioClipIds
          ..clear()
          ..addAll(boxSelectionInitialAudioIds)
          ..addAll(newAudioSelection);
      } else {
        // Replace mode: only clips in current box intersection
        selectedMidiClipIds
          ..clear()
          ..addAll(newMidiSelection);
        selectedAudioClipIds
          ..clear()
          ..addAll(newAudioSelection);
      }
    });
  }
}
