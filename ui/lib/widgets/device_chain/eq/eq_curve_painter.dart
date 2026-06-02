import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/tokens.dart';

/// EQ band shape codes — mirror the engine's `BandShape` encoding.
class EqShape {
  static const int lowShelf = 0;
  static const int bell = 1;
  static const int highShelf = 2;
}

/// Fixed EQ constants — mirror `engine/src/effects.rs`.
const double kEqFreqMin = 20.0;
const double kEqFreqMax = 20000.0;
const double kEqGainRange = 12.0; // ±12 dB visible scale
const double kEqLowCutFreq = 80.0;
const double kEqHighCutFreq = 12000.0;
const double kEqShelfQ = 0.707;

/// One band as the UI sees it (parsed from the effect's flat param map).
class EqBandView {
  final int index;
  final double freq;
  final double gainDb;
  final double focus; // 0..1
  final int shape; // EqShape.*
  final bool on;

  const EqBandView({
    required this.index,
    required this.freq,
    required this.gainDb,
    required this.focus,
    required this.shape,
    required this.on,
  });

  bool get isShelf => shape != EqShape.bell;

  /// Q used for the magnitude curve: bells map Focus→Q geometrically
  /// (`0.4 * 15^focus`), shelves use a fixed gentle slope.
  double get q => shape == EqShape.bell
      ? 0.4 * math.pow(15.0, focus.clamp(0.0, 1.0))
      : kEqShelfQ;
}

/// Maps between frequency/gain values and pixel coordinates inside the graph.
/// Shared by the painter and the gesture layer so they never drift.
class EqGeometry {
  final Size size;
  late final Rect plot;

  static const double _leftGutter = 24;
  static const double _topPad = 6;
  static const double _rightPad = 6;
  static const double _bottomPad = 14;

  EqGeometry(this.size) {
    plot = Rect.fromLTRB(
      _leftGutter,
      _topPad,
      size.width - _rightPad,
      size.height - _bottomPad,
    );
  }

  double freqToX(double f) {
    final t = math.log(f / kEqFreqMin) / math.log(kEqFreqMax / kEqFreqMin);
    return plot.left + t.clamp(0.0, 1.0) * plot.width;
  }

  double xToFreq(double x) {
    final t = ((x - plot.left) / plot.width).clamp(0.0, 1.0);
    return kEqFreqMin * math.pow(kEqFreqMax / kEqFreqMin, t).toDouble();
  }

  double gainToY(double g) {
    final t = (g + kEqGainRange) / (2 * kEqGainRange); // 0 at -12, 1 at +12
    return plot.bottom - t.clamp(0.0, 1.0) * plot.height;
  }

  double yToGain(double y) {
    final t = ((plot.bottom - y) / plot.height).clamp(0.0, 1.0);
    return (t * 2 - 1) * kEqGainRange;
  }
}

/// Log-frequency ↔ 0..1 normalization (size-independent), so the Freq knob
/// feels logarithmic like the graph's x-axis.
double eqFreqToNorm(double f) =>
    (math.log(f / kEqFreqMin) / math.log(kEqFreqMax / kEqFreqMin)).clamp(
      0.0,
      1.0,
    );
double eqNormToFreq(double n) =>
    kEqFreqMin *
    math.pow(kEqFreqMax / kEqFreqMin, n.clamp(0.0, 1.0)).toDouble();

/// Biquad magnitude response in dB at [evalFreq], for a filter designed at
/// [sr]. Mirrors the RBJ cookbook coefficients in `engine/src/effects.rs` so
/// the drawn curve matches what the engine actually does.
double eqBiquadMagDb({
  required int filterType, // EqShape.* or 3 = HPF, 4 = LPF
  required double freq,
  required double gainDb,
  required double q,
  required double sr,
  required double evalFreq,
}) {
  final omega = 2 * math.pi * freq / sr;
  final sinw = math.sin(omega);
  final cosw = math.cos(omega);
  final qq = q < 0.01 ? 0.01 : q;
  final alpha = sinw / (2 * qq);
  final a = math.pow(10.0, gainDb / 40.0).toDouble();
  final sqrtA = math.sqrt(a);

  double b0, b1, b2, a0, a1, a2;
  switch (filterType) {
    case EqShape.lowShelf:
      b0 = a * ((a + 1) - (a - 1) * cosw + 2 * sqrtA * alpha);
      b1 = 2 * a * ((a - 1) - (a + 1) * cosw);
      b2 = a * ((a + 1) - (a - 1) * cosw - 2 * sqrtA * alpha);
      a0 = (a + 1) + (a - 1) * cosw + 2 * sqrtA * alpha;
      a1 = -2 * ((a - 1) + (a + 1) * cosw);
      a2 = (a + 1) + (a - 1) * cosw - 2 * sqrtA * alpha;
      break;
    case EqShape.highShelf:
      b0 = a * ((a + 1) + (a - 1) * cosw + 2 * sqrtA * alpha);
      b1 = -2 * a * ((a - 1) + (a + 1) * cosw);
      b2 = a * ((a + 1) + (a - 1) * cosw - 2 * sqrtA * alpha);
      a0 = (a + 1) - (a - 1) * cosw + 2 * sqrtA * alpha;
      a1 = 2 * ((a - 1) - (a + 1) * cosw);
      a2 = (a + 1) - (a - 1) * cosw - 2 * sqrtA * alpha;
      break;
    case 3: // high-pass (Low Cut)
      b0 = (1 + cosw) / 2;
      b1 = -(1 + cosw);
      b2 = (1 + cosw) / 2;
      a0 = 1 + alpha;
      a1 = -2 * cosw;
      a2 = 1 - alpha;
      break;
    case 4: // low-pass (High Cut)
      b0 = (1 - cosw) / 2;
      b1 = 1 - cosw;
      b2 = (1 - cosw) / 2;
      a0 = 1 + alpha;
      a1 = -2 * cosw;
      a2 = 1 - alpha;
      break;
    default: // bell
      b0 = 1 + alpha * a;
      b1 = -2 * cosw;
      b2 = 1 - alpha * a;
      a0 = 1 + alpha / a;
      a1 = -2 * cosw;
      a2 = 1 - alpha / a;
  }
  b0 /= a0;
  b1 /= a0;
  b2 /= a0;
  a1 /= a0;
  a2 /= a0;

  final w = 2 * math.pi * evalFreq / sr;
  final cw = math.cos(w);
  final sw = math.sin(w);
  final c2 = math.cos(2 * w);
  final s2 = math.sin(2 * w);
  final numRe = b0 + b1 * cw + b2 * c2;
  final numIm = -(b1 * sw + b2 * s2);
  final denRe = 1 + a1 * cw + a2 * c2;
  final denIm = -(a1 * sw + a2 * s2);
  final numMag = math.sqrt(numRe * numRe + numIm * numIm);
  final denMag = math.sqrt(denRe * denRe + denIm * denIm);
  if (denMag == 0) return -120.0;
  final mag = numMag / denMag;
  if (mag <= 0) return -120.0;
  return 20 * (math.log(mag) / math.ln10);
}

/// Total EQ response in dB at [evalFreq] = sum of active bands + enabled cuts.
double eqTotalResponseDb(
  List<EqBandView> bands,
  double sr,
  double evalFreq, {
  required bool lowCutOn,
  required bool highCutOn,
}) {
  double total = 0;
  for (final b in bands) {
    if (!b.on) continue;
    total += eqBiquadMagDb(
      filterType: b.shape,
      freq: b.freq,
      gainDb: b.gainDb,
      q: b.q,
      sr: sr,
      evalFreq: evalFreq,
    );
  }
  if (lowCutOn) {
    total += eqBiquadMagDb(
      filterType: 3,
      freq: kEqLowCutFreq,
      gainDb: 0,
      q: kEqShelfQ,
      sr: sr,
      evalFreq: evalFreq,
    );
  }
  if (highCutOn) {
    total += eqBiquadMagDb(
      filterType: 4,
      freq: kEqHighCutFreq,
      gainDb: 0,
      q: kEqShelfQ,
      sr: sr,
      evalFreq: evalFreq,
    );
  }
  return total;
}

/// Draws the EQ frequency-response graph: grid + axis labels, the summed
/// magnitude curve, and a draggable dot per band.
class EqCurvePainter extends CustomPainter {
  final List<EqBandView> bands;
  final int? selectedBand;
  final bool lowCutOn;
  final bool highCutOn;
  final double sampleRate;
  final BoojyColors colors;
  final double textScale;

  EqCurvePainter({
    required this.bands,
    required this.selectedBand,
    required this.lowCutOn,
    required this.highCutOn,
    required this.sampleRate,
    required this.colors,
    required this.textScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geo = EqGeometry(size);
    final plot = geo.plot;
    if (plot.width <= 0 || plot.height <= 0) return;

    // Grid + axis labels
    final gridPaint = Paint()
      ..color = colors.divider
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    // dB lines (+12 / +6 / 0 / -6 / -12)
    for (final db in [12.0, 6.0, 0.0, -6.0, -12.0]) {
      final y = geo.gainToY(db);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        db == 0.0 ? zeroPaint : gridPaint,
      );
      _label(
        canvas,
        db == 0 ? '0' : (db > 0 ? '+${db.toInt()}' : '${db.toInt()}'),
        Offset(2, y - 5 * textScale),
        colors.textMuted,
      );
    }

    // Frequency lines (100 / 1k / 10k)
    for (final entry in const [
      (100.0, '100'),
      (1000.0, '1k'),
      (10000.0, '10k'),
    ]) {
      final x = geo.freqToX(entry.$1);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      _label(
        canvas,
        entry.$2,
        Offset(x + 2, plot.bottom + 1),
        colors.textMuted,
      );
    }

    // Response curve
    final curve = Path();
    var started = false;
    for (double x = plot.left; x <= plot.right; x += 2) {
      final f = geo.xToFreq(x);
      final db = eqTotalResponseDb(
        bands,
        sampleRate,
        f,
        lowCutOn: lowCutOn,
        highCutOn: highCutOn,
      );
      final y = geo.gainToY(db.clamp(-kEqGainRange, kEqGainRange));
      if (!started) {
        curve.moveTo(x, y);
        started = true;
      } else {
        curve.lineTo(x, y);
      }
    }
    // Soft fill under the curve
    final fill = Path.from(curve)
      ..lineTo(plot.right, geo.gainToY(0))
      ..lineTo(plot.left, geo.gainToY(0))
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = colors.accent.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..color = colors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Band dots
    for (final b in bands) {
      final dx = geo.freqToX(b.freq);
      final dy = geo.gainToY(b.gainDb.clamp(-kEqGainRange, kEqGainRange));
      final isSel = b.index == selectedBand;
      final dotColor = b.on ? colors.accent : colors.textMuted;
      if (isSel) {
        canvas.drawCircle(Offset(dx, dy), 6, Paint()..color = dotColor);
        canvas.drawCircle(
          Offset(dx, dy),
          6,
          Paint()
            ..color = colors.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        canvas.drawCircle(Offset(dx, dy), 5, Paint()..color = colors.standard);
        canvas.drawCircle(
          Offset(dx, dy),
          5,
          Paint()
            ..color = dotColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: BT.fontCaption * textScale),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant EqCurvePainter old) =>
      old.bands != bands ||
      old.selectedBand != selectedBand ||
      old.lowCutOn != lowCutOn ||
      old.highCutOn != highCutOn ||
      old.sampleRate != sampleRate ||
      old.colors != colors ||
      old.textScale != textScale;
}
