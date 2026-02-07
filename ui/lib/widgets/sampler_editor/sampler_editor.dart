import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../audio_engine.dart';
import '../../theme/theme_extension.dart';
import '../../theme/app_colors.dart';
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

  // Waveform data (real peaks from engine)
  List<double> _waveformPeaks = [];

  // Zoom and scroll
  double _pixelsPerSecond = 100.0;
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _rulerScroll = ScrollController();

  // Loop marker dragging
  _DragTarget? _activeDrag;

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
      setState(() {
        _sampleDuration = info.durationSeconds;
        _loopEnabled = info.loopEnabled;
        _loopStartSeconds = info.loopStartSeconds;
        _loopEndSeconds = info.loopEndSeconds;
        _rootNote = info.rootNote;
        _attackMs = info.attackMs;
        _releaseMs = info.releaseMs;
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

  void _zoomIn() {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond * 1.3).clamp(20.0, 800.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond / 1.3).clamp(20.0, 800.0);
    });
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
        return ColoredBox(
          color: colors.dark,
          child: Column(
            children: [
              // Controls bar (two rows)
              SamplerControlsBar(
                loopEnabled: _loopEnabled,
                attackMs: _attackMs,
                releaseMs: _releaseMs,
                rootNote: _rootNote,
                onLoopToggle: _onLoopToggle,
                onAttackChanged: _onAttackChanged,
                onReleaseChanged: _onReleaseChanged,
                onRootNoteChanged: _onRootNoteChanged,
                onLoadSample: _onLoadSample,
              ),

              // Ruler Row (seconds-based)
              _buildRulerRow(colors),

              // Waveform Area with loop markers and envelope overlay
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
  // Ruler (seconds-based)
  // ============================================================================

  Widget _buildRulerRow(BoojyColors colors) {
    final totalWidth = _sampleDuration > 0
        ? _sampleDuration * _pixelsPerSecond
        : 400.0;

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          // Ruler
          Expanded(
            child: SingleChildScrollView(
              controller: _rulerScroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: totalWidth,
                child: CustomPaint(
                  painter: SamplerRulerPainter(
                    pixelsPerSecond: _pixelsPerSecond,
                    sampleDuration: _sampleDuration,
                    loopEnabled: _loopEnabled,
                    loopStartSeconds: _loopStartSeconds,
                    loopEndSeconds: _loopEndSeconds,
                    colors: colors,
                  ),
                ),
              ),
            ),
          ),

          // Zoom controls
          SizedBox(
            width: 48,
            child: Container(
              color: colors.dark,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildZoomButton(Icons.remove, _zoomOut, colors),
                  _buildZoomButton(Icons.add, _zoomIn, colors),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(
      IconData icon, VoidCallback onTap, BoojyColors colors) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 14,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Waveform area with loop markers
  // ============================================================================

  Widget _buildWaveformArea(BoojyColors colors) {
    final totalWidth = _sampleDuration > 0
        ? _sampleDuration * _pixelsPerSecond
        : 400.0;

    return Row(
      children: [
        // Waveform area with gesture detection
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;

              return GestureDetector(
                onHorizontalDragStart: (details) {
                  _handleDragStart(details);
                },
                onHorizontalDragUpdate: (details) {
                  _handleDragUpdate(details);
                },
                onHorizontalDragEnd: (details) {
                  _handleDragEnd();
                },
                child: MouseRegion(
                  cursor: _getCursor(),
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
                          attackMs: _attackMs,
                          releaseMs: _releaseMs,
                          loopEnabled: _loopEnabled,
                          loopStartSeconds: _loopStartSeconds,
                          loopEndSeconds: _loopEndSeconds,
                          colors: colors,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Right margin (under zoom buttons)
        SizedBox(
          width: 48,
          child: ColoredBox(color: colors.dark),
        ),
      ],
    );
  }

  // ============================================================================
  // Loop marker dragging
  // ============================================================================

  MouseCursor _getCursor() {
    if (_activeDrag != null) return SystemMouseCursors.resizeLeftRight;
    return SystemMouseCursors.basic;
  }

  void _handleDragStart(DragStartDetails details) {
    if (_sampleDuration <= 0) return;

    final x = details.localPosition.dx +
        (_horizontalScroll.hasClients ? _horizontalScroll.offset : 0);
    final loopStartX = _loopStartSeconds * _pixelsPerSecond;
    final loopEndX = _loopEndSeconds * _pixelsPerSecond;

    const hitThreshold = 8.0;

    // Check if near loop start marker
    if ((x - loopStartX).abs() < hitThreshold) {
      _activeDrag = _DragTarget.loopStart;
      return;
    }

    // Check if near loop end marker
    if ((x - loopEndX).abs() < hitThreshold) {
      _activeDrag = _DragTarget.loopEnd;
      return;
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_activeDrag == null || _sampleDuration <= 0) return;

    final x = details.localPosition.dx +
        (_horizontalScroll.hasClients ? _horizontalScroll.offset : 0);
    final seconds = x / _pixelsPerSecond;

    switch (_activeDrag!) {
      case _DragTarget.loopStart:
        _onLoopStartChanged(seconds);
      case _DragTarget.loopEnd:
        _onLoopEndChanged(seconds);
    }
  }

  void _handleDragEnd() {
    _activeDrag = null;
  }
}

enum _DragTarget { loopStart, loopEnd }
