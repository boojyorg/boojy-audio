// Regression coverage for the v0.7.0 release-gate item "ruler drag zoom
// doesn't feel right": the arrangement ignored the anchor beat the ruler
// reported (so a zoom pivoted on bar 1 and the bar under the pointer slid
// away) and the ruler counted its scroll offset twice once scrolled past
// bar 1. These drive the real TimelineView over the native engine.

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/tool_mode.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/shared/editors/unified_nav_bar.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/native_engine_harness.dart';

void main() {
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Ruler zoom anchor (native engine + timeline)', () {}, skip: reason);
    }
    return;
  }

  group('Arrangement ruler zoom (timeline widget + native engine)', () {
    late AudioEngine engine;
    late int trackId;

    setUp(() async {
      engine = await createInitializedEngine();
      trackId = engine.createTrack('midi', 'Zoom test');
      expect(trackId, greaterThan(0));
    });

    tearDown(() {
      engine.deleteTrack(trackId);
    });

    Future<TimelineViewState> pumpTimeline(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<TimelineViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
              child: TimelineView(
                key: key,
                playheadNotifier: ValueNotifier<double>(0.0),
                audioEngine: engine,
                tempo: 120.0,
                toolMode: ToolMode.select,
                trackOrder: [trackId],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return key.currentState!;
    }

    /// Beat shown [viewportX] px from the left edge of the ruler viewport.
    double beatAtRulerX(TimelineViewState state, double viewportX) =>
        (state.scrollController.offset + viewportX) / state.pixelsPerBeat;

    testWidgets('a vertical ruler drag holds the bar under the pointer', (
      tester,
    ) async {
      final state = await pumpTimeline(tester);
      // Scroll well past bar 1 so the anchor maths is exercised.
      state.scrollController.jumpTo(500);
      await tester.pump();

      final ruler = tester.getRect(find.byType(UnifiedNavBar));
      const viewportX = 300.0;
      // The ruler is a content-width child inside its scroll view, so its
      // rect starts `offset` px left of the viewport edge.
      final pointer = Offset(
        ruler.left + state.navBarScrollController.offset + viewportX,
        ruler.top + 10,
      );
      final beatBefore = beatAtRulerX(state, viewportX);
      final zoomBefore = state.pixelsPerBeat;

      final gesture = await tester.startGesture(
        pointer,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        // Held on every frame, not corrected a frame late.
        expect(
          beatAtRulerX(state, viewportX),
          closeTo(beatBefore, 1e-6),
          reason: 'move $i',
        );
        expect(
          state.navBarScrollController.offset,
          closeTo(state.scrollController.offset, 1e-6),
        );
      }
      await gesture.up();
      await tester.pump();

      // 100px down = ×2 (drag down zooms in).
      expect(state.pixelsPerBeat, closeTo(zoomBefore * 2, 1e-6));
      expect(beatAtRulerX(state, viewportX), closeTo(beatBefore, 1e-6));

      // And back up returns to the starting zoom with the bar still there.
      final back = await tester.startGesture(
        pointer,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 10; i++) {
        await back.moveBy(const Offset(0, -10));
        await tester.pump();
      }
      await back.up();
      await tester.pump();
      expect(state.pixelsPerBeat, closeTo(zoomBefore, 1e-6));
      expect(beatAtRulerX(state, viewportX), closeTo(beatBefore, 1e-6));
    });

    tearDownAll(() async {
      // Leave no timeline mounted between groups.
    });
  });
}
