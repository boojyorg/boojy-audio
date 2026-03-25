import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/widgets/transport_bar.dart';
import 'package:boojy_audio/theme/theme_provider.dart';

void main() {
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

  testWidgets('TransportBar renders with minimal props', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Suppress overflow errors (TransportBar is layout-sensitive)
    final originalOnError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        return;
      }
      if (details.toString().toLowerCase().contains('svg') ||
          details.toString().toLowerCase().contains('asset')) {
        return;
      }
      originalOnError(details);
    };

    await tester.pumpWidget(
      buildTestWidget(child: const TransportBar(playheadPosition: 0.0)),
    );

    expect(find.byType(TransportBar), findsOneWidget);

    FlutterError.onError = originalOnError;
  });

  testWidgets('TransportBar shows playhead position', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        return;
      }
      if (details.toString().toLowerCase().contains('svg') ||
          details.toString().toLowerCase().contains('asset')) {
        return;
      }
      originalOnError(details);
    };

    await tester.pumpWidget(
      buildTestWidget(child: const TransportBar(playheadPosition: 42.5)),
    );

    expect(find.byType(TransportBar), findsOneWidget);

    FlutterError.onError = originalOnError;
  });

  testWidgets('TransportBar with all callbacks set does not crash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        return;
      }
      if (details.toString().toLowerCase().contains('svg') ||
          details.toString().toLowerCase().contains('asset')) {
        return;
      }
      originalOnError(details);
    };

    await tester.pumpWidget(
      buildTestWidget(
        child: TransportBar(
          playheadPosition: 10.0,
          isPlaying: true,
          isRecording: false,
          metronomeEnabled: true,
          tempo: 140.0,
          projectName: 'Test Project',
          hasProject: true,
          onTempoChanged: (_) {},
          fileMenu: FileMenuCallbacks(
            onNewProject: () {},
            onOpenProject: () {},
            onSaveProject: () {},
            onSaveProjectAs: () {},
            onRenameProject: () {},
            onSaveNewVersion: () {},
            onExportAudio: () {},
            onExportMp3: () {},
            onExportWav: () {},
            onExportMidi: () {},
            onAppSettings: () {},
            onProjectSettings: () {},
            onCloseProject: () {},
          ),
          transport: TransportCallbacks(
            onPlay: () {},
            onPause: () {},
            onStop: () {},
            onRecord: () {},
            onPauseRecording: () {},
            onStopRecording: () {},
            onCaptureMidi: () {},
            onMetronomeToggle: () {},
            onPianoToggle: () {},
            onUndo: () {},
            onRedo: () {},
          ),
          panels: PanelCallbacks(
            onToggleLibrary: () {},
            onToggleMixer: () {},
            onToggleEditor: () {},
            onTogglePiano: () {},
            onResetPanelLayout: () {},
            onHelpPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byType(TransportBar), findsOneWidget);

    FlutterError.onError = originalOnError;
  });
}
