import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/widgets/shared/editors/anchored_zoom.dart';

void main() {
  group('rulerDragZoomFactor', () {
    test('drag down zooms in, drag up zooms out', () {
      expect(rulerDragZoomFactor(10), greaterThan(1));
      expect(rulerDragZoomFactor(-10), lessThan(1));
      expect(rulerDragZoomFactor(0), 1);
    });

    test('equal travel is an equal ratio both ways (round trip = 1)', () {
      for (final d in [1.0, 7.5, 40.0, 100.0, 250.0]) {
        expect(
          rulerDragZoomFactor(d) * rulerDragZoomFactor(-d),
          closeTo(1, 1e-12),
        );
      }
    });

    test('ratios multiply, so many small moves equal one big move', () {
      var product = 1.0;
      for (var i = 0; i < 100; i++) {
        product *= rulerDragZoomFactor(1);
      }
      expect(product, closeTo(rulerDragZoomFactor(100), 1e-9));
      expect(
        rulerDragZoomFactor(kRulerDragPixelsPerDoubling),
        closeTo(2, 1e-12),
      );
    });
  });

  test('anchoredScrollOffset keeps the beat at the viewport x', () {
    // Beat 10 at 30px into the viewport, 50 px/beat → offset 470.
    final offset = anchoredScrollOffset(
      anchorBeat: 10,
      anchorViewportX: 30,
      pixelsPerBeat: 50,
    );
    expect(offset, 470);
    expect((offset + 30) / 50, 10);
  });

  group('applyZoomScroll', () {
    /// A 300px viewport over content that is [contentWidth] wide.
    Future<ScrollController> pumpScroller(
      WidgetTester tester,
      ValueNotifier<double> contentWidth,
    ) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 50,
              child: ValueListenableBuilder<double>(
                valueListenable: contentWidth,
                builder: (_, width, __) => SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, height: 50),
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('a jump past the pre-zoom extent lands and stays', (
      tester,
    ) async {
      final width = ValueNotifier<double>(1000);
      final controller = await pumpScroller(tester, width);
      controller.jumpTo(700); // old max
      await tester.pump();

      // Zoom in ×2 with the anchor near the right edge: the content becomes
      // 2000 wide and the target offset (1600) is past the old max (700).
      width.value = 2000;
      applyZoomScroll(
        controllers: [controller],
        offset: 1600,
        contentWidth: 2000,
      );
      expect(controller.offset, 1600);
      // Nothing springs back over the following frames.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, 1600, reason: 'frame $i');
      }
      expect(controller.position.maxScrollExtent, 1700);
    });

    testWidgets('zooming out clamps to the new, smaller extent', (
      tester,
    ) async {
      final width = ValueNotifier<double>(2000);
      final controller = await pumpScroller(tester, width);
      controller.jumpTo(1500);
      await tester.pump();

      width.value = 1000;
      applyZoomScroll(
        controllers: [controller],
        offset: 1500,
        contentWidth: 1000,
      );
      expect(controller.offset, 700);
      await tester.pump();
      expect(controller.offset, 700);
    });

    testWidgets('controllers without a viewport are skipped', (tester) async {
      final detached = ScrollController();
      applyZoomScroll(controllers: [detached], offset: 10, contentWidth: 100);
      expect(detached.hasClients, isFalse);
    });
  });
}
