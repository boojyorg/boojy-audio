import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/piano_roll.dart';
import 'package:boojy_audio/widgets/transport_bar/signature_dropdown.dart';

void main() {
  testWidgets('piano roll controls bar has no time-signature control '
      '(the toolbar is the only place to change it)', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: const PianoRoll(beatsPerBar: 3, beatUnit: 4),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SignatureDropdown), findsNothing);
    expect(find.text('Signature'), findsNothing);
    // The loop fields are still there.
    expect(find.text('Length'), findsOneWidget);
  });
}
