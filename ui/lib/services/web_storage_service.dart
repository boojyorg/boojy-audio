// Web Storage Service - IndexedDB-based storage for Boojy Audio Web
//
// Provides persistent storage for projects, audio files, and settings
// using the browser's IndexedDB API.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Database schema version - increment to trigger upgrade
const int _dbVersion = 1;

/// Database name
const String _dbName = 'boojy_audio';

/// Store names
const String _projectsStore = 'projects';
const String _audioFilesStore = 'audio_files';
const String _settingsStore = 'settings';

/// Project metadata stored in IndexedDB
class WebProject {
  final String id;
  final String name;
  final String data; // JSON string of project state
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? uiLayoutJson;

  WebProject({
    required this.id,
    required this.name,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    this.uiLayoutJson,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'uiLayoutJson': uiLayoutJson,
  };

  factory WebProject.fromJson(Map<String, dynamic> json) => WebProject(
    id: json['id'] as String,
    name: json['name'] as String,
    data: json['data'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    uiLayoutJson: json['uiLayoutJson'] as String?,
  );

  WebProject copyWith({
    String? id,
    String? name,
    String? data,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? uiLayoutJson,
  }) => WebProject(
    id: id ?? this.id,
    name: name ?? this.name,
    data: data ?? this.data,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    uiLayoutJson: uiLayoutJson ?? this.uiLayoutJson,
  );
}

/// Audio file metadata stored in IndexedDB
class WebAudioFile {
  final String id;
  final String projectId;
  final String name;
  final Uint8List data;
  final String mimeType;
  final int sampleRate;
  final int channels;
  final double durationSeconds;

  WebAudioFile({
    required this.id,
    required this.projectId,
    required this.name,
    required this.data,
    required this.mimeType,
    this.sampleRate = 48000,
    this.channels = 2,
    this.durationSeconds = 0.0,
  });

  Map<String, dynamic> toJsonWithoutData() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'mimeType': mimeType,
    'sampleRate': sampleRate,
    'channels': channels,
    'durationSeconds': durationSeconds,
    'dataLength': data.length,
  };
}

/// Web storage service using IndexedDB
class WebStorageService {
  static WebStorageService? _instance;
  web.IDBDatabase? _db;
  bool _isInitialized = false;

  WebStorageService._();

  static WebStorageService get instance {
    _instance ??= WebStorageService._();
    return _instance!;
  }

  bool get isInitialized => _isInitialized;

  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;

    final completer = Completer<void>();
    final request = web.window.indexedDB.open(_dbName, _dbVersion);

    request.onupgradeneeded = (web.IDBVersionChangeEvent event) {
      final db = (event.target as web.IDBOpenDBRequest).result as web.IDBDatabase;
      _createStores(db);
    }.toJS;

    request.onsuccess = (web.Event event) {
      _db = (event.target as web.IDBOpenDBRequest).result as web.IDBDatabase;
      _isInitialized = true;
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to open IndexedDB: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  void _createStores(web.IDBDatabase db) {
    // Projects store
    if (!db.objectStoreNames.contains(_projectsStore)) {
      final projectStore = db.createObjectStore(
        _projectsStore,
        web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
      );
      projectStore.createIndex('name', 'name'.toJS, web.IDBIndexParameters(unique: false));
      projectStore.createIndex('updatedAt', 'updatedAt'.toJS, web.IDBIndexParameters(unique: false));
    }

    // Audio files store
    if (!db.objectStoreNames.contains(_audioFilesStore)) {
      final audioStore = db.createObjectStore(
        _audioFilesStore,
        web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
      );
      audioStore.createIndex('projectId', 'projectId'.toJS, web.IDBIndexParameters(unique: false));
      audioStore.createIndex('name', 'name'.toJS, web.IDBIndexParameters(unique: false));
    }

    // Settings store
    if (!db.objectStoreNames.contains(_settingsStore)) {
      db.createObjectStore(
        _settingsStore,
        web.IDBObjectStoreParameters(keyPath: 'key'.toJS),
      );
    }
  }

  // ===========================================================================
  // Project Operations
  // ===========================================================================

  /// Save a project to IndexedDB
  Future<void> saveProject(WebProject project) async {
    _ensureInitialized();
    final completer = Completer<void>();

    final transaction = _db!.transaction(_projectsStore.toJS, 'readwrite');
    final store = transaction.objectStore(_projectsStore);

    final request = store.put(project.toJson().jsify());

    request.onsuccess = (web.Event event) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to save project: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Get a project by ID
  Future<WebProject?> getProject(String id) async {
    _ensureInitialized();
    final completer = Completer<WebProject?>();

    final transaction = _db!.transaction(_projectsStore.toJS, 'readonly');
    final store = transaction.objectStore(_projectsStore);
    final request = store.get(id.toJS);

    request.onsuccess = (web.Event event) {
      final result = request.result;
      if (result != null) {
        final map = (result as JSObject).dartify() as Map<String, dynamic>;
        completer.complete(WebProject.fromJson(map));
      } else {
        completer.complete(null);
      }
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get project: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Get all projects
  Future<List<WebProject>> getAllProjects() async {
    _ensureInitialized();
    final completer = Completer<List<WebProject>>();

    final transaction = _db!.transaction(_projectsStore.toJS, 'readonly');
    final store = transaction.objectStore(_projectsStore);
    final request = store.getAll();

    request.onsuccess = (web.Event event) {
      final results = request.result as JSArray;
      final projects = <WebProject>[];
      for (var i = 0; i < results.length; i++) {
        final item = results[i] as JSObject;
        final map = item.dartify() as Map<String, dynamic>;
        projects.add(WebProject.fromJson(map));
      }
      // Sort by updated date, newest first
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      completer.complete(projects);
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get projects: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Delete a project by ID
  Future<void> deleteProject(String id) async {
    _ensureInitialized();
    final completer = Completer<void>();

    // Delete project
    final transaction = _db!.transaction([_projectsStore.toJS, _audioFilesStore.toJS].toJS, 'readwrite');
    final projectStore = transaction.objectStore(_projectsStore);

    final request = projectStore.delete(id.toJS);

    request.onsuccess = (web.Event event) {
      // Also delete associated audio files
      _deleteAudioFilesForProject(id).then((_) {
        completer.complete();
      }).catchError((e) {
        completer.completeError(e);
      });
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to delete project: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  // ===========================================================================
  // Audio File Operations
  // ===========================================================================

  /// Save an audio file to IndexedDB
  Future<void> saveAudioFile(WebAudioFile audioFile) async {
    _ensureInitialized();
    final completer = Completer<void>();

    final transaction = _db!.transaction(_audioFilesStore.toJS, 'readwrite');
    final store = transaction.objectStore(_audioFilesStore);

    // Convert to a storable format
    final data = {
      'id': audioFile.id,
      'projectId': audioFile.projectId,
      'name': audioFile.name,
      'data': audioFile.data.toJS, // Store as ArrayBuffer
      'mimeType': audioFile.mimeType,
      'sampleRate': audioFile.sampleRate,
      'channels': audioFile.channels,
      'durationSeconds': audioFile.durationSeconds,
    };

    final request = store.put(data.jsify());

    request.onsuccess = (web.Event event) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to save audio file: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Get an audio file by ID
  Future<WebAudioFile?> getAudioFile(String id) async {
    _ensureInitialized();
    final completer = Completer<WebAudioFile?>();

    final transaction = _db!.transaction(_audioFilesStore.toJS, 'readonly');
    final store = transaction.objectStore(_audioFilesStore);
    final request = store.get(id.toJS);

    request.onsuccess = (web.Event event) {
      final result = request.result;
      if (result != null) {
        final map = (result as JSObject).dartify() as Map<String, dynamic>;
        final dataBytes = map['data'] as Uint8List;
        completer.complete(WebAudioFile(
          id: map['id'] as String,
          projectId: map['projectId'] as String,
          name: map['name'] as String,
          data: dataBytes,
          mimeType: map['mimeType'] as String,
          sampleRate: map['sampleRate'] as int? ?? 48000,
          channels: map['channels'] as int? ?? 2,
          durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0.0,
        ));
      } else {
        completer.complete(null);
      }
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get audio file: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Get all audio files for a project
  Future<List<WebAudioFile>> getAudioFilesForProject(String projectId) async {
    _ensureInitialized();
    final completer = Completer<List<WebAudioFile>>();

    final transaction = _db!.transaction(_audioFilesStore.toJS, 'readonly');
    final store = transaction.objectStore(_audioFilesStore);
    final index = store.index('projectId');
    final request = index.getAll(projectId.toJS);

    request.onsuccess = (web.Event event) {
      final results = request.result as JSArray;
      final files = <WebAudioFile>[];
      for (var i = 0; i < results.length; i++) {
        final item = results[i] as JSObject;
        final map = item.dartify() as Map<String, dynamic>;
        final dataBytes = map['data'] as Uint8List;
        files.add(WebAudioFile(
          id: map['id'] as String,
          projectId: map['projectId'] as String,
          name: map['name'] as String,
          data: dataBytes,
          mimeType: map['mimeType'] as String,
          sampleRate: map['sampleRate'] as int? ?? 48000,
          channels: map['channels'] as int? ?? 2,
          durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0.0,
        ));
      }
      completer.complete(files);
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get audio files: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Delete an audio file by ID
  Future<void> deleteAudioFile(String id) async {
    _ensureInitialized();
    final completer = Completer<void>();

    final transaction = _db!.transaction(_audioFilesStore.toJS, 'readwrite');
    final store = transaction.objectStore(_audioFilesStore);
    final request = store.delete(id.toJS);

    request.onsuccess = (web.Event event) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to delete audio file: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Delete all audio files for a project
  Future<void> _deleteAudioFilesForProject(String projectId) async {
    final files = await getAudioFilesForProject(projectId);
    for (final file in files) {
      await deleteAudioFile(file.id);
    }
  }

  // ===========================================================================
  // Settings Operations
  // ===========================================================================

  /// Save a setting
  Future<void> saveSetting(String key, dynamic value) async {
    _ensureInitialized();
    final completer = Completer<void>();

    final transaction = _db!.transaction(_settingsStore.toJS, 'readwrite');
    final store = transaction.objectStore(_settingsStore);

    final data = {'key': key, 'value': jsonEncode(value)};
    final request = store.put(data.jsify());

    request.onsuccess = (web.Event event) {
      completer.complete();
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to save setting: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  /// Get a setting
  Future<dynamic> getSetting(String key) async {
    _ensureInitialized();
    final completer = Completer<dynamic>();

    final transaction = _db!.transaction(_settingsStore.toJS, 'readonly');
    final store = transaction.objectStore(_settingsStore);
    final request = store.get(key.toJS);

    request.onsuccess = (web.Event event) {
      final result = request.result;
      if (result != null) {
        final map = (result as JSObject).dartify() as Map<String, dynamic>;
        completer.complete(jsonDecode(map['value'] as String));
      } else {
        completer.complete(null);
      }
    }.toJS;

    request.onerror = (web.Event event) {
      completer.completeError('Failed to get setting: ${request.error?.message}');
    }.toJS;

    return completer.future;
  }

  // ===========================================================================
  // Utility
  // ===========================================================================

  void _ensureInitialized() {
    if (!_isInitialized || _db == null) {
      throw StateError('WebStorageService not initialized. Call initialize() first.');
    }
  }

  /// Generate a unique ID
  static String generateId() {
    final now = DateTime.now();
    final random = now.microsecondsSinceEpoch.toRadixString(36);
    return '${now.millisecondsSinceEpoch.toRadixString(36)}_$random';
  }

  /// Get database storage estimate (if available)
  Future<Map<String, int>?> getStorageEstimate() async {
    try {
      final storage = web.window.navigator.storage;
      final estimate = await storage.estimate().toDart;
      return {
        'usage': estimate.usage.toInt(),
        'quota': estimate.quota.toInt(),
      };
    } catch (e) {
      // Storage API not available
      return null;
    }
  }

  /// Close the database connection
  void close() {
    _db?.close();
    _db = null;
    _isInitialized = false;
  }
}
