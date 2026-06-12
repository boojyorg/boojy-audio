import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:boojy_audio/services/user_settings.dart';
import 'package:boojy_audio/widgets/transport_bar.dart';
import 'package:boojy_audio/widgets/transport_bar/position_display.dart';
import 'package:boojy_audio/widgets/transport_bar/record_controls.dart';
import 'package:boojy_audio/widgets/transport_bar/tempo_controls.dart';
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

  // EH-11: the transport's primary contract — buttons firing their callbacks.
  group('transport taps fire callbacks', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required TransportCallbacks transport,
      bool isPlaying = false,
      bool hasArmedTracks = false,
    }) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildTestWidget(
          child: TransportBar(
            playheadPosition: 0.0,
            canPlay: true,
            isPlaying: isPlaying,
            hasArmedTracks: hasArmedTracks,
            transport: transport,
          ),
        ),
      );
    }

    testWidgets('play fires onPlay', (tester) async {
      var plays = 0;
      await pumpBar(
        tester,
        transport: TransportCallbacks(onPlay: () => plays++),
      );
      await tester.tap(find.byTooltip('Play (Space)'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(plays, 1);
    });

    testWidgets('pause fires onPause while playing', (tester) async {
      var pauses = 0;
      await pumpBar(
        tester,
        isPlaying: true,
        transport: TransportCallbacks(onPause: () => pauses++),
      );
      await tester.tap(find.byTooltip('Pause (Space)'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(pauses, 1);
    });

    testWidgets('stop fires onStop', (tester) async {
      var stops = 0;
      await pumpBar(
        tester,
        transport: TransportCallbacks(onStop: () => stops++),
      );
      await tester.tap(find.byTooltip('Stop'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(stops, 1);
    });

    testWidgets('record fires onRecord with an armed track', (tester) async {
      var records = 0;
      await pumpBar(
        tester,
        hasArmedTracks: true,
        transport: TransportCallbacks(onRecord: () => records++),
      );
      await tester.tap(find.byType(RecordButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(records, 1);
    });
  });

  // X1 regression: with onTap + onDoubleTap on one detector, every mode-cycle
  // tap waited ~300 ms for the double-tap recognizer to give up the arena.
  // Double-click is now detected manually, so a single tap must land at once.
  group('PositionDisplay tap latency (X1)', () {
    tearDown(() => UserSettings().positionDisplayMode = 'bars');

    testWidgets('single tap cycles the mode immediately', (tester) async {
      UserSettings().positionDisplayMode = 'bars';
      await tester.pumpWidget(
        buildTestWidget(
          child: const PositionDisplay(playheadPosition: 0.0, tempo: 120.0),
        ),
      );
      expect(find.text('1.1.1'), findsOneWidget);

      await tester.tap(find.byType(PositionDisplay), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('0:00.000'),
        findsOneWidget,
        reason:
            'The mode must cycle within 50ms of the tap. A failure here '
            'means a double-tap recognizer is holding the arena again (X1).',
      );
    });

    testWidgets('double-click opens the jump editor', (tester) async {
      UserSettings().positionDisplayMode = 'bars';
      await tester.pumpWidget(
        buildTestWidget(
          child: const PositionDisplay(playheadPosition: 0.0, tempo: 120.0),
        ),
      );
      final spot = tester.getCenter(find.byType(PositionDisplay));
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(spot);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      // The first tap's mode-cycle is reverted when it turns into a double.
      expect(UserSettings().positionDisplayMode, 'bars');
    });
  });

  // X2 regression: the tempo number zone's onDoubleTap made every
  // drag-to-nudge start sticky. Double-click is detected manually now.
  // Note: double-click detection compares real DateTime.now() timestamps, so
  // these are split into separate tests — tester.pump() only advances the
  // fake clock, and consecutive taps in one test are milliseconds apart in
  // real time.
  group('TempoDisplay double-tap (X2)', () {
    testWidgets('single tap opens no dialog', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: TempoDisplay(tempo: 120.0, onTempoChanged: (_) {}),
        ),
      );

      await tester.tap(find.text('120'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Project Tempo'), findsNothing);
    });

    testWidgets('double-click opens the tempo dialog', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: TempoDisplay(tempo: 120.0, onTempoChanged: (_) {}),
        ),
      );

      final numberZone = find.text('120');
      await tester.tap(numberZone, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(numberZone, warnIfMissed: false);
      await tester.pump();
      expect(find.text('Project Tempo'), findsOneWidget);
    });
  });
}
