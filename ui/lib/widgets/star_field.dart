import 'dart:math';
import 'package:flutter/material.dart';

/// Animated star field background — the visual signature of the Boojy suite.
///
/// Renders small white dots at random positions with varying opacity,
/// each pulsing at its own speed. Designed to sit behind content areas
/// (timeline, editor) on the deep editor background (#040412).
class StarField extends StatefulWidget {
  final int starCount;

  const StarField({super.key, this.starCount = 70});

  @override
  State<StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<StarField>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<_Star>? _stars;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _generateStars(Size size) {
    if (size == _lastSize && _stars != null) return;
    _lastSize = size;
    final random = Random(size.width.toInt() ^ size.height.toInt());
    _stars = List.generate(widget.starCount, (_) {
      return _Star(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: 0.3 + random.nextDouble() * 1.2,
        baseOpacity: 0.15 + random.nextDouble() * 0.55,
        pulseSpeed: 0.3 + random.nextDouble() * 1.5,
        pulseOffset: random.nextDouble() * 2 * pi,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _StarFieldPainter(
              stars: _stars ?? [],
              time: _controller.value * 10,
              generateStars: _generateStars,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double radius;
  final double baseOpacity;
  final double pulseSpeed;
  final double pulseOffset;

  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.baseOpacity,
    required this.pulseSpeed,
    required this.pulseOffset,
  });
}

class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final double time;
  final void Function(Size) generateStars;

  _StarFieldPainter({
    required this.stars,
    required this.time,
    required this.generateStars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    generateStars(size);

    final paint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      // Gentle pulse: opacity oscillates around baseOpacity
      final pulse = sin(time * star.pulseSpeed + star.pulseOffset);
      final opacity = (star.baseOpacity + pulse * 0.15).clamp(0.05, 0.8);

      paint.color = Color.fromRGBO(255, 255, 255, opacity);

      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter oldDelegate) {
    return oldDelegate.time != time;
  }
}
