import 'package:flutter/material.dart';
import '../theme/theme_extension.dart';

/// Waveform display widget for the library preview bar.
/// Shows peaks with playhead position indicated by color change.
class LibraryPreviewWaveform extends StatelessWidget {
  final List<double> peaks;
  final double position;
  final double duration;
  final bool isAuditionEnabled;
  final ValueChanged<double>? onSeek;

  const LibraryPreviewWaveform({
    super.key,
    required this.peaks,
    required this.position,
    required this.duration,
    required this.isAuditionEnabled,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: onSeek != null ? (details) => _handleSeek(details, constraints.maxWidth) : null,
          onHorizontalDragUpdate: onSeek != null ? (details) => _handleDrag(details, constraints.maxWidth) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _WaveformPainter(
                peaks: peaks,
                position: position,
                duration: duration,
                isAuditionEnabled: isAuditionEnabled,
                playedColor: context.colors.accent,
                unplayedColor: context.colors.accent.withValues(alpha: 0.4),
                disabledColor: context.colors.accent.withValues(alpha: 0.15),
                backgroundColor: context.colors.dark,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleSeek(TapDownDetails details, double width) {
    if (duration <= 0 || onSeek == null) return;
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    onSeek!(fraction * duration);
  }

  void _handleDrag(DragUpdateDetails details, double width) {
    if (duration <= 0 || onSeek == null) return;
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    onSeek!(fraction * duration);
  }
}

/// Custom painter for drawing the waveform
class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double position;
  final double duration;
  final bool isAuditionEnabled;
  final Color playedColor;
  final Color unplayedColor;
  final Color disabledColor;
  final Color backgroundColor;

  _WaveformPainter({
    required this.peaks,
    required this.position,
    required this.duration,
    required this.isAuditionEnabled,
    required this.playedColor,
    required this.unplayedColor,
    required this.disabledColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    if (peaks.isEmpty || duration <= 0) return;

    // Calculate playhead position as fraction
    final playheadFraction = (position / duration).clamp(0.0, 1.0);

    // Draw waveform bars
    final barCount = peaks.length;
    final barWidth = size.width / barCount;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.8;

    for (int i = 0; i < barCount; i++) {
      final peak = peaks[i].clamp(0.0, 1.0);
      final barHeight = peak * maxBarHeight;
      final x = i * barWidth;
      final fraction = i / barCount;

      // Determine color based on position and audition state
      Color barColor;
      if (!isAuditionEnabled) {
        barColor = disabledColor;
      } else if (fraction <= playheadFraction) {
        barColor = playedColor;
      } else {
        barColor = unplayedColor;
      }

      final paint = Paint()
        ..color = barColor
        ..style = PaintingStyle.fill;

      // Draw centered bar
      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth * 0.7,
          height: barHeight.clamp(2.0, maxBarHeight),
        ),
        const Radius.circular(1),
      );
      canvas.drawRRect(barRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.position != position ||
        oldDelegate.duration != duration ||
        oldDelegate.isAuditionEnabled != isAuditionEnabled ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor ||
        oldDelegate.disabledColor != disabledColor;
  }
}
