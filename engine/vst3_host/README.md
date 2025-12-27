# VST3 Host Wrapper

This directory contains a C++ wrapper for the Steinberg VST3 SDK, providing a C ABI for use from Rust.

## Status

**✅ Completed:**
- VST3 SDK integration (git submodule)
- C++ wrapper with clean C ABI (`vst3_host.h`, `vst3_host.cpp`)
- CMake build system with Xcode generator support
- Pre-built static libraries for macOS (arm64 + x86_64)
- Rust FFI bindings (`src/vst3_host.rs`)
- Compilation succeeds (`cargo check` works)

**✅ Status Update (M7):**
- VST3 integration is COMPLETE and functional in the engine
- `cargo build` works successfully on macOS and Windows
- All VST3 FFI functions implemented and available to Flutter
- Plugin scanning, loading, parameter access, and audio processing all implemented
- Plugin state persistence (save/load) fully implemented
- Editor UI hosting (embedded and floating windows) working
- **Windows support added:** Full VST3 support with platform-specific GUI helpers

**🚧 Known Test Limitation:**
- `cargo test` fails to link due to missing `Module::create` symbol in pre-built libraries
- This only affects Rust unit tests, NOT the actual functionality
- The VST3 functionality works perfectly in the Flutter app
- Issue: `module_mac.mm` not included in `libsdk_hosting.a` during SDK build
- Testing should be done via the Flutter UI instead of Rust unit tests

## Building

### macOS Build

```bash
cd vst3_host
mkdir -p build && cd build
cmake -G Xcode ..
cmake --build . --config Release --target vst3_host
```

This creates `build/lib/Release/libvst3_host.a` (universal binary).

### Windows Build

```powershell
cd vst3_host
mkdir build_win
cd build_win
cmake -G "Visual Studio 18 2026" -A x64 ..
cmake --build . --config Release
```

This creates `build_win/lib/Release/*.lib` (6 libraries).

**Note:** Requires Visual Studio 2026 (or 2022) with "Desktop development with C++" workload.

### Rebuild All Libraries

**macOS:**
```bash
cd vst3_host/build
cmake --build . --config Release
cp lib/Release/*.a ../../lib/
```

**Windows:**
```powershell
cd vst3_host/build_win
cmake --build . --config Release
copy lib\Release\*.lib ..\..\lib\
```

## Architecture

```
vst3_host.h          # C API header
vst3_host.cpp        # C++ implementation using VST3 SDK
CMakeLists.txt       # Build configuration
../lib/*.a           # Pre-built libraries (committed)
../src/vst3_host.rs  # Rust FFI bindings
```

## API Overview

The C API provides:
- Plugin scanning (`vst3_scan_directory`, `vst3_scan_standard_locations`)
- Plugin loading (`vst3_load_plugin`, `vst3_unload_plugin`)
- Audio processing (`vst3_process_audio`)
- MIDI events (`vst3_process_midi_event`)
- Parameter management (`vst3_get/set_parameter_value`)
- State persistence (`vst3_get_state`, `vst3_set_state`) - **✅ IMPLEMENTED**
- Editor UI (`vst3_open_editor`, `vst3_close_editor`, `vst3_attach_editor`)

## State Persistence

The state persistence system saves and restores complete VST3 plugin states:

**Binary Format:**
```
[4 bytes: processor_state_size (little-endian u32)]
[4 bytes: controller_state_size (little-endian u32)]
[processor_state_size bytes: processor state data]
[controller_state_size bytes: controller state data]
```

**Implementation:**
- `MemoryStream` class implements `Steinberg::IBStream` interface
- `vst3_get_state()` - Retrieves processor + controller state as combined binary blob
- `vst3_set_state()` - Restores processor + controller state from binary blob
- States are base64-encoded for JSON serialization in project files

**Project Integration:**
- `Vst3PluginData` struct in `engine/src/project.rs` stores:
  - `plugin_path` - Path to .vst3 bundle (for reloading)
  - `plugin_name` - Display name
  - `is_instrument` - Whether plugin is an instrument
  - `state_base64` - Base64-encoded state blob
- Saved in `TrackData.vst3_plugins` array in project.json
- Automatic restoration when project is loaded

## Next Steps

To fix the linking issue:
1. Update `vst3sdk/public.sdk/source/vst/hosting/CMakeLists.txt` to include `module_mac.mm`
2. Rebuild with `cmake --build . --config Release`
3. Copy updated `lib/Release/*.a` to `../lib/`
4. Test with `cargo test vst3`

## License

The VST3 SDK is licensed under the Steinberg VST3 license.
See `vst3sdk/LICENSE.txt` for details.
