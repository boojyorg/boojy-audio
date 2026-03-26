import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/widgets/shared/mini_knob.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
  Widget buildTestWidget({
    required double value,
    double min = 0.0,
    double max = 1.0,
    Function(double)? onChanged,
    VoidCallback? onChangeEnd,
    String? label,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Center(
            child: MiniKnob(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              label: label,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('MiniKnob renders at default size', (tester) async {
    await tester.pumpWidget(buildTestWidget(value: 0.5));
    await tester.pumpAndSettle();
    expect(find.byType(MiniKnob), findsOneWidget);
  });

  testWidgets('MiniKnob shows label when provided', (tester) async {
    await tester.pumpWidget(buildTestWidget(value: 0.5, label: 'Vol'));
    await tester.pumpAndSettle();
    expect(find.text('Vol'), findsOneWidget);
  });

  testWidgets('MiniKnob drag up increases value', (tester) async {
    double currentValue = 0.5;
    await tester.pumpWidget(buildTestWidget(
      value: currentValue,
      onChanged: (v) => currentValue = v,
    ));
    await tester.pumpAndSettle();

    // Drag upward (negative dy = increase)
    final knob = find.byType(MiniKnob);
    await tester.drag(knob, const Offset(0, -75));
    await tester.pumpAndSettle();

    expect(currentValue, greaterThan(0.5));
  });

  testWidgets('MiniKnob drag down decreases value', (tester) async {
    double currentValue = 0.5;
    await tester.pumpWidget(buildTestWidget(
      value: currentValue,
      onChanged: (v) => currentValue = v,
    ));
    await tester.pumpAndSettle();

    final knob = find.byType(MiniKnob);
    await tester.drag(knob, const Offset(0, 75));
    await tester.pumpAndSettle();

    expect(currentValue, lessThan(0.5));
  });

  testWidgets('MiniKnob clamps to min/max range', (tester) async {
    double currentValue = 0.9;
    await tester.pumpWidget(buildTestWidget(
      value: currentValue,
      min: 0.0,
      max: 1.0,
      onChanged: (v) => currentValue = v,
    ));
    await tester.pumpAndSettle();

    // Drag far up — should clamp to max
    final knob = find.byType(MiniKnob);
    await tester.drag(knob, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(currentValue, lessThanOrEqualTo(1.0));
  });

  testWidgets('MiniKnob double-tap resets to center', (tester) async {
    double currentValue = 0.9;
    await tester.pumpWidget(buildTestWidget(
      value: currentValue,
      min: 0.0,
      max: 1.0,
      onChanged: (v) => currentValue = v,
    ));
    await tester.pumpAndSettle();

    final knob = find.byType(MiniKnob);
    await tester.tap(knob);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(knob);
    await tester.pumpAndSettle();

    expect(currentValue, closeTo(0.5, 0.01));
  });

  testWidgets('MiniKnob with no onChanged does not crash on drag',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(value: 0.5));
    await tester.pumpAndSettle();

    final knob = find.byType(MiniKnob);
    await tester.drag(knob, const Offset(0, -50));
    await tester.pumpAndSettle();

    // Should not throw
    expect(find.byType(MiniKnob), findsOneWidget);
  });
}
