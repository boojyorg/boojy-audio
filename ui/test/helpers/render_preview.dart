import 'dart:io';
import 'dart:ui' as ui;

import 'package:boojy_audio/theme/app_colors.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'load_app_fonts.dart';

/// Renders [home] as the app would draw it (Inter, Material icons, Boojy
/// theme, 2x pixels) and writes `<name>.png` to `$PREVIEW_OUT` (default:
/// the system temp dir). For looking at new UI without launching the app.
///
/// Use from a throwaway `*_test.dart` that is NOT committed, e.g.
///   testWidgets('pill', (t) => renderPreview(t, name: 'pill',
///       home: const MyWidget(), before: () => Notices.info('Hi')));
/// then run:
///   PREVIEW_OUT=/some/dir fvm flutter test test/my_preview_test.dart
///
/// [builder] wraps the Navigator like `MaterialApp.builder` (e.g. to mount
/// `NoticeHost`); [before] runs after the first frame, before settling;
/// [interact] runs after settling, before capture (e.g. tap to expand).
Future<void> renderPreview(
  WidgetTester tester, {
  required String name,
  required Widget home,
  BoojyTheme theme = BoojyTheme.dark,
  Size size = const Size(1440, 900),
  TransitionBuilder? builder,
  VoidCallback? before,
  Future<void> Function(WidgetTester tester)? interact,
}) async {
  await loadAppFonts(tester);
  await _loadMaterialIcons(tester);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider()..setTheme(theme),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Inter'),
          builder: builder,
          home: home,
        ),
      ),
    ),
  );
  before?.call();
  // Fixed pumps, not pumpAndSettle: some widgets animate forever, which
  // would never settle.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (interact != null) {
    await interact(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final out = Platform.environment['PREVIEW_OUT'] ?? Directory.systemTemp.path;
  await tester.runAsync(() async {
    final image = await captureImage(key.currentContext! as Element);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$out/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });

  // Let pending timers (e.g. a notice's fade) fire, then unmount so looping
  // animations stop and the test can end.
  await tester.pump(const Duration(minutes: 1));
  await tester.pumpWidget(const SizedBox.shrink());
}

bool _iconsLoaded = false;

/// The Material icon font ships with the Flutter SDK, not the app's assets.
Future<void> _loadMaterialIcons(WidgetTester tester) async {
  if (_iconsLoaded) return;
  await tester.runAsync(() async {
    // flutter_tester lives at <root>/bin/cache/artifacts/engine/<arch>/.
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(
          Platform.resolvedExecutable,
        ).parent.parent.parent.parent.parent.parent.path;
    final font = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    final bytes = await font.readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });
  _iconsLoaded = true;
}
