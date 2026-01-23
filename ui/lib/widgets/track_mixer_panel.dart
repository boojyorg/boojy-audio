import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../audio_engine.dart';
import 'track_mixer_strip.dart';
import 'instrument_browser.dart';
import '../utils/track_colors.dart';
import '../models/instrument_data.dart';
import '../models/track_automation_data.dart';
import '../models/track_data.dart';
import '../models/vst3_plugin_data.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/track_commands.dart';
import 'platform_drop_target.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';

/// Track mixer panel - displays track mixer strips vertically aligned with timeline
class TrackMixerPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final ScrollController? scrollController; // For syncing with timeline
  final int? selectedTrackId; // Unified track selection
  final Set<int>? selectedTrackIds; // Multi-track selection
  final Function(int?, {bool isShiftHeld})? onTrackSelected; // Unified selection callback with shift state
  final Function(int, String)? onInstrumentSelected; // (trackId, instrumentId)
  final Function(int, int)? onTrackDuplicated; // (sourceTrackId, newTrackId)
  final Function(int)? onTrackDeleted; // (trackId)
  final Function(int)? onConvertToSampler; // (trackId) - Convert Audio track to Sampler
  final Map<int, InstrumentData>? trackInstruments;

  // M10: VST3 Plugin support
  final Map<int, int>? trackVst3PluginCounts; // trackId -> plugin count
  final Function(int)? onFxButtonPressed; // (trackId)
  final Function(int, Vst3Plugin)? onVst3PluginDropped; // (trackId, plugin)
  final Function(int, Vst3Plugin)? onVst3InstrumentDropped; // (trackId, vst3 instrument)
  final Function(int, Instrument)? onInstrumentDropped; // (trackId, built-in instrument)
  final Function(int)? onEditPluginsPressed; // (trackId) - M10

  // Audio file drag-and-drop
  final Function(String filePath)? onAudioFileDropped;

  // Callback when MIDI track is created from mixer (to add default clip)
  final Function(int trackId)? onMidiTrackCreated;

  // Callback when any track is created from mixer (to refresh timeline)
  final Function(int trackId, String trackType)? onTrackCreated;

  // Callback when tracks are reordered via drag-and-drop
  final Function(int oldIndex, int newIndex)? onTrackReordered;

  // Track order (synced from TrackController)
  final List<int> trackOrder;

  // Callback to sync track IDs when loaded from engine
  final Function(List<int> trackIds)? onTrackOrderSync;

  // Engine ready state
  final bool isEngineReady;

  // Track height management (synced with timeline)
  final Map<int, double> clipHeights; // trackId -> clip area height
  final Map<int, double> automationHeights; // trackId -> automation lane height
  final double masterTrackHeight;
  final Function(int trackId, double height)? onClipHeightChanged;
  final Function(int trackId, double height)? onAutomationHeightChanged;
  final Function(double height)? onMasterTrackHeightChanged;

  // Panel width (for responsive layout)
  final double panelWidth;

  // Panel toggle callback (clicking header hides panel)
  final VoidCallback? onTogglePanel;

  // Track color management
  final Color Function(int trackId, String trackName, String trackType)? getTrackColor;
  final Function(int trackId, Color color)? onTrackColorChanged;

  // Track name changed callback (for marking as user-edited)
  final Function(int trackId, String newName)? onTrackNameChanged;

  // Double-click track to open editor
  final Function(int trackId)? onTrackDoubleClick;

  // Automation state
  final int? automationVisibleTrackId;
  final Function(int trackId)? onAutomationToggle;
  final TrackAutomationLane? Function(int trackId)? getAutomationLane;
  final double pixelsPerBeat;
  final double totalBeats;
  final Function(int trackId, AutomationPoint point)? onAutomationPointAdded;
  final Function(int trackId, String pointId, AutomationPoint point)? onAutomationPointUpdated;
  final Function(int trackId, String pointId)? onAutomationPointDeleted;

  // Automation parameter controls
  final AutomationParameter Function(int trackId)? getSelectedParameter;
  final Function(int trackId, AutomationParameter param)? onParameterChanged;
  final Function(int trackId)? onResetParameter;
  final Function(int trackId)? onAddParameter;

  // Automation preview values (for live value display during drag)
  final Map<int, double?> automationPreviewValues;
  final Function(int trackId, double? value)? onAutomationPreviewValue;

  const TrackMixerPanel({
    super.key,
    required this.audioEngine,
    this.isEngineReady = false,
    this.scrollController,
    this.selectedTrackId,
    this.selectedTrackIds,
    this.onTrackSelected,
    this.onInstrumentSelected,
    this.onTrackDuplicated,
    this.onTrackDeleted,
    this.onConvertToSampler,
    this.trackInstruments,
    this.trackVst3PluginCounts,
    this.onFxButtonPressed,
    this.onVst3PluginDropped,
    this.onVst3InstrumentDropped,
    this.onInstrumentDropped,
    this.onEditPluginsPressed, // M10
    this.onAudioFileDropped,
    this.onMidiTrackCreated,
    this.onTrackCreated,
    this.onTrackReordered,
    this.trackOrder = const [],
    this.onTrackOrderSync,
    this.clipHeights = const {},
    this.automationHeights = const {},
    this.masterTrackHeight = 60.0,
    this.onClipHeightChanged,
    this.onAutomationHeightChanged,
    this.onMasterTrackHeightChanged,
    this.panelWidth = 380.0,
    this.onTogglePanel,
    this.getTrackColor,
    this.onTrackColorChanged,
    this.onTrackNameChanged,
    this.onTrackDoubleClick,
    this.automationVisibleTrackId,
    this.onAutomationToggle,
    this.getAutomationLane,
    this.pixelsPerBeat = 20.0,
    this.totalBeats = 256.0,
    this.onAutomationPointAdded,
    this.onAutomationPointUpdated,
    this.onAutomationPointDeleted,
    this.getSelectedParameter,
    this.onParameterChanged,
    this.onResetParameter,
    this.onAddParameter,
    this.automationPreviewValues = const {},
    this.onAutomationPreviewValue,
  });

  @override
  State<TrackMixerPanel> createState() => TrackMixerPanelState();
}

class TrackMixerPanelState extends State<TrackMixerPanel> {
  List<TrackData> _tracks = [];
  Timer? _refreshTimer;

  /// Public getter for tracks (used by parent to access track state)
  List<TrackData> get tracks => _tracks;
  Timer? _levelTimer;
  Map<int, (double, double)> _peakLevels = {}; // (left, right) stereo peaks
  Map<int, (double, double)> _displayLevels = {}; // Smoothed levels with decay
  DateTime _lastLevelUpdate = DateTime.now();
  bool _isAudioFileDragging = false;
  bool _forceDecayToZero = false; // When true, decay all meters to zero

  // Drag-and-drop state
  int? _draggingIndex;         // Current position of dragged track in the list
  int? _originalDraggingIndex; // Original position when drag started (for cancel/revert)
  Offset? _dragStartPosition;
  double _dragOffsetY = 0.0;
  bool _dragActivated = false;
  static const double _dragThreshold = 8.0;

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
        // When forcing decay to zero (after stop), use 0.0 as target
        double rawLeft = 0.0;
        double rawRight = 0.0;

        if (!_forceDecayToZero) {
          final levelStr = widget.audioEngine!.getTrackPeakLevels(track.id);
          // Format: "peak_left_db,peak_right_db"
          final parts = levelStr.split(',');
          if (parts.length >= 2) {
            final leftDb = double.tryParse(parts[0]) ?? -96.0;
            final rightDb = double.tryParse(parts[1]) ?? -96.0;
            // Convert dB to 0.0-1.0 range: -60dB = 0.0, 0dB = 1.0
            rawLeft = ((leftDb + 60.0) / 60.0).clamp(0.0, 1.0);
            rawRight = ((rightDb + 60.0) / 60.0).clamp(0.0, 1.0);
          }
        }

        // Get previous display levels
        final prevLeft = _displayLevels[track.id]?.$1 ?? 0.0;
        final prevRight = _displayLevels[track.id]?.$2 ?? 0.0;

        // Instant attack (new peak strictly higher), smooth decay otherwise
        // Using > instead of >= ensures decay happens when values are equal
        // (which occurs when audio engine returns stale/unchanged values)
        final displayLeft = rawLeft > prevLeft
            ? rawLeft // Instant attack
            : (prevLeft - decayPerFrame).clamp(0.0, 1.0); // Smooth decay
        final displayRight = rawRight > prevRight
            ? rawRight
            : (prevRight - decayPerFrame).clamp(0.0, 1.0);

        newLevels[track.id] = (displayLeft, displayRight);
      } catch (e) {
        // Silently fail for level polling
      }
    }

    // Clear force decay flag once all meters have decayed to zero
    if (_forceDecayToZero) {
      final allZero = newLevels.values.every((l) => l.$1 < 0.01 && l.$2 < 0.01);
      if (allZero) {
        _forceDecayToZero = false;
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

  /// Decay all meters smoothly to zero (call when playback stops)
  void resetMeters() {
    if (!mounted) return;
    // Set flag to force decay - the timer will smoothly decay all meters to zero
    _forceDecayToZero = true;
  }

  /// Load tracks asynchronously to avoid blocking UI thread
  /// Uses track order from TrackController (widget.trackOrder)
  Future<void> _loadTracksAsync() async {
    if (widget.audioEngine == null) return;

    try {
      final trackIds = await Future.microtask(() {
        return widget.audioEngine!.getAllTrackIds();
      });

      final tracksMap = <int, TrackData>{};

      for (final int trackId in trackIds) {
        final info = await Future.microtask(() {
          return widget.audioEngine!.getTrackInfo(trackId);
        });

        final track = TrackData.fromCSV(info);
        if (track != null) {
          tracksMap[track.id] = track;
        }
      }

      if (mounted) {
        // Separate master track (not reorderable)
        final masterTrack = tracksMap.values.where((t) => t.type == 'Master').toList();
        final regularTrackIds = tracksMap.keys.where((id) => tracksMap[id]!.type != 'Master').toList();

        // Sync track IDs to TrackController (it will preserve existing order)
        widget.onTrackOrderSync?.call(regularTrackIds);

        setState(() {
          // Build ordered track list using widget.trackOrder
          final orderedTracks = <TrackData>[];

          // First add tracks in the order from TrackController
          for (final id in widget.trackOrder) {
            if (tracksMap.containsKey(id) && tracksMap[id]!.type != 'Master') {
              orderedTracks.add(tracksMap[id]!);
            }
          }

          // Add any tracks not in the order list (new tracks)
          for (final id in regularTrackIds) {
            if (!widget.trackOrder.contains(id)) {
              orderedTracks.add(tracksMap[id]!);
            }
          }

          // Add master track at the end (it's handled separately in UI)
          orderedTracks.addAll(masterTrack);

          _tracks = orderedTracks;
        });
      }
    } catch (e) {
      debugPrint('TrackMixerPanel: Error loading tracks: $e');
    }
  }

  Future<void> _createTrack(String type) async {
    if (widget.audioEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Audio engine not ready'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }

    // Use simple type name - visual numbering comes from displayIndex
    final name = type == 'audio' ? 'Audio' : 'MIDI';

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

      // Notify parent to refresh timeline (for both MIDI and Audio tracks)
      widget.onTrackCreated?.call(command.createdTrackId!, type);
    } else {
      // Show error to user when track creation fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to create track - please try again'),
            backgroundColor: context.colors.error,
          ),
        );
      }
    }
  }

  /// Handle arm button toggle with exclusive arm behavior for MIDI tracks.
  /// Clicking arm on a MIDI track disarms all other MIDI tracks (Ableton-style).
  void _handleArmToggle(TrackData track, List<TrackData> allTracks) {
    setState(() {
      if (!track.armed) {
        // Arming this track - disarm all other MIDI tracks (exclusive arm)
        for (final t in allTracks) {
          if (t.type == 'midi' && t.id != track.id && t.armed) {
            t.armed = false;
            widget.audioEngine?.setTrackArmed(t.id, armed: false);
          }
        }
      }
      // Toggle this track's arm state
      track.armed = !track.armed;
    });
    widget.audioEngine?.setTrackArmed(track.id, armed: track.armed);
  }

  /// Handle Shift+click on arm button for multi-arm mode.
  /// Just toggles this track without affecting others (allows layering).
  void _handleArmShiftClick(TrackData track) {
    setState(() {
      track.armed = !track.armed;
    });
    widget.audioEngine?.setTrackArmed(track.id, armed: track.armed);
  }

  Future<void> _duplicateTrack(TrackData track) async {
    if (widget.audioEngine == null) return;

    // Use UndoRedoManager for undoable track duplication
    final command = DuplicateTrackCommand(
      sourceTrackId: track.id,
      sourceTrackName: track.name,
    );

    await UndoRedoManager().execute(command);

    if (command.duplicatedTrackId != null && command.duplicatedTrackId! >= 0) {

      // Notify parent about duplication so it can copy instrument mapping
      widget.onTrackDuplicated?.call(track.id, command.duplicatedTrackId!);

      _loadTracksAsync();
    } else {
      debugPrint('TrackMixerPanel: Failed to duplicate track ${track.name}');
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
        width: widget.panelWidth,
        decoration: BoxDecoration(
          color: context.colors.standard,
          border: Border(
            left: BorderSide(color: context.colors.elevated),
            top: _isAudioFileDragging
                ? BorderSide(color: context.colors.success, width: 3)
                : BorderSide.none,
            bottom: _isAudioFileDragging
                ? BorderSide(color: context.colors.success, width: 3)
                : BorderSide.none,
            right: _isAudioFileDragging
                ? BorderSide(color: context.colors.success, width: 3)
                : BorderSide.none,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Header (24px to match timeline nav bar)
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
                child: ColoredBox(
                  color: context.colors.success.withValues(alpha: 0.1),
                  child: Center(
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
                            'Drop to create Audio track',
                            style: TextStyle(
                              color: context.colors.textPrimary,
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
      height: 24, // Match timeline nav bar height
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.elevated,
        border: Border(
          bottom: BorderSide(color: context.colors.elevated),
        ),
      ),
      child: Row(
        children: [
          // Toggle arrow button - points right to collapse (hide mixer)
          Tooltip(
            message: 'Hide Mixer',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTogglePanel,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chevron_right,
                    color: context.colors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.tune,
            color: context.colors.textPrimary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'TRACK MIXER',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Add track button (disabled until engine ready)
          if (widget.isEngineReady)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.add_circle_outline,
                color: context.colors.textPrimary,
                size: 18,
              ),
              tooltip: 'Add track',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onSelected: (value) {
                if (mounted) {
                  _createTrack(value);
                }
              },
              itemBuilder: (menuContext) {
                // Use menuContext for colors in popup menu callback
                final colors = Provider.of<ThemeProvider>(menuContext, listen: false).colors;
                return [
                  PopupMenuItem<String>(
                    value: 'audio',
                    child: Row(
                      children: [
                        Icon(Icons.audiotrack, size: 18, color: colors.darkest),
                        const SizedBox(width: 12),
                        const Text('Audio Track', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'midi',
                    child: Row(
                      children: [
                        Icon(Icons.piano, size: 18, color: colors.darkest),
                        const SizedBox(width: 12),
                        const Text('MIDI Track', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ];
              },
            )
          else
            Tooltip(
              message: 'Waiting for audio engine...',
              child: Icon(
                Icons.add_circle_outline,
                color: context.colors.textMuted,
                size: 18,
              ),
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
            color: context.colors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No tracks yet',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a track to get started',
            style: TextStyle(
              color: context.colors.textMuted,
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
        armed: false,
      ),
    );

    return Column(
      children: [
        // Regular tracks with drag-and-drop
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background column with gap animation
                Column(
                  children: [
                    ...regularTracks.asMap().entries.map((entry) {
                      final index = entry.key;
                      final track = entry.value;
                      return _buildDraggableTrackWrapper(track, index, regularTracks);
                    }),
                    // Buffer spacer at the end
                    const SizedBox(height: 160),
                  ],
                ),
                // Dragged track rendered on top (if dragging)
                if (_dragActivated && _draggingIndex != null && _draggingIndex! < regularTracks.length)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _calculateDraggedTrackTop(regularTracks),
                    child: IgnorePointer(
                      child: Material(
                        elevation: 8,
                        color: Colors.transparent,
                        shadowColor: Colors.black.withValues(alpha: 0.5),
                        child: _buildTrackStrip(
                          regularTracks[_draggingIndex!],
                          _draggingIndex!,
                          regularTracks,
                        ),
                      ),
                    ),
                  ),
              ],
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
            stripWidth: widget.panelWidth,
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

  /// Build a draggable track wrapper - live reordering (no gap animation needed)
  Widget _buildDraggableTrackWrapper(TrackData track, int index, List<TrackData> allTracks) {
    final trackHeight = widget.clipHeights[track.id] ?? 100.0;
    final isDragging = _draggingIndex == index;

    return KeyedSubtree(
      key: ValueKey(track.id),
      child: MouseRegion(
        cursor: _dragActivated
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) => _onDragStart(index, details),
          onPanUpdate: (details) => _onDragUpdate(details, allTracks),
          onPanEnd: (details) => _onDragEnd(allTracks),
          onPanCancel: _onDragCancel, // CRITICAL: Handle arena loss
          child: isDragging && _dragActivated
              ? SizedBox(height: trackHeight, width: 380) // Placeholder for dragged track
              : IgnorePointer(
                  ignoring: _dragActivated, // Disable controls during any drag
                  child: _buildTrackStrip(track, index, allTracks),
                ),
        ),
      ),
    );
  }

  /// Called when drag starts
  void _onDragStart(int index, DragStartDetails details) {
    setState(() {
      _draggingIndex = index;
      _originalDraggingIndex = index; // Remember original position for cancel
      _dragStartPosition = details.globalPosition;
      _dragOffsetY = 0.0;
      _dragActivated = false; // Not yet - wait for threshold
    });
  }

  /// Called during drag movement - live reorder when crossing track boundaries
  void _onDragUpdate(DragUpdateDetails details, List<TrackData> tracks) {
    if (_draggingIndex == null || _dragStartPosition == null) return;

    // Check threshold
    if (!_dragActivated) {
      final distance = (details.globalPosition - _dragStartPosition!).distance;
      if (distance < _dragThreshold) return; // Not yet
      _dragActivated = true;
    }

    final newOffsetY = details.globalPosition.dy - _dragStartPosition!.dy;

    // Calculate gap index based on dragged track center position
    final draggedHeight = widget.clipHeights[tracks[_draggingIndex!].id] ?? 100.0;
    double originalTop = 0;
    for (int i = 0; i < _draggingIndex!; i++) {
      originalTop += widget.clipHeights[tracks[i].id] ?? 100.0;
    }
    final draggedCenter = originalTop + newOffsetY + (draggedHeight / 2);

    // Find insertion point
    int newGapIndex = _draggingIndex!;
    double cumulativeHeight = 0;
    for (int i = 0; i < tracks.length; i++) {
      final itemHeight = widget.clipHeights[tracks[i].id] ?? 100.0;
      final itemMidpoint = cumulativeHeight + (itemHeight / 2);

      if (i < _draggingIndex! && draggedCenter < itemMidpoint) {
        newGapIndex = i;
        break;
      } else if (i > _draggingIndex! && draggedCenter > itemMidpoint) {
        newGapIndex = i;
      }
      cumulativeHeight += itemHeight;
    }

    newGapIndex = newGapIndex.clamp(0, tracks.length - 1);

    // Live reorder: when gap changes, actually move the track
    if (newGapIndex != _draggingIndex) {
      final fromIndex = _draggingIndex!;
      final toIndex = newGapIndex;

      // Reorder local tracks list
      final track = _tracks.removeAt(fromIndex);
      _tracks.insert(toIndex, track);

      // Notify parent (syncs timeline live)
      widget.onTrackReordered?.call(fromIndex, toIndex);

      // Update dragging index to new position
      _draggingIndex = toIndex;

      // Adjust drag start position so the track stays under cursor
      // When moving down, we need to add the heights of tracks we passed
      // When moving up, we need to subtract the heights of tracks we passed
      if (toIndex > fromIndex) {
        // Moved down - adjust start position up by the height of the track we passed
        final passedTrackHeight = widget.clipHeights[tracks[fromIndex].id] ?? 100.0;
        _dragStartPosition = Offset(_dragStartPosition!.dx, _dragStartPosition!.dy + passedTrackHeight);
      } else {
        // Moved up - adjust start position down by the height of the track we passed
        final passedTrackHeight = widget.clipHeights[tracks[toIndex].id] ?? 100.0;
        _dragStartPosition = Offset(_dragStartPosition!.dx, _dragStartPosition!.dy - passedTrackHeight);
      }
    }

    setState(() {
      _dragOffsetY = details.globalPosition.dy - _dragStartPosition!.dy;
    });
  }

  /// Called when drag ends - just reset state (reorder already happened live)
  void _onDragEnd(List<TrackData> tracks) {
    _resetDragState();
  }

  /// Called when drag is cancelled (gesture arena loss)
  void _onDragCancel() {
    // Revert to original position if drag was cancelled
    if (_dragActivated && _originalDraggingIndex != null && _draggingIndex != null) {
      final currentIndex = _draggingIndex!;
      final originalIndex = _originalDraggingIndex!;

      if (currentIndex != originalIndex) {
        // Revert the reorder
        final track = _tracks.removeAt(currentIndex);
        _tracks.insert(originalIndex, track);

        // Notify parent to revert
        widget.onTrackReordered?.call(currentIndex, originalIndex);
      }
    }

    _resetDragState();
  }

  /// Reset all drag state
  void _resetDragState() {
    setState(() {
      _draggingIndex = null;
      _originalDraggingIndex = null;
      _dragStartPosition = null;
      _dragOffsetY = 0.0;
      _dragActivated = false;
    });
  }

  /// Calculate top position of dragged track (for visual positioning)
  double _calculateDraggedTrackTop(List<TrackData> tracks) {
    if (_draggingIndex == null) return 0;
    double top = 0;
    for (int i = 0; i < _draggingIndex!; i++) {
      top += widget.clipHeights[tracks[i].id] ?? 100.0;
    }
    return top + _dragOffsetY;
  }

  /// Build the TrackMixerStrip widget
  Widget _buildTrackStrip(TrackData track, int index, List<TrackData> allTracks) {
    final trackColor = widget.getTrackColor?.call(track.id, track.name, track.type)
        ?? TrackColors.getTrackColor(index);

    return TrackMixerStrip(
      trackId: track.id,
      displayIndex: index + 1, // 1-based sequential number
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
      isSelected: widget.selectedTrackIds?.contains(track.id) ?? widget.selectedTrackId == track.id,
      instrumentData: widget.trackInstruments?[track.id],
      onInstrumentSelect: (instrumentId) {
        widget.onInstrumentSelected?.call(track.id, instrumentId);
      },
      vst3PluginCount: widget.trackVst3PluginCounts?[track.id] ?? 0,
      onFxButtonPressed: () => widget.onFxButtonPressed?.call(track.id),
      onVst3PluginDropped: (plugin) => widget.onVst3PluginDropped?.call(track.id, plugin),
      onVst3InstrumentDropped: (plugin) => widget.onVst3InstrumentDropped?.call(track.id, plugin),
      onInstrumentDropped: (instrument) => widget.onInstrumentDropped?.call(track.id, instrument),
      onEditPluginsPressed: () => widget.onEditPluginsPressed?.call(track.id),
      clipHeight: widget.clipHeights[track.id] ?? 100.0,
      automationHeight: widget.automationHeights[track.id] ?? 60.0,
      stripWidth: widget.panelWidth,
      onClipHeightChanged: (height) {
        widget.onClipHeightChanged?.call(track.id, height);
      },
      onAutomationHeightChanged: (height) {
        widget.onAutomationHeightChanged?.call(track.id, height);
      },
      onTap: (isShiftHeld) {
        widget.onTrackSelected?.call(track.id, isShiftHeld: isShiftHeld);
      },
      onDoubleTap: () {
        widget.onTrackDoubleClick?.call(track.id);
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
        widget.audioEngine?.setTrackMute(track.id, mute: track.mute);
      },
      onSoloToggle: () {
        setState(() {
          track.solo = !track.solo;
        });
        widget.audioEngine?.setTrackSolo(track.id, solo: track.solo);
      },
      isArmed: track.armed,
      onArmToggle: () => _handleArmToggle(track, allTracks),
      onArmShiftClick: () => _handleArmShiftClick(track),
      showAutomation: widget.automationVisibleTrackId == track.id,
      onAutomationToggle: () => widget.onAutomationToggle?.call(track.id),
      selectedParameter: widget.getSelectedParameter?.call(track.id) ?? AutomationParameter.volume,
      onParameterChanged: (param) => widget.onParameterChanged?.call(track.id, param),
      onResetParameter: () => widget.onResetParameter?.call(track.id),
      onAddParameter: () => widget.onAddParameter?.call(track.id),
      automationLane: widget.getAutomationLane?.call(track.id),
      pixelsPerBeat: widget.pixelsPerBeat,
      totalBeats: widget.totalBeats,
      onAutomationPointAdded: (point) => widget.onAutomationPointAdded?.call(track.id, point),
      onAutomationPointUpdated: (pointId, point) => widget.onAutomationPointUpdated?.call(track.id, pointId, point),
      onAutomationPointDeleted: (pointId) => widget.onAutomationPointDeleted?.call(track.id, pointId),
      onPreviewValue: (value) => widget.onAutomationPreviewValue?.call(track.id, value),
      previewParameterValue: widget.automationPreviewValues[track.id],
      onDuplicatePressed: () => _duplicateTrack(track),
      onDeletePressed: () => _confirmDeleteTrack(track),
      onConvertToSampler: track.type.toLowerCase() == 'audio' && widget.onConvertToSampler != null
          ? () => widget.onConvertToSampler!(track.id)
          : null,
      onNameChanged: (newName) async {
        final oldName = track.name;
        if (oldName == newName) return;

        final command = RenameTrackCommand(
          trackId: track.id,
          oldName: oldName,
          newName: newName,
          onTrackRenamed: (trackId, name) {
            if (mounted) {
              setState(() {
                track.name = name;
              });
              widget.onTrackNameChanged?.call(trackId, name);
            }
          },
        );
        await UndoRedoManager().execute(command);
      },
      onColorChanged: widget.onTrackColorChanged != null
          ? (color) => widget.onTrackColorChanged!(track.id, color)
          : null,
    );
  }
}
