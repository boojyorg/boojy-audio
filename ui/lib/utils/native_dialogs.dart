// Cross-platform native file/folder dialogs for desktop.
//
// macOS keeps the original AppleScript dialogs (unchanged behaviour); every
// other platform uses file_picker, which shows the real native dialog on
// Windows/Linux. Before this helper existed, all dialog sites called
// `osascript` inline — which throws a ProcessException on Windows, so Save As,
// Open Project, and Export were broken there (v0.5.3 smoke test).

import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Show a native "choose folder" dialog. Returns the chosen folder path
/// (no trailing slash) or null if the user cancelled.
Future<String?> pickFolder({
  required String title,
  String? initialDirectory,
}) async {
  if (Platform.isMacOS) {
    final defaultLocation = initialDirectory != null
        ? ' default location POSIX file "$initialDirectory"'
        : '';
    final result = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose folder with prompt "$title"$defaultLocation)',
    ]);
    if (result.exitCode != 0) return null; // User cancelled
    var path = result.stdout.toString().trim();
    // osascript's `POSIX path of folder` always returns a trailing slash;
    // strip it so joins don't produce `…/Projects//Name.audio`.
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return path.isEmpty ? null : path;
  }

  return FilePicker.platform.getDirectoryPath(
    dialogTitle: title,
    initialDirectory: initialDirectory,
  );
}

/// Show a native "save file" dialog. Returns the chosen file path or null if
/// the user cancelled. Callers are responsible for enforcing the extension
/// (both backends may return a name without one).
Future<String?> pickSaveFilePath({
  required String title,
  required String defaultName,
  String? initialDirectory,
}) async {
  if (Platform.isMacOS) {
    final defaultLocation = initialDirectory != null
        ? ' default location POSIX file "$initialDirectory"'
        : '';
    final script =
        'POSIX path of (choose file name with prompt "$title" '
        'default name "$defaultName"$defaultLocation)';
    final result = await Process.run('osascript', ['-e', script]);
    if (result.exitCode != 0) return null; // User cancelled
    final path = result.stdout.toString().trim();
    return path.isEmpty ? null : path;
  }

  return FilePicker.platform.saveFile(
    dialogTitle: title,
    fileName: defaultName,
    initialDirectory: initialDirectory,
  );
}

/// Strip characters Windows forbids in file/folder names (macOS allows most
/// of them, but a project saved as `My Song: Demo` must not fail on Windows).
String sanitizeFileName(String name) {
  return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
}

/// Platform-appropriate menu label for [revealInFinder].
String get revealInFinderLabel {
  if (Platform.isMacOS) return 'Show in Finder';
  if (Platform.isWindows) return 'Show in Explorer';
  return 'Show in File Manager';
}

/// Reveal [path] in the platform's file manager, selecting it when the
/// platform supports selection. Never throws on a nonzero exit code —
/// Windows `explorer` exits nonzero even on success.
Future<void> revealInFinder(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else if (Platform.isWindows) {
    // explorer needs backslashes; forward slashes make /select silently
    // fall back to opening the Documents folder. The path must reach
    // explorer QUOTED or any space in it truncates the argument (also a
    // silent Documents fallback) — pass `/select,` and the path as two
    // arguments so dart:io's Windows argument quoting wraps the path in
    // quotes itself (`explorer /select, "C:\My Dir\f.txt"`). Embedding
    // quotes in a single `/select,"$winPath"` argument does NOT work:
    // dart:io re-escapes the embedded quotes and explorer's own command
    // line parser mangles them.
    final winPath = path.replaceAll('/', r'\');
    await Process.run('explorer', ['/select,', winPath]);
  } else {
    // Linux: no portable "select file in manager" — open the containing
    // directory instead (or the folder itself if path is a directory).
    final isDir = await Directory(path).exists();
    final target = isDir ? path : File(path).parent.path;
    await Process.run('xdg-open', [target]);
  }
}
