import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../audio_engine.dart';
import '../utils/logger.dart';
import '../models/vst3_plugin_data.dart';
import '../widgets/shared/boojy_notice.dart';
import 'commands/effect_commands.dart';
import 'plugin_folders.dart';

/// Manages VST3 plugin scanning, caching, and track effects.
///
/// Extracted from daw_screen.dart to improve maintainability.
class Vst3PluginManager extends ChangeNotifier {
  /// Whether the DAW scans the machine's VST3 folders at start-up. Tests
  /// turn it off: the scan loads every installed plugin, which is slow and
  /// differs from machine to machine.
  static bool scanOnStart = true;

  final AudioEngine _audioEngine;

  // Plugin scanning state
  List<Map<String, String>> _availablePlugins = [];
  bool _isScanning = false;
  bool _isScanned = false;

  // Track effects mapping: trackId -> [effectIds]
  final Map<int, List<int>> _trackEffects = {};

  // Plugin metadata cache: effectId -> plugin info
  final Map<int, Map<String, String>> _pluginCache = {};

  // Cache version - increment to invalidate old caches
  static const int _cacheVersion = 8;

  Vst3PluginManager(this._audioEngine);

  // Getters
  List<Map<String, String>> get availablePlugins =>
      List.unmodifiable(_availablePlugins);
  bool get isScanning => _isScanning;
  bool get isScanned => _isScanned;

  /// Get the number of VST3 effects per track
  Map<int, int> getTrackPluginCounts() {
    final counts = <int, int>{};
    for (final entry in _trackEffects.entries) {
      counts[entry.key] = entry.value.length;
    }
    return counts;
  }

  /// Get all VST3 plugin instances for a specific track
  List<Vst3PluginInstance> getTrackPlugins(int trackId) {
    final effectIds = _trackEffects[trackId] ?? [];
    final plugins = <Vst3PluginInstance>[];

    for (final effectId in effectIds) {
      final pluginInfo = _pluginCache[effectId];
      if (pluginInfo != null) {
        try {
          // Fetch parameter count and info
          final paramCount = _audioEngine.getVst3ParameterCount(effectId);
          final parameters = <int, Vst3ParameterInfo>{};
          final parameterValues = <int, double>{};

          for (int i = 0; i < paramCount; i++) {
            final info = _audioEngine.getVst3ParameterInfo(effectId, i);
            if (info != null) {
              parameters[i] = Vst3ParameterInfo(
                index: i,
                name: info['name'] as String? ?? 'Parameter $i',
                min: (info['min'] as num?)?.toDouble() ?? 0.0,
                max: (info['max'] as num?)?.toDouble() ?? 1.0,
                defaultValue: (info['default'] as num?)?.toDouble() ?? 0.5,
                unit: '',
              );

              // Fetch current value
              parameterValues[i] = _audioEngine.getVst3ParameterValue(
                effectId,
                i,
              );
            }
          }

          plugins.add(
            Vst3PluginInstance(
              effectId: effectId,
              pluginName: pluginInfo['name'] ?? 'Unknown',
              pluginPath: pluginInfo['path'] ?? '',
              parameters: parameters,
              parameterValues: parameterValues,
            ),
          );
        } catch (e) {
          Log.e(
            'VST3PluginManager: Error getting plugin info for effect $effectId: $e',
          );
        }
      }
    }

    return plugins;
  }

  /// Load cached plugins from SharedPreferences
  Future<void> loadCachedPlugins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedVersion = prefs.getInt('vst3_cache_version') ?? 0;

      // Invalidate cache if version doesn't match
      if (cachedVersion != _cacheVersion) {
        await prefs.remove('vst3_plugins_cache');
        await prefs.remove('vst3_scan_timestamp');
        await prefs.setInt('vst3_cache_version', _cacheVersion);
        return;
      }

      final cachedJson = prefs.getString('vst3_plugins_cache');

      if (cachedJson != null) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final plugins = decoded
            .map((item) => Map<String, String>.from(item as Map))
            .toList();

        // Verify that plugins have type information
        final bool hasTypeInfo = plugins.every(
          (plugin) =>
              plugin.containsKey('is_instrument') &&
              plugin.containsKey('is_effect'),
        );

        if (!hasTypeInfo) {
          await prefs.remove('vst3_plugins_cache');
          return;
        }

        _availablePlugins = plugins;
        _isScanned = true;
        notifyListeners();
      }
    } catch (e) {
      Log.e('VST3PluginManager: Error loading cached plugins: $e');
    }
  }

  /// Save plugins to cache
  Future<void> _saveCache(List<Map<String, String>> plugins) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(plugins);
      await prefs.setString('vst3_plugins_cache', json);
      await prefs.setInt(
        'vst3_scan_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setInt('vst3_cache_version', _cacheVersion);
    } catch (e) {
      Log.e('VST3PluginManager: Error saving plugin cache: $e');
    }
  }

  /// Whether a VST3 folder changed after the saved list was made. Without
  /// this, plugins installed after the first scan never showed up.
  Future<bool> _pluginsChangedSinceScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scannedAt = prefs.getInt('vst3_scan_timestamp');
      if (scannedAt == null) return true;
      return pluginFoldersChangedSince(
        DateTime.fromMillisecondsSinceEpoch(scannedAt),
        vst3Folders(),
      );
    } catch (e) {
      Log.e('VST3PluginManager: Error checking plugin folders: $e');
      return false;
    }
  }

  /// Scan for VST3 plugins
  ///
  /// Returns a status message describing the result.
  Future<String> scanPlugins({bool forceRescan = false}) async {
    if (_isScanning) return 'Scan already in progress';

    // Load from cache if not forcing rescan
    if (!forceRescan && !_isScanned) {
      await loadCachedPlugins();

      // The saved list is good unless a plugin was installed or removed since
      if (_availablePlugins.isNotEmpty && !await _pluginsChangedSinceScan()) {
        return 'Loaded ${_availablePlugins.length} plugin(s) from cache';
      }
    }

    _isScanning = true;
    notifyListeners();

    try {
      final plugins = _audioEngine.scanVst3PluginsStandard();

      // Save to cache
      await _saveCache(plugins);

      _availablePlugins = plugins;
      _isScanned = true;
      _isScanning = false;
      notifyListeners();

      return 'Found ${plugins.length} VST3 plugin${plugins.length == 1 ? '' : 's'}';
    } catch (e) {
      _isScanning = false;
      notifyListeners();
      Notices.problem("Couldn't scan for VST3 plugins", error: e);
      return 'VST3 scan failed: $e';
    }
  }

  /// Add a VST3 plugin to a track
  ///
  /// Returns a result with success status and message.
  ({bool success, String message}) addToTrack(
    int trackId,
    Map<String, String> plugin,
  ) {
    try {
      final pluginPath = plugin['path'] ?? '';
      final effectId = _audioEngine.addVst3EffectToTrack(trackId, pluginPath);

      if (effectId >= 0) {
        _trackEffects[trackId] ??= [];
        _trackEffects[trackId]!.add(effectId);
        _pluginCache[effectId] = plugin;
        notifyListeners();

        return (
          success: true,
          message: 'Added ${plugin['name']} to track $trackId',
        );
      } else {
        return (success: false, message: 'Failed to load ${plugin['name']}');
      }
    } catch (e) {
      return (success: false, message: 'Error adding plugin: $e');
    }
  }

  /// Add a VST3 plugin to a track from Vst3Plugin data
  ({bool success, String message}) addPluginToTrack(
    int trackId,
    Vst3Plugin plugin,
  ) {
    return addToTrack(trackId, {
      'name': plugin.name,
      'path': plugin.path,
      'vendor': plugin.vendor ?? '',
    });
  }

  /// Remove a VST3 plugin from its track
  ///
  /// Returns a result with success status and message.
  ({bool success, String message}) removeFromTrack(int effectId) {
    // Find which track this effect is on
    int? trackId;
    for (final entry in _trackEffects.entries) {
      if (entry.value.contains(effectId)) {
        trackId = entry.key;
        break;
      }
    }

    if (trackId == null) {
      return (success: false, message: 'Could not find track for effect');
    }

    try {
      // Remove via audio engine
      _audioEngine.removeEffectFromTrack(trackId, effectId);

      _trackEffects[trackId]?.remove(effectId);
      _pluginCache.remove(effectId);
      notifyListeners();

      return (success: true, message: 'Removed VST3 plugin');
    } catch (e) {
      return (success: false, message: 'Error removing plugin: $e');
    }
  }

  /// Update a VST3 parameter value
  void updateParameter(int effectId, int paramIndex, double value) {
    try {
      _audioEngine.setVst3ParameterValue(effectId, paramIndex, value);
    } catch (e) {
      // FFI call - ignore errors silently for parameter updates
    }
  }

  /// Adding [plugin] to a track as one undo step. The command loads it into
  /// the engine; the manager's own list follows on add, undo and redo.
  AddEffectCommand addPluginCommand(int trackId, Vst3Plugin plugin) =>
      AddEffectCommand(
        trackId: trackId,
        trackName: '',
        effectType: plugin.path,
        effectName: plugin.name,
        isVst3: true,
        onEffectAdded: (effectId) => registerRestoredPlugin(
          trackId,
          effectId,
          path: plugin.path,
          name: plugin.name,
          vendor: plugin.vendor ?? '',
        ),
        onEffectRemoved: forgetPlugin,
      );

  /// Register a VST3 plugin that a command loaded into the engine (an undoable
  /// add, or the undo of a track or effect delete, which brings it back under
  /// a fresh effect id). This only syncs the manager's own maps (so the editor
  /// and the track's plugin-count chip reappear); it must NOT call the engine
  /// again, or the plugin would be double-added.
  void registerRestoredPlugin(
    int trackId,
    int effectId, {
    required String path,
    required String name,
    String vendor = '',
  }) {
    _trackEffects[trackId] ??= [];
    _trackEffects[trackId]!.add(effectId);
    _pluginCache[effectId] = {'name': name, 'path': path, 'vendor': vendor};
    notifyListeners();
  }

  /// Drop a plugin a command already removed from the engine (undoing its add,
  /// or deleting it from the device chain). Maps only, like
  /// [registerRestoredPlugin].
  void forgetPlugin(int effectId) {
    for (final ids in _trackEffects.values) {
      ids.remove(effectId);
    }
    _pluginCache.remove(effectId);
    notifyListeners();
  }

  /// Get effect IDs for a track
  List<int> getTrackEffectIds(int trackId) {
    return List.unmodifiable(_trackEffects[trackId] ?? []);
  }

  /// Get plugin info from cache
  Map<String, String>? getPluginInfo(int effectId) {
    return _pluginCache[effectId];
  }

  /// Clear all state (used when creating new project)
  void clear() {
    _trackEffects.clear();
    _pluginCache.clear();
    notifyListeners();
  }
}
