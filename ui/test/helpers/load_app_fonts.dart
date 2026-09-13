import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

/// Registers the app's bundled typefaces (Inter for UI text, JetBrains Mono
/// for readouts) with the test engine, so text measures as it does in the
/// real app instead of as the square-glyph test font. Call inside a widget
/// test; loads once per test process.
///
/// Fonts register globally, so widgets still need the family set — pass
/// `ThemeData(fontFamily: 'Inter')` to the test `MaterialApp` like the app
/// does in `main.dart`.
Future<void> loadAppFonts(WidgetTester tester) async {
  if (_loaded) return;
  await tester.runAsync(() async {
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = await File('assets/fonts/$file').readAsBytes();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }

    await load('Inter', [
      'Inter-Regular.ttf',
      'Inter-Medium.ttf',
      'Inter-SemiBold.ttf',
      'Inter-Bold.ttf',
    ]);
    await load('JetBrainsMono', [
      'JetBrainsMono-Regular.ttf',
      'JetBrainsMono-Medium.ttf',
      'JetBrainsMono-SemiBold.ttf',
      'JetBrainsMono-Bold.ttf',
    ]);
  });
  _loaded = true;
}
