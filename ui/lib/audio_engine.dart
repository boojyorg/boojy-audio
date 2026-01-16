// Audio Engine - Platform-specific implementation selector
//
// This file uses conditional imports to select the appropriate
// audio engine implementation based on the target platform:
// - Native (iOS, macOS, Windows, Linux, Android): Uses FFI to Rust engine
// - Web: Uses JS interop to WASM engine

// Export the appropriate implementation based on platform
export 'audio_engine_stub.dart'
    if (dart.library.ffi) 'audio_engine_native.dart'
    if (dart.library.js_interop) 'audio_engine_web.dart';
