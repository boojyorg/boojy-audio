import 'dart:async';
import 'package:flutter/foundation.dart';
import 'project_manager.dart';
import 'user_settings.dart';

// Conditional import for path_provider (not available on web)
import 'auto_save_service_io.dart' if (dart.library.js_interop) 'auto_save_service_io_web.dart';

/// Auto-save service that periodically saves the project
/// Also manages crash recovery backups
class AutoSaveService extends ChangeNotifier {
  static final AutoSaveService _instance = AutoSaveService._internal();
  factory AutoSaveService() => _instance;
  AutoSaveService._internal();

  Timer? _timer;
  ProjectManager? _projectManager;
  UILayoutData Function()? _getUILayout;

  DateTime? _lastAutoSave;
  Completer<void>? _autoSaveCompleter; // Prevents concurrent auto-saves
  String? _backupDirectory;

  // Max number of rotating auto-save backups
  static const int maxBackups = 3;

  /// Whether auto-save is currently running
  bool get isRunning => _timer != null;

  /// Last auto-save timestamp
  DateTime? get lastAutoSave => _lastAutoSave;

  /// Whether currently performing an auto-save
  bool get isAutoSaving => _autoSaveCompleter != null && !_autoSaveCompleter!.isCompleted;

  /// Initialize the service with project manager reference
  void initialize({
    required ProjectManager projectManager,
    required UILayoutData Function() getUILayout,
  }) {
    _projectManager = projectManager;
    _getUILayout = getUILayout;
  }

  /// Start auto-save with the given interval
  Future<void> start() async {
    final settings = UserSettings();
    final minutes = settings.autoSaveMinutes;

    if (minutes <= 0) {
      stop();
      return;
    }

    // Initialize backup directory
    await _initBackupDirectory();

    // Stop existing timer
    _timer?.cancel();

    // Start new timer
    _timer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => _performAutoSave(),
    );

    notifyListeners();
  }

  /// Stop auto-save
  void stop() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Restart with new settings (call after settings change)
  Future<void> restart() async {
    stop();
    await start();
  }

  /// Perform an auto-save
  Future<void> _performAutoSave() async {
    if (_projectManager == null || _getUILayout == null) {
      return;
    }

    // Use Completer to prevent concurrent auto-saves (race-condition safe)
    if (_autoSaveCompleter != null && !_autoSaveCompleter!.isCompleted) {
      return; // Already saving
    }

    _autoSaveCompleter = Completer<void>();
    notifyListeners();

    try {
      // Save to current project path if exists
      if (_projectManager!.hasProject) {
        final uiLayout = _getUILayout!();
        await _projectManager!.saveProject(uiLayout);
      }

      // Always create a backup for crash recovery
      await _createBackup();

      _lastAutoSave = DateTime.now();
      _autoSaveCompleter!.complete();
    } catch (e) {
      debugPrint('AutoSaveService: Auto-save failed: $e');
      _autoSaveCompleter!.completeError(e);
    } finally {
      notifyListeners();
    }
  }

  /// Initialize the backup directory
  Future<void> _initBackupDirectory() async {
    try {
      _backupDirectory = await getBackupDirectoryPath();
    } catch (e) {
      debugPrint('AutoSaveService: Failed to init backup directory: $e');
    }
  }

  /// Create a backup for crash recovery
  Future<void> _createBackup() async {
    if (_backupDirectory == null || _projectManager == null) return;

    try {
      // Create timestamped backup
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupName = 'autosave_$timestamp.audio';
      final backupPath = '$_backupDirectory/$backupName';

      // Save backup
      final uiLayout = _getUILayout?.call();
      await _projectManager!.saveProjectToPath(backupPath, uiLayout);

      // Create/update crash recovery marker
      await _updateCrashRecoveryMarker(backupPath);

      // Rotate old backups
      await _rotateBackups();
    } catch (e) {
      debugPrint('AutoSaveService: Failed to create backup: $e');
    }
  }

  /// Update crash recovery marker file
  Future<void> _updateCrashRecoveryMarker(String latestBackupPath) async {
    if (_backupDirectory == null) return;

    try {
      await writeFileAsString('$_backupDirectory/crash_recovery.marker', latestBackupPath);
    } catch (e) {
      debugPrint('AutoSaveService: Failed to update recovery marker: $e');
    }
  }

  /// Rotate backups, keeping only the most recent ones
  Future<void> _rotateBackups() async {
    if (_backupDirectory == null) return;

    try {
      final entries = await listDirectory(_backupDirectory!);

      // Find auto-save folders
      final backups = entries
          .where((path) => path.contains('autosave_') && path.endsWith('.audio'))
          .toList();

      // Sort by name (which includes timestamp)
      backups.sort((a, b) => b.compareTo(a));

      // Delete old backups
      if (backups.length > maxBackups) {
        for (var i = maxBackups; i < backups.length; i++) {
          await deleteDirectory(backups[i]);
        }
      }
    } catch (e) {
      debugPrint('AutoSaveService: Failed to rotate backups: $e');
    }
  }

  /// Check for crash recovery backup
  /// Returns the path to the recovery backup if one exists
  Future<String?> checkForRecovery() async {
    await _initBackupDirectory();
    if (_backupDirectory == null) return null;

    try {
      final markerPath = '$_backupDirectory/crash_recovery.marker';
      if (!await fileExists(markerPath)) return null;

      final backupPath = await readFileAsString(markerPath);
      final trimmedPath = backupPath.trim();

      if (await directoryExists(trimmedPath)) {
        return trimmedPath;
      }
    } catch (e) {
      debugPrint('AutoSaveService: Failed to check for recovery: $e');
    }

    return null;
  }

  /// Clear crash recovery marker (call after successful load or recovery)
  Future<void> clearRecoveryMarker() async {
    if (_backupDirectory == null) return;

    try {
      final markerPath = '$_backupDirectory/crash_recovery.marker';
      if (await fileExists(markerPath)) {
        await deleteFile(markerPath);
      }
    } catch (e) {
      debugPrint('AutoSaveService: Failed to clear recovery marker: $e');
    }
  }

  /// Clean up all backups (call on clean exit)
  Future<void> cleanupBackups() async {
    if (_backupDirectory == null) return;

    try {
      // Clear recovery marker
      await clearRecoveryMarker();

      // Optionally delete all auto-save backups on clean exit
      // Uncomment if you want to save disk space:
      // if (await directoryExists(_backupDirectory!)) {
      //   await deleteDirectory(_backupDirectory!);
      // }

    } catch (e) {
      debugPrint('AutoSaveService: Failed to cleanup backups: $e');
    }
  }

  /// Get backup directory path
  String? get backupDirectory => _backupDirectory;

  /// Get list of available backups
  Future<List<BackupInfo>> getAvailableBackups() async {
    await _initBackupDirectory();
    if (_backupDirectory == null) return [];

    try {
      final entries = await listDirectory(_backupDirectory!);

      final backups = <BackupInfo>[];
      for (final entryPath in entries) {
        if (entryPath.endsWith('.audio')) {
          final modified = await getDirectoryModified(entryPath);
          backups.add(BackupInfo(
            path: entryPath,
            name: entryPath.split('/').last,
            modified: modified,
          ));
        }
      }

      // Sort by date, newest first
      backups.sort((a, b) => b.modified.compareTo(a.modified));
      return backups;
    } catch (e) {
      return [];
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Information about a backup file
class BackupInfo {
  final String path;
  final String name;
  final DateTime modified;

  BackupInfo({
    required this.path,
    required this.name,
    required this.modified,
  });

  String get formattedDate {
    return '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} '
        '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
  }
}
