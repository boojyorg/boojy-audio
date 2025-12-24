//
//  RustFFI.h
//  Runner
//
//  Bridging header for Rust FFI functions from libengine.dylib
//

#ifndef RustFFI_h
#define RustFFI_h

#include <stdint.h>
#include <stdbool.h>

// VST3 Editor functions
// These functions are exported from the Rust engine library

/// Open the VST3 editor for a plugin (creates IPlugView)
/// Returns a C string with result message (empty on success)
char* vst3_open_editor_ffi(int64_t effect_id);

/// Attach the VST3 editor to a parent NSView
/// Returns a C string with result message (empty on success)
char* vst3_attach_editor_ffi(int64_t effect_id, void* parent_ptr);

/// Close the VST3 editor
/// Returns a C string with result message (empty on success)
char* vst3_close_editor_ffi(int64_t effect_id);

/// Check if a VST3 plugin has an editor
/// Returns a C string with "true" or "false"
char* vst3_has_editor_ffi(int64_t effect_id);

/// Get the editor size
/// Returns a C string with "width,height" or error message
char* vst3_get_editor_size_ffi(int64_t effect_id);

/// Free a string returned by Rust
void free_rust_string(char* ptr);

#endif /* RustFFI_h */
