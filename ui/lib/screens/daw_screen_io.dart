// Native platform IO utilities for DAW screen
// This file is used on native platforms (iOS, macOS, Windows, Linux, Android)

import 'dart:io';

export 'dart:io' show Platform, Directory, File, Process;

/// Get the path separator for the current platform
String get pathSeparator => Platform.pathSeparator;

/// Get an environment variable value
String? getEnv(String name) => Platform.environment[name];

/// Get the default projects folder path
Future<String> getDefaultProjectsFolder() async {
  final home = Platform.environment['HOME'] ?? '/Users/${Platform.environment['USER']}';
  final projectsPath = '$home/Documents/Boojy/Audio/Projects';

  // Create the folder if it doesn't exist
  final dir = Directory(projectsPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return projectsPath;
}

/// Check if running on web
bool get isWeb => false;

/// Check if running on macOS
bool get isMacOS => Platform.isMacOS;

/// Check if running on Windows
bool get isWindows => Platform.isWindows;

/// Check if running on iOS
bool get isIOS => Platform.isIOS;

/// Check if running on Android
bool get isAndroid => Platform.isAndroid;

/// Open a folder in the system file explorer
Future<void> openInFileExplorer(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', [path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  }
}

/// Show a native folder picker dialog (macOS only)
Future<String?> showNativeFolderPicker() async {
  if (!Platform.isMacOS) return null;

  final result = await Process.run('osascript', [
    '-e',
    'tell application "System Events" to return POSIX path of (choose folder with prompt "Select folder")',
  ]);

  if (result.exitCode == 0) {
    final path = result.stdout.toString().trim();
    if (path.isNotEmpty) return path;
  }
  return null;
}

/// Show a native file save dialog (macOS only)
Future<String?> showNativeFileSaveDialog({
  required String defaultName,
  required String fileType,
}) async {
  if (!Platform.isMacOS) return null;

  final result = await Process.run('osascript', [
    '-e',
    'tell application "System Events" to return POSIX path of (choose file name with prompt "Save as" default name "$defaultName")',
  ]);

  if (result.exitCode == 0) {
    var path = result.stdout.toString().trim();
    if (path.isNotEmpty) {
      if (!path.endsWith('.$fileType')) {
        path = '$path.$fileType';
      }
      return path;
    }
  }
  return null;
}
