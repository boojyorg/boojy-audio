import 'package:flutter/material.dart';
import 'dart:async';
import '../audio_engine.dart';
import 'track_mixer_strip.dart';
import '../utils/track_colors.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/track_commands.dart';
import 'platform_drop_target.dart';

/// Track data model
class TrackData {
  final int id;
  String name;
  final String type;
  double volumeDb;
  double pan;
  bool mute;
  bool solo;

  TrackData({
    required this.id,
    required this.name,
    required this.type,
    required this.volumeDb,
    required this.pan,
    required this.mute,
    required this.solo,
  });

  /// Parse track info from CSV format: "track_id,name,type,volume_db,pan,mute,solo"
  static TrackData? fromCSV(String csv) {
    try {
      final parts = csv.split(',');
      if (parts.length < 7) return null;

      return TrackData(
        id: int.parse(parts[0]),
        name: parts[1],
        type: parts[2],
        volumeDb: double.parse(parts[3]),
        pan: double.parse(parts[4]),
        mute: parts[5] == 'true' || parts[5] == '1',
        solo: parts[6] == 'true' || parts[6] == '1',
      );
    } catch (e) {
      debugPrint('❌ Failed to parse track data: $e');
      return null;
    }
  }
}

/// Track mixer panel - displays track mixer strips vertically aligned with timeline
class TrackMixerPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final ScrollController? scrollController; // For syncing with timeline
  final int? selectedTrackId; // Unified track selection
  final Function(int?)? onTrackSelected; // Unified selection callback
  final Function(int, String)? onInstrumentSelected; // (trackId, instrumentId)
  final Function(int, int)? onTrackDuplicated; // (sourceTrackId, newTrackId)
  final Function(int)? onTrackDeleted; // (trackId)
  final Map<int, InstrumentData>? trackInstruments;

  // M10: VST3 Plugin support
  final Map<int, int>? trackVst3PluginCounts; // trackId -> plugin count
  final Function(int)? onFxButtonPressed; // (trackId)
  final Function(int, Vst3Plugin)? onVst3PluginDropped; // (trackId, plugin)
  final Function(int)? onEditPluginsPressed; // (trackId) - M10

  // Audio file drag-and-drop
  final Function(String filePath)? onAudioFileDropped;

  // Callback when MIDI track is created from mixer (to add default clip)
  final Function(int trackId)? onMidiTrackCreated;

  // Engine ready state
  final bool isEngineReady;

  // Track height management (synced with timeline)
  final Map<int, double> trackHeights; // trackId -> height
  final double masterTrackHeight;
  final Function(int trackId, double height)? onTrackHeightChanged;
  final Function(double height)? onMasterTrackHeightChanged;

  // Panel toggle callback (clicking header hides panel)
  final VoidCallback? onTogglePanel;

  // Track color management
  final Color Function(int trackId, String trackName, String trackType)? getTrackColor;
  final Function(int trackId, Color color)? onTrackColorChanged;

  const TrackMixerPanel({
    super.key,
    required this.audioEngine,
    this.isEngineReady = false,
    this.scrollController,
    this.selectedTrackId,
    this.onTrackSelected,
    this.onInstrumentSelected,
    this.onTrackDuplicated,
    this.onTrackDeleted,
    this.trackInstruments,
    this.trackVst3PluginCounts,
    this.onFxButtonPressed,
    this.onVst3PluginDropped,
    this.onEditPluginsPressed, // M10
    this.onAudioFileDropped,
    this.onMidiTrackCreated,
    this.trackHeights = const {},
    this.masterTrackHeight = 60.0,
    this.onTrackHeightChanged,
    this.onMasterTrackHeightChanged,
    this.onTogglePanel,
    this.getTrackColor,
    this.onTrackColorChanged,
  });

  @override
  State<TrackMixerPanel> createState() => TrackMixerPanelState();
}

class TrackMixerPanelState extends State<TrackMixerPanel> {
  List<TrackData> _tracks = [];
  Timer? _refreshTimer;
  Timer? _levelTimer;
  Map<int, (double, double)> _peakLevels = {}; // (left, right) stereo peaks
  Map<int, (double, double)> _displayLevels = {}; // Smoothed levels with decay
  DateTime _lastLevelUpdate = DateTime.now();
  bool _isAudioFileDragging = false;

  @override
  void initState() {
    super.initState();
    _loadTracksAsync();

    // Refresh tracks every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _loadTracksAsync();
    });

    // Poll peak levels every 50ms for responsive meters
    _levelTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _updatePeakLevels();
    });
  }

  @override
  void didUpdateWidget(TrackMixerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload tracks when audio engine becomes available
    if (widget.audioEngine != null && oldWidget.audioEngine == null) {
      _loadTracksAsync();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _levelTimer?.cancel();
    super.dispose();
  }

  /// Update peak levels for all tracks with smooth decay
  /// Attack: instant, Decay: ~300-400ms for snappy feel
  void _updatePeakLevels() {
    if (widget.audioEngine == null || !mounted) return;

    final now = DateTime.now();
    final deltaMs = now.difference(_lastLevelUpdate).inMilliseconds;
    _lastLevelUpdate = now;

    // Decay rate: ~20dB per second → ~0.33 normalized per second
    // At 50ms poll rate: decay ~0.017 per frame
    final decayPerFrame = (deltaMs / 1000.0) * 0.33;

    final newLevels = <int, (double, double)>{};

    for (final track in _tracks) {
      try {
        final levelStr = widget.audioEngine!.getTrackPeakLevels(track.id);
        // Format: "peak_left_db,peak_right_db"
        final parts = levelStr.split(',');
        if (parts.length >= 2) {
          final leftDb = double.tryParse(parts[0]) ?? -96.0;
          final rightDb = double.tryParse(parts[1]) ?? -96.0;
          // Convert dB to 0.0-1.0 range: -60dB = 0.0, 0dB = 1.0
          final rawLeft = ((leftDb + 60.0) / 60.0).clamp(0.0, 1.0);
          final rawRight = ((rightDb + 60.0) / 60.0).clamp(0.0, 1.0);

          // Get previous display levels
          final prevLeft = _displayLevels[track.id]?.$1 ?? 0.0;
          final prevRight = _displayLevels[track.id]?.$2 ?? 0.0;

          // Instant attack (new peak higher), smooth decay (new peak lower)
          final displayLeft = rawLeft >= prevLeft
              ? rawLeft // Instant attack
              : (prevLeft - decayPerFrame).clamp(0.0, 1.0); // Smooth decay
          final displayRight = rawRight >= prevRight
              ? rawRight
              : (prevRight - decayPerFrame).clamp(0.0, 1.0);

          newLevels[track.id] = (displayLeft, displayRight);
        }
      } catch (e) {
        // Silently fail for level polling
      }
    }

    if (mounted && newLevels.isNotEmpty) {
      setState(() {
        _displayLevels = newLevels;
        _peakLevels = newLevels;
      });
    }
  }

  /// Public method to trigger immediate track refresh
  void refreshTracks() {
    _loadTracksAsync();
  }

  /// Load tracks asynchronously to avoid blocking UI thread
  Future<void> _loadTracksAsync() async {
    if (widget.audioEngine == null) return;

    try {
      final trackIds = await Future.microtask(() {
        return widget.audioEngine!.getAllTrackIds();
      });

      final tracks = <TrackData>[];

      for (int trackId in trackIds) {
        final info = await Future.microtask(() {
          return widget.audioEngine!.getTrackInfo(trackId);
        });

        final track = TrackData.fromCSV(info);
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
      debugPrint('❌ Failed to load tracks: $e');
    }
  }

  void _createTrack(String type) async {
    if (widget.audioEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio engine not ready'),
          backgroundColor: Color(0xFFFF5722),
        ),
      );
      return;
    }

    final name = '${type.toUpperCase()} ${_tracks.length + 1}';

    // Use UndoRedoManager for undoable track creation
    final command = CreateTrackCommand(
      trackType: type,
      trackName: name,
    );

    await UndoRedoManager().execute(command);

    if (command.createdTrackId != null && command.createdTrackId! >= 0) {
      _loadTracksAsync();

      // Notify parent to create default MIDI clip for MIDI tracks
      if (type == 'midi') {
        widget.onMidiTrackCreated?.call(command.createdTrackId!);
      }
    } else {
      // Show error to user when track creation fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create track - please try again'),
            backgroundColor: Color(0xFFFF5722),
          ),
        );
      }
    }
  }

  void _showAddTrackMenu() {
    // Find the button position
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // Show popup menu
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 380, // Position near the + button (380 is panel width)
        30, // Below the header
        overlay.size.width,
        0,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'audio',
          child: Row(
            children: const [
              Icon(Icons.audiotrack, size: 18, color: Color(0xFF202020)),
              SizedBox(width: 12),
              Text('Audio Track', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'midi',
          child: Row(
            children: const [
              Icon(Icons.piano, size: 18, color: Color(0xFF202020)),
              SizedBox(width: 12),
              Text('MIDI Track', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
      elevation: 8,
    ).then((value) {
      if (value != null) {
        _createTrack(value);
      }
    });
  }

  void _duplicateTrack(TrackData track) async {
    if (widget.audioEngine == null) return;

    // Use UndoRedoManager for undoable track duplication
    final command = DuplicateTrackCommand(
      sourceTrackId: track.id,
      sourceTrackName: track.name,
    );

    await UndoRedoManager().execute(command);

    if (command.duplicatedTrackId != null && command.duplicatedTrackId! >= 0) {
      debugPrint('✅ Track ${track.id} duplicated → new track ${command.duplicatedTrackId}');

      // Notify parent about duplication so it can copy instrument mapping
      widget.onTrackDuplicated?.call(track.id, command.duplicatedTrackId!);

      _loadTracksAsync();
    } else {
      debugPrint('❌ Failed to duplicate track ${track.id}');
    }
  }

  void _confirmDeleteTrack(TrackData track) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Track'),
        content: Text('Are you sure you want to delete "${track.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();

              // Use UndoRedoManager for undoable track deletion
              final command = DeleteTrackCommand(
                trackId: track.id,
                trackName: track.name,
                trackType: track.type,
                volumeDb: track.volumeDb,
                pan: track.pan,
                mute: track.mute,
                solo: track.solo,
              );

              await UndoRedoManager().execute(command);
              widget.onTrackDeleted?.call(track.id);
              _loadTracksAsync();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformDropTarget(
      onDragDone: (details) {
        // Handle audio file drops
        for (final file in details.files) {
          final ext = file.path.split('.').last.toLowerCase();
          if (['wav', 'mp3', 'flac', 'aif', 'aiff'].contains(ext)) {
            widget.onAudioFileDropped?.call(file.path);
            return; // Only handle first valid audio file
          }
        }
      },
      onDragEntered: (details) {
        setState(() {
          _isAudioFileDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isAudioFileDragging = false;
        });
      },
      child: Container(
        width: 380,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          border: Border(
            left: const BorderSide(color: Color(0xFF363636)),
            top: _isAudioFileDragging
                ? const BorderSide(color: Color(0xFF4CAF50), width: 3)
                : BorderSide.none,
            bottom: _isAudioFileDragging
                ? const BorderSide(color: Color(0xFF4CAF50), width: 3)
                : BorderSide.none,
            right: _isAudioFileDragging
                ? const BorderSide(color: Color(0xFF4CAF50), width: 3)
                : BorderSide.none,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                _buildHeader(),

                // Track strips (vertically scrollable)
                Expanded(
                  child: _tracks.isEmpty
                      ? _buildEmptyState()
                      : _buildTrackStrips(),
                ),
              ],
            ),
            // Drop indicator overlay
            if (_isAudioFileDragging)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Drop to create Audio track',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  Widget _buildHeader() {
    return Container(
      height: 30, // Match timeline ruler height
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF363636),
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Row(
        children: [
          // Clickable header to toggle panel
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTogglePanel,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune,
                    color: Color(0xFFE0E0E0),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'TRACK MIXER',
                    style: TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Add track button (disabled until engine ready)
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: widget.isEngineReady
                ? const Color(0xFFE0E0E0)
                : const Color(0xFF505050),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: widget.isEngineReady ? _showAddTrackMenu : null,
            tooltip: widget.isEngineReady
                ? 'Add track'
                : 'Waiting for audio engine...',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.audio_file_outlined,
            size: 48,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 16),
          Text(
            'No tracks yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a track to get started',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackStrips() {
    // Separate regular tracks from master track
    final regularTracks = _tracks.where((t) => t.type != 'Master').toList();
    final masterTrack = _tracks.firstWhere(
      (t) => t.type == 'Master',
      orElse: () => TrackData(
        id: -1,
        name: 'Master',
        type: 'Master',
        volumeDb: 0.0,
        pan: 0.0,
        mute: false,
        solo: false,
      ),
    );

    return Column(
      children: [
        // Regular tracks in scrollable area
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            child: Column(
              children: regularTracks.asMap().entries.map((entry) {
                final index = entry.key;
                final track = entry.value;
                // Use auto-detected color with override support, fallback to index-based
                final trackColor = widget.getTrackColor?.call(track.id, track.name, track.type)
                    ?? TrackColors.getTrackColor(index);

                return TrackMixerStrip(
                    key: ValueKey(track.id),
                    trackId: track.id,
                    trackName: track.name,
                    trackType: track.type,
                    volumeDb: track.volumeDb,
                    pan: track.pan,
                    isMuted: track.mute,
                    isSoloed: track.solo,
                    peakLevelLeft: _peakLevels[track.id]?.$1 ?? 0.0,
                    peakLevelRight: _peakLevels[track.id]?.$2 ?? 0.0,
                    trackColor: trackColor,
                    audioEngine: widget.audioEngine,
                    isSelected: widget.selectedTrackId == track.id,
                    instrumentData: widget.trackInstruments?[track.id],
                    onInstrumentSelect: (instrumentId) {
                      widget.onInstrumentSelected?.call(track.id, instrumentId);
                    },
                    vst3PluginCount: widget.trackVst3PluginCounts?[track.id] ?? 0, // M10
                    onFxButtonPressed: () => widget.onFxButtonPressed?.call(track.id), // M10
                    onVst3PluginDropped: (plugin) => widget.onVst3PluginDropped?.call(track.id, plugin), // M10
                    onEditPluginsPressed: () => widget.onEditPluginsPressed?.call(track.id), // M10
                    trackHeight: widget.trackHeights[track.id] ?? 100.0,
                    onHeightChanged: (height) {
                      widget.onTrackHeightChanged?.call(track.id, height);
                    },
                    onTap: () {
                      widget.onTrackSelected?.call(track.id);
                    },
                    onVolumeChanged: (volumeDb) {
                      setState(() {
                        track.volumeDb = volumeDb;
                      });
                      widget.audioEngine?.setTrackVolume(track.id, volumeDb);
                    },
                    onPanChanged: (pan) {
                      setState(() {
                        track.pan = pan;
                      });
                      widget.audioEngine?.setTrackPan(track.id, pan);
                    },
                    onMuteToggle: () {
                      setState(() {
                        track.mute = !track.mute;
                      });
                      widget.audioEngine?.setTrackMute(track.id, track.mute);
                    },
                    onSoloToggle: () {
                      setState(() {
                        track.solo = !track.solo;
                      });
                      widget.audioEngine?.setTrackSolo(track.id, track.solo);
                    },
                    onDuplicatePressed: () => _duplicateTrack(track),
                    onDeletePressed: () => _confirmDeleteTrack(track),
                    onNameChanged: (newName) {
                      widget.audioEngine?.setTrackName(track.id, newName);
                      setState(() {
                        track.name = newName;
                      });
                    },
                    onColorChanged: widget.onTrackColorChanged != null
                        ? (color) => widget.onTrackColorChanged!(track.id, color)
                        : null,
                  );
                }).toList(),
            ),
          ),
        ),

        // Master track pinned at bottom (outside scroll area)
        if (masterTrack.id != -1)
          MasterTrackMixerStrip(
            volumeDb: masterTrack.volumeDb,
            pan: masterTrack.pan,
            peakLevelLeft: _peakLevels[masterTrack.id]?.$1 ?? 0.0,
            peakLevelRight: _peakLevels[masterTrack.id]?.$2 ?? 0.0,
            trackHeight: widget.masterTrackHeight,
            onHeightChanged: widget.onMasterTrackHeightChanged,
            onVolumeChanged: (volumeDb) {
              setState(() {
                masterTrack.volumeDb = volumeDb;
              });
              widget.audioEngine?.setTrackVolume(masterTrack.id, volumeDb);
            },
            onPanChanged: (pan) {
              setState(() {
                masterTrack.pan = pan;
              });
              widget.audioEngine?.setTrackPan(masterTrack.id, pan);
            },
          ),
      ],
    );
  }

}
