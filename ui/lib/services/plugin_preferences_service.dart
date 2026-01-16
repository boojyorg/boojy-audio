import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// Uses SharedPreferences for cross-platform compatibility (including web)
class PluginPreferencesService {
  static const _prefsKey = 'plugin_preferences';
  static Map<String, PluginPreference> _preferences = {};
  static bool _initialized = false;

  /// Load preferences from storage
  static Future<void> load() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;

        final pluginPrefs = json['pluginPreferences'] as Map<String, dynamic>?;
        if (pluginPrefs != null) {
          _preferences = pluginPrefs.map(
            (key, value) => MapEntry(
              key,
              PluginPreference.fromJson(value as Map<String, dynamic>),
            ),
          );
        }
      }

      _initialized = true;
    } catch (e) {
      debugPrint('PluginPreferencesService: Error loading preferences: $e');
      _preferences = {};
      _initialized = true;
    }
  }

  /// Save preferences to storage
  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final json = {
        'pluginPreferences': _preferences.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };

      await prefs.setString(
        _prefsKey,
        const JsonEncoder.withIndent('  ').convert(json),
      );
    } catch (e) {
      debugPrint('PluginPreferencesService: Error saving preferences: $e');
    }
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
