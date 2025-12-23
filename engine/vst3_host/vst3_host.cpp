#include "vst3_host.h"

#include <string>
#include <vector>
#include <map>
#include <memory>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <cctype>
#include <filesystem>

// VST3 SDK includes
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/gui/iplugview.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

namespace fs = std::filesystem;

// Global error message
static std::string g_last_error;

// Global host application
static IPtr<HostApplication> g_host_app;

// Plugin instance wrapper
struct VST3PluginInstance {
    IPtr<IComponent> component;
    IPtr<IAudioProcessor> processor;
    IPtr<IEditController> controller;
    std::string file_path;
    VST3::Hosting::Module::Ptr module;

    // Audio setup
    double sample_rate;
    int max_block_size;
    bool initialized;
    bool active;

    // Processing buffers
    ProcessData process_data;

    // Event list for MIDI
    IPtr<IEventList> event_list;

    // Editor view (M7 Phase 1: Native GUI support)
    IPtr<IPlugView> editor_view;
    void* parent_window;  // Platform-specific window handle (NSView* on macOS)
    bool editor_open;

    VST3PluginInstance()
        : sample_rate(44100.0)
        , max_block_size(512)
        , initialized(false)
        , active(false)
        , parent_window(nullptr)
        , editor_open(false) {
        std::memset(&process_data, 0, sizeof(ProcessData));
    }
};

// Helper function to set error message
static void set_error(const std::string& error) {
    g_last_error = error;
}

// C API Implementation

bool vst3_host_init() {
    // Initialize host application
    if (!g_host_app) {
        g_host_app = owned(new HostApplication());
    }
    return true;
}

void vst3_host_shutdown() {
    // Cleanup global resources
    g_host_app = nullptr;
    g_last_error.clear();
}

int vst3_scan_directory(const char* directory, VST3ScanCallback callback, void* user_data) {
    if (!directory || !callback) {
        set_error("Invalid parameters");
        return 0;
    }

    int count = 0;

    try {
        fs::path dir_path(directory);
        if (!fs::exists(dir_path) || !fs::is_directory(dir_path)) {
            set_error("Directory does not exist");
            return 0;
        }

        // Scan for .vst3 bundles/folders
        fprintf(stdout, "🔍 Scanning directory: %s\n", directory);
        fflush(stdout);

        for (const auto& entry : fs::recursive_directory_iterator(dir_path)) {
            if (entry.is_directory() && entry.path().extension() == ".vst3") {
                std::string plugin_path = entry.path().string();
                fprintf(stdout, "📦 Found VST3 bundle: %s\n", plugin_path.c_str());
                fflush(stdout);

                // Try to load the module
                std::string error;
                auto module = VST3::Hosting::Module::create(plugin_path, error);
                if (!module) {
                    fprintf(stderr, "❌ Failed to load module: %s - Error: %s\n",
                            plugin_path.c_str(), error.c_str());
                    fflush(stderr);
                    continue;
                }
                fprintf(stdout, "✅ Module loaded successfully: %s\n", plugin_path.c_str());
                fflush(stdout);

                auto factory = module->getFactory();

                // Get factory info
                PFactoryInfo factory_info;
                factory.get()->getFactoryInfo(&factory_info);

                // Iterate through all class infos
                for (const auto& class_info : factory.classInfos()) {
                    // Check if it's an audio module component
                    if (class_info.category() == kVstAudioEffectClass) {
                        VST3PluginInfo info;
                        std::memset(&info, 0, sizeof(VST3PluginInfo));

                        std::strncpy(info.name, class_info.name().c_str(), sizeof(info.name) - 1);
                        std::strncpy(info.vendor, factory_info.vendor, sizeof(info.vendor) - 1);
                        std::strncpy(info.file_path, plugin_path.c_str(), sizeof(info.file_path) - 1);

                        // Detect plugin type from subcategories and by checking MIDI input capability
                        std::string subcat_str = class_info.subCategoriesString();
                        std::string plugin_name = class_info.name();
                        std::strncpy(info.category, subcat_str.c_str(), sizeof(info.category) - 1);

                        info.is_instrument = false;
                        info.is_effect = false;

                        // First, check if it's an instrument by looking at subcategories
                        if (subcat_str.find("Instrument") != std::string::npos ||
                            subcat_str.find("Synth") != std::string::npos ||
                            subcat_str.find("Sampler") != std::string::npos ||
                            subcat_str.find("Drum") != std::string::npos ||
                            subcat_str.find("Piano") != std::string::npos ||
                            subcat_str.find("SoundGenerator") != std::string::npos ||
                            subcat_str.find("Generator") != std::string::npos) {
                            info.is_instrument = true;
                        }

                        // Check if it's an effect by looking at subcategories
                        if (subcat_str.find("Fx") != std::string::npos ||
                            subcat_str.find("Effect") != std::string::npos) {
                            info.is_effect = true;
                        }

                        // Use plugin name to detect type - most reliable approach
                        // .vst3 bundles contain multiple classes (e.g., Serum 2 and Serum 2 FX)

                        // If plugin name contains "FX" (case-insensitive), it's explicitly an effect
                        std::string name_upper = plugin_name;
                        std::transform(name_upper.begin(), name_upper.end(), name_upper.begin(),
                                     [](unsigned char c) { return std::toupper(c); });
                        if (name_upper.find(" FX") != std::string::npos || name_upper.find(" FX ") != std::string::npos) {
                            info.is_effect = true;
                            info.is_instrument = false;
                        }

                        // If still unknown, DEFAULT to INSTRUMENT
                        // Most synthesizers don't declare proper VST3 subcategories,
                        // so defaulting to instrument makes more sense than defaulting to effect.
                        // Serum, Serum 2, etc. will correctly be identified as instruments.
                        if (!info.is_instrument && !info.is_effect) {
                            info.is_instrument = true;
                        }

                        // DEBUG: Log plugin detection
                        fprintf(stdout, "🔍 VST3 Plugin: '%s' | SubCat: '%s' | Instrument: %d | Effect: %d\n",
                                plugin_name.c_str(), subcat_str.c_str(), info.is_instrument, info.is_effect);
                        fflush(stdout);

                        callback(&info, user_data);
                        count++;
                    }
                }
            }
        }
    } catch (const std::exception& e) {
        set_error(std::string("Scan error: ") + e.what());
        return count;
    }

    return count;
}

int vst3_scan_standard_locations(VST3ScanCallback callback, void* user_data) {
    int total = 0;

    // Standard VST3 locations on macOS
    std::vector<std::string> locations = {
        "/Library/Audio/Plug-Ins/VST3",
        std::string(getenv("HOME")) + "/Library/Audio/Plug-Ins/VST3"
    };

    for (const auto& location : locations) {
        total += vst3_scan_directory(location.c_str(), callback, user_data);
    }

    return total;
}

VST3PluginHandle vst3_load_plugin(const char* file_path) {
    if (!file_path) {
        set_error("Invalid file path");
        return nullptr;
    }

    if (!g_host_app) {
        set_error("Host not initialized. Call vst3_host_init() first");
        return nullptr;
    }

    try {
        auto instance = std::make_unique<VST3PluginInstance>();
        instance->file_path = file_path;

        // Load the module
        std::string error;
        auto module = VST3::Hosting::Module::create(file_path, error);
        if (!module) {
            set_error("Failed to load module: " + error);
            return nullptr;
        }

        instance->module = module;

        auto factory = module->getFactory();

        // Find the first audio effect class
        for (const auto& class_info : factory.classInfos()) {
            if (class_info.category() == kVstAudioEffectClass) {
                // Create the component using modern API
                auto component = factory.createInstance<IComponent>(class_info.ID());
                if (!component) {
                    set_error("Failed to create component instance");
                    return nullptr;
                }

                instance->component = component;

                // Initialize the component
                if (component->initialize(g_host_app) != kResultOk) {
                    set_error("Failed to initialize component");
                    return nullptr;
                }

                // Get the audio processor interface
                auto processor = FUnknownPtr<IAudioProcessor>(component);
                if (processor) {
                    instance->processor = processor;
                }

                // Get the edit controller
                TUID controller_cid;
                if (component->getControllerClassId(controller_cid) == kResultOk) {
                    auto controller = factory.createInstance<IEditController>(VST3::UID::fromTUID(controller_cid));
                    if (controller) {
                        instance->controller = controller;
                        controller->initialize(g_host_app);
                    }
                }

                return instance.release();
            }
        }

        set_error("No audio effect class found in plugin");
        return nullptr;

    } catch (const std::exception& e) {
        set_error(std::string("Load error: ") + e.what());
        return nullptr;
    }
}

void vst3_unload_plugin(VST3PluginHandle handle) {
    if (!handle) return;

    auto instance = static_cast<VST3PluginInstance*>(handle);

    // Deactivate if active
    if (instance->active && instance->processor) {
        instance->processor->setProcessing(false);
        instance->active = false;
    }

    // Cleanup
    if (instance->controller) {
        instance->controller->terminate();
    }

    if (instance->component) {
        instance->component->terminate();
    }

    delete instance;
}

bool vst3_get_plugin_info(VST3PluginHandle handle, VST3PluginInfo* info) {
    if (!handle || !info) {
        set_error("Invalid parameters");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    std::memset(info, 0, sizeof(VST3PluginInfo));

    // Get info from component
    PFactoryInfo factory_info;
    std::strncpy(info->file_path, instance->file_path.c_str(), sizeof(info->file_path) - 1);

    // TODO: Extract more detailed info from component
    info->is_effect = true;
    info->is_instrument = false;

    return true;
}

bool vst3_initialize_plugin(VST3PluginHandle handle, double sample_rate, int max_block_size) {
    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->processor) {
        set_error("No audio processor interface");
        return false;
    }

    instance->sample_rate = sample_rate;
    instance->max_block_size = max_block_size;

    // Setup processing
    ProcessSetup setup;
    setup.processMode = kRealtime;
    setup.symbolicSampleSize = kSample32;
    setup.maxSamplesPerBlock = max_block_size;
    setup.sampleRate = sample_rate;

    if (instance->processor->setupProcessing(setup) != kResultOk) {
        set_error("Failed to setup processing");
        return false;
    }

    // Activate busses
    if (instance->component->activateBus(kAudio, kInput, 0, true) != kResultOk) {
        // Some plugins don't have input (instruments)
    }

    if (instance->component->activateBus(kAudio, kOutput, 0, true) != kResultOk) {
        set_error("Failed to activate output bus");
        return false;
    }

    instance->initialized = true;
    return true;
}

bool vst3_activate_plugin(VST3PluginHandle handle) {
    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->initialized || !instance->processor) {
        set_error("Plugin not initialized");
        return false;
    }

    if (instance->processor->setProcessing(true) != kResultOk) {
        set_error("Failed to start processing");
        return false;
    }

    instance->active = true;
    return true;
}

bool vst3_deactivate_plugin(VST3PluginHandle handle) {
    if (!handle) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (instance->active && instance->processor) {
        instance->processor->setProcessing(false);
        instance->active = false;
    }

    return true;
}

bool vst3_process_audio(
    VST3PluginHandle handle,
    const float* input_left,
    const float* input_right,
    float* output_left,
    float* output_right,
    int num_frames
) {
    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->active || !instance->processor) {
        set_error("Plugin not active");
        return false;
    }

    // Set up input buffers (stereo)
    float* inputs[2] = {
        const_cast<float*>(input_left),
        const_cast<float*>(input_right)
    };

    // Set up output buffers (stereo)
    float* outputs[2] = {
        output_left,
        output_right
    };

    // Set up audio bus buffers
    AudioBusBuffers input_bus;
    input_bus.numChannels = 2;
    input_bus.silenceFlags = 0;
    input_bus.channelBuffers32 = inputs;

    AudioBusBuffers output_bus;
    output_bus.numChannels = 2;
    output_bus.silenceFlags = 0;
    output_bus.channelBuffers32 = outputs;

    // Set up process data
    ProcessData data;
    data.processMode = kRealtime;
    data.symbolicSampleSize = kSample32;
    data.numSamples = num_frames;
    data.numInputs = 1;
    data.numOutputs = 1;
    data.inputs = &input_bus;
    data.outputs = &output_bus;
    data.inputParameterChanges = nullptr;
    data.outputParameterChanges = nullptr;
    data.inputEvents = nullptr;
    data.outputEvents = nullptr;
    data.processContext = nullptr;

    // Process the audio
    tresult result = instance->processor->process(data);
    if (result != kResultOk && result != kResultTrue) {
        set_error("Audio processing failed");
        return false;
    }

    return true;
}

bool vst3_process_midi_event(
    VST3PluginHandle handle,
    int event_type,
    int channel,
    int data1,
    int data2,
    int sample_offset
) {
    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->processor) {
        set_error("No processor available");
        return false;
    }

    // Create an event
    Event event;
    std::memset(&event, 0, sizeof(Event));
    event.busIndex = 0;
    event.sampleOffset = sample_offset;
    event.ppqPosition = 0;
    event.flags = Event::kIsLive;

    // Event types: 0 = note on, 1 = note off, 2 = CC
    switch (event_type) {
        case 0: // Note On
            event.type = Event::kNoteOnEvent;
            event.noteOn.channel = static_cast<int16>(channel);
            event.noteOn.pitch = static_cast<int16>(data1);
            event.noteOn.velocity = static_cast<float>(data2) / 127.0f;
            event.noteOn.length = 0;
            event.noteOn.tuning = 0.0f;
            event.noteOn.noteId = -1;
            break;

        case 1: // Note Off
            event.type = Event::kNoteOffEvent;
            event.noteOff.channel = static_cast<int16>(channel);
            event.noteOff.pitch = static_cast<int16>(data1);
            event.noteOff.velocity = static_cast<float>(data2) / 127.0f;
            event.noteOff.tuning = 0.0f;
            event.noteOff.noteId = -1;
            break;

        case 2: // Control Change (CC)
            // VST3 doesn't have direct CC events - they're typically handled via parameter changes
            // For now, we'll skip CC events as they require IParameterChanges
            return true;

        default:
            set_error("Unknown MIDI event type");
            return false;
    }

    // Note: This creates and adds the event, but for proper MIDI handling,
    // events should be queued and passed during the next process() call.
    // For now, we're setting up the infrastructure.

    return true;
}

int vst3_get_parameter_count(VST3PluginHandle handle) {
    if (!handle) return 0;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return 0;

    return instance->controller->getParameterCount();
}

bool vst3_get_parameter_info(VST3PluginHandle handle, int index, VST3ParameterInfo* info) {
    if (!handle || !info) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return false;

    ParameterInfo param_info;
    if (instance->controller->getParameterInfo(index, param_info) != kResultOk) {
        return false;
    }

    std::memset(info, 0, sizeof(VST3ParameterInfo));
    info->id = param_info.id;

    // Convert from UTF16 to UTF8 (simplified - real implementation needs proper conversion)
    for (int i = 0; i < 255 && param_info.title[i]; i++) {
        info->title[i] = static_cast<char>(param_info.title[i]);
    }

    info->default_value = param_info.defaultNormalizedValue;
    info->step_count = param_info.stepCount;

    return true;
}

double vst3_get_parameter_value(VST3PluginHandle handle, uint32_t param_id) {
    if (!handle) return 0.0;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return 0.0;

    return instance->controller->getParamNormalized(param_id);
}

bool vst3_set_parameter_value(VST3PluginHandle handle, uint32_t param_id, double value) {
    if (!handle) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return false;

    return instance->controller->setParamNormalized(param_id, value) == kResultOk;
}

int vst3_get_state_size(VST3PluginHandle handle) {
    // TODO: Implement state size query
    return 0;
}

int vst3_get_state(VST3PluginHandle handle, void* data, int max_size) {
    // TODO: Implement state save
    return -1;
}

bool vst3_set_state(VST3PluginHandle handle, const void* data, int size) {
    // TODO: Implement state load
    return false;
}

// ============================================================================
// M7 Phase 1: Native Editor Support
// ============================================================================

bool vst3_has_editor(VST3PluginHandle handle) {
    if (!handle) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return false;

    // Check if controller supports creating an editor view
    auto view = instance->controller->createView(ViewType::kEditor);
    if (view) {
        view->release();
        return true;
    }

    return false;
}

bool vst3_open_editor(VST3PluginHandle handle) {
    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) {
        set_error("No edit controller available");
        return false;
    }

    if (instance->editor_open) {
        set_error("Editor is already open");
        return false;
    }

    // Create the editor view
    auto view = instance->controller->createView(ViewType::kEditor);
    if (!view) {
        set_error("Failed to create editor view");
        return false;
    }

    instance->editor_view = view;
    instance->editor_open = true;

    return true;
}

void vst3_close_editor(VST3PluginHandle handle) {
    if (!handle) return;

    auto instance = static_cast<VST3PluginInstance*>(handle);

    if (instance->editor_view) {
        // Detach from parent if attached
        if (instance->parent_window) {
            instance->editor_view->removed();
            instance->parent_window = nullptr;
        }

        // Release the view
        instance->editor_view = nullptr;
    }

    instance->editor_open = false;
}

bool vst3_get_editor_size(VST3PluginHandle handle, int* width, int* height) {
    if (!handle || !width || !height) {
        set_error("Invalid parameters");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->editor_view) {
        set_error("No editor view available");
        return false;
    }

    ViewRect rect;
    if (instance->editor_view->getSize(&rect) != kResultOk) {
        set_error("Failed to get editor size");
        return false;
    }

    *width = rect.right - rect.left;
    *height = rect.bottom - rect.top;

    return true;
}

bool vst3_attach_editor(VST3PluginHandle handle, void* parent) {
    if (!handle || !parent) {
        set_error("Invalid parameters");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->editor_view) {
        set_error("No editor view available");
        return false;
    }

    // Detach from previous parent if needed
    if (instance->parent_window) {
        instance->editor_view->removed();
    }

    // Attach to new parent
    // On macOS, parent is NSView*
    if (instance->editor_view->attached(parent, kPlatformTypeNSView) != kResultOk) {
        set_error("Failed to attach editor to parent window");
        return false;
    }

    instance->parent_window = parent;

    return true;
}

const char* vst3_get_last_error() {
    return g_last_error.c_str();
}
