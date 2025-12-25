import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../models/instrument_data.dart';
import 'instrument_browser.dart';

/// Synthesizer instrument panel widget
class SynthesizerPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final int trackId;
  final InstrumentData? instrumentData;
  final Function(InstrumentData) onParameterChanged;
  final VoidCallback onClose;

  const SynthesizerPanel({
    super.key,
    required this.audioEngine,
    required this.trackId,
    required this.instrumentData,
    required this.onParameterChanged,
    required this.onClose,
  });

  @override
  State<SynthesizerPanel> createState() => _SynthesizerPanelState();
}

class _SynthesizerPanelState extends State<SynthesizerPanel> {
  late InstrumentData _currentData;

  @override
  void initState() {
    super.initState();
    _currentData = widget.instrumentData ??
        InstrumentData.defaultSynthesizer(widget.trackId);
  }

  @override
  void didUpdateWidget(SynthesizerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.instrumentData != null &&
        widget.instrumentData != oldWidget.instrumentData) {
      _currentData = widget.instrumentData!;
    }
  }

  void _updateParameter(String key, dynamic value) {
    setState(() {
      _currentData = _currentData.updateParameter(key, value);
    });
    widget.onParameterChanged(_currentData);

    // Send to audio engine
    if (widget.audioEngine != null) {
      widget.audioEngine!.setSynthParameter(widget.trackId, key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF2B2B2B),
        border: Border(
          left: BorderSide(color: Color(0xFF404040)),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Synth controls - Minimal: 1 osc, filter cutoff, ADSR
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOscillatorSection(),
                  const SizedBox(height: 20),
                  _buildFilterSection(),
                  const SizedBox(height: 20),
                  _buildEnvelopeSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF404040)),
        ),
      ),
      child: Row(
        children: [
          // Make instrument name draggable (instant drag)
          Draggable<Instrument>(
            data: const Instrument(
              id: 'synthesizer',
              name: 'Synthesizer',
              category: 'Synthesizer',
              icon: Icons.graphic_eq,
            ),
            feedback: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Synthesizer',
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
            childWhenDragging: Opacity(
              opacity: 0.5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.piano,
                    color: Color(0xFFA0A0A0),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'SYNTHESIZER',
                    style: TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.piano,
                    color: Color(0xFFA0A0A0),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'SYNTHESIZER',
                    style: TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            color: const Color(0xFFA0A0A0),
            iconSize: 20,
            onPressed: widget.onClose,
            tooltip: 'Close synthesizer',
          ),
        ],
      ),
    );
  }

  Widget _buildOscillatorSection() {
    // Single oscillator - uses 'osc_type' key to match new minimal synth
    final type = _currentData.getParameter<String>('osc_type', 'saw');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF404040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with waveform preview
          Row(
            children: [
              const Icon(
                Icons.graphic_eq,
                color: Color(0xFF4CAF50),
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'OSCILLATOR',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Waveform visualization
          _buildWaveformPreview(type),
          const SizedBox(height: 16),

          // Waveform type dropdown
          _buildDropdown(
            'Type',
            type,
            ['sine', 'saw', 'square', 'triangle'],
            (value) => _updateParameter('osc_type', value),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformPreview(String waveType) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF404040)),
      ),
      child: CustomPaint(
        painter: WaveformPainter(waveType: waveType),
        size: const Size(double.infinity, 60),
      ),
    );
  }

  Widget _buildFilterSection() {
    // Simple one-pole lowpass filter - cutoff only
    final cutoff = _currentData.getParameter<double>('filter_cutoff', 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF404040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: const [
              Icon(
                Icons.filter_alt,
                color: Color(0xFF4CAF50),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'FILTER (LOWPASS)',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Cutoff slider
          _buildSlider(
            'Cutoff',
            cutoff,
            0.0,
            1.0,
            (value) => _updateParameter('filter_cutoff', value),
            formatter: (val) {
              // Map 0-1 to frequency range
              if (val >= 0.95) return 'OPEN';
              final freq = 100 + (val * 9900); // 100Hz to 10kHz
              if (freq >= 1000) {
                return '${(freq / 1000).toStringAsFixed(1)}kHz';
              }
              return '${freq.toStringAsFixed(0)}Hz';
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEnvelopeSection() {
    final attack = _currentData.getParameter<double>('env_attack', 0.01);
    final decay = _currentData.getParameter<double>('env_decay', 0.1);
    final sustain = _currentData.getParameter<double>('env_sustain', 0.7);
    final release = _currentData.getParameter<double>('env_release', 0.3);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF404040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: const [
              Icon(
                Icons.show_chart,
                color: Color(0xFF4CAF50),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'ENVELOPE (ADSR)',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ADSR visualization
          _buildADSRPreview(attack, decay, sustain, release),
          const SizedBox(height: 16),

          // Attack slider
          _buildSlider(
            'Attack',
            attack,
            0.001,
            2.0,
            (value) => _updateParameter('env_attack', value),
            formatter: (val) => '${(val * 1000).toStringAsFixed(0)}ms',
          ),
          const SizedBox(height: 12),

          // Decay slider
          _buildSlider(
            'Decay',
            decay,
            0.001,
            2.0,
            (value) => _updateParameter('env_decay', value),
            formatter: (val) => '${(val * 1000).toStringAsFixed(0)}ms',
          ),
          const SizedBox(height: 12),

          // Sustain slider
          _buildSlider(
            'Sustain',
            sustain,
            0.0,
            1.0,
            (value) => _updateParameter('env_sustain', value),
            formatter: (val) => '${(val * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 12),

          // Release slider
          _buildSlider(
            'Release',
            release,
            0.001,
            5.0,
            (value) => _updateParameter('env_release', value),
            formatter: (val) => '${(val * 1000).toStringAsFixed(0)}ms',
          ),
        ],
      ),
    );
  }

  Widget _buildADSRPreview(
      double attack, double decay, double sustain, double release) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF404040)),
      ),
      child: CustomPaint(
        painter: ADSRPainter(
          attack: attack,
          decay: decay,
          sustain: sustain,
          release: release,
        ),
        size: const Size(double.infinity, 80),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> options,
    Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF808080),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2B2B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF404040)),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF2B2B2B),
            style: const TextStyle(
              color: Color(0xFFA0A0A0),
              fontSize: 13,
            ),
            items: options.map((String option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(option.toUpperCase()),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged, {
    String Function(double)? formatter,
  }) {
    final displayValue = formatter != null ? formatter(value) : value.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF808080),
                fontSize: 12,
              ),
            ),
            Text(
              displayValue,
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 7,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 14,
            ),
            activeTrackColor: const Color(0xFF4CAF50),
            inactiveTrackColor: const Color(0xFF404040),
            thumbColor: const Color(0xFFA0A0A0),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Custom painter for waveform visualization
class WaveformPainter extends CustomPainter {
  final String waveType;

  WaveformPainter({required this.waveType});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final amplitude = size.height * 0.35;

    for (var i = 0; i < size.width; i++) {
      final x = i.toDouble();
      final normalizedX = (i / size.width) * 4 * 3.14159; // 2 cycles
      double y;

      switch (waveType) {
        case 'sine':
          y = centerY + amplitude * sin(normalizedX);
          break;
        case 'saw':
          y = centerY + amplitude * (2 * ((normalizedX / (2 * 3.14159)) % 1) - 1);
          break;
        case 'square':
          y = centerY + amplitude * (sin(normalizedX) > 0 ? 1 : -1);
          break;
        case 'triangle':
          final phase = (normalizedX / (2 * 3.14159)) % 1;
          y = centerY + amplitude * (phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase);
          break;
        default:
          y = centerY;
      }

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.waveType != waveType;

  double sin(double x) {
    // Simple sine approximation
    return (x - (x * x * x) / 6 + (x * x * x * x * x) / 120);
  }
}

/// Custom painter for ADSR envelope visualization
class ADSRPainter extends CustomPainter {
  final double attack;
  final double decay;
  final double sustain;
  final double release;

  ADSRPainter({
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Calculate time proportions
    final totalTime = attack + decay + 0.5 + release; // 0.5s for sustain display
    final attackWidth = (attack / totalTime) * size.width;
    final decayWidth = (decay / totalTime) * size.width;
    final sustainWidth = (0.5 / totalTime) * size.width;
    final releaseWidth = (release / totalTime) * size.width;

    final bottom = size.height - 10;
    final top = 10.0;
    final sustainY = bottom - (sustain * (bottom - top));

    // Start at bottom left
    path.moveTo(0, bottom);

    // Attack: rise to peak
    path.lineTo(attackWidth, top);

    // Decay: drop to sustain level
    path.lineTo(attackWidth + decayWidth, sustainY);

    // Sustain: hold level
    path.lineTo(attackWidth + decayWidth + sustainWidth, sustainY);

    // Release: drop to zero
    path.lineTo(attackWidth + decayWidth + sustainWidth + releaseWidth, bottom);

    canvas.drawPath(path, paint);

    // Draw labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    void drawLabel(String text, double x, double y) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF808080),
          fontSize: 10,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y));
    }

    drawLabel('A', attackWidth / 2, bottom + 5);
    drawLabel('D', attackWidth + decayWidth / 2, bottom + 5);
    drawLabel('S', attackWidth + decayWidth + sustainWidth / 2, bottom + 5);
    drawLabel(
        'R', attackWidth + decayWidth + sustainWidth + releaseWidth / 2, bottom + 5);
  }

  @override
  bool shouldRepaint(ADSRPainter oldDelegate) =>
      oldDelegate.attack != attack ||
      oldDelegate.decay != decay ||
      oldDelegate.sustain != sustain ||
      oldDelegate.release != release;
}
