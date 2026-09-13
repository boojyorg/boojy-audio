import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/shared/add_track_button.dart';
import 'package:boojy_audio/widgets/shared/circular_toggle_button.dart';
import 'package:boojy_audio/widgets/transport_bar.dart';
import 'package:boojy_audio/widgets/transport_bar/loop_split_button.dart';
import 'package:boojy_audio/widgets/transport_bar/metronome_split_button.dart';
import 'package:boojy_audio/widgets/transport_bar/position_display.dart';
import 'package:boojy_audio/widgets/transport_bar/record_controls.dart';
import 'package:boojy_audio/widgets/transport_bar/signature_dropdown.dart';
import 'package:boojy_audio/widgets/transport_bar/snap_split_button.dart';
import 'package:boojy_audio/widgets/transport_bar/tempo_controls.dart';

/// The transport bar's responsive ladder, swept across every window width
/// from the 960px minimum to a comfortable desktop width.
///
/// Rule under test (v0.7.0 release gate): the centre cluster sheds labels,
/// then gaps, then the tempo/signature readouts, but its glyphs never scale
/// below the outer buttons' size, and it never runs under the rails. When
/// the rails must yield (below ~1110px) they shed their own labels instead.
///
/// The width constants in `transport_bar.dart` are measured, not derived, so
/// a change to any centre button's width shows up here as an overflow or a
/// scale at some width: re-measure and update the ladder, don't loosen this.
void main() {
  const minWindow = 960.0;
  const maxWindow = 1600.0;

  final overflowErrors = <String>[];
  late FlutterExceptionHandler originalOnError;

  setUp(() {
    overflowErrors.clear();
    originalOnError = FlutterError.onError!;
    FlutterError.onError = (details) {
      final text = details.toString().toLowerCase();
      if (text.contains('overflowed')) {
        overflowErrors.add(details.exceptionAsString().split('\n').first);
        return;
      }
      // SVG / raster assets are absent under `flutter test`.
      if (text.contains('svg') || text.contains('asset')) return;
      originalOnError(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
  });

  /// Pumps a fresh bar (new key, so a RenderFlex that overflowed at one
  /// width can report again at the next: Flutter reports each render
  /// object's overflow only once).
  Future<void> pumpBar(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: TransportBar(
              key: UniqueKey(),
              playheadPosition: 0.0,
              projectName: 'A Fairly Long Project Name',
              // The real app wires Capture MIDI, which widens the modifiers
              // well; the ladder must be measured with it present.
              transport: TransportCallbacks(onCaptureMidi: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A widget is unscaled when its painted rect equals its layout size (the
  /// FittedBox that used to wrap the wells made these differ).
  void expectUnscaled(WidgetTester tester, Finder finder, double width) {
    final rect = tester.getRect(finder);
    final size = tester.getSize(finder);
    expect(
      rect.size,
      size,
      reason: '${finder.describeMatch(Plurality.one)} is scaled at ${width}px',
    );
  }

  Iterable<double> widths() sync* {
    for (var w = minWindow; w <= maxWindow; w += 4) {
      yield w;
    }
  }

  testWidgets('no centre control scales at any window width', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final w in widths()) {
      await pumpBar(tester, w);
      expectUnscaled(tester, find.byType(LoopSplitButton), w);
      expectUnscaled(tester, find.byType(SnapSplitButton), w);
      expectUnscaled(tester, find.byType(MetronomeSplitButton), w);
      expectUnscaled(tester, find.byType(PositionDisplay), w);
      expectUnscaled(tester, find.byType(CircularToggleButton).first, w);
      expectUnscaled(tester, find.byType(RecordButton), w);
      if (find.byType(TempoDisplay).evaluate().isNotEmpty) {
        expectUnscaled(tester, find.byType(TempoDisplay), w);
        expectUnscaled(tester, find.byType(SignatureDropdown), w);
      }
    }
  });

  testWidgets(
    'the centre cluster sits between the rails and nothing overflows',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final w in widths()) {
        await pumpBar(tester, w);
        expect(overflowErrors, isEmpty, reason: 'overflow at ${w}px');

        final libraryToggle = tester.getRect(find.byTooltip('Hide Library'));
        final addMidi = tester.getRect(find.byType(AddTrackButton).first);
        final loop = tester.getRect(find.byType(LoopSplitButton));
        final snap = tester.getRect(find.byType(SnapSplitButton));
        final metronome = tester.getRect(find.byType(MetronomeSplitButton));
        final play = tester.getRect(find.byType(CircularToggleButton).first);
        final record = tester.getRect(find.byType(RecordButton));
        final position = tester.getRect(find.byType(PositionDisplay));
        final hasTempo = find.byType(TempoDisplay).evaluate().isNotEmpty;
        final readoutsRight = hasTempo
            ? tester.getRect(find.byType(SignatureDropdown)).right
            : position.right;

        // Left to right, no overlaps, and clear of both rails.
        expect(
          loop.left,
          greaterThanOrEqualTo(libraryToggle.right),
          reason: '${w}px',
        );
        expect(snap.left, greaterThanOrEqualTo(loop.right), reason: '${w}px');
        expect(
          metronome.left,
          greaterThanOrEqualTo(snap.right),
          reason: '${w}px',
        );
        expect(play.left, greaterThan(metronome.right), reason: '${w}px');
        expect(position.left, greaterThan(record.right), reason: '${w}px');
        expect(
          readoutsRight,
          lessThanOrEqualTo(addMidi.left),
          reason: '${w}px',
        );

        // The transport stays on the window midpoint at every width.
        final transportMid = (play.left + record.right) / 2;
        expect(transportMid, closeTo(w / 2, 1.0), reason: '${w}px');
      }
    },
  );

  testWidgets('the right rail sheds its Add-track labels before it overflows', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpBar(tester, maxWindow);
    expect(find.text('MIDI'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);

    await pumpBar(tester, minWindow);
    expect(overflowErrors, isEmpty);
    expect(find.text('MIDI'), findsNothing);
    expect(find.text('Audio'), findsNothing);
  });
}
