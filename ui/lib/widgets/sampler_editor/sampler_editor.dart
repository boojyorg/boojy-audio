import 'package:flutter/material.dart';
import '../../audio_engine.dart';
import '../../theme/theme_extension.dart';
import '../../theme/app_colors.dart';
import 'sampler_controls_bar.dart';

/// Sampler Editor widget for editing sampler instrument parameters.
/// Displays the loaded sample waveform and provides controls for
/// Attack, Release, and Root Note in addition to the audio waveform view.
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
  double _attackMs = 10.0; // Default 10ms attack
  double _releaseMs = 100.0; // Default 100ms release
  int _rootNote = 60; // C4

  // Waveform data (will be loaded from sample)
  List<double> _waveformPeaks = [];

  // Zoom and scroll
  double _pixelsPerBeat = 40.0;
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _rulerScroll = ScrollController();

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
    // TODO: Load waveform peaks from the sampler's loaded sample
    // For now, generate placeholder data
    setState(() {
      _waveformPeaks = List.generate(1000, (i) {
        final t = i / 1000.0;
        // Simple envelope shape for visual feedback
        final envelope = (1 - t) * (t * 4).clamp(0.0, 1.0);
        return envelope * 0.8;
      });
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

  void _sendParameterToEngine(String param, String value) {
    if (widget.audioEngine != null && widget.trackId != null) {
      widget.audioEngine!.setSamplerParameter(widget.trackId!, param, value);
    }
  }

  void _zoomIn() {
    setState(() {
      _pixelsPerBeat = (_pixelsPerBeat * 1.2).clamp(10.0, 200.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _pixelsPerBeat = (_pixelsPerBeat / 1.2).clamp(10.0, 200.0);
    });
  }

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
              // Controls Bar with Attack/Release/Root Note
              SamplerControlsBar(
                attackMs: _attackMs,
                releaseMs: _releaseMs,
                rootNote: _rootNote,
                onAttackChanged: _onAttackChanged,
                onReleaseChanged: _onReleaseChanged,
                onRootNoteChanged: _onRootNoteChanged,
              ),

              // Ruler Row
              _buildRulerRow(colors),

              // Waveform Area with Envelope Overlay
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

  Widget _buildRulerRow(BoojyColors colors) {
    const totalBeats = 16.0; // Fixed for sampler view

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          // Left corner
          SizedBox(
            width: 80,
            child: ColoredBox(color: colors.dark),
          ),

          // Ruler
          Expanded(
            child: SingleChildScrollView(
              controller: _rulerScroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: totalBeats * _pixelsPerBeat,
                child: CustomPaint(
                  painter: _SamplerRulerPainter(
                    pixelsPerBeat: _pixelsPerBeat,
                    totalBeats: totalBeats,
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

  Widget _buildWaveformArea(BoojyColors colors) {
    const totalBeats = 16.0;

    return Row(
      children: [
        // Left margin with root note indicator
        SizedBox(
          width: 80,
          child: Container(
            color: colors.dark,
            child: Center(
              child: Text(
                _midiNoteToName(_rootNote),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        // Waveform area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;

              return SingleChildScrollView(
                controller: _horizontalScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: totalBeats * _pixelsPerBeat,
                  height: availableHeight,
                  child: CustomPaint(
                    size: Size(totalBeats * _pixelsPerBeat, availableHeight),
                    painter: _SamplerWaveformPainter(
                      peaks: _waveformPeaks,
                      attackMs: _attackMs,
                      releaseMs: _releaseMs,
                      pixelsPerBeat: _pixelsPerBeat,
                      totalBeats: totalBeats,
                      colors: colors,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Right margin
        SizedBox(
          width: 48,
          child: ColoredBox(color: colors.dark),
        ),
      ],
    );
  }

  String _midiNoteToName(int note) {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B'
    ];
    final octave = (note ~/ 12) - 1;
    final noteName = noteNames[note % 12];
    return '$noteName$octave';
  }
}

/// Custom painter for sampler ruler
class _SamplerRulerPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final BoojyColors colors;

  _SamplerRulerPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.divider
      ..strokeWidth = 1;

    final textPaint = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw beat markers
    for (int beat = 0; beat <= totalBeats.toInt(); beat++) {
      final x = beat * pixelsPerBeat;

      // Draw tick
      final isBar = beat % 4 == 0;
      canvas.drawLine(
        Offset(x, isBar ? 0 : size.height * 0.5),
        Offset(x, size.height),
        paint,
      );

      // Draw beat number at bar lines
      if (isBar) {
        textPaint.text = TextSpan(
          text: '${beat ~/ 4 + 1}',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
          ),
        );
        textPaint.layout();
        textPaint.paint(canvas, Offset(x + 2, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SamplerRulerPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        totalBeats != oldDelegate.totalBeats;
  }
}

/// Custom painter for sampler waveform with envelope overlay
class _SamplerWaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double attackMs;
  final double releaseMs;
  final double pixelsPerBeat;
  final double totalBeats;
  final BoojyColors colors;

  _SamplerWaveformPainter({
    required this.peaks,
    required this.attackMs,
    required this.releaseMs,
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final waveformPaint = Paint()
      ..color = colors.accent.withAlpha(180)
      ..style = PaintingStyle.fill;

    final envelopePaint = Paint()
      ..color = colors.warning.withAlpha(100)
      ..style = PaintingStyle.fill;

    final envelopeStrokePaint = Paint()
      ..color = colors.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final totalWidth = totalBeats * pixelsPerBeat;
    final centerY = size.height / 2;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = colors.divider.withAlpha(50)
      ..strokeWidth = 1;

    for (int beat = 0; beat <= totalBeats.toInt(); beat++) {
      final x = beat * pixelsPerBeat;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw waveform
    final path = Path();
    path.moveTo(0, centerY);

    for (int i = 0; i < peaks.length; i++) {
      final x = (i / peaks.length) * totalWidth;
      final amplitude = peaks[i] * (size.height * 0.4);
      path.lineTo(x, centerY - amplitude);
    }

    // Return path
    for (int i = peaks.length - 1; i >= 0; i--) {
      final x = (i / peaks.length) * totalWidth;
      final amplitude = peaks[i] * (size.height * 0.4);
      path.lineTo(x, centerY + amplitude);
    }

    path.close();
    canvas.drawPath(path, waveformPaint);

    // Draw envelope overlay
    // Simplified: show attack and release regions
    const sampleDurationMs = 2000.0; // Assume 2 second sample for visualization
    final attackWidth = (attackMs / sampleDurationMs) * totalWidth;
    final releaseStart = totalWidth - (releaseMs / sampleDurationMs) * totalWidth;

    // Attack region
    final attackPath = Path();
    attackPath.moveTo(0, size.height);
    attackPath.lineTo(0, centerY);
    attackPath.lineTo(attackWidth, 0);
    attackPath.lineTo(attackWidth, size.height);
    attackPath.close();
    canvas.drawPath(attackPath, envelopePaint);

    // Release region
    final releasePath = Path();
    releasePath.moveTo(releaseStart, 0);
    releasePath.lineTo(totalWidth, centerY);
    releasePath.lineTo(totalWidth, size.height);
    releasePath.lineTo(releaseStart, size.height);
    releasePath.close();
    canvas.drawPath(releasePath, envelopePaint);

    // Envelope curve stroke
    final envelopeCurve = Path();
    envelopeCurve.moveTo(0, size.height);
    envelopeCurve.lineTo(attackWidth, 0);
    envelopeCurve.lineTo(releaseStart, 0);
    envelopeCurve.lineTo(totalWidth, size.height);
    canvas.drawPath(envelopeCurve, envelopeStrokePaint);

    // Draw center line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(totalWidth, centerY),
      Paint()
        ..color = colors.textMuted.withAlpha(100)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SamplerWaveformPainter oldDelegate) {
    return peaks != oldDelegate.peaks ||
        attackMs != oldDelegate.attackMs ||
        releaseMs != oldDelegate.releaseMs ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat;
  }
}
