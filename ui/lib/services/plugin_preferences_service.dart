import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Display mode for VST3 plugin UI
enum PluginDisplayMode { embedded, floating }

/// Preference settings for a single plugin
class PluginPreference {
  final PluginDisplayMode displayMode;
  final double? windowX;
  final double? windowY;

  const PluginPreference({
    this.displayMode = PluginDisplayMode.embedded,
    this.windowX,
    this.windowY,
  });

  Map<String, dynamic> toJson() => {
        'displayMode': displayMode.name,
        if (windowX != null) 'windowX': windowX,
        if (windowY != null) 'windowY': windowY,
      };

  factory PluginPreference.fromJson(Map<String, dynamic> json) {
    return PluginPreference(
      displayMode: PluginDisplayMode.values.firstWhere(
        (e) => e.name == json['displayMode'],
        orElse: () => PluginDisplayMode.embedded,
      ),
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
    );
  }

  PluginPreference copyWith({
    PluginDisplayMode? displayMode,
    double? windowX,
    double? windowY,
  }) {
    return PluginPreference(
      displayMode: displayMode ?? this.displayMode,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
    );
  }
}

/// Service for persisting VST3 plugin UI preferences
/// Stores per-plugin settings like display mode (embedded/floating) and window positions
class PluginPreferencesService {
  static const _fileName = 'plugin-preferences.json';
  static Map<String, PluginPreference> _preferences = {};
  static bool _initialized = false;

  /// Load preferences from disk
  static Future<void> load() async {
    if (_initialized) return;

    try {
      final file = await _getPreferencesFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;

        final pluginPrefs = json['pluginPreferences'] as Map<String, dynamic>?;
        if (pluginPrefs != null) {
          _preferences = pluginPrefs.map(
            (key, value) => MapEntry(
              key,
              PluginPreference.fromJson(value as Map<String, dynamic>),
            ),
          );
        }

      } else {
      }

      _initialized = true;
    } catch (e) {
      _preferences = {};
      _initialized = true;
    }
  }

  /// Save preferences to disk
  static Future<void> save() async {
    try {
      final file = await _getPreferencesFile();

      final json = {
        'pluginPreferences': _preferences.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
      );

    } catch (e) {
    }
  }

  /// Get the preferences file path
  static Future<File> _getPreferencesFile() async {
    final appSupport = await getApplicationSupportDirectory();
    return File('${appSupport.path}/$_fileName');
  }

  /// Get preference for a plugin by name
  static PluginPreference? getPreference(String pluginName) {
    return _preferences[pluginName];
  }

  /// Set display mode preference for a plugin
  static Future<void> setDisplayMode(
    String pluginName,
    PluginDisplayMode mode,
  ) async {
    final existing = _preferences[pluginName] ?? const PluginPreference();
    _preferences[pluginName] = existing.copyWith(displayMode: mode);

    await save();
  }

  /// Save window position for a plugin
  static Future<void> saveWindowPosition(
    String pluginName,
    double x,
    double y,
  ) async {
    final existing = _preferences[pluginName] ?? const PluginPreference();
    _preferences[pluginName] = existing.copyWith(windowX: x, windowY: y);

    await save();
  }

  /// Get saved window position for a plugin
  /// Returns null if no position is saved
  static ({double x, double y})? getWindowPosition(String pluginName) {
    final pref = _preferences[pluginName];
    if (pref?.windowX != null && pref?.windowY != null) {
      return (x: pref!.windowX!, y: pref.windowY!);
    }
    return null;
  }

  /// Check if plugin prefers floating mode
  static bool prefersFloating(String pluginName) {
    return _preferences[pluginName]?.displayMode == PluginDisplayMode.floating;
  }

  /// Check if plugin prefers embedded mode (default)
  static bool prefersEmbedded(String pluginName) {
    final pref = _preferences[pluginName];
    return pref == null || pref.displayMode == PluginDisplayMode.embedded;
  }
}
