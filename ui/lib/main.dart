import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/daw_screen.dart';
import 'services/user_settings.dart';
import 'services/vst3_editor_service.dart';
import 'services/window_title_service.dart';
import 'theme/theme_provider.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load user settings first
  final settings = UserSettings();
  await settings.load();

  // Initialize window title service for desktop
  await WindowTitleService.initialize();

  _runApp(settings);
}

void _runApp(UserSettings settings) {
  // Catch Flutter framework errors (layout, rendering, etc.)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('💥 [Flutter] ${details.exceptionAsString()}');
    debugPrint('💥 [Flutter] ${details.stack}');
  };

  // Catch uncaught async errors (Futures, isolate errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('💥 [Async] $error');
    debugPrint('💥 [Async] $stack');
    return true; // Prevent app termination
  };

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const BoojyAudioApp(),
    ),
  );
}

class BoojyAudioApp extends StatelessWidget {
  const BoojyAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = themeProvider.colors;

    return MaterialApp(
      title: 'Boojy Audio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: colors.standard,
          brightness: themeProvider.isDark ? Brightness.dark : Brightness.light,
        ).copyWith(primary: colors.accent, surface: colors.standard),
        useMaterial3: true,
        // Bundled UI typeface — all default Text inherits Inter; numeric
        // readouts opt into JetBrains Mono via BT.display() / BT.fontFamilyMono.
        fontFamily: 'Inter',
        scaffoldBackgroundColor: colors.dark,
        popupMenuTheme: PopupMenuThemeData(
          color: colors.elevated,
          shadowColor: BT.shadowColor,
          elevation: BT.elevationMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.divider, width: 1),
          ),
          textStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        ),
        dividerTheme: DividerThemeData(color: colors.divider, thickness: 1),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: colors.darkest,
            borderRadius: BorderRadius.circular(5),
            boxShadow: BT.shadowSm,
          ),
          textStyle: TextStyle(color: colors.textPrimary, fontSize: 11),
          waitDuration: const Duration(milliseconds: 200),
        ),
      ),
      builder: (context, child) {
        // Apply the persisted UI Scale globally via MediaQuery.textScaler.
        // ListenableBuilder rebuilds live when the user changes it in
        // Settings → Appearance; `child` is preserved so the app subtree
        // is not rebuilt, only the inherited MediaQuery re-propagates.
        return ListenableBuilder(
          listenable: UserSettings(),
          builder: (context, _) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(UserSettings().uiScale),
              ),
              child: child!,
            );
          },
        );
      },
      navigatorObservers: [_VST3OverlayObserver()],
      home: const DAWScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Dims embedded VST3 plugin child windows when modal dialogs appear,
/// so the dialog is readable through the faintly visible plugin.
/// Context menus (transparent barrier) are excluded.
class _VST3OverlayObserver extends NavigatorObserver {
  int _overlayCount = 0;

  bool _isModalOverlay(Route<dynamic> route) {
    if (route is PopupRoute) {
      final color = route.barrierColor;
      return color != null && color.a > 0;
    }
    return false;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModalOverlay(route)) {
      _overlayCount++;
      if (_overlayCount == 1) {
        VST3EditorService.hideAllEditors();
      }
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModalOverlay(route)) {
      _overlayCount = (_overlayCount - 1).clamp(0, 999);
      if (_overlayCount == 0) {
        VST3EditorService.showAllEditors();
      }
    }
  }
}
