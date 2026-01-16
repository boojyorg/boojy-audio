// Web platform IO utilities for DAW screen
// This file is used on web platform where dart:io is not available

import 'dart:async';

// Stub classes for web compatibility
// These mirror dart:io classes but are safe for web

/// Stub Platform class for web
class Platform {
  Platform._();
  static const String pathSeparator = '/';
  static const Map<String, String> environment = {};
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isIOS = false;
  static const bool isAndroid = false;
  static const String operatingSystem = 'web';
}

/// Stub FileStat class for web
class FileStat {
  final DateTime modified;
  final int size;

  FileStat({DateTime? modified, this.size = 0})
      : modified = modified ?? DateTime.now();
}

/// Stub Directory class for web
class Directory extends FileSystemEntity {
  @override
  final String path;
  Directory(this.path);

  Future<bool> exists() async => false;
  Future<Directory> create({bool recursive = false}) async => this;
  Stream<FileSystemEntity> list({bool recursive = false}) => const Stream.empty();
  Future<FileStat> stat() async => FileStat();
}

/// Stub File class for web
class File extends FileSystemEntity {
  @override
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<File> copy(String newPath) async => File(newPath);
  Future<String> readAsString() async => '';
  Future<List<int>> readAsBytes() async => [];
  Future<File> writeAsString(String contents) async => this;
  Future<File> writeAsBytes(List<int> bytes) async => this;
  Directory get parent => Directory(path.substring(0, path.lastIndexOf('/')));
  Future<FileStat> stat() async => FileStat();
}

/// Stub FileSystemEntity class for web
abstract class FileSystemEntity {
  String get path;
}

/// Stub Process class for web
class Process {
  static Future<ProcessResult> run(String executable, List<String> arguments) async {
    return ProcessResult(0, 1, '', 'Process.run not supported on web');
  }
}

/// Stub ProcessResult class for web
class ProcessResult {
  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;

  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
}

/// Get the path separator (always / on web)
String get pathSeparator => '/';

/// Get an environment variable value (not available on web)
String? getEnv(String name) => null;

/// Get the default projects folder path (not applicable on web)
Future<String> getDefaultProjectsFolder() async {
  // On web, projects are stored in IndexedDB, not file system
  return '';
}

/// Check if running on web
bool get isWeb => true;

/// Check if running on macOS
bool get isMacOS => false;

/// Check if running on Windows
bool get isWindows => false;

/// Check if running on iOS
bool get isIOS => false;

/// Check if running on Android
bool get isAndroid => false;

/// Open a folder in the system file explorer (not available on web)
Future<void> openInFileExplorer(String path) async {
  // Not supported on web
}

/// Show a native folder picker dialog (not available on web)
Future<String?> showNativeFolderPicker() async {
  // Not supported on web - use file_picker package instead
  return null;
}

/// Show a native file save dialog (not available on web)
Future<String?> showNativeFileSaveDialog({
  required String defaultName,
  required String fileType,
}) async {
  // Not supported on web - use download API instead
  return null;
}
