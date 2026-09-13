import 'package:flutter/foundation.dart'
    show
        FlutterExceptionHandler,
        TargetPlatform,
        debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/shared/boojy_wordmark.dart';
import 'package:boojy_audio/widgets/shared/circular_toggle_button.dart';
import 'package:boojy_audio/widgets/transport_bar.dart';
import 'package:boojy_audio/widgets/transport_bar/count_in_toggle_button.dart';
import 'package:boojy_audio/widgets/transport_bar/loop_toggle_button.dart';
import 'package:boojy_audio/widgets/transport_bar/metronome_toggle_button.dart';
import 'package:boojy_audio/widgets/transport_bar/position_display.dart';
import 'package:boojy_audio/widgets/transport_bar/record_controls.dart';
import 'package:boojy_audio/widgets/transport_bar/signature_dropdown.dart';
import 'package:boojy_audio/widgets/transport_bar/snap_split_button.dart';
import 'package:boojy_audio/widgets/transport_bar/tempo_controls.dart';

import '../helpers/load_app_fonts.dart';

/// The transport bar's width allocation, swept across every window width
/// from the 960px minimum to a comfortable desktop width, on macOS (traffic
/// light inset) and Windows (none).
///
/// Rules under test (v0.7.0 toolbar): every control keeps its size at every
/// width; the project name gets a budget that depends on the window only
/// ("Untitled" always fits, longer names get more room as the window grows);
/// the transport is on the window midpoint wherever that leaves the name its
/// minimum, and slides right by exactly the shortfall where it doesn't. The
/// well widths in `transport_bar.dart` are measured with the app's real
/// typefaces, which is why this file loads them; a change to any centre
/// button's width shows up here as an overflow or an off-centre transport.
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
  Future<void> pumpBar(
    WidgetTester tester,
    double width, {
    String projectName = 'Untitled',
  }) async {
    await loadAppFonts(tester);
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        // The app sets Inter as its UI face (main.dart); the allocation is
        // measured with it.
        theme: ThemeData(fontFamily: 'Inter'),
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: TransportBar(
              key: UniqueKey(),
              playheadPosition: 0.0,
              projectName: projectName,
              // The real app wires Capture MIDI, which widens the transport
              // well; the allocation must be measured with it present.
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

  bool nameTruncated(WidgetTester tester, String name) =>
      tester.renderObject<RenderParagraph>(find.text(name)).didExceedMaxLines;

  Iterable<double> widths() sync* {
    for (var w = minWindow; w <= maxWindow; w += 4) {
      yield w;
    }
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    group('$platform', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      testWidgets('no centre control scales at any window width', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final w in widths()) {
          await pumpBar(tester, w);
          expectUnscaled(tester, find.byType(SnapSplitButton), w);
          expectUnscaled(tester, find.byType(LoopToggleButton), w);
          expectUnscaled(tester, find.byType(MetronomeToggleButton), w);
          expectUnscaled(tester, find.byType(CountInToggleButton), w);
          expectUnscaled(tester, find.byType(PositionDisplay), w);
          expectUnscaled(tester, find.byType(CircularToggleButton).first, w);
          expectUnscaled(tester, find.byType(RecordButton), w);
          if (find.byType(TempoDisplay).evaluate().isNotEmpty) {
            expectUnscaled(tester, find.byType(TempoDisplay), w);
            expectUnscaled(tester, find.byType(SignatureDropdown), w);
          }
        }
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets(
        'everything sits in order, nothing overflows, "Untitled" always fits, '
        'and the transport is centred or right of centre only',
        (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var sawCentred = false;
          for (final w in widths()) {
            await pumpBar(tester, w);
            expect(overflowErrors, isEmpty, reason: 'overflow at ${w}px');
            expect(
              nameTruncated(tester, 'Untitled'),
              isFalse,
              reason: '"Untitled" truncated at ${w}px',
            );

            final wordmark = tester.getRect(find.byType(BoojyWordmark));
            final libraryToggle = tester.getRect(
              find.byTooltip('Hide Library'),
            );
            final mixerToggle = tester.getRect(find.byTooltip('Hide Mixer'));
            final snap = tester.getRect(find.byType(SnapSplitButton));
            final loop = tester.getRect(find.byType(LoopToggleButton));
            final metronome = tester.getRect(
              find.byType(MetronomeToggleButton),
            );
            final countIn = tester.getRect(find.byType(CountInToggleButton));
            final play = tester.getRect(
              find.byType(CircularToggleButton).first,
            );
            final record = tester.getRect(find.byType(RecordButton));
            final capture = tester.getRect(
              find.byKey(const Key('captureMidi')),
            );
            final position = tester.getRect(find.byType(PositionDisplay));
            final hasTempo = find.byType(TempoDisplay).evaluate().isNotEmpty;
            final readoutsRight = hasTempo
                ? tester.getRect(find.byType(SignatureDropdown)).right
                : position.right;

            if (platform == TargetPlatform.macOS) {
              // Traffic lights (nudged 5pt right) end at x≈64.
              expect(wordmark.left, greaterThanOrEqualTo(74.0), reason: '$w');
            }
            expect(
              snap.left,
              greaterThanOrEqualTo(libraryToggle.right),
              reason: '${w}px',
            );
            expect(loop.left, greaterThanOrEqualTo(snap.right), reason: '$w');
            expect(
              metronome.left,
              greaterThanOrEqualTo(loop.right),
              reason: '${w}px',
            );
            expect(
              countIn.left,
              greaterThanOrEqualTo(metronome.right),
              reason: '${w}px',
            );
            expect(play.left, greaterThan(countIn.right), reason: '${w}px');
            expect(capture.left, greaterThan(record.right), reason: '$w');
            expect(position.left, greaterThan(capture.right), reason: '$w');
            expect(
              readoutsRight,
              lessThanOrEqualTo(mixerToggle.left),
              reason: '${w}px',
            );

            // Centred where the name has room; otherwise right of centre by
            // the shortfall, never left.
            final transportMid = (play.left + capture.right + 6) / 2;
            expect(
              transportMid,
              greaterThanOrEqualTo(w / 2 - 1.0),
              reason: 'transport left of centre at ${w}px',
            );
            if ((transportMid - w / 2).abs() <= 1.0) sawCentred = true;
          }
          expect(sawCentred, isTrue, reason: 'never reached exact centring');
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets('the name budget grows with the window, not the name', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const longName = 'Sunday Evening Beat';
        // The name slot is the same width whatever it holds.
        await pumpBar(tester, 1280);
        final shortSlot = tester.getSize(find.text('Untitled')).width;
        final playShort = tester.getRect(
          find.byType(CircularToggleButton).first,
        );
        await pumpBar(tester, 1280, projectName: longName);
        final longSlot = tester.getSize(find.text(longName)).width;
        final playLong = tester.getRect(
          find.byType(CircularToggleButton).first,
        );
        expect(longSlot, closeTo(shortSlot, 0.5));
        expect(playLong.left, closeTo(playShort.left, 0.5));

        // A long name truncates at the default window and fits when the
        // window is wide enough to pay for it.
        expect(nameTruncated(tester, longName), isTrue);
        await pumpBar(tester, maxWindow, projectName: longName);
        expect(nameTruncated(tester, longName), isFalse);
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }

  testWidgets('the default window keeps every label, including BPM', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpBar(tester, 1280);
    expect(find.text('Count-in'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('Bar'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
