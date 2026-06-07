import 'package:flutter/material.dart';

import 'dart:async';
import '../audio_engine.dart';
import 'track_mixer_strip.dart';
import '../utils/track_colors.dart';
import '../models/instrument_data.dart';
import '../constants/ui_constants.dart';
import '../models/track_data.dart';
import '../models/track_send_data.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/track_commands.dart';
import '../services/commands/mixer_commands.dart';
import '../services/commands/send_commands.dart';
import 'platform_drop_target.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

import '../utils/logger.dart';
import 'mixer/mixer_models.dart';
import 'timeline/timeline_models.dart';

/// Track mixer panel - displays track mixer strips vertically aligned with timeline
class TrackMixerPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final ScrollController? scrollController; // For syncing with timeline
  final Map<int, InstrumentData>? trackInstruments;
  final Map<int, int>? trackVst3PluginCounts; // trackId -> plugin count

  // Audio file drag-and-drop
  final Function(String filePath)? onAudioFileDropped;

  // Track height management (reuses TrackHeightState from timeline_models)
  final TrackHeightState trackHeightState;
  final Function(double height)? onMasterTrackHeightChanged;

  // Track color management
  final Color Function(int trackId, String trackName, String trackType)?
  getTrackColor;

  // Automation (reuses AutomationCallbacks from timeline_models)
  final AutomationCallbacks automationCallbacks;
  final MixerAutomationState automationState;

  // Custom track icons
  final String? Function(int trackId)? getTrackIcon;

  // Grouped callback/config objects
  final TrackSelectionState selectionState;
  final TrackManagementCallbacks trackCallbacks;
  final MixerInstrumentCallbacks instrumentCallbacks;
  final MixerPanelConfig config;

  const TrackMixerPanel({
    super.key,
    required this.audioEngine,
    this.scrollController,
    this.trackInstruments,
    this.trackVst3PluginCounts,
    this.onAudioFileDropped,
    this.trackHeightState = const TrackHeightState(),
    this.onMasterTrackHeightChanged,
    this.getTrackColor,
    this.automationCallbacks = const AutomationCallbacks(),
    this.automationState = const MixerAutomationState(),
    this.getTrackIcon,
    this.selectionState = const TrackSelectionState(),
    this.trackCallbacks = const TrackManagementCallbacks(),
    this.instrumentCallbacks = const MixerInstrumentCallbacks(),
    this.config = const MixerPanelConfig(),
  });

  @override
  State<TrackMixerPanel> createState() => TrackMixerPanelState();
}

class TrackMixerPanelState extends State<TrackMixerPanel> {
  List<TrackData> _tracks = [];
  List<ReturnTrackData> _returns = [];
  Map<int, List<TrackSendData>> _trackSends = {};
  Timer? _refreshTimer;

  /// Public getter for tracks (used by parent to access track state)
  List<TrackData> get tracks => _tracks;
  Timer? _levelTimer;
  final ValueNotifier<Map<int, (double, double)>> _displayLevelsNotifier =
      ValueNotifier({}); // Smoothed stereo peak levels with decay
  DateTime _lastLevelUpdate = DateTime.now();
  bool _isAudioFileDragging = false;
  bool _forceDecayToZero = false; // When true, decay all meters to zero

  // Audio input devices cache (refreshed with tracks)
  List<Map<String, dynamic>> _inputDevices = [];

  // Input level for armed tracks (track_id -> input level 0.0-1.0)
  final ValueNotifier<Map<int, double>> _inputLevelsNotifier = ValueNotifier(
    {},
  );

  // Drag-and-drop state
  int? _draggingIndex; // Current position of dragged track in the list
  int?
  _originalDraggingIndex; // Original position when drag started (for cancel/revert)
  Offset? _dragStartPosition;
  double _dragOffsetY = 0.0;
  bool _dragActivated = false;
  static const double _dragThreshold = 8.0;

  /// Values captured at fader/pan drag start (for undo on drag end).
  final Map<int, double> _volumeDragStartDb = {};
  final Map<int, double> _panDragStart = {};
  final Map<String, double> _sendDragStartDb = {};

  TrackData? _findTrack(int trackId) {
    for (final track in _tracks) {
      if (track.id == trackId) return track;
    }
    return null;
  }

  void _beginVolumeDrag(int trackId, double currentDb) {
    _volumeDragStartDb.putIfAbsent(trackId, () => currentDb);
  }

  void _beginPanDrag(int trackId, double currentPan) {
    _panDragStart.putIfAbsent(trackId, () => currentPan);
  }

  Future<void> _commitVolumeChange(
    int trackId,
    String trackName,
    double newDb,
  ) async {
    final oldDb = _volumeDragStartDb.remove(trackId);
    if (oldDb == null || (newDb - oldDb).abs() < 0.01) return;

    await UndoRedoManager().execute(
      SetVolumeCommand(
        trackId: trackId,
        trackName: trackName,
        newVolumeDb: newDb,
        oldVolumeDb: oldDb,
        onVolumeChanged: (id, volumeDb) {
          if (!mounted) return;
          final track = _findTrack(id);
          if (track != null) setState(() => track.volumeDb = volumeDb);
        },
      ),
    );
  }

  Future<void> _commitPanChange(
    int trackId,
    String trackName,
    double newPan,
  ) async {
    final oldPan = _panDragStart.remove(trackId);
    if (oldPan == null || (newPan - oldPan).abs() < 0.001) return;

    await UndoRedoManager().execute(
      SetPanCommand(
        trackId: trackId,
        trackName: trackName,
        newPan: newPan,
        oldPan: oldPan,
        onPanChanged: (id, pan) {
          if (!mounted) return;
          final track = _findTrack(id);
          if (track != null) setState(() => track.pan = pan);
        },
      ),
    );
  }

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

    // Listen to automation preview changes (rebuilds mixer, not entire DAWScreen)
    widget.automationState.previewNotifier?.addListener(_onPreviewChanged);
  }

  void _onPreviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TrackMixerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload tracks when audio engine becomes available
    if (widget.audioEngine != null && oldWidget.audioEngine == null) {
      _loadTracksAsync();
    }
    if (oldWidget.automationState.previewNotifier !=
        widget.automationState.previewNotifier) {
      oldWidget.automationState.previewNotifier?.removeListener(
        _onPreviewChanged,
      );
      widget.automationState.previewNotifier?.addListener(_onPreviewChanged);
    }
  }

  @override
  void dispose() {
    widget.automationState.previewNotifier?.removeListener(_onPreviewChanged);
    _refreshTimer?.cancel();
    _levelTimer?.cancel();
    _displayLevelsNotifier.dispose();
    _inputLevelsNotifier.dispose();
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
        final prevLeft = _displayLevelsNotifier.value[track.id]?.$1 ?? 0.0;
        final prevRight = _displayLevelsNotifier.value[track.id]?.$2 ?? 0.0;

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

    // Poll input levels for armed tracks
    final newInputLevels = <int, double>{};
    for (final track in _tracks) {
      if (track.armed && track.inputDeviceIndex >= 0) {
        try {
          final rawLevel = widget.audioEngine!.getInputChannelLevel(
            track.inputChannel,
          );
          // Convert raw amplitude (0.0-1.0+) to display range
          final displayLevel = rawLevel.clamp(0.0, 1.0);
          newInputLevels[track.id] = displayLevel;
        } catch (e) {
          // Silently fail
        }
      }
    }

    if (mounted && (newLevels.isNotEmpty || newInputLevels.isNotEmpty)) {
      _displayLevelsNotifier.value = newLevels;
      _inputLevelsNotifier.value = newInputLevels;
    }
  }

  String _sendKey(int sourceTrackId, int returnTrackId) =>
      '$sourceTrackId:$returnTrackId';

  /// Refresh mixer/timeline after send or return mutation.
  /// Deferred to avoid setState/notifyListeners during dialog teardown.
  void _deferSendMutationRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadTracksAsync();
    });
  }

  void _refreshSendData() {
    if (widget.audioEngine == null) return;

    final previousReturnEffectTypes = {
      for (final ret in _returns) ret.id: ret.effectType,
    };
    final returns = _tracks
        .where((track) => track.type.toLowerCase() == 'return')
        .map(
          (track) => ReturnTrackData(
            id: track.id,
            name: track.name,
            effectType:
                previousReturnEffectTypes[track.id] ??
                _guessReturnEffectType(track.name),
          ),
        )
        .toList(growable: false);
    final returnEffectTypes = {
      for (final ret in returns) ret.id: ret.effectType,
    };

    final sendsMap = <int, List<TrackSendData>>{};
    final sendCounts = <int, int>{};
    for (final track in _tracks) {
      if (track.type.toLowerCase() == 'master' ||
          track.type.toLowerCase() == 'return') {
        continue;
      }
      final csv = widget.audioEngine!.getTrackSends(track.id);
      final sends = TrackSendData.parseTrackSendsCsv(
        csv,
        returnEffectTypes: returnEffectTypes,
      );
      sendsMap[track.id] = sends;
      sendCounts[track.id] = sends.length;
    }

    if (!mounted) return;

    for (final entry in sendCounts.entries) {
      widget.trackHeightState.onSendCountChanged?.call(entry.key, entry.value);
    }

    setState(() {
      _returns = returns;
      _trackSends = sendsMap;
    });
  }

  String _guessReturnEffectType(String name) {
    final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
    if (normalized.contains('reverb')) return 'reverb';
    if (normalized.contains('delay')) return 'delay';
    if (normalized.contains('compressor')) return 'compressor';
    if (normalized.contains('chorus')) return 'chorus';
    if (normalized.contains('limiter')) return 'limiter';
    if (normalized.contains('eq')) return 'eq';
    return normalized.isEmpty ? 'unknown' : normalized;
  }

  Future<void> _handleAddSendToReturn(
    TrackData sourceTrack,
    ReturnTrackData returnTrack,
  ) async {
    if (widget.audioEngine == null) return;

    final existing = _trackSends[sourceTrack.id]?.any(
      (s) => s.returnId == returnTrack.id,
    );
    if (existing == true) return;

    await UndoRedoManager().execute(
      AddSendCommand(
        sourceTrackId: sourceTrack.id,
        sourceTrackName: sourceTrack.name,
        returnTrackId: returnTrack.id,
        returnLabel: returnTrack.name,
        onChanged: _deferSendMutationRefresh,
      ),
    );
  }

  Future<void> _handleRemoveSend(
    TrackData sourceTrack,
    int returnTrackId,
    String returnLabel,
    double previousAmountDb,
  ) async {
    await UndoRedoManager().execute(
      RemoveSendCommand(
        sourceTrackId: sourceTrack.id,
        sourceTrackName: sourceTrack.name,
        returnTrackId: returnTrackId,
        returnLabel: returnLabel,
        previousAmountDb: previousAmountDb,
        onChanged: _deferSendMutationRefresh,
      ),
    );
  }

  Future<void> _handleDeleteReturn(ReturnTrackData returnTrack) async {
    await UndoRedoManager().execute(
      RemoveReturnCommand(
        returnTrackId: returnTrack.id,
        returnLabel: returnTrack.name,
        effectType: returnTrack.effectType,
        onChanged: _deferSendMutationRefresh,
      ),
    );
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
      // Refresh input devices list alongside tracks
      final devices = await Future.microtask(() {
        return widget.audioEngine!.getAudioInputDevices();
      });

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
        _inputDevices = devices;
        // Separate master track (not reorderable)
        final masterTrack = tracksMap.values
            .where((t) => t.type == 'Master')
            .toList();
        final regularTrackIds = tracksMap.keys
            .where((id) => _isRegularTrack(tracksMap[id]!))
            .toList();

        // Sync track IDs to TrackController (excludes returns and master)
        widget.trackCallbacks.onOrderSync?.call(regularTrackIds);

        setState(() {
          final orderedTracks = <TrackData>[];

          for (final id in widget.config.trackOrder) {
            if (tracksMap.containsKey(id) && _isRegularTrack(tracksMap[id]!)) {
              orderedTracks.add(tracksMap[id]!);
            }
          }

          for (final id in regularTrackIds) {
            if (!widget.config.trackOrder.contains(id)) {
              orderedTracks.add(tracksMap[id]!);
            }
          }

          // Returns before master in internal list (UI splits them)
          orderedTracks.addAll(
            tracksMap.values.where((t) => t.type.toLowerCase() == 'return'),
          );
          orderedTracks.addAll(masterTrack);

          _tracks = orderedTracks;
        });
        _refreshSendData();
      }
    } catch (e) {
      Log.e('TrackMixerPanel: Error loading tracks: $e');
    }
  }

  /// Handle arm button toggle with exclusive arm behavior for MIDI tracks.
  /// Clicking arm on a MIDI track disarms all other MIDI tracks (Ableton-style).
  void _handleArmToggle(TrackData track, List<TrackData> allTracks) {
    final disarmedIds = <int>[];
    setState(() {
      if (!track.armed) {
        // Arming this track - disarm all other MIDI tracks (exclusive arm)
        for (final t in allTracks) {
          if (t.type == 'midi' && t.id != track.id && t.armed) {
            t.armed = false;
            t.inputMonitoring = false; // engine auto-mode mirrors arm
            disarmedIds.add(t.id);
          }
        }
      }
      // Toggle this track's arm state
      track.armed = !track.armed;
      // Engine auto-mode: set_track_armed resets monitoring to match arm,
      // so mirror it here or the I button would show stale state.
      track.inputMonitoring = track.armed;
    });
    // Defer FFI calls so the frame paints first
    Future.microtask(() {
      for (final id in disarmedIds) {
        widget.audioEngine?.setTrackArmed(id, armed: false);
      }
      widget.audioEngine?.setTrackArmed(track.id, armed: track.armed);
      // Arming an instrument track is the moment the user is about to play —
      // a good time to catch a keyboard that was hot-plugged while Boojy
      // stayed focused. (Audio-track arming doesn't need a MIDI rescan.)
      if (track.armed && track.type != 'audio') {
        widget.config.onTrackArmed?.call();
      }
    });
  }

  /// Handle Shift+click on arm button for multi-arm mode.
  /// Just toggles this track without affecting others (allows layering).
  void _handleArmShiftClick(TrackData track) {
    setState(() {
      track.armed = !track.armed;
      track.inputMonitoring = track.armed; // engine auto-mode mirrors arm
    });
    Future.microtask(
      () => widget.audioEngine?.setTrackArmed(track.id, armed: track.armed),
    );
  }

  /// Toggle input monitoring for an audio track (hear live input while
  /// armed). Live state like arm — not undoable; the engine re-couples it to
  /// arm on every arm change (auto-mode), this overrides it afterwards.
  void _handleMonitorToggle(TrackData track) {
    setState(() {
      track.inputMonitoring = !track.inputMonitoring;
    });
    Future.microtask(
      () => widget.audioEngine?.setTrackInputMonitoring(
        track.id,
        enabled: track.inputMonitoring,
      ),
    );
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
      widget.trackCallbacks.onDuplicated?.call(
        track.id,
        command.duplicatedTrackId!,
      );

      _loadTracksAsync();
    } else {
      Log.e('TrackMixerPanel: Failed to duplicate track ${track.name}');
    }
  }

  void _confirmDeleteTrack(TrackData track) {
    // Read theme from the dialog's own build context — reading `context.colors`
    // here (an event-handler callback, not a build) makes Provider.of listen
    // from outside the widget tree, which throws and silently aborts the delete.
    showDialog(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
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

                // Prefer the DAW-layer undoable delete (snapshots + restores the
                // track's full content). Fall back to the plain command +
                // teardown only if the host didn't wire onDeleteRequested.
                if (widget.trackCallbacks.onDeleteRequested != null) {
                  await widget.trackCallbacks.onDeleteRequested!(track);
                } else {
                  final command = DeleteTrackCommand(
                    trackId: track.id,
                    trackName: track.name,
                    trackType: track.type,
                    volumeDb: track.volumeDb,
                    pan: track.pan,
                    mute: track.mute,
                    solo: track.solo,
                    armed: track.armed,
                  );
                  await UndoRedoManager().execute(command);
                  widget.trackCallbacks.onDeleted?.call(track.id);
                }
                _loadTracksAsync();
              },
              child: Text('Delete', style: TextStyle(color: colors.error)),
            ),
          ],
        );
      },
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
      child: ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.dark,
            border: Border(
              left: _isAudioFileDragging
                  ? BorderSide(color: context.colors.success, width: 3)
                  : BorderSide.none,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              BI.addCircle,
                              color: context.colors.textPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Drop to create Audio track',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                                fontWeight: BT.weightSemiBold,
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
      ),
    );
  }

  Widget _buildHeader() {
    // 24px strip mirroring the timeline nav bar's height so the first track
    // strip lines up with the first arrangement row. Hosts the global
    // automation toggle (GarageBand model: one switch shows every track's
    // lane in the timeline).
    return Container(
      height: 24, // Match timeline nav bar height
      decoration: BoxDecoration(
        color: context.colors.dark,
        border: Border(bottom: BorderSide(color: context.colors.divider)),
      ),
      child: UIConstants.enableAutomation
          ? Row(children: [const SizedBox(width: 6), _buildAutomationToggle()])
          : null,
    );
  }

  /// Global automation toggle: shows/hides automation lanes for all tracks.
  Widget _buildAutomationToggle() {
    final colors = context.colors;
    final isActive = widget.automationState.visible;
    return GestureDetector(
      onTap: widget.automationState.onToggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isActive ? colors.accent : colors.surface,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                BI.chartLine,
                size: 11,
                color: isActive ? colors.darkest : colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Automation',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: BT.weightMedium,
                  color: isActive ? colors.darkest : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(BI.sliders, size: 48, color: context.colors.textMuted),
          const SizedBox(height: 16),
          Text(
            'Mixer',
            style: TextStyle(color: context.colors.textMuted, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Add tracks to see mixer controls',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: BT.fontBody,
            ),
          ),
        ],
      ),
    );
  }

  bool _isRegularTrack(TrackData track) {
    final type = track.type.toLowerCase();
    return type != 'master' && type != 'return';
  }

  Widget _buildTrackStrips() {
    // Separate regular tracks, returns, and master
    final regularTracks = _tracks.where(_isRegularTrack).toList();
    final returnTracks = _tracks
        .where((t) => t.type.toLowerCase() == 'return')
        .toList();
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
                      return _buildDraggableTrackWrapper(
                        track,
                        index,
                        regularTracks,
                      );
                    }),
                    // Buffer spacer at the end
                    const SizedBox(height: 160),
                  ],
                ),
                // Dragged track rendered on top (if dragging)
                if (_dragActivated &&
                    _draggingIndex != null &&
                    _draggingIndex! < regularTracks.length)
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

        // Return tracks pinned before master (not scrollable, not draggable)
        if (returnTracks.isNotEmpty)
          ...returnTracks.map(
            (track) => ValueListenableBuilder<Map<int, (double, double)>>(
              valueListenable: _displayLevelsNotifier,
              builder: (context, levels, _) => _buildReturnTrackStrip(
                track,
                levels[track.id]?.$1 ?? 0.0,
                levels[track.id]?.$2 ?? 0.0,
              ),
            ),
          ),

        // Master track pinned at bottom (outside scroll area)
        if (masterTrack.id != -1)
          ValueListenableBuilder<Map<int, (double, double)>>(
            valueListenable: _displayLevelsNotifier,
            builder: (context, levels, _) => MasterTrackMixerStrip(
              volumeDb: masterTrack.volumeDb,
              pan: masterTrack.pan,
              isSelected:
                  widget.selectionState.selectedTrackId == masterTrack.id,
              onTap: () =>
                  widget.selectionState.onTrackSelected?.call(masterTrack.id),
              peakLevelLeft: levels[masterTrack.id]?.$1 ?? 0.0,
              peakLevelRight: levels[masterTrack.id]?.$2 ?? 0.0,
              trackHeight: widget.trackHeightState.masterTrackHeight,
              onHeightChanged: widget.onMasterTrackHeightChanged,
              stripWidth: widget.config.panelWidth,
              onVolumeChanged: (volumeDb) {
                setState(() {
                  masterTrack.volumeDb = volumeDb;
                });
                widget.audioEngine?.setTrackVolume(masterTrack.id, volumeDb);
              },
              onVolumeDragStart: () =>
                  _beginVolumeDrag(masterTrack.id, masterTrack.volumeDb),
              onVolumeDragEnd: () => _commitVolumeChange(
                masterTrack.id,
                masterTrack.name,
                masterTrack.volumeDb,
              ),
              onPanChanged: (pan) {
                setState(() {
                  masterTrack.pan = pan;
                });
                widget.audioEngine?.setTrackPan(masterTrack.id, pan);
              },
              onPanDragStart: () =>
                  _beginPanDrag(masterTrack.id, masterTrack.pan),
              onPanDragEnd: () => _commitPanChange(
                masterTrack.id,
                masterTrack.name,
                masterTrack.pan,
              ),
              onFxButtonPressed:
                  widget.instrumentCallbacks.onFxButtonPressed != null
                  ? () => widget.instrumentCallbacks.onFxButtonPressed!(
                      masterTrack.id,
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  /// Build a draggable track wrapper - live reordering (no gap animation needed)
  Widget _buildDraggableTrackWrapper(
    TrackData track,
    int index,
    List<TrackData> allTracks,
  ) {
    final trackHeight = widget.trackHeightState.clipHeights[track.id] ?? 100.0;
    final isDragging = _draggingIndex == index;

    return KeyedSubtree(
      key: ValueKey(track.id),
      child: MouseRegion(
        cursor: _dragActivated
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Reorder is vertical-only; using onVerticalDrag (not onPan) lets the
          // fader's horizontal-drag recognizer win the gesture arena.
          onVerticalDragStart: (details) => _onDragStart(index, details),
          onVerticalDragUpdate: (details) => _onDragUpdate(details, allTracks),
          onVerticalDragEnd: (details) => _onDragEnd(allTracks),
          onVerticalDragCancel: _onDragCancel, // CRITICAL: Handle arena loss
          child: isDragging && _dragActivated
              ? SizedBox(
                  height: trackHeight,
                  width: 380,
                ) // Placeholder for dragged track
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
    final draggedHeight =
        widget.trackHeightState.clipHeights[tracks[_draggingIndex!].id] ??
        100.0;
    double originalTop = 0;
    for (int i = 0; i < _draggingIndex!; i++) {
      originalTop += widget.trackHeightState.clipHeights[tracks[i].id] ?? 100.0;
    }
    final draggedCenter = originalTop + newOffsetY + (draggedHeight / 2);

    // Find insertion point
    int newGapIndex = _draggingIndex!;
    double cumulativeHeight = 0;
    for (int i = 0; i < tracks.length; i++) {
      final itemHeight =
          widget.trackHeightState.clipHeights[tracks[i].id] ?? 100.0;
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
      widget.trackCallbacks.onReordered?.call(fromIndex, toIndex);

      // Update dragging index to new position
      _draggingIndex = toIndex;

      // Adjust drag start position so the track stays under cursor
      // When moving down, we need to add the heights of tracks we passed
      // When moving up, we need to subtract the heights of tracks we passed
      if (toIndex > fromIndex) {
        // Moved down - adjust start position up by the height of the track we passed
        final passedTrackHeight =
            widget.trackHeightState.clipHeights[tracks[fromIndex].id] ?? 100.0;
        _dragStartPosition = Offset(
          _dragStartPosition!.dx,
          _dragStartPosition!.dy + passedTrackHeight,
        );
      } else {
        // Moved up - adjust start position down by the height of the track we passed
        final passedTrackHeight =
            widget.trackHeightState.clipHeights[tracks[toIndex].id] ?? 100.0;
        _dragStartPosition = Offset(
          _dragStartPosition!.dx,
          _dragStartPosition!.dy - passedTrackHeight,
        );
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
    if (_dragActivated &&
        _originalDraggingIndex != null &&
        _draggingIndex != null) {
      final currentIndex = _draggingIndex!;
      final originalIndex = _originalDraggingIndex!;

      if (currentIndex != originalIndex) {
        // Revert the reorder
        final track = _tracks.removeAt(currentIndex);
        _tracks.insert(originalIndex, track);

        // Notify parent to revert
        widget.trackCallbacks.onReordered?.call(currentIndex, originalIndex);
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
      top += widget.trackHeightState.clipHeights[tracks[i].id] ?? 100.0;
    }
    return top + _dragOffsetY;
  }

  /// Build the TrackMixerStrip widget.
  Widget _buildReturnTrackStrip(
    TrackData track,
    double peakLeft,
    double peakRight,
  ) {
    final returnMeta = _returns.where((r) => r.id == track.id).firstOrNull;
    final trackColor =
        widget.getTrackColor?.call(track.id, track.name, track.type) ??
        TrackColors.getTrackColor(track.id);

    return TrackMixerStrip(
      trackId: track.id,
      displayIndex: 0,
      trackName: track.name,
      trackType: track.type,
      volumeDb: track.volumeDb,
      pan: track.pan,
      isMuted: track.mute,
      isSoloed: track.solo,
      peakLevelLeft: peakLeft,
      peakLevelRight: peakRight,
      trackColor: trackColor,
      isReturnTrack: true,
      isSelected:
          widget.selectionState.selectedTrackIds?.contains(track.id) ??
          widget.selectionState.selectedTrackId == track.id,
      clipHeight: widget.trackHeightState.clipHeights[track.id] ?? 100.0,
      stripWidth: widget.config.panelWidth,
      onTap: (isShiftHeld) {
        widget.selectionState.onTrackSelected?.call(
          track.id,
          isShiftHeld: isShiftHeld,
        );
      },
      onVolumeChanged: (volumeDb) {
        setState(() => track.volumeDb = volumeDb);
        widget.audioEngine?.setTrackVolume(track.id, volumeDb);
      },
      onVolumeDragStart: () => _beginVolumeDrag(track.id, track.volumeDb),
      onVolumeDragEnd: () =>
          _commitVolumeChange(track.id, track.name, track.volumeDb),
      onPanChanged: (pan) {
        setState(() => track.pan = pan);
        widget.audioEngine?.setTrackPan(track.id, pan);
      },
      onPanDragStart: () => _beginPanDrag(track.id, track.pan),
      onPanDragEnd: () => _commitPanChange(track.id, track.name, track.pan),
      onMuteToggle: () async {
        final oldMute = track.mute;
        setState(() => track.mute = !track.mute);
        await UndoRedoManager().execute(
          SetMuteCommand(
            trackId: track.id,
            trackName: track.name,
            newMute: track.mute,
            oldMute: oldMute,
            onMuteChanged: (id, {required bool muted}) {
              if (!mounted) return;
              final t = _findTrack(id);
              if (t != null) setState(() => t.mute = muted);
            },
          ),
        );
      },
      onSoloToggle: () async {
        final oldSolo = track.solo;
        setState(() => track.solo = !track.solo);
        await UndoRedoManager().execute(
          SetSoloCommand(
            trackId: track.id,
            trackName: track.name,
            newSolo: track.solo,
            oldSolo: oldSolo,
            onSoloChanged: (id, {required bool soloed}) {
              if (!mounted) return;
              final t = _findTrack(id);
              if (t != null) setState(() => t.solo = soloed);
            },
          ),
        );
      },
      onNameChanged: (newName) async {
        final oldName = track.name;
        if (oldName == newName) return;
        await UndoRedoManager().execute(
          RenameTrackCommand(
            trackId: track.id,
            oldName: oldName,
            newName: newName,
            onTrackRenamed: (trackId, name) {
              if (mounted) setState(() => track.name = name);
            },
          ),
        );
      },
      onDeleteReturn: returnMeta != null
          ? () => _handleDeleteReturn(returnMeta)
          : null,
      onClipHeightChanged: (height) {
        widget.trackHeightState.onClipHeightChanged?.call(track.id, height);
      },
    );
  }

  /// Build the TrackMixerStrip widget.
  /// Meter levels are delivered via ValueListenableBuilder so only the meters
  /// rebuild on the 50ms poll — the rest of the strip (name, fader, buttons)
  /// stays untouched.
  Widget _buildTrackStrip(
    TrackData track,
    int index,
    List<TrackData> allTracks,
  ) {
    final trackColor =
        widget.getTrackColor?.call(track.id, track.name, track.type) ??
        TrackColors.getTrackColor(index);

    return ValueListenableBuilder<Map<int, (double, double)>>(
      valueListenable: _displayLevelsNotifier,
      builder: (context, levels, _) {
        return ValueListenableBuilder<Map<int, double>>(
          valueListenable: _inputLevelsNotifier,
          builder: (context, inputLevels, _) {
            return TrackMixerStrip(
              trackId: track.id,
              displayIndex: index + 1, // 1-based sequential number
              trackName: track.name,
              trackType: track.type,
              volumeDb: track.volumeDb,
              pan: track.pan,
              isMuted: track.mute,
              isSoloed: track.solo,
              peakLevelLeft: levels[track.id]?.$1 ?? 0.0,
              peakLevelRight: levels[track.id]?.$2 ?? 0.0,
              trackColor: trackColor,
              audioEngine: widget.audioEngine,
              isSelected:
                  widget.selectionState.selectedTrackIds?.contains(track.id) ??
                  widget.selectionState.selectedTrackId == track.id,
              instrumentData: widget.trackInstruments?[track.id],
              onInstrumentSelect: (instrumentId) {
                widget.instrumentCallbacks.onInstrumentSelected?.call(
                  track.id,
                  instrumentId,
                );
              },
              vst3PluginCount: widget.trackVst3PluginCounts?[track.id] ?? 0,
              onFxButtonPressed: () =>
                  widget.instrumentCallbacks.onFxButtonPressed?.call(track.id),
              onVst3PluginDropped: (plugin) => widget
                  .instrumentCallbacks
                  .onVst3PluginDropped
                  ?.call(track.id, plugin),
              onVst3InstrumentDropped: (plugin) => widget
                  .instrumentCallbacks
                  .onVst3InstrumentDropped
                  ?.call(track.id, plugin),
              onInstrumentDropped: (instrument) => widget
                  .instrumentCallbacks
                  .onInstrumentDropped
                  ?.call(track.id, instrument),
              onBuiltInEffectDropped: (effect) => widget
                  .instrumentCallbacks
                  .onBuiltInEffectDropped
                  ?.call(track.id, effect),
              onEditPluginsPressed: () => widget
                  .instrumentCallbacks
                  .onEditPluginsPressed
                  ?.call(track.id),
              sends: _trackSends[track.id] ?? const [],
              existingReturns: _returns,
              onSendAmountChanged: (returnTrackId, amountDb) {
                widget.audioEngine?.setSendAmount(
                  track.id,
                  returnTrackId,
                  amountDb,
                );
                final sends = _trackSends[track.id];
                if (sends == null) return;
                final idx = sends.indexWhere(
                  (s) => s.returnId == returnTrackId,
                );
                if (idx < 0) return;
                setState(() {
                  final updated = [...sends];
                  updated[idx] = TrackSendData(
                    returnId: returnTrackId,
                    label: sends[idx].label,
                    effectType: sends[idx].effectType,
                    amountLinear: TrackSendData.dbToLinear(amountDb),
                  );
                  _trackSends[track.id] = updated;
                });
              },
              onSendAmountDragStart: (returnTrackId) {
                final send = _trackSends[track.id]
                    ?.where((s) => s.returnId == returnTrackId)
                    .firstOrNull;
                if (send != null) {
                  _sendDragStartDb[_sendKey(track.id, returnTrackId)] =
                      TrackSendData.linearToDb(send.amountLinear);
                }
              },
              onSendAmountDragEnd: (returnTrackId) async {
                final key = _sendKey(track.id, returnTrackId);
                final oldDb = _sendDragStartDb.remove(key);
                if (oldDb == null) return;
                final send = _trackSends[track.id]
                    ?.where((s) => s.returnId == returnTrackId)
                    .firstOrNull;
                if (send == null) return;
                final newDb = TrackSendData.linearToDb(send.amountLinear);
                if ((newDb - oldDb).abs() < 0.01) return;
                await UndoRedoManager().execute(
                  SetSendAmountCommand(
                    sourceTrackId: track.id,
                    sourceTrackName: track.name,
                    returnTrackId: returnTrackId,
                    returnLabel: send.label,
                    newAmountDb: newDb,
                    oldAmountDb: oldDb,
                  ),
                );
              },
              onRemoveSend: (returnTrackId) {
                final send = _trackSends[track.id]
                    ?.where((s) => s.returnId == returnTrackId)
                    .firstOrNull;
                if (send == null) return;
                _handleRemoveSend(
                  track,
                  returnTrackId,
                  send.label,
                  TrackSendData.linearToDb(send.amountLinear),
                );
              },
              onSendToReturn: (returnTrack) =>
                  _handleAddSendToReturn(track, returnTrack),
              clipHeight:
                  widget.trackHeightState.clipHeights[track.id] ?? 100.0,
              automationHeight:
                  widget.trackHeightState.automationHeights[track.id] ?? 60.0,
              stripWidth: widget.config.panelWidth,
              onClipHeightChanged: (height) {
                widget.trackHeightState.onClipHeightChanged?.call(
                  track.id,
                  height,
                );
              },
              onAutomationHeightChanged: (height) {
                widget.trackHeightState.onAutomationHeightChanged?.call(
                  track.id,
                  height,
                );
              },
              onTap: (isShiftHeld) {
                widget.selectionState.onTrackSelected?.call(
                  track.id,
                  isShiftHeld: isShiftHeld,
                );
              },
              onDoubleTap: () {
                widget.trackCallbacks.onDoubleClick?.call(track.id);
              },
              onVolumeChanged: (volumeDb) {
                setState(() {
                  track.volumeDb = volumeDb;
                });
                widget.audioEngine?.setTrackVolume(track.id, volumeDb);
              },
              onVolumeDragStart: () =>
                  _beginVolumeDrag(track.id, track.volumeDb),
              onVolumeDragEnd: () =>
                  _commitVolumeChange(track.id, track.name, track.volumeDb),
              onPanChanged: (pan) {
                setState(() {
                  track.pan = pan;
                });
                widget.audioEngine?.setTrackPan(track.id, pan);
              },
              onPanDragStart: () => _beginPanDrag(track.id, track.pan),
              onPanDragEnd: () =>
                  _commitPanChange(track.id, track.name, track.pan),
              onMuteToggle: () async {
                final oldMute = track.mute;
                setState(() {
                  track.mute = !track.mute;
                });
                await UndoRedoManager().execute(
                  SetMuteCommand(
                    trackId: track.id,
                    trackName: track.name,
                    newMute: track.mute,
                    oldMute: oldMute,
                    onMuteChanged: (id, {required bool muted}) {
                      if (!mounted) return;
                      final t = _findTrack(id);
                      if (t != null) setState(() => t.mute = muted);
                    },
                  ),
                );
              },
              onSoloToggle: () async {
                final oldSolo = track.solo;
                setState(() {
                  track.solo = !track.solo;
                });
                await UndoRedoManager().execute(
                  SetSoloCommand(
                    trackId: track.id,
                    trackName: track.name,
                    newSolo: track.solo,
                    oldSolo: oldSolo,
                    onSoloChanged: (id, {required bool soloed}) {
                      if (!mounted) return;
                      final t = _findTrack(id);
                      if (t != null) setState(() => t.solo = soloed);
                    },
                  ),
                );
              },
              isArmed: track.armed,
              onArmToggle: () => _handleArmToggle(track, allTracks),
              onArmShiftClick: () => _handleArmShiftClick(track),
              inputMonitoring: track.inputMonitoring,
              onMonitorToggle: track.type.toLowerCase() == 'audio'
                  ? () => _handleMonitorToggle(track)
                  : null,
              showAutomation: widget.automationState.visible,
              selectedParameter: widget.automationState.parameter,
              onParameterChanged: widget.automationState.onParameterChanged,
              onResetAutomation: () =>
                  widget.automationState.onReset?.call(track.id),
              previewParameterValue:
                  widget.automationState.previewNotifier?.value[track.id],
              onDuplicatePressed: () => _duplicateTrack(track),
              onDeletePressed: () => _confirmDeleteTrack(track),
              onConvertToSampler:
                  track.type.toLowerCase() == 'audio' &&
                      widget.trackCallbacks.onConvertToSampler != null
                  ? () => widget.trackCallbacks.onConvertToSampler!(track.id)
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
                      widget.trackCallbacks.onNameChanged?.call(trackId, name);
                    }
                  },
                );
                await UndoRedoManager().execute(command);
              },
              onColorChanged: widget.trackCallbacks.onColorChanged != null
                  ? (color) =>
                        widget.trackCallbacks.onColorChanged!(track.id, color)
                  : null,
              // Custom icon
              customIcon: widget.getTrackIcon?.call(track.id),
              onIconChanged: widget.trackCallbacks.onIconChanged != null
                  ? (icon) =>
                        widget.trackCallbacks.onIconChanged!(track.id, icon)
                  : null,
              // Input routing
              inputDeviceIndex: track.inputDeviceIndex,
              inputChannel: track.inputChannel,
              inputDevices: _inputDevices,
              isRecording: widget.config.isRecording,
              inputLevel: inputLevels[track.id],
              onInputChanged: (deviceIndex, channel) {
                setState(() {
                  track.inputDeviceIndex = deviceIndex;
                  track.inputChannel = channel;
                });
                widget.audioEngine?.setTrackInput(
                  track.id,
                  deviceIndex,
                  channel,
                );
              },
            );
          },
        );
      },
    );
  }
}
