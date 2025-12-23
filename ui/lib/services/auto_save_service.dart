import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'project_manager.dart';
import 'user_settings.dart';

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
  bool _isAutoSaving = false;
  String? _backupDirectory;

  // Max number of rotating auto-save backups
  static const int maxBackups = 3;

  /// Whether auto-save is currently running
  bool get isRunning => _timer != null;

  /// Last auto-save timestamp
  DateTime? get lastAutoSave => _lastAutoSave;

  /// Whether currently performing an auto-save
  bool get isAutoSaving => _isAutoSaving;

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
      debugPrint('[AutoSave] Disabled (interval=0)');
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

    debugPrint('[AutoSave] Started with ${minutes}min interval');
    notifyListeners();
  }

  /// Stop auto-save
  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[AutoSave] Stopped');
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
      debugPrint('[AutoSave] Not initialized');
      return;
    }

    if (_isAutoSaving) {
      debugPrint('[AutoSave] Already in progress, skipping');
      return;
    }

    _isAutoSaving = true;
    notifyListeners();

    try {
      // Save to current project path if exists
      if (_projectManager!.hasProject) {
        final uiLayout = _getUILayout!();
        await _projectManager!.saveProject(uiLayout);
        debugPrint('[AutoSave] Saved to project: ${_projectManager!.currentPath}');
      }

      // Always create a backup for crash recovery
      await _createBackup();

      _lastAutoSave = DateTime.now();
      debugPrint('[AutoSave] Complete at $_lastAutoSave');
    } catch (e) {
      debugPrint('[AutoSave] Failed: $e');
    } finally {
      _isAutoSaving = false;
      notifyListeners();
    }
  }

  /// Initialize the backup directory
  Future<void> _initBackupDirectory() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final backupDir = Directory('${appSupport.path}/Backups');

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      _backupDirectory = backupDir.path;
      debugPrint('[AutoSave] Backup directory: $_backupDirectory');
    } catch (e) {
      debugPrint('[AutoSave] Failed to init backup directory: $e');
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
      debugPrint('[AutoSave] Backup created: $backupPath');

      // Create/update crash recovery marker
      await _updateCrashRecoveryMarker(backupPath);

      // Rotate old backups
      await _rotateBackups();
    } catch (e) {
      debugPrint('[AutoSave] Backup failed: $e');
    }
  }

  /// Update crash recovery marker file
  Future<void> _updateCrashRecoveryMarker(String latestBackupPath) async {
    if (_backupDirectory == null) return;

    try {
      final markerFile = File('$_backupDirectory/crash_recovery.marker');
      await markerFile.writeAsString(latestBackupPath);
    } catch (e) {
      debugPrint('[AutoSave] Failed to update recovery marker: $e');
    }
  }

  /// Rotate backups, keeping only the most recent ones
  Future<void> _rotateBackups() async {
    if (_backupDirectory == null) return;

    try {
      final backupDir = Directory(_backupDirectory!);
      final entries = await backupDir.list().toList();

      // Find auto-save folders
      final backups = entries
          .whereType<Directory>()
          .where((d) => d.path.contains('autosave_') && d.path.endsWith('.audio'))
          .toList();

      // Sort by name (which includes timestamp)
      backups.sort((a, b) => b.path.compareTo(a.path));

      // Delete old backups
      if (backups.length > maxBackups) {
        for (var i = maxBackups; i < backups.length; i++) {
          await backups[i].delete(recursive: true);
          debugPrint('[AutoSave] Deleted old backup: ${backups[i].path}');
        }
      }
    } catch (e) {
      debugPrint('[AutoSave] Backup rotation failed: $e');
    }
  }

  /// Check for crash recovery backup
  /// Returns the path to the recovery backup if one exists
  Future<String?> checkForRecovery() async {
    await _initBackupDirectory();
    if (_backupDirectory == null) return null;

    try {
      final markerFile = File('$_backupDirectory/crash_recovery.marker');
      if (!await markerFile.exists()) return null;

      final backupPath = await markerFile.readAsString();
      final backupDir = Directory(backupPath.trim());

      if (await backupDir.exists()) {
        debugPrint('[AutoSave] Found recovery backup: $backupPath');
        return backupPath.trim();
      }
    } catch (e) {
      debugPrint('[AutoSave] Recovery check failed: $e');
    }

    return null;
  }

  /// Clear crash recovery marker (call after successful load or recovery)
  Future<void> clearRecoveryMarker() async {
    if (_backupDirectory == null) return;

    try {
      final markerFile = File('$_backupDirectory/crash_recovery.marker');
      if (await markerFile.exists()) {
        await markerFile.delete();
        debugPrint('[AutoSave] Cleared recovery marker');
      }
    } catch (e) {
      debugPrint('[AutoSave] Failed to clear recovery marker: $e');
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
      // final backupDir = Directory(_backupDirectory!);
      // if (await backupDir.exists()) {
      //   await backupDir.delete(recursive: true);
      // }

      debugPrint('[AutoSave] Cleanup complete');
    } catch (e) {
      debugPrint('[AutoSave] Cleanup failed: $e');
    }
  }

  /// Get backup directory path
  String? get backupDirectory => _backupDirectory;

  /// Get list of available backups
  Future<List<BackupInfo>> getAvailableBackups() async {
    await _initBackupDirectory();
    if (_backupDirectory == null) return [];

    try {
      final backupDir = Directory(_backupDirectory!);
      final entries = await backupDir.list().toList();

      final backups = <BackupInfo>[];
      for (final entry in entries) {
        if (entry is Directory && entry.path.endsWith('.audio')) {
          final stat = await entry.stat();
          backups.add(BackupInfo(
            path: entry.path,
            name: entry.path.split('/').last,
            modified: stat.modified,
          ));
        }
      }

      // Sort by date, newest first
      backups.sort((a, b) => b.modified.compareTo(a.modified));
      return backups;
    } catch (e) {
      debugPrint('[AutoSave] Failed to list backups: $e');
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
