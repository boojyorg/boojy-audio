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

// macOS specific includes for main thread check
#ifdef __APPLE__
#include <pthread.h>
#endif

#include <stdexcept>
#include <atomic>

// VST3 SDK includes
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstpluginterfacesupport.h"  // For IComponentHandler
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstmessage.h"  // For IConnectionPoint
#include "pluginterfaces/base/ibstream.h"     // For IBStream (state save/load)
#include "pluginterfaces/vst/ivstunits.h"     // For IUnitInfo (preset enumeration)
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/hosting/eventlist.h"  // For MIDI event queue

using namespace Steinberg;
using namespace Steinberg::Vst;

namespace fs = std::filesystem;

// Global error message
static std::string g_last_error;

// Global host application
static IPtr<HostApplication> g_host_app;

// Forward declaration
struct VST3PluginInstance;

//------------------------------------------------------------------------
// IComponentHandler implementation - required for plugins to communicate back to host
// Plugins use this to notify about parameter changes, restarts, etc.
// Many plugins may crash or malfunction without a valid component handler.
//------------------------------------------------------------------------
class ComponentHandler : public IComponentHandler
{
public:
    ComponentHandler() : refCount_(1) {}

    // IComponentHandler
    tresult PLUGIN_API beginEdit(ParamID id) override {
        fprintf(stderr, "📊 [ComponentHandler] beginEdit: param %u\n", id);
        fflush(stderr);
        return kResultOk;  // Accept the edit start
    }

    tresult PLUGIN_API performEdit(ParamID id, ParamValue valueNormalized) override {
        // Don't log every performEdit as it can be very frequent
        return kResultOk;
    }

    tresult PLUGIN_API endEdit(ParamID id) override {
        fprintf(stderr, "📊 [ComponentHandler] endEdit: param %u\n", id);
        fflush(stderr);
        return kResultOk;
    }

    tresult PLUGIN_API restartComponent(int32 flags) override {
        fprintf(stderr, "📊 [ComponentHandler] restartComponent: flags=%d\n", flags);
        fflush(stderr);
        // TODO: Handle restart flags properly (kReloadComponent, kIoChanged, etc.)
        return kResultOk;
    }

    // FUnknown
    tresult PLUGIN_API queryInterface(const TUID _iid, void** obj) override {
        if (FUnknownPrivate::iidEqual(_iid, IComponentHandler::iid) ||
            FUnknownPrivate::iidEqual(_iid, FUnknown::iid)) {
            *obj = this;
            addRef();
            return kResultTrue;
        }
        *obj = nullptr;
        return kNoInterface;
    }

    uint32 PLUGIN_API addRef() override {
        return ++refCount_;
    }

    uint32 PLUGIN_API release() override {
        uint32 count = --refCount_;
        if (count == 0) {
            delete this;
        }
        return count;
    }

private:
    std::atomic<uint32> refCount_;
};

// Global component handler - shared by all plugin instances
static IPtr<ComponentHandler> g_component_handler;

//------------------------------------------------------------------------
// IPlugFrame declaration - implementation after VST3PluginInstance is defined
// Many plugins (especially Serum) crash if setFrame() is not called before attached()
//------------------------------------------------------------------------

#ifdef __APPLE__
// Forward declare the Objective-C helper functions
extern "C" void vst3_resize_nsview(void* nsview, int width, int height);
extern "C" void vst3_set_nsview_bounds(void* nsview, int width, int height);
#endif

class PlugFrame : public IPlugFrame
{
public:
    PlugFrame(VST3PluginInstance* instance);

    // IPlugFrame - implemented after VST3PluginInstance is defined
    tresult PLUGIN_API resizeView(IPlugView* view, ViewRect* newSize) override;

    // FUnknown
    tresult PLUGIN_API queryInterface(const TUID _iid, void** obj) override {
        if (FUnknownPrivate::iidEqual(_iid, IPlugFrame::iid) ||
            FUnknownPrivate::iidEqual(_iid, FUnknown::iid)) {
            *obj = this;
            addRef();
            return kResultTrue;
        }
        *obj = nullptr;
        return kNoInterface;
    }

    uint32 PLUGIN_API addRef() override {
        return ++refCount_;
    }

    uint32 PLUGIN_API release() override {
        uint32 count = --refCount_;
        if (count == 0) {
            delete this;
        }
        return count;
    }

private:
    VST3PluginInstance* instance_;
    std::atomic<uint32> refCount_;
    bool resizeRecursionGuard_;
};

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

    // Event list for MIDI - concrete class for queuing MIDI events
    EventList midi_events;

    // Editor view (M7 Phase 1: Native GUI support)
    IPtr<IPlugView> editor_view;
    IPtr<PlugFrame> plug_frame;  // IPlugFrame for resize notifications
    void* parent_window;  // Platform-specific window handle (NSView* on macOS)
    bool editor_open;

    // Max editor size constraints (0 = unconstrained, e.g. floating windows)
    int max_editor_width;
    int max_editor_height;

    // Original preferred editor size (stored on first attachment, never changes)
    int preferred_editor_width;
    int preferred_editor_height;

    VST3PluginInstance()
        : sample_rate(44100.0)
        , max_block_size(512)
        , initialized(false)
        , active(false)
        , midi_events(128)  // Up to 128 MIDI events per buffer
        , parent_window(nullptr)
        , editor_open(false)
        , max_editor_width(0)
        , max_editor_height(0)
        , preferred_editor_width(0)
        , preferred_editor_height(0) {
        std::memset(&process_data, 0, sizeof(ProcessData));
    }
};

//------------------------------------------------------------------------
// PlugFrame implementation (needs VST3PluginInstance to be complete)
//------------------------------------------------------------------------
PlugFrame::PlugFrame(VST3PluginInstance* instance)
    : instance_(instance)
    , refCount_(1)
    , resizeRecursionGuard_(false) {}

tresult PLUGIN_API PlugFrame::resizeView(IPlugView* view, ViewRect* newSize) {
    if (!newSize || !view) {
        fprintf(stderr, "📐 [PlugFrame] resizeView: invalid args\n");
        fflush(stderr);
        return kInvalidArgument;
    }

    int width = newSize->right - newSize->left;
    int height = newSize->bottom - newSize->top;

    // Save ORIGINAL size before clamping (needed for bounds in embedded mode)
    int origWidth = width;
    int origHeight = height;

    // Clamp to max size if constraints are set (embedded mode)
    if (instance_->max_editor_width > 0 && width > instance_->max_editor_width) {
        width = instance_->max_editor_width;
        newSize->right = newSize->left + width;
    }
    if (instance_->max_editor_height > 0 && height > instance_->max_editor_height) {
        height = instance_->max_editor_height;
        newSize->bottom = newSize->top + height;
    }

    fprintf(stderr, "📐 [PlugFrame] resizeView: requested=%dx%d, clamped=%dx%d\n",
            origWidth, origHeight, width, height);
    fflush(stderr);

    // Prevent recursion
    if (resizeRecursionGuard_) {
        return kResultFalse;
    }

    resizeRecursionGuard_ = true;

#ifdef __APPLE__
    if (instance_->max_editor_width > 0 || instance_->max_editor_height > 0) {
        // Embedded mode: plugin stays at native size, CATransform3D scales visually.
        // Just acknowledge the resize — don't change container or call onSize.
        resizeRecursionGuard_ = false;
        return kResultTrue;
    }

    // Floating/unconstrained: resize container normally
    if (instance_ && instance_->parent_window) {
        vst3_resize_nsview(instance_->parent_window, width, height);
    }
#endif

    // Also tell the view about the new size
    ViewRect r;
    if (view->getSize(&r) == kResultTrue) {
        if (r.right - r.left != width || r.bottom - r.top != height) {
            fprintf(stderr, "📐 [PlugFrame] Calling view->onSize\n");
            fflush(stderr);
            view->onSize(newSize);
        }
    }

    resizeRecursionGuard_ = false;
    return kResultTrue;
}

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
    // Initialize component handler
    if (!g_component_handler) {
        g_component_handler = owned(new ComponentHandler());
        fprintf(stdout, "✅ VST3 Host: Created global ComponentHandler\n");
        fflush(stdout);
    }
    return true;
}

void vst3_host_shutdown() {
    // Cleanup global resources
    g_component_handler = nullptr;
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

    std::vector<std::string> locations;

#ifdef _WIN32
    // Standard VST3 locations on Windows
    locations.push_back("C:\\Program Files\\Common Files\\VST3");
    locations.push_back("C:\\Program Files (x86)\\Common Files\\VST3");

    // User VST3 directory
    char* appdata = getenv("APPDATA");
    if (appdata) {
        locations.push_back(std::string(appdata) + "\\VST3");
    }

    // Also check LOCALAPPDATA for some plugins
    char* localappdata = getenv("LOCALAPPDATA");
    if (localappdata) {
        locations.push_back(std::string(localappdata) + "\\Programs\\Common\\VST3");
    }
#elif __APPLE__
    // Standard VST3 locations on macOS
    locations.push_back("/Library/Audio/Plug-Ins/VST3");
    const char* home = getenv("HOME");
    if (home) {
        locations.push_back(std::string(home) + "/Library/Audio/Plug-Ins/VST3");
    }
#elif __linux__
    // Standard VST3 locations on Linux
    const char* home = getenv("HOME");
    if (home) {
        locations.push_back(std::string(home) + "/.vst3");
    }
    locations.push_back("/usr/lib/vst3");
    locations.push_back("/usr/local/lib/vst3");
#endif

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
                auto cidResult = component->getControllerClassId(controller_cid);
                fprintf(stderr, "🔌 [C++] getControllerClassId result=%d\n", cidResult);
                fflush(stderr);

                if (cidResult == kResultOk) {
                    auto controller = factory.createInstance<IEditController>(VST3::UID::fromTUID(controller_cid));
                    fprintf(stderr, "🔌 [C++] Separate controller created: %s\n", controller ? "yes" : "no");
                    fflush(stderr);

                    if (controller) {
                        instance->controller = controller;
                        controller->initialize(g_host_app);

                        // Set the component handler on the controller
                        // This allows the plugin to notify us of parameter changes, restarts, etc.
                        if (g_component_handler) {
                            controller->setComponentHandler(g_component_handler);
                        }

                        // Connect component and controller via IConnectionPoint
                        // This allows them to communicate - required by many plugins
                        FUnknownPtr<IConnectionPoint> componentCP(component);
                        FUnknownPtr<IConnectionPoint> controllerCP(controller);

                        if (componentCP && controllerCP) {
                            componentCP->connect(controllerCP);
                            controllerCP->connect(componentCP);
                            fprintf(stderr, "🔌 [C++] Connected component <-> controller via IConnectionPoint\n");
                            fflush(stderr);
                        }
                    }
                }

                // Fallback: some plugins implement IEditController on the component itself
                // (no separate controller class). Query the component directly.
                if (!instance->controller) {
                    FUnknownPtr<IEditController> controllerFromComponent(component);
                    if (controllerFromComponent) {
                        instance->controller = controllerFromComponent;
                        fprintf(stderr, "🔌 [C++] Controller found on component itself (combined mode)\n");
                        fflush(stderr);

                        // Don't call initialize() — already initialized as part of the component
                        if (g_component_handler) {
                            controllerFromComponent->setComponentHandler(g_component_handler);
                        }
                    } else {
                        fprintf(stderr, "⚠️ [C++] No controller found — neither separate nor on component\n");
                        fflush(stderr);
                    }
                }

                fprintf(stderr, "🔌 [C++] Plugin loaded: controller=%s, processor=%s\n",
                        instance->controller ? "yes" : "NO",
                        instance->processor ? "yes" : "NO");
                fflush(stderr);

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
    fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: handle=%p\n", handle);
    fflush(stderr);
    if (!handle) return;

    auto instance = static_cast<VST3PluginInstance*>(handle);

    // Check if this is a combined component/controller (same object)
    bool isCombinedMode = (instance->component && instance->controller &&
        instance->component.get() == FUnknownPtr<IComponent>(instance->controller).get());
    fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: combinedMode=%d, active=%d\n",
            isCombinedMode, instance->active);
    fflush(stderr);

    // Close editor first if still open
    if (instance->editor_open) {
        fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: closing editor first\n");
        fflush(stderr);
        vst3_close_editor(handle);
    }

    // Deactivate if active
    if (instance->active && instance->processor) {
        fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: setProcessing(false)\n");
        fflush(stderr);
        try {
            instance->processor->setProcessing(false);
        } catch (...) {
            fprintf(stderr, "💥 [C++] vst3_unload_plugin: CRASH in setProcessing(false)\n");
            fflush(stderr);
        }
        instance->active = false;
    }

    // Disconnect component and controller via IConnectionPoint before terminating
    // Skip for combined mode (same object — disconnecting from self is meaningless)
    if (instance->component && instance->controller && !isCombinedMode) {
        FUnknownPtr<IConnectionPoint> componentCP(instance->component);
        FUnknownPtr<IConnectionPoint> controllerCP(instance->controller);

        if (componentCP && controllerCP) {
            fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: disconnecting IConnectionPoint\n");
            fflush(stderr);
            try {
                componentCP->disconnect(controllerCP);
                controllerCP->disconnect(componentCP);
            } catch (...) {
                fprintf(stderr, "💥 [C++] vst3_unload_plugin: CRASH in disconnect\n");
                fflush(stderr);
            }
        }
    }

    // Cleanup — for combined mode, only terminate once (component == controller)
    if (isCombinedMode) {
        fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: combined mode — terminating component only\n");
        fflush(stderr);
        try {
            instance->controller = nullptr;  // Release ref without terminate
            instance->component->terminate();
        } catch (...) {
            fprintf(stderr, "💥 [C++] vst3_unload_plugin: CRASH in component->terminate()\n");
            fflush(stderr);
        }
    } else {
        if (instance->controller) {
            fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: terminating controller\n");
            fflush(stderr);
            try {
                instance->controller->terminate();
            } catch (...) {
                fprintf(stderr, "💥 [C++] vst3_unload_plugin: CRASH in controller->terminate()\n");
                fflush(stderr);
            }
        }

        if (instance->component) {
            fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: terminating component\n");
            fflush(stderr);
            try {
                instance->component->terminate();
            } catch (...) {
                fprintf(stderr, "💥 [C++] vst3_unload_plugin: CRASH in component->terminate()\n");
                fflush(stderr);
            }
        }
    }

    fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: deleting instance\n");
    fflush(stderr);
    delete instance;
    fprintf(stderr, "🗑️ [C++] vst3_unload_plugin: complete\n");
    fflush(stderr);
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
    fprintf(stdout, "🎛️ [C++] vst3_initialize_plugin called: handle=%p, sample_rate=%f, block_size=%d\n",
            handle, sample_rate, max_block_size);
    fflush(stdout);

    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->processor) {
        set_error("No audio processor interface");
        fprintf(stderr, "❌ [C++] vst3_initialize_plugin: No audio processor interface\n");
        fflush(stderr);
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

    tresult setupResult = instance->processor->setupProcessing(setup);
    fprintf(stdout, "🎛️ [C++] setupProcessing result: %d\n", setupResult);
    fflush(stdout);

    if (setupResult != kResultOk) {
        set_error("Failed to setup processing");
        return false;
    }

    // Activate busses
    tresult inputBusResult = instance->component->activateBus(kAudio, kInput, 0, true);
    fprintf(stdout, "🎛️ [C++] activateBus(input) result: %d\n", inputBusResult);
    fflush(stdout);
    // Some plugins don't have input (instruments) - that's OK

    tresult outputBusResult = instance->component->activateBus(kAudio, kOutput, 0, true);
    fprintf(stdout, "🎛️ [C++] activateBus(output) result: %d\n", outputBusResult);
    fflush(stdout);

    if (outputBusResult != kResultOk) {
        set_error("Failed to activate output bus");
        return false;
    }

    instance->initialized = true;
    fprintf(stdout, "✅ [C++] vst3_initialize_plugin: success\n");
    fflush(stdout);
    return true;
}

bool vst3_activate_plugin(VST3PluginHandle handle) {
    fprintf(stdout, "🎛️ [C++] vst3_activate_plugin called: handle=%p\n", handle);
    fflush(stdout);

    if (!handle) {
        set_error("Invalid handle");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->initialized || !instance->processor) {
        set_error("Plugin not initialized");
        fprintf(stderr, "❌ [C++] vst3_activate_plugin: Plugin not initialized\n");
        fflush(stderr);
        return false;
    }

    tresult result = instance->processor->setProcessing(true);
    fprintf(stdout, "🎛️ [C++] setProcessing(true) result: %d\n", result);
    fflush(stdout);

    if (result != kResultOk) {
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

    // Pass queued MIDI events to the plugin
    // For instruments, this is critical - they need MIDI to generate audio
    data.inputEvents = (instance->midi_events.getEventCount() > 0) ? &instance->midi_events : nullptr;
    data.outputEvents = nullptr;
    data.processContext = nullptr;

    // Process the audio
    tresult result = instance->processor->process(data);

    // Clear MIDI events after processing (they've been consumed)
    instance->midi_events.clear();

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

    // Add the event to the queue - will be sent during next process() call
    tresult result = instance->midi_events.addEvent(event);
    if (result != kResultOk) {
        set_error("Failed to queue MIDI event");
        return false;
    }

    return true;
}

int vst3_get_parameter_count(VST3PluginHandle handle) {
    if (!handle) {
        printf("🎛️ [C++] vst3_get_parameter_count: handle is null\n");
        return 0;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) {
        printf("🎛️ [C++] vst3_get_parameter_count: controller is null\n");
        return 0;
    }

    int count = instance->controller->getParameterCount();
    printf("🎛️ [C++] vst3_get_parameter_count: handle=%p, count=%d\n", handle, count);
    return count;
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

// ============================================================================
// Memory Stream for State Save/Load
// ============================================================================

class MemoryStream : public IBStream {
public:
    MemoryStream() : position_(0), refCount_(1) {}

    MemoryStream(const void* data, int size) : position_(0), refCount_(1) {
        buffer_.resize(size);
        std::memcpy(buffer_.data(), data, size);
    }

    virtual ~MemoryStream() = default;

    // IBStream
    tresult PLUGIN_API read(void* buffer, int32 numBytes, int32* numBytesRead) override {
        if (!buffer || numBytes < 0) return kInvalidArgument;

        int32 available = static_cast<int32>(buffer_.size()) - position_;
        int32 toRead = std::min(numBytes, available);

        if (toRead > 0) {
            std::memcpy(buffer, buffer_.data() + position_, toRead);
            position_ += toRead;
        }

        if (numBytesRead) *numBytesRead = toRead;
        return kResultOk;
    }

    tresult PLUGIN_API write(void* buffer, int32 numBytes, int32* numBytesWritten) override {
        if (!buffer || numBytes < 0) return kInvalidArgument;

        // Expand buffer if needed
        int32 endPos = position_ + numBytes;
        if (endPos > static_cast<int32>(buffer_.size())) {
            buffer_.resize(endPos);
        }

        std::memcpy(buffer_.data() + position_, buffer, numBytes);
        position_ += numBytes;

        if (numBytesWritten) *numBytesWritten = numBytes;
        return kResultOk;
    }

    tresult PLUGIN_API seek(int64 pos, int32 mode, int64* result) override {
        int64 newPos = 0;
        switch (mode) {
            case IBStream::kIBSeekSet: newPos = pos; break;
            case IBStream::kIBSeekCur: newPos = position_ + pos; break;
            case IBStream::kIBSeekEnd: newPos = static_cast<int64>(buffer_.size()) + pos; break;
            default: return kInvalidArgument;
        }

        if (newPos < 0) newPos = 0;
        position_ = static_cast<int32>(newPos);

        if (result) *result = position_;
        return kResultOk;
    }

    tresult PLUGIN_API tell(int64* pos) override {
        if (pos) *pos = position_;
        return kResultOk;
    }

    // FUnknown
    tresult PLUGIN_API queryInterface(const TUID _iid, void** obj) override {
        if (FUnknownPrivate::iidEqual(_iid, IBStream::iid) ||
            FUnknownPrivate::iidEqual(_iid, FUnknown::iid)) {
            *obj = this;
            addRef();
            return kResultTrue;
        }
        *obj = nullptr;
        return kNoInterface;
    }

    uint32 PLUGIN_API addRef() override { return ++refCount_; }
    uint32 PLUGIN_API release() override {
        uint32 count = --refCount_;
        if (count == 0) delete this;
        return count;
    }

    // Accessors
    const std::vector<uint8_t>& getData() const { return buffer_; }
    int32 getSize() const { return static_cast<int32>(buffer_.size()); }

private:
    std::vector<uint8_t> buffer_;
    int32 position_;
    std::atomic<uint32> refCount_;
};

// ============================================================================
// State Save/Load Functions
// ============================================================================

int vst3_get_state_size(VST3PluginHandle handle) {
    if (!handle) return 0;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->component) return 0;

    // Create a temporary stream to get the state size
    MemoryStream stream;

    // Get processor state
    if (instance->component->getState(&stream) != kResultOk) {
        fprintf(stderr, "❌ [C++] vst3_get_state_size: component->getState failed\n");
        return 0;
    }

    int32 processorSize = stream.getSize();

    // Get controller state if available
    int32 controllerSize = 0;
    if (instance->controller) {
        MemoryStream controllerStream;
        if (instance->controller->getState(&controllerStream) == kResultOk) {
            controllerSize = controllerStream.getSize();
        }
    }

    // Total size = 8 bytes header + processor state + controller state
    // Header format: [4 bytes processor size][4 bytes controller size]
    int totalSize = 8 + processorSize + controllerSize;

    fprintf(stderr, "📦 [C++] vst3_get_state_size: processor=%d, controller=%d, total=%d\n",
            processorSize, controllerSize, totalSize);

    return totalSize;
}

int vst3_get_state(VST3PluginHandle handle, void* data, int max_size) {
    if (!handle || !data || max_size < 8) return -1;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->component) return -1;

    // Get processor state
    MemoryStream processorStream;
    if (instance->component->getState(&processorStream) != kResultOk) {
        fprintf(stderr, "❌ [C++] vst3_get_state: component->getState failed\n");
        return -1;
    }

    // Get controller state
    MemoryStream controllerStream;
    bool hasControllerState = false;
    if (instance->controller) {
        hasControllerState = (instance->controller->getState(&controllerStream) == kResultOk);
    }

    int32 processorSize = processorStream.getSize();
    int32 controllerSize = hasControllerState ? controllerStream.getSize() : 0;
    int32 totalSize = 8 + processorSize + controllerSize;

    if (totalSize > max_size) {
        fprintf(stderr, "❌ [C++] vst3_get_state: buffer too small (%d < %d)\n", max_size, totalSize);
        return -1;
    }

    // Write header
    uint8_t* ptr = static_cast<uint8_t*>(data);
    std::memcpy(ptr, &processorSize, 4);
    std::memcpy(ptr + 4, &controllerSize, 4);
    ptr += 8;

    // Write processor state
    std::memcpy(ptr, processorStream.getData().data(), processorSize);
    ptr += processorSize;

    // Write controller state
    if (controllerSize > 0) {
        std::memcpy(ptr, controllerStream.getData().data(), controllerSize);
    }

    fprintf(stderr, "✅ [C++] vst3_get_state: saved %d bytes (processor=%d, controller=%d)\n",
            totalSize, processorSize, controllerSize);

    return totalSize;
}

bool vst3_set_state(VST3PluginHandle handle, const void* data, int size) {
    if (!handle || !data || size < 8) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->component) return false;

    // Read header
    const uint8_t* ptr = static_cast<const uint8_t*>(data);
    int32 processorSize, controllerSize;
    std::memcpy(&processorSize, ptr, 4);
    std::memcpy(&controllerSize, ptr + 4, 4);
    ptr += 8;

    // Validate sizes
    if (8 + processorSize + controllerSize > size) {
        fprintf(stderr, "❌ [C++] vst3_set_state: invalid sizes (header says %d, got %d)\n",
                8 + processorSize + controllerSize, size);
        return false;
    }

    fprintf(stderr, "📦 [C++] vst3_set_state: loading %d bytes (processor=%d, controller=%d)\n",
            size, processorSize, controllerSize);

    // Set processor state
    if (processorSize > 0) {
        MemoryStream processorStream(ptr, processorSize);
        if (instance->component->setState(&processorStream) != kResultOk) {
            fprintf(stderr, "❌ [C++] vst3_set_state: component->setState failed\n");
            return false;
        }
        ptr += processorSize;

        // Also sync to controller (important for parameter display)
        if (instance->controller) {
            MemoryStream processorStream2(ptr - processorSize, processorSize);
            instance->controller->setComponentState(&processorStream2);
        }
    }

    // Set controller state
    if (controllerSize > 0 && instance->controller) {
        MemoryStream controllerStream(ptr, controllerSize);
        if (instance->controller->setState(&controllerStream) != kResultOk) {
            fprintf(stderr, "⚠️ [C++] vst3_set_state: controller->setState failed (non-fatal)\n");
            // Controller state is optional, don't fail
        }
    }

    fprintf(stderr, "✅ [C++] vst3_set_state: state restored successfully\n");
    return true;
}

// ============================================================================
// M7 Phase 1: Native Editor Support
// ============================================================================

bool vst3_has_editor(VST3PluginHandle handle) {
    fprintf(stderr, "🖥️ [C++] vst3_has_editor: handle=%p\n", handle);
    fflush(stderr);

    if (!handle) {
        fprintf(stderr, "🖥️ [C++] vst3_has_editor: handle is null → false\n");
        fflush(stderr);
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) {
        fprintf(stderr, "🖥️ [C++] vst3_has_editor: controller is null → false\n");
        fflush(stderr);
        return false;
    }

    // Check if controller supports creating an editor view
    auto view = instance->controller->createView(ViewType::kEditor);
    if (view) {
        view->release();
        fprintf(stderr, "🖥️ [C++] vst3_has_editor: createView succeeded → true\n");
        fflush(stderr);
        return true;
    }

    fprintf(stderr, "🖥️ [C++] vst3_has_editor: createView returned null → false\n");
    fflush(stderr);
    return false;
}

bool vst3_open_editor(VST3PluginHandle handle) {
    fprintf(stderr, "🎨 [C++] vst3_open_editor called: handle=%p\n", handle);

    if (!handle) {
        set_error("Invalid handle");
        fprintf(stderr, "❌ [C++] vst3_open_editor: handle is null\n");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);

    if (!instance->controller) {
        set_error("No edit controller available");
        fprintf(stderr, "❌ [C++] vst3_open_editor: no edit controller\n");
        return false;
    }

    if (instance->editor_open) {
        // Already open is okay, just return success
        fprintf(stderr, "⏭️ [C++] vst3_open_editor: editor already open\n");
        return true;
    }

    // Create the editor view
    fprintf(stderr, "📝 [C++] Creating editor view via controller->createView\n");
    auto view = instance->controller->createView(ViewType::kEditor);
    if (!view) {
        set_error("Failed to create editor view");
        fprintf(stderr, "❌ [C++] vst3_open_editor: createView returned null\n");
        return false;
    }

    instance->editor_view = view;
    instance->editor_open = true;

    fprintf(stderr, "✅ [C++] vst3_open_editor: success, editor_view=%p\n", (void*)view);

    return true;
}

void vst3_close_editor(VST3PluginHandle handle) {
    fprintf(stderr, "🔒 [C++] vst3_close_editor: handle=%p\n", handle);
    fflush(stderr);
    if (!handle) return;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    fprintf(stderr, "🔒 [C++] vst3_close_editor: editor_open=%d, parent_window=%p, editor_view=%p\n",
            instance->editor_open, instance->parent_window,
            instance->editor_view ? (void*)instance->editor_view.get() : nullptr);
    fflush(stderr);

    if (instance->editor_view) {
        // Clear the frame first
        fprintf(stderr, "🔒 [C++] vst3_close_editor: setFrame(nullptr)\n");
        fflush(stderr);
        try {
            instance->editor_view->setFrame(nullptr);
        } catch (...) {
            fprintf(stderr, "💥 [C++] vst3_close_editor: CRASH in setFrame(nullptr)\n");
            fflush(stderr);
        }

        // Detach from parent if attached
        if (instance->parent_window) {
            fprintf(stderr, "🔒 [C++] vst3_close_editor: calling removed()\n");
            fflush(stderr);
            try {
                instance->editor_view->removed();
            } catch (...) {
                fprintf(stderr, "💥 [C++] vst3_close_editor: CRASH in removed()\n");
                fflush(stderr);
            }
            instance->parent_window = nullptr;
        }

        // Release the view
        fprintf(stderr, "🔒 [C++] vst3_close_editor: releasing editor_view\n");
        fflush(stderr);
        instance->editor_view = nullptr;
    }

    // Release the plug frame
    fprintf(stderr, "🔒 [C++] vst3_close_editor: releasing plug_frame\n");
    fflush(stderr);
    instance->plug_frame = nullptr;

    instance->editor_open = false;
    fprintf(stderr, "🔒 [C++] vst3_close_editor: complete\n");
    fflush(stderr);
}

bool vst3_get_editor_size(VST3PluginHandle handle, int* width, int* height) {
    fprintf(stderr, "📏 [C++] vst3_get_editor_size: handle=%p\n", handle);
    fflush(stderr);

    if (!handle || !width || !height) {
        set_error("Invalid parameters");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->editor_view) {
        set_error("No editor view available");
        fprintf(stderr, "❌ [C++] vst3_get_editor_size: editor_view is null\n");
        fflush(stderr);
        return false;
    }

    ViewRect rect;
    auto result = instance->editor_view->getSize(&rect);
    if (result != kResultOk) {
        set_error("Failed to get editor size");
        fprintf(stderr, "❌ [C++] vst3_get_editor_size: getSize() failed, result=%d\n", result);
        fflush(stderr);
        return false;
    }

    *width = rect.right - rect.left;
    *height = rect.bottom - rect.top;

    fprintf(stderr, "📏 [C++] vst3_get_editor_size: rect=(%d,%d,%d,%d) → %dx%d\n",
            rect.left, rect.top, rect.right, rect.bottom, *width, *height);
    fflush(stderr);

    return true;
}

bool vst3_attach_editor(VST3PluginHandle handle, void* parent) {
    fprintf(stderr, "📤 [C++] vst3_attach_editor: handle=%p, parent=%p\n", handle, parent);
    fflush(stderr);

    if (!handle) {
        set_error("Invalid handle (null)");
        return false;
    }

    if (!parent) {
        set_error("Invalid parent (null)");
        return false;
    }

    auto instance = static_cast<VST3PluginInstance*>(handle);

    if (!instance->editor_open) {
        set_error("Editor not opened - call vst3_open_editor first");
        fprintf(stderr, "❌ [C++] vst3_attach_editor: editor not opened\n");
        fflush(stderr);
        return false;
    }

    if (!instance->editor_view) {
        set_error("No editor view available (editor_view is null)");
        fprintf(stderr, "❌ [C++] vst3_attach_editor: editor_view is null\n");
        fflush(stderr);
        return false;
    }

    // Detach from previous parent if needed.
    // IMPORTANT: Don't call editor_view->removed() here — the old parent NSView
    // may have been deallocated by Flutter's platform view lifecycle.
    // Instead, release the old IPlugView entirely and create a fresh one.
    if (instance->parent_window) {
        fprintf(stderr, "📤 [C++] vst3_attach_editor: recreating editor view (old parent=%p)\n", instance->parent_window);
        fflush(stderr);
        instance->editor_view->setFrame(nullptr);
        instance->editor_view = nullptr;
        instance->plug_frame = nullptr;
        instance->parent_window = nullptr;
        instance->editor_open = false;

        auto fresh_view = instance->controller->createView(ViewType::kEditor);
        if (!fresh_view) {
            set_error("Failed to recreate editor view after stale detach");
            return false;
        }
        instance->editor_view = fresh_view;
        instance->editor_open = true;
    }

    IPlugView* view = instance->editor_view.get();
    if (!view) {
        set_error("IPlugView pointer is null");
        return false;
    }

    auto platformResult = view->isPlatformTypeSupported(kPlatformTypeNSView);
    fprintf(stderr, "📤 [C++] vst3_attach_editor: isPlatformTypeSupported(NSView)=%d\n", platformResult);
    fflush(stderr);
    if (platformResult != kResultTrue) {
        set_error("Plugin does not support NSView platform type");
        fprintf(stderr, "❌ [C++] vst3_attach_editor: NSView not supported\n");
        fflush(stderr);
        return false;
    }

    // Store the plugin's preferred size
    ViewRect preferredSize;
    auto sizeResult = view->getSize(&preferredSize);
    if (sizeResult == kResultOk) {
        instance->preferred_editor_width = preferredSize.right - preferredSize.left;
        instance->preferred_editor_height = preferredSize.bottom - preferredSize.top;
        fprintf(stderr, "📤 [C++] vst3_attach_editor: preferredSize=%dx%d (rect=%d,%d,%d,%d)\n",
                instance->preferred_editor_width, instance->preferred_editor_height,
                preferredSize.left, preferredSize.top, preferredSize.right, preferredSize.bottom);
    } else {
        fprintf(stderr, "⚠️ [C++] vst3_attach_editor: getSize() failed, result=%d\n", sizeResult);
    }
    fflush(stderr);

    // CRITICAL: Create and set the IPlugFrame BEFORE calling attached()
    if (!instance->plug_frame) {
        instance->plug_frame = owned(new PlugFrame(instance));
    }
    view->setFrame(instance->plug_frame.get());
    fprintf(stderr, "📤 [C++] vst3_attach_editor: setFrame done, calling attached(parent=%p)\n", parent);
    fflush(stderr);

    // Call attached()
    tresult result;
    try {
        result = view->attached(parent, kPlatformTypeNSView);
    } catch (const std::exception& e) {
        fprintf(stderr, "❌ [C++] Exception in attached(): %s\n", e.what());
        fflush(stderr);
        set_error("C++ exception in IPlugView->attached()");
        return false;
    } catch (...) {
        fprintf(stderr, "❌ [C++] Unknown exception in attached()\n");
        fflush(stderr);
        set_error("Unknown exception in IPlugView->attached()");
        return false;
    }

    fprintf(stderr, "📤 [C++] vst3_attach_editor: attached() returned %d\n", result);
    fflush(stderr);

    if (result != kResultOk) {
        set_error("Failed to attach editor to parent window");
        fprintf(stderr, "❌ [C++] vst3_attach_editor: attached() failed\n");
        fflush(stderr);
        return false;
    }

    instance->parent_window = parent;
    fprintf(stderr, "✅ [C++] vst3_attach_editor: success, parent=%p, size=%dx%d\n",
            parent, instance->preferred_editor_width, instance->preferred_editor_height);
    fflush(stderr);
    return true;
}

void vst3_set_editor_max_size(VST3PluginHandle handle, int maxW, int maxH) {
    if (!handle) return;
    auto instance = static_cast<VST3PluginInstance*>(handle);

    instance->max_editor_width = maxW;
    instance->max_editor_height = maxH;
    // In embedded mode, CATransform3D handles visual scaling on the Swift side.
    // No onSize or native resize needed — just store the max values for PlugFrame.
}

// ============================================================================
// Preset Enumeration via IUnitInfo
// ============================================================================

// Helper: convert Steinberg::Vst::String128 (UTF-16) to UTF-8 char buffer
static void string128_to_utf8(const Vst::String128& src, char* dst, int dst_len) {
    if (!dst || dst_len <= 0) return;
    int j = 0;
    for (int i = 0; i < 128 && src[i] && j < dst_len - 1; i++) {
        // Simplified: truncate to ASCII. For full Unicode, use a proper converter.
        char16_t ch = static_cast<char16_t>(src[i]);
        if (ch < 0x80) {
            dst[j++] = static_cast<char>(ch);
        } else if (ch < 0x800 && j + 1 < dst_len - 1) {
            dst[j++] = static_cast<char>(0xC0 | (ch >> 6));
            dst[j++] = static_cast<char>(0x80 | (ch & 0x3F));
        } else if (j + 2 < dst_len - 1) {
            dst[j++] = static_cast<char>(0xE0 | (ch >> 12));
            dst[j++] = static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
            dst[j++] = static_cast<char>(0x80 | (ch & 0x3F));
        }
    }
    dst[j] = '\0';
}

int vst3_get_program_list_count(VST3PluginHandle handle) {
    if (!handle) return 0;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return 0;

    FUnknownPtr<IUnitInfo> unitInfo(instance->controller);
    if (!unitInfo) return 0;

    return unitInfo->getProgramListCount();
}

bool vst3_get_program_list_info(
    VST3PluginHandle handle,
    int index,
    int* list_id,
    char* name,
    int name_len,
    int* count
) {
    if (!handle || !list_id || !name || !count) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return false;

    FUnknownPtr<IUnitInfo> unitInfo(instance->controller);
    if (!unitInfo) return false;

    ProgramListInfo info;
    if (unitInfo->getProgramListInfo(index, info) != kResultOk) {
        return false;
    }

    *list_id = info.id;
    *count = info.programCount;
    string128_to_utf8(info.name, name, name_len);

    return true;
}

bool vst3_get_program_name(
    VST3PluginHandle handle,
    int list_id,
    int program_index,
    char* name,
    int name_len
) {
    if (!handle || !name) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return false;

    FUnknownPtr<IUnitInfo> unitInfo(instance->controller);
    if (!unitInfo) return false;

    String128 name128;
    if (unitInfo->getProgramName(list_id, program_index, name128) != kResultOk) {
        return false;
    }

    string128_to_utf8(name128, name, name_len);
    return true;
}

bool vst3_set_program(
    VST3PluginHandle handle,
    int list_id,
    int program_index
) {
    if (!handle) return false;

    auto instance = static_cast<VST3PluginInstance*>(handle);
    if (!instance->controller) return false;

    // Find the parameter that controls program selection for this list.
    // VST3 uses a special parameter with the ProgramListID to switch programs.
    // We iterate parameters to find one associated with this program list.
    int param_count = instance->controller->getParameterCount();
    for (int i = 0; i < param_count; i++) {
        ParameterInfo param_info;
        if (instance->controller->getParameterInfo(i, param_info) == kResultOk) {
            if (param_info.flags & ParameterInfo::kIsProgramChange) {
                // Found a program change parameter.
                // In VST3, program change is set as normalized value:
                // value = programIndex / (programCount - 1)
                // We need the program count from the list.
                FUnknownPtr<IUnitInfo> unitInfo(instance->controller);
                if (!unitInfo) return false;

                int list_count = unitInfo->getProgramListCount();
                for (int li = 0; li < list_count; li++) {
                    ProgramListInfo pl_info;
                    if (unitInfo->getProgramListInfo(li, pl_info) == kResultOk) {
                        if (pl_info.id == list_id && pl_info.programCount > 0) {
                            double value = (pl_info.programCount > 1)
                                ? static_cast<double>(program_index) / static_cast<double>(pl_info.programCount - 1)
                                : 0.0;

                            // Set parameter on controller
                            instance->controller->setParamNormalized(param_info.id, value);

                            // Also push to component via IComponentHandler pattern
                            // This ensures the processor gets the update
                            if (instance->component) {
                                FUnknownPtr<IEditController> editCtrl(instance->controller);
                                if (editCtrl) {
                                    editCtrl->setParamNormalized(param_info.id, value);
                                }
                            }

                            return true;
                        }
                    }
                }
            }
        }
    }

    set_error("No program change parameter found for list " + std::to_string(list_id));
    return false;
}

const char* vst3_get_last_error() {
    return g_last_error.c_str();
}
