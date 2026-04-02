import 'dart:math';
import 'package:flutter/material.dart';

/// Animated star field background — the visual signature of the Boojy suite.
///
/// Renders small white dots at random positions with tiered brightness:
/// - Background stars (60%): dim, small
/// - Mid stars (30%): medium brightness and size
/// - Bright stars (10%): large, some with accent color, gentle twinkle
///
/// Designed to sit behind content areas (timeline, editor) on the deep
/// editor background (#040412).
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
    _stars = List.generate(widget.starCount, (i) {
      // Tier assignment: 60% background, 30% mid, 10% bright
      final roll = random.nextDouble();
      final _StarTier tier;
      if (roll < 0.6) {
        tier = _StarTier.background;
      } else if (roll < 0.9) {
        tier = _StarTier.mid;
      } else {
        tier = _StarTier.bright;
      }

      // Accent color for ~2-3 bright stars
      final isAccent = tier == _StarTier.bright && random.nextDouble() < 0.4;

      return _Star(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: tier.radius(random),
        baseOpacity: tier.opacity(random),
        pulseSpeed: tier.pulseSpeed(random),
        pulseOffset: random.nextDouble() * 2 * pi,
        pulseAmplitude: tier == _StarTier.bright ? 0.15 : 0.08,
        isAccent: isAccent,
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

enum _StarTier { background, mid, bright }

extension on _StarTier {
  double radius(Random r) {
    switch (this) {
      case _StarTier.background:
        return 0.4 + r.nextDouble() * 0.6; // 0.4–1.0
      case _StarTier.mid:
        return 0.8 + r.nextDouble() * 0.7; // 0.8–1.5
      case _StarTier.bright:
        return 1.2 + r.nextDouble() * 0.8; // 1.2–2.0
    }
  }

  double opacity(Random r) {
    switch (this) {
      case _StarTier.background:
        return 0.15 + r.nextDouble() * 0.10; // 0.15–0.25
      case _StarTier.mid:
        return 0.35 + r.nextDouble() * 0.15; // 0.35–0.50
      case _StarTier.bright:
        return 0.60 + r.nextDouble() * 0.20; // 0.60–0.80
    }
  }

  double pulseSpeed(Random r) {
    switch (this) {
      case _StarTier.background:
        return 0.2 + r.nextDouble() * 0.3; // slow, subtle
      case _StarTier.mid:
        return 0.3 + r.nextDouble() * 0.5;
      case _StarTier.bright:
        return 0.5 + r.nextDouble() * 0.8; // 2-4s cycle visible twinkle
    }
  }
}

class _Star {
  final double x;
  final double y;
  final double radius;
  final double baseOpacity;
  final double pulseSpeed;
  final double pulseOffset;
  final double pulseAmplitude;
  final bool isAccent;

  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.baseOpacity,
    required this.pulseSpeed,
    required this.pulseOffset,
    required this.pulseAmplitude,
    required this.isAccent,
  });
}

class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final double time;
  final void Function(Size) generateStars;

  // Accent color matching the app theme
  static const _accentColor = Color(0xFF40B3E8);

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
      final opacity = (star.baseOpacity + pulse * star.pulseAmplitude).clamp(
        0.05,
        0.9,
      );

      if (star.isAccent) {
        paint.color = _accentColor.withValues(alpha: opacity * 0.5);
      } else {
        paint.color = Color.fromRGBO(232, 234, 240, opacity);
      }

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
