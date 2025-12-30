import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// A compact 24px knob widget for toolbar use.
/// Drag vertically to change value, double-tap to reset.
///
/// Used for Stretch, Humanize, and Randomize controls in Piano Roll toolbar.
class MiniKnob extends StatefulWidget {
  /// Current value (0.0 to 1.0)
  final double value;

  /// Minimum value
  final double min;

  /// Maximum value
  final double max;

  /// Called when value changes during drag
  final Function(double)? onChanged;

  /// Called when drag ends (for committing changes)
  final VoidCallback? onChangeEnd;

  /// Size of the knob (default 24px)
  final double size;

  /// Label shown below the knob
  final String? label;

  /// Format the value for display inside the knob
  final String Function(double)? valueFormatter;

  /// Color of the arc when active
  final Color? arcColor;

  const MiniKnob({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.onChanged,
    this.onChangeEnd,
    this.size = 24,
    this.label,
    this.valueFormatter,
    this.arcColor,
  });

  @override
  State<MiniKnob> createState() => _MiniKnobState();
}

class _MiniKnobState extends State<MiniKnob> {
  bool _isDragging = false;

  double get _normalizedValue =>
      ((widget.value - widget.min) / (widget.max - widget.min))
          .clamp(0.0, 1.0);

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onChanged == null) return;

    // Drag up = increase, drag down = decrease
    // Sensitivity: 150px drag = full range
    final delta = -details.delta.dy / 150.0;
    final range = widget.max - widget.min;
    final newValue = (widget.value + delta * range).clamp(widget.min, widget.max);
    widget.onChanged!(newValue);
  }

  void _handleDoubleTap() {
    // Reset to center/default value on double-tap
    final defaultValue = (widget.min + widget.max) / 2;
    widget.onChanged?.call(defaultValue);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: GestureDetector(
            onVerticalDragStart: (_) {
              setState(() => _isDragging = true);
            },
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: (_) {
              setState(() => _isDragging = false);
              widget.onChangeEnd?.call();
            },
            onDoubleTap: _handleDoubleTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _MiniKnobPainter(
                  value: _normalizedValue,
                  isDragging: _isDragging,
                  arcColor: widget.arcColor ?? context.colors.accent,
                  baseColor: context.colors.textMuted,
                  valueFormatter: widget.valueFormatter,
                  rawValue: widget.value,
                ),
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.label!,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniKnobPainter extends CustomPainter {
  final double value; // 0.0 to 1.0 (normalized)
  final bool isDragging;
  final Color arcColor;
  final Color baseColor;
  final String Function(double)? valueFormatter;
  final double rawValue;

  _MiniKnobPainter({
    required this.value,
    required this.isDragging,
    required this.arcColor,
    required this.baseColor,
    this.valueFormatter,
    required this.rawValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Stroke width scales with size - fatter arc
    final strokeWidth = (size.width * 0.1).clamp(3.0, 5.0);
    // Smaller radius to make room for bigger text
    final radius = size.width / 2 - strokeWidth / 2 - 2;

    // Arc angles: 7 o'clock to 5 o'clock (270° sweep)
    const startAngle = 135 * math.pi / 180; // 7 o'clock
    const sweepAngle = 270 * math.pi / 180; // 270° sweep

    // 1. Draw base arc (grey ring)
    final baseArcPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      baseArcPaint,
    );

    // 2. Draw value arc (colored portion)
    if (value > 0.01) {
      final valueArcPaint = Paint()
        ..color = isDragging ? arcColor : arcColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final valueSweep = sweepAngle * value;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        valueSweep,
        false,
        valueArcPaint,
      );
    }

    // 3. Draw indicator dot at current position
    final indicatorAngle = startAngle + sweepAngle * value;
    final indicatorOffset = Offset(
      center.dx + radius * math.cos(indicatorAngle),
      center.dy + radius * math.sin(indicatorAngle),
    );

    final dotPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.fill;

    final dotRadius = (strokeWidth * 0.7).clamp(2.0, 4.0);
    canvas.drawCircle(indicatorOffset, dotRadius, dotPaint);

    // 4. Draw value text if formatter provided and size is large enough
    if (valueFormatter != null && size.width >= 24) {
      final label = valueFormatter!(rawValue);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: const Color(0xFFE0E0E0),
            fontSize: size.width * 0.28, // Bigger text
            fontWeight: FontWeight.w500,
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

  @override
  bool shouldRepaint(_MiniKnobPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.arcColor != arcColor;
  }
}

/// A knob with an apply button next to it.
/// Used for Stretch and Humanize controls that need explicit apply action.
class KnobWithApply extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final Function(double)? onChanged;
  final VoidCallback? onApply;
  final String label;
  final String Function(double)? valueFormatter;
  final Color? arcColor;

  const KnobWithApply({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.onChanged,
    this.onApply,
    required this.label,
    this.valueFormatter,
    this.arcColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Knob
        MiniKnob(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          size: 24,
          valueFormatter: valueFormatter,
          arcColor: arcColor,
        ),
        const SizedBox(width: 4),
        // Apply button (clickable label)
        GestureDetector(
          onTap: onApply,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colors.dark,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
