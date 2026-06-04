import 'package:flutter/material.dart';

/// Candidate fills for the arrangement/timeline canvas, explored live via the
/// dev cycle shortcut (Cmd+Shift+B). The canvas is currently a near-black
/// (`colors.editor` ≈ #0C0E11); these lift it toward a more refined dark grey.
///
/// Each variant carries everything the lift needs: the [background] fill, a
/// [gridLift] that nudges the (opaque, lighter-than-bg) grid lines toward white
/// so they don't lose contrast as the canvas brightens, and an optional
/// [laneTint] for the Logic-style alternating-lane option. Once a winner is
/// chosen we hard-set it and drop the switcher.
enum CanvasBgVariant {
  /// 1 — barely lifted. Safest; still reads as "black".
  barelyLifted,

  /// 2 — a clear dark grey with a slight cool tint.
  darkGrey,

  /// 3 — noticeably grey. Watch the grid lines don't wash out.
  noticeableGrey,

  /// 4 — a mid base plus a faint alternating per-lane tint (adds structure).
  tintedLanes,
}

extension CanvasBgVariantInfo on CanvasBgVariant {
  /// The canvas background fill.
  Color get background {
    switch (this) {
      case CanvasBgVariant.barelyLifted:
        return const Color(0xFF121214);
      case CanvasBgVariant.darkGrey:
        return const Color(0xFF16171A);
      case CanvasBgVariant.noticeableGrey:
        return const Color(0xFF1C1D21);
      case CanvasBgVariant.tintedLanes:
        return const Color(0xFF141518);
    }
  }

  /// How far to lerp each grid-line colour toward white. The grid lines are
  /// opaque and already a touch lighter than every background here, so a small
  /// lift restores the contrast a brighter canvas would otherwise eat.
  double get gridLift {
    switch (this) {
      case CanvasBgVariant.barelyLifted:
        return 0.0;
      case CanvasBgVariant.darkGrey:
        return 0.06;
      case CanvasBgVariant.noticeableGrey:
        return 0.12;
      case CanvasBgVariant.tintedLanes:
        return 0.05;
    }
  }

  /// Faint wash applied to alternating track lanes (only [tintedLanes]); null
  /// means lanes stay transparent and show the flat canvas.
  Color? get laneTint {
    switch (this) {
      case CanvasBgVariant.tintedLanes:
        return Colors.white.withValues(alpha: 0.015);
      default:
        return null;
    }
  }

  /// Apply [gridLift] to a base grid-line colour.
  Color liftGrid(Color base) => Color.lerp(base, Colors.white, gridLift)!;

  /// Label shown in the cycle's on-screen confirmation.
  String get labLabel {
    switch (this) {
      case CanvasBgVariant.barelyLifted:
        return '1 · #121214 (barely lifted)';
      case CanvasBgVariant.darkGrey:
        return '2 · #16171A (dark grey)';
      case CanvasBgVariant.noticeableGrey:
        return '3 · #1C1D21 (noticeable grey)';
      case CanvasBgVariant.tintedLanes:
        return '4 · #141518 + lane tint';
    }
  }

  /// Next variant in the cycle (wraps).
  CanvasBgVariant get next =>
      CanvasBgVariant.values[(index + 1) % CanvasBgVariant.values.length];
}
