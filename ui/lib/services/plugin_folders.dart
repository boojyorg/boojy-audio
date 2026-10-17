import 'dart:io';

/// The folders the engine scans for VST3 plugins (`vst3_host.cpp`, keep in
/// sync).
List<String> vst3Folders() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return [
      r'C:\Program Files\Common Files\VST3',
      r'C:\Program Files (x86)\Common Files\VST3',
      if (env['APPDATA'] case final appData?) '$appData\\VST3',
      if (env['LOCALAPPDATA'] case final local?)
        '$local\\Programs\\Common\\VST3',
    ];
  }
  if (Platform.isMacOS) {
    return [
      '/Library/Audio/Plug-Ins/VST3',
      if (env['HOME'] case final home?) '$home/Library/Audio/Plug-Ins/VST3',
    ];
  }
  return [
    if (env['HOME'] case final home?) '$home/.vst3',
    '/usr/lib/vst3',
    '/usr/local/lib/vst3',
  ];
}

/// Whether a plugin was installed or removed in [folders] after [since].
///
/// Adding or removing a plugin changes its folder's modified time. The engine
/// searches every folder inside a VST3 folder (installers use vendor and
/// category folders), so every folder counts down to the plugin bundles,
/// whose insides don't. Missing folders are skipped: [savedPluginsMissing]
/// catches a removed VST3 folder.
bool pluginFoldersChangedSince(DateTime since, List<String> folders) {
  for (final path in folders) {
    final folder = Directory(path);
    if (folder.existsSync() && _folderChangedSince(folder, since)) return true;
  }
  return false;
}

bool _folderChangedSince(Directory folder, DateTime since) {
  if (folder.statSync().modified.isAfter(since)) return true;
  final List<FileSystemEntity> entries;
  try {
    entries = folder.listSync(followLinks: false);
  } on FileSystemException {
    return false; // Unreadable: the engine can't scan it either
  }
  for (final entry in entries) {
    if (entry is Directory &&
        !entry.path.endsWith('.vst3') &&
        _folderChangedSince(entry, since)) {
      return true;
    }
  }
  return false;
}

/// Whether any of the saved list's plugin bundles at [paths] is gone, for
/// example because its whole VST3 folder was deleted.
bool savedPluginsMissing(Iterable<String> paths) =>
    paths.any((path) => path.isNotEmpty && !Directory(path).existsSync());
