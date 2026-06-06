import 'package:flutter/material.dart';
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

    // Regression guard: _buildNestedCategoryContents must render top-level
    // category items, not just subcategories — the Drums folder lives there.
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
}
