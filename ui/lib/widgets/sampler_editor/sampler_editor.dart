import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../audio_engine.dart';
import '../../services/commands/sampler_commands.dart';
import '../../services/undo_redo_manager.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../../theme/app_colors.dart';
import '../platform_drop_target.dart';
import '../shared/editors/nav_bar_with_zoom.dart';
import 'sampler_controls_bar.dart';
import 'sampler_keyboard_strip.dart';
import 'sampler_waveform_painter.dart';

/// Sampler Editor widget — beginner-first flow (GarageBand Quick Sampler):
/// drop/Browse a file → see the waveform → audition on the keyboard strip.
/// Loop points are edited with drag handles directly on the waveform.
/// All parameter edits are Command-wrapped (one undo step per gesture).
class SamplerEditor extends StatefulWidget {
  static const List<String> acceptedExtensions = [
    'wav',
    'mp3',
    'flac',
    'aif',
    'aiff',
  ];

  final AudioEngine? audioEngine;
  final int? trackId;
  final String? samplePath;
  final VoidCallback? onClose;
  final UndoRedoManager? undoManager;

  const SamplerEditor({
    super.key,
    this.audioEngine,
    this.trackId,
    this.samplePath,
    this.onClose,
    this.undoManager,
  });

  @override
  State<SamplerEditor> createState() => _SamplerEditorState();
}

class _SamplerEditorState extends State<SamplerEditor> {
  // Sampler parameters (mirrors of engine state)
  double _attackMs = 1.0;
  double _releaseMs = 50.0;
  int _rootNote = 60; // C4
  bool _loopEnabled = false;
  double _loopStartSeconds = 0.0;
  double _loopEndSeconds = 1.0;
  double _sampleDuration = 0.0; // in seconds
  double _volumeDb = 0.0;
  bool _reversed = false;

  // Waveform data (real peaks from engine)
  List<double> _waveformPeaks = [];

  bool get _hasSample => _sampleDuration > 0;

  // Zoom and scroll
  double _pixelsPerSecond = 100.0;
  bool _needsAutoZoom = true;
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _rulerScroll = ScrollController();

  // Nav bar interaction (loop edges + navigation drag)
  double? _navBarHoverSeconds;
  _NavDragMode _navDragMode = _NavDragMode.none;
  double? _navDragStartX;
  double? _navDragStartY;

  // On-waveform loop handle interaction
  LoopEdge? _waveHoverEdge;
  LoopEdge? _waveDragEdge;

  // Undo coalescing: param key -> value snapshot at gesture start
  final Map<String, String> _gestureOldValues = {};

  // External file drag highlight
  bool _isDropHovering = false;

  // Keyboard strip audition
  int? _auditionNote;

  @override
  void initState() {
    super.initState();
    _loadSampleData();
    _syncScrollControllers();
  }

  @override
  void dispose() {
    _stopAudition();
    _horizontalScroll.dispose();
    _rulerScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SamplerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackId != oldWidget.trackId ||
        widget.samplePath != oldWidget.samplePath) {
      _stopAudition();
      _loadSampleData();
    }
  }

  void _loadSampleData() {
    if (widget.audioEngine == null || widget.trackId == null) return;
    _needsAutoZoom = true;
    _syncFromEngine(reloadPeaks: true);
  }

  /// Pull the engine's sampler state into local mirrors. Used on load and as
  /// the `onApplied` hook of every command so undo/redo refreshes the UI.
  void _syncFromEngine({bool reloadPeaks = false}) {
    if (!mounted || widget.audioEngine == null || widget.trackId == null) {
      return;
    }

    final info = widget.audioEngine!.getSamplerInfo(widget.trackId!);
    final peaks = reloadPeaks
        ? widget.audioEngine!.getSamplerWaveformPeaks(widget.trackId!, 2048)
        : null;

    setState(() {
      if (info != null) {
        _sampleDuration = info.durationSeconds;
        _loopEnabled = info.loopEnabled;
        _loopStartSeconds = info.loopStartSeconds;
        _loopEndSeconds = info.loopEndSeconds;
        _rootNote = info.rootNote;
        _attackMs = info.attackMs;
        _releaseMs = info.releaseMs;
        _volumeDb = info.volumeDb;
        _reversed = info.reversed;
      }
      if (peaks != null) {
        _waveformPeaks = peaks;
      }
    });
  }

  void _syncScrollControllers() {
    _horizontalScroll.addListener(() {
      if (_rulerScroll.hasClients &&
          _rulerScroll.offset != _horizontalScroll.offset) {
        _rulerScroll.jumpTo(_horizontalScroll.offset);
      }
    });

    _rulerScroll.addListener(() {
      if (_horizontalScroll.hasClients &&
          _horizontalScroll.offset != _rulerScroll.offset) {
        _horizontalScroll.jumpTo(_rulerScroll.offset);
      }
    });
  }

  // ============================================================================
  // Parameter plumbing — live writes during a drag, one Command per gesture
  // ============================================================================

  String _currentValueString(String param) {
    switch (param) {
      case 'attack_ms':
        return _attackMs.toString();
      case 'release_ms':
        return _releaseMs.toString();
      case 'root_note':
        return _rootNote.toString();
      case 'loop_enabled':
        return _loopEnabled ? '1' : '0';
      case 'loop_start_seconds':
        return _loopStartSeconds.toString();
      case 'loop_end_seconds':
        return _loopEndSeconds.toString();
      case 'volume_db':
        return _volumeDb.toString();
      case 'reversed':
        return _reversed ? '1' : '0';
      default:
        return '';
    }
  }

  /// Live engine write during a drag — no undo entry.
  void _sendParameterToEngine(String param, String value) {
    if (widget.audioEngine != null && widget.trackId != null) {
      widget.audioEngine!.setSamplerParameter(widget.trackId!, param, value);
    }
  }

  /// Snapshot the pre-gesture value. Re-entrant begins for the same param are
  /// ignored so the whole drag stays one undo step (drum-kit pattern).
  void _beginParamGesture(String param) {
    _gestureOldValues.putIfAbsent(param, () => _currentValueString(param));
  }

  /// Commit the gesture as a single command (old → current).
  void _endParamGesture(String param) {
    final oldValue = _gestureOldValues.remove(param);
    if (oldValue == null) return;
    _commitParam(param, oldValue, _currentValueString(param));
  }

  /// Push one undoable parameter change. The engine already holds `newValue`
  /// from the live writes, so execute() re-applying it is idempotent.
  void _commitParam(String param, String oldValue, String newValue) {
    if (oldValue == newValue) return;
    if (widget.trackId == null) return;

    final manager = widget.undoManager;
    if (manager == null) {
      // No undo plumbing (shouldn't happen from EditorPanel) — at least apply.
      _sendParameterToEngine(param, newValue);
      _syncFromEngine(reloadPeaks: param == 'reversed');
      return;
    }

    manager.execute(
      SetSamplerParameterCommand(
        trackId: widget.trackId!,
        paramName: param,
        oldValue: oldValue,
        newValue: newValue,
        onApplied: () => _syncFromEngine(reloadPeaks: param == 'reversed'),
      ),
    );
  }

  /// Instant (non-drag) undoable change: toggle, dropdown pick, reset.
  void _applyInstantParam(String param, String newValue) {
    _commitParam(param, _currentValueString(param), newValue);
  }

  // Live drag setters (engine + local mirror, no undo entry until gesture end)

  void _onAttackChanged(double value) {
    setState(() => _attackMs = value);
    _sendParameterToEngine('attack_ms', value.toString());
  }

  void _onReleaseChanged(double value) {
    setState(() => _releaseMs = value);
    _sendParameterToEngine('release_ms', value.toString());
  }

  void _onVolumeChanged(double value) {
    setState(() => _volumeDb = value);
    _sendParameterToEngine('volume_db', value.toString());
  }

  void _onLoopStartChanged(double seconds) {
    final clamped = seconds.clamp(0.0, _loopEndSeconds - 0.01);
    setState(() => _loopStartSeconds = clamped);
    _sendParameterToEngine('loop_start_seconds', clamped.toString());
  }

  void _onLoopEndChanged(double seconds) {
    final clamped = seconds.clamp(_loopStartSeconds + 0.01, _sampleDuration);
    setState(() => _loopEndSeconds = clamped);
    _sendParameterToEngine('loop_end_seconds', clamped.toString());
  }

  // ============================================================================
  // Sample loading (file picker + drag-and-drop)
  // ============================================================================

  Future<void> _onLoadSample() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: SamplerEditor.acceptedExtensions,
      dialogTitle: 'Select Sample',
    );
    // The user can close the panel / switch tracks while the OS picker is
    // open; this State may be disposed by the time the future completes.
    if (!mounted) return;

    final path = result?.files.firstOrNull?.path;
    if (path != null) {
      _loadFromPath(path);
    }
  }

  void _loadFromPath(String path) {
    if (widget.audioEngine == null || widget.trackId == null) return;
    final ok = widget.audioEngine!.loadSampleForTrack(
      widget.trackId!,
      path,
      _rootNote,
    );
    if (ok) {
      _loadSampleData();
    } else if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not load that audio file')),
      );
    }
  }

  String? _firstAcceptedPath(Iterable<String> paths) {
    for (final path in paths) {
      final ext = path.split('.').last.toLowerCase();
      if (SamplerEditor.acceptedExtensions.contains(ext)) return path;
    }
    return null;
  }

  // ============================================================================
  // Keyboard strip audition
  // ============================================================================

  void _startAudition(int note) {
    if (widget.audioEngine == null || widget.trackId == null) return;
    _auditionNote = note;
    widget.audioEngine!.sendTrackMidiNoteOn(widget.trackId!, note, 100);
  }

  void _stopAudition() {
    final note = _auditionNote;
    if (note != null && widget.audioEngine != null && widget.trackId != null) {
      widget.audioEngine!.sendTrackMidiNoteOff(widget.trackId!, note, 0);
    }
    _auditionNote = null;
  }

  void _zoomIn() => _zoomByFactor(1.3);
  void _zoomOut() => _zoomByFactor(1.0 / 1.3);

  void _zoomByFactor(double factor) {
    final oldPps = _pixelsPerSecond;
    final newPps = (oldPps * factor).clamp(20.0, 800.0);
    if (newPps == oldPps) return;

    // Calculate new scroll offset to keep viewport center anchored
    double newScrollOffset = 0.0;
    if (_horizontalScroll.hasClients) {
      final viewportWidth = _horizontalScroll.position.viewportDimension;
      final centerOffset = _horizontalScroll.offset + viewportWidth / 2;
      final centerSeconds = centerOffset / oldPps;
      final newCenterOffset = centerSeconds * newPps;
      newScrollOffset = newCenterOffset - viewportWidth / 2;
    }

    setState(() {
      _pixelsPerSecond = newPps;
    });

    // Sync both scroll controllers after layout with new content size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScrollTo(newScrollOffset);
    });
  }

  /// Set both scroll controllers to the same offset (clamped to valid range).
  void _syncScrollTo(double offset) {
    if (_horizontalScroll.hasClients) {
      final max = _horizontalScroll.position.maxScrollExtent;
      final clamped = offset.clamp(0.0, max);
      _horizontalScroll.jumpTo(clamped);
      // Ruler syncs via listener
    }
  }

  // ============================================================================
  // Build
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (widget.trackId == null) {
      return _buildNoTrackState(colors);
    }

    if (!_hasSample) {
      return _buildDropZone(colors);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Auto-zoom to fit sample in available width on load
        if (_needsAutoZoom && _sampleDuration > 0 && constraints.maxWidth > 0) {
          _needsAutoZoom = false;
          _pixelsPerSecond = (constraints.maxWidth / _sampleDuration).clamp(
            20.0,
            800.0,
          );
        }

        final totalWidth = _sampleDuration * _pixelsPerSecond;

        return PlatformDropTarget(
          onDragDone: (details) {
            final path = _firstAcceptedPath(details.files.map((f) => f.path));
            if (path != null) _loadFromPath(path);
          },
          child: ColoredBox(
            color: colors.dark,
            child: Column(
              children: [
                // Controls bar (slim: Loop / Atk / Rel / Root / Reverse / Vol / Load)
                SamplerControlsBar(
                  loopEnabled: _loopEnabled,
                  attackMs: _attackMs,
                  releaseMs: _releaseMs,
                  rootNote: _rootNote,
                  reversed: _reversed,
                  volumeDb: _volumeDb,
                  onLoopToggle: () => _applyInstantParam(
                    'loop_enabled',
                    _loopEnabled ? '0' : '1',
                  ),
                  onReverseToggle: () =>
                      _applyInstantParam('reversed', _reversed ? '0' : '1'),
                  onRootNoteChanged: (note) =>
                      _applyInstantParam('root_note', note.toString()),
                  onAttackChanged: _onAttackChanged,
                  onReleaseChanged: _onReleaseChanged,
                  onVolumeChanged: _onVolumeChanged,
                  onVolumeReset: () => _applyInstantParam('volume_db', '0.0'),
                  onParamGestureStart: _beginParamGesture,
                  onParamGestureEnd: _endParamGesture,
                  onLoadSample: _onLoadSample,
                ),

                // Navigation bar with loop drag interaction
                NavBarWithZoom(
                  scrollController: _rulerScroll,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  height: 24.0,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _handleScrollWheel(event.scrollDelta.dy);
                      }
                    },
                    child: MouseRegion(
                      cursor: _getNavBarCursor(),
                      onHover: _handleNavBarHover,
                      onExit: (_) => setState(() => _navBarHoverSeconds = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _handleNavBarPanStart,
                        onPanUpdate: _handleNavBarPanUpdate,
                        onPanEnd: (_) => _endNavBarPan(),
                        onPanCancel: _endNavBarPan,
                        child: SizedBox(
                          width: totalWidth,
                          height: 24.0,
                          child: CustomPaint(
                            size: Size(totalWidth, 24.0),
                            painter: SamplerRulerPainter(
                              pixelsPerSecond: _pixelsPerSecond,
                              sampleDuration: _sampleDuration,
                              loopEnabled: _loopEnabled,
                              loopStartSeconds: _loopStartSeconds,
                              loopEndSeconds: _loopEndSeconds,
                              colors: colors,
                              hoverSeconds: _isNearLoopEdge(_navBarHoverSeconds)
                                  ? _navBarHoverSeconds
                                  : null,
                              textScale: MediaQuery.textScalerOf(
                                context,
                              ).scale(1.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Waveform area with on-waveform loop handles
                Expanded(child: _buildWaveformArea(colors)),

                // Audition keyboard
                SamplerKeyboardStrip(
                  rootNote: _rootNote,
                  onNoteOn: _startAudition,
                  onNoteOff: (_) => _stopAudition(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// No sampler track selected at all.
  Widget _buildNoTrackState(BoojyColors colors) {
    return ColoredBox(
      color: colors.dark,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(BI.musicNote, size: 64, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Sampler',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: BT.fontHeading,
                fontWeight: BT.weightSemiBold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a Sampler track to view the sample',
              style: TextStyle(color: colors.textMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Sampler track selected but no sample loaded yet — the empty state IS the
  /// load UI: a full-panel drop target with a Browse button.
  Widget _buildDropZone(BoojyColors colors) {
    final borderColor = _isDropHovering ? colors.accent : colors.surface;

    return PlatformDropTarget(
      onDragEntered: (_) => setState(() => _isDropHovering = true),
      onDragExited: (_) => setState(() => _isDropHovering = false),
      onDragDone: (details) {
        setState(() => _isDropHovering = false);
        final path = _firstAcceptedPath(details.files.map((f) => f.path));
        if (path != null) _loadFromPath(path);
      },
      child: ColoredBox(
        color: colors.dark,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // Bordered container with NO clip (corner-artifact rule).
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(BT.radiusMd),
              color: _isDropHovering
                  ? colors.accent.withValues(alpha: 0.06)
                  : Colors.transparent,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(BI.audioFile, size: 48, color: colors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Drop an audio file here',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: BT.fontLabel,
                      fontWeight: BT.weightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'WAV, MP3, FLAC or AIFF — or load one from disk',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: BT.fontCaption,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _onLoadSample,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.standard,
                          borderRadius: BorderRadius.circular(BT.radiusSm),
                          border: Border.all(color: colors.surface, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              BI.folderOpen,
                              size: 14,
                              color: colors.textPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Browse…',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: BT.fontLabel,
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
    );
  }

  // ============================================================================
  // Waveform area — scroll + on-waveform loop handle drag
  // ============================================================================

  Widget _buildWaveformArea(BoojyColors colors) {
    final totalWidth = _sampleDuration * _pixelsPerSecond;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;

        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _handleScrollWheel(event.scrollDelta.dy);
            }
          },
          child: SingleChildScrollView(
            controller: _horizontalScroll,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: MouseRegion(
              cursor: (_waveHoverEdge != null || _waveDragEdge != null)
                  ? SystemMouseCursors.resizeLeftRight
                  : MouseCursor.defer,
              onHover: _handleWaveformHover,
              onExit: (_) => setState(() => _waveHoverEdge = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _handleWaveformPanStart,
                onPanUpdate: _handleWaveformPanUpdate,
                onPanEnd: (_) => _endWaveformPan(),
                onPanCancel: _endWaveformPan,
                child: SizedBox(
                  width: totalWidth,
                  height: availableHeight,
                  child: CustomPaint(
                    size: Size(totalWidth, availableHeight),
                    painter: SamplerWaveformPainter(
                      peaks: _waveformPeaks,
                      sampleDuration: _sampleDuration,
                      pixelsPerSecond: _pixelsPerSecond,
                      loopEnabled: _loopEnabled,
                      loopStartSeconds: _loopStartSeconds,
                      loopEndSeconds: _loopEndSeconds,
                      colors: colors,
                      highlightedEdge: _waveDragEdge ?? _waveHoverEdge,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleScrollWheel(double delta) {
    if (!_horizontalScroll.hasClients) return;
    final newOffset = (_horizontalScroll.offset + delta).clamp(
      0.0,
      _horizontalScroll.position.maxScrollExtent,
    );
    _horizontalScroll.jumpTo(newOffset);
  }

  // ============================================================================
  // Coordinate helpers
  // ============================================================================

  static const double _edgeHitZone = 10.0;

  /// The ruler/waveform gesture children sit INSIDE their horizontal scroll
  /// views at full content width, so `localPosition.dx` is already content
  /// space — adding the scroll offset here would double-count it (the
  /// documented content-vs-viewport trap; loop drags drifted when scrolled).
  double _secondsAtX(double localX) => localX / _pixelsPerSecond;

  LoopEdge? _loopEdgeAt(double localX) {
    if (!_loopEnabled || !_hasSample) return null;
    final startX = _loopStartSeconds * _pixelsPerSecond;
    final endX = _loopEndSeconds * _pixelsPerSecond;
    if ((localX - startX).abs() < _edgeHitZone) return LoopEdge.start;
    if ((localX - endX).abs() < _edgeHitZone) return LoopEdge.end;
    return null;
  }

  bool _isNearLoopEdge(double? seconds) {
    if (seconds == null) return false;
    return _loopEdgeAt(seconds * _pixelsPerSecond) != null;
  }

  // ============================================================================
  // On-waveform loop handle drag
  // ============================================================================

  void _handleWaveformHover(PointerHoverEvent event) {
    final edge = _loopEdgeAt(event.localPosition.dx);
    if (edge != _waveHoverEdge) {
      setState(() => _waveHoverEdge = edge);
    }
  }

  void _handleWaveformPanStart(DragStartDetails details) {
    final edge = _loopEdgeAt(details.localPosition.dx);
    if (edge == null) return;
    setState(() => _waveDragEdge = edge);
    _beginParamGesture(
      edge == LoopEdge.start ? 'loop_start_seconds' : 'loop_end_seconds',
    );
  }

  void _handleWaveformPanUpdate(DragUpdateDetails details) {
    final edge = _waveDragEdge;
    if (edge == null) return;
    final seconds = _secondsAtX(details.localPosition.dx);
    if (edge == LoopEdge.start) {
      _onLoopStartChanged(seconds);
    } else {
      _onLoopEndChanged(seconds);
    }
  }

  void _endWaveformPan() {
    final edge = _waveDragEdge;
    if (edge == null) return;
    setState(() => _waveDragEdge = null);
    _endParamGesture(
      edge == LoopEdge.start ? 'loop_start_seconds' : 'loop_end_seconds',
    );
  }

  // ============================================================================
  // Nav bar loop interaction (hover + drag)
  // ============================================================================

  MouseCursor _getNavBarCursor() {
    if (_navDragMode == _NavDragMode.navigation) {
      return SystemMouseCursors.grabbing;
    }
    if (_navDragMode == _NavDragMode.loopStart ||
        _navDragMode == _NavDragMode.loopEnd) {
      return SystemMouseCursors.resizeLeftRight;
    }
    if (_isNearLoopEdge(_navBarHoverSeconds)) {
      return SystemMouseCursors.resizeLeftRight;
    }
    return SystemMouseCursors.grab;
  }

  void _handleNavBarHover(PointerHoverEvent event) {
    final seconds = _secondsAtX(event.localPosition.dx);
    setState(() => _navBarHoverSeconds = seconds);
  }

  void _handleNavBarPanStart(DragStartDetails details) {
    if (!_hasSample) return;

    final edge = _loopEdgeAt(details.localPosition.dx);
    if (edge == LoopEdge.start) {
      setState(() => _navDragMode = _NavDragMode.loopStart);
      _beginParamGesture('loop_start_seconds');
    } else if (edge == LoopEdge.end) {
      setState(() => _navDragMode = _NavDragMode.loopEnd);
      _beginParamGesture('loop_end_seconds');
    } else {
      setState(() {
        _navDragMode = _NavDragMode.navigation;
        _navDragStartX = details.globalPosition.dx;
        _navDragStartY = details.globalPosition.dy;
      });
    }
  }

  void _handleNavBarPanUpdate(DragUpdateDetails details) {
    if (_navDragMode == _NavDragMode.none || !_hasSample) return;

    switch (_navDragMode) {
      case _NavDragMode.loopStart:
        _onLoopStartChanged(_secondsAtX(details.localPosition.dx));
      case _NavDragMode.loopEnd:
        _onLoopEndChanged(_secondsAtX(details.localPosition.dx));
      case _NavDragMode.navigation:
        _handleNavBarNavigationDrag(details);
      case _NavDragMode.none:
        break;
    }
  }

  void _endNavBarPan() {
    final mode = _navDragMode;
    setState(() {
      _navDragMode = _NavDragMode.none;
      _navDragStartX = null;
      _navDragStartY = null;
    });
    if (mode == _NavDragMode.loopStart) {
      _endParamGesture('loop_start_seconds');
    } else if (mode == _NavDragMode.loopEnd) {
      _endParamGesture('loop_end_seconds');
    }
  }

  void _handleNavBarNavigationDrag(DragUpdateDetails details) {
    if (_navDragStartX == null || _navDragStartY == null) return;

    final deltaX = details.globalPosition.dx - _navDragStartX!;
    final deltaY = details.globalPosition.dy - _navDragStartY!;

    // Horizontal drag = scroll (opposite direction — drag right = scroll left)
    if (deltaX.abs() > 2 && _horizontalScroll.hasClients) {
      final newOffset = (_horizontalScroll.offset - deltaX).clamp(
        0.0,
        _horizontalScroll.position.maxScrollExtent,
      );
      _horizontalScroll.jumpTo(newOffset);
      _navDragStartX = details.globalPosition.dx;
    }

    // Vertical drag = zoom (drag up = zoom in, drag down = zoom out)
    if (deltaY.abs() > 2) {
      final factor = 1.0 - (deltaY / 200.0);
      _zoomByFactor(factor);
      _navDragStartY = details.globalPosition.dy;
    }
  }
}

enum _NavDragMode { none, loopStart, loopEnd, navigation }
