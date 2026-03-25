import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/widgets/editor_panel.dart';
import 'package:boojy_audio/models/tool_mode.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
  // Suppress SVG / asset-loading errors that occur in the test environment.
  late Function(FlutterErrorDetails)? originalOnError;

  setUp(() {
    originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final message = details.toString().toLowerCase();
      if (message.contains('svg') || message.contains('asset')) return;
      originalOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
  });

  Widget buildTestWidget({required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: child,
        ),
      ),
    );
  }

  testWidgets('EditorPanel renders collapsed', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(child: const EditorPanel(isCollapsed: true)),
    );

    expect(find.byType(EditorPanel), findsOneWidget);
  });

  testWidgets('EditorPanel renders with default props', (tester) async {
    await tester.pumpWidget(buildTestWidget(child: const EditorPanel()));

    expect(find.byType(EditorPanel), findsOneWidget);
  });

  testWidgets('EditorPanel renders with each toolMode variant', (tester) async {
    for (final mode in ToolMode.values) {
      await tester.pumpWidget(
        buildTestWidget(child: EditorPanel(toolMode: mode)),
      );

      expect(
        find.byType(EditorPanel),
        findsOneWidget,
        reason: 'EditorPanel should render with toolMode: $mode',
      );
    }
  });
}
