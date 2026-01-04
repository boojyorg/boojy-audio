import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerScrollEvent, kPrimaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'dart:math' as math;
import 'dart:async';
import 'package:cross_file/cross_file.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';
import '../utils/track_colors.dart';
import '../models/clip_data.dart';
import '../models/midi_note_data.dart';
import '../models/vst3_plugin_data.dart';
import 'instrument_browser.dart';
import 'painters/dashed_line_painter.dart';
import 'painters/time_ruler_painter.dart';
import 'painters/timeline_grid_painter.dart';
import 'platform_drop_target.dart';
import 'context_menus/clip_context_menu.dart';
import 'timeline/timeline_state.dart';

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
  final Function(MidiClipData)? onMidiClipUpdated;
  final Function(MidiClipData sourceClip, double newStartTime)? onMidiClipCopied;
  final int Function(int dartClipId)? getRustClipId;
  final Function(int clipId, int trackId)? onMidiClipDeleted;

  // Instrument drag-and-drop
  final Function(int trackId, Instrument instrument)? onInstrumentDropped;
  final Function(Instrument instrument)? onInstrumentDroppedOnEmpty;

  // VST3 instrument drag-and-drop
  final Function(int trackId, Vst3Plugin plugin)? onVst3InstrumentDropped;
  final Function(Vst3Plugin plugin)? onVst3InstrumentDroppedOnEmpty;

  // Audio file drag-and-drop on empty space
  final Function(String filePath)? onAudioFileDroppedOnEmpty;

  // Drag-to-create callbacks
  final Function(String trackType, double startBeats, double durationBeats)? onCreateTrackWithClip;
  final Function(int trackId, double startBeats, double durationBeats)? onCreateClipOnTrack;

  // Track heights (synced from mixer panel)
  final Map<int, double> trackHeights; // trackId -> height
  final double masterTrackHeight;

  // Track color callback (for auto-detected colors with override support)
  final Color Function(int trackId, String trackName, String trackType)? getTrackColor;

  // Loop region state
  final bool isLoopEnabled;
  final double loopStartBeats;
  final double loopEndBeats;
  final Function(double startBeats, double endBeats)? onLoopRegionChanged;

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
    this.onMidiClipUpdated,
    this.onMidiClipCopied,
    this.getRustClipId,
    this.onMidiClipDeleted,
    this.onInstrumentDropped,
    this.onInstrumentDroppedOnEmpty,
    this.onVst3InstrumentDropped,
    this.onVst3InstrumentDroppedOnEmpty,
    this.onAudioFileDroppedOnEmpty,
    this.onCreateTrackWithClip,
    this.onCreateClipOnTrack,
    this.trackHeights = const {},
    this.masterTrackHeight = 60.0,
    this.getTrackColor,
    this.isLoopEnabled = false,
    this.loopStartBeats = 0.0,
    this.loopEndBeats = 4.0,
    this.onLoopRegionChanged,
  });

  @override
  State<TimelineView> createState() => TimelineViewState();
}

class TimelineViewState extends State<TimelineView> with TimelineViewStateMixin {
  @override
  void initState() {
    super.initState();
    _loadTracksAsync();

    // Refresh tracks every 2 seconds
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _loadTracksAsync();
    });
  }

  @override
  void didUpdateWidget(TimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload tracks when audio engine becomes available
    if (widget.audioEngine != null && oldWidget.audioEngine == null) {
      _loadTracksAsync();
    }
  }

  @override
  void dispose() {
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
    if (pixelsPerBeat < 10) return 4.0;     // Snap to bars (every 4 beats)
    if (pixelsPerBeat < 20) return 1.0;     // Snap to beats
    if (pixelsPerBeat < 40) return 0.5;     // Snap to half beats (1/8th notes)
    if (pixelsPerBeat < 80) return 0.25;    // Snap to quarter beats (1/16th notes)
    return 0.125;                            // Snap to eighth beats (1/32nd notes)
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
    return (beats / snapResolution).round() * snapResolution;
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
      final peaks = widget.audioEngine!.getWaveformPeaks(clipId, 2000);

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
    });
  }

  /// Check if a MIDI clip is selected
  bool isMidiClipSelected(int clipId) => selectedMidiClipIds.contains(clipId);

  /// Check if an audio clip is selected
  bool isAudioClipSelected(int clipId) => selectedAudioClipIds.contains(clipId);

  /// Select a MIDI clip with multi-selection support
  /// - Normal click: Select only this clip (clear others)
  /// - Shift+click: Add to selection
  /// - Cmd+click: Toggle selection
  void selectMidiClipMulti(int clipId, {bool addToSelection = false, bool toggleSelection = false}) {
    setState(() {
      if (toggleSelection) {
        // Cmd+click: Toggle this clip's selection
        if (selectedMidiClipIds.contains(clipId)) {
          selectedMidiClipIds.remove(clipId);
        } else {
          selectedMidiClipIds.add(clipId);
        }
      } else if (addToSelection) {
        // Shift+click: Add to selection
        selectedMidiClipIds.add(clipId);
      } else {
        // Normal click: Select only this clip
        selectedMidiClipIds.clear();
        selectedMidiClipIds.add(clipId);
      }
      // Clear audio selection when selecting MIDI
      selectedAudioClipIds.clear();
      selectedAudioClipId = null;
    });
  }

  /// Select an audio clip with multi-selection support
  /// - Normal click: Select only this clip (clear others)
  /// - Shift+click: Add to selection
  /// - Cmd+click: Toggle selection
  void selectAudioClipMulti(int clipId, {bool addToSelection = false, bool toggleSelection = false}) {
    setState(() {
      if (toggleSelection) {
        // Cmd+click: Toggle this clip's selection
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
        // Shift+click: Add to selection
        selectedAudioClipIds.add(clipId);
        selectedAudioClipId = clipId;
      } else {
        // Normal click: Select only this clip
        selectedAudioClipIds.clear();
        selectedAudioClipIds.add(clipId);
        selectedAudioClipId = clipId;
      }
      // Clear MIDI selection when selecting audio
      selectedMidiClipIds.clear();
    });
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
          _splitMidiClipAtInsertMarker(clip);
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
          value: 'set_marker',
          child: Row(
            children: [
              Icon(Icons.location_on, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set Insert Marker Here'),
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
        case 'set_marker':
          setInsertMarker(snappedBeat);
          break;
        case 'select_all':
          selectAllClips();
          break;
      }
    });
  }

  /// Delete an audio clip
  void _deleteAudioClip(ClipData clip) {
    // Note: Audio clips are managed locally in Flutter state
    // The Rust engine doesn't have a remove_audio_clip FFI yet
    setState(() {
      clips.removeWhere((c) => c.clipId == clip.clipId);
      if (selectedAudioClipId == clip.clipId) {
        selectedAudioClipId = null;
      }
      selectedAudioClipIds.remove(clip.clipId);
    });
  }

  /// Duplicate an audio clip (place copy after original)
  void _duplicateAudioClip(ClipData clip) {
    final newClipId = DateTime.now().millisecondsSinceEpoch;
    final newStartTime = clip.startTime + clip.duration;

    // Note: Audio clips are managed locally in Flutter state
    // For full engine support, we'd need to load the file again via loadAudioFileToTrack
    final newClip = clip.copyWith(
      clipId: newClipId,
      startTime: newStartTime,
    );
    setState(() {
      clips.add(newClip);
    });
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

    // Paste at insert marker if available, otherwise at start
    final pastePosition = insertMarkerBeats ?? 0.0;
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

  /// Toggle loop state of a MIDI clip
  void _toggleMidiClipLoop(MidiClipData clip) {
    final loopedClip = clip.copyWith(isLooping: !clip.isLooping);
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
  void _startErasing(Offset globalPosition) {
    setState(() {
      isErasing = true;
      erasedAudioClipIds.clear();
      erasedMidiClipIds.clear();
    });
    _eraseClipsAt(globalPosition);
  }

  /// Erase clips at the given position
  void _eraseClipsAt(Offset globalPosition) {
    if (!isErasing) return;

    // Convert global position to local position relative to timeline content
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPosition = box.globalToLocal(globalPosition);

    // Calculate beat position from mouse X
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final beatPosition = (localPosition.dx + scrollOffset) / pixelsPerBeat;

    // Check audio clips
    for (final clip in clips) {
      if (erasedAudioClipIds.contains(clip.clipId)) continue;

      // Convert clip times from seconds to beats for comparison
      final beatsPerSecond = widget.tempo / 60.0;
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;

      // Find track Y position
      final trackIndex = tracks.indexWhere((t) => t.id == clip.trackId);
      if (trackIndex < 0) continue;

      final trackTop = trackIndex * 80.0; // Track height
      final trackBottom = trackTop + 80.0;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          localPosition.dy >= trackTop &&
          localPosition.dy <= trackBottom) {
        erasedAudioClipIds.add(clip.clipId);
        _deleteAudioClip(clip);
      }
    }

    // Check MIDI clips
    for (final midiClip in widget.midiClips) {
      if (erasedMidiClipIds.contains(midiClip.clipId)) continue;

      final clipStartBeats = midiClip.startTime;
      final clipEndBeats = midiClip.startTime + midiClip.duration;

      // Find track Y position
      final trackIndex = tracks.indexWhere((t) => t.id == midiClip.trackId);
      if (trackIndex < 0) continue;

      final trackTop = trackIndex * 80.0;
      final trackBottom = trackTop + 80.0;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          localPosition.dy >= trackTop &&
          localPosition.dy <= trackBottom) {
        erasedMidiClipIds.add(midiClip.clipId);
        widget.onMidiClipDeleted?.call(midiClip.clipId, midiClip.trackId);
      }
    }
  }

  /// Stop eraser mode
  void _stopErasing() {
    if (isErasing) {
      final totalErased = erasedAudioClipIds.length + erasedMidiClipIds.length;
      if (totalErased > 0) {
      }
    }
    setState(() {
      isErasing = false;
      erasedAudioClipIds.clear();
      erasedMidiClipIds.clear();
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
  void _splitAudioClipAtPreview(ClipData clip) {
    if (splitPreviewAudioClipId != clip.clipId) return;

    // Convert beat position back to seconds
    final splitTimeRelative = splitPreviewBeatPosition * (60.0 / widget.tempo);
    final splitTimeAbsolute = clip.startTime + splitTimeRelative;

    // Validate split point is within clip bounds
    if (splitTimeRelative <= 0 || splitTimeRelative >= clip.duration) {
      return;
    }

    // Create left clip (original, shortened)
    final leftClip = clip.copyWith(
      duration: splitTimeRelative,
    );

    // Create right clip (new, starting at split point)
    final rightClipId = DateTime.now().millisecondsSinceEpoch;
    final rightClip = clip.copyWith(
      clipId: rightClipId,
      startTime: splitTimeAbsolute,
      duration: clip.duration - splitTimeRelative,
      offset: clip.offset + splitTimeRelative,
    );

    // Update local state
    setState(() {
      final index = clips.indexWhere((c) => c.clipId == clip.clipId);
      if (index >= 0) {
        clips[index] = leftClip;
        clips.add(rightClip);
      }
    });

    // Update engine for left clip
    widget.audioEngine?.setClipStartTime(clip.trackId, clip.clipId, clip.startTime);

    _clearSplitPreview();
  }

  /// Split MIDI clip at preview position
  void _splitMidiClipAtPreview(MidiClipData clip) {
    if (splitPreviewMidiClipId != clip.clipId) return;

    // Split point in beats relative to clip start
    final splitPointBeats = splitPreviewBeatPosition;

    // Validate split point is within clip bounds
    if (splitPointBeats <= 0 || splitPointBeats >= clip.duration) {
      return;
    }

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

    // Add both new clips (need to call the copy callback twice)
    widget.onMidiClipCopied?.call(leftClip, leftClip.startTime);
    widget.onMidiClipCopied?.call(rightClip, rightClip.startTime);

    _clearSplitPreview();
  }

  /// Split MIDI clip at insert marker position
  void _splitMidiClipAtInsertMarker(MidiClipData clip) {
    if (insertMarkerBeats == null) {
      return;
    }

    // Check if insert marker is within clip bounds
    final markerBeats = insertMarkerBeats!;
    if (markerBeats <= clip.startTime || markerBeats >= clip.endTime) {
      return;
    }

    // Split point in beats relative to clip start
    final splitPointBeats = markerBeats - clip.startTime;

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
  Future<void> _loadTracksAsync() async {
    if (widget.audioEngine == null) return;

    try {
      final trackIds = await Future.microtask(() {
        return widget.audioEngine!.getAllTrackIds();
      });

      final loadedTracks = <TimelineTrackData>[];

      for (final int trackId in trackIds) {
        final info = await Future.microtask(() {
          return widget.audioEngine!.getTrackInfo(trackId);
        });

        final track = TimelineTrackData.fromCSV(info);
        if (track != null) {
          loadedTracks.add(track);
        }
      }

      if (mounted) {
        setState(() {
          tracks = loadedTracks;
        });
      }
    } catch (e) {
      debugPrint('TimelineView: Error loading tracks: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewWidth = MediaQuery.of(context).size.width;

    // Beat-based width calculation (tempo-independent)
    final beatsPerSecond = widget.tempo / 60.0;

    // Minimum 16 bars (64 beats), or extend based on clip duration
    const minBars = 16;
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

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle Delete/Backspace to delete selected MIDI clip
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (widget.selectedMidiClipId != null) {
              // Find the clip to get its track ID
              final clip = widget.midiClips.firstWhere(
                (c) => c.clipId == widget.selectedMidiClipId,
                orElse: () => MidiClipData(clipId: -1, trackId: -1, startTime: 0, duration: 0),
              );
              if (clip.clipId != -1) {
                widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
                return KeyEventResult.handled;
              }
            }
          }

          // Handle Escape to deselect all clips (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _deselectAllClips();
            return KeyEventResult.handled;
          }

          // Cmd+D to duplicate selected clip (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.keyD &&
              (HardwareKeyboard.instance.isMetaPressed ||
               HardwareKeyboard.instance.isControlPressed)) {
            if (widget.selectedMidiClipId != null) {
              final clip = widget.midiClips.firstWhere(
                (c) => c.clipId == widget.selectedMidiClipId,
                orElse: () => MidiClipData(clipId: -1, trackId: -1, startTime: 0, duration: 0),
              );
              if (clip.clipId != -1) {
                _duplicateMidiClip(clip);
                return KeyEventResult.handled;
              }
            }
          }

          // Cmd+A to select all clips (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.keyA &&
              (HardwareKeyboard.instance.isMetaPressed ||
               HardwareKeyboard.instance.isControlPressed)) {
            _selectAllClips();
            return KeyEventResult.handled;
          }

          // Q to quantize selected clip (spec v2.0)
          if (event.logicalKey == LogicalKeyboardKey.keyQ) {
            if (widget.selectedMidiClipId != null) {
              final clip = widget.midiClips.firstWhere(
                (c) => c.clipId == widget.selectedMidiClipId,
                orElse: () => MidiClipData(clipId: -1, trackId: -1, startTime: 0, duration: 0),
              );
              if (clip.clipId != -1) {
                _quantizeMidiClip(clip);
                return KeyEventResult.handled;
              }
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.standard,
          border: Border.all(color: context.colors.elevated),
        ),
        child: Stack(
        children: [
          // Main scrollable area (time ruler + tracks)
          Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                // Check for Cmd (Mac) or Ctrl (Windows/Linux) modifier
                final isModifierPressed =
                    HardwareKeyboard.instance.isMetaPressed ||
                    HardwareKeyboard.instance.isControlPressed;

                if (isModifierPressed) {
                  final scrollDelta = pointerSignal.scrollDelta.dy;
                  setState(() {
                    if (scrollDelta < 0) {
                      // Scroll up = zoom in
                      pixelsPerBeat = (pixelsPerBeat * 1.1).clamp(10.0, 150.0);
                    } else {
                      // Scroll down = zoom out
                      pixelsPerBeat = (pixelsPerBeat / 1.1).clamp(10.0, 150.0);
                    }
                  });
                }
              }
            },
            child: SingleChildScrollView(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    // Time ruler (scrolls with content)
                    _buildTimeRuler(totalWidth, duration),

                    // Timeline tracks area with eraser mode support (Ctrl/Cmd+drag)
                    Expanded(
                      child: Listener(
                        onPointerDown: (event) {
                          // Ctrl/Cmd+click on empty space - no action needed
                        },
                        onPointerMove: (event) {
                          // Ctrl/Cmd+drag = eraser mode
                          if (event.buttons == kPrimaryButton) {
                            final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
                                HardwareKeyboard.instance.isControlPressed;
                            if (isCtrlOrCmd) {
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
                            // Grid lines
                            _buildGrid(totalWidth, duration),

                            // Tracks
                            _buildTracks(totalWidth),

                            // Insert marker (blue dashed line)
                            _buildInsertMarker(),

                            // Playhead
                            _buildPlayhead(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Zoom controls (fixed position, top-right)
          Positioned(
            right: 8,
            top: 4,
            child: _buildZoomControls(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTracks(double width) {
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

    // Separate regular tracks from master
    final regularTracks = tracks.where((t) => t.type != 'Master').toList();
    final masterTrack = tracks.firstWhere(
      (t) => t.type == 'Master',
      orElse: () => TimelineTrackData(id: -1, name: 'Master', type: 'Master'),
    );

    // Count audio and MIDI tracks for numbering
    int audioCount = 0;
    int midiCount = 0;

    return Column(
      children: [
        // Regular tracks
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

          return _buildTrack(
            width,
            track,
            trackColor,
            currentAudioCount,
            currentMidiCount,
          );
        }),

        // Empty space drop target - wraps spacer to push master track to bottom
        // Supports: instruments, VST3 plugins, audio files, AND drag-to-create
        Expanded(
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
            child: PlatformDropTarget(
              onDragDone: (details) {
                // Handle audio file drops
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
                      final isAnyHovering = isInstrumentHovering || isAudioFileDraggingOverEmpty;

                      // Determine label text
                      String dropLabel;
                      if (isAudioFileDraggingOverEmpty) {
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
                            _buildDragToCreatePreview(),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),

        // Master track at bottom
        if (masterTrack.id != -1)
          _buildMasterTrack(width, masterTrack),
      ],
    );
  }

  Widget _buildTimeRuler(double width, double duration) {
    return Stack(
      children: [
        // Base ruler with CustomPaint
        GestureDetector(
          onTapUp: (details) {
            // Click ruler to place insert marker (spec v2.0)
            final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
            final xInContent = details.localPosition.dx + scrollOffset;
            final beats = xInContent / pixelsPerBeat;
            setInsertMarker(beats.clamp(0.0, double.infinity));
          },
          onSecondaryTapUp: (details) {
            // Right-click ruler for context menu
            _showRulerContextMenu(details.globalPosition, details.localPosition);
          },
          child: Container(
            height: 30,
            width: width,
            decoration: BoxDecoration(
              color: context.colors.elevated,
              border: Border(
                bottom: BorderSide(color: context.colors.elevated),
              ),
            ),
            child: CustomPaint(
              painter: TimeRulerPainter(
                pixelsPerBeat: pixelsPerBeat,
                isLoopEnabled: widget.isLoopEnabled,
                loopStartBeats: widget.loopStartBeats,
                loopEndBeats: widget.loopEndBeats,
              ),
            ),
          ),
        ),
        // Loop region drag handles and bar (only visible when loop is enabled)
        if (widget.isLoopEnabled) ...[
          // Loop bar (draggable region between handles) - added first so handles are on top
          _buildLoopBar(),
          // Loop start handle
          _buildLoopHandle(
            beats: widget.loopStartBeats,
            isStart: true,
            onDrag: (newBeats) {
              // Clamp to not go past loop end
              final clampedBeats = newBeats.clamp(0.0, widget.loopEndBeats - 1.0);
              widget.onLoopRegionChanged?.call(clampedBeats, widget.loopEndBeats);
            },
          ),
          // Loop end handle
          _buildLoopHandle(
            beats: widget.loopEndBeats,
            isStart: false,
            onDrag: (newBeats) {
              // Clamp to not go before loop start
              final clampedBeats = newBeats.clamp(widget.loopStartBeats + 1.0, double.infinity);
              widget.onLoopRegionChanged?.call(widget.loopStartBeats, clampedBeats);
            },
          ),
        ],
      ],
    );
  }

  /// Build a draggable handle for loop region start or end
  Widget _buildLoopHandle({
    required double beats,
    required bool isStart,
    required Function(double) onDrag,
  }) {
    final handleX = beats * pixelsPerBeat;
    const handleWidth = 12.0;
    const loopColor = Color(0xFFF97316);

    return Positioned(
      left: isStart ? handleX - handleWidth / 2 : handleX - handleWidth / 2,
      top: 0,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          // Calculate new beat position from drag
          final newX = handleX + details.delta.dx;
          final newBeats = newX / pixelsPerBeat;
          onDrag(newBeats);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Container(
            width: handleWidth,
            height: 30,
            decoration: BoxDecoration(
              color: loopColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: loopColor, width: 1),
            ),
            child: Center(
              child: Icon(
                isStart ? Icons.chevron_left : Icons.chevron_right,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build a draggable bar for moving the entire loop region
  Widget _buildLoopBar() {
    final loopStartX = widget.loopStartBeats * pixelsPerBeat;
    final loopEndX = widget.loopEndBeats * pixelsPerBeat;
    final loopWidth = loopEndX - loopStartX;
    final loopDuration = widget.loopEndBeats - widget.loopStartBeats;
    const loopColor = Color(0xFFF97316);
    const handleWidth = 12.0;

    // Only show bar if there's enough width (handles take 12px each)
    if (loopWidth <= handleWidth * 2) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: loopStartX + handleWidth / 2,
      top: 0,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          // Calculate new start position from drag delta
          final deltaBeats = details.delta.dx / pixelsPerBeat;
          final newStart = (widget.loopStartBeats + deltaBeats).clamp(0.0, double.infinity);
          final newEnd = newStart + loopDuration;
          widget.onLoopRegionChanged?.call(newStart, newEnd);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Container(
            width: loopWidth - handleWidth,
            height: 30,
            decoration: BoxDecoration(
              color: loopColor.withValues(alpha: 0.3),
              border: const Border(
                top: BorderSide(color: loopColor, width: 3),
              ),
            ),
            child: Center(
              child: Icon(
                Icons.drag_indicator,
                size: 14,
                color: loopColor.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.elevated.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                pixelsPerBeat = (pixelsPerBeat - 10).clamp(10.0, 150.0);
              });
            },
            icon: const Icon(Icons.remove, size: 14),
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: context.colors.textSecondary,
            tooltip: 'Zoom out (Cmd -)',
          ),
          Text(
            '${pixelsPerBeat.toInt()}',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                pixelsPerBeat = (pixelsPerBeat + 10).clamp(10.0, 150.0);
              });
            },
            icon: const Icon(Icons.add, size: 14),
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: context.colors.textSecondary,
            tooltip: 'Zoom in (Cmd +)',
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(double width, double duration) {
    return CustomPaint(
      size: Size(width, double.infinity),
      painter: TimelineGridPainter(
        pixelsPerBeat: pixelsPerBeat,
      ),
    );
  }

  Widget _buildTrack(
    double width,
    TimelineTrackData track,
    Color trackColor,
    int audioCount,
    int midiCount,
  ) {
    // Find clips for this track
    final trackClips = clips.where((c) => c.trackId == track.id).toList();
    final trackMidiClips = widget.midiClips.where((c) => c.trackId == track.id).toList();
    final isHovered = dragHoveredTrackId == track.id;
    final isMidiTrack = track.type.toLowerCase() == 'midi';

    // Wrap with VST3Plugin drag target first
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
            setState(() {
              dragHoveredTrackId = track.id;
            });
          },
          onDragExited: (details) {
            setState(() {
              dragHoveredTrackId = null;
              previewClip = null;
            });
          },
          onDragUpdated: (details) {
            // Update preview position
            const fileName = 'Preview'; // We don't have filename yet
            final startTime = _calculateTimelinePosition(details.localPosition);

            setState(() {
              previewClip = PreviewClip(
                fileName: fileName,
                startTime: startTime,
                trackId: track.id,
                mousePosition: details.localPosition,
              );
            });
          },
          onDragDone: (details) async {
            await _handleFileDrop(details.files, track.id, details.localPosition);
          },
          child: GestureDetector(
        onTapUp: (details) {
          // Place insert marker at click position on empty space (spec v2.0)
          final beatPosition = _calculateBeatPosition(details.localPosition);
          final isOnClip = _isPositionOnClip(beatPosition, track.id, trackClips, trackMidiClips);

          if (!isOnClip) {
            setInsertMarker(beatPosition);
          }

          // Select track if it's a MIDI track
          if (isMidiTrack) {
            widget.onMidiTrackSelected?.call(track.id);
          }
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
          // Check if drag starts on empty space (not on a clip)
          final beatPosition = _calculateBeatPosition(details.localPosition);
          final isOnClip = _isPositionOnClip(beatPosition, track.id, trackClips, trackMidiClips);

          if (!isOnClip && isMidiTrack) {
            // Start drag-to-create on this track
            setState(() {
              isDraggingNewClip = true;
              newClipStartBeats = _snapToGrid(beatPosition);
              newClipEndBeats = newClipStartBeats;
              newClipTrackId = track.id;
            });
          }
        },
        onHorizontalDragUpdate: (details) {
          if (isDraggingNewClip && newClipTrackId == track.id) {
            final currentBeats = _calculateBeatPosition(details.localPosition);
            setState(() {
              newClipEndBeats = _snapToGrid(currentBeats);
            });
          }
        },
        onHorizontalDragEnd: (details) {
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
        height: widget.trackHeights[track.id] ?? 100.0,
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
              painter: _GridPatternPainter(),
            ),

            // Render audio clips for this track
            ...trackClips.map((clip) => _buildClip(clip, trackColor, widget.trackHeights[track.id] ?? 100.0)),

            // Render MIDI clips for this track
            ...trackMidiClips.map((midiClip) => _buildMidiClip(
                  midiClip,
                  trackColor,
                  widget.trackHeights[track.id] ?? 100.0,
                )),

            // Stamp copy ghost previews for Alt+drag
            ...trackMidiClips
                .where((midiClip) => draggingMidiClipId == midiClip.clipId && isCopyDrag && stampCopyCount > 0)
                .expand((midiClip) => _buildStampCopyPreviews(midiClip, trackColor, widget.trackHeights[track.id] ?? 100.0)),

            // Show preview clip if hovering over this track
            if (previewClip != null && previewClip!.trackId == track.id)
              _buildPreviewClip(previewClip!),

            // Drag-to-create preview for this track
            if (isDraggingNewClip && newClipTrackId == track.id)
              _buildDragToCreatePreviewOnTrack(trackColor, widget.trackHeights[track.id] ?? 100.0),
          ],
        ),
      ),
    ),
        );
          },
        );
      },
    );
  }

  Widget _buildMasterTrack(double width, TimelineTrackData track) {
    const headerHeight = 18.0;

    return Container(
      height: widget.masterTrackHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colors.hover,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Track header bar (fully opaque)
          Container(
            height: headerHeight,
            color: TrackColors.masterColor,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(
                  '🎚️ Master',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Content area (transparent, shows grid)
          Expanded(
            child: CustomPaint(
              painter: _GridPatternPainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClip(ClipData clip, Color trackColor, double trackHeight) {
    final clipWidth = clip.duration * pixelsPerSecond;
    // Use dragged position if this clip is being dragged
    final displayStartTime = draggingClipId == clip.clipId
        ? dragStartTime + (dragCurrentX - dragStartX) / pixelsPerSecond
        : clip.startTime;
    final clipX = displayStartTime.clamp(0.0, double.infinity) * pixelsPerSecond;
    final isDragging = draggingClipId == clip.clipId;
    final isSelected = selectedAudioClipIds.contains(clip.clipId);
    final isMultiSelected = selectedAudioClipIds.length > 1 && isSelected;

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 8.0; // Track height minus padding

    // Check if this clip has split preview active
    final hasSplitPreview = splitPreviewAudioClipId == clip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (splitPreviewBeatPosition / (clip.duration * (widget.tempo / 60.0))) * clipWidth
        : 0.0;

    return Positioned(
      left: clipX,
      top: 4,
      child: GestureDetector(
        onTapDown: (details) {
          // Ctrl/Cmd+click: delete clip immediately
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) {
            _deleteAudioClip(clip);
            return;
          }

          // Alt+click: split at hover position
          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
          if (isAltPressed && hasSplitPreview) {
            _splitAudioClipAtPreview(clip);
            return;
          }
        },
        onTapUp: (details) {
          // Skip if Ctrl/Cmd was pressed (delete handled in onTapDown)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          // Skip if Alt was pressed (split handled in onTapDown)
          if (HardwareKeyboard.instance.isAltPressed) return;

          // Shift+click = toggle selection (spec v2.0)
          final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

          selectAudioClipMulti(
            clip.clipId,
            addToSelection: false,
            toggleSelection: isShiftPressed,
          );
          // Deselect any MIDI clip (notify parent)
          widget.onMidiClipSelected?.call(null, null);

          // Place insert marker at click position (spec v2.0)
          // Convert local X position in clip to global beats
          final clickXInClip = details.localPosition.dx;
          final clickSeconds = clip.startTime + (clickXInClip / pixelsPerSecond);
          final beatsPerSecond = widget.tempo / 60.0;
          final clickBeats = clickSeconds * beatsPerSecond;
          setInsertMarker(clickBeats.clamp(0.0, double.infinity));
        },
        onSecondaryTapDown: (details) {
          // Right-click: show context menu
          _showAudioClipContextMenu(details.globalPosition, clip);
        },
        onHorizontalDragStart: (details) {
          // Skip if Ctrl/Cmd is held (eraser mode)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          // Check if this clip is in the multi-selection
          final isInMultiSelection = selectedAudioClipIds.contains(clip.clipId);

          setState(() {
            // If not in multi-selection, select just this clip
            if (!isInMultiSelection) {
              selectedAudioClipIds.clear();
              selectedAudioClipIds.add(clip.clipId);
            }
            selectedAudioClipId = clip.clipId;
            draggingClipId = clip.clipId;
            dragStartTime = clip.startTime;
            dragStartX = details.globalPosition.dx;
            dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragUpdate: (details) {
          // Skip if Ctrl/Cmd is held (eraser mode)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          setState(() {
            dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragEnd: (details) {
          if (draggingClipId == null) return;

          // Calculate final position and persist to engine
          final newStartTime = (dragStartTime + (dragCurrentX - dragStartX) / pixelsPerSecond)
              .clamp(0.0, double.infinity);
          widget.audioEngine?.setClipStartTime(clip.trackId, clip.clipId, newStartTime);
          // Update local state
          setState(() {
            final index = clips.indexWhere((c) => c.clipId == clip.clipId);
            if (index >= 0) {
              clips[index] = clips[index].copyWith(startTime: newStartTime);
            }
            draggingClipId = null;
          });
        },
        child: MouseRegion(
          cursor: trimmingAudioClipId == clip.clipId
              ? (isTrimmingLeftEdge ? SystemMouseCursors.resizeLeft : SystemMouseCursors.resizeRight)
              : (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)
                  ? SystemMouseCursors.forbidden // Ctrl/Cmd = delete
                  : HardwareKeyboard.instance.isAltPressed
                      ? SystemMouseCursors.copy // Alt = duplicate
                      : SystemMouseCursors.grab,
          onHover: (event) {
            // Track hover position for split preview (only when Alt is pressed - but Alt is now duplicate)
            // Keep split preview disabled for now, we'll use a different approach later
          },
          onExit: (_) {
            if (splitPreviewAudioClipId == clip.clipId) {
              _clearSplitPreview();
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main clip container
              Container(
                width: clipWidth,
                height: totalHeight,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected
                        ? (isMultiSelected ? context.colors.accent : context.colors.textPrimary) // Accent for multi, primary for single
                        : isDragging
                            ? trackColor
                            : trackColor.withValues(alpha: 0.7),
                    width: isSelected || isDragging ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    // Header with track color
                    Container(
                      height: headerHeight,
                      decoration: BoxDecoration(
                        color: trackColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
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
                      ),
                    ),
                    // Content area with waveform (transparent background)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(3),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return CustomPaint(
                              size: Size(constraints.maxWidth, constraints.maxHeight),
                              painter: _WaveformPainter(
                                peaks: clip.waveformPeaks,
                                color: TrackColors.getLighterShade(trackColor),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
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
                    newStartTime = newStartTime.clamp(0.0, audioTrimStartTime + audioTrimStartDuration - 0.1);
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
                  onHorizontalDragEnd: (details) {
                    // Persist to engine
                    final trimmedClip = clips.firstWhere((c) => c.clipId == clip.clipId, orElse: () => clip);
                    widget.audioEngine?.setClipStartTime(trimmedClip.trackId, trimmedClip.clipId, trimmedClip.startTime);
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
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
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
                    newDuration = newDuration.clamp(0.1, double.infinity);

                    setState(() {
                      final index = clips.indexWhere((c) => c.clipId == clip.clipId);
                      if (index >= 0) {
                        clips[index] = clips[index].copyWith(duration: newDuration);
                      }
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      trimmingAudioClipId = null;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRight,
                    child: Container(
                      width: 8,
                      height: totalHeight,
                      color: Colors.transparent,
                    ),
                  ),
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
          ),
        ),
      ),
    );
  }

  /// Build ghost preview widgets for stamp copies during Alt+drag
  List<Widget> _buildStampCopyPreviews(MidiClipData sourceClip, Color trackColor, double trackHeight) {
    final previews = <Widget>[];
    final clipWidth = sourceClip.duration * pixelsPerBeat;
    final totalHeight = trackHeight - 8.0;

    for (int i = 1; i <= stampCopyCount; i++) {
      final copyStartBeats = sourceClip.startTime + (i * stampCopySourceDuration);
      final copyX = copyStartBeats * pixelsPerBeat;

      previews.add(
        Positioned(
          left: copyX,
          top: 4,
          child: IgnorePointer(
            child: Container(
              width: clipWidth,
              height: totalHeight,
              decoration: BoxDecoration(
                color: trackColor.withValues(alpha: 0.3),
                border: Border.all(
                  color: trackColor.withValues(alpha: 0.6),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '+$i',
                  style: TextStyle(
                    color: trackColor.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return previews;
  }

  Widget _buildMidiClip(MidiClipData midiClip, Color trackColor, double trackHeight) {
    // MIDI clips use beat-based positioning (tempo-independent visual layout)
    final clipStartBeats = midiClip.startTime;
    final clipDurationBeats = midiClip.duration;
    final clipWidth = clipDurationBeats * pixelsPerBeat;

    // Use dragged position if this clip is being dragged (with snap preview)
    double displayStartBeats;
    if (draggingMidiClipId == midiClip.clipId) {
      final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;
      var draggedBeats = clipStartBeats + dragDeltaBeats;
      draggedBeats = draggedBeats.clamp(0.0, double.infinity);
      // Snap to beat grid
      final snapResolution = _getGridSnapResolution();
      displayStartBeats = (draggedBeats / snapResolution).round() * snapResolution;
    } else {
      displayStartBeats = clipStartBeats;
    }
    final clipX = displayStartBeats * pixelsPerBeat;

    // Use both widget prop (single) and internal multi-selection
    final isSelected = widget.selectedMidiClipId == midiClip.clipId || selectedMidiClipIds.contains(midiClip.clipId);
    final isMultiSelected = selectedMidiClipIds.length > 1 && selectedMidiClipIds.contains(midiClip.clipId);
    final isDragging = draggingMidiClipId == midiClip.clipId;

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 8.0; // Track height minus padding

    // Check if this clip has split preview active
    final hasSplitPreview = splitPreviewMidiClipId == midiClip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (splitPreviewBeatPosition / midiClip.duration) * clipWidth
        : 0.0;

    return Positioned(
      left: clipX,
      top: 4,
      child: GestureDetector(
        onTapDown: (details) {
          // Ctrl/Cmd+click: delete clip immediately
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) {
            widget.onMidiClipDeleted?.call(midiClip.clipId, midiClip.trackId);
            return;
          }

          // Alt+click: split at hover position
          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
          if (isAltPressed && hasSplitPreview) {
            _splitMidiClipAtPreview(midiClip);
            return;
          }
        },
        onTapUp: (details) {
          // Skip if Ctrl/Cmd was pressed (delete handled in onTapDown)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          // Skip if Alt was pressed (split handled in onTapDown)
          if (HardwareKeyboard.instance.isAltPressed) return;

          // Shift+click = toggle selection (spec v2.0)
          final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

          selectMidiClipMulti(
            midiClip.clipId,
            addToSelection: false,
            toggleSelection: isShiftPressed,
          );

          // Notify parent about selection (for piano roll, use primary selection)
          if (!isShiftPressed || selectedMidiClipIds.contains(midiClip.clipId)) {
            widget.onMidiClipSelected?.call(midiClip.clipId, midiClip);
          } else if (selectedMidiClipIds.isEmpty) {
            widget.onMidiClipSelected?.call(null, null);
          }

          // Place insert marker at click position (spec v2.0)
          final clickXInClip = details.localPosition.dx;
          final clickBeats = midiClip.startTime + (clickXInClip / pixelsPerBeat);
          setInsertMarker(clickBeats.clamp(0.0, double.infinity));
        },
        onSecondaryTapDown: (details) {
          _showMidiClipContextMenu(details.globalPosition, midiClip);
        },
        onHorizontalDragStart: (details) {
          // Check if Ctrl/Cmd is held (eraser mode - don't start drag)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          // Check if this clip is in the multi-selection
          final isInMultiSelection = selectedMidiClipIds.contains(midiClip.clipId);
          // Alt+drag = duplicate (spec v2.0)
          final isDuplicate = HardwareKeyboard.instance.isAltPressed;
          setState(() {
            // If not in multi-selection, select just this clip
            if (!isInMultiSelection) {
              selectedMidiClipIds.clear();
              selectedMidiClipIds.add(midiClip.clipId);
            }
            draggingMidiClipId = midiClip.clipId;
            midiDragStartTime = midiClip.startTime;
            midiDragStartX = details.globalPosition.dx;
            midiDragCurrentX = details.globalPosition.dx;
            isCopyDrag = isDuplicate; // Alt = duplicate
            // Store source clip duration for stamp copies
            stampCopySourceDuration = midiClip.duration;
            stampCopyCount = 0;
          });
        },
        onHorizontalDragUpdate: (details) {
          // Skip if Ctrl/Cmd is held (eraser mode)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          // Shift bypasses snap (spec v2.0)
          final bypassSnap = HardwareKeyboard.instance.isShiftPressed;

          // Calculate stamp copy count for Alt+drag (spec v2.0)
          int stampCount = 0;
          if (isCopyDrag && stampCopySourceDuration > 0) {
            final dragDeltaBeats = (details.globalPosition.dx - midiDragStartX) / pixelsPerBeat;
            // Only stamp copies when dragging forward past the clip's own length
            if (dragDeltaBeats > stampCopySourceDuration) {
              stampCount = (dragDeltaBeats / stampCopySourceDuration).floor();
            }
          }

          setState(() {
            midiDragCurrentX = details.globalPosition.dx;
            snapBypassActive = bypassSnap;
            stampCopyCount = stampCount;
          });
        },
        onHorizontalDragEnd: (details) {
          if (draggingMidiClipId == null) return;

          // Calculate final position with beat-based snapping
          final startBeats = midiDragStartTime;
          final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;
          var newStartBeats = (startBeats + dragDeltaBeats).clamp(0.0, double.infinity);

          // Snap to beat grid (unless Shift bypasses snap)
          if (!snapBypassActive) {
            final snapResolution = _getGridSnapResolution();
            newStartBeats = (newStartBeats / snapResolution).round() * snapResolution;
          }

          if (isCopyDrag) {
            // Alt+drag: create stamp copies (spec v2.0)
            if (stampCopyCount > 0) {
              // Create multiple stamp copies at regular intervals
              for (int i = 1; i <= stampCopyCount; i++) {
                final copyStartBeats = midiClip.startTime + (i * stampCopySourceDuration);
                widget.onMidiClipCopied?.call(midiClip, copyStartBeats);
              }
            } else {
              // Single copy at new position
              widget.onMidiClipCopied?.call(midiClip, newStartBeats);
            }
          } else {
            // Move: update existing clip position
            final beatsPerSecond = widget.tempo / 60.0;
            final newStartTimeSeconds = newStartBeats / beatsPerSecond;
            final rustClipId = widget.getRustClipId?.call(midiClip.clipId) ?? midiClip.clipId;
            widget.audioEngine?.setClipStartTime(midiClip.trackId, rustClipId, newStartTimeSeconds);
            final updatedClip = midiClip.copyWith(startTime: newStartBeats);
            widget.onMidiClipUpdated?.call(updatedClip);
          }

          setState(() {
            draggingMidiClipId = null;
            isCopyDrag = false;
            snapBypassActive = false;
            stampCopyCount = 0;
          });
        },
        child: MouseRegion(
          cursor: resizingMidiClipId == midiClip.clipId
              ? SystemMouseCursors.resizeRight
              : (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)
                  ? SystemMouseCursors.forbidden // Ctrl/Cmd = delete
                  : HardwareKeyboard.instance.isAltPressed
                      ? SystemMouseCursors.copy // Alt = duplicate
                      : SystemMouseCursors.grab,
          onHover: (event) {
            // Track hover position for split preview (only when Alt is pressed)
            if (HardwareKeyboard.instance.isAltPressed) {
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
              // Main clip container
              Container(
                width: clipWidth,
                height: totalHeight,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDragging
                        ? trackColor
                        : isSelected
                            ? (isMultiSelected ? context.colors.accent : context.colors.textPrimary) // Accent for multi, primary for single
                            : trackColor.withValues(alpha: 0.7),
                    width: isDragging || isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      height: headerHeight,
                      decoration: BoxDecoration(
                        color: trackColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
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
                      ),
                    ),
                    // Content area with notes (transparent background)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(3),
                        ),
                        child: midiClip.notes.isNotEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  return CustomPaint(
                                    size: Size(constraints.maxWidth, constraints.maxHeight),
                                    painter: _MidiClipPainter(
                                      notes: midiClip.notes,
                                      clipDuration: clipDurationBeats,
                                      loopLength: midiClip.loopLength,
                                      trackColor: trackColor,
                                    ),
                                  );
                                },
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
              // Loop boundary lines overlay
              if (clipDurationBeats > midiClip.loopLength)
                _buildLoopBoundaryLines(midiClip.loopLength, clipDurationBeats, totalHeight, trackColor),
              // Left edge trim handle
              Positioned(
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
                    newStartTime = newStartTime.clamp(0.0, trimStartTime + trimStartDuration - 1.0);

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
              // Right edge resize handle
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
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

                    final updatedClip = midiClip.copyWith(duration: newDuration);
                    widget.onMidiClipUpdated?.call(updatedClip);
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      resizingMidiClipId = null;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRight,
                    child: Container(
                      width: 8,
                      height: totalHeight,
                      color: Colors.transparent,
                    ),
                  ),
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
          ),
        ),
      ),
    );
  }

  /// Build loop boundary lines for when arrangement > loop length
  Widget _buildLoopBoundaryLines(double loopLength, double clipDuration, double height, Color trackColor) {
    final List<Widget> lines = [];
    var loopBeat = loopLength;

    while (loopBeat < clipDuration) {
      final lineX = loopBeat * pixelsPerBeat;
      lines.add(
        Positioned(
          left: lineX,
          top: 0,
          child: Container(
            width: 1,
            height: height,
            color: trackColor.withValues(alpha: 0.4),
          ),
        ),
      );
      loopBeat += loopLength;
    }

    return Stack(children: lines);
  }

  Widget _buildPreviewClip(PreviewClip preview) {
    const previewDuration = 3.0; // seconds (placeholder)
    final clipWidth = previewDuration * pixelsPerSecond;
    final clipX = preview.startTime * pixelsPerSecond;

    return Positioned(
      left: clipX,
      top: 4,
      child: Container(
        width: clipWidth,
        height: 72,
        decoration: BoxDecoration(
          color: context.colors.success.withValues(alpha: 0.3),
          border: Border.all(
            color: context.colors.success,
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Icon(
            Icons.audiotrack,
            color: context.colors.success.withValues(alpha: 0.6),
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayhead() {
    final playheadX = widget.playheadPosition * pixelsPerSecond;
    // Playhead color: blue per spec (#3B82F6)
    const playheadColor = Color(0xFF3B82F6);

    return Positioned(
      left: playheadX - 10, // Center the 20px wide handle on the playhead position
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          // Calculate new position from drag delta
          final newX = (playheadX + details.delta.dx).clamp(0.0, double.infinity);
          final newPosition = newX / pixelsPerSecond;

          // Clamp to valid range (0 to project duration)
          final maxDuration = widget.clipDuration ?? 300.0; // Default to 5 minutes if no clip
          final clampedPosition = newPosition.clamp(0.0, maxDuration);

          widget.onSeek?.call(clampedPosition);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: SizedBox(
            width: 20, // Hit area width
            child: Column(
              children: [
                // Playhead handle
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: playheadColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.colors.textPrimary, width: 2),
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    size: 12,
                    color: context.colors.textPrimary,
                  ),
                ),
                // Playhead line
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: playheadColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the insert marker (blue dashed line, separate from playhead)
  /// Used for split operations (Cmd+E) and paste location
  Widget _buildInsertMarker() {
    if (insertMarkerBeats == null) return const SizedBox.shrink();

    final markerX = insertMarkerBeats! * pixelsPerBeat;

    return Positioned(
      left: markerX - 1, // Center the 2px line
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          child: CustomPaint(
            painter: DashedLinePainter(
              color: context.colors.accent, // Accent color for insert marker
              strokeWidth: 2,
              dashLength: 6,
              gapLength: 4,
            ),
          ),
        ),
      ),
    );
  }

  /// Set insert marker position (in beats)
  void setInsertMarker(double? beats) {
    setState(() {
      insertMarkerBeats = beats;
    });
  }

  /// Get insert marker position in seconds (for split operations)
  double? getInsertMarkerSeconds() {
    if (insertMarkerBeats == null) return null;
    final beatsPerSecond = widget.tempo / 60.0;
    return insertMarkerBeats! / beatsPerSecond;
  }

  /// Build the drag-to-create preview rectangle
  Widget _buildDragToCreatePreview() {
    // Calculate positions (handle reverse drag)
    final startBeats = math.min(newClipStartBeats, newClipEndBeats);
    final endBeats = math.max(newClipStartBeats, newClipEndBeats);
    final durationBeats = endBeats - startBeats;

    // Convert to pixels
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final startX = (startBeats * pixelsPerBeat) - scrollOffset;
    final width = durationBeats * pixelsPerBeat;

    // Calculate bars for label
    final bars = durationBeats / 4.0;
    final barsLabel = bars >= 1.0
        ? '${bars.toStringAsFixed(bars == bars.roundToDouble() ? 0 : 1)} bar${bars != 1.0 ? 's' : ''}'
        : '${durationBeats.toStringAsFixed(1)} beats';

    return Positioned(
      left: startX,
      top: 8,
      child: Container(
        width: math.max(width, 20.0),
        height: 60,
        decoration: BoxDecoration(
          color: context.colors.success.withValues(alpha: 0.3),
          border: Border.all(
            color: context.colors.success,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            barsLabel,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
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

  /// Build drag-to-create preview for an existing track
  Widget _buildDragToCreatePreviewOnTrack(Color trackColor, double trackHeight) {
    // Calculate positions (handle reverse drag)
    final startBeats = math.min(newClipStartBeats, newClipEndBeats);
    final endBeats = math.max(newClipStartBeats, newClipEndBeats);
    final durationBeats = endBeats - startBeats;

    // Convert to pixels
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final startX = (startBeats * pixelsPerBeat) - scrollOffset;
    final width = durationBeats * pixelsPerBeat;

    // Calculate bars for label
    final bars = durationBeats / 4.0;
    final barsLabel = bars >= 1.0
        ? '${bars.toStringAsFixed(bars == bars.roundToDouble() ? 0 : 1)} bar${bars != 1.0 ? 's' : ''}'
        : '${durationBeats.toStringAsFixed(1)} beats';

    return Positioned(
      left: startX,
      top: 4,
      child: Container(
        width: math.max(width, 20.0),
        height: trackHeight - 8,
        decoration: BoxDecoration(
          color: trackColor.withValues(alpha: 0.3),
          border: Border.all(
            color: trackColor,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            barsLabel,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

}

/// Painter for the waveform
class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final Color color;

  _WaveformPainter({
    required this.peaks,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.5) // Semi-transparent so grid shows through
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerY = size.height / 2;
    final pixelsPerPeak = size.width / (peaks.length / 2);

    path.moveTo(0, centerY);

    // Draw waveform (peaks come as min/max pairs)
    for (int i = 0; i < peaks.length; i += 2) {
      if (i + 1 >= peaks.length) break;

      final x = (i / 2) * pixelsPerPeak;
      final max = peaks[i + 1];

      final maxY = centerY + (max * centerY);

      if (i == 0) {
        path.moveTo(x, maxY);
      } else {
        path.lineTo(x, maxY);
      }
    }

    // Draw bottom half
    for (int i = peaks.length - 2; i >= 0; i -= 2) {
      final x = (i / 2) * pixelsPerPeak;
      final min = peaks[i];
      final minY = centerY + (min * centerY);
      path.lineTo(x, minY);
    }

    path.close();
    canvas.drawPath(path, paint);

    // Draw center line
    final centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      centerLinePaint,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks || oldDelegate.color != color;
  }
}

/// Painter for grid pattern in track background
class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Empty - grid lines are drawn by the main grid painter
  }

  @override
  bool shouldRepaint(_GridPatternPainter oldDelegate) => false;
}

/// Painter for mini MIDI clip preview with dynamic height based on note range
/// Height formula:
/// - Range 1-8 semitones: height = range × 12.5% of content area
/// - Range 9+: Full height (100%), notes compress to fit
class _MidiClipPainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double clipDuration; // Total clip duration in beats (arrangement length)
  final double loopLength; // Loop length in beats
  final Color trackColor;

  _MidiClipPainter({
    required this.notes,
    required this.clipDuration,
    required this.loopLength,
    required this.trackColor,
  });

  /// Get lighter shade of track color for notes
  Color _getLighterColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + 0.3).clamp(0.0, 0.85)).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || clipDuration == 0) return;

    // Find note range for vertical scaling
    final minNote = notes.map((n) => n.note).reduce(math.min);
    final maxNote = notes.map((n) => n.note).reduce(math.max);
    final noteRange = maxNote - minNote + 1;

    // Calculate dynamic height based on note range
    // Range 1-8: 12.5% per semitone, Range 9+: full height with compression
    final double heightPercentage;
    final double noteSlotHeight;

    if (noteRange <= 8) {
      heightPercentage = noteRange * 0.125;
      noteSlotHeight = size.height * 0.125;
    } else {
      heightPercentage = 1.0;
      noteSlotHeight = size.height / noteRange;
    }

    final usedHeight = size.height * heightPercentage;
    final topOffset = size.height - usedHeight; // Anchor notes to bottom

    // Calculate pixels per beat
    final pixelsPerBeat = size.width / clipDuration;

    // Use lighter shade of track color for notes
    final noteColor = _getLighterColor(trackColor);
    final notePaint = Paint()
      ..color = noteColor
      ..style = PaintingStyle.fill;

    // Draw notes
    for (final note in notes) {
      final noteStartBeats = note.startTime;
      final noteDurationBeats = note.duration;

      final x = noteStartBeats * pixelsPerBeat;
      var width = noteDurationBeats * pixelsPerBeat;

      // Calculate Y position based on note's position in range
      final notePosition = note.note - minNote;
      final y = topOffset + (usedHeight - (notePosition + 1) * noteSlotHeight);
      final height = noteSlotHeight - 1; // 1px gap between notes

      // Skip notes that would start beyond the clip
      if (x >= size.width) continue;

      // Clip width to not exceed the clip boundary
      if (x + width > size.width) {
        width = size.width - x;
      }

      // Draw note rectangle with slight rounding
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, math.max(width, 2.0), math.max(height, 2.0)),
        const Radius.circular(2),
      );

      canvas.drawRRect(rect, notePaint);
    }
  }

  @override
  bool shouldRepaint(_MidiClipPainter oldDelegate) {
    return !listEquals(notes, oldDelegate.notes) ||
           clipDuration != oldDelegate.clipDuration ||
           trackColor != oldDelegate.trackColor;
  }
}

