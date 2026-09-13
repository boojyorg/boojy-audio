import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import '../utils/logger.dart';

/// Service for managing application updates.
/// Uses Sparkle on macOS. Windows has no native updater channel yet, so the
/// Settings section is hidden there (see docs/BACKLOG.md, Windows updater).
class UpdaterService {
  static const _channel = MethodChannel('boojy_audio/updater');

  /// Check if updates are supported on this platform
  static bool get isSupported => Platform.isMacOS;

  /// Trigger a manual check for updates.
  /// Shows the update UI if an update is available.
  static Future<void> checkForUpdates() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('checkForUpdates');
    } on PlatformException catch (e) {
      Log.e('UpdaterService: Failed to check for updates: ${e.message}');
    }
  }

  /// Set whether to automatically check for updates on app launch.
  static Future<void> setAutoCheck({required bool enabled}) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setAutoCheck', enabled);
    } on PlatformException catch (e) {
      Log.e('UpdaterService: Failed to set auto-check: ${e.message}');
    }
  }

  /// Get whether automatic update checking is enabled.
  static Future<bool> getAutoCheck() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('getAutoCheck');
      return result ?? true;
    } on PlatformException catch (e) {
      Log.e('UpdaterService: Failed to get auto-check: ${e.message}');
      return true; // Default to enabled
    }
  }

  /// Check if an update operation is currently in progress.
  static Future<bool> isUpdateInProgress() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isUpdateInProgress');
      return result ?? false;
    } on PlatformException catch (e) {
      Log.e('UpdaterService: Failed to check update progress: ${e.message}');
      return false;
    }
  }

  /// Get the date of the last update check.
  /// Returns null if never checked or on unsupported platforms.
  static Future<DateTime?> getLastCheckDate() async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMethod<double>('getLastCheckDate');
      if (result != null) {
        return DateTime.fromMillisecondsSinceEpoch(result.toInt());
      }
      return null;
    } on PlatformException catch (e) {
      Log.e('UpdaterService: Failed to get last check date: ${e.message}');
      return null;
    }
  }
}
