import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/virtual_piano.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/native_engine_harness.dart';

void main() {
  // The computer-keyboard piano only listened while its own widget had focus.
  // Clicking a track (or anything else) moved focus away, so every note key
  // went unhandled and macOS played its error sound. These drive the real
  // piano over the real engine with focus parked somewhere else.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Virtual piano keys (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Virtual piano keys (native engine)', () {
    late AudioEngine engine;
    late int trackId;

    setUp(() async {
      engine = await createInitializedEngine();
      trackId = engine.createTrack('midi', 'Piano Keys');
    });

    Future<({FocusNode elsewhere, FocusNode textField, List<int?> notes})>
    pumpPiano(WidgetTester tester) async {
      final elsewhere = FocusNode();
      final textField = FocusNode();
      final notes = <int?>[];
      addTearDown(elsewhere.dispose);
      addTearDown(textField.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Focus(
                    focusNode: elsewhere,
                    child: const SizedBox(height: 20),
                  ),
                  TextField(focusNode: textField),
                  const Spacer(),
                  VirtualPiano(
                    audioEngine: engine,
                    isEnabled: true,
                    targetTrackId: () => trackId,
                    onNoteHighlight: notes.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (elsewhere: elsewhere, textField: textField, notes: notes);
    }

    testWidgets('note keys play while focus is on another widget', (
      tester,
    ) async {
      final p = await pumpPiano(tester);
      p.elsewhere.requestFocus();
      await tester.pump();

      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      expect(handled, isTrue, reason: 'unhandled keys make macOS beep');
      expect(p.notes.whereType<int>(), isNotEmpty);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    });

    testWidgets('note keys are left alone while typing in a text field', (
      tester,
    ) async {
      final p = await pumpPiano(tester);
      p.textField.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(p.notes.whereType<int>(), isEmpty);
    });

    testWidgets('command shortcuts are not swallowed', (tester) async {
      final p = await pumpPiano(tester);
      p.elsewhere.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      expect(handled, isFalse);
      expect(p.notes.whereType<int>(), isEmpty);
    });
  });
}
