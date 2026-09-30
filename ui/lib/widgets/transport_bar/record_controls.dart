import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../shared/boojy_tooltip.dart';

/// Record button states for the CustomPainter
enum _RecordButtonVisualState { idle, disabled, countingIn, recording }

/// Record button with the count-in ring timer.
///
/// During count-in: depleting orange ring + beat number inside.
/// During recording: solid red fill + white dot. No animation.
class RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isCountingIn;
  final int countInBeat; // 1-indexed beat number from engine
  final double countInProgress; // 0.0-1.0 from engine
  final int beatsPerBar; // time signature numerator
  final VoidCallback? onPressed;
  final double size;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isCountingIn,
    this.countInBeat = 0,
    this.countInProgress = 0.0,
    this.beatsPerBar = 4,
    required this.onPressed,
    this.size = 40,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final scale = _isPressed
        ? AnimationConstants.pressScale
        : (_isHovered ? AnimationConstants.hoverScale : 1.0);

    final recordColor = context.colors.recordActive;
    final countInColor = context.colors.countInActive;

    final String tipTitle;
    String? tipDescription;
    String? tipShortcut;
    if (widget.isRecording) {
      tipTitle = 'Stop Recording';
      tipShortcut = 'R';
    } else if (widget.isCountingIn) {
      tipTitle = 'Counting In…';
    } else {
      tipTitle = 'Record';
      tipDescription = 'Record onto the armed track';
      tipShortcut = 'R';
    }

    final visualState = widget.isRecording
        ? _RecordButtonVisualState.recording
        : widget.isCountingIn
        ? _RecordButtonVisualState.countingIn
        : (isEnabled
              ? _RecordButtonVisualState.idle
              : _RecordButtonVisualState.disabled);

    return BoojyTooltip(
      title: tipTitle,
      description: tipDescription,
      shortcut: tipShortcut,
      child: MouseRegion(
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onPressed?.call();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.hoverDuration,
            curve: AnimationConstants.standardCurve,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RecordButtonPainter(
                state: visualState,
                ringProgress: widget.countInProgress,
                beatNumber: widget.countInBeat,
                isHovered: _isHovered,
                recordColor: recordColor,
                countInColor: countInColor,
                disabledColor: context.colors.elevated,
                textMutedColor: context.colors.textMuted,
              ),
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
/// - Recording: solid red fill + white dot
class _RecordButtonPainter extends CustomPainter {
  final _RecordButtonVisualState state;
  final double ringProgress; // 0.0 (start) to 1.0 (end of count-in)
  final int beatNumber; // 1-indexed beat within bar
  final bool isHovered;
  final Color recordColor;
  final Color countInColor;
  final Color disabledColor;
  final Color textMutedColor;

  _RecordButtonPainter({
    required this.state,
    required this.ringProgress,
    required this.beatNumber,
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
        _drawCountingIn(canvas, center, radius, borderWidth);
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

    // Red dot in center
    final dotPaint = Paint()
      ..color = recordColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.30, dotPaint);
  }

  void _drawDisabled(Canvas canvas, Offset center, double radius, double bw) {
    // Subtle red fill (muted, not grey)
    final fillPaint = Paint()
      ..color = recordColor.withValues(alpha: isHovered ? 0.25 : 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - bw, fillPaint);

    // Dim red border
    final borderPaint = Paint()
      ..color = recordColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw;
    canvas.drawCircle(center, radius - bw / 2, borderPaint);

    // Dim red dot
    final dotPaint = Paint()
      ..color = recordColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.30, dotPaint);
  }

  void _drawCountingIn(Canvas canvas, Offset center, double radius, double bw) {
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
            fontWeight: BT.weightSemiBold,
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
    // Solid red fill
    final fillPaint = Paint()
      ..color = recordColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // White dot in center
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.28, dotPaint);
  }

  @override
  bool shouldRepaint(_RecordButtonPainter oldDelegate) {
    return state != oldDelegate.state ||
        ringProgress != oldDelegate.ringProgress ||
        beatNumber != oldDelegate.beatNumber ||
        isHovered != oldDelegate.isHovered;
  }
}
