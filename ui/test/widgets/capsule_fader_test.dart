// Regression test for the M1 fader click-teleport: a single click on the
// fader body used to jump the volume to the click point (the only recovery
// was double-tap-reset or undo). Clicks must now be inert; volume changes
// only through drag or double-tap reset.
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/capsule_fader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: Center(child: SizedBox(width: 200, height: 24, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('single click on the fader body does not change volume', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      _wrap(
        CapsuleFader(
          leftLevel: 0.0,
          rightLevel: 0.0,
          volumeDb: 0.0,
          onVolumeChanged: changes.add,
        ),
      ),
    );

    // Click near the left end — far from the unity-gain thumb position.
    final faderRect = tester.getRect(find.byType(CapsuleFader));
    await tester.tapAt(Offset(faderRect.left + 10, faderRect.center.dy));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      changes,
      isEmpty,
      reason:
          'A single click must not teleport the volume (M1). Only drag and '
          'double-tap-reset may change it.',
    );
  });

  testWidgets('horizontal drag still changes volume', (tester) async {
    final changes = <double>[];
    await tester.pumpWidget(
      _wrap(
        CapsuleFader(
          leftLevel: 0.0,
          rightLevel: 0.0,
          volumeDb: 0.0,
          onVolumeChanged: changes.add,
        ),
      ),
    );

    await tester.drag(
      find.byType(CapsuleFader),
      const Offset(-40, 0),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(changes, isNotEmpty);
  });

  testWidgets('double-tap fires the reset callback', (tester) async {
    var resets = 0;
    await tester.pumpWidget(
      _wrap(
        CapsuleFader(
          leftLevel: 0.0,
          rightLevel: 0.0,
          volumeDb: -12.0,
          onVolumeChanged: (_) {},
          onDoubleTap: () => resets++,
        ),
      ),
    );

    final spot = tester.getCenter(find.byType(CapsuleFader));
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 400));

    expect(resets, 1);
  });
}
