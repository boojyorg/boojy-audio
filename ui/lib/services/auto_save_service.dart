import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/logger.dart';
import 'project_manager.dart';

import 'auto_save_service_io.dart';

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

  /// Auto-save is always on, at a fixed interval
  static const Duration interval = Duration(minutes: 5);

  /// Whether auto-save is currently running
  bool get isRunning => _timer != null;

  /// Last auto-save timestamp
  DateTime? get lastAutoSave => _lastAutoSave;

  /// Whether currently performing an auto-save
  bool get isAutoSaving =>
      _autoSaveCompleter != null && !_autoSaveCompleter!.isCompleted;

  /// Initialize the service with project manager reference
  void initialize({
    required ProjectManager projectManager,
    required UILayoutData Function() getUILayout,
  }) {
    _projectManager = projectManager;
    _getUILayout = getUILayout;
  }

  /// Start auto-save (every [interval])
  Future<void> start() async {
    // Initialize backup directory
    await _initBackupDirectory();

    // Stop existing timer
    _timer?.cancel();

    // Start new timer
    _timer = Timer.periodic(interval, (_) => _performAutoSave());

    notifyListeners();
  }

  /// Stop auto-save
  void stop() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
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
      Log.e('AutoSaveService: Auto-save failed: $e');
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
      Log.e('AutoSaveService: Failed to init backup directory: $e');
    }
  }

  /// Create a backup for crash recovery
  Future<void> _createBackup() async {
    final directory = _backupDirectory;
    final projectManager = _projectManager;
    if (directory == null || projectManager == null) return;

    // Never repoint the project at the backup file — doing so would silently
    // redirect every subsequent save into the backup folder.
    await writeBackup(
      directory,
      (path) => projectManager.saveProjectToPath(
        path,
        _getUILayout?.call(),
        updateCurrentPath: false,
      ),
    );
  }

  /// Save a timestamped backup into [directory] with [save], and point crash
  /// recovery at it. Returns whether the backup worked.
  ///
  /// A backup that fails changes nothing: the marker keeps pointing at the
  /// last backup that worked (so recovery still offers it), older backups are
  /// kept, and whatever the failed save left behind is removed.
  @visibleForTesting
  Future<bool> writeBackup(
    String directory,
    Future<ProjectResult> Function(String path) save, {
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now())
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final backupPath = '$directory/autosave_$timestamp.audio';

    try {
      final existedBefore = await directoryExists(backupPath);
      final result = await save(backupPath);
      if (!result.success) {
        Log.e('AutoSaveService: Backup failed: ${result.message}');
        if (!existedBefore && await directoryExists(backupPath)) {
          await deleteDirectory(backupPath);
        }
        return false;
      }

      await _updateCrashRecoveryMarker(directory, backupPath);
      await _rotateBackups(directory);
      return true;
    } catch (e) {
      Log.e('AutoSaveService: Failed to create backup: $e');
      return false;
    }
  }

  /// Update crash recovery marker file
  Future<void> _updateCrashRecoveryMarker(
    String directory,
    String latestBackupPath,
  ) async {
    try {
      await writeFileAsString(
        '$directory/crash_recovery.marker',
        latestBackupPath,
      );
    } catch (e) {
      Log.e('AutoSaveService: Failed to update recovery marker: $e');
    }
  }

  /// Rotate backups, keeping only the most recent ones
  Future<void> _rotateBackups(String directory) async {
    try {
      final entries = await listDirectory(directory);

      // Find auto-save folders
      final backups = entries
          .where(
            (path) => path.contains('autosave_') && path.endsWith('.audio'),
          )
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
      Log.e('AutoSaveService: Failed to rotate backups: $e');
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
      Log.e('AutoSaveService: Failed to check for recovery: $e');
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
      Log.e('AutoSaveService: Failed to clear recovery marker: $e');
    }
  }

  /// Clean up all backups (call on clean exit)
  Future<void> cleanupBackups() async {
    if (_backupDirectory == null) return;

    try {
      // Clear recovery marker
      await clearRecoveryMarker();
    } catch (e) {
      Log.e('AutoSaveService: Failed to cleanup backups: $e');
    }
  }

  /// Get backup directory path
  String? get backupDirectory => _backupDirectory;

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

  BackupInfo({required this.path, required this.name, required this.modified});

  String get formattedDate {
    return '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} '
        '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
  }
}
