// Native platform IO utilities for auto-save service
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Get the application support directory path for backups
Future<String?> getBackupDirectoryPath() async {
  try {
    final appSupport = await getApplicationSupportDirectory();
    final backupDir = Directory('${appSupport.path}/Backups');

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    return backupDir.path;
  } catch (e) {
    return null;
  }
}

/// Check if a directory exists
Future<bool> directoryExists(String path) async {
  return Directory(path).exists();
}

/// Create a directory
Future<void> createDirectory(String path) async {
  await Directory(path).create(recursive: true);
}

/// Delete a directory recursively
Future<void> deleteDirectory(String path) async {
  await Directory(path).delete(recursive: true);
}

/// List directory entries
Future<List<String>> listDirectory(String path) async {
  final dir = Directory(path);
  final entries = await dir.list().toList();
  return entries.map((e) => e.path).toList();
}

/// Get directory modified time
Future<DateTime> getDirectoryModified(String path) async {
  final stat = await Directory(path).stat();
  return stat.modified;
}

/// Check if a file exists
Future<bool> fileExists(String path) async {
  return File(path).exists();
}

/// Read file as string
Future<String> readFileAsString(String path) async {
  return File(path).readAsString();
}

/// Write string to file
Future<void> writeFileAsString(String path, String contents) async {
  await File(path).writeAsString(contents);
}

/// Delete a file
Future<void> deleteFile(String path) async {
  await File(path).delete();
}
