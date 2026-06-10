import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/piano_roll.dart';
import 'package:boojy_audio/widgets/transport_bar/signature_dropdown.dart';

void main() {
  (int, int)? committed;
  var dragStarts = 0;
  var dragEnds = 0;

  Future<void> pumpPianoRoll(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    committed = null;
    dragStarts = 0;
    dragEnds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: PianoRoll(
              beatsPerBar: 4,
              beatUnit: 4,
              onTimeSignatureChanged: (numerator, unit) =>
                  committed = (numerator, unit),
              onTimeSignatureDragStart: () => dragStarts++,
              onTimeSignatureDragEnd: () => dragEnds++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Signature box click opens the n/4 menu and commits a pick', (
    tester,
  ) async {
    await pumpPianoRoll(tester);

    final box = find.byType(SignatureDropdown);
    expect(
      box,
      findsOneWidget,
      reason: 'piano roll reuses the transport-bar signature control',
    );

    // Click anywhere on the box — not a pixel-perfect digit target.
    await tester.tap(box);
    await tester.pumpAndSettle();

    expect(
      find.text('6/4'),
      findsOneWidget,
      reason: 'menu should list the n/4 options',
    );

    await tester.tap(find.text('6/4'));
    await tester.pumpAndSettle();

    expect(committed, (6, 4));
  });

  testWidgets('Signature drag scrubs the numerator and brackets the drag '
      'with start/end callbacks for undo coalescing', (tester) async {
    await pumpPianoRoll(tester);

    // Drag up = increase. 30px at 6px/step = +5, clamped per-step by the
    // current value, so we just assert a change plus the bracket callbacks.
    await tester.drag(find.byType(SignatureDropdown), const Offset(0, -30));
    await tester.pumpAndSettle();

    expect(dragStarts, 1);
    expect(dragEnds, 1);
    expect(committed, isNotNull);
    expect(committed!.$1, greaterThan(4));
    expect(committed!.$2, 4);
  });
}
