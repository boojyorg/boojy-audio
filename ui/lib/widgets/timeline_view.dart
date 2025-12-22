import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'dart:math' as math;
import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
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
  });

  @override
  State<TimelineView> createState() => TimelineViewState();
}

class TimelineViewState extends State<TimelineView> {
  final ScrollController _scrollController = ScrollController();
  double _pixelsPerSecond = 100.0; // Zoom level
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
  bool _isCopyDrag = false; // True when Shift held at drag start

  // Resize handle drag state (free-form resize)
  int? _loopDraggingClipId;
  double _loopDragStartX = 0.0;
  double _loopDragCurrentX = 0.0;
  double _resizeDragStartDuration = 0.0;

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
  void dispose() {
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
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
    final beatsPerSecond = widget.tempo / 60.0;
    final pixelsPerBeat = _pixelsPerSecond / beatsPerSecond;

    if (pixelsPerBeat < 10) return 4.0;     // Snap to bars (every 4 beats)
    if (pixelsPerBeat < 20) return 1.0;     // Snap to beats
    if (pixelsPerBeat < 40) return 0.5;     // Snap to half beats (1/8th notes)
    if (pixelsPerBeat < 80) return 0.25;    // Snap to quarter beats (1/16th notes)
    return 0.125;                            // Snap to eighth beats (1/32nd notes)
  }

  /// Snap a time value to the beat grid
  /// Returns the snapped time in seconds
  double _snapToGrid(double seconds) {
    if (_snapBypassActive) return seconds;

    final beatsPerSecond = widget.tempo / 60.0;
    final beats = seconds * beatsPerSecond;

    // Use zoom-dependent snap resolution
    final snapResolution = _getGridSnapResolution();
    final snappedBeats = (beats / snapResolution).round() * snapResolution;

    return snappedBeats / beatsPerSecond;
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

    // Calculate beat-based width
    final beatsPerSecond = widget.tempo / 60.0;
    final pixelsPerBeat = _pixelsPerSecond / beatsPerSecond;

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
    final totalWidth = math.max(totalBeats * pixelsPerBeat, viewWidth);

    // Duration in seconds for backward compatibility with painters
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
                      _pixelsPerSecond = (_pixelsPerSecond * 1.1).clamp(20.0, 200.0);
                    } else {
                      // Scroll down = zoom out
                      _pixelsPerSecond = (_pixelsPerSecond / 1.1).clamp(20.0, 200.0);
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

                    // Timeline tracks area
                    Expanded(
                      child: Stack(
                        children: [
                          // Grid lines
                          _buildGrid(totalWidth, duration),

                          // Tracks
                          _buildTracks(totalWidth),

                          // Playhead
                          _buildPlayhead(),
                        ],
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

          final trackColor = TrackColors.getTrackColor(index);
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
        // Supports: instruments, VST3 plugins, and audio files
        Expanded(
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

                    return Container(
                      decoration: isAnyHovering
                          ? BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.1),
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
                    );
                  },
                );
              },
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
    return Container(
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
          duration: duration,
          pixelsPerSecond: _pixelsPerSecond,
          tempo: widget.tempo,
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
                _pixelsPerSecond = math.max(20, _pixelsPerSecond - 20);
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
            '${_pixelsPerSecond.toInt()}',
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _pixelsPerSecond = math.min(200, _pixelsPerSecond + 20);
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
        duration: duration,
        pixelsPerSecond: _pixelsPerSecond,
        tempo: widget.tempo,
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
    // Build formatted name
    final formattedName = TrackColors.getFormattedTrackName(
      trackType: track.type,
      trackName: track.name,
      audioCount: audioCount,
      midiCount: midiCount,
    );
    final emoji = TrackColors.getTrackEmoji(track.name, track.type);

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
        final isVst3PluginHovering = candidateVst3Plugins.isNotEmpty;
        final isVst3PluginRejected = rejectedVst3Plugins.isNotEmpty;

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
            final isInstrumentHovering = candidateInstruments.isNotEmpty || isVst3PluginHovering;
            final isInstrumentRejected = rejectedInstruments.isNotEmpty || isVst3PluginRejected;

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
        onTap: isMidiTrack
            ? () {
                // Select MIDI track when clicked
                widget.onMidiTrackSelected?.call(track.id);
              }
            : null,
        child: Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isHovered
              ? const Color(0xFF363636).withValues(alpha: 0.3)
              : (isSelected
                  ? const Color(0xFF363636).withValues(alpha: 0.3)
                  : Colors.transparent),
          border: Border(
            left: BorderSide(
              color: isInstrumentHovering
                  ? const Color(0xFF00BCD4)
                  : (isInstrumentRejected
                      ? Colors.red.withValues(alpha: 0.8)
                      : (isSelected
                          ? trackColor.withValues(alpha: 1.0)
                          : (isHovered ? trackColor.withValues(alpha: 0.8) : trackColor))),
              width: (isInstrumentHovering || isInstrumentRejected)
                  ? 3
                  : (isSelected ? 3 : (isHovered ? 3 : 2)),
            ),
            top: BorderSide(
              color: isInstrumentHovering
                  ? const Color(0xFF00BCD4)
                  : (isInstrumentRejected
                      ? Colors.red.withValues(alpha: 0.8)
                      : (isSelected
                          ? trackColor.withValues(alpha: 1.0)
                          : (isHovered ? trackColor.withValues(alpha: 0.8) : trackColor))),
              width: (isInstrumentHovering || isInstrumentRejected)
                  ? 3
                  : (isSelected ? 3 : (isHovered ? 3 : 2)),
            ),
            right: BorderSide(
              color: isInstrumentHovering
                  ? const Color(0xFF00BCD4)
                  : (isInstrumentRejected
                      ? Colors.red.withValues(alpha: 0.8)
                      : (isSelected
                          ? trackColor.withValues(alpha: 1.0)
                          : (isHovered ? trackColor.withValues(alpha: 0.8) : trackColor))),
              width: (isInstrumentHovering || isInstrumentRejected)
                  ? 3
                  : (isSelected ? 3 : (isHovered ? 3 : 2)),
            ),
            // Bottom separator line between tracks
            bottom: const BorderSide(
              color: Color(0xFF606060),
              width: 2,
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
            ...trackClips.map((clip) => _buildClip(clip)),

            // Render MIDI clips for this track
            ...trackMidiClips.map((midiClip) => _buildMidiClip(
                  midiClip,
                  trackColor,
                )),

            // Show preview clip if hovering over this track
            if (_previewClip != null && _previewClip!.trackId == track.id)
              _buildPreviewClip(_previewClip!),
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
    return Container(
      height: 100,
      margin: const EdgeInsets.only(bottom: 4), // Match other tracks
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: TrackColors.masterColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Track header bar (fully opaque)
          Container(
            height: 20,
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

          // Empty content area
          Expanded(
            child: CustomPaint(
              painter: _GridPatternPainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClip(ClipData clip) {
    final clipWidth = clip.duration * _pixelsPerSecond;
    // Use dragged position if this clip is being dragged
    final displayStartTime = _draggingClipId == clip.clipId
        ? _dragStartTime + (_dragCurrentX - _dragStartX) / _pixelsPerSecond
        : clip.startTime;
    final clipX = displayStartTime.clamp(0.0, double.infinity) * _pixelsPerSecond;

    return Positioned(
      left: clipX,
      top: 4,
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          setState(() {
            _draggingClipId = clip.clipId;
            _dragStartTime = clip.startTime;
            _dragStartX = details.globalPosition.dx;
            _dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            _dragCurrentX = details.globalPosition.dx;
          });
        },
        onHorizontalDragEnd: (details) {
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
          cursor: SystemMouseCursors.grab,
          child: Container(
            width: clipWidth,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF363636).withValues(alpha: 0.3),
              border: Border.all(
                color: _draggingClipId == clip.clipId
                    ? const Color(0xFF81C784)
                    : const Color(0xFF4CAF50),
                width: _draggingClipId == clip.clipId ? 3 : 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                // Waveform - must use Positioned.fill so CustomPaint gets proper size
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        peaks: clip.waveformPeaks,
                        color: const Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                ),
                // File name label
                Positioned(
                  top: 2,
                  left: 4,
                  child: Text(
                    clip.fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMidiClip(MidiClipData midiClip, Color trackColor) {
    // Calculate the content duration (extent of all notes)
    double contentDuration;
    if (midiClip.notes.isEmpty) {
      contentDuration = midiClip.duration; // Use clip duration if no notes
    } else {
      // Find the furthest note end time (in seconds at current tempo)
      final furthestBeat = midiClip.notes
          .map((note) => note.startTime + note.duration)
          .reduce((a, b) => a > b ? a : b);
      // Convert beats to seconds: seconds = (beats / BPM) * 60
      contentDuration = (furthestBeat / widget.tempo) * 60.0;
    }

    // Calculate display width (during resize drag, show preview with snap)
    double displayDuration;
    if (_loopDraggingClipId == midiClip.clipId) {
      // Free-form resize: calculate new duration from drag delta (with snap preview)
      final dragDelta = _loopDragCurrentX - _loopDragStartX;
      final durationDelta = dragDelta / _pixelsPerSecond;
      final rawDuration = (_resizeDragStartDuration + durationDelta).clamp(0.5, double.infinity);
      displayDuration = _snapToGrid(rawDuration);
    } else {
      displayDuration = midiClip.duration;
    }

    final clipWidth = displayDuration * _pixelsPerSecond;

    // Calculate how many times content repeats within the clip
    final repeatCount = contentDuration > 0 ? (displayDuration / contentDuration).ceil() : 1;

    // Use dragged position if this clip is being dragged (with snap preview)
    double displayStartTime;
    if (_draggingMidiClipId == midiClip.clipId) {
      var draggedTime = _midiDragStartTime + (_midiDragCurrentX - _midiDragStartX) / _pixelsPerSecond;
      draggedTime = draggedTime.clamp(0.0, double.infinity);
      displayStartTime = _snapToGrid(draggedTime);
    } else {
      displayStartTime = midiClip.startTime;
    }
    final clipX = displayStartTime * _pixelsPerSecond;
    final isSelected = widget.selectedMidiClipId == midiClip.clipId;
    final isDragging = _draggingMidiClipId == midiClip.clipId;
    final isResizing = _loopDraggingClipId == midiClip.clipId;

    const headerHeight = 18.0;
    const contentHeight = 54.0;
    const totalHeight = headerHeight + contentHeight;

    return Positioned(
      left: clipX,
      top: 4,
      child: SizedBox(
        width: clipWidth,
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main clip body (handles move/copy drag)
            Positioned.fill(
              right: 8, // Leave space for resize handle
              child: GestureDetector(
                onDoubleTap: () {
                  // Double-click to open in piano roll
                  widget.onMidiClipSelected?.call(midiClip.clipId, midiClip);
                },
                onHorizontalDragStart: (details) {
                  // Check if Shift is held at drag start for copy mode
                  final isCopy = HardwareKeyboard.instance.isShiftPressed;
                  setState(() {
                    _draggingMidiClipId = midiClip.clipId;
                    _midiDragStartTime = midiClip.startTime;
                    _midiDragStartX = details.globalPosition.dx;
                    _midiDragCurrentX = details.globalPosition.dx;
                    _isCopyDrag = isCopy;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  // Check Alt/Option for snap bypass during drag
                  final bypassSnap = HardwareKeyboard.instance.isAltPressed;
                  setState(() {
                    _midiDragCurrentX = details.globalPosition.dx;
                    _snapBypassActive = bypassSnap;
                  });
                },
                onHorizontalDragEnd: (details) {
                  // Calculate final position with snap
                  var newStartTime = (_midiDragStartTime + (_midiDragCurrentX - _midiDragStartX) / _pixelsPerSecond)
                      .clamp(0.0, double.infinity);
                  newStartTime = _snapToGrid(newStartTime);

                  if (_isCopyDrag) {
                    // Copy: create new clip at new position
                    widget.onMidiClipCopied?.call(midiClip, newStartTime);
                  } else {
                    // Move: update existing clip position
                    // Use Rust clip ID (not Dart clip ID) for engine call
                    final rustClipId = widget.getRustClipId?.call(midiClip.clipId) ?? midiClip.clipId;
                    widget.audioEngine?.setClipStartTime(midiClip.trackId, rustClipId, newStartTime);
                    final updatedClip = midiClip.copyWith(startTime: newStartTime);
                    widget.onMidiClipUpdated?.call(updatedClip);
                  }

                  setState(() {
                    _draggingMidiClipId = null;
                    _isCopyDrag = false;
                    _snapBypassActive = false;
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDragging || isResizing
                            ? trackColor
                            : isSelected
                                ? trackColor.withValues(alpha: 1.0)
                                : trackColor.withValues(alpha: 0.7),
                        width: isDragging || isSelected || isResizing ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        // FL Studio style HEADER
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
                              if (repeatCount > 1)
                                Text(
                                  '×$repeatCount',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // CONTENT area with notes
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(3),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(3),
                              ),
                              child: Stack(
                                children: [
                                  // Mini piano roll preview with looping
                                  if (midiClip.notes.isNotEmpty)
                                    CustomPaint(
                                      size: Size(clipWidth - 8, contentHeight),
                                      painter: _MidiClipPainter(
                                        notes: midiClip.notes,
                                        clipDuration: displayDuration,
                                        contentDuration: contentDuration,
                                        color: trackColor,
                                        loopCount: repeatCount,
                                      ),
                                    ),
                                  // Loop divider lines
                                  if (repeatCount > 1 && contentDuration > 0)
                                    for (int i = 1; i < repeatCount; i++)
                                      Positioned(
                                        left: (contentDuration * i * _pixelsPerSecond) - 1,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 1,
                                          color: trackColor.withValues(alpha: 0.4),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Resize handle on right edge (free-form resize)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  setState(() {
                    _loopDraggingClipId = midiClip.clipId;
                    _loopDragStartX = details.globalPosition.dx;
                    _loopDragCurrentX = details.globalPosition.dx;
                    _resizeDragStartDuration = midiClip.duration;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _loopDragCurrentX = details.globalPosition.dx;
                  });
                },
                onHorizontalDragEnd: (details) {
                  // Calculate final duration from drag
                  final dragDelta = _loopDragCurrentX - _loopDragStartX;
                  final durationDelta = dragDelta / _pixelsPerSecond;
                  final rawDuration = (_resizeDragStartDuration + durationDelta).clamp(0.5, double.infinity);

                  // Snap duration to grid (zoom-dependent resolution)
                  final newDuration = _snapToGrid(rawDuration);

                  if ((newDuration - midiClip.duration).abs() > 0.01) {
                    final updatedClip = midiClip.copyWith(duration: newDuration);
                    widget.onMidiClipUpdated?.call(updatedClip);
                  }

                  setState(() {
                    _loopDraggingClipId = null;
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeRight,
                  child: Container(
                    width: 8,
                    decoration: BoxDecoration(
                      color: isResizing
                          ? trackColor.withValues(alpha: 0.8)
                          : trackColor.withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 2,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
          color: const Color(0xFF4CAF50).withOpacity(0.3),
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
            color: const Color(0xFF4CAF50).withOpacity(0.6),
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

}

/// Painter for the time ruler (bar numbers with beat subdivisions)
class _TimeRulerPainter extends CustomPainter {
  final double duration;
  final double pixelsPerSecond;
  final double tempo;

  _TimeRulerPainter({
    required this.duration,
    required this.pixelsPerSecond,
    required this.tempo,
  });

  /// Get the smallest grid subdivision to show based on zoom level
  double _getGridDivision(double pixelsPerBeat) {
    if (pixelsPerBeat < 10) return 4.0;     // Only bars
    if (pixelsPerBeat < 20) return 1.0;     // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;     // + half beats
    return 0.25;                             // + quarter beats
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate beat-based measurements
    final beatsPerSecond = tempo / 60.0;
    final pixelsPerBeat = pixelsPerSecond / beatsPerSecond;
    final gridDivision = _getGridDivision(pixelsPerBeat);

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
    return oldDelegate.duration != duration ||
           oldDelegate.pixelsPerSecond != pixelsPerSecond ||
           oldDelegate.tempo != tempo;
  }
}

/// Painter for the grid lines (beat-based with zoom-dependent visibility)
class _GridPainter extends CustomPainter {
  final double duration;
  final double pixelsPerSecond;
  final double tempo;

  _GridPainter({
    required this.duration,
    required this.pixelsPerSecond,
    required this.tempo,
  });

  /// Get the smallest grid subdivision to show based on zoom level
  double _getGridDivision(double pixelsPerBeat) {
    if (pixelsPerBeat < 10) return 4.0;     // Only bars (every 4 beats)
    if (pixelsPerBeat < 20) return 1.0;     // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;     // + half beats
    if (pixelsPerBeat < 80) return 0.25;    // + quarter beats
    return 0.125;                            // + eighth beats
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate beat-based measurements
    final beatsPerSecond = tempo / 60.0;
    final pixelsPerBeat = pixelsPerSecond / beatsPerSecond;
    final gridDivision = _getGridDivision(pixelsPerBeat);

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
    return oldDelegate.duration != duration ||
           oldDelegate.pixelsPerSecond != pixelsPerSecond ||
           oldDelegate.tempo != tempo;
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
      ..color = color.withOpacity(0.5) // Semi-transparent so grid shows through
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
      ..color = color.withOpacity(0.3)
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
    final paint = Paint()
      ..color = const Color(0xFF363636)
      ..strokeWidth = 0.5;

    // Draw subtle horizontal line in middle
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GridPatternPainter oldDelegate) => false;
}

/// Painter for mini MIDI clip preview with content looping
class _MidiClipPainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double clipDuration; // Total clip duration in seconds
  final double contentDuration; // Duration of one content iteration in seconds
  final Color color;
  final int loopCount; // How many times content repeats

  _MidiClipPainter({
    required this.notes,
    required this.clipDuration,
    required this.contentDuration,
    required this.color,
    this.loopCount = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || clipDuration == 0 || contentDuration == 0) return;

    // Find note range for vertical scaling
    final minNote = notes.map((n) => n.note).reduce(math.min);
    final maxNote = notes.map((n) => n.note).reduce(math.max);
    final noteRange = (maxNote - minNote).toDouble();
    final effectiveRange = noteRange == 0 ? 12.0 : noteRange; // At least one octave

    // Calculate pixels per second for the entire clip
    final pixelsPerSecond = size.width / clipDuration;
    final singleIterationWidth = contentDuration * pixelsPerSecond;
    final pixelsPerNote = size.height / (effectiveRange + 4); // Add padding

    // Draw notes for each loop iteration
    for (int loop = 0; loop < loopCount; loop++) {
      final loopOffsetX = loop * singleIterationWidth;

      // Skip if this loop starts beyond the clip width
      if (loopOffsetX >= size.width) break;

      for (final note in notes) {
        // Calculate note position in beats, then convert to seconds
        final noteStartInBeats = note.startTime;
        final noteDurationInBeats = note.duration;

        // For display, assume 120 BPM (2 beats per second)
        // This is just for visualization in the mini preview
        const tempo = 120.0;
        final noteStartInSeconds = (noteStartInBeats / tempo) * 60.0;
        final noteDurationInSeconds = (noteDurationInBeats / tempo) * 60.0;

        // Calculate pixel coordinates
        final x = loopOffsetX + (noteStartInSeconds * pixelsPerSecond);
        var width = noteDurationInSeconds * pixelsPerSecond;
        final y = size.height - ((note.note - minNote + 2) * pixelsPerNote);
        final height = pixelsPerNote * 0.8; // Slight gap between notes

        // Skip notes that would start beyond the clip
        if (x >= size.width) continue;

        // Clip width to not exceed the clip boundary
        if (x + width > size.width) {
          width = size.width - x;
        }

        // Draw note rectangle (FL Studio style: white bars with sharp corners)
        final rect = Rect.fromLTWH(x, y, math.max(width, 2.0), height);

        final notePaint = Paint()
          ..color = const Color(0xFFF5F5F5).withValues(alpha: 0.6)
          ..style = PaintingStyle.fill;

        canvas.drawRect(rect, notePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_MidiClipPainter oldDelegate) {
    return !listEquals(notes, oldDelegate.notes) ||
           clipDuration != oldDelegate.clipDuration ||
           contentDuration != oldDelegate.contentDuration ||
           color != oldDelegate.color ||
           loopCount != oldDelegate.loopCount;
  }
}

