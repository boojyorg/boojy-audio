import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'screens/daw_screen.dart';
import 'services/user_settings.dart';
import 'theme/theme_provider.dart';

const String _sentryDsn = 'https://e9ed35471624004209d192efe41ff66d@o4510676795260928.ingest.de.sentry.io/4510676802207824';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load user settings first to check crash reporting preference
  final settings = UserSettings();
  await settings.load();

  if (settings.crashReportingEnabled && _sentryDsn != 'YOUR_SENTRY_DSN_HERE') {
    // Initialize Sentry if user has opted in
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.tracesSampleRate = 1.0;
        options.environment = 'production';
        // Reduce debug noise in console
        options.debug = false;
      },
      appRunner: () => _runApp(settings),
    );
  } else {
    // Run without Sentry
    _runApp(settings);
  }
}

void _runApp(UserSettings settings) {
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
        ).copyWith(
          primary: colors.accent,
          surface: colors.standard,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: colors.standard,
        popupMenuTheme: PopupMenuThemeData(
          color: colors.elevated,
        ),
      ),
      home: const DAWScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
