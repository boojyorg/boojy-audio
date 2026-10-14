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
/// Adding or removing a plugin changes its folder's modified time. Installers
/// often use a vendor folder inside the VST3 folder, so the folders one level
/// down count too. Missing folders are skipped.
bool pluginFoldersChangedSince(DateTime since, List<String> folders) {
  for (final path in folders) {
    final folder = Directory(path);
    if (!folder.existsSync()) continue;
    if (folder.statSync().modified.isAfter(since)) return true;
    for (final entry in folder.listSync(followLinks: false)) {
      if (entry is Directory && entry.statSync().modified.isAfter(since)) {
        return true;
      }
    }
  }
  return false;
}
