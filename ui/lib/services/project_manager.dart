// Project Manager - Platform-specific implementation selector
//
// This file uses conditional imports to select the appropriate
// project manager implementation based on the target platform:
// - Native (iOS, macOS, Windows, Linux, Android): Uses file system storage
// - Web: Uses IndexedDB storage

export 'project_manager_stub.dart'
    if (dart.library.io) 'project_manager_native.dart'
    if (dart.library.js_interop) 'project_manager_web.dart';
