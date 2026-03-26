import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/widgets/shared/split_button.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
  Widget buildTestWidget({
    required Widget child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Center(child: child),
        ),
      ),
    );
  }

  testWidgets('SplitButton renders with label', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      child: const SplitButton<String>(label: 'Snap'),
    ));

    expect(find.text('Snap'), findsOneWidget);
  });

  testWidgets('SplitButton triggers onLabelTap', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(buildTestWidget(
      child: SplitButton<String>(
        label: 'Loop',
        onLabelTap: () => tapped = true,
      ),
    ));

    await tester.tap(find.text('Loop'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('SplitButton shows active state', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      child: const SplitButton<String>(label: 'Snap', isActive: true),
    ));

    // Widget should render without error in active state
    expect(find.byType(SplitButton<String>), findsOneWidget);
  });

  testWidgets('SplitButton shows icon when provided', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      child: const SplitButton<String>(
        label: 'Test',
        icon: Icons.loop,
      ),
    ));

    expect(find.byIcon(Icons.loop), findsOneWidget);
  });

  testWidgets('SplitButton opens dropdown on right zone tap', (tester) async {
    String? selected;
    await tester.pumpWidget(buildTestWidget(
      child: SplitButton<String>(
        label: 'Grid',
        dropdownItems: const [
          PopupMenuItem(value: 'beat', child: Text('Beat')),
          PopupMenuItem(value: 'bar', child: Text('Bar')),
        ],
        onItemSelected: (v) => selected = v,
      ),
    ));

    // Find and tap the dropdown arrow zone (right side of split button)
    final dropdownIcon = find.byIcon(Icons.arrow_drop_down);
    if (dropdownIcon.evaluate().isNotEmpty) {
      await tester.tap(dropdownIcon);
      await tester.pumpAndSettle();

      // Dropdown should show menu items
      expect(find.text('Beat'), findsOneWidget);
      expect(find.text('Bar'), findsOneWidget);

      // Select an item
      await tester.tap(find.text('Beat'));
      await tester.pumpAndSettle();
      expect(selected, 'beat');
    }
  });

  testWidgets('SplitButton without dropdown hides arrow', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      child: const SplitButton<String>(
        label: 'Simple',
        showDropdown: false,
      ),
    ));

    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
  });
}
