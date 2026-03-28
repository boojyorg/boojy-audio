#ifndef VST3_HOST_H
#define VST3_HOST_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// Opaque plugin handle
typedef void* VST3PluginHandle;

// Plugin info structure
typedef struct {
    char name[256];
    char vendor[256];
    char version[64];
    char category[64];
    char file_path[1024];
    bool is_instrument;
    bool is_effect;
} VST3PluginInfo;

// Scan result callback
typedef void (*VST3ScanCallback)(const VST3PluginInfo* info, void* user_data);

// Initialize the VST3 host system
bool vst3_host_init();

// Shutdown the VST3 host system
void vst3_host_shutdown();

// Scan for plugins in a directory
// Returns the number of plugins found
int vst3_scan_directory(const char* directory, VST3ScanCallback callback, void* user_data);

// Scan standard VST3 plugin locations
int vst3_scan_standard_locations(VST3ScanCallback callback, void* user_data);

// Load a plugin from file path
// Returns handle to plugin or NULL on failure
VST3PluginHandle vst3_load_plugin(const char* file_path);

// Unload a plugin
void vst3_unload_plugin(VST3PluginHandle handle);

// Get plugin info
bool vst3_get_plugin_info(VST3PluginHandle handle, VST3PluginInfo* info);

// Initialize plugin with sample rate and max block size
bool vst3_initialize_plugin(VST3PluginHandle handle, double sample_rate, int max_block_size);

// Activate plugin (start processing)
bool vst3_activate_plugin(VST3PluginHandle handle);

// Deactivate plugin (stop processing)
bool vst3_deactivate_plugin(VST3PluginHandle handle);

// Process audio (stereo in/out for now)
// input_left, input_right: input audio buffers
// output_left, output_right: output audio buffers
// num_frames: number of frames to process
// For instruments, input buffers can be NULL
bool vst3_process_audio(
    VST3PluginHandle handle,
    const float* input_left,
    const float* input_right,
    float* output_left,
    float* output_right,
    int num_frames
);

// Process MIDI event (for instruments)
// event_type: 0 = note on, 1 = note off, 2 = CC
// channel: MIDI channel (0-15)
// data1: note number or CC number
// data2: velocity or CC value
// sample_offset: offset in current audio buffer
bool vst3_process_midi_event(
    VST3PluginHandle handle,
    int event_type,
    int channel,
    int data1,
    int data2,
    int sample_offset
);

// Parameter management
int vst3_get_parameter_count(VST3PluginHandle handle);

typedef struct {
    uint32_t id;
    char title[256];
    char short_title[64];
    char units[64];
    double default_value;
    double min_value;
    double max_value;
    int step_count;  // 0 for continuous, >0 for discrete
} VST3ParameterInfo;

bool vst3_get_parameter_info(VST3PluginHandle handle, int index, VST3ParameterInfo* info);

double vst3_get_parameter_value(VST3PluginHandle handle, uint32_t param_id);
bool vst3_set_parameter_value(VST3PluginHandle handle, uint32_t param_id, double value);

// State management (binary chunks)
// Returns the size of the state data
int vst3_get_state_size(VST3PluginHandle handle);

// Get plugin state
// data: buffer to write state to (must be at least get_state_size() bytes)
// Returns actual size written, or -1 on error
int vst3_get_state(VST3PluginHandle handle, void* data, int max_size);

// Set plugin state
// data: state data to load
// size: size of state data
bool vst3_set_state(VST3PluginHandle handle, const void* data, int size);

// Open plugin editor window (native GUI)
// Returns true if editor opened successfully
bool vst3_open_editor(VST3PluginHandle handle);

// Close plugin editor window
void vst3_close_editor(VST3PluginHandle handle);

// Check if editor is supported
bool vst3_has_editor(VST3PluginHandle handle);

// Get editor size
// Returns true if size is available, false otherwise
bool vst3_get_editor_size(VST3PluginHandle handle, int* width, int* height);

// Attach editor to parent window
// parent: platform-specific window handle (NSView* on macOS)
// Returns true if attached successfully
bool vst3_attach_editor(VST3PluginHandle handle, void* parent);

// Preset enumeration via IUnitInfo
// Returns number of program lists, or 0 if IUnitInfo not supported
int vst3_get_program_list_count(VST3PluginHandle handle);

// Get program list info
// index: 0-based index into program lists
// list_id: output — unique ID for this list
// name: output — UTF-8 name (caller provides buffer)
// name_len: size of name buffer
// count: output — number of programs in this list
// Returns true if successful
bool vst3_get_program_list_info(
    VST3PluginHandle handle,
    int index,
    int* list_id,
    char* name,
    int name_len,
    int* count
);

// Get program (preset) name
// list_id: program list ID (from vst3_get_program_list_info)
// program_index: 0-based index into the list
// name: output — UTF-8 name (caller provides buffer)
// name_len: size of name buffer
// Returns true if successful
bool vst3_get_program_name(
    VST3PluginHandle handle,
    int list_id,
    int program_index,
    char* name,
    int name_len
);

// Set the active program (preset)
// list_id: program list ID
// program_index: 0-based index
// Returns true if successful
bool vst3_set_program(
    VST3PluginHandle handle,
    int list_id,
    int program_index
);

// Editor max size constraint (for embedded mode scale-to-fit)
// Set to 0,0 to unconstrain (floating window mode)
void vst3_set_editor_max_size(VST3PluginHandle handle, int maxW, int maxH);

// Error handling
const char* vst3_get_last_error();

#ifdef __cplusplus
}
#endif

#endif // VST3_HOST_H
