import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/snapshot.dart';

/// Manages project snapshots (version control)
///
/// Snapshots are stored in a "Snapshots" folder within the project directory:
/// MyProject/
///   ├── MyProject.boojy (current version)
///   ├── Samples/
///   └── Snapshots/
///       ├── snapshots.json (metadata)
///       ├── Original.boojy
///       └── Chorus Idea 1.boojy
class SnapshotManager extends ChangeNotifier {
  final String projectFolderPath;

  List<Snapshot> _snapshots = [];

  SnapshotManager(this.projectFolderPath) {
    _loadSnapshots();
  }

  /// Get list of all snapshots
  List<Snapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Get the snapshots folder path
  String get snapshotsFolderPath => path.join(projectFolderPath, 'Snapshots');

  /// Get the metadata file path
  String get _metadataFilePath => path.join(snapshotsFolderPath, 'snapshots.json');

  /// Load snapshots from the metadata file
  Future<void> _loadSnapshots() async {
    try {
      final metadataFile = File(_metadataFilePath);

      if (!await metadataFile.exists()) {
        _snapshots = [];
        notifyListeners();
        return;
      }

      final jsonString = await metadataFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final snapshotsJson = jsonData['snapshots'] as List<dynamic>;

      _snapshots = snapshotsJson
          .map((json) => Snapshot.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by creation date (newest first)
      _snapshots.sort((a, b) => b.created.compareTo(a.created));

      notifyListeners();
      debugPrint('[SnapshotManager] Loaded ${_snapshots.length} snapshots');
    } catch (e) {
      debugPrint('[SnapshotManager] Failed to load snapshots: $e');
      _snapshots = [];
      notifyListeners();
    }
  }

  /// Save snapshots metadata to file
  Future<void> _saveMetadata() async {
    try {
      // Ensure snapshots folder exists
      final snapshotsFolder = Directory(snapshotsFolderPath);
      if (!await snapshotsFolder.exists()) {
        await snapshotsFolder.create(recursive: true);
      }

      final metadataFile = File(_metadataFilePath);
      final jsonData = {
        'version': '1.0',
        'snapshots': _snapshots.map((s) => s.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      await metadataFile.writeAsString(jsonString);

      debugPrint('[SnapshotManager] Saved metadata for ${_snapshots.length} snapshots');
    } catch (e) {
      debugPrint('[SnapshotManager] Failed to save metadata: $e');
      rethrow;
    }
  }

  /// Create a new snapshot from the current project file
  ///
  /// Returns the created snapshot, or null if failed
  Future<Snapshot?> createSnapshot({
    required String name,
    String? note,
    required String currentProjectFilePath,
  }) async {
    try {
      // Create the snapshot object
      final snapshot = Snapshot.create(name: name, note: note);

      // Ensure snapshots folder exists
      final snapshotsFolder = Directory(snapshotsFolderPath);
      if (!await snapshotsFolder.exists()) {
        await snapshotsFolder.create(recursive: true);
      }

      // Copy current project file to snapshots folder
      final currentFile = File(currentProjectFilePath);
      final snapshotFilePath = path.join(snapshotsFolderPath, snapshot.fileName);

      await currentFile.copy(snapshotFilePath);

      // Add to list and save metadata
      _snapshots.insert(0, snapshot); // Add at beginning (newest first)
      await _saveMetadata();

      notifyListeners();
      debugPrint('[SnapshotManager] Created snapshot: ${snapshot.name}');

      return snapshot;
    } catch (e) {
      debugPrint('[SnapshotManager] Failed to create snapshot: $e');
      return null;
    }
  }

  /// Load a snapshot (restore it as the current project)
  ///
  /// This copies the snapshot file over the current project file
  /// Returns true if successful
  Future<bool> loadSnapshot({
    required Snapshot snapshot,
    required String currentProjectFilePath,
  }) async {
    try {
      final snapshotFilePath = path.join(snapshotsFolderPath, snapshot.fileName);
      final snapshotFile = File(snapshotFilePath);

      if (!await snapshotFile.exists()) {
        debugPrint('[SnapshotManager] Snapshot file not found: ${snapshot.fileName}');
        return false;
      }

      // Copy snapshot file to current project file
      await snapshotFile.copy(currentProjectFilePath);

      debugPrint('[SnapshotManager] Loaded snapshot: ${snapshot.name}');
      return true;
    } catch (e) {
      debugPrint('[SnapshotManager] Failed to load snapshot: $e');
      return false;
    }
  }

  /// Delete a snapshot
  ///
  /// Returns true if successful
  Future<bool> deleteSnapshot(Snapshot snapshot) async {
    try {
      final snapshotFilePath = path.join(snapshotsFolderPath, snapshot.fileName);
      final snapshotFile = File(snapshotFilePath);

      // Delete the file if it exists
      if (await snapshotFile.exists()) {
        await snapshotFile.delete();
      }

      // Remove from list and save metadata
      _snapshots.removeWhere((s) => s.id == snapshot.id);
      await _saveMetadata();

      notifyListeners();
      debugPrint('[SnapshotManager] Deleted snapshot: ${snapshot.name}');

      return true;
    } catch (e) {
      debugPrint('[SnapshotManager] Failed to delete snapshot: $e');
      return false;
    }
  }

  /// Get a snapshot by ID
  Snapshot? getSnapshotById(String id) {
    try {
      return _snapshots.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Check if a snapshot name already exists
  bool isNameTaken(String name) {
    return _snapshots.any((s) => s.name.toLowerCase() == name.toLowerCase());
  }

  /// Get the number of snapshots
  int get count => _snapshots.length;

  /// Refresh snapshots from disk
  Future<void> refresh() async {
    await _loadSnapshots();
  }
}
