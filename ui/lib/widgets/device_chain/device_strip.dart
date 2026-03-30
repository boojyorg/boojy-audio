import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';

/// 24px-wide right strip on every device box in the chain.
///
/// Contains (top to bottom):
/// - On/off dot (every device)
/// - Float icon (third-party plugins only)
/// - Vertical capsule fader — exact rotation of CapsuleFader from track mixer
class DeviceStrip extends StatefulWidget {
  final bool isEnabled;
  final bool isFloated;
  final bool showFloat;
  final bool showVolumeThumb; // true for instruments only
  final double leftLevel; // 0.0-1.0 normalized
  final double rightLevel; // 0.0-1.0 normalized
  final double volumeDb; // -60 to +6 dB
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onFloat;
  final VoidCallback? onEmbed;
  final ValueChanged<double>? onVolumeChanged; // dB value

  const DeviceStrip({
    super.key,
    required this.isEnabled,
    this.isFloated = false,
    this.showFloat = false,
    this.showVolumeThumb = false,
    this.leftLevel = 0.0,
    this.rightLevel = 0.0,
    this.volumeDb = 0.0,
    this.onToggleEnabled,
    this.onFloat,
    this.onEmbed,
    this.onVolumeChanged,
  });

  @override
  State<DeviceStrip> createState() => _DeviceStripState();
}

class _DeviceStripState extends State<DeviceStrip> {
  bool _isDragging = false;

  // Boojy volume curve — identical to CapsuleFader
  static const List<double> _sliderPoints = [
    0.01,
    0.05,
    0.10,
    0.30,
    0.50,
    0.70,
    0.85,
    1.00,
  ];
  static const List<double> _dbPoints = [
    -60.0,
    -52.0,
    -45.0,
    -24.0,
    -10.0,
    0.0,
    3.0,
    6.0,
  ];

  double _volumeDbToSlider(double db) {
    if (db <= -60.0) return 0.0;
    if (db >= 6.0) return 1.0;
    for (int i = 0; i < _dbPoints.length - 1; i++) {
      if (db <= _dbPoints[i + 1]) {
        final t = (db - _dbPoints[i]) / (_dbPoints[i + 1] - _dbPoints[i]);
        return _sliderPoints[i] + t * (_sliderPoints[i + 1] - _sliderPoints[i]);
      }
    }
    return 0.7;
  }

  double _sliderToVolumeDb(double slider) {
    if (slider <= 0.0) return -60.0;
    if (slider <= 0.01) return -60.0;
    if (slider >= 1.0) return 6.0;
    for (int i = 0; i < _sliderPoints.length - 1; i++) {
      if (slider <= _sliderPoints[i + 1]) {
        final t =
            (slider - _sliderPoints[i]) /
            (_sliderPoints[i + 1] - _sliderPoints[i]);
        return _dbPoints[i] + t * (_dbPoints[i + 1] - _dbPoints[i]);
      }
    }
    return 6.0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 22,
      decoration: BoxDecoration(
        color: colors.dark,
        border: Border(left: BorderSide(color: colors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            _buildOnOffDot(colors),
            if (widget.showFloat) ...[
              const SizedBox(height: 8),
              _buildFloatIcon(colors),
            ],
            const SizedBox(height: 4),
            Expanded(child: _buildCapsuleMeter()),
          ],
        ),
      ),
    );
  }

  Widget _buildOnOffDot(BoojyColors colors) {
    return Tooltip(
      message: widget.isEnabled ? 'Disable' : 'Enable',
      child: GestureDetector(
        onTap: widget.onToggleEnabled,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isEnabled ? colors.accent : Colors.transparent,
              border: Border.all(
                color: widget.isEnabled ? colors.accent : colors.textMuted,
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatIcon(BoojyColors colors) {
    final icon = widget.isFloated ? BI.arrowDown : BI.openInNew;
    final color = widget.isFloated ? colors.accent : colors.textMuted;

    return Tooltip(
      message: widget.isFloated ? 'Embed in panel' : 'Float to window',
      child: GestureDetector(
        onTap: widget.isFloated ? widget.onEmbed : widget.onFloat,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }

  /// Vertical capsule fader — exact copy of CapsuleFader logic, rotated 90°.
  Widget _buildCapsuleMeter() {
    final accentColor = context.colors.accent;
    final sliderValue = _volumeDbToSlider(widget.volumeDb);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _VerticalCapsulePainter(
            leftLevel: widget.leftLevel,
            rightLevel: widget.rightLevel,
            volumeSliderValue: widget.showVolumeThumb ? sliderValue : -1,
            isDragging: _isDragging,
            accentColor: accentColor,
          ),
        );

        if (!widget.showVolumeThumb || widget.onVolumeChanged == null) {
          return painter;
        }

        // Volume drag — same as CapsuleFader but vertical
        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragUpdate: (details) {
            // Invert Y: dragging up = higher volume
            final normalized =
                1.0 - (details.localPosition.dy / constraints.maxHeight);
            final db = _sliderToVolumeDb(normalized.clamp(0.0, 1.0));
            widget.onVolumeChanged!(db);
          },
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragCancel: () => setState(() => _isDragging = false),
          onTapDown: (details) {
            final normalized =
                1.0 - (details.localPosition.dy / constraints.maxHeight);
            final db = _sliderToVolumeDb(normalized.clamp(0.0, 1.0));
            widget.onVolumeChanged!(db);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: painter,
          ),
        );
      },
    );
  }
}

/// Vertical capsule fader painter — exact rotation of _CapsuleFaderPainter.
///
/// Every value copied from capsule_fader.dart:
///   capsule bg: 0xFF1A1A1A, border: 0xFF3A3A3A @ 1.5px
///   capsule radius: width/2 (perfect pill)
///   meter padding: 4px
///   gradient: green→green→yellow→orange→red→brightred at stops [0,0.7,0.8,0.9,0.95,1.0]
///   handle: grey 0xFF808080 @ 0.6, border 0xFFAAAAAA @ 0.4
class _VerticalCapsulePainter extends CustomPainter {
  final double leftLevel;
  final double rightLevel;
  final double volumeSliderValue; // 0-1, or <0 to hide handle
  final bool isDragging;
  final Color accentColor;

  _VerticalCapsulePainter({
    required this.leftLevel,
    required this.rightLevel,
    required this.volumeSliderValue,
    required this.isDragging,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Capsule: radius = width/2 (same as horizontal uses height/2)
    final capsuleRadius = size.width / 2;
    final capsuleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(capsuleRadius),
    );

    // Draw capsule background — same color as CapsuleFader
    canvas.drawRRect(capsuleRect, Paint()..color = const Color(0xFF1A1A1A));

    // Draw capsule border — same as CapsuleFader
    canvas.drawRRect(
      capsuleRect,
      Paint()
        ..color = const Color(0xFF3A3A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Clip to capsule
    canvas.save();
    canvas.clipRRect(capsuleRect);

    // Calculate meter dimensions — rotated version of CapsuleFader
    // Horizontal: meterLeft = capsuleRadius + padding
    // Vertical:   meterTop = capsuleRadius + padding
    const meterPadding = 4.0;
    final meterTop = capsuleRadius + meterPadding;
    final meterBottom = size.height - capsuleRadius - meterPadding;
    final meterHeight = meterBottom - meterTop;
    final meterWidth = (size.width - 3 * meterPadding) / 2;

    // Left channel (left column) — mirrors horizontal's top row
    _drawMeterColumn(
      canvas,
      Offset(meterPadding, meterTop),
      meterWidth,
      meterHeight,
      leftLevel,
    );

    // Right channel (right column) — mirrors horizontal's bottom row
    _drawMeterColumn(
      canvas,
      Offset(meterPadding * 2 + meterWidth, meterTop),
      meterWidth,
      meterHeight,
      rightLevel,
    );

    canvas.restore();

    // Draw volume handle (instruments only)
    if (volumeSliderValue >= 0) {
      _drawVolumeHandle(canvas, size);
    }
  }

  /// Draw one meter column — exact rotation of CapsuleFader._drawMeterRow
  void _drawMeterColumn(
    Canvas canvas,
    Offset offset,
    double width,
    double height,
    double level,
  ) {
    // Background track (dark) — same as CapsuleFader
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx, offset.dy, width, height),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Level bar with gradient — fills from bottom
    if (level > 0.01) {
      final levelHeight = height * level;
      final levelTop = offset.dy + height - levelHeight;

      // Same gradient as CapsuleFader but vertical (bottom=green, top=red)
      final levelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx, levelTop, width, levelHeight),
        const Radius.circular(2),
      );

      final levelPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xFF22c55e), // Green (low levels)
            Color(0xFF22c55e), // Green continues
            Color(0xFFeab308), // Yellow/Amber
            Color(0xFFf97316), // Orange
            Color(0xFFef4444), // Red
            Color(0xFFdc2626), // Bright red (clipping)
          ],
          stops: [0.0, 0.7, 0.8, 0.9, 0.95, 1.0],
        ).createShader(Rect.fromLTWH(offset.dx, offset.dy, width, height));

      canvas.drawRRect(levelRect, levelPaint);
    }
  }

  /// Draw volume handle — exact rotation of CapsuleFader._drawVolumeHandle
  void _drawVolumeHandle(Canvas canvas, Size size) {
    // Horizontal: handleRadius = height/2, handleX = radius + value * usable
    // Vertical:   handleRadius = width/2, handleY inverted
    final handleRadius = size.width / 2;
    final usableHeight = size.height - handleRadius * 2;
    // Invert: 0 = bottom, 1 = top
    final handleY =
        size.height - handleRadius - volumeSliderValue * usableHeight;
    final handleX = size.width / 2;
    final center = Offset(handleX, handleY);

    // Glow when dragging — same as CapsuleFader
    if (isDragging) {
      canvas.drawCircle(
        center,
        handleRadius + 2,
        Paint()
          ..color = accentColor.withValues(
            alpha: AnimationConstants.glowOpacity,
          )
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            AnimationConstants.glowBlurRadius,
          ),
      );
    }

    // Grey circle handle — same as CapsuleFader
    canvas.drawCircle(
      center,
      handleRadius - 1,
      Paint()..color = const Color(0xFF808080).withValues(alpha: 0.6),
    );

    // Border — same as CapsuleFader
    canvas.drawCircle(
      center,
      handleRadius - 1,
      Paint()
        ..color = const Color(0xFFAAAAAA).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_VerticalCapsulePainter oldDelegate) {
    return oldDelegate.leftLevel != leftLevel ||
        oldDelegate.rightLevel != rightLevel ||
        oldDelegate.volumeSliderValue != volumeSliderValue ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.accentColor != accentColor;
  }
}
