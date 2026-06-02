// Headless golden tests for the legibility-critical CustomPainters.
//
// These render the painters straight to an image under plain `flutter test` —
// no macOS window, no device, no engine. They exist so the v0.5 "Trust &
// Legibility" work has a visual safety net: a token or lane-colour change that
// shifts these pixels fails the suite instead of silently regressing the look.
//
// Refresh the baselines after an *intentional* visual change:
//   cd ui && fvm flutter test --update-goldens test/goldens/
// then eyeball the PNGs in test/goldens/ before committing them.
//
// Both painters take their colours explicitly (GridPainter) or default to the
// dark-theme literals (TimelineGridPainter); we feed GridPainter from the real
// BoojyColors(BoojyTheme.dark) so a theme-token edit is caught here.
import 'dart:io' show Platform;

import 'package:boojy_audio/theme/app_colors.dart';
import 'package:boojy_audio/widgets/painters/painters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const colors = BoojyColors(BoojyTheme.dark);
  const boundaryKey = ValueKey('golden-boundary');

  // Golden pixels are rasterized per-platform; the baselines are generated on
  // macOS (the reference host). Windows CI also runs `flutter test`, so compare
  // only on macOS to avoid a cross-platform pixel mismatch turning CI red.
  // `--update-goldens` still regenerates on macOS.
  final skipOffReference = !Platform.isMacOS;

  Widget host(Size size, CustomPainter painter) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: CustomPaint(size: size, painter: painter),
        ),
      ),
    );
  }

  testWidgets(
    'piano-roll lane painter — key rows, root band, scale highlight',
    (tester) async {
      const minMidi = 48;
      const maxMidi = 84;
      const pixelsPerNote = 12.0;
      const pixelsPerBeat = 80.0;
      const totalBeats = 8.0;

      final painter = GridPainter(
        pixelsPerBeat: pixelsPerBeat,
        pixelsPerNote: pixelsPerNote,
        gridDivision: 0.25,
        maxMidiNote: maxMidi,
        minMidiNote: minMidi,
        totalBeats: totalBeats,
        activeBeats: totalBeats,
        // Lane / key-row colours — sourced from the real dark theme so a token
        // change moves these pixels and trips the golden.
        blackKeyBackground: const Color(0xFF15171C),
        whiteKeyBackground: colors.elevated,
        separatorLine: colors.elevated,
        subdivisionGridLine: colors.surface,
        beatGridLine: colors.hover,
        barGridLine: colors.textMuted,
        // The legibility features the v0.5 pass is tuning.
        scaleHighlightEnabled: true,
        scaleRootMidi: 0,
        activeRow: 60,
        activeLaneColor: colors.accent.withValues(alpha: 0.12),
        activeEdgeColor: colors.accent.withValues(alpha: 0.85),
        rootBandColor: colors.accent.withValues(alpha: 0.18),
      );

      await tester.pumpWidget(
        host(
          const Size(
            totalBeats * pixelsPerBeat,
            (maxMidi - minMidi) * pixelsPerNote,
          ),
          painter,
        ),
      );

      await expectLater(
        find.byKey(boundaryKey),
        matchesGoldenFile('piano_roll_lanes.png'),
      );
    },
    skip: skipOffReference,
  );

  testWidgets('timeline grid painter — bars, beats, loop region', (
    tester,
  ) async {
    final painter = TimelineGridPainter(
      pixelsPerBeat: 80.0,
      loopEnabled: true,
      loopStart: 4.0,
      loopEnd: 8.0,
    );

    await tester.pumpWidget(host(const Size(960, 120), painter));

    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('timeline_grid.png'),
    );
  }, skip: skipOffReference);
}
