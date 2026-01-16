// Platform Drop Target - Platform-specific implementation selector
//
// This file uses conditional imports to select the appropriate
// drop target implementation based on the target platform:
// - Native (iOS, macOS, Windows, Linux, Android): Uses dart:io for platform detection
// - Web: Uses desktop_drop directly (has web support)

export 'platform_drop_target_stub.dart'
    if (dart.library.io) 'platform_drop_target_native.dart'
    if (dart.library.js_interop) 'platform_drop_target_web.dart';
