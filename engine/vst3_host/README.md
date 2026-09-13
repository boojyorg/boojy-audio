# VST3 host wrapper

A C++ wrapper around the Steinberg VST3 SDK that exposes a plain C ABI for the Rust engine.
Plugin scanning, loading, audio/MIDI processing, parameters, state persistence and editor
windows (embedded and floating) all go through it, on macOS and Windows.

```
vst3_host.h          # C API header
vst3_host.cpp        # Implementation on top of the VST3 SDK
vst3_host_mac.mm     # macOS editor-window helpers
vst3_host_win.cpp    # Windows editor-window helpers
CMakeLists.txt       # Build configuration
../lib/              # Pre-built static libraries, committed (macOS .a, Windows .lib)
../src/vst3_host.rs  # Rust FFI bindings
../vst3sdk/          # VST3 SDK submodule — carries a deliberate CMake patch, do not discard
```

## When to rebuild

Cargo links against the pre-built libraries in `engine/lib/`, so editing `vst3_host.cpp`,
the `.mm`/`.cpp` platform helpers, or the SDK submodule does **not** take effect until you
rebuild and copy the libraries. Existing build directories can hold stale absolute paths;
configure fresh if a rebuild fails oddly.

### macOS

```bash
cd engine/vst3_host
rm -rf build && mkdir build && cd build
cmake -G Xcode ..
cmake --build . --config Release --target vst3_host
cp lib/Release/*.a ../../lib/
```

Produces a universal (arm64 + x86_64) `libvst3_host.a`.

### Windows

Requires Visual Studio 2022 with the "Desktop development with C++" workload and CMake.
CI uses the same generator on `windows-2022`; keep them aligned.

```powershell
cd engine\vst3_host
mkdir build_win; cd build_win
cmake -G "Visual Studio 17 2022" -A x64 ..
cmake --build . --config Release
copy lib\Release\*.lib ..\..\lib\
```

Produces six `.lib` files.

## State persistence

`vst3_get_state` / `vst3_set_state` move the processor and controller state as one binary blob:

```
[u32 LE: processor state size][u32 LE: controller state size][processor bytes][controller bytes]
```

The engine base64-encodes the blob into `Vst3PluginData.state_base64` (`engine/src/project.rs`)
and restores it when a project loads.

## License

The VST3 SDK is licensed under the Steinberg VST3 licence; see `../vst3sdk/LICENSE.txt`.
