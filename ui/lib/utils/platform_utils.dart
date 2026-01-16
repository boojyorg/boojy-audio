// Platform Utilities - Safe platform detection for web compatibility
//
// This file provides platform detection that works across all platforms
// including web, where dart:io is not available.

import 'package:flutter/foundation.dart';

/// Platform detection utilities that work on web
class PlatformUtils {
  PlatformUtils._();

  /// Whether running on web
  static bool get isWeb => kIsWeb;

  /// Whether running on macOS (false on web)
  static bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Whether running on Windows (false on web)
  static bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Whether running on Linux (false on web)
  static bool get isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// Whether running on iOS (false on web)
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether running on Android (false on web)
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether running on desktop (macOS, Windows, or Linux)
  static bool get isDesktop => isMacOS || isWindows || isLinux;

  /// Whether running on mobile (iOS or Android)
  static bool get isMobile => isIOS || isAndroid;

  /// Get the platform name as a string
  static String get operatingSystem {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  /// Get path separator (always / on web)
  static String get pathSeparator => isWindows ? '\\' : '/';

  /// Get environment variable (returns null on web)
  static String? getEnvironmentVariable(String name) {
    // Environment variables are not available on web
    if (kIsWeb) return null;
    // On native platforms, we would need dart:io which we can't import here
    // This method should be overridden in platform-specific code
    return null;
  }
}

/// Mixin for widgets/services that need platform-specific behavior
mixin PlatformAwareMixin {
  bool get isWeb => PlatformUtils.isWeb;
  bool get isDesktop => PlatformUtils.isDesktop;
  bool get isMobile => PlatformUtils.isMobile;
  bool get isMacOS => PlatformUtils.isMacOS;
  bool get isWindows => PlatformUtils.isWindows;
}
