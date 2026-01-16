// Web platform IO utilities for auto-save service
// On web, auto-save uses IndexedDB via web_storage_service instead of file system

/// Get the application support directory path for backups
/// Returns null on web - use IndexedDB instead
Future<String?> getBackupDirectoryPath() async {
  // Not supported on web - auto-save will use IndexedDB
  return null;
}

/// Check if a directory exists (always false on web)
Future<bool> directoryExists(String path) async {
  return false;
}

/// Create a directory (no-op on web)
Future<void> createDirectory(String path) async {
  // No-op on web
}

/// Delete a directory recursively (no-op on web)
Future<void> deleteDirectory(String path) async {
  // No-op on web
}

/// List directory entries (empty on web)
Future<List<String>> listDirectory(String path) async {
  return [];
}

/// Get directory modified time (returns now on web)
Future<DateTime> getDirectoryModified(String path) async {
  return DateTime.now();
}

/// Check if a file exists (always false on web)
Future<bool> fileExists(String path) async {
  return false;
}

/// Read file as string (returns empty on web)
Future<String> readFileAsString(String path) async {
  return '';
}

/// Write string to file (no-op on web)
Future<void> writeFileAsString(String path, String contents) async {
  // No-op on web
}

/// Delete a file (no-op on web)
Future<void> deleteFile(String path) async {
  // No-op on web
}
