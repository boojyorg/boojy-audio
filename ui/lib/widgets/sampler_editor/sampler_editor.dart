import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../audio_engine.dart';
import '../../theme/theme_extension.dart';
import '../../theme/app_colors.dart';
import '../shared/editors/nav_bar_with_zoom.dart';
import 'sampler_controls_bar.dart';
import 'sampler_waveform_painter.dart';

/// Sampler Editor widget for editing sampler instrument parameters.
/// Displays the loaded sample waveform with loop markers, seconds ruler,
/// and provides controls for Loop, Attack, Release, Root Note, and Load.
class SamplerEditor extends StatefulWidget {
  final AudioEngine? audioEngine;
  final int? trackId;
  final String? samplePath;
  final VoidCallback? onClose;

  const SamplerEditor({
    super.key,
    this.audioEngine,
    this.trackId,
    this.samplePath,
    this.onClose,
  });

  @override
  State<SamplerEditor> createState() => _SamplerEditorState();
}

class _SamplerEditorState extends State<SamplerEditor> {
  // Sampler parameters
  double _attackMs = 1.0;
  double _releaseMs = 50.0;
  int _rootNote = 60; // C4
  bool _loopEnabled = false;
  double _loopStartSeconds = 0.0;
  double _loopEndSeconds = 1.0;
  double _sampleDuration = 0.0; // in seconds

  // Audio manipulation parameters (matching Audio Editor)
  int _transposeSemitones = 0;
  int _fineCents = 0;
  double _volumeDb = 0.0;
  bool _reversed = false;
  double _originalBpm = 120.0;
  bool _warpEnabled = false;
  int _warpMode = 0; // 0=repitch, 1=warp
  int _beatsPerBar = 4;
  int _beatUnit = 4;

  // Waveform data (real peaks from engine)
  List<double> _waveformPeaks = [];

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

  @override
  void initState() {
    super.initState();
    _loadSampleData();
    _syncScrollControllers();
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _rulerScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SamplerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackId != oldWidget.trackId ||
        widget.samplePath != oldWidget.samplePath) {
      _loadSampleData();
    }
  }

  void _loadSampleData() {
    if (widget.audioEngine == null || widget.trackId == null) return;

    final info = widget.audioEngine!.getSamplerInfo(widget.trackId!);
    if (info != null) {
      _needsAutoZoom = true;
      setState(() {
        _sampleDuration = info.durationSeconds;
        _loopEnabled = info.loopEnabled;
        _loopStartSeconds = info.loopStartSeconds;
        _loopEndSeconds = info.loopEndSeconds;
        _rootNote = info.rootNote;
        _attackMs = info.attackMs;
        _releaseMs = info.releaseMs;
        _volumeDb = info.volumeDb;
        _transposeSemitones = info.transposeSemitones;
        _fineCents = info.fineCents;
        _reversed = info.reversed;
        _originalBpm = info.originalBpm;
        _warpEnabled = info.warpEnabled;
        _warpMode = info.warpMode;
        _beatsPerBar = info.beatsPerBar;
        _beatUnit = info.beatUnit;
      });
    }

    // Load waveform peaks
    final peaks = widget.audioEngine!.getSamplerWaveformPeaks(
      widget.trackId!,
      2048, // resolution - enough for smooth display
    );
    if (peaks.isNotEmpty) {
      setState(() {
        _waveformPeaks = peaks;
      });
    }
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
  // Parameter callbacks
  // ============================================================================

  void _onAttackChanged(double value) {
    setState(() => _attackMs = value);
    _sendParameterToEngine('attack_ms', value.toString());
  }

  void _onReleaseChanged(double value) {
    setState(() => _releaseMs = value);
    _sendParameterToEngine('release_ms', value.toString());
  }

  void _onRootNoteChanged(int value) {
    setState(() => _rootNote = value);
    _sendParameterToEngine('root_note', value.toString());
  }

  void _onLoopToggle() {
    setState(() => _loopEnabled = !_loopEnabled);
    _sendParameterToEngine('loop_enabled', _loopEnabled ? '1' : '0');
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

  void _onVolumeChanged(double value) {
    setState(() => _volumeDb = value);
    _sendParameterToEngine('volume_db', value.toString());
  }

  void _onTransposeChanged(int value) {
    setState(() => _transposeSemitones = value);
    _sendParameterToEngine('transpose_semitones', value.toString());
  }

  void _onFineCentsChanged(int value) {
    setState(() => _fineCents = value);
    _sendParameterToEngine('fine_cents', value.toString());
  }

  void _onReverseToggle() {
    setState(() => _reversed = !_reversed);
    _sendParameterToEngine('reversed', _reversed ? '1' : '0');
  }

  void _onOriginalBpmChanged(double value) {
    setState(() => _originalBpm = value);
    _sendParameterToEngine('original_bpm', value.toString());
  }

  void _onWarpToggle() {
    setState(() => _warpEnabled = !_warpEnabled);
    _sendParameterToEngine('warp_enabled', _warpEnabled ? '1' : '0');
  }

  void _onWarpModeChanged(int value) {
    setState(() => _warpMode = value);
    _sendParameterToEngine('warp_mode', value.toString());
  }

  void _onSignatureChanged(int beatsPerBar, int beatUnit) {
    setState(() {
      _beatsPerBar = beatsPerBar;
      _beatUnit = beatUnit;
    });
    _sendParameterToEngine('beats_per_bar', beatsPerBar.toString());
    _sendParameterToEngine('beat_unit', beatUnit.toString());
  }

  void _sendParameterToEngine(String param, String value) {
    if (widget.audioEngine != null && widget.trackId != null) {
      widget.audioEngine!.setSamplerParameter(widget.trackId!, param, value);
    }
  }

  Future<void> _onLoadSample() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'flac', 'aif', 'aiff'],
      dialogTitle: 'Select Sample',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (widget.audioEngine != null && widget.trackId != null) {
        widget.audioEngine!.loadSampleForTrack(widget.trackId!, path, _rootNote);
        _loadSampleData(); // Refresh
      }
    }
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
      return _buildEmptyState(colors);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Auto-zoom to fit sample in available width on load
        if (_needsAutoZoom && _sampleDuration > 0 && constraints.maxWidth > 0) {
          _needsAutoZoom = false;
          _pixelsPerSecond = (constraints.maxWidth / _sampleDuration)
              .clamp(20.0, 800.0);
        }

        final totalWidth = _sampleDuration > 0
            ? _sampleDuration * _pixelsPerSecond
            : 400.0;

        return ColoredBox(
          color: colors.dark,
          child: Column(
            children: [
              // Controls bar
              SamplerControlsBar(
                loopEnabled: _loopEnabled,
                attackMs: _attackMs,
                releaseMs: _releaseMs,
                rootNote: _rootNote,
                onLoopToggle: _onLoopToggle,
                onAttackChanged: _onAttackChanged,
                onReleaseChanged: _onReleaseChanged,
                onRootNoteChanged: _onRootNoteChanged,
                loopStartSeconds: _loopStartSeconds,
                loopEndSeconds: _loopEndSeconds,
                sampleDuration: _sampleDuration,
                onLoopStartChanged: _onLoopStartChanged,
                onLoopEndChanged: _onLoopEndChanged,
                beatsPerBar: _beatsPerBar,
                beatUnit: _beatUnit,
                onSignatureChanged: _onSignatureChanged,
                warpEnabled: _warpEnabled,
                onWarpToggle: _onWarpToggle,
                warpMode: _warpMode,
                onWarpModeChanged: _onWarpModeChanged,
                originalBpm: _originalBpm,
                onOriginalBpmChanged: _onOriginalBpmChanged,
                reversed: _reversed,
                onReverseToggle: _onReverseToggle,
                transposeSemitones: _transposeSemitones,
                fineCents: _fineCents,
                onTransposeChanged: _onTransposeChanged,
                onFineCentsChanged: _onFineCentsChanged,
                volumeDb: _volumeDb,
                onVolumeChanged: _onVolumeChanged,
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
                    onPanEnd: (_) => setState(() {
                      _navDragMode = _NavDragMode.none;
                      _navDragStartX = null;
                      _navDragStartY = null;
                    }),
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
                            originalBpm: _originalBpm,
                            beatsPerBar: _beatsPerBar,
                            hoverSeconds: _isNearLoopEdge(_navBarHoverSeconds)
                                ? _navBarHoverSeconds
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Waveform area (simple scrollable, no drag interaction)
              Expanded(child: _buildWaveformArea(colors)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BoojyColors colors) {
    return ColoredBox(
      color: colors.dark,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 64,
              color: colors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Sampler',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a Sampler track to view the sample',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // Waveform area (simple scrollable display, no drag interaction)
  // ============================================================================

  Widget _buildWaveformArea(BoojyColors colors) {
    final totalWidth = _sampleDuration > 0
        ? _sampleDuration * _pixelsPerSecond
        : 400.0;

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
                  originalBpm: _originalBpm,
                  beatsPerBar: _beatsPerBar,
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
  // Nav bar loop interaction (hover + drag)
  // ============================================================================

  static const double _edgeHitZone = 10.0;

  double _secondsAtX(double localX) {
    final scrollOffset = _rulerScroll.hasClients ? _rulerScroll.offset : 0.0;
    return (localX + scrollOffset) / _pixelsPerSecond;
  }

  bool _isNearLoopEdge(double? seconds) {
    if (seconds == null) return false;
    final x = seconds * _pixelsPerSecond;
    final startX = _loopStartSeconds * _pixelsPerSecond;
    final endX = _loopEndSeconds * _pixelsPerSecond;
    return (x - startX).abs() < _edgeHitZone ||
        (x - endX).abs() < _edgeHitZone;
  }

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
    if (_sampleDuration <= 0) return;

    final seconds = _secondsAtX(details.localPosition.dx);
    final x = seconds * _pixelsPerSecond;
    final startX = _loopStartSeconds * _pixelsPerSecond;
    final endX = _loopEndSeconds * _pixelsPerSecond;

    if ((x - startX).abs() < _edgeHitZone) {
      setState(() => _navDragMode = _NavDragMode.loopStart);
    } else if ((x - endX).abs() < _edgeHitZone) {
      setState(() => _navDragMode = _NavDragMode.loopEnd);
    } else {
      setState(() {
        _navDragMode = _NavDragMode.navigation;
        _navDragStartX = details.globalPosition.dx;
        _navDragStartY = details.globalPosition.dy;
      });
    }
  }

  void _handleNavBarPanUpdate(DragUpdateDetails details) {
    if (_navDragMode == _NavDragMode.none || _sampleDuration <= 0) return;

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
