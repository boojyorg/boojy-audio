import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'dart:math' as math;
import 'dart:async';
import 'package:cross_file/cross_file.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';
import '../utils/grid_utils.dart';
import '../utils/track_colors.dart';
import '../models/clip_data.dart';
import '../models/midi_note_data.dart';
import '../models/tool_mode.dart';
import '../models/track_automation_data.dart';
import '../models/vst3_plugin_data.dart';
import '../models/library_item.dart';
import '../services/tool_mode_resolver.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/clip_commands.dart';
import 'instrument_browser.dart';
import 'painters/timeline_grid_painter.dart';
import 'platform_drop_target.dart';
import 'context_menus/clip_context_menu.dart';
import 'shared/editors/zoomable_editor_mixin.dart';
import 'shared/editors/unified_nav_bar.dart';
import 'shared/editors/nav_bar_with_zoom.dart';
import 'timeline/timeline_state.dart';
import 'timeline/clip_preview_builders.dart';
import '../services/live_recording_notifier.dart';
import 'timeline/painters/painters.dart';
import 'timeline/track_automation_lane_widget.dart';

/// Track data model for timeline
class TimelineTrackData {
  final int id;
  final String name;
  final String type;

  TimelineTrackData({
    required this.id,
    required this.name,
    required this.type,
  });

  static TimelineTrackData? fromCSV(String csv) {
    try {
      final parts = csv.split(',');
      if (parts.length < 3) return null;
      return TimelineTrackData(
        id: int.parse(parts[0]),
        name: parts[1],
        type: parts[2],
      );
    } catch (e) {
      return null;
    }
  }
}

/// Timeline view widget for displaying audio clips and playhead
class TimelineView extends StatefulWidget {
  final double playheadPosition; // in seconds
  final double? clipDuration; // in seconds (null if no clip loaded)
  final List<double> waveformPeaks; // waveform data
  final AudioEngine? audioEngine;
  final Function(double)? onSeek; // callback when user drags playhead (passes position in seconds)
  final double tempo; // BPM for beat-based grid

  // MIDI editing state
  final int? selectedMidiTrackId;
  final int? selectedMidiClipId;
  final MidiClipData? currentEditingClip;
  final List<MidiClipData> midiClips; // All MIDI clips for visualization
  final Function(int?)? onMidiTrackSelected;
  final Function(int?, MidiClipData?)? onMidiClipSelected;
  final Function(int?, ClipData?)? onAudioClipSelected;
  final Function(MidiClipData)? onMidiClipUpdated;
  final Function(MidiClipData sourceClip, double newStartTime)? onMidiClipCopied;
  final Function(ClipData sourceClip, double newStartTime)? onAudioClipCopied;
  final int Function(int dartClipId)? getRustClipId;
  final Function(int clipId, int trackId)? onMidiClipDeleted;

  // Batch delete callbacks (for eraser tool)
  final Function(List<(int clipId, int trackId)>)? onMidiClipsBatchDeleted;
  final Function(List<ClipData>)? onAudioClipsBatchDeleted;

  // Instrument drag-and-drop
  final Function(int trackId, Instrument instrument)? onInstrumentDropped;
  final Function(Instrument instrument)? onInstrumentDroppedOnEmpty;

  // VST3 instrument drag-and-drop
  final Function(int trackId, Vst3Plugin plugin)? onVst3InstrumentDropped;
  final Function(Vst3Plugin plugin)? onVst3InstrumentDroppedOnEmpty;

  // Audio file drag-and-drop on empty space
  final Function(String filePath)? onAudioFileDroppedOnEmpty;

  // Audio file drag-and-drop on existing track
  final Function(int trackId, String filePath, double startTimeBeats)? onAudioFileDroppedOnTrack;

  // Drag-to-create callbacks
  final Function(String trackType, double startBeats, double durationBeats)? onCreateTrackWithClip;
  final Function(int trackId, double startBeats, double durationBeats)? onCreateClipOnTrack;

  // Track heights (synced from mixer panel)
  final Map<int, double> clipHeights; // trackId -> clip area height
  final Map<int, double> automationHeights; // trackId -> automation lane height
  final double masterTrackHeight;
  final Function(int trackId, double height)? onClipHeightChanged;
  final Function(int trackId, double height)? onAutomationHeightChanged;

  // Track order (synced from TrackController for drag-and-drop reordering)
  final List<int> trackOrder;

  // Track color callback (for auto-detected colors with override support)
  final Color Function(int trackId, String trackName, String trackType)? getTrackColor;

  // Loop playback state (controls if arrangement playback loops)
  final bool loopPlaybackEnabled;
  final double loopStartBeats;
  final double loopEndBeats;
  final Function(double startBeats, double endBeats)? onLoopRegionChanged;

  // Vertical scroll controller (synced with track mixer panel)
  final ScrollController? verticalScrollController;

  // Tool mode (shared with piano roll)
  final ToolMode toolMode;
  final Function(ToolMode)? onToolModeChanged;

  // Recording state (for auto-scroll and visual indicators)
  final bool isRecording;

  // Automation state
  final int? automationVisibleTrackId;
  final TrackAutomationLane? Function(int trackId)? getAutomationLane;
  final Function(int trackId, AutomationPoint point)? onAutomationPointAdded;
  final Function(int trackId, String pointId, AutomationPoint point)? onAutomationPointUpdated;
  final Function(int trackId, String pointId)? onAutomationPointDeleted;
  final Function(int trackId, double? value)? onAutomationPreviewValue; // Callback for live value display during drag
  final ScrollController? automationScrollController; // For syncing automation lane scroll

  const TimelineView({
    super.key,
    required this.playheadPosition,
    this.clipDuration,
    this.waveformPeaks = const [],
    this.audioEngine,
    this.onSeek,
    this.tempo = 120.0,
    this.selectedMidiTrackId,
    this.selectedMidiClipId,
    this.currentEditingClip,
    this.midiClips = const [], // All MIDI clips for visualization
    this.onMidiTrackSelected,
    this.onMidiClipSelected,
    this.onAudioClipSelected,
    this.onMidiClipUpdated,
    this.onMidiClipCopied,
    this.onAudioClipCopied,
    this.getRustClipId,
    this.onMidiClipDeleted,
    this.onMidiClipsBatchDeleted,
    this.onAudioClipsBatchDeleted,
    this.onInstrumentDropped,
    this.onInstrumentDroppedOnEmpty,
    this.onVst3InstrumentDropped,
    this.onVst3InstrumentDroppedOnEmpty,
    this.onAudioFileDroppedOnEmpty,
    this.onAudioFileDroppedOnTrack,
    this.onCreateTrackWithClip,
    this.onCreateClipOnTrack,
    this.clipHeights = const {},
    this.automationHeights = const {},
    this.masterTrackHeight = 60.0,
    this.onClipHeightChanged,
    this.onAutomationHeightChanged,
    this.trackOrder = const [],
    this.getTrackColor,
    this.loopPlaybackEnabled = false,
    this.loopStartBeats = 0.0,
    this.loopEndBeats = 4.0,
    this.onLoopRegionChanged,
    this.verticalScrollController,
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
    this.automationVisibleTrackId,
    this.getAutomationLane,
    this.onAutomationPointAdded,
    this.onAutomationPointUpdated,
    this.onAutomationPointDeleted,
    this.onAutomationPreviewValue,
    this.automationScrollController,
    this.isRecording = false,
  });

  @override
  State<TimelineView> createState() => TimelineViewState();
}

class TimelineViewState extends State<TimelineView> with ZoomableEditorMixin, TimelineViewStateMixin, ClipPreviewBuildersMixin {
  @override
  void initState() {
    super.initState();
    _loadTracksAsync();

    // Refresh tracks every 2 seconds
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _loadTracksAsync();
    });

    // Listen for hardware keyboard events (for instant modifier key updates)
    HardwareKeyboard.instance.addHandler(_onHardwareKey);

    // Initialize cursor based on initial tool mode
    currentCursor = _cursorForToolMode(widget.toolMode);
  }

  /// Handle hardware keyboard events for instant modifier key cursor updates
  bool _onHardwareKey(KeyEvent event) {
    // Update temp tool mode when Shift, Alt, or Cmd/Ctrl is pressed or released
    if (event.logicalKey == LogicalKeyboardKey.shift ||
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight ||
        event.logicalKey == LogicalKeyboardKey.alt ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight ||
        event.logicalKey == LogicalKeyboardKey.meta ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight ||
        event.logicalKey == LogicalKeyboardKey.control ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      updateTempToolMode();
    }
    return false; // Don't consume the event, let other handlers process it
  }

  @override
  void didUpdateWidget(TimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload tracks when audio engine becomes available
    if (widget.audioEngine != null && oldWidget.audioEngine == null) {
      _loadTracksAsync();
    }
    // Reorder tracks immediately when track order changes (from drag-and-drop)
    if (!_listEquals(widget.trackOrder, oldWidget.trackOrder)) {
      _reorderTracksToMatchOrder();
    }
    // Update cursor when tool mode changes (from toolbar button click)
    if (widget.toolMode != oldWidget.toolMode && tempToolMode == null) {
      setState(() {
        currentCursor = _cursorForToolMode(widget.toolMode);
      });
    }
    // Auto-scroll to keep playhead visible during recording
    if (widget.isRecording && scrollController.hasClients) {
      final beatsPerSecond = widget.tempo / 60.0;
      final playheadPixelX = widget.playheadPosition * beatsPerSecond * pixelsPerBeat;
      final viewportRight = scrollController.offset + viewWidth;
      // Scroll when playhead passes 80% of the visible area
      if (playheadPixelX > viewportRight - viewWidth * 0.2) {
        final targetOffset = playheadPixelX - viewWidth * 0.3;
        scrollController.jumpTo(targetOffset.clamp(0.0, scrollController.position.maxScrollExtent));
      }
    }
  }

  /// Get cursor for a given tool mode.
  MouseCursor _cursorForToolMode(ToolMode tool) {
    switch (tool) {
      case ToolMode.draw:
        return SystemMouseCursors.precise;
      case ToolMode.select:
        return SystemMouseCursors.basic;
      case ToolMode.eraser:
        return SystemMouseCursors.forbidden;
      case ToolMode.duplicate:
        return SystemMouseCursors.copy;
      case ToolMode.slice:
        return SystemMouseCursors.verticalText;
    }
  }

  /// Reorder local tracks list to match widget.trackOrder (instant, no async)
  void _reorderTracksToMatchOrder() {
    if (tracks.isEmpty) return;

    final tracksMap = <int, TimelineTrackData>{};
    for (final track in tracks) {
      tracksMap[track.id] = track;
    }

    // Separate master track
    final masterTrack = tracks.where((t) => t.type == 'Master').toList();
    final regularTrackIds = tracksMap.keys.where((id) => tracksMap[id]!.type != 'Master').toSet();

    // Build ordered list
    final orderedTracks = <TimelineTrackData>[];
    for (final id in widget.trackOrder) {
      if (tracksMap.containsKey(id) && regularTrackIds.contains(id)) {
        orderedTracks.add(tracksMap[id]!);
      }
    }
    // Add any tracks not in order (shouldn't happen but just in case)
    for (final id in regularTrackIds) {
      if (!widget.trackOrder.contains(id)) {
        orderedTracks.add(tracksMap[id]!);
      }
    }
    // Add master at end
    orderedTracks.addAll(masterTrack);

    setState(() {
      tracks = orderedTracks;
    });
  }

  /// Compare two lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    scrollController.dispose();
    refreshTimer?.cancel();
    super.dispose();
  }

  /// Calculate timeline position from mouse X coordinate
  double _calculateTimelinePosition(Offset localPosition) {
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final totalX = localPosition.dx + scrollOffset;
    return totalX / pixelsPerSecond;
  }

  /// Get grid snap resolution in beats based on zoom level
  /// Matches TimelineGridPainter._getGridDivision for consistent snapping
  double _getGridSnapResolution() {
    return GridUtils.getTimelineGridResolution(pixelsPerBeat);
  }

  /// Calculate beat position from mouse X coordinate (for MIDI/beat-based operations)
  double _calculateBeatPosition(Offset localPosition) {
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final totalX = localPosition.dx + scrollOffset;
    return totalX / pixelsPerBeat;
  }

  /// Snap a beat value to the current grid resolution
  double _snapToGrid(double beats) {
    final snapResolution = _getGridSnapResolution();
    return GridUtils.snapToGridRound(beats, snapResolution);
  }

  /// Get cursor based on current tool mode
  MouseCursor _getCursorForTool(ToolMode tool, {bool isOverClip = false}) {
    switch (tool) {
      case ToolMode.draw:
        return SystemMouseCursors.precise;
      case ToolMode.select:
        return isOverClip ? SystemMouseCursors.grab : SystemMouseCursors.basic;
      case ToolMode.eraser:
        return SystemMouseCursors.forbidden;
      case ToolMode.duplicate:
        return SystemMouseCursors.copy;
      case ToolMode.slice:
        return SystemMouseCursors.verticalText;
    }
  }

  /// Handle file drop on track
  Future<void> _handleFileDrop(List<XFile> files, int trackId, Offset localPosition) async {
    if (files.isEmpty || widget.audioEngine == null) return;

    final file = files.first;
    final filePath = file.path;

    // Only accept audio files
    if (!filePath.endsWith('.wav') &&
        !filePath.endsWith('.mp3') &&
        !filePath.endsWith('.aif') &&
        !filePath.endsWith('.aiff') &&
        !filePath.endsWith('.flac')) {
      return;
    }

    try {
      // Load audio file
      final clipId = widget.audioEngine!.loadAudioFile(filePath);
      if (clipId < 0) {
        return;
      }

      // Get duration and waveform
      final duration = widget.audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = widget.audioEngine!.getWaveformPeaks(clipId, peakResolution);

      // Calculate drop position
      final startTime = _calculateTimelinePosition(localPosition);

      // Create clip
      final clip = ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: filePath,
        startTime: startTime,
        duration: duration,
        waveformPeaks: peaks,
        color: context.colors.success,
      );

      setState(() {
        clips.add(clip);
        previewClip = null;
        dragHoveredTrackId = null;
      });

    } catch (e) {
      debugPrint('TimelineView: Error loading audio file: $e');
    }
  }

  /// Load waveform data for drag preview.
  /// Uses the engine's preview system to get duration and waveform without creating a clip.
  void _loadWaveformForPreview(String filePath) {
    final engine = widget.audioEngine;
    if (engine == null) return;

    // Load file into engine's preview system
    final result = engine.previewLoadAudio(filePath);
    if (result.startsWith('Error')) return;

    final duration = engine.previewGetDuration();
    final rawPeaks = engine.previewGetWaveform(500); // Low-res for preview

    // Convert single-value peaks to [min, max] pairs
    // WaveformPainter expects [min, max, min, max, ...] format
    // Mirror the max values to create min values for proper waveform display
    final peaks = <double>[];
    for (final value in rawPeaks) {
      peaks.add(-value.abs()); // min (negative/bottom)
      peaks.add(value.abs());  // max (positive/top)
    }

    // Only update if we're still previewing this file
    if (mounted && previewWaveformPath == filePath) {
      setState(() {
        previewWaveformDuration = duration;
        previewWaveformPeaks = peaks;
      });
    }
  }

  /// Clear cached waveform preview data.
  void _clearWaveformPreviewCache() {
    previewWaveformPath = null;
    previewWaveformDuration = null;
    previewWaveformPeaks = null;
  }

  /// Public method to trigger immediate track refresh
  void refreshTracks() {
    _loadTracksAsync();
  }

  /// Public method to clear all clips (used when project is cleared)
  void clearClips() {
    setState(() {
      clips.clear();
    });
  }

  /// Public method to add a clip to the timeline
  void addClip(ClipData clip) {
    setState(() {
      clips.add(clip);
    });
  }

  /// Public method to remove a clip from the timeline (for undo support)
  void removeClip(int clipId) {
    setState(() {
      clips.removeWhere((c) => c.clipId == clipId);
      // Also deselect if this clip was selected
      selectedAudioClipIds.remove(clipId);
      if (selectedAudioClipId == clipId) {
        selectedAudioClipId = null;
      }
    });
  }

  /// Public method to update a clip in the timeline (for Audio Editor changes)
  void updateClip(ClipData updatedClip) {
    setState(() {
      final index = clips.indexWhere((c) => c.clipId == updatedClip.clipId);
      if (index != -1) {
        clips[index] = updatedClip;
      }
    });
  }

  /// Check if a track has any audio clips
  bool hasClipsOnTrack(int trackId) {
    return clips.any((clip) => clip.trackId == trackId);
  }

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

  /// Split the selected audio clip at the given position (in seconds)
  /// Returns true if split was successful
  bool splitSelectedAudioClipAtPlayhead(double playheadSeconds) {
    final clip = selectedAudioClip;
    if (clip == null) {
      return false;
    }

    // Check if playhead is within clip bounds
    if (playheadSeconds <= clip.startTime || playheadSeconds >= clip.endTime) {
      return false;
    }

    // Calculate split point relative to clip start
    final splitRelative = playheadSeconds - clip.startTime;

    // Generate new clip IDs
    final leftClipId = DateTime.now().millisecondsSinceEpoch;
    final rightClipId = leftClipId + 1;

    // Create left clip (same start, shorter duration)
    final leftClip = clip.copyWith(
      clipId: leftClipId,
      duration: splitRelative,
    );

    // Create right clip (starts at split point, uses offset for audio position)
    final rightClip = clip.copyWith(
      clipId: rightClipId,
      startTime: playheadSeconds,
      duration: clip.duration - splitRelative,
      offset: clip.offset + splitRelative,
    );

    // Remove original clip
    setState(() {
      clips.removeWhere((c) => c.clipId == clip.clipId);
      clips.add(leftClip);
      clips.add(rightClip);
      selectedAudioClipId = rightClipId; // Select the right clip
    });

    // TODO: Update engine with split clips when engine API supports it
    // For now, the visual split is applied but engine audio may need refresh

    return true;
  }

  /// Quantize the selected audio clip's start time to the nearest grid position
  /// [gridSizeSeconds] is the grid resolution in seconds
  /// Returns true if quantize was successful
  bool quantizeSelectedAudioClip(double gridSizeSeconds) {
    final clip = selectedAudioClip;
    if (clip == null) {
      return false;
    }

    // Quantize start time to nearest grid position
    final quantizedStart = (clip.startTime / gridSizeSeconds).round() * gridSizeSeconds;

    // Only update if position changed
    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      return false;
    }

    // Update clip position
    widget.audioEngine?.setClipStartTime(clip.trackId, clip.clipId, quantizedStart);

    setState(() {
      final index = clips.indexWhere((c) => c.clipId == clip.clipId);
      if (index >= 0) {
        clips[index] = clips[index].copyWith(startTime: quantizedStart);
      }
    });

    return true;
  }

  // =========================================================================
  // Context Menus
  // =========================================================================

  /// Show context menu for an audio clip
  void _showAudioClipContextMenu(Offset position, ClipData clip) {
    showClipContextMenu(
      context: context,
      position: position,
      clipType: ClipType.audio,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          _deleteAudioClip(clip);
          break;
        case 'duplicate':
          _duplicateAudioClip(clip);
          break;
        case 'split':
          // TODO: Implement split for audio clips
          break;
        case 'cut':
          // TODO: Implement cut for audio clips
          break;
        case 'copy':
          // TODO: Implement copy for audio clips
          break;
        case 'paste':
          // TODO: Implement paste for audio clips
          break;
        case 'mute':
          // TODO: Implement mute for audio clips
          break;
        case 'color':
          // TODO: Implement color picker for audio clips
          break;
        case 'rename':
          // TODO: Implement rename for audio clips
          break;
      }
    });
  }

  /// Show context menu for a MIDI clip
  void _showMidiClipContextMenu(Offset position, MidiClipData clip) {
    showClipContextMenu(
      context: context,
      position: position,
      clipType: ClipType.midi,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
          break;
        case 'duplicate':
          _duplicateMidiClip(clip);
          break;
        case 'split':
          _splitMidiClipAtPlayhead(clip);
          break;
        case 'cut':
          _cutMidiClip(clip);
          break;
        case 'copy':
          _copyMidiClip(clip);
          break;
        case 'paste':
          _pasteMidiClip(clip.trackId);
          break;
        case 'mute':
          _toggleMidiClipMute(clip);
          break;
        case 'loop':
          _toggleMidiClipLoop(clip);
          break;
        case 'bounce':
          // TODO: Implement bounce to audio
          break;
        case 'color':
          _showColorPicker(clip);
          break;
        case 'rename':
          _showRenameDialog(clip);
          break;
      }
    });
  }

  /// Show context menu for the time ruler
  void _showRulerContextMenu(Offset globalPosition, Offset localPosition) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    // Calculate beat position from click
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final xInContent = localPosition.dx + scrollOffset;
    final clickedBeat = xInContent / pixelsPerBeat;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'set_loop_start',
          child: Row(
            children: [
              Icon(Icons.first_page, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set Loop Start Here'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'set_loop_end',
          child: Row(
            children: [
              Icon(Icons.last_page, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set Loop End Here'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'set_loop_1_bar',
          child: Row(
            children: [
              Icon(Icons.crop_square, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set 1 Bar Loop Here'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'set_loop_4_bars',
          child: Row(
            children: [
              Icon(Icons.view_module, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set 4 Bar Loop Here'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'add_marker',
          enabled: false, // Placeholder for future feature
          child: Row(
            children: [
              Icon(Icons.bookmark_add, size: 18, color: context.colors.textMuted),
              const SizedBox(width: 8),
              Text('Add Marker', style: TextStyle(color: context.colors.textMuted)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      // Snap to bar boundary
      final snappedBeat = (clickedBeat / 4.0).floor() * 4.0;

      switch (value) {
        case 'set_loop_start':
          widget.onLoopRegionChanged?.call(snappedBeat, widget.loopEndBeats);
          break;
        case 'set_loop_end':
          widget.onLoopRegionChanged?.call(widget.loopStartBeats, snappedBeat + 4.0);
          break;
        case 'set_loop_1_bar':
          widget.onLoopRegionChanged?.call(snappedBeat, snappedBeat + 4.0);
          break;
        case 'set_loop_4_bars':
          widget.onLoopRegionChanged?.call(snappedBeat, snappedBeat + 16.0);
          break;
        case 'add_marker':
          // TODO: Implement markers in future version
          break;
      }
    });
  }

  /// Show context menu for empty track area
  void _showEmptyAreaContextMenu(Offset globalPosition, Offset localPosition, TimelineTrackData track, bool isMidiTrack) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    // Calculate beat position from click
    final beatPosition = _calculateBeatPosition(localPosition);
    final snappedBeat = _snapToGrid(beatPosition);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isMidiTrack)
          PopupMenuItem<String>(
            value: 'create_clip',
            child: Row(
              children: [
                Icon(Icons.add_box, size: 18, color: context.colors.textSecondary),
                const SizedBox(width: 8),
                const Text('Create MIDI Clip Here'),
                const Spacer(),
                Text('Double-click', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: clipboardMidiClip != null,
          child: Row(
            children: [
              Icon(Icons.paste, size: 18, color: clipboardMidiClip != null ? context.colors.textSecondary : context.colors.textMuted),
              const SizedBox(width: 8),
              Text('Paste', style: TextStyle(color: clipboardMidiClip != null ? null : context.colors.textMuted)),
              const Spacer(),
              Text('⌘V', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'select_all',
          child: Row(
            children: [
              Icon(Icons.select_all, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Select All Clips'),
              const Spacer(),
              Text('⌘A', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'create_clip':
          // Create a 1-bar MIDI clip at the clicked position
          widget.onCreateClipOnTrack?.call(track.id, snappedBeat, 4.0);
          break;
        case 'paste':
          if (clipboardMidiClip != null) {
            _pasteMidiClip(track.id);
          }
          break;
        case 'select_all':
          selectAllClips();
          break;
      }
    });
  }

  /// Delete an audio clip
  Future<void> _deleteAudioClip(ClipData clip) async {
    final command = DeleteAudioClipCommand(
      clipData: clip,
      onClipRemoved: (clipId) {
        if (mounted) {
          setState(() {
            clips.removeWhere((c) => c.clipId == clipId);
            if (selectedAudioClipId == clipId) {
              selectedAudioClipId = null;
            }
            selectedAudioClipIds.remove(clipId);
          });
        }
      },
      onClipRestored: (restoredClip) {
        if (mounted) {
          setState(() {
            clips.add(restoredClip);
          });
        }
      },
    );
    await UndoRedoManager().execute(command);
  }

  /// Duplicate an audio clip (place copy at specified position or after original)
  void _duplicateAudioClip(ClipData clip, {double? atPosition}) {
    final newStartTime = atPosition ?? clip.startTime + clip.duration;
    widget.onAudioClipCopied?.call(clip, newStartTime);
  }

  /// Duplicate a MIDI clip
  void _duplicateMidiClip(MidiClipData clip) {
    final newStartTime = clip.startTime + clip.duration;
    widget.onMidiClipCopied?.call(clip, newStartTime);
  }

  /// Quantize a MIDI clip
  void _quantizeMidiClip(MidiClipData clip) {
    const gridSizeBeats = 1.0; // 1 beat
    final quantizedStart = (clip.startTime / gridSizeBeats).round() * gridSizeBeats;

    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      return;
    }

    final quantizedClip = clip.copyWith(startTime: quantizedStart);
    widget.onMidiClipUpdated?.call(quantizedClip);
  }

  // ========================================================================
  // MIDI CLIP CLIPBOARD OPERATIONS
  // ========================================================================

  /// Copy a MIDI clip to clipboard
  void _copyMidiClip(MidiClipData clip) {
    clipboardMidiClip = clip;
  }

  /// Cut a MIDI clip (copy to clipboard, then delete)
  void _cutMidiClip(MidiClipData clip) {
    clipboardMidiClip = clip;
    widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
  }

  /// Paste a MIDI clip from clipboard to track
  void _pasteMidiClip(int trackId) {
    if (clipboardMidiClip == null) {
      return;
    }

    // Paste at playhead position (convert from seconds to beats)
    final beatsPerSecond = widget.tempo / 60.0;
    final pastePosition = widget.playheadPosition * beatsPerSecond;
    widget.onMidiClipCopied?.call(clipboardMidiClip!, pastePosition);
  }

  // ========================================================================
  // MIDI CLIP PROPERTY TOGGLES
  // ========================================================================

  /// Toggle mute state of a MIDI clip
  void _toggleMidiClipMute(MidiClipData clip) {
    final mutedClip = clip.copyWith(isMuted: !clip.isMuted);
    widget.onMidiClipUpdated?.call(mutedClip);
  }

  /// Toggle loop state of a MIDI clip (controls if content can repeat when stretched)
  void _toggleMidiClipLoop(MidiClipData clip) {
    final loopedClip = clip.copyWith(canRepeat: !clip.canRepeat);
    widget.onMidiClipUpdated?.call(loopedClip);
  }

  // ========================================================================
  // MIDI CLIP DIALOGS
  // ========================================================================

  /// Show color picker for a MIDI clip
  void _showColorPicker(MidiClipData clip) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.pink,
      Colors.amber,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clip Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                final coloredClip = clip.copyWith(color: color);
                widget.onMidiClipUpdated?.call(coloredClip);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: clip.color == color ? this.context.colors.textPrimary : this.context.colors.dark,
                    width: 3,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Show rename dialog for a MIDI clip
  void _showRenameDialog(MidiClipData clip) {
    final controller = TextEditingController(text: clip.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Clip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Clip Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              final renamedClip = clip.copyWith(name: value);
              widget.onMidiClipUpdated?.call(renamedClip);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text;
              if (value.isNotEmpty) {
                final renamedClip = clip.copyWith(name: value);
                widget.onMidiClipUpdated?.call(renamedClip);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // ERASER MODE (Ctrl/Cmd+drag to delete multiple clips)
  // ========================================================================

  /// Start eraser mode
  // Pending clips to delete (for batched eraser undo)
  final List<ClipData> _pendingAudioClipsToErase = [];
  final List<(int clipId, int trackId)> _pendingMidiClipsToErase = [];

  void _startErasing(Offset globalPosition) {
    setState(() {
      isErasing = true;
      erasedAudioClipIds.clear();
      erasedMidiClipIds.clear();
      _pendingAudioClipsToErase.clear();
      _pendingMidiClipsToErase.clear();
    });
    _eraseClipsAt(globalPosition);
  }

  /// Mark clips for erasing at the given position (batched deletion on stop)
  void _eraseClipsAt(Offset globalPosition) {
    if (!isErasing) return;

    // Convert global position to local position relative to timeline content
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPosition = box.globalToLocal(globalPosition);

    // Calculate beat position from mouse X (accounting for horizontal scroll)
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final beatPosition = (localPosition.dx + scrollOffset) / pixelsPerBeat;

    // Calculate Y position in track coordinate space
    // localPosition.dy is relative to TimelineView top
    // We need to account for:
    // 1. Nav bar height (24px) - subtract this to get position relative to tracks area
    // 2. Vertical scroll offset - add this to convert from visible to content coordinates
    const navBarHeight = 24.0;
    final verticalScrollOffset = widget.verticalScrollController?.hasClients == true
        ? widget.verticalScrollController!.offset
        : 0.0;
    final trackAreaY = localPosition.dy - navBarHeight + verticalScrollOffset;

    // Use regularTracks (non-Master) for Y position calculations to match visual layout
    final regularTracks = tracks.where((t) => t.type != 'Master').toList();

    // Check audio clips
    for (final clip in clips) {
      if (erasedAudioClipIds.contains(clip.clipId)) continue;

      // Convert clip times from seconds to beats for comparison
      final beatsPerSecond = widget.tempo / 60.0;
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;

      // Find track Y position using actual track heights (regularTracks matches rendering order)
      final trackIndex = regularTracks.indexWhere((t) => t.id == clip.trackId);
      if (trackIndex < 0) continue;

      double trackTop = 0.0;
      for (int i = 0; i < trackIndex; i++) {
        trackTop += widget.clipHeights[regularTracks[i].id] ?? 100.0;
        // Include automation height if visible for this track
        if (widget.automationVisibleTrackId == regularTracks[i].id) {
          trackTop += widget.automationHeights[regularTracks[i].id] ?? 60.0;
        }
      }
      // Only use clip height for hit testing (clips are in clip area only)
      final trackHeight = widget.clipHeights[regularTracks[trackIndex].id] ?? 100.0;
      final trackBottom = trackTop + trackHeight;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          trackAreaY >= trackTop &&
          trackAreaY <= trackBottom) {
        erasedAudioClipIds.add(clip.clipId);
        _pendingAudioClipsToErase.add(clip);
        // Update UI immediately to show clip as "erased" (visual feedback)
        setState(() {});
      }
    }

    // Check MIDI clips
    for (final midiClip in widget.midiClips) {
      if (erasedMidiClipIds.contains(midiClip.clipId)) continue;

      final clipStartBeats = midiClip.startTime;
      final clipEndBeats = midiClip.startTime + midiClip.duration;

      // Find track Y position using actual track heights (regularTracks matches rendering order)
      final trackIndex = regularTracks.indexWhere((t) => t.id == midiClip.trackId);
      if (trackIndex < 0) continue;

      double trackTop = 0.0;
      for (int i = 0; i < trackIndex; i++) {
        trackTop += widget.clipHeights[regularTracks[i].id] ?? 100.0;
        // Include automation height if visible for this track
        if (widget.automationVisibleTrackId == regularTracks[i].id) {
          trackTop += widget.automationHeights[regularTracks[i].id] ?? 60.0;
        }
      }
      // Only use clip height for hit testing (clips are in clip area only)
      final trackHeight = widget.clipHeights[regularTracks[trackIndex].id] ?? 100.0;
      final trackBottom = trackTop + trackHeight;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          trackAreaY >= trackTop &&
          trackAreaY <= trackBottom) {
        erasedMidiClipIds.add(midiClip.clipId);
        _pendingMidiClipsToErase.add((midiClip.clipId, midiClip.trackId));
        // Update UI immediately to show clip as "erased" (visual feedback)
        setState(() {});
      }
    }
  }

  /// Stop eraser mode and batch-delete all marked clips (single undo action)
  void _stopErasing() {
    if (isErasing) {
      // Batch delete all pending clips (single undo action for all)
      if (_pendingMidiClipsToErase.isNotEmpty) {
        widget.onMidiClipsBatchDeleted?.call(_pendingMidiClipsToErase.toList());
      }
      if (_pendingAudioClipsToErase.isNotEmpty) {
        widget.onAudioClipsBatchDeleted?.call(_pendingAudioClipsToErase.toList());
      }
    }
    setState(() {
      isErasing = false;
      erasedAudioClipIds.clear();
      erasedMidiClipIds.clear();
      _pendingAudioClipsToErase.clear();
      _pendingMidiClipsToErase.clear();
    });
  }

  // ========================================================================
  // SELECTION (Escape to deselect, Cmd+A to select all)
  // ========================================================================

  /// Deselect all clips (audio and MIDI)
  void _deselectAllClips() {
    final hadSelection = selectedAudioClipIds.isNotEmpty ||
        selectedMidiClipIds.isNotEmpty ||
        widget.selectedMidiClipId != null;

    setState(() {
      selectedAudioClipIds.clear();
      selectedMidiClipIds.clear();
      selectedAudioClipId = null;
    });

    // Notify parent to clear MIDI clip selection (for piano roll)
    widget.onMidiClipSelected?.call(null, null);

    if (hadSelection) {
    }
  }

  /// Select all clips (audio and MIDI)
  void _selectAllClips() {
    setState(() {
      // Select all audio clips
      selectedAudioClipIds.clear();
      for (final clip in clips) {
        selectedAudioClipIds.add(clip.clipId);
      }

      // Select all MIDI clips
      selectedMidiClipIds.clear();
      for (final clip in widget.midiClips) {
        selectedMidiClipIds.add(clip.clipId);
      }
    });

  }

  // ========================================================================
  // SPLIT PREVIEW (hover shows line, Alt+click splits)
  // ========================================================================

  /// Update split preview for MIDI clip
  void _updateMidiClipSplitPreview(int clipId, double localX, double clipWidth, MidiClipData clip) {
    // Convert local X position to beat position within clip
    final positionRatio = localX / clipWidth;
    final beatPosition = positionRatio * clip.duration;

    setState(() {
      splitPreviewAudioClipId = null;
      splitPreviewMidiClipId = clipId;
      splitPreviewBeatPosition = beatPosition;
    });
  }

  /// Clear split preview
  void _clearSplitPreview() {
    setState(() {
      splitPreviewAudioClipId = null;
      splitPreviewMidiClipId = null;
    });
  }

  /// Split audio clip at preview position
  Future<void> _splitAudioClipAtPreview(ClipData clip) async {
    if (splitPreviewAudioClipId != clip.clipId) return;

    // Convert beat position back to seconds
    final splitTimeRelative = splitPreviewBeatPosition * (60.0 / widget.tempo);
    final splitTimeAbsolute = clip.startTime + splitTimeRelative;

    // Validate split point is within clip bounds
    if (splitTimeRelative <= 0 || splitTimeRelative >= clip.duration) {
      _clearSplitPreview();
      return;
    }

    // Store original clip data for undo
    final originalClip = clip;

    // Create command for split operation
    final command = SplitAudioClipCommand(
      originalClipId: clip.clipId,
      originalTrackId: clip.trackId,
      originalFilePath: clip.filePath,
      originalStartTime: clip.startTime,
      originalDuration: clip.duration,
      originalOffset: clip.offset,
      originalWaveformPeaks: clip.waveformPeaks,
      splitPointSeconds: splitTimeAbsolute,
      onSplit: (leftClipId, rightClipId) {
        if (!mounted) return;

        // Create left clip (original, shortened - reuse original ID)
        final leftClip = clip.copyWith(
          duration: splitTimeRelative,
        );

        // Create right clip (new, starting at split point)
        final rightClip = clip.copyWith(
          clipId: rightClipId,
          startTime: splitTimeAbsolute,
          duration: clip.duration - splitTimeRelative,
          offset: clip.offset + splitTimeRelative,
        );

        setState(() {
          final index = clips.indexWhere((c) => c.clipId == clip.clipId);
          if (index >= 0) {
            clips[index] = leftClip;
            clips.add(rightClip);
          }
        });

        // Register right clip with engine (load same audio file at new position)
        if (widget.audioEngine != null) {
          final newEngineClipId = widget.audioEngine!.loadAudioFileToTrack(
            clip.filePath,
            clip.trackId,
            startTime: splitTimeAbsolute,
          );
          // Update right clip with engine clip ID if successful
          if (newEngineClipId >= 0) {
            setState(() {
              final rightIndex = clips.indexWhere((c) => c.clipId == rightClipId);
              if (rightIndex >= 0) {
                clips[rightIndex] = clips[rightIndex].copyWith(clipId: newEngineClipId);
              }
            });
          }
        }
      },
      onUndo: () {
        if (!mounted) return;
        setState(() {
          // Remove the right clip
          clips.removeWhere((c) => c.startTime == splitTimeAbsolute && c.trackId == clip.trackId);
          // Restore original left clip
          final index = clips.indexWhere((c) => c.clipId == clip.clipId);
          if (index >= 0) {
            clips[index] = originalClip;
          } else {
            clips.add(originalClip);
          }
        });
      },
    );

    await UndoRedoManager().execute(command);
    _clearSplitPreview();
  }

  /// Split MIDI clip at preview position
  Future<void> _splitMidiClipAtPreview(MidiClipData clip) async {
    if (splitPreviewMidiClipId != clip.clipId) return;

    // Split point in beats relative to clip start
    final splitPointBeats = splitPreviewBeatPosition;

    // Validate split point is within clip bounds
    if (splitPointBeats <= 0 || splitPointBeats >= clip.duration) {
      _clearSplitPreview();
      return;
    }

    // Create command for split operation
    final command = SplitMidiClipCommand(
      originalClip: clip,
      splitPointBeats: splitPointBeats,
      onSplit: (leftClip, rightClip) {
        // Delete original and add both new clips via callbacks
        widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
        // Add both new clips
        widget.onMidiClipCopied?.call(leftClip, leftClip.startTime);
        widget.onMidiClipCopied?.call(rightClip, rightClip.startTime);
      },
      onUndo: (restoredClip) {
        // Delete the split clips (by their IDs)
        // Note: This requires the parent to handle restoration
        // For now, signal that original clip should be restored
        widget.onMidiClipCopied?.call(restoredClip, restoredClip.startTime);
      },
    );

    await UndoRedoManager().execute(command);
    _clearSplitPreview();
  }

  /// Split MIDI clip at playhead position
  void _splitMidiClipAtPlayhead(MidiClipData clip) {
    // Convert playhead from seconds to beats
    final beatsPerSecond = widget.tempo / 60.0;
    final playheadBeats = widget.playheadPosition * beatsPerSecond;

    // Check if playhead is within clip bounds
    if (playheadBeats <= clip.startTime || playheadBeats >= clip.endTime) {
      return;
    }

    // Split point in beats relative to clip start
    final splitPointBeats = playheadBeats - clip.startTime;

    // Split notes into two groups
    final leftNotes = <MidiNoteData>[];
    final rightNotes = <MidiNoteData>[];

    for (final note in clip.notes) {
      if (note.endTime <= splitPointBeats) {
        leftNotes.add(note);
      } else if (note.startTime >= splitPointBeats) {
        rightNotes.add(note.copyWith(
          startTime: note.startTime - splitPointBeats,
          id: '${note.note}_${note.startTime - splitPointBeats}_${DateTime.now().microsecondsSinceEpoch}',
        ));
      } else {
        // Note straddles split - truncate to left
        leftNotes.add(note.copyWith(
          duration: splitPointBeats - note.startTime,
        ));
      }
    }

    // Create left and right clips
    final leftClipId = DateTime.now().millisecondsSinceEpoch;
    final rightClipId = leftClipId + 1;

    final leftClip = clip.copyWith(
      clipId: leftClipId,
      duration: splitPointBeats,
      loopLength: splitPointBeats.clamp(0.25, clip.loopLength),
      notes: leftNotes,
      name: '${clip.name} (L)',
    );

    final rightClip = clip.copyWith(
      clipId: rightClipId,
      startTime: clip.startTime + splitPointBeats,
      duration: clip.duration - splitPointBeats,
      loopLength: (clip.duration - splitPointBeats).clamp(0.25, clip.loopLength),
      notes: rightNotes,
      name: '${clip.name} (R)',
    );

    // Delete original and add both new clips via callbacks
    widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);

    // Add both new clips
    widget.onMidiClipCopied?.call(leftClip, leftClip.startTime);
    widget.onMidiClipCopied?.call(rightClip, rightClip.startTime);

  }

  /// Load tracks from audio engine
  /// Respects track order from TrackController for drag-and-drop reordering
  Future<void> _loadTracksAsync() async {
    if (widget.audioEngine == null) return;

    try {
      final trackIds = await Future.microtask(() {
        return widget.audioEngine!.getAllTrackIds();
      });

      final tracksMap = <int, TimelineTrackData>{};

      for (final int trackId in trackIds) {
        final info = await Future.microtask(() {
          return widget.audioEngine!.getTrackInfo(trackId);
        });

        final track = TimelineTrackData.fromCSV(info);
        if (track != null) {
          tracksMap[track.id] = track;
        }
      }

      if (mounted) {
        setState(() {
          // Separate master track (always at end, not reorderable)
          final masterTrack = tracksMap.values.where((t) => t.type == 'Master').toList();
          final regularTrackIds = tracksMap.keys.where((id) => tracksMap[id]!.type != 'Master').toSet();

          // Build ordered list respecting widget.trackOrder
          final orderedTracks = <TimelineTrackData>[];

          // First add tracks in the specified order
          for (final id in widget.trackOrder) {
            if (tracksMap.containsKey(id) && regularTrackIds.contains(id)) {
              orderedTracks.add(tracksMap[id]!);
            }
          }

          // Add any tracks not in the order list (new tracks)
          for (final id in regularTrackIds) {
            if (!widget.trackOrder.contains(id)) {
              orderedTracks.add(tracksMap[id]!);
            }
          }

          // Add master track at the end
          orderedTracks.addAll(masterTrack);

          tracks = orderedTracks;
        });
      }
    } catch (e) {
      debugPrint('TimelineView: Error loading tracks: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Update viewWidth for zoom calculations
    viewWidth = MediaQuery.of(context).size.width;

    // Beat-based width calculation (tempo-independent)
    final beatsPerSecond = widget.tempo / 60.0;

    // Minimum 64 bars (256 beats) for a typical song length, or extend based on clip duration
    const minBars = 64;
    const beatsPerBar = 4;
    const minBeats = minBars * beatsPerBar;

    // Calculate beats needed for clip duration (if any)
    final clipDurationBeats = widget.clipDuration != null
        ? (widget.clipDuration! * beatsPerSecond).ceil() + 4 // Add padding
        : 0;

    // Use the larger of minimum bars or clip duration
    final totalBeats = math.max(minBeats, clipDurationBeats);
    final totalWidth = math.max(totalBeats * pixelsPerBeat, viewWidth);

    // Duration in seconds for backward compatibility
    final duration = totalBeats / beatsPerSecond;

    // Calculate total tracks height for scrollable area (excludes Master - it's pinned at bottom)
    final regularTracks = tracks.where((t) => t.type != 'Master').toList();
    final masterTrack = tracks.firstWhere(
      (t) => t.type == 'Master',
      orElse: () => TimelineTrackData(id: -1, name: 'Master', type: 'Master'),
    );
    double totalTracksHeight = 0.0;
    for (final track in regularTracks) {
      totalTracksHeight += widget.clipHeights[track.id] ?? 100.0;
      // Add automation lane height if visible for this track
      if (widget.automationVisibleTrackId == track.id) {
        totalTracksHeight += widget.automationHeights[track.id] ?? 60.0;
      }
    }
    totalTracksHeight += 160.0; // Empty drop target area + buffer before Master

    return MouseRegion(
      cursor: currentCursor,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle Delete/Backspace to delete all selected clips
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            bool handled = false;

            // Delete all selected MIDI clips
            if (selectedMidiClipIds.isNotEmpty) {
              final clipsToDelete = <(int, int)>[];
              for (final clipId in selectedMidiClipIds) {
                final clip = widget.midiClips.where((c) => c.clipId == clipId).firstOrNull;
                if (clip != null) {
                  clipsToDelete.add((clip.clipId, clip.trackId));
                }
              }
              if (clipsToDelete.isNotEmpty) {
                widget.onMidiClipsBatchDeleted?.call(clipsToDelete);
                selectedMidiClipIds.clear();
                handled = true;
              }
            }

            // Delete all selected audio clips
            if (selectedAudioClipIds.isNotEmpty) {
              final clipsToDelete = <ClipData>[];
              for (final clipId in selectedAudioClipIds) {
                final clip = clips.where((c) => c.clipId == clipId).firstOrNull;
                if (clip != null) {
                  clipsToDelete.add(clip);
                }
              }
              if (clipsToDelete.isNotEmpty) {
                widget.onAudioClipsBatchDeleted?.call(clipsToDelete);
                selectedAudioClipIds.clear();
                handled = true;
              }
            }

            if (handled) {
              setState(() {});
              return KeyEventResult.handled;
            }
          }

          // Handle Escape to deselect all clips (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _deselectAllClips();
            return KeyEventResult.handled;
          }

          // Cmd+D to duplicate selected clip (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.keyD &&
              ModifierKeyState.current().isCtrlOrCmd) {
            if (widget.selectedMidiClipId != null) {
              final clip = widget.midiClips.where((c) => c.clipId == widget.selectedMidiClipId).firstOrNull;
              if (clip != null) {
                _duplicateMidiClip(clip);
                return KeyEventResult.handled;
              }
            }
          }

          // Cmd+A to select all clips (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.keyA &&
              ModifierKeyState.current().isCtrlOrCmd) {
            _selectAllClips();
            return KeyEventResult.handled;
          }

          // Q to quantize selected clip (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.keyQ) {
            if (widget.selectedMidiClipId != null) {
              final clip = widget.midiClips.where((c) => c.clipId == widget.selectedMidiClipId).firstOrNull;
              if (clip != null) {
                _quantizeMidiClip(clip);
                return KeyEventResult.handled;
              }
            }
          }

          // ============================================
          // Tool shortcuts (Z, X, C, V, B)
          // Press once to switch tool, stays active until switched again
          // ============================================
          final modifiers = ModifierKeyState.current();

          // Z = Draw tool (without Cmd/Ctrl - Cmd+Z is undo)
          if (event.logicalKey == LogicalKeyboardKey.keyZ && !modifiers.isCtrlOrCmd) {
            widget.onToolModeChanged?.call(ToolMode.draw);
            return KeyEventResult.handled;
          }
          // X = Select tool (without Cmd/Ctrl - Cmd+X is cut)
          if (event.logicalKey == LogicalKeyboardKey.keyX && !modifiers.isCtrlOrCmd) {
            widget.onToolModeChanged?.call(ToolMode.select);
            return KeyEventResult.handled;
          }
          // C = Erase tool (without Cmd/Ctrl - Cmd+C is copy)
          if (event.logicalKey == LogicalKeyboardKey.keyC && !modifiers.isCtrlOrCmd) {
            widget.onToolModeChanged?.call(ToolMode.eraser);
            return KeyEventResult.handled;
          }
          // V = Duplicate tool (without Cmd/Ctrl - Cmd+V is paste)
          if (event.logicalKey == LogicalKeyboardKey.keyV && !modifiers.isCtrlOrCmd) {
            widget.onToolModeChanged?.call(ToolMode.duplicate);
            return KeyEventResult.handled;
          }
          // B = Slice tool
          if (event.logicalKey == LogicalKeyboardKey.keyB && !modifiers.isCtrlOrCmd) {
            widget.onToolModeChanged?.call(ToolMode.slice);
            return KeyEventResult.handled;
          }
        }

        // ============================================
        // Modifier key handling for temporary tool override
        // ============================================
        // Update tempToolMode when Alt/Cmd/Ctrl keys change
        if (event.logicalKey == LogicalKeyboardKey.alt ||
            event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight ||
            event.logicalKey == LogicalKeyboardKey.meta ||
            event.logicalKey == LogicalKeyboardKey.metaLeft ||
            event.logicalKey == LogicalKeyboardKey.metaRight ||
            event.logicalKey == LogicalKeyboardKey.control ||
            event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight) {
          updateTempToolMode();
        }

        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.standard,
          border: Border.all(color: context.colors.elevated),
        ),
        child: Column(
        children: [
          // Unified nav bar (loop region + bar numbers + zoom controls)
          NavBarWithZoom(
            scrollController: navBarScrollController,
            onZoomIn: () => setState(() {
              pixelsPerBeat = (pixelsPerBeat * 1.1).clamp(minZoom, maxZoom);
            }),
            onZoomOut: () => setState(() {
              pixelsPerBeat = (pixelsPerBeat / 1.1).clamp(minZoom, maxZoom);
            }),
            height: 24.0,
            child: UnifiedNavBar(
              config: UnifiedNavBarConfig(
                pixelsPerBeat: pixelsPerBeat,
                totalBeats: totalBeats.toDouble(),
                loopEnabled: widget.loopPlaybackEnabled,
                loopStart: widget.loopStartBeats,
                loopEnd: widget.loopEndBeats,
                playheadPosition: _calculatePlayheadBeat(),
              ),
              callbacks: UnifiedNavBarCallbacks(
                onHorizontalScroll: _handleNavBarScroll,
                onZoom: _handleNavBarZoom,
                onPlayheadSet: _handleNavBarPlayheadSet,
                onPlayheadDrag: _handleNavBarPlayheadSet, // Same handler for drag
                onLoopRegionChanged: widget.onLoopRegionChanged,
              ),
              scrollController: navBarScrollController,
              height: 24.0,
            ),
          ),

          // Main scrollable area (tracks)
          Expanded(
            child: Stack(
              children: [
                Listener(
                  onPointerSignal: handlePointerSignalSimple,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      // Sync nav bar scroll with main scroll
                      _syncNavBarScroll();
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalWidth,
                        child: Stack(
                          children: [
                            // Grid lines spanning entire area (scrollable + Master)
                            Positioned.fill(
                              child: _buildGrid(totalWidth, duration, double.infinity),
                            ),

                            // Content column: scrollable tracks + Master
                            Column(
                              children: [
                                // Scrollable tracks area
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: widget.verticalScrollController,
                                    scrollDirection: Axis.vertical,
                                    child: Listener(
                                      onPointerDown: (event) {
                                        // Eraser tool (toolbar OR Alt modifier) = start erasing on pointer down
                                        if (event.buttons == kPrimaryButton) {
                                          final modifiers = ModifierKeyState.current();
                                          final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;
                                          if (tool == ToolMode.eraser) {
                                            _startErasing(event.position);
                                          }
                                        }
                                      },
                                      onPointerMove: (event) {
                                        // Eraser tool (toolbar OR Alt modifier) = drag-to-erase
                                        if (event.buttons == kPrimaryButton) {
                                          final modifiers = ModifierKeyState.current();
                                          final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;
                                          if (tool == ToolMode.eraser) {
                                            if (!isErasing) {
                                              _startErasing(event.position);
                                            } else {
                                              _eraseClipsAt(event.position);
                                            }
                                          }
                                        }
                                      },
                                      onPointerUp: (event) {
                                        if (isErasing) {
                                          _stopErasing();
                                        }
                                      },
                                      child: Stack(
                                        children: [
                                          // Sized box to ensure proper height for scrolling
                                          SizedBox(
                                            height: totalTracksHeight,
                                            width: totalWidth,
                                          ),

                                          // Tracks (regular tracks only, Master is pinned below)
                                          _buildTracks(totalWidth, totalBeats.toDouble()),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Master track pinned at bottom (outside scroll area)
                                if (masterTrack.id != -1)
                                  _buildMasterTrack(totalWidth, masterTrack),
                              ],
                            ),

                            // Playhead line (vertical line spanning full height)
                            _buildPlayheadLine(),

                            // Box selection overlay
                            buildBoxSelectionOverlay(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildTracks(double width, double totalBeats) {
    // Only show empty state if audio engine is not initialized
    // Master track should always exist, so empty tracks means audio engine issue
    if (tracks.isEmpty && widget.audioEngine == null) {
      // Show empty state only if no audio engine
      return Container(
        height: 200,
        color: context.colors.standard,
        child: Center(
          child: Text(
            'Audio engine not initialized',
            style: TextStyle(color: context.colors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    // Separate regular tracks from master (Master is rendered outside scroll area)
    final regularTracks = tracks.where((t) => t.type != 'Master').toList();

    // Count audio and MIDI tracks for numbering
    int audioCount = 0;
    int midiCount = 0;

    return Column(
      mainAxisSize: MainAxisSize.min, // Don't expand, use actual content size
      children: [
        // Regular tracks (with automation lanes inside when visible)
        ...regularTracks.asMap().entries.map((entry) {
          final index = entry.key;
          final track = entry.value;

          // Increment counters for track numbering
          if (track.type.toLowerCase() == 'audio') {
            audioCount++;
          } else if (track.type.toLowerCase() == 'midi') {
            midiCount++;
          }

          // Use auto-detected color with override support, fallback to index-based
          final trackColor = widget.getTrackColor?.call(track.id, track.name, track.type)
              ?? TrackColors.getTrackColor(index);
          final currentAudioCount = track.type.toLowerCase() == 'audio' ? audioCount : 0;
          final currentMidiCount = track.type.toLowerCase() == 'midi' ? midiCount : 0;

          // Check if automation is visible for this track
          final showAutomation = widget.automationVisibleTrackId == track.id;

          return _buildTrack(
            width,
            track,
            trackColor,
            currentAudioCount,
            currentMidiCount,
            showAutomation: showAutomation,
            totalBeats: totalBeats,
          );
        }),

        // Empty space drop target - minimum height area for drops
        // Supports: instruments, VST3 plugins, audio files, AND drag-to-create
        SizedBox(
          height: 100, // Minimum drop target area height
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) {
              final startBeats = _calculateBeatPosition(details.localPosition);
              setState(() {
                isDraggingNewClip = true;
                newClipStartBeats = _snapToGrid(startBeats);
                newClipEndBeats = newClipStartBeats;
                newClipTrackId = null; // null = create new track
              });
            },
            onHorizontalDragUpdate: (details) {
              if (!isDraggingNewClip) return;
              final currentBeats = _calculateBeatPosition(details.localPosition);
              setState(() {
                newClipEndBeats = _snapToGrid(currentBeats);
              });
            },
            onHorizontalDragEnd: (details) {
              if (!isDraggingNewClip) return;

              // Calculate final start and duration (handle reverse drag)
              final startBeats = math.min(newClipStartBeats, newClipEndBeats);
              final endBeats = math.max(newClipStartBeats, newClipEndBeats);
              final durationBeats = endBeats - startBeats;

              // Minimum clip length is 1 bar (4 beats)
              if (durationBeats >= 4.0) {
                // Show track type selection popup
                _showTrackTypePopup(context, details.globalPosition, startBeats, durationBeats);
              }

              setState(() {
                isDraggingNewClip = false;
              });
            },
            onHorizontalDragCancel: () {
              setState(() {
                isDraggingNewClip = false;
              });
            },
            // Library panel AudioFileItem drag target (outermost)
            child: DragTarget<AudioFileItem>(
              onWillAcceptWithDetails: (details) => true,
              onAcceptWithDetails: (details) {
                widget.onAudioFileDroppedOnEmpty?.call(details.data.filePath);
              },
              builder: (context, candidateLibraryAudioFiles, rejectedLibraryAudioFiles) {
                final isLibraryAudioHovering = candidateLibraryAudioFiles.isNotEmpty;

                return PlatformDropTarget(
              onDragDone: (details) {
                // Handle audio file drops from Finder
                for (final file in details.files) {
                  final ext = file.path.split('.').last.toLowerCase();
                  if (['wav', 'mp3', 'flac', 'aif', 'aiff'].contains(ext)) {
                    widget.onAudioFileDroppedOnEmpty?.call(file.path);
                    return; // Only handle first valid audio file
                  }
                }
              },
              onDragEntered: (details) {
                setState(() {
                  isAudioFileDraggingOverEmpty = true;
                });
              },
              onDragExited: (details) {
                setState(() {
                  isAudioFileDraggingOverEmpty = false;
                });
              },
              child: DragTarget<Vst3Plugin>(
                onWillAcceptWithDetails: (details) {
                  return details.data.isInstrument; // Only accept VST3 instruments
                },
                onAcceptWithDetails: (details) {
                  widget.onVst3InstrumentDroppedOnEmpty?.call(details.data);
                },
                builder: (context, candidateVst3Plugins, rejectedVst3Plugins) {
                  final isVst3PluginHovering = candidateVst3Plugins.isNotEmpty;

                  return DragTarget<Instrument>(
                    onWillAcceptWithDetails: (details) {
                      return true; // Always accept instruments
                    },
                    onAcceptWithDetails: (details) {
                      widget.onInstrumentDroppedOnEmpty?.call(details.data);
                    },
                    builder: (context, candidateInstruments, rejectedInstruments) {
                      final isInstrumentHovering = candidateInstruments.isNotEmpty || isVst3PluginHovering;
                      final isAudioHovering = isAudioFileDraggingOverEmpty || isLibraryAudioHovering;
                      final isAnyHovering = isInstrumentHovering || isAudioHovering;

                      // Helper to truncate filename for display
                      String truncateFilename(String name, {int maxLength = 30}) {
                        if (name.length <= maxLength) return name;
                        return '${name.substring(0, maxLength - 3)}...';
                      }

                      // Determine label text
                      String dropLabel;
                      if (isLibraryAudioHovering && candidateLibraryAudioFiles.isNotEmpty) {
                        final fileName = truncateFilename(candidateLibraryAudioFiles.first!.name);
                        dropLabel = 'Drop to create new Audio track with $fileName';
                      } else if (isAudioFileDraggingOverEmpty) {
                        dropLabel = 'Drop to create new Audio track';
                      } else if (candidateVst3Plugins.isNotEmpty) {
                        dropLabel = 'Drop to create new MIDI track with ${candidateVst3Plugins.first?.name}';
                      } else if (candidateInstruments.isNotEmpty) {
                        dropLabel = 'Drop to create new MIDI track with ${candidateInstruments.first?.name ?? "instrument"}';
                      } else {
                        dropLabel = 'Drop to create new track';
                      }

                      return Stack(
                        children: [
                          // Drop target feedback
                          // ignore: use_decorated_box
                          Container(
                            decoration: isAnyHovering
                                ? BoxDecoration(
                                    color: context.colors.success.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: context.colors.success,
                                      width: 3,
                                      style: BorderStyle.solid,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  )
                                : null,
                            child: isAnyHovering
                                ? Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: context.colors.success,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.add_circle_outline,
                                            color: context.colors.textPrimary,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            dropLabel,
                                            style: TextStyle(
                                              color: context.colors.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.expand(),
                          ),
                          // Drag-to-create preview (for empty space)
                          if (isDraggingNewClip && newClipTrackId == null)
                            buildDragToCreatePreview(),
                        ],
                      );
                    },
                  );
                },
              ),
            );
              },
            ),
          ),
        ),
        // Master track is now rendered outside scroll area (in build method)
      ],
    );
  }

  Widget _buildGrid(double width, double duration, double height) {
    // When height is infinite, let the CustomPaint fill available space
    if (height == double.infinity) {
      return SizedBox(
        width: width,
        child: CustomPaint(
          painter: TimelineGridPainter(
            pixelsPerBeat: pixelsPerBeat,
            loopEnabled: widget.loopPlaybackEnabled,
            loopStart: widget.loopStartBeats,
            loopEnd: widget.loopEndBeats,
          ),
        ),
      );
    }
    return CustomPaint(
      size: Size(width, height),
      painter: TimelineGridPainter(
        pixelsPerBeat: pixelsPerBeat,
        loopEnabled: widget.loopPlaybackEnabled,
        loopStart: widget.loopStartBeats,
        loopEnd: widget.loopEndBeats,
      ),
    );
  }

  /// Build automation lane for a track in the timeline
  Widget _buildAutomationLane(int trackId, Color trackColor, double width, double totalBeats) {
    final lane = widget.getAutomationLane?.call(trackId);
    final automationHeight = widget.automationHeights[trackId] ?? 60.0;

    // Create empty lane if none provided
    final automationLane = lane ??
        TrackAutomationLane(
          trackId: trackId,
          parameter: AutomationParameter.volume,
          points: const [],
        );

    return TrackAutomationLaneWidget(
      lane: automationLane,
      pixelsPerBeat: pixelsPerBeat,
      totalBeats: totalBeats,
      laneHeight: automationHeight,
      horizontalScrollController: scrollController,
      trackColor: trackColor,
      toolMode: widget.toolMode,
      snapEnabled: !snapBypassActive,
      snapResolution: _getGridSnapResolution(),
      beatsPerBar: 4,
      onPointAdded: (point) => widget.onAutomationPointAdded?.call(trackId, point),
      onPointUpdated: (pointId, point) => widget.onAutomationPointUpdated?.call(trackId, pointId, point),
      onPointDeleted: (pointId) => widget.onAutomationPointDeleted?.call(trackId, pointId),
      onHeightChanged: (newHeight) => widget.onAutomationHeightChanged?.call(trackId, newHeight),
      onPreviewValue: (value) => widget.onAutomationPreviewValue?.call(trackId, value),
    );
  }

  Widget _buildTrack(
    double width,
    TimelineTrackData track,
    Color trackColor,
    int audioCount,
    int midiCount, {
    bool showAutomation = false,
    double totalBeats = 0.0,
  }) {
    // Find clips for this track
    final trackClips = clips.where((c) => c.trackId == track.id).toList();
    final trackMidiClips = widget.midiClips.where((c) => c.trackId == track.id).toList();
    final isHovered = dragHoveredTrackId == track.id;
    final isMidiTrack = track.type.toLowerCase() == 'midi';
    final clipHeight = widget.clipHeights[track.id] ?? 100.0;

    // Detect active recording region on this track (for visual masking)
    double? recStartBeat;
    double? recEndBeat;
    if (widget.isRecording) {
      final liveClip = trackMidiClips
          .where((c) => c.clipId == LiveRecordingNotifier.liveClipId)
          .firstOrNull;
      if (liveClip != null) {
        recStartBeat = liveClip.startTime;
        recEndBeat = liveClip.startTime + liveClip.duration;
      }
    }

    // Build the clip area widget
    final clipAreaWidget = DragTarget<AudioFileItem>(
      onWillAcceptWithDetails: (details) {
        // Only accept on Audio tracks, reject on MIDI tracks
        return !isMidiTrack;
      },
      onMove: (details) {
        // Library audio file drag - show preview with file info
        if (isMidiTrack) return;

        // Load waveform data if this is a new file being dragged
        if (previewWaveformPath != details.data.filePath) {
          previewWaveformPath = details.data.filePath;
          _loadWaveformForPreview(details.data.filePath);
        }

        // Convert global offset to local coordinates
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        final localPos = box?.globalToLocal(details.offset) ?? Offset.zero;
        final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
        final xInContent = localPos.dx + scrollOffset;
        final rawBeats = xInContent / pixelsPerBeat;

        // Snap to grid
        final snappedBeats = GridUtils.snapToGridRound(
          rawBeats,
          GridUtils.getTimelineGridResolution(pixelsPerBeat),
        );
        final startTime = snappedBeats.clamp(0.0, double.infinity) / (widget.tempo / 60.0);

        setState(() {
          dragHoveredTrackId = track.id;
          previewClip = PreviewClip(
            fileName: details.data.name,
            filePath: details.data.filePath,
            startTime: startTime,
            trackId: track.id,
            mousePosition: localPos,
            duration: previewWaveformDuration,
            waveformPeaks: previewWaveformPeaks,
          );
        });
      },
      onLeave: (data) {
        // Clear preview when leaving this track
        if (previewClip?.trackId == track.id) {
          setState(() {
            dragHoveredTrackId = null;
            previewClip = null;
          });
        }
      },
      onAcceptWithDetails: (details) {
        // Clear preview and waveform cache on drop
        _clearWaveformPreviewCache();
        setState(() {
          previewClip = null;
          dragHoveredTrackId = null;
        });

        // Calculate drop position with scroll offset
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        final localPos = box?.globalToLocal(details.offset) ?? Offset.zero;
        final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
        final xInContent = localPos.dx + scrollOffset;
        final rawBeats = xInContent / pixelsPerBeat;

        // Snap to grid
        final snappedBeats = GridUtils.snapToGridRound(
          rawBeats,
          GridUtils.getTimelineGridResolution(pixelsPerBeat),
        );

        widget.onAudioFileDroppedOnTrack?.call(
          track.id,
          details.data.filePath,
          snappedBeats.clamp(0.0, double.infinity),
        );
      },
      builder: (context, candidateAudioFiles, rejectedAudioFiles) {
        final isAudioFileRejected = rejectedAudioFiles.isNotEmpty;

        // Wrap with VST3Plugin drag target
        return DragTarget<Vst3Plugin>(
          onWillAcceptWithDetails: (details) {
            return isMidiTrack && details.data.isInstrument;
          },
          onAcceptWithDetails: (details) {
            widget.onVst3InstrumentDropped?.call(track.id, details.data);
          },
          builder: (context, candidateVst3Plugins, rejectedVst3Plugins) {
            // Note: candidateVst3Plugins/rejectedVst3Plugins available for visual feedback

            // Nest Instrument drag target inside
            return DragTarget<Instrument>(
              onWillAcceptWithDetails: (details) {
                return isMidiTrack;
              },
              onAcceptWithDetails: (details) {
                widget.onInstrumentDropped?.call(track.id, details.data);
              },
              builder: (context, candidateInstruments, rejectedInstruments) {
                // Note: candidateInstruments/rejectedInstruments and isVst3PluginHovering/Rejected
                // are available for visual feedback if needed in the future

            return PlatformDropTarget(
              onDragEntered: (details) {
                // Only show hover state if not MIDI track (for audio file drops)
                if (!isMidiTrack) {
                  setState(() {
                    dragHoveredTrackId = track.id;
                  });
                } else {
                  // Track platform drag over MIDI for visual feedback
                  setState(() {
                    platformDragOverMidiTrackId = track.id;
                  });
                }
              },
              onDragExited: (details) {
                setState(() {
                  dragHoveredTrackId = null;
                  previewClip = null;
                  platformDragOverMidiTrackId = null;
                });
              },
              onDragUpdated: (details) {
                // Only show preview on Audio tracks
                if (isMidiTrack) return;

                // Update preview position (Finder drag - no file info yet)
                final startTime = _calculateTimelinePosition(details.localPosition);

                setState(() {
                  previewClip = PreviewClip(
                    fileName: 'Audio File',
                    filePath: '', // Unknown until drop
                    startTime: startTime,
                    trackId: track.id,
                    mousePosition: details.localPosition,
                  );
                });
              },
              onDragDone: (details) async {
                // Reject drops on MIDI tracks
                if (isMidiTrack) return;
                await _handleFileDrop(details.files, track.id, details.localPosition);
              },
          child: GestureDetector(
        onTapDown: (details) {
          // Handle deselection on tap down (before drag can intercept)
          // But DON'T deselect if modifier keys are held (user might be Cmd+clicking to drag duplicate)
          final modifiers = ModifierKeyState.current();
          if (modifiers.isCtrlOrCmd || modifiers.isAltPressed) {
            // Don't clear selection when modifier keys are held - let clip gesture handle it
            return;
          }

          final beatPosition = _calculateBeatPosition(details.localPosition);
          final isOnClip = _isPositionOnClip(beatPosition, track.id, trackClips, trackMidiClips);

          // Click on empty space - deselect all clips (like piano roll)
          if (!isOnClip) {
            setState(() {
              selectedAudioClipIds.clear();
              selectedMidiClipIds.clear();
              selectedAudioClipId = null;
            });
            widget.onMidiClipSelected?.call(null, null);
            widget.onAudioClipSelected?.call(null, null);
          }
        },
        onTapUp: (details) {
          // Draw tool: single click on empty space just deselects (handled in onTapDown)
          // Use click+drag to create new clips, or double-click for quick creation
          // Note: Duplicate tool only works via drag, not click (Ableton-style)
        },
        onDoubleTapDown: isMidiTrack
            ? (details) {
                // Double-click: create a default MIDI clip at this position (spec v2.0: 1 bar)
                final beatPosition = _calculateBeatPosition(details.localPosition);
                final isOnClip = _isPositionOnClip(beatPosition, track.id, trackClips, trackMidiClips);

                if (!isOnClip) {
                  // Create a 1-bar clip at the clicked position (snapped to grid)
                  final startBeats = _snapToGrid(beatPosition);
                  const durationBeats = 4.0; // 1 bar (spec v2.0)
                  widget.onCreateClipOnTrack?.call(track.id, startBeats, durationBeats);
                }
              }
            : null,
        onHorizontalDragStart: (details) {
          final tool = effectiveToolMode;
          final beatPosition = _calculateBeatPosition(details.localPosition);
          final isOnClip = _isPositionOnClip(beatPosition, track.id, trackClips, trackMidiClips);

          // SELECT TOOL: Start box selection on empty space
          if (tool == ToolMode.select && !isOnClip) {
            // Calculate this track's Y offset within the content area
            // (localPosition.dy is relative to this track widget, not the whole timeline)
            final regularTracks = tracks.where((t) => t.type != 'Master').toList();
            final trackIndex = regularTracks.indexWhere((t) => t.id == track.id);
            double trackYOffset = 0.0;
            for (int i = 0; i < trackIndex; i++) {
              trackYOffset += widget.clipHeights[regularTracks[i].id] ?? 100.0;
              // Include automation height if visible for this track
              if (widget.automationVisibleTrackId == regularTracks[i].id) {
                trackYOffset += widget.automationHeights[regularTracks[i].id] ?? 60.0;
              }
            }

            final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
            final verticalOffset = widget.verticalScrollController?.hasClients == true
                ? widget.verticalScrollController!.offset
                : 0.0;

            // Calculate visible Y position (for overlay rendering)
            // localPosition.dy is relative to the track, trackYOffset is the track's position in content
            // Subtract verticalOffset to get visible position
            final visibleY = details.localPosition.dy + trackYOffset - verticalOffset;

            // Capture shift state at drag START for proper additive behavior
            final shiftHeld = ModifierKeyState.current().isShiftPressed;

            setState(() {
              isBoxSelecting = true;
              // Store position in VISIBLE coordinates (for overlay rendering)
              // Selection logic will convert back to content coordinates
              boxSelectionStart = Offset(
                details.localPosition.dx + scrollOffset,
                visibleY,
              );
              boxSelectionEnd = boxSelectionStart;
              boxSelectionScrollOffset = scrollOffset;
              boxSelectionTrackYOffset = trackYOffset;
              // Capture shift state and initial selection for proper additive behavior
              boxSelectionShiftHeld = shiftHeld;
              boxSelectionInitialMidiIds = shiftHeld ? Set.from(selectedMidiClipIds) : {};
              boxSelectionInitialAudioIds = shiftHeld ? Set.from(selectedAudioClipIds) : {};
            });
            return;
          }

          // DRAW TOOL: Drag-to-create on MIDI tracks
          if (tool == ToolMode.draw && !isOnClip && isMidiTrack) {
            setState(() {
              isDraggingNewClip = true;
              newClipStartBeats = _snapToGrid(beatPosition);
              newClipEndBeats = newClipStartBeats;
              newClipTrackId = track.id;
            });
          }
        },
        onHorizontalDragUpdate: (details) {
          // Box selection update
          if (isBoxSelecting) {
            final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
            final verticalOffset = widget.verticalScrollController?.hasClients == true
                ? widget.verticalScrollController!.offset
                : 0.0;

            // Calculate visible Y position (for overlay rendering)
            final visibleY = details.localPosition.dy + boxSelectionTrackYOffset - verticalOffset;

            setState(() {
              // Update end position in VISIBLE coordinates (for overlay rendering)
              boxSelectionEnd = Offset(
                details.localPosition.dx + scrollOffset,
                visibleY,
              );
            });
            // Live selection update - select clips within the box
            _updateBoxSelection();
            return;
          }

          // Drag-to-create update
          if (isDraggingNewClip && newClipTrackId == track.id) {
            final currentBeats = _calculateBeatPosition(details.localPosition);
            setState(() {
              newClipEndBeats = _snapToGrid(currentBeats);
            });
          }
        },
        onHorizontalDragEnd: (details) {
          // Box selection end
          if (isBoxSelecting) {
            // If nothing was selected, notify parent to deselect current clip
            if (selectedMidiClipIds.isEmpty && selectedAudioClipIds.isEmpty) {
              widget.onMidiClipSelected?.call(null, null);
              widget.onAudioClipSelected?.call(null, null);
            }
            setState(() {
              isBoxSelecting = false;
              boxSelectionStart = null;
              boxSelectionEnd = null;
            });
            return;
          }

          // Drag-to-create end
          if (isDraggingNewClip && newClipTrackId == track.id) {
            // Calculate final start and duration (handle reverse drag)
            final startBeats = math.min(newClipStartBeats, newClipEndBeats);
            final endBeats = math.max(newClipStartBeats, newClipEndBeats);
            final durationBeats = endBeats - startBeats;

            // Minimum clip length is 1 bar (4 beats)
            if (durationBeats >= 4.0) {
              widget.onCreateClipOnTrack?.call(track.id, startBeats, durationBeats);
            }

            setState(() {
              isDraggingNewClip = false;
              newClipTrackId = null;
            });
          }
        },
        onHorizontalDragCancel: () {
          if (newClipTrackId == track.id) {
            setState(() {
              isDraggingNewClip = false;
              newClipTrackId = null;
            });
          }
        },
        onSecondaryTapUp: (details) {
          // Right-click on empty area: show context menu
          final beatPosition = _calculateBeatPosition(details.localPosition);
          final isOnClip = _isPositionOnClip(beatPosition, track.id, trackClips, trackMidiClips);
          if (!isOnClip) {
            _showEmptyAreaContextMenu(details.globalPosition, details.localPosition, track, isMidiTrack);
          }
        },
        child: Container(
        height: widget.clipHeights[track.id] ?? 100.0,
        decoration: BoxDecoration(
          // Transparent background to show grid through
          color: isHovered
              ? context.colors.elevated.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: context.colors.hover,
              width: 1,
            ),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // Grid pattern
            CustomPaint(
              painter: GridPatternPainter(),
            ),

            // Render audio clips for this track (hide clips being erased)
            ...trackClips
                .where((clip) => !erasedAudioClipIds.contains(clip.clipId))
                .map((clip) => _buildClip(clip, trackColor, widget.clipHeights[track.id] ?? 100.0, recStartBeat: recStartBeat, recEndBeat: recEndBeat)),

            // Ghost preview for audio clip copy drag (all selected clips)
            ...trackClips
                .where((clip) => isCopyDrag && draggingClipId != null && selectedAudioClipIds.contains(clip.clipId))
                .expand((clip) => buildAudioCopyDragPreviews(clip, trackColor, widget.clipHeights[track.id] ?? 100.0)),

            // Ghost preview for audio clips during MIDI drag (cross-type)
            ...trackClips
                .where((clip) => isCopyDrag && draggingMidiClipId != null && selectedAudioClipIds.contains(clip.clipId))
                .expand((clip) => buildAudioCopyDragPreviewsForMidiDrag(clip, trackColor, widget.clipHeights[track.id] ?? 100.0)),

            // Render MIDI clips for this track (hide clips being erased)
            ...trackMidiClips
                .where((midiClip) => !erasedMidiClipIds.contains(midiClip.clipId))
                .map((midiClip) => _buildMidiClip(
                  midiClip,
                  trackColor,
                  widget.clipHeights[track.id] ?? 100.0,
                  recStartBeat: recStartBeat,
                  recEndBeat: recEndBeat,
                )),

            // Ghost preview for MIDI clip copy drag (all selected clips)
            ...trackMidiClips
                .where((midiClip) => isCopyDrag && draggingMidiClipId != null && selectedMidiClipIds.contains(midiClip.clipId))
                .expand((midiClip) => buildCopyDragPreviews(midiClip, trackColor, widget.clipHeights[track.id] ?? 100.0)),

            // Ghost preview for MIDI clips during audio drag (cross-type)
            ...trackMidiClips
                .where((midiClip) => isCopyDrag && draggingClipId != null && selectedMidiClipIds.contains(midiClip.clipId))
                .expand((midiClip) => buildMidiCopyDragPreviewsForAudioDrag(midiClip, trackColor, widget.clipHeights[track.id] ?? 100.0)),

            // Show preview clip if hovering over this track
            if (previewClip != null && previewClip!.trackId == track.id)
              buildPreviewClip(previewClip!),

            // Drag-to-create preview for this track
            if (isDraggingNewClip && newClipTrackId == track.id)
              buildDragToCreatePreviewOnTrack(trackColor, widget.clipHeights[track.id] ?? 100.0),

            // Red rejection overlay when dragging audio onto MIDI track
            if (isAudioFileRejected || platformDragOverMidiTrackId == track.id)
              Positioned.fill(
                child: Container(
                  color: Colors.red.withValues(alpha: 0.15),
                  child: Center(
                    child: Icon(
                      Icons.block,
                      color: Colors.red.withValues(alpha: 0.6),
                      size: 32,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
            );
          },
        );
          },
        );
      },
    );

    // If automation is not visible, return just the clip area
    if (!showAutomation) {
      return clipAreaWidget;
    }

    // When automation is visible, wrap clip and automation in a Column
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Clip area with resize handle at bottom
        Stack(
          children: [
            clipAreaWidget,
            // Resize handle between clip and automation
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    final newHeight = (clipHeight + details.delta.dy).clamp(40.0, 400.0);
                    widget.onClipHeightChanged?.call(track.id, newHeight);
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
        // Automation lane (includes its own resize handle at bottom)
        _buildAutomationLane(track.id, trackColor, width, totalBeats),
      ],
    );
  }

  Widget _buildMasterTrack(double width, TimelineTrackData track) {
    final masterColor = context.colors.accent;
    const headerHeight = 18.0;

    // Match the MIDI/Audio clip style - spans full width like a clip
    // Content area is transparent so grid shows through from behind
    return Container(
      width: width,
      height: widget.masterTrackHeight,
      margin: const EdgeInsets.only(left: 2, right: 2, top: 1, bottom: 1),
      decoration: BoxDecoration(
        // Rounded corners like clips
        borderRadius: BorderRadius.circular(4),
        // Border matching clip style (1px when not selected)
        border: Border.all(
          color: masterColor,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3), // Inside border radius
        child: Column(
          children: [
            // Header bar (like clip header)
            Container(
              height: headerHeight,
              color: masterColor,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRect(
                child: Row(
                  children: [
                    // Icon (headphones)
                    const Text('🎧', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    // "Master" text (white)
                    Text(
                      'Master',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Content area - transparent so grid shows through
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  /// Wraps [child] in a [ClipPath] that hides the recording region,
  /// or returns [child] unmodified if no masking is needed.
  Widget _applyRecordingMask({
    required Widget child,
    required double clipX,
    required double clipWidth,
    required double pixelsPerUnit,
    double? recStart,
    double? recEnd,
    bool exclude = false,
  }) {
    if (exclude || recStart == null || recEnd == null) return child;
    final recStartPx = recStart * pixelsPerUnit - clipX;
    final recEndPx = recEnd * pixelsPerUnit - clipX;
    if (recStartPx >= clipWidth || recEndPx <= 0) return child;
    return ClipPath(
      clipper: RecordingMaskClipper(
        excludeStartPx: recStartPx,
        excludeEndPx: recEndPx,
      ),
      child: child,
    );
  }

  Widget _buildClip(ClipData clip, Color trackColor, double trackHeight, {double? recStartBeat, double? recEndBeat}) {
    // Calculate clip width based on warp state:
    // - Warp ON: clip syncs to project tempo, so it covers a fixed number of beats
    // - Warp OFF: clip is fixed-length in seconds, so width changes with tempo
    final double clipWidth;
    if (clip.editData?.syncEnabled ?? false) {
      // Warp ON: use beat-based width (fixed visual size regardless of tempo)
      final beatsInClip = clip.duration * ((clip.editData?.bpm ?? 120.0) / 60.0);
      clipWidth = beatsInClip * pixelsPerBeat;
    } else {
      // Warp OFF: use time-based width (stretches with tempo)
      clipWidth = clip.duration * pixelsPerSecond;
    }
    // Use dragged position if this clip is being dragged OR is part of the selection being dragged
    // BUT NOT for copy drags - the original stays in place, only the ghost moves
    double displayStartTime;

    // Check if being dragged via audio clip drag
    final isBeingDraggedViaAudio = draggingClipId != null &&
        (draggingClipId == clip.clipId || selectedAudioClipIds.contains(clip.clipId)) &&
        !isCopyDrag;

    // Check if being dragged via MIDI clip drag (cross-type multi-track selection)
    final isBeingDraggedViaMidi = draggingMidiClipId != null &&
        selectedAudioClipIds.contains(clip.clipId) &&
        !isCopyDrag;

    if (isBeingDraggedViaAudio) {
      // Calculate delta in seconds from audio drag
      final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

      // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
      final beatsPerSecond = widget.tempo / 60.0;
      final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
      final snappedBeats = _snapToGrid(rawBeats);
      final snappedNewStartTime = snappedBeats / beatsPerSecond;
      final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

      // Apply the same delta to this clip
      displayStartTime = (clip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
    } else if (isBeingDraggedViaMidi) {
      // Calculate delta from MIDI drag (beats) and convert to seconds
      final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

      // Snap the delta based on the MIDI drag position
      var snappedDeltaBeats = dragDeltaBeats;
      if (!snapBypassActive) {
        final snapResolution = _getGridSnapResolution();
        final draggedClipNewPos = midiDragStartTime + dragDeltaBeats;
        final snappedPos = (draggedClipNewPos / snapResolution).round() * snapResolution;
        snappedDeltaBeats = snappedPos - midiDragStartTime;
      }

      // Convert beats delta to seconds delta
      final beatsPerSecond = widget.tempo / 60.0;
      final snappedDeltaSeconds = snappedDeltaBeats / beatsPerSecond;

      // Apply the same delta to this clip
      displayStartTime = (clip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
    } else {
      displayStartTime = clip.startTime;
    }
    final clipX = displayStartTime.clamp(0.0, double.infinity) * pixelsPerSecond;
    final isDragging = draggingClipId == clip.clipId;
    final isSelected = selectedAudioClipIds.contains(clip.clipId);

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 3.0; // Track height minus padding

    // Check if this clip has split preview active
    final hasSplitPreview = splitPreviewAudioClipId == clip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (splitPreviewBeatPosition / (clip.duration * (widget.tempo / 60.0))) * clipWidth
        : 0.0;

    return Positioned(
      key: ValueKey('audio_clip_${clip.clipId}'),
      left: clipX,
      top: 0,
      child: _applyRecordingMask(
        clipX: clipX,
        clipWidth: clipWidth,
        pixelsPerUnit: pixelsPerBeat,
        recStart: recStartBeat,
        recEnd: recEndBeat,
        child: GestureDetector(
        onTapDown: (details) {
          // Check modifier keys directly at click time (more reliable than cached tempToolMode)
          final modifiers = ModifierKeyState.current();
          final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;

          // IMPORTANT: Capture copy modifier state at tap down
          // This is needed because by the time onHorizontalDragStart fires,
          // the modifier key state may have changed (widget rebuild, etc.)
          audioPointerDownWasCopyModifier = modifiers.isCtrlOrCmd || tool == ToolMode.duplicate;

          // Eraser tool: start batched erasing (supports drag-to-delete like piano roll)
          if (tool == ToolMode.eraser) {
            // Convert local click position to global for eraser system
            final RenderBox? box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              final globalPos = box.localToGlobal(details.localPosition);
              _startErasing(globalPos);
            }
            return;
          }

          // Slice tool: split at click position
          if (tool == ToolMode.slice) {
            // Calculate split position from click (audio clips use seconds)
            final clickXInClip = details.localPosition.dx;
            final clickSecondsInClip = clickXInClip / pixelsPerSecond;
            if (clickSecondsInClip > 0 && clickSecondsInClip < clip.duration) {
              // Convert to beats for split preview
              final beatsPerSecond = widget.tempo / 60.0;
              setState(() {
                splitPreviewAudioClipId = clip.clipId;
                splitPreviewBeatPosition = clickSecondsInClip * beatsPerSecond;
              });
              _splitAudioClipAtPreview(clip);
            }
            return;
          }

          // DRAW, SELECT, or DUPLICATE TOOL: Handle selection on tap down
          // (Duplicate only creates copy on drag-end, not click)
          final wasAlreadySelected = selectedAudioClipIds.contains(clip.clipId);

          // If clicking on already-selected clip without Shift, defer single-selection to tap-up
          // (allows multi-drag if user drags instead of clicking)
          if (wasAlreadySelected && !modifiers.isShiftPressed) {
            pendingAudioClipTapSelection = clip.clipId;
          } else {
            pendingAudioClipTapSelection = null;
            selectAudioClipMulti(
              clip.clipId,
              addToSelection: false,
              toggleSelection: modifiers.isShiftPressed,
            );
          }
          // Deselect any MIDI clip (notify parent)
          widget.onMidiClipSelected?.call(null, null);
        },
        onTapUp: (details) {
          // Stop erasing if in eraser mode (single click delete)
          if (isErasing) {
            _stopErasing();
            return;
          }

          // If we had a pending tap selection (clicked on already-selected clip),
          // now reduce to single selection since no drag occurred
          if (pendingAudioClipTapSelection == clip.clipId) {
            selectAudioClipMulti(clip.clipId, forceSelect: true);
          }
          pendingAudioClipTapSelection = null;
        },
        onSecondaryTapDown: (details) {
          // Right-click: show context menu
          _showAudioClipContextMenu(details.globalPosition, clip);
        },
        onHorizontalDragStart: (details) {
          // Clear pending tap selection - user is dragging, not clicking
          pendingAudioClipTapSelection = null;

          // Check modifier keys at drag start
          final modifiers = ModifierKeyState.current();
          final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;

          // Eraser mode: block all drag operations (erasing handled by onTapDown + onHorizontalDragUpdate)
          if (tool == ToolMode.eraser) return;

          // Slice mode: block drag (slicing is handled by onTapDown)
          if (tool == ToolMode.slice) return;

          // Check copy modifier: use captured state from tap down, OR check current state
          // (onTapDown might not fire if drag starts immediately)
          final isDuplicate = audioPointerDownWasCopyModifier ||
              modifiers.isCtrlOrCmd ||
              tool == ToolMode.duplicate;

          // Check if this clip is in the multi-selection
          final isInMultiSelection = selectedAudioClipIds.contains(clip.clipId);

          // Capture the clips to drag/copy at drag START (before any state changes)
          final Set<int> clipIdsToProcess;
          if (isInMultiSelection) {
            // Dragging a selected clip - process all selected clips
            clipIdsToProcess = Set.from(selectedAudioClipIds);
          } else {
            // Dragging an unselected clip - only process this clip
            clipIdsToProcess = {clip.clipId};
          }

          setState(() {
            // Update audio selection to match what we're processing
            // NOTE: Don't clear MIDI selection - we want to drag both types together
            selectedAudioClipIds.clear();
            selectedAudioClipIds.addAll(clipIdsToProcess);

            selectedAudioClipId = clip.clipId;
            draggingClipId = clip.clipId;
            dragStartTime = clip.startTime;
            dragStartX = details.globalPosition.dx;
            dragCurrentX = details.globalPosition.dx;
            isCopyDrag = isDuplicate; // Duplicate tool or Cmd/Ctrl = copy drag
          });
        },
        onHorizontalDragUpdate: (details) {
          // Continue erasing if in eraser mode
          if (isErasing) {
            _eraseClipsAt(details.globalPosition);
            return;
          }

          // Skip in eraser/slice mode (Draw mode allows moving)
          final tool = effectiveToolMode;
          if (tool == ToolMode.eraser || tool == ToolMode.slice) return;

          setState(() {
            dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragEnd: (details) async {
          // Stop erasing if in eraser mode
          if (isErasing) {
            _stopErasing();
            return;
          }

          if (draggingClipId == null) return;

          // Calculate delta in seconds
          final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

          // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
          final beatsPerSecond = widget.tempo / 60.0;
          final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
          final snappedBeats = _snapToGrid(rawBeats);
          final snappedNewStartTime = snappedBeats / beatsPerSecond;
          final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

          if (isCopyDrag) {
            // Get all selected clips BEFORE clearing selection
            final audioClipsToCopy = clips
                .where((c) => selectedAudioClipIds.contains(c.clipId))
                .toList();
            final midiClipsToCopy = widget.midiClips
                .where((c) => selectedMidiClipIds.contains(c.clipId))
                .toList();

            // Convert delta to beats for MIDI clips
            final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

            // Clear internal selection - we'll select new clips after duplication
            selectedAudioClipIds.clear();
            selectedMidiClipIds.clear();

            // Duplicate ALL selected audio clips with same offset delta
            for (final selectedClip in audioClipsToCopy) {
              final newStartTime = (selectedClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
              _duplicateAudioClip(selectedClip, atPosition: newStartTime);
            }

            // Duplicate ALL selected MIDI clips with same offset delta (in beats)
            for (final midiClip in midiClipsToCopy) {
              final newStartBeats = (midiClip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
              widget.onMidiClipCopied?.call(midiClip, newStartBeats);
            }

            // After all copies are made, select the new clips
            // Use addPostFrameCallback to wait for the widget tree to rebuild
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Store original clip IDs for exclusion
              final originalAudioClipIds = audioClipsToCopy.map((c) => c.clipId).toSet();
              final originalMidiClipIds = midiClipsToCopy.map((c) => c.clipId).toSet();

              setState(() {
                // Select new audio clips
                for (final originalClip in audioClipsToCopy) {
                  final expectedNewStart = (originalClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
                  // Find a clip at this position that wasn't an original
                  final newClip = clips.where((c) =>
                    (c.startTime - expectedNewStart).abs() < 0.01 && // Slightly larger tolerance
                    c.trackId == originalClip.trackId &&
                    !originalAudioClipIds.contains(c.clipId)
                  ).firstOrNull;
                  if (newClip != null) {
                    selectedAudioClipIds.add(newClip.clipId);
                  }
                }

                // Select new MIDI clips
                for (final originalClip in midiClipsToCopy) {
                  final expectedNewStart = (originalClip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
                  // Find a clip at this position that wasn't an original
                  final newClip = widget.midiClips.where((c) =>
                    (c.startTime - expectedNewStart).abs() < 0.01 &&
                    c.trackId == originalClip.trackId &&
                    !originalMidiClipIds.contains(c.clipId)
                  ).firstOrNull;
                  if (newClip != null) {
                    selectedMidiClipIds.add(newClip.clipId);
                  }
                }
              });
            });
          } else {
            // Move: update ALL selected clips by the same delta

            // Convert delta to beats for MIDI clips
            final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

            // Move audio clips
            final selectedAudioClips = clips.where((c) => selectedAudioClipIds.contains(c.clipId)).toList();

            for (final selectedClip in selectedAudioClips) {
              final newStartTime = (selectedClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);

              // Only create command if position actually changed
              if ((newStartTime - selectedClip.startTime).abs() > 0.001) {
                final command = MoveAudioClipCommand(
                  trackId: selectedClip.trackId,
                  clipId: selectedClip.clipId,
                  clipName: selectedClip.fileName,
                  newStartTime: newStartTime,
                  oldStartTime: selectedClip.startTime,
                );
                await UndoRedoManager().execute(command);
              }

              // Update local state
              setState(() {
                final index = clips.indexWhere((c) => c.clipId == selectedClip.clipId);
                if (index >= 0) {
                  clips[index] = clips[index].copyWith(startTime: newStartTime);
                }
              });
            }

            // Move MIDI clips
            final selectedMidiClips = widget.midiClips.where((c) => selectedMidiClipIds.contains(c.clipId)).toList();

            for (final midiClip in selectedMidiClips) {
              final newStartBeats = (midiClip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
              final newStartTimeSeconds = newStartBeats / beatsPerSecond;
              final rustClipId = widget.getRustClipId?.call(midiClip.clipId) ?? midiClip.clipId;
              widget.audioEngine?.setClipStartTime(midiClip.trackId, rustClipId, newStartTimeSeconds);
              final updatedClip = midiClip.copyWith(startTime: newStartBeats);
              widget.onMidiClipUpdated?.call(updatedClip);
            }

            // Force UI refresh after parent processes MIDI updates
            if (selectedMidiClips.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
          }

          setState(() {
            draggingClipId = null;
            isCopyDrag = false;
          });
        },
        child: MouseRegion(
          cursor: trimmingAudioClipId == clip.clipId
              ? (isTrimmingLeftEdge ? SystemMouseCursors.resizeLeft : SystemMouseCursors.resizeRight)
              : _getCursorForTool(effectiveToolMode, isOverClip: true),
          onHover: (event) {
            // Update temp tool mode on hover (in case modifier keys changed)
            updateTempToolMode();
          },
          onExit: (_) {
            if (splitPreviewAudioClipId == clip.clipId) {
              _clearSplitPreview();
            }
          },
          child: Builder(
            builder: (context) {
              // Calculate loop boundary positions for audio clips (like MIDI clips)
              // loopLength is in seconds, need to calculate loop boundary X positions in pixels
              final loopWidthPixels = clip.loopLength * pixelsPerSecond;
              final isLooped = clip.canRepeat && clip.duration > clip.loopLength;
              final loopBoundaryPositions = isLooped
                  ? _calculateLoopBoundaryPositions(
                      loopWidthPixels, // loopLength in pixels
                      clipWidth, // clipDuration in pixels
                      clipWidth,
                    )
                  : <double>[];

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Main clip container with notched border (like MIDI clips)
                  ClipPath(
                    clipper: ClipPathClipper(
                      cornerRadius: 4,
                      notchRadius: 4,
                      loopBoundaryXPositions: loopBoundaryPositions,
                    ),
                    child: Container(
                      width: clipWidth,
                      height: totalHeight,
                      child: Column(
                        children: [
                          // Header with track color (simplified when clip is too narrow)
                          Container(
                            height: headerHeight,
                            decoration: BoxDecoration(
                              color: trackColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                            padding: clipWidth > 30 ? const EdgeInsets.symmetric(horizontal: 6) : null,
                            child: clipWidth > 30
                                ? Row(
                                    children: [
                                      Icon(
                                        Icons.audiotrack,
                                        size: 12,
                                        color: context.colors.textPrimary,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          clip.fileName,
                                          style: TextStyle(
                                            color: context.colors.textPrimary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                : null, // Just show colored bar for very narrow clips
                          ),
                          // Content area with waveform (transparent background)
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(3),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Calculate visual gain from clip's editData
                                  final clipGainDb = clip.editData?.gainDb ?? 0.0;
                                  final clipVisualGain = clipGainDb > -70
                                      ? math.pow(10, clipGainDb / 20).toDouble()
                                      : 0.0;
                                  // Calculate visible duration for non-looped clips
                                  // For looped: each iteration shows full loopLength
                                  // For non-looped: show only clip.duration (may be trimmed)
                                  final visibleDuration = isLooped ? clip.loopLength : clip.duration;
                                  return CustomPaint(
                                    size: Size(constraints.maxWidth, constraints.maxHeight),
                                    painter: WaveformPainter(
                                      peaks: clip.waveformPeaks,
                                      color: TrackColors.getLighterShade(trackColor),
                                      visualGain: clipVisualGain,
                                      loopWidth: isLooped ? loopWidthPixels : null,
                                      contentDuration: clip.loopLength, // Full content duration
                                      startOffset: clip.offset, // Left trim offset
                                      visibleDuration: visibleDuration, // How much is actually visible
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Border with integrated notches (like MIDI clips)
                  CustomPaint(
                    size: Size(clipWidth, totalHeight),
                    painter: ClipBorderPainter(
                      borderColor: isSelected
                          ? context.colors.textPrimary
                          : trackColor.withValues(alpha: 0.7),
                      trackColor: trackColor,
                      headerHeight: headerHeight,
                      borderWidth: isDragging || isSelected ? 2 : 1,
                      cornerRadius: 4,
                      loopBoundaryXPositions: loopBoundaryPositions,
                    ),
                  ),
              // Left edge trim handle
              Positioned(
                left: 0,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() {
                      trimmingAudioClipId = clip.clipId;
                      isTrimmingLeftEdge = true;
                      audioTrimStartTime = clip.startTime;
                      audioTrimStartDuration = clip.duration;
                      audioTrimStartOffset = clip.offset;
                      audioTrimStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (trimmingAudioClipId != clip.clipId || !isTrimmingLeftEdge) return;
                    final deltaX = details.globalPosition.dx - audioTrimStartX;
                    final deltaSeconds = deltaX / pixelsPerSecond;

                    // Calculate new start time and duration
                    var newStartTime = audioTrimStartTime + deltaSeconds;
                    var newDuration = audioTrimStartDuration - deltaSeconds;
                    var newOffset = audioTrimStartOffset + deltaSeconds;

                    // Clamp to valid bounds
                    double minStartTime = 0.0;

                    // Overlap blocking: clamp to nearest clip on the left
                    final leftSiblings = clips.where(
                        (c) => c.trackId == clip.trackId && c.clipId != clip.clipId);
                    for (final sibling in leftSiblings) {
                      final siblingEnd = sibling.startTime + sibling.duration;
                      if (siblingEnd <= audioTrimStartTime + audioTrimStartDuration &&
                          siblingEnd > minStartTime) {
                        minStartTime = siblingEnd;
                      }
                    }

                    newStartTime = newStartTime.clamp(minStartTime, audioTrimStartTime + audioTrimStartDuration - 0.1);
                    newDuration = (audioTrimStartTime + audioTrimStartDuration) - newStartTime;
                    newDuration = newDuration.clamp(0.1, double.infinity);
                    newOffset = newOffset.clamp(0.0, double.infinity);

                    setState(() {
                      final index = clips.indexWhere((c) => c.clipId == clip.clipId);
                      if (index >= 0) {
                        clips[index] = clips[index].copyWith(
                          startTime: newStartTime,
                          duration: newDuration,
                          offset: newOffset,
                        );
                      }
                    });
                  },
                  onHorizontalDragEnd: (details) async {
                    // Get the trimmed clip values
                    final trimmedClip = clips.firstWhere((c) => c.clipId == clip.clipId, orElse: () => clip);

                    // Only create command if values actually changed
                    if ((trimmedClip.startTime - audioTrimStartTime).abs() > 0.001 ||
                        (trimmedClip.duration - audioTrimStartDuration).abs() > 0.001) {
                      final command = ResizeAudioClipCommand(
                        trackId: trimmedClip.trackId,
                        clipId: trimmedClip.clipId,
                        clipName: trimmedClip.fileName,
                        oldDuration: audioTrimStartDuration,
                        newDuration: trimmedClip.duration,
                        oldOffset: audioTrimStartOffset,
                        newOffset: trimmedClip.offset,
                        oldStartTime: audioTrimStartTime,
                        newStartTime: trimmedClip.startTime,
                        onClipResized: (clipId, duration, offset, startTime) {
                          setState(() {
                            final index = clips.indexWhere((c) => c.clipId == clipId);
                            if (index >= 0) {
                              clips[index] = clips[index].copyWith(
                                duration: duration,
                                offset: offset,
                                startTime: startTime,
                              );
                            }
                          });
                        },
                      );
                      await UndoRedoManager().execute(command);
                    }

                    setState(() {
                      trimmingAudioClipId = null;
                      isTrimmingLeftEdge = false;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeft,
                    child: Container(
                      width: 8,
                      height: totalHeight,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
              // Right edge trim handle
              // Audio clips: canRepeat=false limits to loopLength, canRepeat=true allows looping
              Positioned(
                right: 0,
                top: 0,
                child: Builder(
                  builder: (context) {
                    // Determine if clip can be extended (looping enabled)
                    final canExtend = clip.canRepeat;
                    // Check if we're at or beyond the loop limit
                    final atLoopLimit = !canExtend && clip.duration >= clip.loopLength - 0.001;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) {
                        setState(() {
                          trimmingAudioClipId = clip.clipId;
                          isTrimmingLeftEdge = false;
                          audioTrimStartDuration = clip.duration;
                          audioTrimStartX = details.globalPosition.dx;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (trimmingAudioClipId != clip.clipId || isTrimmingLeftEdge) return;
                        final deltaX = details.globalPosition.dx - audioTrimStartX;
                        final deltaSeconds = deltaX / pixelsPerSecond;

                        // Calculate new duration
                        var newDuration = audioTrimStartDuration + deltaSeconds;

                        // Audio clips: limit based on canRepeat
                        if (clip.canRepeat) {
                          // Loop enabled: can extend beyond loopLength (content tiles)
                          newDuration = newDuration.clamp(0.1, double.infinity);
                        } else {
                          // Loop disabled: cannot extend beyond loopLength
                          newDuration = newDuration.clamp(0.1, clip.loopLength);
                        }

                        // Overlap blocking: clamp to nearest clip on the right
                        final siblingClips = clips.where(
                            (c) => c.trackId == clip.trackId && c.clipId != clip.clipId);
                        for (final sibling in siblingClips) {
                          if (sibling.startTime > clip.startTime) {
                            final maxDuration = sibling.startTime - clip.startTime;
                            if (newDuration > maxDuration) {
                              newDuration = maxDuration;
                            }
                          }
                        }

                        setState(() {
                          final index = clips.indexWhere((c) => c.clipId == clip.clipId);
                          if (index >= 0) {
                            clips[index] = clips[index].copyWith(duration: newDuration);
                          }
                        });
                      },
                      onHorizontalDragEnd: (details) async {
                        // Get the trimmed clip values
                        final trimmedClip = clips.firstWhere((c) => c.clipId == clip.clipId, orElse: () => clip);

                        // Only create command if duration actually changed
                        if ((trimmedClip.duration - audioTrimStartDuration).abs() > 0.001) {
                          final command = ResizeAudioClipCommand(
                            trackId: trimmedClip.trackId,
                            clipId: trimmedClip.clipId,
                            clipName: trimmedClip.fileName,
                            oldDuration: audioTrimStartDuration,
                            newDuration: trimmedClip.duration,
                            onClipResized: (clipId, duration, offset, startTime) {
                              setState(() {
                                final index = clips.indexWhere((c) => c.clipId == clipId);
                                if (index >= 0) {
                                  clips[index] = clips[index].copyWith(duration: duration);
                                }
                              });
                            },
                          );
                          await UndoRedoManager().execute(command);
                        }

                        setState(() {
                          trimmingAudioClipId = null;
                        });
                      },
                      child: Tooltip(
                        message: atLoopLimit
                            ? 'Drag left to trim, or enable Loop to extend'
                            : 'Drag to resize',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeRight,
                          child: Container(
                            width: 8,
                            height: totalHeight,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Split preview line (shown when Alt is pressed and hovering)
              if (hasSplitPreview)
                Positioned(
                  left: splitPreviewX,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: totalHeight,
                    color: context.colors.textPrimary.withValues(alpha: 0.8),
                  ),
                ),
                ],
              );
            },
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildMidiClip(MidiClipData midiClip, Color trackColor, double trackHeight, {double? recStartBeat, double? recEndBeat}) {
    // MIDI clips use beat-based positioning (tempo-independent visual layout)
    final clipStartBeats = midiClip.startTime;
    final clipDurationBeats = midiClip.duration;
    // Ensure minimum width to prevent layout errors (Stack requires finite size)
    final clipWidth = (clipDurationBeats * pixelsPerBeat).clamp(10.0, double.infinity);

    // Use dragged position if this clip is being dragged OR is part of the selection being dragged
    // BUT NOT for copy drags - the original stays in place, only the ghost moves
    double displayStartBeats;

    // Check if being dragged via MIDI clip drag
    final isBeingDraggedViaMidi = draggingMidiClipId != null &&
        (draggingMidiClipId == midiClip.clipId || selectedMidiClipIds.contains(midiClip.clipId)) &&
        !isCopyDrag;

    // Check if being dragged via audio clip drag (cross-type multi-track selection)
    final isBeingDraggedViaAudio = draggingClipId != null &&
        selectedMidiClipIds.contains(midiClip.clipId) &&
        !isCopyDrag;

    if (isBeingDraggedViaMidi) {
      final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

      // Calculate snapped delta based on the primary dragged clip
      var snappedDeltaBeats = dragDeltaBeats;
      if (!snapBypassActive) {
        final snapResolution = _getGridSnapResolution();
        // Snap based on the dragged clip's new position
        final draggedClipNewPos = midiDragStartTime + dragDeltaBeats;
        final snappedPos = (draggedClipNewPos / snapResolution).round() * snapResolution;
        snappedDeltaBeats = snappedPos - midiDragStartTime;
      }

      // Apply the same delta to this clip
      displayStartBeats = (clipStartBeats + snappedDeltaBeats).clamp(0.0, double.infinity);
    } else if (isBeingDraggedViaAudio) {
      // Calculate delta from audio drag (seconds) and convert to beats
      final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

      // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
      final beatsPerSecond = widget.tempo / 60.0;
      final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
      final snappedBeats = _snapToGrid(rawBeats);
      final snappedNewStartTime = snappedBeats / beatsPerSecond;
      final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

      // Convert seconds delta to beats delta
      final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

      // Apply the same delta to this clip
      displayStartBeats = (clipStartBeats + snappedDeltaBeats).clamp(0.0, double.infinity);
    } else {
      displayStartBeats = clipStartBeats;
    }
    final clipX = displayStartBeats * pixelsPerBeat;

    // Use both widget prop (single) and internal multi-selection
    final isSelected = widget.selectedMidiClipId == midiClip.clipId || selectedMidiClipIds.contains(midiClip.clipId);
    final isDragging = draggingMidiClipId == midiClip.clipId;

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 3.0; // Track height minus padding
    final isLiveRecording = midiClip.clipId == LiveRecordingNotifier.liveClipId;
    final recordingColor = const Color(0xFFE53935); // Red for recording indicator

    // Check if this clip has split preview active
    final hasSplitPreview = splitPreviewMidiClipId == midiClip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (splitPreviewBeatPosition / midiClip.duration) * clipWidth
        : 0.0;

    return Positioned(
      key: ValueKey('midi_clip_${midiClip.clipId}'),
      left: clipX,
      top: 0,
      child: _applyRecordingMask(
        clipX: clipX,
        clipWidth: clipWidth,
        pixelsPerUnit: pixelsPerBeat,
        recStart: recStartBeat,
        recEnd: recEndBeat,
        exclude: isLiveRecording,
        child: Listener(
        onPointerDown: isLiveRecording ? null : (event) {
          // Immediate selection feedback on pointer down (no gesture delay)
          if (event.buttons == kPrimaryButton) {
            // Check modifier keys directly at click time (more reliable than cached tempToolMode)
            final modifiers = ModifierKeyState.current();
            final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;

            // IMPORTANT: Capture copy modifier state at pointer down
            // This is needed because by the time onHorizontalDragStart fires,
            // the modifier key state may have changed (widget rebuild, etc.)
            midiPointerDownWasCopyModifier = modifiers.isCtrlOrCmd || tool == ToolMode.duplicate;

            // Eraser tool: start batched erasing (supports drag-to-delete like piano roll)
            if (tool == ToolMode.eraser) {
              // Convert local click position to global for eraser system
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final globalPos = box.localToGlobal(event.localPosition);
                _startErasing(globalPos);
              }
              return;
            }

            // Slice tool: split at click position
            if (tool == ToolMode.slice) {
              final clickXInClip = event.localPosition.dx;
              final clickBeatsInClip = clickXInClip / pixelsPerBeat;
              if (clickBeatsInClip > 0 && clickBeatsInClip < midiClip.duration) {
                setState(() {
                  splitPreviewMidiClipId = midiClip.clipId;
                  splitPreviewBeatPosition = clickBeatsInClip;
                });
                _splitMidiClipAtPreview(midiClip);
              }
              return;
            }

            // DRAW, SELECT, or DUPLICATE TOOL: Handle selection
            // (Duplicate only creates copy on drag-end, not click)
            final wasAlreadySelected = selectedMidiClipIds.contains(midiClip.clipId);

            // If clicking on already-selected clip without Shift, defer single-selection to tap-up
            // (allows multi-drag if user drags instead of clicking)
            if (wasAlreadySelected && !modifiers.isShiftPressed) {
              pendingMidiClipTapSelection = midiClip.clipId;
            } else {
              pendingMidiClipTapSelection = null;
              selectMidiClipMulti(
                midiClip.clipId,
                addToSelection: false,
                toggleSelection: modifiers.isShiftPressed,
              );
            }

            // Notify parent about selection
            if (!modifiers.isShiftPressed || selectedMidiClipIds.contains(midiClip.clipId)) {
              widget.onMidiClipSelected?.call(midiClip.clipId, midiClip);
            } else if (selectedMidiClipIds.isEmpty) {
              widget.onMidiClipSelected?.call(null, null);
            }
          }
        },
        child: GestureDetector(
        onSecondaryTapDown: isLiveRecording ? null : (details) {
          _showMidiClipContextMenu(details.globalPosition, midiClip);
        },
        onTapUp: isLiveRecording ? null : (details) {
          // Stop erasing if in eraser mode (single click delete)
          if (isErasing) {
            _stopErasing();
            return;
          }

          // If we had a pending tap selection (clicked on already-selected clip),
          // now reduce to single selection since no drag occurred
          if (pendingMidiClipTapSelection == midiClip.clipId) {
            selectMidiClipMulti(midiClip.clipId, forceSelect: true);
            widget.onMidiClipSelected?.call(midiClip.clipId, midiClip);
          }
          pendingMidiClipTapSelection = null;
        },
        onHorizontalDragStart: isLiveRecording ? null : (details) {
          // Clear pending tap selection - user is dragging, not clicking
          pendingMidiClipTapSelection = null;

          // Check modifier keys at drag start
          final modifiers = ModifierKeyState.current();
          final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;

          // Eraser mode: block all drag operations (erasing handled by onPointerDown + onHorizontalDragUpdate)
          if (tool == ToolMode.eraser) return;

          // Slice mode: block drag (slicing is handled by onPointerDown)
          if (tool == ToolMode.slice) return;

          // Check copy modifier: use captured state from pointer down, OR check current state
          // (ensures duplicate works even if pointer down didn't capture the state)
          final isDuplicate = midiPointerDownWasCopyModifier ||
              modifiers.isCtrlOrCmd ||
              tool == ToolMode.duplicate;

          // Check if this clip is in the multi-selection
          final isInMultiSelection = selectedMidiClipIds.contains(midiClip.clipId);

          // Capture the clips to drag/copy at drag START (before any state changes)
          // This ensures we have a stable list even if selection changes during drag
          final Set<int> clipIdsToProcess;
          if (isInMultiSelection) {
            // Dragging a selected clip - process all selected clips
            clipIdsToProcess = Set.from(selectedMidiClipIds);
          } else {
            // Dragging an unselected clip - only process this clip
            clipIdsToProcess = {midiClip.clipId};
          }

          setState(() {
            // Update MIDI selection to match what we're processing
            // NOTE: Don't clear audio selection - we want to drag both types together
            selectedMidiClipIds.clear();
            selectedMidiClipIds.addAll(clipIdsToProcess);

            draggingMidiClipId = midiClip.clipId;
            midiDragStartTime = midiClip.startTime;
            midiDragStartX = details.globalPosition.dx;
            midiDragCurrentX = details.globalPosition.dx;
            isCopyDrag = isDuplicate; // Use captured state from pointer down
          });
        },
        onHorizontalDragUpdate: isLiveRecording ? null : (details) {
          // Continue erasing if in eraser mode
          if (isErasing) {
            _eraseClipsAt(details.globalPosition);
            return;
          }

          // Skip in eraser/slice mode (Draw mode allows moving)
          final tool = effectiveToolMode;
          if (tool == ToolMode.eraser || tool == ToolMode.slice) return;

          // Shift bypasses snap (spec v2.0)
          final bypassSnap = ModifierKeyState.current().isShiftPressed;

          setState(() {
            midiDragCurrentX = details.globalPosition.dx;
            snapBypassActive = bypassSnap;
          });
        },
        onHorizontalDragEnd: isLiveRecording ? null : (details) {
          // Stop erasing if in eraser mode
          if (isErasing) {
            _stopErasing();
            return;
          }

          if (draggingMidiClipId == null) return;

          // Calculate delta in beats
          final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

          // Snap the delta (not absolute position) for consistent multi-clip movement
          var snappedDeltaBeats = dragDeltaBeats;
          if (!snapBypassActive) {
            final snapResolution = _getGridSnapResolution();
            // Snap the dragged clip's new position, then derive delta
            final newStartBeats = ((midiDragStartTime + dragDeltaBeats) / snapResolution).round() * snapResolution;
            snappedDeltaBeats = newStartBeats - midiDragStartTime;
          }

          // Convert delta to seconds for audio clips
          final beatsPerSecond = widget.tempo / 60.0;
          final snappedDeltaSeconds = snappedDeltaBeats / beatsPerSecond;

          if (isCopyDrag) {
            // Get all selected clips BEFORE clearing selection
            final midiClipsToCopy = widget.midiClips
                .where((c) => selectedMidiClipIds.contains(c.clipId))
                .toList();
            final audioClipsToCopy = clips
                .where((c) => selectedAudioClipIds.contains(c.clipId))
                .toList();

            // Clear internal selection - new copies will be selected after creation
            selectedMidiClipIds.clear();
            selectedAudioClipIds.clear();

            // Copy ALL selected MIDI clips with same offset delta
            // The parent will handle selecting the new clips via onMidiClipCopied callback
            for (final clip in midiClipsToCopy) {
              final newStartBeats = (clip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
              widget.onMidiClipCopied?.call(clip, newStartBeats);
            }

            // Copy ALL selected audio clips with same offset delta (in seconds)
            for (final audioClip in audioClipsToCopy) {
              final newStartTime = (audioClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
              _duplicateAudioClip(audioClip, atPosition: newStartTime);
            }

            // After all copies are made, we need to select the new clips
            // The new clips should now be at the end of widget.midiClips
            // Select them by finding clips that match the expected new positions
            // Use addPostFrameCallback to wait for the widget tree to rebuild after all
            // duplicate commands have executed (they're async via undo/redo manager)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                // Store original clip IDs for exclusion
                final originalMidiClipIds = midiClipsToCopy.map((c) => c.clipId).toSet();
                final originalAudioClipIds = audioClipsToCopy.map((c) => c.clipId).toSet();

                // Find newly created MIDI clips by their positions
                for (final originalClip in midiClipsToCopy) {
                  final expectedNewStart = (originalClip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
                  // Find a clip at this position that wasn't an original
                  final newClip = widget.midiClips.where((c) =>
                    (c.startTime - expectedNewStart).abs() < 0.01 && // Slightly larger tolerance
                    c.trackId == originalClip.trackId &&
                    !originalMidiClipIds.contains(c.clipId)
                  ).firstOrNull;
                  if (newClip != null) {
                    selectedMidiClipIds.add(newClip.clipId);
                  }
                }

                // Find newly created audio clips by their positions
                for (final originalClip in audioClipsToCopy) {
                  final expectedNewStart = (originalClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
                  final newClip = clips.where((c) =>
                    (c.startTime - expectedNewStart).abs() < 0.01 &&
                    c.trackId == originalClip.trackId &&
                    !originalAudioClipIds.contains(c.clipId)
                  ).firstOrNull;
                  if (newClip != null) {
                    selectedAudioClipIds.add(newClip.clipId);
                  }
                }
              });
            });
          } else {
            // Move: update ALL selected clips by the same delta

            // Move MIDI clips
            final selectedMidiClips = widget.midiClips.where((c) => selectedMidiClipIds.contains(c.clipId)).toList();

            for (final clip in selectedMidiClips) {
              final newStartBeats = (clip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
              final newStartTimeSeconds = newStartBeats / beatsPerSecond;
              final rustClipId = widget.getRustClipId?.call(clip.clipId) ?? clip.clipId;
              widget.audioEngine?.setClipStartTime(clip.trackId, rustClipId, newStartTimeSeconds);
              final updatedClip = clip.copyWith(startTime: newStartBeats);
              widget.onMidiClipUpdated?.call(updatedClip);
            }

            // Force UI refresh after parent processes MIDI updates
            if (selectedMidiClips.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }

            // Move audio clips
            final selectedAudioClips = clips.where((c) => selectedAudioClipIds.contains(c.clipId)).toList();

            for (final audioClip in selectedAudioClips) {
              final newStartTime = (audioClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);

              // Only create command if position actually changed
              if ((newStartTime - audioClip.startTime).abs() > 0.001) {
                final command = MoveAudioClipCommand(
                  trackId: audioClip.trackId,
                  clipId: audioClip.clipId,
                  clipName: audioClip.fileName,
                  newStartTime: newStartTime,
                  oldStartTime: audioClip.startTime,
                );
                UndoRedoManager().execute(command);
              }

              // Update local state
              setState(() {
                final index = clips.indexWhere((c) => c.clipId == audioClip.clipId);
                if (index >= 0) {
                  clips[index] = clips[index].copyWith(startTime: newStartTime);
                }
              });
            }
          }

          setState(() {
            draggingMidiClipId = null;
            isCopyDrag = false;
            snapBypassActive = false;
          });
        },
        child: MouseRegion(
          cursor: resizingMidiClipId == midiClip.clipId
              ? SystemMouseCursors.resizeRight
              : _getCursorForTool(effectiveToolMode, isOverClip: true),
          onHover: (event) {
            // Update temp tool mode on hover (in case modifier keys changed)
            updateTempToolMode();
            // Track hover position for split preview (when using slice tool)
            if (effectiveToolMode == ToolMode.slice) {
              _updateMidiClipSplitPreview(midiClip.clipId, event.localPosition.dx, clipWidth, midiClip);
            }
          },
          onExit: (_) {
            if (splitPreviewMidiClipId == midiClip.clipId) {
              _clearSplitPreview();
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main clip container with integrated loop boundary notches
              SizedBox(
                width: clipWidth,
                height: totalHeight,
                child: Stack(
                  children: [
                    // Content clipped to notched shape
                    ClipPath(
                      clipper: ClipPathClipper(
                        cornerRadius: 4,
                        notchRadius: 4,
                        loopBoundaryXPositions: _calculateLoopBoundaryPositions(
                          midiClip.loopLength,
                          clipDurationBeats,
                          clipWidth,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Header (simplified when clip is too narrow)
                          Container(
                            height: headerHeight,
                            decoration: BoxDecoration(
                              color: isLiveRecording ? recordingColor : trackColor,
                            ),
                            padding: clipWidth > 26 ? const EdgeInsets.symmetric(horizontal: 4) : null,
                            child: clipWidth > 26
                                ? Row(
                                    children: [
                                      Icon(
                                        Icons.piano,
                                        size: 10,
                                        color: context.colors.textPrimary,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          midiClip.name,
                                          style: TextStyle(
                                            color: context.colors.textPrimary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                : null, // Just show colored bar for very narrow clips
                          ),
                          // Content area with notes (transparent background)
                          Expanded(
                            child: midiClip.notes.isNotEmpty
                                ? LayoutBuilder(
                                    builder: (context, constraints) {
                                      return CustomPaint(
                                        size: Size(constraints.maxWidth, constraints.maxHeight),
                                        painter: MidiClipPainter(
                                          notes: midiClip.notes,
                                          clipDuration: clipDurationBeats,
                                          loopLength: midiClip.loopLength,
                                          trackColor: isLiveRecording ? recordingColor : trackColor,
                                          contentStartOffset: midiClip.contentStartOffset,
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    // Border with integrated notches
                    CustomPaint(
                      size: Size(clipWidth, totalHeight),
                      painter: ClipBorderPainter(
                        borderColor: isLiveRecording
                            ? recordingColor
                            : isSelected
                                ? context.colors.textPrimary
                                : trackColor.withValues(alpha: 0.7),
                        trackColor: isLiveRecording ? recordingColor : trackColor,
                        headerHeight: headerHeight,
                        borderWidth: isDragging || isSelected ? 2 : 1,
                        cornerRadius: 4,
                        loopBoundaryXPositions: _calculateLoopBoundaryPositions(
                          midiClip.loopLength,
                          clipDurationBeats,
                          clipWidth,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Left edge trim handle (hidden during live recording)
              if (!isLiveRecording) Positioned(
                left: 0,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() {
                      trimmingMidiClipId = midiClip.clipId;
                      trimStartTime = midiClip.startTime;
                      trimStartDuration = midiClip.duration;
                      trimStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (trimmingMidiClipId != midiClip.clipId) return;
                    final deltaX = details.globalPosition.dx - trimStartX;
                    final deltaBeats = deltaX / pixelsPerBeat;

                    // Calculate new start time and duration
                    var newStartTime = trimStartTime + deltaBeats;
                    var newDuration = trimStartDuration - deltaBeats;

                    // Snap to grid
                    final snapResolution = _getGridSnapResolution();
                    newStartTime = (newStartTime / snapResolution).round() * snapResolution;

                    // Overlap blocking: clamp to nearest MIDI clip on the left
                    double midiMinStartTime = 0.0;
                    final midiLeftSiblings = widget.midiClips.where(
                        (c) => c.trackId == midiClip.trackId && c.clipId != midiClip.clipId);
                    for (final sibling in midiLeftSiblings) {
                      final siblingEnd = sibling.startTime + sibling.duration;
                      if (siblingEnd <= trimStartTime + trimStartDuration &&
                          siblingEnd > midiMinStartTime) {
                        midiMinStartTime = siblingEnd;
                      }
                    }

                    newStartTime = newStartTime.clamp(midiMinStartTime, trimStartTime + trimStartDuration - 1.0);

                    // Recalculate duration based on snapped start
                    newDuration = (trimStartTime + trimStartDuration) - newStartTime;
                    newDuration = newDuration.clamp(1.0, 256.0);

                    // Filter notes that are now outside the clip (cropped by left trim)
                    final trimOffset = newStartTime - midiClip.startTime;
                    final filteredNotes = midiClip.notes.where((note) {
                      // Keep notes that end after the new start
                      return note.endTime > trimOffset;
                    }).map((note) {
                      // Adjust note start times relative to new clip start
                      final adjustedStart = note.startTime - trimOffset;
                      if (adjustedStart < 0) {
                        // Note starts before new clip start - truncate it
                        return note.copyWith(
                          startTime: 0,
                          duration: note.duration + adjustedStart, // Reduce duration
                        );
                      }
                      return note.copyWith(startTime: adjustedStart);
                    }).where((note) => note.duration > 0).toList();

                    final updatedClip = midiClip.copyWith(
                      startTime: newStartTime,
                      duration: newDuration,
                      loopLength: newDuration.clamp(0.25, midiClip.loopLength),
                      notes: filteredNotes,
                    );
                    widget.onMidiClipUpdated?.call(updatedClip);
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      trimmingMidiClipId = null;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeft,
                    child: Container(
                      width: 8,
                      height: totalHeight,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
              // Right edge resize handle (hidden during live recording)
              if (!isLiveRecording) Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    // Don't allow resize if canRepeat is false and already at loopLength
                    if (!midiClip.canRepeat && midiClip.duration >= midiClip.loopLength) {
                      return;
                    }
                    setState(() {
                      resizingMidiClipId = midiClip.clipId;
                      resizeStartDuration = midiClip.duration;
                      resizeStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (resizingMidiClipId != midiClip.clipId) return;
                    final deltaX = details.globalPosition.dx - resizeStartX;
                    final deltaBeats = deltaX / pixelsPerBeat;
                    var newDuration = (resizeStartDuration + deltaBeats).clamp(1.0, 256.0);

                    // Snap to grid
                    final snapResolution = _getGridSnapResolution();
                    newDuration = (newDuration / snapResolution).round() * snapResolution;
                    newDuration = newDuration.clamp(1.0, 256.0);

                    // Constrain to loopLength if canRepeat is false
                    if (!midiClip.canRepeat) {
                      newDuration = newDuration.clamp(1.0, midiClip.loopLength);
                    }

                    // Overlap blocking: clamp to nearest MIDI clip on the right
                    final midiSiblings = widget.midiClips.where(
                        (c) => c.trackId == midiClip.trackId && c.clipId != midiClip.clipId);
                    for (final sibling in midiSiblings) {
                      if (sibling.startTime > midiClip.startTime) {
                        final maxDuration = sibling.startTime - midiClip.startTime;
                        if (newDuration > maxDuration) {
                          newDuration = maxDuration;
                        }
                      }
                    }

                    final updatedClip = midiClip.copyWith(duration: newDuration);
                    widget.onMidiClipUpdated?.call(updatedClip);
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      resizingMidiClipId = null;
                    });
                  },
                  child: Tooltip(
                    message: midiClip.canRepeat
                        ? 'Drag to resize clip'
                        : 'Enable clip loop to stretch beyond content',
                    child: MouseRegion(
                      // Show forbidden cursor if canRepeat is false and at max length
                      cursor: !midiClip.canRepeat && midiClip.duration >= midiClip.loopLength
                          ? SystemMouseCursors.forbidden
                          : SystemMouseCursors.resizeRight,
                      child: Container(
                        width: 8,
                        height: totalHeight,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              // Split preview line (shown when Alt is pressed and hovering, hidden during recording)
              if (hasSplitPreview && !isLiveRecording)
                Positioned(
                  left: splitPreviewX,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: totalHeight,
                    color: context.colors.textPrimary.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }

  /// Calculate X positions of loop boundaries within a clip
  List<double> _calculateLoopBoundaryPositions(double loopLength, double clipDuration, double clipWidth) {
    final positions = <double>[];
    final clipPixelsPerBeat = clipWidth / clipDuration;
    var loopBeat = loopLength;
    while (loopBeat < clipDuration) {
      positions.add(loopBeat * clipPixelsPerBeat);
      loopBeat += loopLength;
    }
    return positions;
  }

  /// Build the playhead vertical line (spans full arrangement height)
  Widget _buildPlayheadLine() {
    final playheadX = widget.playheadPosition * pixelsPerSecond;
    const playheadColor = Color(0xFF3B82F6);

    return Positioned(
      left: playheadX - 1, // Center the 2px line
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          width: 2,
          color: playheadColor,
        ),
      ),
    );
  }

  /// Show track type selection popup after drag-to-create
  void _showTrackTypePopup(BuildContext context, Offset globalPosition, double startBeats, double durationBeats) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'midi',
          child: Row(
            children: [
              Icon(Icons.piano, size: 18, color: this.context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('MIDI Track'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'audio',
          child: Row(
            children: [
              Icon(Icons.audiotrack, size: 18, color: this.context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Audio Track'),
            ],
          ),
        ),
      ],
      color: this.context.colors.elevated,
    ).then((value) {
      if (value != null) {
        widget.onCreateTrackWithClip?.call(value, startBeats, durationBeats);
      }
    });
  }

  /// Check if a beat position is on an existing clip
  bool _isPositionOnClip(double beatPosition, int trackId, List<ClipData> audioClips, List<MidiClipData> midiClips) {
    // Check audio clips (convert seconds to beats for comparison)
    final beatsPerSecond = widget.tempo / 60.0;
    for (final clip in audioClips) {
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;
      if (beatPosition >= clipStartBeats && beatPosition <= clipEndBeats) {
        return true;
      }
    }

    // Check MIDI clips (already in beats)
    for (final clip in midiClips) {
      if (beatPosition >= clip.startTime && beatPosition <= clip.endTime) {
        return true;
      }
    }

    return false;
  }

  /// Update selection based on box selection rectangle.
  /// Called during drag to provide live selection feedback.
  void _updateBoxSelection() {
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
        trackTop += widget.clipHeights[regularTracks[i].id] ?? 100.0;
        // Include automation height if visible for this track
        if (widget.automationVisibleTrackId == regularTracks[i].id) {
          trackTop += widget.automationHeights[regularTracks[i].id] ?? 60.0;
        }
      }
      // Only use clip height for hit testing (clips are in clip area only)
      final trackHeight = widget.clipHeights[regularTracks[trackIndex].id] ?? 100.0;
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

  // ============================================
  // UNIFIED NAV BAR HANDLERS
  // ============================================

  /// Sync nav bar scroll with main scroll controller.
  void _syncNavBarScroll() {
    if (navBarScrollController.hasClients && scrollController.hasClients) {
      if ((navBarScrollController.offset - scrollController.offset).abs() > 0.1) {
        navBarScrollController.jumpTo(scrollController.offset);
      }
    }
  }

  /// Handle horizontal scroll from UnifiedNavBar drag.
  void _handleNavBarScroll(double delta) {
    if (!scrollController.hasClients) return;
    final maxScroll = scrollController.position.maxScrollExtent;
    final newOffset = (scrollController.offset + delta).clamp(0.0, maxScroll);
    scrollController.jumpTo(newOffset);
  }

  /// Handle zoom from UnifiedNavBar vertical drag.
  void _handleNavBarZoom(double factor, double anchorBeat) {
    setState(() {
      pixelsPerBeat = (pixelsPerBeat * factor).clamp(minZoom, maxZoom);
    });
  }

  /// Handle playhead set from UnifiedNavBar click.
  void _handleNavBarPlayheadSet(double beat) {
    final seconds = beat * 60.0 / widget.tempo;
    widget.onSeek?.call(seconds);
  }

  /// Calculate playhead position in beats.
  double _calculatePlayheadBeat() {
    return widget.playheadPosition * widget.tempo / 60.0;
  }

}
