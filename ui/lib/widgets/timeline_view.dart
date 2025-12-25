import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerScrollEvent, kPrimaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'dart:math' as math;
import 'dart:async';
import 'package:cross_file/cross_file.dart';
import '../audio_engine.dart';
import '../utils/track_colors.dart';
import '../models/clip_data.dart';
import '../models/midi_note_data.dart';
import '../models/vst3_plugin_data.dart';
import 'instrument_browser.dart';
import 'platform_drop_target.dart';

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
  });

  @override
  State<TimelineView> createState() => TimelineViewState();
}

class TimelineViewState extends State<TimelineView> {
  final ScrollController _scrollController = ScrollController();
  double _pixelsPerBeat = 25.0; // Zoom level (beat-based, tempo-independent)
  List<TimelineTrackData> _tracks = [];
  Timer? _refreshTimer;

  // Clip management
  List<ClipData> _clips = [];
  PreviewClip? _previewClip;
  int? _dragHoveredTrackId;
  bool _isAudioFileDraggingOverEmpty = false;

  // Drag-to-move state for audio clips
  int? _draggingClipId;
  double _dragStartTime = 0.0;
  double _dragStartX = 0.0;
  double _dragCurrentX = 0.0;

  // Drag-to-move state for MIDI clips
  int? _draggingMidiClipId;
  double _midiDragStartTime = 0.0;
  double _midiDragStartX = 0.0;
  double _midiDragCurrentX = 0.0;

  // Snap and copy state
  bool _snapBypassActive = false; // True when Alt/Option held during drag
  bool _isCopyDrag = false; // True when Alt held at drag start

  // Stamp copy state (Alt+drag creates repeated copies when extended)
  double _stampCopySourceDuration = 0.0; // Duration of source clip (in beats for MIDI, seconds for audio)
  int _stampCopyCount = 0; // Number of stamp copies to create (calculated during drag)

  // Edge resize state for MIDI clips (arrangement length - right edge)
  int? _resizingMidiClipId;
  double _resizeStartDuration = 0.0;
  double _resizeStartX = 0.0;

  // Left edge trim state for MIDI clips
  int? _trimmingMidiClipId;
  double _trimStartTime = 0.0; // Clip start time at trim begin
  double _trimStartDuration = 0.0; // Clip duration at trim begin
  double _trimStartX = 0.0; // Mouse X at trim begin

  // Audio clip selection state (single selection, deprecated - use multi-select)
  int? _selectedAudioClipId;

  // Multi-selection state for clips
  final Set<int> _selectedMidiClipIds = {};
  final Set<int> _selectedAudioClipIds = {};

  // Audio clip trim state (left and right edges)
  int? _trimmingAudioClipId;
  bool _isTrimmingLeftEdge = false;
  double _audioTrimStartTime = 0.0; // Clip start time at trim begin
  double _audioTrimStartDuration = 0.0; // Clip duration at trim begin
  double _audioTrimStartOffset = 0.0; // Clip offset at trim begin
  double _audioTrimStartX = 0.0; // Mouse X at trim begin

  // Drag-to-create new clip state
  bool _isDraggingNewClip = false;
  double _newClipStartBeats = 0.0;
  double _newClipEndBeats = 0.0;
  int? _newClipTrackId; // null = create new track, otherwise create clip on existing track

  // Eraser mode state (right-click drag to delete multiple clips)
  bool _isErasing = false;
  final Set<int> _erasedAudioClipIds = {};
  final Set<int> _erasedMidiClipIds = {};

  // Split preview state (hover shows vertical line, Alt+click splits)
  int? _splitPreviewAudioClipId;
  int? _splitPreviewMidiClipId;
  double _splitPreviewBeatPosition = 0.0; // Position within clip bounds (in beats)

  // Insert marker state (separate from playhead, for split/paste operations)
  double? _insertMarkerBeats; // Position in beats (null = not visible)

  // Clipboard state for copy/paste operations
  MidiClipData? _clipboardMidiClip;

  @override
  void initState() {
    super.initState();
    _loadTracksAsync();

    // Refresh tracks every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
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
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Get pixels per second (derived from pixelsPerBeat and tempo)
  /// Used for time-based positioning (audio clips, playhead)
  double get _pixelsPerSecond {
    final beatsPerSecond = widget.tempo / 60.0;
    return _pixelsPerBeat * beatsPerSecond;
  }

  /// Calculate timeline position from mouse X coordinate
  double _calculateTimelinePosition(Offset localPosition) {
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final totalX = localPosition.dx + scrollOffset;
    return totalX / _pixelsPerSecond;
  }

  /// Get grid snap resolution in beats based on zoom level
  /// Matches _GridPainter._getGridDivision for consistent snapping
  double _getGridSnapResolution() {
    if (_pixelsPerBeat < 10) return 4.0;     // Snap to bars (every 4 beats)
    if (_pixelsPerBeat < 20) return 1.0;     // Snap to beats
    if (_pixelsPerBeat < 40) return 0.5;     // Snap to half beats (1/8th notes)
    if (_pixelsPerBeat < 80) return 0.25;    // Snap to quarter beats (1/16th notes)
    return 0.125;                            // Snap to eighth beats (1/32nd notes)
  }

  /// Calculate beat position from mouse X coordinate (for MIDI/beat-based operations)
  double _calculateBeatPosition(Offset localPosition) {
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final totalX = localPosition.dx + scrollOffset;
    return totalX / _pixelsPerBeat;
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
      debugPrint('⚠️  Unsupported file type: $filePath');
      return;
    }

    try {
      // Load audio file
      final clipId = widget.audioEngine!.loadAudioFile(filePath);
      if (clipId < 0) {
        debugPrint('❌ Failed to load file: $filePath');
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
        color: const Color(0xFF4CAF50),
      );

      setState(() {
        _clips.add(clip);
        _previewClip = null;
        _dragHoveredTrackId = null;
      });

      debugPrint('✅ Dropped clip on track $trackId at ${startTime.toStringAsFixed(2)}s');
    } catch (e) {
      debugPrint('❌ Error loading dropped file: $e');
    }
  }

  /// Public method to trigger immediate track refresh
  void refreshTracks() {
    _loadTracksAsync();
  }

  /// Public method to clear all clips (used when project is cleared)
  void clearClips() {
    setState(() {
      _clips.clear();
    });
  }

  /// Public method to add a clip to the timeline
  void addClip(ClipData clip) {
    setState(() {
      _clips.add(clip);
    });
  }

  /// Check if a track has any audio clips
  bool hasClipsOnTrack(int trackId) {
    return _clips.any((clip) => clip.trackId == trackId);
  }

  /// Get selected audio clip ID (if any)
  int? get selectedAudioClipId => _selectedAudioClipId;

  /// Get selected audio clip data (if any)
  ClipData? get selectedAudioClip {
    if (_selectedAudioClipId == null) return null;
    try {
      return _clips.firstWhere((c) => c.clipId == _selectedAudioClipId);
    } catch (_) {
      return null;
    }
  }

  /// Select an audio clip by ID
  void selectAudioClip(int? clipId) {
    setState(() {
      _selectedAudioClipId = clipId;
      // Also update multi-select
      _selectedAudioClipIds.clear();
      if (clipId != null) {
        _selectedAudioClipIds.add(clipId);
      }
    });
  }

  /// Get all selected MIDI clip IDs (multi-selection)
  Set<int> get selectedMidiClipIds => Set.unmodifiable(_selectedMidiClipIds);

  /// Get all selected audio clip IDs (multi-selection)
  Set<int> get selectedAudioClipIds => Set.unmodifiable(_selectedAudioClipIds);

  /// Check if a MIDI clip is selected
  bool isMidiClipSelected(int clipId) => _selectedMidiClipIds.contains(clipId);

  /// Check if an audio clip is selected
  bool isAudioClipSelected(int clipId) => _selectedAudioClipIds.contains(clipId);

  /// Select a MIDI clip with multi-selection support
  /// - Normal click: Select only this clip (clear others)
  /// - Shift+click: Add to selection
  /// - Cmd+click: Toggle selection
  void selectMidiClipMulti(int clipId, {bool addToSelection = false, bool toggleSelection = false}) {
    setState(() {
      if (toggleSelection) {
        // Cmd+click: Toggle this clip's selection
        if (_selectedMidiClipIds.contains(clipId)) {
          _selectedMidiClipIds.remove(clipId);
        } else {
          _selectedMidiClipIds.add(clipId);
        }
      } else if (addToSelection) {
        // Shift+click: Add to selection
        _selectedMidiClipIds.add(clipId);
      } else {
        // Normal click: Select only this clip
        _selectedMidiClipIds.clear();
        _selectedMidiClipIds.add(clipId);
      }
      // Clear audio selection when selecting MIDI
      _selectedAudioClipIds.clear();
      _selectedAudioClipId = null;
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
        if (_selectedAudioClipIds.contains(clipId)) {
          _selectedAudioClipIds.remove(clipId);
          if (_selectedAudioClipId == clipId) {
            _selectedAudioClipId = _selectedAudioClipIds.isEmpty ? null : _selectedAudioClipIds.first;
          }
        } else {
          _selectedAudioClipIds.add(clipId);
          _selectedAudioClipId = clipId;
        }
      } else if (addToSelection) {
        // Shift+click: Add to selection
        _selectedAudioClipIds.add(clipId);
        _selectedAudioClipId = clipId;
      } else {
        // Normal click: Select only this clip
        _selectedAudioClipIds.clear();
        _selectedAudioClipIds.add(clipId);
        _selectedAudioClipId = clipId;
      }
      // Clear MIDI selection when selecting audio
      _selectedMidiClipIds.clear();
    });
  }

  /// Clear all clip selections
  void clearClipSelection() {
    setState(() {
      _selectedMidiClipIds.clear();
      _selectedAudioClipIds.clear();
      _selectedAudioClipId = null;
    });
  }

  /// Select all clips (both MIDI and audio)
  void selectAllClips() {
    setState(() {
      // Select all MIDI clips
      _selectedMidiClipIds.clear();
      for (final clip in widget.midiClips) {
        _selectedMidiClipIds.add(clip.clipId);
      }

      // Select all audio clips
      _selectedAudioClipIds.clear();
      for (final clip in _clips) {
        _selectedAudioClipIds.add(clip.clipId);
      }
    });
    debugPrint('🎯 Selected all clips: ${_selectedMidiClipIds.length} MIDI, ${_selectedAudioClipIds.length} audio');
  }

  /// Get all selected MIDI clips data
  List<MidiClipData> get selectedMidiClips {
    return widget.midiClips.where((c) => _selectedMidiClipIds.contains(c.clipId)).toList();
  }

  /// Get all selected audio clips data
  List<ClipData> get selectedAudioClips {
    return _clips.where((c) => _selectedAudioClipIds.contains(c.clipId)).toList();
  }

  /// Split the selected audio clip at the given position (in seconds)
  /// Returns true if split was successful
  bool splitSelectedAudioClipAtPlayhead(double playheadSeconds) {
    final clip = selectedAudioClip;
    if (clip == null) {
      debugPrint('[Timeline] No audio clip selected for split');
      return false;
    }

    // Check if playhead is within clip bounds
    if (playheadSeconds <= clip.startTime || playheadSeconds >= clip.endTime) {
      debugPrint('[Timeline] Playhead ($playheadSeconds) not within audio clip bounds (${clip.startTime} - ${clip.endTime})');
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
      _clips.removeWhere((c) => c.clipId == clip.clipId);
      _clips.add(leftClip);
      _clips.add(rightClip);
      _selectedAudioClipId = rightClipId; // Select the right clip
    });

    // TODO: Update engine with split clips when engine API supports it
    // For now, the visual split is applied but engine audio may need refresh

    debugPrint('[Timeline] Split audio clip at ${playheadSeconds}s');
    return true;
  }

  /// Quantize the selected audio clip's start time to the nearest grid position
  /// [gridSizeSeconds] is the grid resolution in seconds
  /// Returns true if quantize was successful
  bool quantizeSelectedAudioClip(double gridSizeSeconds) {
    final clip = selectedAudioClip;
    if (clip == null) {
      debugPrint('[Timeline] No audio clip selected for quantize');
      return false;
    }

    // Quantize start time to nearest grid position
    final quantizedStart = (clip.startTime / gridSizeSeconds).round() * gridSizeSeconds;

    // Only update if position changed
    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      debugPrint('[Timeline] Audio clip already quantized');
      return false;
    }

    // Update clip position
    widget.audioEngine?.setClipStartTime(clip.trackId, clip.clipId, quantizedStart);

    setState(() {
      final index = _clips.indexWhere((c) => c.clipId == clip.clipId);
      if (index >= 0) {
        _clips[index] = _clips[index].copyWith(startTime: quantizedStart);
      }
    });

    debugPrint('[Timeline] Quantized audio clip from ${clip.startTime}s to ${quantizedStart}s');
    return true;
  }

  // =========================================================================
  // Context Menus
  // =========================================================================

  /// Show context menu for an audio clip
  void _showAudioClipContextMenu(Offset position, ClipData clip) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 8),
              const Text('Delete Clip'),
              const Spacer(),
              Text('⌘⌫', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.content_copy, size: 18),
              const SizedBox(width: 8),
              const Text('Duplicate'),
              const Spacer(),
              Text('⌘D', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split',
          child: Row(
            children: [
              const Icon(Icons.content_cut, size: 18),
              const SizedBox(width: 8),
              const Text('Split at Marker'),
              const Spacer(),
              Text('⌘E', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'cut',
          child: Row(
            children: [
              const Icon(Icons.content_cut, size: 18),
              const SizedBox(width: 8),
              const Text('Cut'),
              const Spacer(),
              Text('⌘X', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18),
              const SizedBox(width: 8),
              const Text('Copy'),
              const Spacer(),
              Text('⌘C', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: Row(
            children: [
              const Icon(Icons.paste, size: 18),
              const SizedBox(width: 8),
              const Text('Paste'),
              const Spacer(),
              Text('⌘V', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'mute',
          child: Row(
            children: [
              Icon(Icons.volume_off, size: 18),
              SizedBox(width: 8),
              Text('Mute Clip'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'color',
          child: Row(
            children: [
              Icon(Icons.color_lens, size: 18),
              SizedBox(width: 8),
              Text('Color...'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 8),
              Text('Rename...'),
            ],
          ),
        ),
      ],
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
          debugPrint('Split audio clip: ${clip.fileName}');
          break;
        case 'cut':
          // TODO: Implement cut for audio clips
          debugPrint('Cut audio clip: ${clip.fileName}');
          break;
        case 'copy':
          // TODO: Implement copy for audio clips
          debugPrint('Copy audio clip: ${clip.fileName}');
          break;
        case 'paste':
          // TODO: Implement paste for audio clips
          debugPrint('Paste audio clip');
          break;
        case 'mute':
          // TODO: Implement mute for audio clips
          debugPrint('Mute audio clip: ${clip.fileName}');
          break;
        case 'color':
          // TODO: Implement color picker for audio clips
          debugPrint('Color audio clip: ${clip.fileName}');
          break;
        case 'rename':
          // TODO: Implement rename for audio clips
          debugPrint('Rename audio clip: ${clip.fileName}');
          break;
      }
    });
  }

  /// Show context menu for a MIDI clip
  void _showMidiClipContextMenu(Offset position, MidiClipData clip) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 8),
              const Text('Delete Clip'),
              const Spacer(),
              Text('⌘⌫', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.content_copy, size: 18),
              const SizedBox(width: 8),
              const Text('Duplicate'),
              const Spacer(),
              Text('⌘D', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split',
          child: Row(
            children: [
              const Icon(Icons.content_cut, size: 18),
              const SizedBox(width: 8),
              const Text('Split at Marker'),
              const Spacer(),
              Text('⌘E', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'cut',
          child: Row(
            children: [
              const Icon(Icons.content_cut, size: 18),
              const SizedBox(width: 8),
              const Text('Cut'),
              const Spacer(),
              Text('⌘X', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18),
              const SizedBox(width: 8),
              const Text('Copy'),
              const Spacer(),
              Text('⌘C', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: Row(
            children: [
              const Icon(Icons.paste, size: 18),
              const SizedBox(width: 8),
              const Text('Paste'),
              const Spacer(),
              Text('⌘V', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'mute',
          child: Row(
            children: [
              Icon(Icons.volume_off, size: 18),
              SizedBox(width: 8),
              Text('Mute Clip'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'loop',
          child: Row(
            children: [
              Icon(Icons.loop, size: 18),
              SizedBox(width: 8),
              Text('Loop Clip'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'bounce',
          child: Row(
            children: [
              Icon(Icons.audiotrack, size: 18),
              SizedBox(width: 8),
              Text('Bounce to Audio'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'color',
          child: Row(
            children: [
              Icon(Icons.color_lens, size: 18),
              SizedBox(width: 8),
              Text('Color...'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 8),
              Text('Rename...'),
            ],
          ),
        ),
      ],
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
          // Split at insert marker position
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
          debugPrint('Bounce MIDI clip: ${clip.name}');
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

  /// Delete an audio clip
  void _deleteAudioClip(ClipData clip) {
    // Note: Audio clips are managed locally in Flutter state
    // The Rust engine doesn't have a remove_audio_clip FFI yet
    setState(() {
      _clips.removeWhere((c) => c.clipId == clip.clipId);
      if (_selectedAudioClipId == clip.clipId) {
        _selectedAudioClipId = null;
      }
      _selectedAudioClipIds.remove(clip.clipId);
    });
    debugPrint('🗑️ Deleted audio clip: ${clip.fileName}');
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
      _clips.add(newClip);
    });
    debugPrint('📋 Duplicated audio clip: ${clip.fileName}');
  }

  /// Duplicate a MIDI clip
  void _duplicateMidiClip(MidiClipData clip) {
    final newStartTime = clip.startTime + clip.duration;
    widget.onMidiClipCopied?.call(clip, newStartTime);
    debugPrint('📋 Duplicated MIDI clip: ${clip.name}');
  }

  /// Quantize a MIDI clip
  void _quantizeMidiClip(MidiClipData clip) {
    const gridSizeBeats = 1.0; // 1 beat
    final quantizedStart = (clip.startTime / gridSizeBeats).round() * gridSizeBeats;

    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      debugPrint('[Timeline] MIDI clip already quantized');
      return;
    }

    final quantizedClip = clip.copyWith(startTime: quantizedStart);
    widget.onMidiClipUpdated?.call(quantizedClip);
    debugPrint('📐 Quantized MIDI clip to $quantizedStart beats');
  }

  // ========================================================================
  // MIDI CLIP CLIPBOARD OPERATIONS
  // ========================================================================

  /// Copy a MIDI clip to clipboard
  void _copyMidiClip(MidiClipData clip) {
    _clipboardMidiClip = clip;
    debugPrint('📋 Copied MIDI clip: ${clip.name}');
  }

  /// Cut a MIDI clip (copy to clipboard, then delete)
  void _cutMidiClip(MidiClipData clip) {
    _clipboardMidiClip = clip;
    widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
    debugPrint('✂️ Cut MIDI clip: ${clip.name}');
  }

  /// Paste a MIDI clip from clipboard to track
  void _pasteMidiClip(int trackId) {
    if (_clipboardMidiClip == null) {
      debugPrint('⚠️ No MIDI clip in clipboard');
      return;
    }

    // Paste at insert marker if available, otherwise at start
    final pastePosition = _insertMarkerBeats ?? 0.0;
    widget.onMidiClipCopied?.call(_clipboardMidiClip!, pastePosition);
    debugPrint('📌 Pasted MIDI clip at beat $pastePosition');
  }

  // ========================================================================
  // MIDI CLIP PROPERTY TOGGLES
  // ========================================================================

  /// Toggle mute state of a MIDI clip
  void _toggleMidiClipMute(MidiClipData clip) {
    final mutedClip = clip.copyWith(isMuted: !clip.isMuted);
    widget.onMidiClipUpdated?.call(mutedClip);
    debugPrint('${clip.isMuted ? '🔊' : '🔇'} ${clip.isMuted ? 'Unmuted' : 'Muted'} MIDI clip: ${clip.name}');
  }

  /// Toggle loop state of a MIDI clip
  void _toggleMidiClipLoop(MidiClipData clip) {
    final loopedClip = clip.copyWith(isLooping: !clip.isLooping);
    widget.onMidiClipUpdated?.call(loopedClip);
    debugPrint('${clip.isLooping ? '⏹️' : '🔁'} ${clip.isLooping ? 'Disabled' : 'Enabled'} loop for MIDI clip: ${clip.name}');
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
                debugPrint('🎨 Set MIDI clip color to ${color.toString()}');
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: clip.color == color ? Colors.white : Colors.transparent,
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
              debugPrint('✏️ Renamed MIDI clip to: $value');
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
                debugPrint('✏️ Renamed MIDI clip to: $value');
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
      _isErasing = true;
      _erasedAudioClipIds.clear();
      _erasedMidiClipIds.clear();
    });
    _eraseClipsAt(globalPosition);
  }

  /// Erase clips at the given position
  void _eraseClipsAt(Offset globalPosition) {
    if (!_isErasing) return;

    // Convert global position to local position relative to timeline content
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPosition = box.globalToLocal(globalPosition);

    // Calculate beat position from mouse X
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final beatPosition = (localPosition.dx + scrollOffset) / _pixelsPerBeat;

    // Check audio clips
    for (final clip in _clips) {
      if (_erasedAudioClipIds.contains(clip.clipId)) continue;

      // Convert clip times from seconds to beats for comparison
      final beatsPerSecond = widget.tempo / 60.0;
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;

      // Find track Y position
      final trackIndex = _tracks.indexWhere((t) => t.id == clip.trackId);
      if (trackIndex < 0) continue;

      final trackTop = trackIndex * 80.0; // Track height
      final trackBottom = trackTop + 80.0;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          localPosition.dy >= trackTop &&
          localPosition.dy <= trackBottom) {
        _erasedAudioClipIds.add(clip.clipId);
        _deleteAudioClip(clip);
        debugPrint('🧹 Erased audio clip: ${clip.fileName}');
      }
    }

    // Check MIDI clips
    for (final midiClip in widget.midiClips) {
      if (_erasedMidiClipIds.contains(midiClip.clipId)) continue;

      final clipStartBeats = midiClip.startTime;
      final clipEndBeats = midiClip.startTime + midiClip.duration;

      // Find track Y position
      final trackIndex = _tracks.indexWhere((t) => t.id == midiClip.trackId);
      if (trackIndex < 0) continue;

      final trackTop = trackIndex * 80.0;
      final trackBottom = trackTop + 80.0;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          localPosition.dy >= trackTop &&
          localPosition.dy <= trackBottom) {
        _erasedMidiClipIds.add(midiClip.clipId);
        widget.onMidiClipDeleted?.call(midiClip.clipId, midiClip.trackId);
        debugPrint('🧹 Erased MIDI clip: ${midiClip.name}');
      }
    }
  }

  /// Stop eraser mode
  void _stopErasing() {
    if (_isErasing) {
      final totalErased = _erasedAudioClipIds.length + _erasedMidiClipIds.length;
      if (totalErased > 0) {
        debugPrint('🧹 Eraser mode ended: deleted $totalErased clips');
      }
    }
    setState(() {
      _isErasing = false;
      _erasedAudioClipIds.clear();
      _erasedMidiClipIds.clear();
    });
  }

  // ========================================================================
  // SELECTION (Escape to deselect, Cmd+A to select all)
  // ========================================================================

  /// Deselect all clips (audio and MIDI)
  void _deselectAllClips() {
    final hadSelection = _selectedAudioClipIds.isNotEmpty ||
        _selectedMidiClipIds.isNotEmpty ||
        widget.selectedMidiClipId != null;

    setState(() {
      _selectedAudioClipIds.clear();
      _selectedMidiClipIds.clear();
      _selectedAudioClipId = null;
    });

    // Notify parent to clear MIDI clip selection (for piano roll)
    widget.onMidiClipSelected?.call(null, null);

    if (hadSelection) {
      debugPrint('⎋ Deselected all clips');
    }
  }

  /// Select all clips (audio and MIDI)
  void _selectAllClips() {
    setState(() {
      // Select all audio clips
      _selectedAudioClipIds.clear();
      for (final clip in _clips) {
        _selectedAudioClipIds.add(clip.clipId);
      }

      // Select all MIDI clips
      _selectedMidiClipIds.clear();
      for (final clip in widget.midiClips) {
        _selectedMidiClipIds.add(clip.clipId);
      }
    });

    debugPrint('⌘A Selected ${_selectedAudioClipIds.length} audio clips and ${_selectedMidiClipIds.length} MIDI clips');
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
      _splitPreviewAudioClipId = null;
      _splitPreviewMidiClipId = clipId;
      _splitPreviewBeatPosition = beatPosition;
    });
  }

  /// Clear split preview
  void _clearSplitPreview() {
    setState(() {
      _splitPreviewAudioClipId = null;
      _splitPreviewMidiClipId = null;
    });
  }

  /// Split audio clip at preview position
  void _splitAudioClipAtPreview(ClipData clip) {
    if (_splitPreviewAudioClipId != clip.clipId) return;

    // Convert beat position back to seconds
    final splitTimeRelative = _splitPreviewBeatPosition * (60.0 / widget.tempo);
    final splitTimeAbsolute = clip.startTime + splitTimeRelative;

    // Validate split point is within clip bounds
    if (splitTimeRelative <= 0 || splitTimeRelative >= clip.duration) {
      debugPrint('[Timeline] Split point outside clip bounds');
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
      final index = _clips.indexWhere((c) => c.clipId == clip.clipId);
      if (index >= 0) {
        _clips[index] = leftClip;
        _clips.add(rightClip);
      }
    });

    // Update engine for left clip
    widget.audioEngine?.setClipStartTime(clip.trackId, clip.clipId, clip.startTime);

    debugPrint('✂️ Split audio clip at ${splitTimeAbsolute.toStringAsFixed(2)}s');
    _clearSplitPreview();
  }

  /// Split MIDI clip at preview position
  void _splitMidiClipAtPreview(MidiClipData clip) {
    if (_splitPreviewMidiClipId != clip.clipId) return;

    // Split point in beats relative to clip start
    final splitPointBeats = _splitPreviewBeatPosition;

    // Validate split point is within clip bounds
    if (splitPointBeats <= 0 || splitPointBeats >= clip.duration) {
      debugPrint('[Timeline] Split point outside MIDI clip bounds');
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

    debugPrint('✂️ Split MIDI clip at ${(clip.startTime + splitPointBeats).toStringAsFixed(2)} beats');
    _clearSplitPreview();
  }

  /// Split MIDI clip at insert marker position
  void _splitMidiClipAtInsertMarker(MidiClipData clip) {
    if (_insertMarkerBeats == null) {
      debugPrint('[Timeline] No insert marker set for split');
      return;
    }

    // Check if insert marker is within clip bounds
    final markerBeats = _insertMarkerBeats!;
    if (markerBeats <= clip.startTime || markerBeats >= clip.endTime) {
      debugPrint('[Timeline] Insert marker not within clip bounds');
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

    debugPrint('✂️ Split MIDI clip at insert marker (${markerBeats.toStringAsFixed(2)} beats)');
  }

  /// Load tracks from audio engine
  Future<void> _loadTracksAsync() async {
    if (widget.audioEngine == null) return;

    try {
      final trackIds = await Future.microtask(() {
        return widget.audioEngine!.getAllTrackIds();
      });

      final tracks = <TimelineTrackData>[];

      for (int trackId in trackIds) {
        final info = await Future.microtask(() {
          return widget.audioEngine!.getTrackInfo(trackId);
        });

        final track = TimelineTrackData.fromCSV(info);
        if (track != null) {
          tracks.add(track);
        }
      }

      if (mounted) {
        setState(() {
          _tracks = tracks;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to load tracks for timeline: $e');
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
    final minBeats = minBars * beatsPerBar;

    // Calculate beats needed for clip duration (if any)
    final clipDurationBeats = widget.clipDuration != null
        ? (widget.clipDuration! * beatsPerSecond).ceil() + 4 // Add padding
        : 0;

    // Use the larger of minimum bars or clip duration
    final totalBeats = math.max(minBeats, clipDurationBeats);
    final totalWidth = math.max(totalBeats * _pixelsPerBeat, viewWidth);

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
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          border: Border.all(color: const Color(0xFF363636)),
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
                      _pixelsPerBeat = (_pixelsPerBeat * 1.1).clamp(10.0, 150.0);
                    } else {
                      // Scroll down = zoom out
                      _pixelsPerBeat = (_pixelsPerBeat / 1.1).clamp(10.0, 150.0);
                    }
                  });
                }
              }
            },
            child: SingleChildScrollView(
              controller: _scrollController,
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
                              if (!_isErasing) {
                                _startErasing(event.position);
                              } else {
                                _eraseClipsAt(event.position);
                              }
                            }
                          }
                        },
                        onPointerUp: (event) {
                          if (_isErasing) {
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
    // Master track should always exist, so empty _tracks means audio engine issue
    if (_tracks.isEmpty && widget.audioEngine == null) {
      // Show empty state only if no audio engine
      return Container(
        height: 200,
        color: const Color(0xFF242424),
        child: Center(
          child: Text(
            'Audio engine not initialized',
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
        ),
      );
    }

    // Separate regular tracks from master
    final regularTracks = _tracks.where((t) => t.type != 'Master').toList();
    final masterTrack = _tracks.firstWhere(
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
                _isDraggingNewClip = true;
                _newClipStartBeats = _snapToGrid(startBeats);
                _newClipEndBeats = _newClipStartBeats;
                _newClipTrackId = null; // null = create new track
              });
            },
            onHorizontalDragUpdate: (details) {
              if (!_isDraggingNewClip) return;
              final currentBeats = _calculateBeatPosition(details.localPosition);
              setState(() {
                _newClipEndBeats = _snapToGrid(currentBeats);
              });
            },
            onHorizontalDragEnd: (details) {
              if (!_isDraggingNewClip) return;

              // Calculate final start and duration (handle reverse drag)
              final startBeats = math.min(_newClipStartBeats, _newClipEndBeats);
              final endBeats = math.max(_newClipStartBeats, _newClipEndBeats);
              final durationBeats = endBeats - startBeats;

              // Minimum clip length is 1 bar (4 beats)
              if (durationBeats >= 4.0) {
                // Show track type selection popup
                _showTrackTypePopup(context, details.globalPosition, startBeats, durationBeats);
              }

              setState(() {
                _isDraggingNewClip = false;
              });
            },
            onHorizontalDragCancel: () {
              setState(() {
                _isDraggingNewClip = false;
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
                  _isAudioFileDraggingOverEmpty = true;
                });
              },
              onDragExited: (details) {
                setState(() {
                  _isAudioFileDraggingOverEmpty = false;
                });
              },
              child: DragTarget<Vst3Plugin>(
                onWillAcceptWithDetails: (details) {
                  debugPrint('🎯 VST3 onWillAccept EMPTY SPACE: plugin=${details.data.name}, isInstrument=${details.data.isInstrument}');
                  return details.data.isInstrument; // Only accept VST3 instruments
                },
                onAcceptWithDetails: (details) {
                  debugPrint('🎯 VST3 onAccept EMPTY SPACE: plugin=${details.data.name}');
                  widget.onVst3InstrumentDroppedOnEmpty?.call(details.data);
                },
                builder: (context, candidateVst3Plugins, rejectedVst3Plugins) {
                  final isVst3PluginHovering = candidateVst3Plugins.isNotEmpty;

                  return DragTarget<Instrument>(
                    onWillAcceptWithDetails: (details) {
                      debugPrint('🎯 onWillAccept EMPTY SPACE: instrument=${details.data.name}');
                      return true; // Always accept instruments
                    },
                    onAcceptWithDetails: (details) {
                      debugPrint('🎯 onAccept EMPTY SPACE: instrument=${details.data.name}');
                      widget.onInstrumentDroppedOnEmpty?.call(details.data);
                    },
                    builder: (context, candidateInstruments, rejectedInstruments) {
                      final isInstrumentHovering = candidateInstruments.isNotEmpty || isVst3PluginHovering;
                      final isAnyHovering = isInstrumentHovering || _isAudioFileDraggingOverEmpty;

                      // Determine label text
                      String dropLabel;
                      if (_isAudioFileDraggingOverEmpty) {
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
                          Container(
                            decoration: isAnyHovering
                                ? BoxDecoration(
                                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: const Color(0xFF4CAF50),
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
                                        color: const Color(0xFF4CAF50),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.add_circle_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            dropLabel,
                                            style: const TextStyle(
                                              color: Colors.white,
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
                          if (_isDraggingNewClip && _newClipTrackId == null)
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
    return GestureDetector(
      onTapUp: (details) {
        // Click ruler to place insert marker (spec v2.0)
        final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beats = xInContent / _pixelsPerBeat;
        setInsertMarker(beats.clamp(0.0, double.infinity));
      },
      child: Container(
        height: 30,
        width: width,
        decoration: const BoxDecoration(
          color: Color(0xFF363636),
          border: Border(
            bottom: BorderSide(color: Color(0xFF363636)),
          ),
        ),
        child: CustomPaint(
          painter: _TimeRulerPainter(
            pixelsPerBeat: _pixelsPerBeat,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF363636).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _pixelsPerBeat = (_pixelsPerBeat - 10).clamp(10.0, 150.0);
              });
            },
            icon: const Icon(Icons.remove, size: 14),
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: const Color(0xFF9E9E9E),
            tooltip: 'Zoom out (Cmd -)',
          ),
          Text(
            '${_pixelsPerBeat.toInt()}',
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _pixelsPerBeat = (_pixelsPerBeat + 10).clamp(10.0, 150.0);
              });
            },
            icon: const Icon(Icons.add, size: 14),
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: const Color(0xFF9E9E9E),
            tooltip: 'Zoom in (Cmd +)',
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(double width, double duration) {
    return CustomPaint(
      size: Size(width, double.infinity),
      painter: _GridPainter(
        pixelsPerBeat: _pixelsPerBeat,
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
    final trackClips = _clips.where((c) => c.trackId == track.id).toList();
    final trackMidiClips = widget.midiClips.where((c) => c.trackId == track.id).toList();
    final isHovered = _dragHoveredTrackId == track.id;
    final isSelected = widget.selectedMidiTrackId == track.id;
    final isMidiTrack = track.type.toLowerCase() == 'midi';

    // Wrap with VST3Plugin drag target first
    return DragTarget<Vst3Plugin>(
      onWillAcceptWithDetails: (details) {
        debugPrint('🎯 VST3 onWillAccept: track=${track.id} (${track.type}), isMidiTrack=$isMidiTrack, plugin=${details.data.name}, isInstrument=${details.data.isInstrument}');
        return isMidiTrack && details.data.isInstrument;
      },
      onAcceptWithDetails: (details) {
        debugPrint('🎯 VST3 onAccept: track=${track.id}, plugin=${details.data.name}');
        widget.onVst3InstrumentDropped?.call(track.id, details.data);
      },
      builder: (context, candidateVst3Plugins, rejectedVst3Plugins) {
        // Note: candidateVst3Plugins/rejectedVst3Plugins available for visual feedback

        // Nest Instrument drag target inside
        return DragTarget<Instrument>(
          onWillAcceptWithDetails: (details) {
            debugPrint('🎯 onWillAccept: track=${track.id} (${track.type}), isMidiTrack=$isMidiTrack, instrument=${details.data.name}');
            return isMidiTrack;
          },
          onAcceptWithDetails: (details) {
            debugPrint('🎯 onAccept: track=${track.id}, instrument=${details.data.name}');
            widget.onInstrumentDropped?.call(track.id, details.data);
          },
          builder: (context, candidateInstruments, rejectedInstruments) {
            // Note: candidateInstruments/rejectedInstruments and isVst3PluginHovering/Rejected
            // are available for visual feedback if needed in the future

        return PlatformDropTarget(
          onDragEntered: (details) {
            setState(() {
              _dragHoveredTrackId = track.id;
            });
          },
          onDragExited: (details) {
            setState(() {
              _dragHoveredTrackId = null;
              _previewClip = null;
            });
          },
          onDragUpdated: (details) {
            // Update preview position
            final fileName = 'Preview'; // We don't have filename yet
            final startTime = _calculateTimelinePosition(details.localPosition);

            setState(() {
              _previewClip = PreviewClip(
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
                  debugPrint('🎵 Created 1-bar MIDI clip at beat $startBeats (double-click)');
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
              _isDraggingNewClip = true;
              _newClipStartBeats = _snapToGrid(beatPosition);
              _newClipEndBeats = _newClipStartBeats;
              _newClipTrackId = track.id;
            });
          }
        },
        onHorizontalDragUpdate: (details) {
          if (_isDraggingNewClip && _newClipTrackId == track.id) {
            final currentBeats = _calculateBeatPosition(details.localPosition);
            setState(() {
              _newClipEndBeats = _snapToGrid(currentBeats);
            });
          }
        },
        onHorizontalDragEnd: (details) {
          if (_isDraggingNewClip && _newClipTrackId == track.id) {
            // Calculate final start and duration (handle reverse drag)
            final startBeats = math.min(_newClipStartBeats, _newClipEndBeats);
            final endBeats = math.max(_newClipStartBeats, _newClipEndBeats);
            final durationBeats = endBeats - startBeats;

            // Minimum clip length is 1 bar (4 beats)
            if (durationBeats >= 4.0) {
              widget.onCreateClipOnTrack?.call(track.id, startBeats, durationBeats);
            }

            setState(() {
              _isDraggingNewClip = false;
              _newClipTrackId = null;
            });
          }
        },
        onHorizontalDragCancel: () {
          if (_newClipTrackId == track.id) {
            setState(() {
              _isDraggingNewClip = false;
              _newClipTrackId = null;
            });
          }
        },
        child: Container(
        height: widget.trackHeights[track.id] ?? 100.0,
        decoration: BoxDecoration(
          color: isHovered
              ? const Color(0xFF363636).withValues(alpha: 0.3)
              : (isSelected
                  ? const Color(0xFF363636).withValues(alpha: 0.3)
                  : Colors.transparent),
          border: const Border(
            bottom: BorderSide(
              color: Color(0xFF606060),
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
                .where((midiClip) => _draggingMidiClipId == midiClip.clipId && _isCopyDrag && _stampCopyCount > 0)
                .expand((midiClip) => _buildStampCopyPreviews(midiClip, trackColor, widget.trackHeights[track.id] ?? 100.0)),

            // Show preview clip if hovering over this track
            if (_previewClip != null && _previewClip!.trackId == track.id)
              _buildPreviewClip(_previewClip!),

            // Drag-to-create preview for this track
            if (_isDraggingNewClip && _newClipTrackId == track.id)
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
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF606060),
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
            child: const Row(
              children: [
                Text(
                  '🎚️ Master',
                  style: TextStyle(
                    color: Colors.white,
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
    final clipWidth = clip.duration * _pixelsPerSecond;
    // Use dragged position if this clip is being dragged
    final displayStartTime = _draggingClipId == clip.clipId
        ? _dragStartTime + (_dragCurrentX - _dragStartX) / _pixelsPerSecond
        : clip.startTime;
    final clipX = displayStartTime.clamp(0.0, double.infinity) * _pixelsPerSecond;
    final isDragging = _draggingClipId == clip.clipId;
    final isSelected = _selectedAudioClipIds.contains(clip.clipId);
    final isMultiSelected = _selectedAudioClipIds.length > 1 && isSelected;

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 8.0; // Track height minus padding

    // Check if this clip has split preview active
    final hasSplitPreview = _splitPreviewAudioClipId == clip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (_splitPreviewBeatPosition / (clip.duration * (widget.tempo / 60.0))) * clipWidth
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
          final clickSeconds = clip.startTime + (clickXInClip / _pixelsPerSecond);
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
          final isInMultiSelection = _selectedAudioClipIds.contains(clip.clipId);

          setState(() {
            // If not in multi-selection, select just this clip
            if (!isInMultiSelection) {
              _selectedAudioClipIds.clear();
              _selectedAudioClipIds.add(clip.clipId);
            }
            _selectedAudioClipId = clip.clipId;
            _draggingClipId = clip.clipId;
            _dragStartTime = clip.startTime;
            _dragStartX = details.globalPosition.dx;
            _dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragUpdate: (details) {
          // Skip if Ctrl/Cmd is held (eraser mode)
          final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isCtrlOrCmd) return;

          setState(() {
            _dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragEnd: (details) {
          if (_draggingClipId == null) return;

          // Calculate final position and persist to engine
          final newStartTime = (_dragStartTime + (_dragCurrentX - _dragStartX) / _pixelsPerSecond)
              .clamp(0.0, double.infinity);
          widget.audioEngine?.setClipStartTime(clip.trackId, clip.clipId, newStartTime);
          // Update local state
          setState(() {
            final index = _clips.indexWhere((c) => c.clipId == clip.clipId);
            if (index >= 0) {
              _clips[index] = _clips[index].copyWith(startTime: newStartTime);
            }
            _draggingClipId = null;
          });
        },
        child: MouseRegion(
          cursor: _trimmingAudioClipId == clip.clipId
              ? (_isTrimmingLeftEdge ? SystemMouseCursors.resizeLeft : SystemMouseCursors.resizeRight)
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
            if (_splitPreviewAudioClipId == clip.clipId) {
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
                        ? (isMultiSelected ? const Color(0xFF64B5F6) : Colors.white) // Blue for multi, white for single
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
                          const Icon(
                            Icons.audiotrack,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              clip.fileName,
                              style: const TextStyle(
                                color: Colors.white,
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
                      _trimmingAudioClipId = clip.clipId;
                      _isTrimmingLeftEdge = true;
                      _audioTrimStartTime = clip.startTime;
                      _audioTrimStartDuration = clip.duration;
                      _audioTrimStartOffset = clip.offset;
                      _audioTrimStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_trimmingAudioClipId != clip.clipId || !_isTrimmingLeftEdge) return;
                    final deltaX = details.globalPosition.dx - _audioTrimStartX;
                    final deltaSeconds = deltaX / _pixelsPerSecond;

                    // Calculate new start time and duration
                    var newStartTime = _audioTrimStartTime + deltaSeconds;
                    var newDuration = _audioTrimStartDuration - deltaSeconds;
                    var newOffset = _audioTrimStartOffset + deltaSeconds;

                    // Clamp to valid bounds
                    newStartTime = newStartTime.clamp(0.0, _audioTrimStartTime + _audioTrimStartDuration - 0.1);
                    newDuration = (_audioTrimStartTime + _audioTrimStartDuration) - newStartTime;
                    newDuration = newDuration.clamp(0.1, double.infinity);
                    newOffset = newOffset.clamp(0.0, double.infinity);

                    setState(() {
                      final index = _clips.indexWhere((c) => c.clipId == clip.clipId);
                      if (index >= 0) {
                        _clips[index] = _clips[index].copyWith(
                          startTime: newStartTime,
                          duration: newDuration,
                          offset: newOffset,
                        );
                      }
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    // Persist to engine
                    final trimmedClip = _clips.firstWhere((c) => c.clipId == clip.clipId, orElse: () => clip);
                    widget.audioEngine?.setClipStartTime(trimmedClip.trackId, trimmedClip.clipId, trimmedClip.startTime);
                    setState(() {
                      _trimmingAudioClipId = null;
                      _isTrimmingLeftEdge = false;
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
                      _trimmingAudioClipId = clip.clipId;
                      _isTrimmingLeftEdge = false;
                      _audioTrimStartDuration = clip.duration;
                      _audioTrimStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_trimmingAudioClipId != clip.clipId || _isTrimmingLeftEdge) return;
                    final deltaX = details.globalPosition.dx - _audioTrimStartX;
                    final deltaSeconds = deltaX / _pixelsPerSecond;

                    // Calculate new duration
                    var newDuration = _audioTrimStartDuration + deltaSeconds;
                    newDuration = newDuration.clamp(0.1, double.infinity);

                    setState(() {
                      final index = _clips.indexWhere((c) => c.clipId == clip.clipId);
                      if (index >= 0) {
                        _clips[index] = _clips[index].copyWith(duration: newDuration);
                      }
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      _trimmingAudioClipId = null;
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
                    color: Colors.white.withValues(alpha: 0.8),
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
    final clipWidth = sourceClip.duration * _pixelsPerBeat;
    final totalHeight = trackHeight - 8.0;

    for (int i = 1; i <= _stampCopyCount; i++) {
      final copyStartBeats = sourceClip.startTime + (i * _stampCopySourceDuration);
      final copyX = copyStartBeats * _pixelsPerBeat;

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
    final clipWidth = clipDurationBeats * _pixelsPerBeat;

    // Use dragged position if this clip is being dragged (with snap preview)
    double displayStartBeats;
    if (_draggingMidiClipId == midiClip.clipId) {
      final dragDeltaBeats = (_midiDragCurrentX - _midiDragStartX) / _pixelsPerBeat;
      var draggedBeats = clipStartBeats + dragDeltaBeats;
      draggedBeats = draggedBeats.clamp(0.0, double.infinity);
      // Snap to beat grid
      final snapResolution = _getGridSnapResolution();
      displayStartBeats = (draggedBeats / snapResolution).round() * snapResolution;
    } else {
      displayStartBeats = clipStartBeats;
    }
    final clipX = displayStartBeats * _pixelsPerBeat;

    // Use both widget prop (single) and internal multi-selection
    final isSelected = widget.selectedMidiClipId == midiClip.clipId || _selectedMidiClipIds.contains(midiClip.clipId);
    final isMultiSelected = _selectedMidiClipIds.length > 1 && _selectedMidiClipIds.contains(midiClip.clipId);
    final isDragging = _draggingMidiClipId == midiClip.clipId;

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 8.0; // Track height minus padding

    // Check if this clip has split preview active
    final hasSplitPreview = _splitPreviewMidiClipId == midiClip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (_splitPreviewBeatPosition / midiClip.duration) * clipWidth
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
          if (!isShiftPressed || _selectedMidiClipIds.contains(midiClip.clipId)) {
            widget.onMidiClipSelected?.call(midiClip.clipId, midiClip);
          } else if (_selectedMidiClipIds.isEmpty) {
            widget.onMidiClipSelected?.call(null, null);
          }

          // Place insert marker at click position (spec v2.0)
          final clickXInClip = details.localPosition.dx;
          final clickBeats = midiClip.startTime + (clickXInClip / _pixelsPerBeat);
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
          final isInMultiSelection = _selectedMidiClipIds.contains(midiClip.clipId);
          // Alt+drag = duplicate (spec v2.0)
          final isDuplicate = HardwareKeyboard.instance.isAltPressed;
          setState(() {
            // If not in multi-selection, select just this clip
            if (!isInMultiSelection) {
              _selectedMidiClipIds.clear();
              _selectedMidiClipIds.add(midiClip.clipId);
            }
            _draggingMidiClipId = midiClip.clipId;
            _midiDragStartTime = midiClip.startTime;
            _midiDragStartX = details.globalPosition.dx;
            _midiDragCurrentX = details.globalPosition.dx;
            _isCopyDrag = isDuplicate; // Alt = duplicate
            // Store source clip duration for stamp copies
            _stampCopySourceDuration = midiClip.duration;
            _stampCopyCount = 0;
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
          if (_isCopyDrag && _stampCopySourceDuration > 0) {
            final dragDeltaBeats = (details.globalPosition.dx - _midiDragStartX) / _pixelsPerBeat;
            // Only stamp copies when dragging forward past the clip's own length
            if (dragDeltaBeats > _stampCopySourceDuration) {
              stampCount = (dragDeltaBeats / _stampCopySourceDuration).floor();
            }
          }

          setState(() {
            _midiDragCurrentX = details.globalPosition.dx;
            _snapBypassActive = bypassSnap;
            _stampCopyCount = stampCount;
          });
        },
        onHorizontalDragEnd: (details) {
          if (_draggingMidiClipId == null) return;

          // Calculate final position with beat-based snapping
          final startBeats = _midiDragStartTime;
          final dragDeltaBeats = (_midiDragCurrentX - _midiDragStartX) / _pixelsPerBeat;
          var newStartBeats = (startBeats + dragDeltaBeats).clamp(0.0, double.infinity);

          // Snap to beat grid (unless Shift bypasses snap)
          if (!_snapBypassActive) {
            final snapResolution = _getGridSnapResolution();
            newStartBeats = (newStartBeats / snapResolution).round() * snapResolution;
          }

          if (_isCopyDrag) {
            // Alt+drag: create stamp copies (spec v2.0)
            if (_stampCopyCount > 0) {
              // Create multiple stamp copies at regular intervals
              for (int i = 1; i <= _stampCopyCount; i++) {
                final copyStartBeats = midiClip.startTime + (i * _stampCopySourceDuration);
                widget.onMidiClipCopied?.call(midiClip, copyStartBeats);
              }
              debugPrint('📋 Created $_stampCopyCount stamp copies');
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
            _draggingMidiClipId = null;
            _isCopyDrag = false;
            _snapBypassActive = false;
            _stampCopyCount = 0;
          });
        },
        child: MouseRegion(
          cursor: _resizingMidiClipId == midiClip.clipId
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
            if (_splitPreviewMidiClipId == midiClip.clipId) {
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
                            ? (isMultiSelected ? const Color(0xFF64B5F6) : Colors.white) // Blue for multi, white for single
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
                          const Icon(
                            Icons.piano,
                            size: 10,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              midiClip.name,
                              style: const TextStyle(
                                color: Colors.white,
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
                      _trimmingMidiClipId = midiClip.clipId;
                      _trimStartTime = midiClip.startTime;
                      _trimStartDuration = midiClip.duration;
                      _trimStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_trimmingMidiClipId != midiClip.clipId) return;
                    final deltaX = details.globalPosition.dx - _trimStartX;
                    final deltaBeats = deltaX / _pixelsPerBeat;

                    // Calculate new start time and duration
                    var newStartTime = _trimStartTime + deltaBeats;
                    var newDuration = _trimStartDuration - deltaBeats;

                    // Snap to grid
                    final snapResolution = _getGridSnapResolution();
                    newStartTime = (newStartTime / snapResolution).round() * snapResolution;
                    newStartTime = newStartTime.clamp(0.0, _trimStartTime + _trimStartDuration - 1.0);

                    // Recalculate duration based on snapped start
                    newDuration = (_trimStartTime + _trimStartDuration) - newStartTime;
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
                      _trimmingMidiClipId = null;
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
                      _resizingMidiClipId = midiClip.clipId;
                      _resizeStartDuration = midiClip.duration;
                      _resizeStartX = details.globalPosition.dx;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_resizingMidiClipId != midiClip.clipId) return;
                    final deltaX = details.globalPosition.dx - _resizeStartX;
                    final deltaBeats = deltaX / _pixelsPerBeat;
                    var newDuration = (_resizeStartDuration + deltaBeats).clamp(1.0, 256.0);

                    // Snap to grid
                    final snapResolution = _getGridSnapResolution();
                    newDuration = (newDuration / snapResolution).round() * snapResolution;
                    newDuration = newDuration.clamp(1.0, 256.0);

                    final updatedClip = midiClip.copyWith(duration: newDuration);
                    widget.onMidiClipUpdated?.call(updatedClip);
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      _resizingMidiClipId = null;
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
                    color: Colors.white.withValues(alpha: 0.8),
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
      final lineX = loopBeat * _pixelsPerBeat;
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
    final clipWidth = previewDuration * _pixelsPerSecond;
    final clipX = preview.startTime * _pixelsPerSecond;

    return Positioned(
      left: clipX,
      top: 4,
      child: Container(
        width: clipWidth,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
          border: Border.all(
            color: const Color(0xFF4CAF50),
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Icon(
            Icons.audiotrack,
            color: const Color(0xFF4CAF50).withValues(alpha: 0.6),
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayhead() {
    final playheadX = widget.playheadPosition * _pixelsPerSecond;

    return Positioned(
      left: playheadX - 10, // Center the 20px wide handle on the playhead position
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          // Calculate new position from drag delta
          final newX = (playheadX + details.delta.dx).clamp(0.0, double.infinity);
          final newPosition = newX / _pixelsPerSecond;

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
                    color: const Color(0xFFF44336),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                // Playhead line
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: const Color(0xFFF44336),
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
    if (_insertMarkerBeats == null) return const SizedBox.shrink();

    final markerX = _insertMarkerBeats! * _pixelsPerBeat;

    return Positioned(
      left: markerX - 1, // Center the 2px line
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          child: CustomPaint(
            painter: _DashedLinePainter(
              color: const Color(0xFF2196F3), // Blue color
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
      _insertMarkerBeats = beats;
    });
  }

  /// Get insert marker position in seconds (for split operations)
  double? getInsertMarkerSeconds() {
    if (_insertMarkerBeats == null) return null;
    final beatsPerSecond = widget.tempo / 60.0;
    return _insertMarkerBeats! / beatsPerSecond;
  }

  /// Build the drag-to-create preview rectangle
  Widget _buildDragToCreatePreview() {
    // Calculate positions (handle reverse drag)
    final startBeats = math.min(_newClipStartBeats, _newClipEndBeats);
    final endBeats = math.max(_newClipStartBeats, _newClipEndBeats);
    final durationBeats = endBeats - startBeats;

    // Convert to pixels
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final startX = (startBeats * _pixelsPerBeat) - scrollOffset;
    final width = durationBeats * _pixelsPerBeat;

    // Calculate bars for label
    final bars = (durationBeats / 4.0);
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
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
          border: Border.all(
            color: const Color(0xFF4CAF50),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            barsLabel,
            style: const TextStyle(
              color: Colors.white,
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
        const PopupMenuItem<String>(
          value: 'midi',
          child: Row(
            children: [
              Icon(Icons.piano, size: 18, color: Color(0xFF9E9E9E)),
              SizedBox(width: 8),
              Text('MIDI Track'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'audio',
          child: Row(
            children: [
              Icon(Icons.audiotrack, size: 18, color: Color(0xFF9E9E9E)),
              SizedBox(width: 8),
              Text('Audio Track'),
            ],
          ),
        ),
      ],
      color: const Color(0xFF363636),
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
    final startBeats = math.min(_newClipStartBeats, _newClipEndBeats);
    final endBeats = math.max(_newClipStartBeats, _newClipEndBeats);
    final durationBeats = endBeats - startBeats;

    // Convert to pixels
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final startX = (startBeats * _pixelsPerBeat) - scrollOffset;
    final width = durationBeats * _pixelsPerBeat;

    // Calculate bars for label
    final bars = (durationBeats / 4.0);
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

}

/// Painter for the time ruler (bar numbers with beat subdivisions)
class _TimeRulerPainter extends CustomPainter {
  final double pixelsPerBeat;

  _TimeRulerPainter({
    required this.pixelsPerBeat,
  });

  /// Get the smallest grid subdivision to show based on zoom level
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return 4.0;     // Only bars
    if (pixelsPerBeat < 20) return 1.0;     // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;     // + half beats
    return 0.25;                             // + quarter beats
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Beat-based measurements (tempo-independent)
    final gridDivision = _getGridDivision();

    // Calculate total beats to draw
    final totalBeats = (size.width / pixelsPerBeat).ceil() + 4;

    final paint = Paint()
      ..color = const Color(0xFF3a3a3a)
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw markers based on beat subdivisions
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      if (x > size.width) break;

      // Determine tick style based on beat position
      final isBar = (beat % 4.0).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;

      double tickHeight;
      if (isBar) {
        tickHeight = 15.0;
        paint.strokeWidth = 1.5;
      } else if (isBeat) {
        tickHeight = 10.0;
        paint.strokeWidth = 1.0;
      } else {
        tickHeight = 6.0;
        paint.strokeWidth = 0.5;
      }

      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        paint,
      );

      // Draw bar numbers at bar lines
      if (isBar) {
        final barNumber = (beat / 4.0).round() + 1; // Bars are 1-indexed

        textPainter.text = TextSpan(
          text: '$barNumber',
          style: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 2),
        );
      } else if (isBeat && pixelsPerBeat >= 30) {
        // Show beat subdivisions (1.2, 1.3, 1.4) when zoomed in enough
        final barNumber = (beat / 4.0).floor() + 1;
        final beatInBar = ((beat % 4.0) + 1).round();

        if (beatInBar > 1) {
          textPainter.text = TextSpan(
            text: '$barNumber.$beatInBar',
            style: const TextStyle(
              color: Color(0xFF707070),
              fontSize: 9,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          );

          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(x - textPainter.width / 2, 4),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) {
    return oldDelegate.pixelsPerBeat != pixelsPerBeat;
  }
}

/// Painter for the grid lines (beat-based with zoom-dependent visibility)
class _GridPainter extends CustomPainter {
  final double pixelsPerBeat;

  _GridPainter({
    required this.pixelsPerBeat,
  });

  /// Get the smallest grid subdivision to show based on zoom level
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return 4.0;     // Only bars (every 4 beats)
    if (pixelsPerBeat < 20) return 1.0;     // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;     // + half beats
    if (pixelsPerBeat < 80) return 0.25;    // + quarter beats
    return 0.125;                            // + eighth beats
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Beat-based measurements (tempo-independent)
    final gridDivision = _getGridDivision();

    // Calculate total beats to draw (extend to fill width)
    final totalBeats = (size.width / pixelsPerBeat).ceil() + 4;

    final paint = Paint()..style = PaintingStyle.stroke;

    // Draw grid lines based on beat subdivisions
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      if (x > size.width) break;

      // Determine line style based on beat position
      final isBar = (beat % 4.0).abs() < 0.001;  // Every 4 beats = bar
      final isBeat = (beat % 1.0).abs() < 0.001; // Whole beats
      final isHalfBeat = (beat % 0.5).abs() < 0.001; // Half beats

      if (isBar) {
        // Bar lines - thickest and brightest
        paint.color = const Color(0xFF505050);
        paint.strokeWidth = 2.0;
      } else if (isBeat) {
        // Beat lines - medium
        paint.color = const Color(0xFF404040);
        paint.strokeWidth = 1.0;
      } else if (isHalfBeat) {
        // Half beat lines - thin
        paint.color = const Color(0xFF363636);
        paint.strokeWidth = 0.5;
      } else {
        // Subdivision lines - thinnest
        paint.color = const Color(0xFF303030);
        paint.strokeWidth = 0.5;
      }

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.pixelsPerBeat != pixelsPerBeat;
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

/// Painter for dashed vertical line (insert marker)
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedLinePainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashLength = 6,
    this.gapLength = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, math.min(y + dashLength, size.height)),
        paint,
      );
      y += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
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

