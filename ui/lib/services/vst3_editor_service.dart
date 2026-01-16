// VST3 Editor Service - Platform-specific implementation selector
//
// This file uses conditional imports to select the appropriate
// VST3 editor service based on the target platform:
// - Native (macOS, Windows): Uses FFI to Rust engine with platform channels
// - Web: Stub implementation (VST3 not supported on web)

export 'vst3_editor_service_stub.dart'
    if (dart.library.ffi) 'vst3_editor_service_native.dart';
