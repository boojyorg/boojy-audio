import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/widgets/shared/boojy_button.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
  Widget wrap({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Center(child: child),
        ),
      ),
    );
  }

  testWidgets('renders with icon and label', (tester) async {
    await tester.pumpWidget(wrap(
      child: const BoojyButton(icon: Icons.loop, label: 'Loop'),
    ));
    expect(find.byIcon(Icons.loop), findsOneWidget);
    expect(find.text('Loop'), findsOneWidget);
  });

  testWidgets('renders icon-only when no label', (tester) async {
    await tester.pumpWidget(wrap(
      child: const BoojyButton(icon: Icons.delete),
    ));
    expect(find.byIcon(Icons.delete), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('triggers onTap', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(wrap(
      child: BoojyButton(
        icon: Icons.loop,
        label: 'Loop',
        onTap: () => tapped = true,
      ),
    ));
    await tester.tap(find.byType(BoojyButton));
    expect(tapped, isTrue);
  });

  testWidgets('active state renders without error', (tester) async {
    await tester.pumpWidget(wrap(
      child: const BoojyButton(
        icon: Icons.loop,
        label: 'Loop',
        isActive: true,
      ),
    ));
    expect(find.byType(BoojyButton), findsOneWidget);
  });

  testWidgets('compact size renders without error', (tester) async {
    await tester.pumpWidget(wrap(
      child: const BoojyButton(
        icon: Icons.grid_on,
        label: 'Snap',
        compact: true,
      ),
    ));
    expect(find.byType(BoojyButton), findsOneWidget);
  });

  testWidgets('shows tooltip when provided', (tester) async {
    await tester.pumpWidget(wrap(
      child: const BoojyButton(
        icon: Icons.loop,
        label: 'Loop',
        tooltip: 'Toggle Loop (L)',
      ),
    ));
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('iconWidget overrides icon', (tester) async {
    await tester.pumpWidget(wrap(
      child: BoojyButton(
        iconWidget: Container(color: Colors.red),
        label: 'Custom',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.loop), findsNothing);
    expect(find.text('Custom'), findsOneWidget);
  });
}
