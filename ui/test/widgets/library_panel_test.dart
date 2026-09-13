import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boojy_audio/services/library_service.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/library_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildPanel(LibraryService service) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: LibraryPanel(libraryService: service),
        ),
      ),
    );
  }

  const roots = [
    'Favorites',
    'Sounds',
    'Samples',
    'Instruments',
    'Effects',
    'Plugins',
  ];

  testWidgets('Samples category lists the built-in Drums folder', (
    tester,
  ) async {
    final service = LibraryService();
    // Simulate a completed bundled-content install (no real filesystem
    // needed: the folder is only scanned when expanded).
    service.debugSetBundledDrumsRoot('/bundled/Samples/Drums');

    await tester.pumpWidget(buildPanel(service));
    await tester.pump();

    await tester.tap(find.text('Samples'));
    await tester.pumpAndSettle();

    // Regression guard: category rows must render top-level category items,
    // not just subcategories — the Drums folder lives there.
    expect(find.text('Drums'), findsOneWidget);
  });

  testWidgets('Samples category shows empty state before install completes', (
    tester,
  ) async {
    final service = LibraryService();

    await tester.pumpWidget(buildPanel(service));
    await tester.pump();

    await tester.tap(find.text('Samples'));
    await tester.pumpAndSettle();

    expect(find.text('Drums'), findsNothing);
    expect(find.textContaining('No samples'), findsOneWidget);
  });

  testWidgets('roots open in place and several stay open at once', (
    tester,
  ) async {
    final service = LibraryService();
    service.debugSetBundledDrumsRoot('/bundled/Samples/Drums');

    await tester.pumpWidget(buildPanel(service));
    await tester.pump();

    await tester.tap(find.text('Instruments'));
    await tester.pumpAndSettle();
    expect(find.text('Synthesizer'), findsOneWidget);

    // Opening a second root does not close the first.
    await tester.tap(find.text('Samples'));
    await tester.pumpAndSettle();
    expect(find.text('Synthesizer'), findsOneWidget);
    expect(find.text('Drums'), findsOneWidget);

    // Every root is still listed below the open ones — nothing is hidden.
    for (final root in roots) {
      expect(find.text(root), findsOneWidget);
    }

    // Clicking an open root closes only that root.
    await tester.tap(find.text('Instruments'));
    await tester.pumpAndSettle();
    expect(find.text('Synthesizer'), findsNothing);
    expect(find.text('Drums'), findsOneWidget);
  });

  testWidgets('roots expose expanded state; opening is not selecting', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final service = LibraryService();

    await tester.pumpWidget(buildPanel(service));
    await tester.pump();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Instruments')),
      matchesSemantics(
        label: 'Instruments',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    await tester.tap(find.text('Instruments'));
    await tester.pumpAndSettle();

    // Open, but still not selected — the root carries no selected state.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Instruments')),
      matchesSemantics(
        label: 'Instruments',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );

    // Items are the only selectable rows. Item rows also listen for double
    // taps, so a single tap lands after the double-tap timeout.
    await tester.tap(find.text('Synthesizer'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Synthesizer')),
      matchesSemantics(
        label: 'Synthesizer',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('arrow keys walk the tree and open or close rows', (
    tester,
  ) async {
    final service = LibraryService();

    await tester.pumpWidget(buildPanel(service));
    await tester.pump();

    // Click empty space below the rows to give the panel keyboard focus
    // without toggling anything.
    final panel = tester.getRect(find.byType(LibraryPanel));
    await tester.tapAt(Offset(panel.center.dx, panel.bottom - 8));
    await tester.pump();

    // Down ×4: Favorites → Sounds → Samples → Instruments.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Synthesizer'), findsOneWidget);

    // Right on an open root steps into its first child; Left steps back out;
    // Left on the open root closes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Synthesizer'), findsNothing);
    for (final root in roots) {
      expect(find.text(root), findsOneWidget);
    }
  });
}
