import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'dart:math' as math;
import 'dart:async';
import '../constants/ui_constants.dart';
import '../audio_engine.dart';
import '../theme/animation_constants.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../utils/clip_overlap_handler.dart';
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
import '../services/commands/command.dart';
import '../services/commands/clip_commands.dart';
import 'canvas_bg_variant.dart';
import 'instrument_browser.dart';
import 'painters/timeline_grid_painter.dart';
import 'platform_drop_target.dart';
import 'shared/editors/zoomable_editor_mixin.dart';
import 'shared/editors/unified_nav_bar.dart';
import 'shared/editors/nav_bar_with_zoom.dart';
import 'timeline/timeline_models.dart';
import 'timeline/timeline_state.dart';
import 'timeline/clip_preview_builders.dart';
import 'timeline/timeline_selection.dart';
import 'timeline/timeline_file_handlers.dart';
import 'timeline/timeline_context_menus.dart';
import '../services/live_recording_notifier.dart';
import 'timeline/painters/painters.dart';
import 'timeline/track_automation_lane_widget.dart';
import '../utils/csv_field.dart';
import '../utils/logger.dart';

part 'timeline/timeline_gesture_layer.dart';
part 'timeline/timeline_track_list.dart';

/// Track data model for timeline
class TimelineTrackData {
  final int id;
  final String name;
  final String type;

  TimelineTrackData({required this.id, required this.name, required this.type});

  static TimelineTrackData? fromCSV(String csv) {
    try {
      final parts = csv.split(',');
      if (parts.length < 3) return null;
      return TimelineTrackData(
        id: int.parse(parts[0]),
        // Engine percent-encodes the name field (C34).
        name: decodeCsvField(parts[1]),
        type: parts[2],
      );
    } catch (e) {
      return null;
    }
  }
}

/// Timeline view widget for displaying audio clips and playhead
class TimelineView extends StatefulWidget {
  final ValueListenable<double>
  playheadNotifier; // in seconds, listened locally
  final double? clipDuration; // in seconds (null if no clip loaded)
  final List<double> waveformPeaks; // waveform data
  final AudioEngine? audioEngine;
  final Function(double)?
  onSeek; // callback when user drags playhead (passes position in seconds)
  final double tempo; // BPM for beat-based grid

  // MIDI editing state
  final int? selectedMidiTrackId;
  final int? selectedMidiClipId;
  final MidiClipData? currentEditingClip;
  final List<MidiClipData> midiClips; // All MIDI clips for visualization
  final Function(int?)? onMidiTrackSelected;
  final int Function(int dartClipId)? getRustClipId;

  // Grouped callback objects
  final MidiClipCallbacks midiClipCallbacks;
  final AudioClipCallbacks audioClipCallbacks;
  final DragDropCallbacks dragDropCallbacks;
  final AutomationCallbacks automationCallbacks;
  final TrackHeightState trackHeightState;

  // Track order (synced from TrackController for drag-and-drop reordering)
  final List<int> trackOrder;

  // Track color callback (for auto-detected colors with override support)
  final Color Function(int trackId, String trackName, String trackType)?
  getTrackColor;

  // Loop playback state (controls if arrangement playback loops)
  final bool loopPlaybackEnabled;
  final double loopStartBeats;
  final double loopEndBeats;
  final Function(double startBeats, double endBeats)? onLoopRegionChanged;

  // Punch in/out state (reuses loop region boundaries)
  final bool punchInEnabled;
  final bool punchOutEnabled;

  // Vertical scroll controller (synced with track mixer panel)
  final ScrollController? verticalScrollController;

  // Tool mode (shared with piano roll)
  final ToolMode toolMode;
  final Function(ToolMode)? onToolModeChanged;

  // Playback state (for playhead glow)
  final bool isPlaying;

  // Empty timeline callbacks (for adding tracks from empty state prompt)
  final VoidCallback? onAddMidiTrack;
  final VoidCallback? onAddAudioTrack;

  // Recording state (for auto-scroll and visual indicators)
  final bool isRecording;

  /// When false, the master timeline row is hidden (v0.3).
  final bool masterTimelineVisible;

  // Automation state
  final int? automationVisibleTrackId;
  final ScrollController?
  automationScrollController; // For syncing automation lane scroll

  /// Beats per bar (time-signature numerator) — drives the grid + nav-bar ruler.
  final int beatsPerBar;

  /// Dev "UI Labs" Variant D — pins the hero position/time readout to the
  /// top-left of the arrangement (non-scrolling) instead of the top bar.
  final bool showPinnedReadout;

  /// Canvas background lift (dev Cmd+Shift+B switcher). Drives the canvas fill,
  /// the grid-line lift, and the optional alternating-lane tint.
  final CanvasBgVariant canvasBgVariant;

  const TimelineView({
    super.key,
    required this.playheadNotifier,
    this.clipDuration,
    this.waveformPeaks = const [],
    this.audioEngine,
    this.onSeek,
    this.tempo = 120.0,
    this.selectedMidiTrackId,
    this.selectedMidiClipId,
    this.currentEditingClip,
    this.midiClips = const [],
    this.onMidiTrackSelected,
    this.getRustClipId,
    this.midiClipCallbacks = const MidiClipCallbacks(),
    this.audioClipCallbacks = const AudioClipCallbacks(),
    this.dragDropCallbacks = const DragDropCallbacks(),
    this.automationCallbacks = const AutomationCallbacks(),
    this.trackHeightState = const TrackHeightState(),
    this.trackOrder = const [],
    this.getTrackColor,
    this.loopPlaybackEnabled = false,
    this.loopStartBeats = 0.0,
    this.loopEndBeats = 4.0,
    this.onLoopRegionChanged,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
    this.verticalScrollController,
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
    this.automationVisibleTrackId,
    this.automationScrollController,
    this.isPlaying = false,
    this.onAddMidiTrack,
    this.onAddAudioTrack,
    this.isRecording = false,
    this.masterTimelineVisible = false,
    this.beatsPerBar = 4,
    this.showPinnedReadout = false,
    this.canvasBgVariant = CanvasBgVariant.noticeableGrey,
  });

  @override
  State<TimelineView> createState() => TimelineViewState();
}

class TimelineViewState extends State<TimelineView>
    with
        ZoomableEditorMixin,
        TimelineViewStateMixin,
        ClipPreviewBuildersMixin,
        TimelineSelectionMixin,
        TimelineFileHandlersMixin,
        TimelineContextMenusMixin,
        TimelineGestureLayerMixin,
        TimelineTrackListMixin {
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

    // Listen to playhead for recording auto-scroll (without rebuilding entire timeline)
    widget.playheadNotifier.addListener(_onPlayheadChanged);

    // Throttled scroll listener for viewport culling (rebuild when scrolled 50+ px)
    scrollController.addListener(_onScrollForCulling);

    // Initialize cursor based on initial tool mode
    currentCursor = _cursorForToolMode(widget.toolMode);
  }

  double _lastCullScrollOffset = 0.0;

  void _onScrollForCulling() {
    final delta = (scrollController.offset - _lastCullScrollOffset).abs();
    if (delta > 50) {
      _lastCullScrollOffset = scrollController.offset;
      setState(() {});
    }
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
    // Swap playhead notifier listener if it changed
    if (widget.playheadNotifier != oldWidget.playheadNotifier) {
      oldWidget.playheadNotifier.removeListener(_onPlayheadChanged);
      widget.playheadNotifier.addListener(_onPlayheadChanged);
    }
  }

  /// Auto-scroll to keep playhead visible during recording.
  /// Called by the playhead notifier (does NOT trigger timeline rebuild).
  void _onPlayheadChanged() {
    if (widget.isRecording && scrollController.hasClients) {
      final beatsPerSecond = widget.tempo / 60.0;
      final playheadPixelX =
          widget.playheadNotifier.value * beatsPerSecond * pixelsPerBeat;
      final viewportRight = scrollController.offset + viewWidth;
      // Scroll when playhead passes 80% of the visible area
      if (playheadPixelX >
          viewportRight - viewWidth * UIConstants.playheadScrollThreshold) {
        final targetOffset =
            playheadPixelX - viewWidth * UIConstants.playheadScrollOffset;
        scrollController.jumpTo(
          targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
        );
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

    // Separate master and return tracks (returns rendered in arrangement as
    // section dividers; need them in the tracks list so timeline_view can
    // pick them up).
    final masterTrack = tracks.where((t) => t.type == 'Master').toList();
    final returnTracksList = tracks
        .where((t) => t.type.toLowerCase() == 'return')
        .toList();
    final regularTrackIds = tracksMap.keys
        .where(
          (id) =>
              tracksMap[id]!.type.toLowerCase() != 'master' &&
              tracksMap[id]!.type.toLowerCase() != 'return',
        )
        .toSet();

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
    // Returns then master at end
    orderedTracks.addAll(returnTracksList);
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
    widget.playheadNotifier.removeListener(_onPlayheadChanged);
    scrollController.removeListener(_onScrollForCulling);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    scrollController.dispose();
    timelineFocusNode.dispose();
    refreshTimer?.cancel();
    previewLoadTimer?.cancel();
    super.dispose();
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

    // Route through the shared undoable split (trims left + registers right in
    // the engine). Previously this only mutated the UI list, so the engine kept
    // playing the un-split clip until the next save/load — and it couldn't undo.
    runAudioSplit(clip, playheadSeconds);
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
    final quantizedStart =
        (clip.startTime / gridSizeSeconds).round() * gridSizeSeconds;

    // Only update if position changed
    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      return false;
    }

    // Update clip position
    widget.audioEngine?.setClipStartTime(
      clip.trackId,
      clip.clipId,
      quantizedStart,
    );

    setState(() {
      final index = clips.indexWhere((c) => c.clipId == clip.clipId);
      if (index >= 0) {
        clips[index] = clips[index].copyWith(startTime: quantizedStart);
      }
    });

    return true;
  }

  /// Compare two track lists by id, name, and type to avoid unnecessary rebuilds.
  bool _tracksEqual(List<TimelineTrackData> a, List<TimelineTrackData> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].type != b[i].type) {
        return false;
      }
    }
    return true;
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
        // Separate master + returns (returns become section dividers in the
        // arrangement; they're not in the scrollable track area).
        final masterTrack = tracksMap.values
            .where((t) => t.type == 'Master')
            .toList();
        final returnTracksList = tracksMap.values
            .where((t) => t.type.toLowerCase() == 'return')
            .toList();
        final regularTrackIds = tracksMap.keys
            .where(
              (id) =>
                  tracksMap[id]!.type.toLowerCase() != 'master' &&
                  tracksMap[id]!.type.toLowerCase() != 'return',
            )
            .toSet();

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

        // Returns then master at the end
        orderedTracks.addAll(returnTracksList);
        orderedTracks.addAll(masterTrack);

        // Only rebuild if tracks actually changed
        if (!_tracksEqual(tracks, orderedTracks)) {
          setState(() {
            tracks = orderedTracks;
          });
        }
      }
    } catch (e) {
      Log.e('TimelineView: Error loading tracks: $e');
    }
  }

  /// Deletes every currently-selected MIDI and audio clip. Returns true if
  /// anything was deleted. Public so the root DAW shortcut handler can use it as
  /// a Delete fallback when timeline focus was momentarily elsewhere.
  bool deleteSelectedClips() {
    bool handled = false;

    // Delete all selected MIDI clips
    if (selectedMidiClipIds.isNotEmpty) {
      final clipsToDelete = <(int, int)>[];
      for (final clipId in selectedMidiClipIds) {
        final clip = widget.midiClips
            .where((c) => c.clipId == clipId)
            .firstOrNull;
        if (clip != null) {
          clipsToDelete.add((clip.clipId, clip.trackId));
        }
      }
      if (clipsToDelete.isNotEmpty) {
        widget.midiClipCallbacks.onBatchDeleted?.call(clipsToDelete);
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
        widget.audioClipCallbacks.onBatchDeleted?.call(clipsToDelete);
        selectedAudioClipIds.clear();
        handled = true;
      }
    }

    if (handled) setState(() {});
    return handled;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Handle Delete/Backspace to delete all selected clips
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        if (deleteSelectedClips()) {
          return KeyEventResult.handled;
        }
      }

      // Handle Escape to deselect all clips (spec v2.0)
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        deselectAllClips();
        return KeyEventResult.handled;
      }

      // Cmd+D to duplicate selected clip (spec v2.0)
      if (event.logicalKey == LogicalKeyboardKey.keyD &&
          ModifierKeyState.current().isCtrlOrCmd) {
        if (widget.selectedMidiClipId != null) {
          final clip = widget.midiClips
              .where((c) => c.clipId == widget.selectedMidiClipId)
              .firstOrNull;
          if (clip != null) {
            duplicateMidiClip(clip);
            return KeyEventResult.handled;
          }
        }
      }

      // Cmd+A to select all clips (spec v2.0)
      if (event.logicalKey == LogicalKeyboardKey.keyA &&
          ModifierKeyState.current().isCtrlOrCmd) {
        selectAllClips();
        return KeyEventResult.handled;
      }

      // Q to quantize selected clip (spec v2.0)
      if (event.logicalKey == LogicalKeyboardKey.keyQ) {
        if (widget.selectedMidiClipId != null) {
          final clip = widget.midiClips
              .where((c) => c.clipId == widget.selectedMidiClipId)
              .firstOrNull;
          if (clip != null) {
            quantizeMidiClip(clip);
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
      if (event.logicalKey == LogicalKeyboardKey.keyZ &&
          !modifiers.isCtrlOrCmd) {
        widget.onToolModeChanged?.call(ToolMode.draw);
        return KeyEventResult.handled;
      }
      // X = Select tool (without Cmd/Ctrl - Cmd+X is cut)
      if (event.logicalKey == LogicalKeyboardKey.keyX &&
          !modifiers.isCtrlOrCmd) {
        widget.onToolModeChanged?.call(ToolMode.select);
        return KeyEventResult.handled;
      }
      // C = Erase tool (without Cmd/Ctrl - Cmd+C is copy)
      if (event.logicalKey == LogicalKeyboardKey.keyC &&
          !modifiers.isCtrlOrCmd) {
        widget.onToolModeChanged?.call(ToolMode.eraser);
        return KeyEventResult.handled;
      }
      // V = Duplicate tool (without Cmd/Ctrl - Cmd+V is paste)
      if (event.logicalKey == LogicalKeyboardKey.keyV &&
          !modifiers.isCtrlOrCmd) {
        widget.onToolModeChanged?.call(ToolMode.duplicate);
        return KeyEventResult.handled;
      }
      // B = Slice tool
      if (event.logicalKey == LogicalKeyboardKey.keyB &&
          !modifiers.isCtrlOrCmd) {
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
  }

  @override
  Widget build(BuildContext context) {
    // Update viewWidth for zoom calculations
    viewWidth = MediaQuery.of(context).size.width;

    // Beat-based width calculation (tempo-independent)
    final beatsPerSecond = widget.tempo / 60.0;

    // Minimum 64 bars (256 beats) for a typical song length, or extend based on clip duration
    const minBeats = UIConstants.timelineMinBeats;

    // Calculate beats needed for clip duration (if any)
    final clipDurationBeats = widget.clipDuration != null
        ? (widget.clipDuration! * beatsPerSecond).ceil() +
              4 // Add padding
        : 0;

    // Use the larger of minimum bars or clip duration
    final totalBeats = math.max(minBeats, clipDurationBeats);
    final totalWidth = math.max(totalBeats * pixelsPerBeat, viewWidth);

    // Duration in seconds for backward compatibility
    final duration = totalBeats / beatsPerSecond;

    // Calculate total tracks height for scrollable area (excludes Master - it's pinned at bottom)
    final regularTracks = tracks
        .where(
          (t) =>
              t.type.toLowerCase() != 'master' &&
              t.type.toLowerCase() != 'return',
        )
        .toList();
    final masterTrack = tracks.firstWhere(
      (t) => t.type == 'Master',
      orElse: () => TimelineTrackData(id: -1, name: 'Master', type: 'Master'),
    );
    // Return tracks render outside the scroll area as section anchors:
    // a thin divider + reserved master-height band each. Visually mirrors
    // the mixer's return strip placement above Master.
    final returnTracks = tracks
        .where((t) => t.type.toLowerCase() == 'return')
        .toList(growable: false);
    double totalTracksHeight = 0.0;
    for (final track in regularTracks) {
      totalTracksHeight +=
          widget.trackHeightState.clipHeights[track.id] ??
          UIConstants.defaultClipHeight;
      // Add automation lane height if visible for this track
      if (UIConstants.enableAutomation &&
          widget.automationVisibleTrackId == track.id) {
        totalTracksHeight +=
            widget.trackHeightState.automationHeights[track.id] ??
            UIConstants.defaultAutomationHeight;
      }
    }
    final actualTracksHeight = totalTracksHeight; // Before adding empty area

    return MouseRegion(
      cursor: currentCursor,
      child: Focus(
        focusNode: timelineFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.canvasBgVariant.background,
            border: Border.all(color: context.colors.divider),
          ),
          child: Stack(
            children: [
              // Main timeline content
              Column(
                children: [
                  // Unified nav bar (loop region + bar numbers + zoom controls)
                  NavBarWithZoom(
                    scrollController: navBarScrollController,
                    onZoomIn: () => setState(() {
                      pixelsPerBeat =
                          (pixelsPerBeat * UIConstants.zoomStepFactor).clamp(
                            minZoom,
                            maxZoom,
                          );
                    }),
                    onZoomOut: () => setState(() {
                      pixelsPerBeat =
                          (pixelsPerBeat / UIConstants.zoomStepFactor).clamp(
                            minZoom,
                            maxZoom,
                          );
                    }),
                    height: UIConstants.navBarHeight,
                    pixelsPerBeat: pixelsPerBeat,
                    beatsPerBar: widget.beatsPerBar,
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.playheadNotifier,
                      builder: (context, _, __) => UnifiedNavBar(
                        config: UnifiedNavBarConfig(
                          pixelsPerBeat: pixelsPerBeat,
                          totalBeats: totalBeats.toDouble(),
                          beatsPerBar: widget.beatsPerBar,
                          loopEnabled: widget.loopPlaybackEnabled,
                          loopStart: widget.loopStartBeats,
                          loopEnd: widget.loopEndBeats,
                          playheadPosition: _calculatePlayheadBeat(),
                          isPlaying: widget.isPlaying,
                          punchInEnabled: widget.punchInEnabled,
                          punchOutEnabled: widget.punchOutEnabled,
                        ),
                        callbacks: UnifiedNavBarCallbacks(
                          onHorizontalScroll: _handleNavBarScroll,
                          onZoom: _handleNavBarZoom,
                          onPlayheadSet: _handleNavBarPlayheadSet,
                          onPlayheadDrag:
                              _handleNavBarPlayheadSet, // Same handler for drag
                          onLoopRegionChanged: widget.onLoopRegionChanged,
                        ),
                        scrollController: navBarScrollController,
                        height: UIConstants.navBarHeight,
                      ),
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
                                      child: RepaintBoundary(
                                        child: _buildGrid(
                                          totalWidth,
                                          duration,
                                          double.infinity,
                                        ),
                                      ),
                                    ),

                                    // Content column: scrollable tracks + Master
                                    Column(
                                      children: [
                                        // Scrollable tracks area
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              // Compute empty area height to fill remaining viewport
                                              final emptyAreaHeight = math.max(
                                                100.0,
                                                constraints.maxHeight -
                                                    actualTracksHeight,
                                              );
                                              final totalTracksHeight =
                                                  actualTracksHeight +
                                                  emptyAreaHeight;

                                              return SingleChildScrollView(
                                                controller: widget
                                                    .verticalScrollController,
                                                scrollDirection: Axis.vertical,
                                                child: Listener(
                                                  onPointerDown: (event) {
                                                    // Eraser tool (toolbar OR Alt modifier) = start erasing on pointer down
                                                    if (event.buttons ==
                                                        kPrimaryButton) {
                                                      final modifiers =
                                                          ModifierKeyState.current();
                                                      final tool =
                                                          modifiers
                                                              .getOverrideToolMode() ??
                                                          widget.toolMode;
                                                      if (tool ==
                                                          ToolMode.eraser) {
                                                        _startErasing(
                                                          event.position,
                                                        );
                                                      }
                                                    }
                                                  },
                                                  onPointerMove: (event) {
                                                    // Eraser tool (toolbar OR Alt modifier) = drag-to-erase
                                                    if (event.buttons ==
                                                        kPrimaryButton) {
                                                      final modifiers =
                                                          ModifierKeyState.current();
                                                      final tool =
                                                          modifiers
                                                              .getOverrideToolMode() ??
                                                          widget.toolMode;
                                                      if (tool ==
                                                          ToolMode.eraser) {
                                                        if (!isErasing) {
                                                          _startErasing(
                                                            event.position,
                                                          );
                                                        } else {
                                                          _eraseClipsAt(
                                                            event.position,
                                                          );
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
                                                        height:
                                                            totalTracksHeight,
                                                        width: totalWidth,
                                                      ),

                                                      // Tracks (regular tracks only, Master is pinned below)
                                                      _buildTracks(
                                                        totalWidth,
                                                        totalBeats.toDouble(),
                                                        emptyAreaHeight:
                                                            emptyAreaHeight,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),

                                        // Return + Master sections pinned at the bottom of the
                                        // arrangement, outside the scroll area. Each is a thin
                                        // divider + reserved-height band so the dividers act as
                                        // section anchors ("Returns start here", "Master starts
                                        // here") even when their content is empty / hidden.
                                        ...returnTracks.map(
                                          (track) => Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: totalWidth,
                                                height: 2,
                                                color: context.colors.hover,
                                              ),
                                              SizedBox(
                                                // Match the mixer strip height for this return
                                                // so the divider lines up with the top edge of
                                                // the Reverb strip in the mixer panel.
                                                height:
                                                    widget
                                                        .trackHeightState
                                                        .clipHeights[track
                                                        .id] ??
                                                    UIConstants
                                                        .defaultClipHeight,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (masterTrack.id != -1) ...[
                                          Container(
                                            width: totalWidth,
                                            height: 2,
                                            color: context.colors.hover,
                                          ),
                                          if (widget.masterTimelineVisible)
                                            _buildMasterTrack(
                                              totalWidth,
                                              masterTrack,
                                            )
                                          else
                                            SizedBox(
                                              height: widget
                                                  .trackHeightState
                                                  .masterTrackHeight,
                                            ),
                                        ],
                                      ],
                                    ),

                                    // Playhead line (vertical line spanning full height)
                                    // VLB isolates rebuild to just this Positioned child at 60fps
                                    ValueListenableBuilder<double>(
                                      valueListenable: widget.playheadNotifier,
                                      builder: (context, _, __) {
                                        final playheadX =
                                            widget.playheadNotifier.value *
                                            pixelsPerSecond;
                                        return Positioned(
                                          left: playheadX - 1,
                                          top: 0,
                                          bottom: 0,
                                          child: IgnorePointer(
                                            child: Container(
                                              width: 2,
                                              color: context.colors.accent,
                                            ),
                                          ),
                                        );
                                      },
                                    ),

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
              ), // end Column
              // Empty timeline prompt — on top of grid and stars
              if (_shouldShowEmptyPrompt) _buildEmptyTimelinePrompt(context),
              // Variant D — hero readout pinned to the arrangement's top-left,
              // just below the ruler so it clears the orientation chip. Floats
              // over the grid and never scrolls. IgnorePointer so clicks pass
              // through to the timeline beneath.
              if (widget.showPinnedReadout)
                Positioned(
                  left: BT.sm,
                  top: UIConstants.navBarHeight + BT.sm,
                  child: IgnorePointer(child: _buildPinnedReadout()),
                ),
            ], // end Stack children
          ), // end Stack (child of DecoratedBox)
        ), // end DecoratedBox (child of Focus)
      ), // end Focus (child of MouseRegion)
    ); // end MouseRegion
  }

  /// Variant D's pinned readout — bars.beats.ticks over M:SS.mmm in the LCD
  /// style of the top-bar B panel. Formatting mirrors [PositionDisplay]
  /// (position_display.dart); kept self-contained as this is a dev A/B variant.
  Widget _buildPinnedReadout() {
    final colors = context.colors;
    return ValueListenableBuilder<double>(
      valueListenable: widget.playheadNotifier,
      builder: (context, seconds, _) {
        final beatsPerSecond = widget.tempo / 60.0;
        final totalBeats = seconds * beatsPerSecond;
        final bar = (totalBeats / widget.beatsPerBar).floor() + 1;
        final beat = (totalBeats % widget.beatsPerBar).floor() + 1;
        final sub = ((totalBeats % 1) * 4).floor() + 1;
        final minutes = seconds ~/ 60;
        final secs = (seconds % 60).floor();
        final millis = ((seconds % 1) * 1000).floor();
        final barsText = '$bar.$beat.$sub';
        final timeText =
            '$minutes:${secs.toString().padLeft(2, '0')}'
            '.${millis.toString().padLeft(3, '0')}';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.darkest.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(BT.radiusMd),
            border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                offset: const Offset(0, 2),
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                barsText,
                style: TextStyle(
                  fontFamily: BT.fontFamilyMono,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  height: 1.0,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeText,
                style: TextStyle(
                  fontFamily: BT.fontFamilyMono,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                  height: 1.0,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
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
            beatsPerBar: widget.beatsPerBar,
            loopEnabled: widget.loopPlaybackEnabled,
            loopStart: widget.loopStartBeats,
            loopEnd: widget.loopEndBeats,
            barLineColor: widget.canvasBgVariant.liftGrid(context.colors.hover),
            beatLineColor: widget.canvasBgVariant.liftGrid(
              context.colors.divider,
            ),
            subBeatLineColor: widget.canvasBgVariant.liftGrid(
              context.colors.surface,
            ),
            minorGridColor: widget.canvasBgVariant.liftGrid(
              context.colors.standard,
            ),
          ),
        ),
      );
    }
    return CustomPaint(
      size: Size(width, height),
      painter: TimelineGridPainter(
        pixelsPerBeat: pixelsPerBeat,
        beatsPerBar: widget.beatsPerBar,
        loopEnabled: widget.loopPlaybackEnabled,
        loopStart: widget.loopStartBeats,
        loopEnd: widget.loopEndBeats,
        barLineColor: widget.canvasBgVariant.liftGrid(context.colors.hover),
        beatLineColor: widget.canvasBgVariant.liftGrid(context.colors.divider),
        subBeatLineColor: widget.canvasBgVariant.liftGrid(
          context.colors.surface,
        ),
        minorGridColor: widget.canvasBgVariant.liftGrid(
          context.colors.standard,
        ),
      ),
    );
  }

  /// Build automation lane for a track in the timeline

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

  // ============================================
  // EMPTY TIMELINE PROMPT
  // ============================================

  /// Show empty state when no user tracks exist (only master track).
  bool get _shouldShowEmptyPrompt =>
      tracks.where((t) => t.type != 'Master').isEmpty;

  /// Centered prompt over star field with add-track buttons. Lights up when a
  /// library instrument/sample is dragged over the empty arrangement.
  Widget _buildEmptyTimelinePrompt(BuildContext context) {
    final colors = context.colors;
    final isDragOver =
        isMidiFileDraggingOverEmpty || isAudioFileDraggingOverEmpty;

    return Positioned.fill(
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            // A soft accent wash + ring while a sound hovers, so "drop here"
            // reads instantly; invisible at rest.
            color: isDragOver
                ? colors.accent.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDragOver
                  ? colors.accent.withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Instrument glyph — the "this is where music goes" anchor.
                Icon(
                  BI.piano,
                  size: 44,
                  color: isDragOver ? colors.accent : colors.textMuted,
                ),
                const SizedBox(height: 16),
                // Two lines, same length whether dragging or not (no layout jump).
                Text(
                  isDragOver
                      ? 'Drop it here to'
                      : 'Drag an instrument from the',
                  style: TextStyle(color: colors.textSecondary, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                Text(
                  isDragOver
                      ? 'add your new track'
                      : 'library to start making music',
                  style: TextStyle(color: colors.textSecondary, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'or',
                    style: TextStyle(
                      color: colors.textMuted.withValues(alpha: 0.5),
                      fontSize: BT.fontLabel,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _EmptyPromptButton(
                      icon: BI.piano,
                      label: 'MIDI Track',
                      hoverColor:
                          TrackColors.categoryColors[TrackColorCategory.synth],
                      onTap: widget.onAddMidiTrack,
                    ),
                    const SizedBox(width: 12),
                    _EmptyPromptButton(
                      icon: BI.waveform,
                      label: 'Audio Track',
                      hoverColor:
                          TrackColors.categoryColors[TrackColorCategory.audio],
                      onTap: widget.onAddAudioTrack,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Calculate playhead position in beats.
  double _calculatePlayheadBeat() {
    return widget.playheadNotifier.value * widget.tempo / 60.0;
  }
}

/// Styled button for the empty timeline prompt with icon.
class _EmptyPromptButton extends StatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  /// Track-type tint shown on hover (border + type icon). Defaults to accent.
  final Color? hoverColor;

  const _EmptyPromptButton({
    this.icon,
    required this.label,
    this.onTap,
    this.hoverColor,
  });

  @override
  State<_EmptyPromptButton> createState() => _EmptyPromptButtonState();
}

class _EmptyPromptButtonState extends State<_EmptyPromptButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hover = widget.hoverColor ?? colors.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_isHovered) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = true);
          });
        }
      },
      onExit: (_) {
        if (_isHovered) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = false);
          });
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationConstants.hoverDuration,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _isHovered ? hover : colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                BI.add,
                size: 13,
                color: _isHovered ? colors.textPrimary : colors.textSecondary,
              ),
              if (widget.icon != null) ...[
                const SizedBox(width: 4),
                Icon(
                  widget.icon,
                  size: 14,
                  // Type icon picks up the track-type tint on hover.
                  color: _isHovered ? hover : colors.textMuted,
                ),
              ],
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isHovered ? colors.textPrimary : colors.textSecondary,
                  fontSize: BT.fontLabel,
                  fontWeight: BT.weightMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
