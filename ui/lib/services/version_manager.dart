import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/project_version.dart';
import '../models/version_type.dart';

/// Manages project versions (evolved from SnapshotManager)
///
/// Versions are stored in a "Snapshots" folder within the project directory:
/// MyProject/
///   ├── MyProject.boojy (current version)
///   ├── Samples/
///   └── Snapshots/
///       ├── versions.json (metadata)
///       ├── Demo 1.boojy
///       └── Mix 2.boojy
class VersionManager extends ChangeNotifier {
  final String projectFolderPath;

  List<ProjectVersion> _versions = [];
  int _currentVersionNumber = 0; // 0 means working on unsaved/initial version
  int _nextVersionNumber = 1;

  VersionManager(this.projectFolderPath) {
    _loadVersions();
  }

  /// Get list of all versions (sorted newest first)
  List<ProjectVersion> get versions => List.unmodifiable(_versions);

  /// Get the versions folder path (using "Snapshots" for backward compatibility)
  String get versionsFolderPath => path.join(projectFolderPath, 'Snapshots');

  /// Get the new metadata file path
  String get _metadataFilePath => path.join(versionsFolderPath, 'versions.json');

  /// Get the old metadata file path (for migration)
  String get _oldMetadataFilePath => path.join(versionsFolderPath, 'snapshots.json');

  /// Get the next version number that will be assigned
  int get nextVersionNumber => _nextVersionNumber;

  /// Get the current working version number (0 if none)
  int get currentVersionNumber => _currentVersionNumber;

  /// Get the current working version (null if working on initial/unsaved)
  ProjectVersion? get currentVersion {
    if (_currentVersionNumber == 0) return null;
    try {
      return _versions.firstWhere((v) => v.versionNumber == _currentVersionNumber);
    } catch (e) {
      return null;
    }
  }

  /// Get the number of versions
  int get count => _versions.length;

  /// Reload versions from disk (public method for external callers)
  Future<void> reload() => _loadVersions();

  /// Load versions from the metadata file (with migration from old format)
  Future<void> _loadVersions() async {
    try {
      final metadataFile = File(_metadataFilePath);
      final oldMetadataFile = File(_oldMetadataFilePath);

      // Check if we need to migrate from old format
      if (!await metadataFile.exists() && await oldMetadataFile.exists()) {
        await _migrateFromOldFormat();
        return;
      }

      if (!await metadataFile.exists()) {
        _versions = [];
        _nextVersionNumber = 1;
        _currentVersionNumber = 0;
        notifyListeners();
        return;
      }

      final jsonString = await metadataFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final versionsJson = jsonData['versions'] as List<dynamic>;

      _versions = versionsJson
          .map((json) => ProjectVersion.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by creation date (newest first)
      _versions.sort((a, b) => b.created.compareTo(a.created));

      // Restore next version number and current version
      _nextVersionNumber = jsonData['nextVersionNumber'] as int? ??
          (_versions.isEmpty ? 1 : _versions.map((v) => v.versionNumber).reduce((a, b) => a > b ? a : b) + 1);
      _currentVersionNumber = jsonData['currentVersionNumber'] as int? ?? 0;

      notifyListeners();
    } catch (e) {
      _versions = [];
      _nextVersionNumber = 1;
      _currentVersionNumber = 0;
      notifyListeners();
    }
  }

  /// Migrate from old snapshots.json format to new versions.json
  Future<void> _migrateFromOldFormat() async {
    try {
      final oldMetadataFile = File(_oldMetadataFilePath);
      final jsonString = await oldMetadataFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final snapshotsJson = jsonData['snapshots'] as List<dynamic>;

      // Convert old snapshots to versions, sorted by creation date
      final oldSnapshots = snapshotsJson
          .map((json) => json as Map<String, dynamic>)
          .toList();

      // Sort by created date (oldest first for numbering)
      oldSnapshots.sort((a, b) {
        final aDate = DateTime.parse(a['created'] as String);
        final bDate = DateTime.parse(b['created'] as String);
        return aDate.compareTo(bDate);
      });

      // Assign version numbers in order
      _versions = [];
      for (int i = 0; i < oldSnapshots.length; i++) {
        final json = oldSnapshots[i];
        _versions.add(ProjectVersion.fromJson(json, fallbackVersionNumber: i + 1));
      }

      // Sort newest first for display
      _versions.sort((a, b) => b.created.compareTo(a.created));

      _nextVersionNumber = _versions.isEmpty ? 1 : _versions.length + 1;
      _currentVersionNumber = 0;

      // Save in new format
      await _saveMetadata();

      // Optionally delete old file
      // await oldMetadataFile.delete();

      notifyListeners();
    } catch (e) {
      _versions = [];
      _nextVersionNumber = 1;
      _currentVersionNumber = 0;
      notifyListeners();
    }
  }

  /// Save versions metadata to file
  Future<void> _saveMetadata() async {
    try {
      // Ensure versions folder exists
      final versionsFolder = Directory(versionsFolderPath);
      if (!await versionsFolder.exists()) {
        await versionsFolder.create(recursive: true);
      }

      final metadataFile = File(_metadataFilePath);
      final jsonData = {
        'version': '2.0',
        'nextVersionNumber': _nextVersionNumber,
        'currentVersionNumber': _currentVersionNumber,
        'versions': _versions.map((v) => v.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      await metadataFile.writeAsString(jsonString);

    } catch (e) {
      rethrow;
    }
  }

  /// Create a new version from the current project file
  ///
  /// Returns the created version, or null if failed.
  /// After creation, automatically switches to the new version.
  Future<ProjectVersion?> createVersion({
    required String name,
    String? note,
    required VersionType versionType,
    required String currentProjectFilePath,
  }) async {
    try {
      // Create the version object with next global number
      final version = ProjectVersion.create(
        name: name,
        note: note,
        versionType: versionType,
        versionNumber: _nextVersionNumber,
      );

      // Ensure versions folder exists
      final versionsFolder = Directory(versionsFolderPath);
      if (!await versionsFolder.exists()) {
        await versionsFolder.create(recursive: true);
      }

      // Copy current project file to versions folder
      final currentFile = File(currentProjectFilePath);
      final versionFilePath = path.join(versionsFolderPath, version.fileName);

      await currentFile.copy(versionFilePath);

      // Add to list (newest first)
      _versions.insert(0, version);

      // Update tracking
      _currentVersionNumber = _nextVersionNumber;
      _nextVersionNumber++;

      await _saveMetadata();

      notifyListeners();

      return version;
    } catch (e) {
      return null;
    }
  }

  /// Switch to a different version (restore it as the current project)
  ///
  /// This copies the version file over the current project file
  /// Returns true if successful
  Future<bool> switchToVersion({
    required ProjectVersion version,
    required String currentProjectFilePath,
  }) async {
    try {
      final versionFilePath = path.join(versionsFolderPath, version.fileName);
      final versionFile = File(versionFilePath);

      if (!await versionFile.exists()) {
        return false;
      }

      // Copy version file to current project file
      await versionFile.copy(currentProjectFilePath);

      // Update current version tracking
      _currentVersionNumber = version.versionNumber;
      await _saveMetadata();

      notifyListeners();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a version
  ///
  /// Returns true if successful
  Future<bool> deleteVersion(ProjectVersion version) async {
    try {
      final versionFilePath = path.join(versionsFolderPath, version.fileName);
      final versionFile = File(versionFilePath);

      // Delete the file if it exists
      if (await versionFile.exists()) {
        await versionFile.delete();
      }

      // Remove from list and save metadata
      _versions.removeWhere((v) => v.id == version.id);

      // If we deleted the current version, clear current tracking
      if (_currentVersionNumber == version.versionNumber) {
        _currentVersionNumber = 0;
      }

      await _saveMetadata();

      notifyListeners();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get a version by ID
  ProjectVersion? getVersionById(String id) {
    try {
      return _versions.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Check if a version name already exists
  bool isNameTaken(String name) {
    return _versions.any((v) => v.name.toLowerCase() == name.toLowerCase());
  }

  /// Get suggested name for a new version of the given type
  String getSuggestedName(VersionType type) {
    return type.displayLabel(_nextVersionNumber);
  }

  /// Refresh versions from disk
  Future<void> refresh() async {
    await _loadVersions();
  }

  /// Clear current version tracking (e.g., after creating new project)
  void clearCurrentVersion() {
    _currentVersionNumber = 0;
    notifyListeners();
  }
}

/// Backward compatibility alias
@Deprecated('Use VersionManager instead')
typedef SnapshotManager = VersionManager;
