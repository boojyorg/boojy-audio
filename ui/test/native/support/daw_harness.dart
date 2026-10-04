import 'dart:io';
import 'dart:typed_data';

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/main.dart';
import 'package:boojy_audio/screens/daw/mixins/daw_project_mixin.dart';
import 'package:boojy_audio/screens/daw_screen.dart';
import 'package:boojy_audio/services/state_consistency.dart';
import 'package:boojy_audio/services/vst3_plugin_manager.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/load_app_fonts.dart';

/// The real DAW screen over the real engine, with no window: workflow tests
/// do what Tyr does (drop a file, change tempo, loop, duplicate, save and
/// reopen) through the same DAW methods the buttons call, and check after
/// each step that the screen shows what the engine plays.
///
/// One per test: `final daw = await DawHarness.start(tester);` …
/// `await daw.close();`. The engine is shared by the whole test process;
/// every start begins with New Project, which clears it.
class DawHarness {
  DawHarness._(this.tester, this.tempDir);

  final WidgetTester tester;

  /// Scratch folder for audio files and saved projects; also where the app
  /// thinks its support folders are.
  final Directory tempDir;

  /// The DAW itself. Its state class is private; the helper mixins it is
  /// built from are not, and hold the methods the buttons call.
  DAWProjectMixin get daw => tester.state(find.byType(DAWScreen));

  AudioEngine get engine => daw.audioEngine!;

  static Future<DawHarness> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadAppFonts(tester);

    // Platform plugins have no implementation under `flutter test`.
    final tempDir = Directory.systemTemp.createTempSync('boojy_daw_');
    SharedPreferences.setMockInitialValues({});
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => {
        'appName': 'Boojy Audio',
        'packageName': 'com.boojy.audio',
        'version': '0.0.0',
        'buildNumber': '0',
      },
    );
    // Plugin editor windows hide while a dialog is open (the start screen).
    messenger.setMockMethodCallHandler(
      _vst3EditorChannel,
      (call) async => null,
    );
    Vst3PluginManager.scanOnStart = false;

    // The real app widget (theme, fonts, notices), as main() runs it.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const BoojyAudioApp(),
      ),
    );

    final harness = DawHarness._(tester, tempDir);
    // Settings, plugin preferences and the engine start for real, so they
    // need real time; the start screen appears once they have.
    await harness.settleUntil(
      () =>
          harness.daw.isAudioGraphInitialized &&
          find.text('New Project').evaluate().isNotEmpty,
      what: 'the engine to start and the start screen to show',
    );
    await tester.tap(find.text('New Project'));
    await harness.settle();
    return harness;
  }

  /// Run a DAW action that does real file work (save, open): under the test
  /// clock that work never finishes, so it runs on the real one. Then draw.
  Future<void> realTime(Future<void> Function() action) async {
    await tester.runAsync(action);
    await settle();
  }

  /// Let real time pass (engine, file and timer work) while drawing frames.
  Future<void> settle({int frames = 5, int ms = 50}) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  /// [settle] until [done] holds, failing after [timeout].
  Future<void> settleUntil(
    bool Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final watch = Stopwatch()..start();
    while (!done()) {
      if (watch.elapsed > timeout) fail('Timed out waiting for $what');
      await settle(frames: 1);
    }
  }

  /// The screen shows exactly what the engine plays (`state_consistency`).
  void expectScreenMatchesEngine({required String after}) {
    final problems = compareScreenWithEngine(
      engine: EngineSnapshot.read(engine),
      screenTempo: daw.tempo,
      audioClips: daw.timelineKey.currentState?.clips ?? const [],
      midiClips: daw.midiPlaybackManager?.midiClips ?? const [],
      midiEngineIds: daw.midiPlaybackManager?.dartToRustClipIds ?? const {},
    );
    expect(problems, isEmpty, reason: 'After $after');
  }

  /// A 2 s mono 48 kHz WAV in [tempDir]: a short 1 kHz click every half
  /// second (on the beat at 120 BPM), silence between.
  String writeClickWav(String name) {
    const rate = 48000;
    const frames = rate * 2;
    final data = ByteData(44 + frames * 2);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + frames * 2, Endian.little);
    ascii(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, frames * 2, Endian.little);
    for (var i = 0; i < frames; i++) {
      final click = i % (rate ~/ 2) < rate ~/ 100;
      final v = click ? ((i % 48) < 24 ? 12000 : -12000) : 0;
      data.setInt16(44 + i * 2, v, Endian.little);
    }
    final file = File('${tempDir.path}/$name')
      ..writeAsBytesSync(data.buffer.asUint8List());
    return file.path;
  }

  /// Stop playback, unmount the DAW (its dispose stops timers and
  /// listeners) and remove the scratch folder.
  Future<void> close() async {
    if (daw.isPlaying) daw.stopPlayback();
    await settle(frames: 2);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      null,
    );
    messenger.setMockMethodCallHandler(_vst3EditorChannel, null);
    Vst3PluginManager.scanOnStart = true;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

const _vst3EditorChannel = MethodChannel('boojy_audio.vst3.editor');
