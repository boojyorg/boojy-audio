import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Record button states for the CustomPainter
enum _RecordButtonVisualState { idle, disabled, countingIn, recording }

/// Record button with count-in ring timer and right-click context menu.
///
/// During count-in: depleting orange ring + beat number inside.
/// During recording: solid red fill + white dot + glow.
/// Transition flash on recording start.
class RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isCountingIn;
  final int countInBars;
  final int countInBeat; // 1-indexed beat number from engine
  final double countInProgress; // 0.0-1.0 from engine
  final int beatsPerBar; // time signature numerator
  final VoidCallback? onPressed;
  final Function(int)? onCountInChanged;
  final double size;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isCountingIn,
    required this.countInBars,
    this.countInBeat = 0,
    this.countInProgress = 0.0,
    this.beatsPerBar = 4,
    required this.onPressed,
    required this.onCountInChanged,
    this.size = 40,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with TickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _flashController;
  late AnimationController _pulseController;
  bool _wasCountingIn = false;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _wasCountingIn = widget.isCountingIn;
  }

  @override
  void didUpdateWidget(RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Flash on count-in → recording transition
    if (widget.isRecording && !oldWidget.isRecording && _wasCountingIn) {
      _flashController.forward(from: 0.0);
    }

    _wasCountingIn = widget.isCountingIn;
  }

  @override
  void dispose() {
    _flashController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _showCountInMenu(BuildContext context, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.close, size: 16),
              SizedBox(width: 8),
              Text('Count-in: Off'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.looks_one, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 1 Bar'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(Icons.looks_two, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 2 Bars'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 4,
          child: Row(
            children: [
              Icon(Icons.looks_4, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 4 Bars'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        widget.onCountInChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0);

    const recordColor = Color(0xFFFF4444);
    const countInColor = Color(0xFFFFA600);

    String tooltip = widget.isRecording
        ? 'Stop Recording (R)'
        : (widget.isCountingIn ? 'Counting In...' : 'Record (R)');

    if (!widget.isRecording && !widget.isCountingIn) {
      final countInText = widget.countInBars == 0
          ? 'Off'
          : widget.countInBars == 1
              ? '1 Bar'
              : widget.countInBars == 2
                  ? '2 Bars'
                  : '4 Bars';
      tooltip += ' | Right-click: Count-in ($countInText)';
    }

    final visualState = widget.isRecording
        ? _RecordButtonVisualState.recording
        : widget.isCountingIn
            ? _RecordButtonVisualState.countingIn
            : (isEnabled
                ? _RecordButtonVisualState.idle
                : _RecordButtonVisualState.disabled);

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onPressed?.call();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          onSecondaryTapDown: (details) {
            _showCountInMenu(context, details.globalPosition);
          },
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: Listenable.merge([_flashController, _pulseController]),
              builder: (context, child) {
                return CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _RecordButtonPainter(
                    state: visualState,
                    ringProgress: widget.countInProgress,
                    beatNumber: widget.countInBeat,
                    flashValue: _flashController.value,
                    pulseValue: _pulseController.value,
                    isHovered: _isHovered,
                    recordColor: recordColor,
                    countInColor: countInColor,
                    disabledColor: context.colors.elevated,
                    textMutedColor: context.colors.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// CustomPainter for the record button.
///
/// Draws different visuals based on state:
/// - Idle: red border + dim red fill + red dot
/// - Disabled: grey border + grey fill + grey dot
/// - CountingIn: orange depleting ring (CW from 12 o'clock) + beat number
/// - Recording: red fill + pulsing glow + white dot + optional flash overlay
class _RecordButtonPainter extends CustomPainter {
  final _RecordButtonVisualState state;
  final double ringProgress; // 0.0 (start) to 1.0 (end of count-in)
  final int beatNumber; // 1-indexed beat within bar
  final double flashValue; // 0.0 to 1.0 (flash animation)
  final double pulseValue; // 0.0 to 1.0 (pulse animation, 2-second cycle)
  final bool isHovered;
  final Color recordColor;
  final Color countInColor;
  final Color disabledColor;
  final Color textMutedColor;

  _RecordButtonPainter({
    required this.state,
    required this.ringProgress,
    required this.beatNumber,
    required this.flashValue,
    required this.pulseValue,
    required this.isHovered,
    required this.recordColor,
    required this.countInColor,
    required this.disabledColor,
    required this.textMutedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const borderWidth = 2.0;

    switch (state) {
      case _RecordButtonVisualState.idle:
        _drawIdle(canvas, center, radius, borderWidth);
        break;
      case _RecordButtonVisualState.disabled:
        _drawDisabled(canvas, center, radius, borderWidth);
        break;
      case _RecordButtonVisualState.countingIn:
        _drawCountingIn(canvas, center, radius, borderWidth, size);
        break;
      case _RecordButtonVisualState.recording:
        _drawRecording(canvas, center, radius, borderWidth);
        break;
    }
  }

  void _drawIdle(Canvas canvas, Offset center, double radius, double bw) {
    // Fill
    final fillPaint = Paint()
      ..color = recordColor.withValues(alpha: isHovered ? 0.3 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - bw, fillPaint);

    // Border
    final borderPaint = Paint()
      ..color = recordColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw;
    canvas.drawCircle(center, radius - bw / 2, borderPaint);

    // Glow on hover
    if (isHovered) {
      final glowPaint = Paint()
        ..color = recordColor.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, radius, glowPaint);
    }

    // Red dot in center
    final dotPaint = Paint()
      ..color = recordColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.22, dotPaint);
  }

  void _drawDisabled(Canvas canvas, Offset center, double radius, double bw) {
    // Fill
    final fillPaint = Paint()
      ..color = disabledColor.withValues(alpha: isHovered ? 1.0 : 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - bw, fillPaint);

    // Border
    final borderPaint = Paint()
      ..color = disabledColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw;
    canvas.drawCircle(center, radius - bw / 2, borderPaint);

    // Grey dot
    final dotPaint = Paint()
      ..color = textMutedColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.22, dotPaint);
  }

  void _drawCountingIn(
      Canvas canvas, Offset center, double radius, double bw, Size size) {
    // Dim orange fill
    final fillPaint = Paint()
      ..color = countInColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - bw, fillPaint);

    // Depleting ring arc (clockwise from 12 o'clock)
    final remaining = (1.0 - ringProgress).clamp(0.0, 1.0);
    if (remaining > 0.001) {
      final arcPaint = Paint()
        ..color = countInColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw + 1.5
        ..strokeCap = StrokeCap.round;

      const startAngle = -pi / 2; // 12 o'clock
      final sweepAngle = remaining * 2 * pi;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - bw / 2),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }

    // Beat number text in center
    if (beatNumber > 0) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$beatNumber',
          style: TextStyle(
            color: countInColor,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawRecording(Canvas canvas, Offset center, double radius, double bw) {
    // Pulsing glow: 0.8 to 1.0 opacity (2-second cycle)
    final glowAlpha = 0.8 + (0.2 * sin(pulseValue * 2 * pi));
    final glowPaint = Paint()
      ..color = recordColor.withValues(alpha: glowAlpha * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius + 2, glowPaint);

    // Solid red fill with subtle pulse
    final fillAlpha = 0.8 + (0.15 * sin(pulseValue * 2 * pi));
    final fillPaint = Paint()
      ..color = recordColor.withValues(alpha: isHovered ? 0.95 : fillAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // Border
    final borderPaint = Paint()
      ..color = recordColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw;
    canvas.drawCircle(center, radius - bw / 2, borderPaint);

    // White dot in center
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.2, dotPaint);

    // Flash overlay (on transition from count-in)
    if (flashValue > 0) {
      final flashPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6 * (1.0 - flashValue))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, flashPaint);
    }
  }

  @override
  bool shouldRepaint(_RecordButtonPainter oldDelegate) {
    return state != oldDelegate.state ||
        ringProgress != oldDelegate.ringProgress ||
        beatNumber != oldDelegate.beatNumber ||
        flashValue != oldDelegate.flashValue ||
        pulseValue != oldDelegate.pulseValue ||
        isHovered != oldDelegate.isHovered;
  }
}
