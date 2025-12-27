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

  // Export setting keys
  static const String _keyExportFormat = 'export_format'; // 'mp3', 'wav', 'both'
  static const String _keyExportMp3Bitrate = 'export_mp3_bitrate';
  static const String _keyExportWavBitDepth = 'export_wav_bit_depth';
  static const String _keyExportSampleRate = 'export_sample_rate';
  static const String _keyExportNormalize = 'export_normalize';
  static const String _keyExportDither = 'export_dither';
  static const String _keyExportArtist = 'export_artist';
  static const String _keyExportRememberArtist = 'export_remember_artist';

  // Audio device setting keys
  static const String _keyPreferredOutputDevice = 'preferred_output_device';
  static const String _keyPreferredInputDevice = 'preferred_input_device';
  static const String _keySampleRate = 'sample_rate';
  static const String _keyBufferSize = 'buffer_size';

  // MIDI setting keys
  static const String _keyPreferredMidiInput = 'preferred_midi_input';

  // Project setting keys
  static const String _keyContinueWhereLeftOff = 'continue_where_left_off';
  static const String _keyCopySamplesToProject = 'copy_samples_to_project';

  // Limits
  static const int maxRecentProjects = 20;

  // Default values
  static const int defaultUndoLimit = 100;
  static const int defaultAutoSaveMinutes = 5;

  // Export defaults
  static const String defaultExportFormat = 'mp3';
  static const int defaultMp3Bitrate = 320;
  static const int defaultWavBitDepth = 16;
  static const int defaultSampleRate = 44100;
  static const bool defaultNormalize = false;
  static const bool defaultDither = false;

  // Current values
  int _undoLimit = defaultUndoLimit;
  int _autoSaveMinutes = defaultAutoSaveMinutes;
  DateTime? _lastCleanExit;
  List<RecentProject> _recentProjects = [];

  // Export settings
  String _exportFormat = defaultExportFormat;
  int _exportMp3Bitrate = defaultMp3Bitrate;
  int _exportWavBitDepth = defaultWavBitDepth;
  int _exportSampleRate = defaultSampleRate;
  bool _exportNormalize = defaultNormalize;
  bool _exportDither = defaultDither;
  String? _exportArtist;
  bool _rememberArtist = false;

  // Audio device settings
  String? _preferredOutputDevice;
  String? _preferredInputDevice;
  int _sampleRate = 48000; // 44100 or 48000
  int _bufferSize = 256; // 128/256/512/1024

  // MIDI settings
  String? _preferredMidiInput; // null = all devices

  // Project settings
  bool _continueWhereLeftOff = true;
  bool _copySamplesToProject = true;

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

  // ========================================================================
  // Export Settings
  // ========================================================================

  /// Export format: 'mp3', 'wav', or 'both'
  String get exportFormat => _exportFormat;
  set exportFormat(String value) {
    if (_exportFormat != value) {
      _exportFormat = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  /// MP3 bitrate: 128, 192, or 320 kbps
  int get exportMp3Bitrate => _exportMp3Bitrate;
  set exportMp3Bitrate(int value) {
    if (_exportMp3Bitrate != value && [128, 192, 320].contains(value)) {
      _exportMp3Bitrate = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  /// WAV bit depth: 16, 24, or 32
  int get exportWavBitDepth => _exportWavBitDepth;
  set exportWavBitDepth(int value) {
    if (_exportWavBitDepth != value && [16, 24, 32].contains(value)) {
      _exportWavBitDepth = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  /// Sample rate: 44100 or 48000
  int get exportSampleRate => _exportSampleRate;
  set exportSampleRate(int value) {
    if (_exportSampleRate != value && [44100, 48000].contains(value)) {
      _exportSampleRate = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  /// Whether to normalize audio on export
  bool get exportNormalize => _exportNormalize;
  set exportNormalize(bool value) {
    if (_exportNormalize != value) {
      _exportNormalize = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  /// Whether to apply dithering on export
  bool get exportDither => _exportDither;
  set exportDither(bool value) {
    if (_exportDither != value) {
      _exportDither = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  /// Remembered artist name for metadata
  String? get exportArtist => _rememberArtist ? _exportArtist : null;
  set exportArtist(String? value) {
    if (_exportArtist != value) {
      _exportArtist = value;
      if (_rememberArtist) {
        _saveExportSettings();
      }
      notifyListeners();
    }
  }

  /// Whether to remember artist name across sessions
  bool get rememberArtist => _rememberArtist;
  set rememberArtist(bool value) {
    if (_rememberArtist != value) {
      _rememberArtist = value;
      _saveExportSettings();
      notifyListeners();
    }
  }

  // ========================================================================
  // Audio Device Settings
  // ========================================================================

  /// Preferred audio output device
  String? get preferredOutputDevice => _preferredOutputDevice;
  set preferredOutputDevice(String? value) {
    if (_preferredOutputDevice != value) {
      _preferredOutputDevice = value;
      _saveAudioSettings();
      notifyListeners();
    }
  }

  /// Preferred audio input device
  String? get preferredInputDevice => _preferredInputDevice;
  set preferredInputDevice(String? value) {
    if (_preferredInputDevice != value) {
      _preferredInputDevice = value;
      _saveAudioSettings();
      notifyListeners();
    }
  }

  /// Sample rate: 44100 or 48000
  int get sampleRate => _sampleRate;
  set sampleRate(int value) {
    if (_sampleRate != value && [44100, 48000].contains(value)) {
      _sampleRate = value;
      _saveAudioSettings();
      notifyListeners();
    }
  }

  /// Buffer size: 128, 256, 512, or 1024 samples
  int get bufferSize => _bufferSize;
  set bufferSize(int value) {
    if (_bufferSize != value && [128, 256, 512, 1024].contains(value)) {
      _bufferSize = value;
      _saveAudioSettings();
      notifyListeners();
    }
  }

  // ========================================================================
  // MIDI Settings
  // ========================================================================

  /// Preferred MIDI input device (null = all devices)
  String? get preferredMidiInput => _preferredMidiInput;
  set preferredMidiInput(String? value) {
    if (_preferredMidiInput != value) {
      _preferredMidiInput = value;
      _saveMidiSettings();
      notifyListeners();
    }
  }

  // ========================================================================
  // Project Settings
  // ========================================================================

  /// Continue where I left off (restore zoom, scroll, panels)
  bool get continueWhereLeftOff => _continueWhereLeftOff;
  set continueWhereLeftOff(bool value) {
    if (_continueWhereLeftOff != value) {
      _continueWhereLeftOff = value;
      _saveProjectSettings();
      notifyListeners();
    }
  }

  /// Copy imported samples to project folder
  bool get copySamplesToProject => _copySamplesToProject;
  set copySamplesToProject(bool value) {
    if (_copySamplesToProject != value) {
      _copySamplesToProject = value;
      _saveProjectSettings();
      notifyListeners();
    }
  }

  /// Convenience method to set auto-save minutes
  void setAutoSaveMinutes(int value) {
    autoSaveMinutes = value;
  }

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

      // Load export settings
      _exportFormat = _prefs?.getString(_keyExportFormat) ?? defaultExportFormat;
      _exportMp3Bitrate = _prefs?.getInt(_keyExportMp3Bitrate) ?? defaultMp3Bitrate;
      _exportWavBitDepth = _prefs?.getInt(_keyExportWavBitDepth) ?? defaultWavBitDepth;
      _exportSampleRate = _prefs?.getInt(_keyExportSampleRate) ?? defaultSampleRate;
      _exportNormalize = _prefs?.getBool(_keyExportNormalize) ?? defaultNormalize;
      _exportDither = _prefs?.getBool(_keyExportDither) ?? defaultDither;
      _exportArtist = _prefs?.getString(_keyExportArtist);
      _rememberArtist = _prefs?.getBool(_keyExportRememberArtist) ?? false;

      // Load audio device settings
      _preferredOutputDevice = _prefs?.getString(_keyPreferredOutputDevice);
      _preferredInputDevice = _prefs?.getString(_keyPreferredInputDevice);
      _sampleRate = _prefs?.getInt(_keySampleRate) ?? 48000;
      _bufferSize = _prefs?.getInt(_keyBufferSize) ?? 256;

      // Load MIDI settings
      _preferredMidiInput = _prefs?.getString(_keyPreferredMidiInput);

      // Load project settings
      _continueWhereLeftOff = _prefs?.getBool(_keyContinueWhereLeftOff) ?? true;
      _copySamplesToProject = _prefs?.getBool(_keyCopySamplesToProject) ?? true;

      _isLoaded = true;
      debugPrint('[UserSettings] Loaded: undoLimit=$_undoLimit, autoSave=${_autoSaveMinutes}min, recentProjects=${_recentProjects.length}, exportFormat=$_exportFormat');
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

  /// Save export settings to SharedPreferences
  Future<void> _saveExportSettings() async {
    if (_prefs == null) return;

    try {
      await _prefs!.setString(_keyExportFormat, _exportFormat);
      await _prefs!.setInt(_keyExportMp3Bitrate, _exportMp3Bitrate);
      await _prefs!.setInt(_keyExportWavBitDepth, _exportWavBitDepth);
      await _prefs!.setInt(_keyExportSampleRate, _exportSampleRate);
      await _prefs!.setBool(_keyExportNormalize, _exportNormalize);
      await _prefs!.setBool(_keyExportDither, _exportDither);
      await _prefs!.setBool(_keyExportRememberArtist, _rememberArtist);
      if (_rememberArtist && _exportArtist != null) {
        await _prefs!.setString(_keyExportArtist, _exportArtist!);
      } else {
        await _prefs!.remove(_keyExportArtist);
      }
    } catch (e) {
      debugPrint('[UserSettings] Failed to save export settings: $e');
    }
  }

  /// Save audio device settings to SharedPreferences
  Future<void> _saveAudioSettings() async {
    if (_prefs == null) return;

    try {
      if (_preferredOutputDevice != null) {
        await _prefs!.setString(_keyPreferredOutputDevice, _preferredOutputDevice!);
      } else {
        await _prefs!.remove(_keyPreferredOutputDevice);
      }
      if (_preferredInputDevice != null) {
        await _prefs!.setString(_keyPreferredInputDevice, _preferredInputDevice!);
      } else {
        await _prefs!.remove(_keyPreferredInputDevice);
      }
      await _prefs!.setInt(_keySampleRate, _sampleRate);
      await _prefs!.setInt(_keyBufferSize, _bufferSize);
    } catch (e) {
      debugPrint('[UserSettings] Failed to save audio settings: $e');
    }
  }

  /// Save MIDI settings to SharedPreferences
  Future<void> _saveMidiSettings() async {
    if (_prefs == null) return;

    try {
      if (_preferredMidiInput != null) {
        await _prefs!.setString(_keyPreferredMidiInput, _preferredMidiInput!);
      } else {
        await _prefs!.remove(_keyPreferredMidiInput);
      }
    } catch (e) {
      debugPrint('[UserSettings] Failed to save MIDI settings: $e');
    }
  }

  /// Save project settings to SharedPreferences
  Future<void> _saveProjectSettings() async {
    if (_prefs == null) return;

    try {
      await _prefs!.setBool(_keyContinueWhereLeftOff, _continueWhereLeftOff);
      await _prefs!.setBool(_keyCopySamplesToProject, _copySamplesToProject);
    } catch (e) {
      debugPrint('[UserSettings] Failed to save project settings: $e');
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
