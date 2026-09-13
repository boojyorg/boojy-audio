import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/shared/editors/anchored_zoom.dart';
import 'package:boojy_audio/widgets/shared/editors/nav_bar_with_zoom.dart';
import 'package:boojy_audio/widgets/shared/editors/unified_nav_bar.dart';

/// The ruler (UnifiedNavBar) inside its scrolling wrapper, as every editor
/// mounts it: 400px viewport, 50 px/beat, 64 beats of content.
void main() {
  const ppb = 50.0;
  late ScrollController scroll;
  late List<double> playheadSets;
  late List<({double factor, double anchorBeat, double viewportX})> drags;

  Future<void> pumpRuler(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    scroll = ScrollController();
    playheadSets = [];
    drags = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: NavBarWithZoom(
                  scrollController: scroll,
                  onZoomIn: () {},
                  onZoomOut: () {},
                  child: UnifiedNavBar(
                    config: const UnifiedNavBarConfig(
                      pixelsPerBeat: ppb,
                      totalBeats: 64,
                    ),
                    callbacks: UnifiedNavBarCallbacks(
                      onPlayheadSet: playheadSets.add,
                      onZoom: (factor, anchorBeat, viewportX) => drags.add((
                        factor: factor,
                        anchorBeat: anchorBeat,
                        viewportX: viewportX,
                      )),
                    ),
                    scrollController: scroll,
                    height: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a click lands on the beat under the pointer, scrolled or not', (
    tester,
  ) async {
    await pumpRuler(tester);
    await tester.tapAt(const Offset(100, 12));
    await tester.pump();
    expect(playheadSets, [2.0]);

    // Scroll 4 beats right: viewport x=100 is now beat 6 (it used to report
    // beat 10 because the scroll offset was counted twice).
    scroll.jumpTo(200);
    await tester.pump();
    await tester.tapAt(const Offset(100, 12));
    await tester.pump();
    expect(playheadSets, [2.0, 6.0]);
  });

  testWidgets('a vertical drag holds the grabbed beat and is exponential', (
    tester,
  ) async {
    await pumpRuler(tester);
    scroll.jumpTo(200);
    await tester.pump();

    // Mouse drag (no touch slop) from viewport x=100 → beat 6.
    final gesture = await tester.startGesture(
      const Offset(100, 12),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    // Sub-2px moves count too (there is no dead zone any more).
    await gesture.moveBy(const Offset(0, -1));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(drags, isNotEmpty);
    for (final d in drags) {
      expect(d.anchorBeat, closeTo(6.0, 1e-9));
      expect(d.viewportX, closeTo(100.0, 1e-9));
    }
    // Down = in, up = out.
    expect(drags.first.factor, greaterThan(1));
    expect(drags.last.factor, lessThan(1));
    // Down 60 then up 60 is a round trip; the final 1px is the only net move.
    final net = drags.fold(1.0, (p, d) => p * d.factor);
    expect(net, closeTo(rulerDragZoomFactor(-1), 1e-9));
  });

  testWidgets('a horizontal drag reports factor 1 and tracks the pointer', (
    tester,
  ) async {
    await pumpRuler(tester);
    final gesture = await tester.startGesture(
      const Offset(100, 12),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(drags.map((d) => d.factor), everyElement(1.0));
    expect(drags.map((d) => d.anchorBeat), everyElement(closeTo(2.0, 1e-9)));
    expect(drags.map((d) => d.viewportX).toList(), [130.0, 80.0]);
  });
}
