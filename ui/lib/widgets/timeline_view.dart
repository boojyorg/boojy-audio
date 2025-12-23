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
  double _pixelsPerBeat = 50.0; // Zoom level (beat-based, tempo-independent)
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

  // Edge resize state for MIDI clips (arrangement length)
  int? _resizingMidiClipId;
  double _resizeStartDuration = 0.0;
  double _resizeStartX = 0.0;

  // Drag-to-create new clip state
  bool _isDraggingNewClip = false;
  double _newClipStartBeats = 0.0;
  double _newClipEndBeats = 0.0;
  int? _newClipTrackId; // null = create new track, otherwise create clip on existing track

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
          pixelsPerBeat: _pixelsPerBeat,
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

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 8.0; // Track height minus padding

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
            height: totalHeight,
            decoration: BoxDecoration(
              border: Border.all(
                color: isDragging
                    ? trackColor
                    : trackColor.withValues(alpha: 0.7),
                width: isDragging ? 2 : 1,
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
        ),
      ),
    );
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

    final isSelected = widget.selectedMidiClipId == midiClip.clipId;
    final isDragging = _draggingMidiClipId == midiClip.clipId;

    const headerHeight = 18.0;
    final totalHeight = trackHeight - 8.0; // Track height minus padding

    return Positioned(
      left: clipX,
      top: 4,
      child: GestureDetector(
        onTap: () {
          // Single-click to open in piano roll editor
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
          // Calculate final position with beat-based snapping
          final startBeats = _midiDragStartTime;
          final dragDeltaBeats = (_midiDragCurrentX - _midiDragStartX) / _pixelsPerBeat;
          var newStartBeats = (startBeats + dragDeltaBeats).clamp(0.0, double.infinity);

          // Snap to beat grid (unless Alt/Option bypasses snap)
          if (!_snapBypassActive) {
            final snapResolution = _getGridSnapResolution();
            newStartBeats = (newStartBeats / snapResolution).round() * snapResolution;
          }

          if (_isCopyDrag) {
            // Copy: create new clip at new position (in beats)
            widget.onMidiClipCopied?.call(midiClip, newStartBeats);
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
          });
        },
        child: MouseRegion(
          cursor: _resizingMidiClipId == midiClip.clipId
              ? SystemMouseCursors.resizeRight
              : SystemMouseCursors.grab,
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
                            ? trackColor.withValues(alpha: 1.0)
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

