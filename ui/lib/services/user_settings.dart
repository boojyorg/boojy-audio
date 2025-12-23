import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recent project entry
class RecentProject {
  final String path;
  final String name;
  final DateTime openedAt;

  RecentProject({
    required this.path,
    required this.name,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'openedAt': openedAt.toIso8601String(),
  };

  factory RecentProject.fromJson(Map<String, dynamic> json) {
    return RecentProject(
      path: json['path'] as String,
      name: json['name'] as String,
      openedAt: DateTime.parse(json['openedAt'] as String),
    );
  }
}

/// User settings service for persistent app preferences
/// Singleton that manages user-configurable settings
class UserSettings extends ChangeNotifier {
  static final UserSettings _instance = UserSettings._internal();
  factory UserSettings() => _instance;
  UserSettings._internal();

  SharedPreferences? _prefs;
  bool _isLoaded = false;

  // Setting keys
  static const String _keyUndoLimit = 'undo_limit';
  static const String _keyAutoSaveMinutes = 'auto_save_minutes';
  static const String _keyLastCleanExit = 'last_clean_exit';
  static const String _keyRecentProjects = 'recent_projects';

  // Limits
  static const int maxRecentProjects = 20;

  // Default values
  static const int defaultUndoLimit = 100;
  static const int defaultAutoSaveMinutes = 5;

  // Current values
  int _undoLimit = defaultUndoLimit;
  int _autoSaveMinutes = defaultAutoSaveMinutes;
  DateTime? _lastCleanExit;
  List<RecentProject> _recentProjects = [];

  /// Whether settings have been loaded
  bool get isLoaded => _isLoaded;

  /// Maximum undo history steps (10-500)
  int get undoLimit => _undoLimit;
  set undoLimit(int value) {
    final clamped = value.clamp(10, 500);
    if (_undoLimit != clamped) {
      _undoLimit = clamped;
      _save();
      notifyListeners();
    }
  }

  /// Auto-save interval in minutes (0 = disabled)
  int get autoSaveMinutes => _autoSaveMinutes;
  set autoSaveMinutes(int value) {
    final clamped = value.clamp(0, 60);
    if (_autoSaveMinutes != clamped) {
      _autoSaveMinutes = clamped;
      _save();
      notifyListeners();
    }
  }

  /// Last clean exit timestamp (for crash detection)
  DateTime? get lastCleanExit => _lastCleanExit;

  /// Recent projects list (most recent first)
  List<RecentProject> get recentProjects => List.unmodifiable(_recentProjects);

  /// Load settings from SharedPreferences
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      _prefs = await SharedPreferences.getInstance();

      _undoLimit = _prefs?.getInt(_keyUndoLimit) ?? defaultUndoLimit;
      _autoSaveMinutes = _prefs?.getInt(_keyAutoSaveMinutes) ?? defaultAutoSaveMinutes;

      final exitTimestamp = _prefs?.getInt(_keyLastCleanExit);
      if (exitTimestamp != null) {
        _lastCleanExit = DateTime.fromMillisecondsSinceEpoch(exitTimestamp);
      }

      // Load recent projects
      final recentJson = _prefs?.getString(_keyRecentProjects);
      if (recentJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(recentJson);
          _recentProjects = decoded
              .map((json) => RecentProject.fromJson(json as Map<String, dynamic>))
              .toList();
        } catch (e) {
          debugPrint('[UserSettings] Failed to parse recent projects: $e');
          _recentProjects = [];
        }
      }

      _isLoaded = true;
      debugPrint('[UserSettings] Loaded: undoLimit=$_undoLimit, autoSave=${_autoSaveMinutes}min, recentProjects=${_recentProjects.length}');
      notifyListeners();
    } catch (e) {
      debugPrint('[UserSettings] Failed to load: $e');
      _isLoaded = true; // Use defaults
    }
  }

  /// Save current settings to SharedPreferences
  Future<void> _save() async {
    if (_prefs == null) return;

    try {
      await _prefs!.setInt(_keyUndoLimit, _undoLimit);
      await _prefs!.setInt(_keyAutoSaveMinutes, _autoSaveMinutes);
    } catch (e) {
      debugPrint('[UserSettings] Failed to save: $e');
    }
  }

  /// Save recent projects to SharedPreferences
  Future<void> _saveRecentProjects() async {
    if (_prefs == null) return;

    try {
      final jsonList = _recentProjects.map((p) => p.toJson()).toList();
      await _prefs!.setString(_keyRecentProjects, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[UserSettings] Failed to save recent projects: $e');
    }
  }

  /// Add a project to the recent list (moves to top if already exists)
  Future<void> addRecentProject(String path, String name) async {
    // Remove if already exists (we'll re-add at top)
    _recentProjects.removeWhere((p) => p.path == path);

    // Add at the beginning (most recent first)
    _recentProjects.insert(0, RecentProject(
      path: path,
      name: name,
      openedAt: DateTime.now(),
    ));

    // Enforce max limit
    while (_recentProjects.length > maxRecentProjects) {
      _recentProjects.removeLast();
    }

    await _saveRecentProjects();
    notifyListeners();
  }

  /// Remove a specific project from recents (e.g., if file no longer exists)
  Future<void> removeRecentProject(String path) async {
    _recentProjects.removeWhere((p) => p.path == path);
    await _saveRecentProjects();
    notifyListeners();
  }

  /// Clear all recent projects
  Future<void> clearRecentProjects() async {
    _recentProjects.clear();
    await _saveRecentProjects();
    notifyListeners();
  }

  /// Record a clean exit (call on app shutdown)
  Future<void> recordCleanExit() async {
    if (_prefs == null) return;

    try {
      await _prefs!.setInt(_keyLastCleanExit, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[UserSettings] Recorded clean exit');
    } catch (e) {
      debugPrint('[UserSettings] Failed to record clean exit: $e');
    }
  }

  /// Clear clean exit marker (call on app start, after crash check)
  Future<void> clearCleanExit() async {
    if (_prefs == null) return;

    try {
      await _prefs!.remove(_keyLastCleanExit);
      _lastCleanExit = null;
    } catch (e) {
      debugPrint('[UserSettings] Failed to clear clean exit: $e');
    }
  }

  /// Check if the app crashed last time (no clean exit recorded)
  bool get didCrashLastTime {
    // If we have a clean exit marker, the app exited normally
    // If no marker, the app likely crashed
    return _lastCleanExit == null;
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    _undoLimit = defaultUndoLimit;
    _autoSaveMinutes = defaultAutoSaveMinutes;
    await _save();
    notifyListeners();
  }

  /// Get available auto-save interval options
  static List<AutoSaveOption> get autoSaveOptions => [
    AutoSaveOption(0, 'Off'),
    AutoSaveOption(1, '1 minute'),
    AutoSaveOption(2, '2 minutes'),
    AutoSaveOption(5, '5 minutes'),
    AutoSaveOption(10, '10 minutes'),
    AutoSaveOption(15, '15 minutes'),
  ];
}

/// Helper class for auto-save dropdown options
class AutoSaveOption {
  final int minutes;
  final String label;

  AutoSaveOption(this.minutes, this.label);
}
