import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Degrees of total sweep (from start to end).
const double _kSweepDeg = 270.0;

/// Start angle in degrees (bottom-left, clockwise sweep).
const double _kStartDeg = 135.0;

/// Full-range drag travel in pixels (drag this far = min→max).
const double _kDragRange = 120.0;

/// Arc knob for effect parameters.
///
/// Draws a 270° arc track with an accent fill up to [value]. Responds to
/// vertical drag (up = increase). Label and value are rendered below.
class ArcKnob extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;

  /// Display suffix. Use '%' for wet_dry (0–1 mapped to 0–100%).
  /// Empty string for dimensionless 0–1 params.
  final String unit;

  final bool enabled;
  final double size;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const ArcKnob({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.unit = '',
    this.enabled = true,
    this.size = 32,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<ArcKnob> createState() => _ArcKnobState();
}

class _ArcKnobState extends State<ArcKnob> {
  double? _dragStartValue;
  double? _dragStartY;

  double get _normalized =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  String get _displayValue {
    if (widget.unit == '%') {
      return '${(widget.value * 100).round()}%';
    }
    final s = widget.max >= 100
        ? widget.value.round().toString()
        : widget.value.toStringAsFixed(1);
    return '$s${widget.unit}';
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartValue = widget.value;
    _dragStartY = details.globalPosition.dy;
    widget.onChangeStart?.call(widget.value);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dragStartValue == null || _dragStartY == null) return;
    final dy = _dragStartY! - details.globalPosition.dy; // up = positive
    final delta = dy / _kDragRange * (widget.max - widget.min);
    final next = (_dragStartValue! + delta).clamp(widget.min, widget.max);
    widget.onChanged?.call(next);
  }

  void _onDragEnd(DragEndDetails _) {
    widget.onChangeEnd?.call(widget.value);
    _dragStartValue = null;
    _dragStartY = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onVerticalDragStart: widget.enabled ? _onDragStart : null,
            onVerticalDragUpdate: widget.enabled ? _onDragUpdate : null,
            onVerticalDragEnd: widget.enabled ? _onDragEnd : null,
            child: MouseRegion(
              cursor: widget.enabled
                  ? SystemMouseCursors.resizeUpDown
                  : SystemMouseCursors.basic,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _ArcKnobPainter(
                    normalized: _normalized,
                    trackColor: colors.surface,
                    fillColor: colors.accent,
                    dotColor: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9,
              fontWeight: BT.weightMedium,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            _displayValue,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ArcKnobPainter extends CustomPainter {
  final double normalized;
  final Color trackColor;
  final Color fillColor;
  final Color dotColor;

  const _ArcKnobPainter({
    required this.normalized,
    required this.trackColor,
    required this.fillColor,
    required this.dotColor,
  });

  static const double _startRad = _kStartDeg * pi / 180;
  static const double _sweepRad = _kSweepDeg * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startRad,
      _sweepRad,
      false,
      trackPaint,
    );

    if (normalized > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startRad,
        _sweepRad * normalized,
        false,
        fillPaint,
      );
    }

    final dotAngle = _startRad + _sweepRad * normalized;
    final dotCenter = Offset(
      center.dx + radius * cos(dotAngle),
      center.dy + radius * sin(dotAngle),
    );
    canvas.drawCircle(dotCenter, 2.5, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_ArcKnobPainter old) =>
      old.normalized != normalized ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor ||
      old.dotColor != dotColor;
}
