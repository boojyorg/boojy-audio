import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/daw_screen.dart';
import 'theme/theme_provider.dart';

void main() {
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
