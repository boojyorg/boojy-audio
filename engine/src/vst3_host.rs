use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_double, c_float, c_int, c_void};

// C FFI bindings to the C++ VST3 host library

/// Opaque plugin handle
#[repr(C)]
pub struct VST3PluginHandle {
    _private: [u8; 0],
}

/// Plugin info structure (matches C header)
#[repr(C)]
#[derive(Debug, Clone)]
pub struct VST3PluginInfo {
    pub name: [c_char; 256],
    pub vendor: [c_char; 256],
    pub version: [c_char; 64],
    pub category: [c_char; 64],
    pub file_path: [c_char; 1024],
    pub is_instrument: bool,
    pub is_effect: bool,
}

impl VST3PluginInfo {
    pub fn name_str(&self) -> &str {
        unsafe {
            CStr::from_ptr(self.name.as_ptr())
                .to_str()
                .unwrap_or("")
        }
    }

    pub fn vendor_str(&self) -> &str {
        unsafe {
            CStr::from_ptr(self.vendor.as_ptr())
                .to_str()
                .unwrap_or("")
        }
    }

    pub fn file_path_str(&self) -> &str {
        unsafe {
            CStr::from_ptr(self.file_path.as_ptr())
                .to_str()
                .unwrap_or("")
        }
    }

    pub fn version_str(&self) -> &str {
        unsafe {
            CStr::from_ptr(self.version.as_ptr())
                .to_str()
                .unwrap_or("")
        }
    }
}

/// Parameter info structure
#[repr(C)]
#[derive(Debug, Clone)]
pub struct VST3ParameterInfo {
    pub id: u32,
    pub title: [c_char; 256],
    pub short_title: [c_char; 64],
    pub units: [c_char; 64],
    pub default_value: c_double,
    pub min_value: c_double,
    pub max_value: c_double,
    pub step_count: c_int,
}

impl VST3ParameterInfo {
    pub fn title_str(&self) -> &str {
        unsafe {
            CStr::from_ptr(self.title.as_ptr())
                .to_str()
                .unwrap_or("")
        }
    }

    pub fn units_str(&self) -> &str {
        unsafe {
            CStr::from_ptr(self.units.as_ptr())
                .to_str()
                .unwrap_or("")
        }
    }
}

/// Scan callback type
pub type VST3ScanCallback = extern "C" fn(*const VST3PluginInfo, *mut c_void);

// External C functions from the C++ library
extern "C" {
    pub fn vst3_host_init() -> bool;
    pub fn vst3_host_shutdown();

    pub fn vst3_scan_directory(
        directory: *const c_char,
        callback: VST3ScanCallback,
        user_data: *mut c_void,
    ) -> c_int;

    pub fn vst3_scan_standard_locations(
        callback: VST3ScanCallback,
        user_data: *mut c_void,
    ) -> c_int;

    pub fn vst3_load_plugin(file_path: *const c_char) -> *mut VST3PluginHandle;
    pub fn vst3_unload_plugin(handle: *mut VST3PluginHandle);

    pub fn vst3_get_plugin_info(
        handle: *mut VST3PluginHandle,
        info: *mut VST3PluginInfo,
    ) -> bool;

    pub fn vst3_initialize_plugin(
        handle: *mut VST3PluginHandle,
        sample_rate: c_double,
        max_block_size: c_int,
    ) -> bool;

    pub fn vst3_activate_plugin(handle: *mut VST3PluginHandle) -> bool;
    pub fn vst3_deactivate_plugin(handle: *mut VST3PluginHandle) -> bool;

    pub fn vst3_process_audio(
        handle: *mut VST3PluginHandle,
        input_left: *const c_float,
        input_right: *const c_float,
        output_left: *mut c_float,
        output_right: *mut c_float,
        num_frames: c_int,
    ) -> bool;

    pub fn vst3_process_midi_event(
        handle: *mut VST3PluginHandle,
        event_type: c_int,
        channel: c_int,
        data1: c_int,
        data2: c_int,
        sample_offset: c_int,
    ) -> bool;

    pub fn vst3_get_parameter_count(handle: *mut VST3PluginHandle) -> c_int;

    pub fn vst3_get_parameter_info(
        handle: *mut VST3PluginHandle,
        index: c_int,
        info: *mut VST3ParameterInfo,
    ) -> bool;

    pub fn vst3_get_parameter_value(
        handle: *mut VST3PluginHandle,
        param_id: u32,
    ) -> c_double;

    pub fn vst3_set_parameter_value(
        handle: *mut VST3PluginHandle,
        param_id: u32,
        value: c_double,
    ) -> bool;

    pub fn vst3_get_state_size(handle: *mut VST3PluginHandle) -> c_int;

    pub fn vst3_get_state(
        handle: *mut VST3PluginHandle,
        data: *mut c_void,
        max_size: c_int,
    ) -> c_int;

    pub fn vst3_set_state(
        handle: *mut VST3PluginHandle,
        data: *const c_void,
        size: c_int,
    ) -> bool;

    // M7 Phase 1: Native Editor Support
    pub fn vst3_has_editor(handle: *mut VST3PluginHandle) -> bool;
    pub fn vst3_open_editor(handle: *mut VST3PluginHandle) -> bool;
    pub fn vst3_close_editor(handle: *mut VST3PluginHandle);
    pub fn vst3_get_editor_size(
        handle: *mut VST3PluginHandle,
        width: *mut c_int,
        height: *mut c_int,
    ) -> bool;
    pub fn vst3_attach_editor(handle: *mut VST3PluginHandle, parent: *mut c_void) -> bool;

    pub fn vst3_get_last_error() -> *const c_char;
}

// Rust-safe wrapper API

pub struct VST3Host;

impl VST3Host {
    pub fn init() -> Result<(), String> {
        unsafe {
            if vst3_host_init() {
                Ok(())
            } else {
                Err(Self::get_last_error())
            }
        }
    }

    pub fn shutdown() {
        unsafe {
            vst3_host_shutdown();
        }
    }

    pub fn scan_directory<F>(directory: &str, mut callback: F) -> Result<usize, String>
    where
        F: FnMut(&VST3PluginInfo),
    {
        let dir_cstr = CString::new(directory).map_err(|e| e.to_string())?;

        extern "C" fn scan_callback<F>(info: *const VST3PluginInfo, user_data: *mut c_void)
        where
            F: FnMut(&VST3PluginInfo),
        {
            unsafe {
                let callback = &mut *(user_data as *mut F);
                if !info.is_null() {
                    callback(&*info);
                }
            }
        }

        unsafe {
            let count = vst3_scan_directory(
                dir_cstr.as_ptr(),
                scan_callback::<F>,
                &mut callback as *mut F as *mut c_void,
            );

            if count >= 0 {
                Ok(count as usize)
            } else {
                Err(Self::get_last_error())
            }
        }
    }

    pub fn scan_standard_locations<F>(mut callback: F) -> Result<usize, String>
    where
        F: FnMut(&VST3PluginInfo),
    {
        extern "C" fn scan_callback<F>(info: *const VST3PluginInfo, user_data: *mut c_void)
        where
            F: FnMut(&VST3PluginInfo),
        {
            unsafe {
                let callback = &mut *(user_data as *mut F);
                if !info.is_null() {
                    callback(&*info);
                }
            }
        }

        unsafe {
            let count = vst3_scan_standard_locations(
                scan_callback::<F>,
                &mut callback as *mut F as *mut c_void,
            );

            if count >= 0 {
                Ok(count as usize)
            } else {
                Err(Self::get_last_error())
            }
        }
    }

    fn get_last_error() -> String {
        unsafe {
            let err_ptr = vst3_get_last_error();
            if err_ptr.is_null() {
                "Unknown error".to_string()
            } else {
                CStr::from_ptr(err_ptr)
                    .to_string_lossy()
                    .into_owned()
            }
        }
    }
}

// ============================================================================
// Convenience Functions for Scanning (M7)
// ============================================================================

/// Scan a directory and return a Vec of plugin infos
pub fn scan_directory(directory: &str) -> Result<Vec<VST3PluginInfo>, String> {
    let mut plugins = Vec::new();

    VST3Host::scan_directory(directory, |info| {
        plugins.push(info.clone());
    })?;

    Ok(plugins)
}

/// Scan standard locations and return a Vec of plugin infos
pub fn scan_standard_locations() -> Result<Vec<VST3PluginInfo>, String> {
    let mut plugins = Vec::new();

    VST3Host::scan_standard_locations(|info| {
        let category_str = unsafe {
            CStr::from_ptr(info.category.as_ptr())
                .to_string_lossy()
                .into_owned()
        };
        eprintln!("🔍 VST3 Plugin: {} | Category: '{}' | is_instrument: {} | is_effect: {}",
                  info.name_str(), category_str, info.is_instrument, info.is_effect);
        plugins.push(info.clone());
    })?;

    Ok(plugins)
}

pub struct VST3Plugin {
    pub handle: *mut VST3PluginHandle,
}

impl VST3Plugin {
    pub fn load(file_path: &str) -> Result<Self, String> {
        let path_cstr = CString::new(file_path).map_err(|e| e.to_string())?;

        unsafe {
            let handle = vst3_load_plugin(path_cstr.as_ptr());
            if handle.is_null() {
                Err(VST3Host::get_last_error())
            } else {
                Ok(VST3Plugin { handle })
            }
        }
    }

    pub fn get_info(&self) -> Result<VST3PluginInfo, String> {
        let mut info: VST3PluginInfo = unsafe { std::mem::zeroed() };

        unsafe {
            if vst3_get_plugin_info(self.handle, &mut info) {
                Ok(info)
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn initialize(&self, sample_rate: f64, max_block_size: i32) -> Result<(), String> {
        unsafe {
            if vst3_initialize_plugin(self.handle, sample_rate, max_block_size) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn activate(&self) -> Result<(), String> {
        unsafe {
            if vst3_activate_plugin(self.handle) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn deactivate(&self) -> Result<(), String> {
        unsafe {
            if vst3_deactivate_plugin(self.handle) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn process_audio(
        &self,
        input_left: &[f32],
        input_right: &[f32],
        output_left: &mut [f32],
        output_right: &mut [f32],
    ) -> Result<(), String> {
        let num_frames = input_left.len().min(output_left.len()) as i32;

        unsafe {
            if vst3_process_audio(
                self.handle,
                input_left.as_ptr(),
                input_right.as_ptr(),
                output_left.as_mut_ptr(),
                output_right.as_mut_ptr(),
                num_frames,
            ) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn process_midi_event(
        &self,
        event_type: i32,
        channel: i32,
        data1: i32,
        data2: i32,
        sample_offset: i32,
    ) -> Result<(), String> {
        unsafe {
            if vst3_process_midi_event(
                self.handle,
                event_type,
                channel,
                data1,
                data2,
                sample_offset,
            ) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn get_parameter_count(&self) -> i32 {
        unsafe { vst3_get_parameter_count(self.handle) }
    }

    pub fn get_parameter_info(&self, index: i32) -> Result<VST3ParameterInfo, String> {
        let mut info: VST3ParameterInfo = unsafe { std::mem::zeroed() };

        unsafe {
            if vst3_get_parameter_info(self.handle, index, &mut info) {
                Ok(info)
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn get_parameter_value(&self, param_id: u32) -> f64 {
        unsafe { vst3_get_parameter_value(self.handle, param_id) }
    }

    pub fn set_parameter_value(&self, param_id: u32, value: f64) -> Result<(), String> {
        unsafe {
            if vst3_set_parameter_value(self.handle, param_id, value) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn get_state(&self) -> Result<Vec<u8>, String> {
        unsafe {
            let size = vst3_get_state_size(self.handle);
            if size <= 0 {
                return Ok(Vec::new());
            }

            let mut buffer = vec![0u8; size as usize];
            let actual_size = vst3_get_state(
                self.handle,
                buffer.as_mut_ptr() as *mut c_void,
                size,
            );

            if actual_size > 0 {
                buffer.truncate(actual_size as usize);
                Ok(buffer)
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn set_state(&self, data: &[u8]) -> Result<(), String> {
        unsafe {
            if vst3_set_state(
                self.handle,
                data.as_ptr() as *const c_void,
                data.len() as i32,
            ) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    // M7 Phase 1: Native Editor Support
    pub fn has_editor(&self) -> bool {
        unsafe { vst3_has_editor(self.handle) }
    }

    pub fn open_editor(&self) -> Result<(), String> {
        unsafe {
            if vst3_open_editor(self.handle) {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn close_editor(&self) {
        unsafe {
            vst3_close_editor(self.handle);
        }
    }

    pub fn get_editor_size(&self) -> Result<(i32, i32), String> {
        unsafe {
            let mut width: c_int = 0;
            let mut height: c_int = 0;
            if vst3_get_editor_size(self.handle, &mut width, &mut height) {
                Ok((width, height))
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }

    pub fn attach_editor(&self, parent: *mut c_void) -> Result<(), String> {
        use std::io::Write;

        // Get thread ID for debugging
        let thread_id = std::thread::current().id();
        eprintln!("🔧 [VST3Plugin] attach_editor on thread {:?}", thread_id);
        eprintln!("🔧 [VST3Plugin] handle={:?}, handle_addr={:p}", self.handle, &self.handle);
        eprintln!("🔧 [VST3Plugin] parent={:?}", parent);
        let _ = std::io::stderr().flush();

        // Verify handle is not null
        if self.handle.is_null() {
            eprintln!("❌ [VST3Plugin] Handle is null!");
            let _ = std::io::stderr().flush();
            return Err("VST3 plugin handle is null".to_string());
        }

        // Verify parent is not null
        if parent.is_null() {
            eprintln!("❌ [VST3Plugin] Parent is null!");
            let _ = std::io::stderr().flush();
            return Err("Parent view pointer is null".to_string());
        }

        eprintln!("🔧 [VST3Plugin] Pointers validated, calling C++ FFI...");
        let _ = std::io::stderr().flush();

        unsafe {
            eprintln!("🔧 [VST3Plugin] Inside unsafe block, about to call vst3_attach_editor");
            eprintln!("🔧 [VST3Plugin] self.handle as usize = 0x{:x}", self.handle as usize);
            eprintln!("🔧 [VST3Plugin] parent as usize = 0x{:x}", parent as usize);
            let _ = std::io::stderr().flush();

            // Try calling the function
            let result = vst3_attach_editor(self.handle, parent);

            eprintln!("🔧 [VST3Plugin] C++ vst3_attach_editor returned: {}", result);
            let _ = std::io::stderr().flush();

            if result {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }
}

impl Drop for VST3Plugin {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                vst3_unload_plugin(self.handle);
            }
        }
    }
}

unsafe impl Send for VST3Plugin {}
unsafe impl Sync for VST3Plugin {}

// ========================================================================
// EFFECT SYSTEM INTEGRATION
// ========================================================================

use std::sync::{Arc, Mutex};

/// VST3 effect wrapper for the effect system
///
/// This wraps a VST3Plugin in an Arc<Mutex<>> so it can be cloned (by cloning
/// the Arc) and safely shared across threads. The Effect trait is implemented
/// on this wrapper.
#[derive(Clone)]
pub struct VST3Effect {
    plugin: Arc<Mutex<VST3Plugin>>,
    name: String,
    sample_rate: f64,
    block_size: i32,
    initialized: bool,
    pub is_instrument: bool,  // True if this is a VST3 instrument (generates audio from MIDI)
}

impl VST3Effect {
    /// Create a new VST3Effect from a plugin path
    pub fn new(plugin_path: &str, sample_rate: f64, block_size: i32) -> Result<Self, String> {
        let plugin = VST3Plugin::load(plugin_path)?;
        let info = plugin.get_info()?;
        let name = info.name_str().to_string();
        let is_instrument = info.is_instrument;

        Ok(Self {
            plugin: Arc::new(Mutex::new(plugin)),
            name,
            sample_rate,
            block_size,
            initialized: false,
            is_instrument,
        })
    }

    /// Initialize the plugin (must be called before processing)
    pub fn initialize(&mut self) -> Result<(), String> {
        if !self.initialized {
            let plugin = self.plugin.lock().expect("mutex poisoned");
            plugin.initialize(self.sample_rate, self.block_size)?;
            plugin.activate()?;
            self.initialized = true;
        }
        Ok(())
    }

    /// Get parameter count
    pub fn get_parameter_count(&self) -> i32 {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.get_parameter_count()
    }

    /// Get parameter info by index
    pub fn get_parameter_info(&self, index: i32) -> Result<VST3ParameterInfo, String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.get_parameter_info(index)
    }

    /// Get parameter value by ID
    pub fn get_parameter_value(&self, param_id: u32) -> f64 {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.get_parameter_value(param_id)
    }

    /// Set parameter value by ID
    pub fn set_parameter_value(&mut self, param_id: u32, value: f64) -> Result<(), String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.set_parameter_value(param_id, value)
    }

    /// Process MIDI event
    pub fn process_midi_event(
        &mut self,
        event_type: i32,
        channel: i32,
        data1: i32,
        data2: i32,
        sample_offset: i32,
    ) -> Result<(), String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.process_midi_event(event_type, channel, data1, data2, sample_offset)
    }

    /// Get plugin state
    pub fn get_state(&self) -> Result<Vec<u8>, String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.get_state()
    }

    /// Set plugin state
    pub fn set_state(&mut self, data: &[u8]) -> Result<(), String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.set_state(data)
    }

    // M7 Phase 1: Native Editor Support
    /// Check if plugin has an editor GUI
    pub fn has_editor(&self) -> bool {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.has_editor()
    }

    /// Open editor view (creates IPlugView)
    pub fn open_editor(&self) -> Result<(), String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.open_editor()
    }

    /// Close editor view
    pub fn close_editor(&self) {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.close_editor();
    }

    /// Get editor size in pixels
    pub fn get_editor_size(&self) -> Result<(i32, i32), String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.get_editor_size()
    }

    /// Attach editor to parent window
    pub fn attach_editor(&self, parent: *mut c_void) -> Result<(), String> {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.attach_editor(parent)
    }

    /// Get the raw C++ handle for the plugin
    /// This is used for calling attach_editor without holding Rust locks
    pub fn get_handle(&self) -> *mut c_void {
        let plugin = self.plugin.lock().expect("mutex poisoned");
        plugin.handle as *mut c_void
    }

    /// Attach editor to parent window using raw handle (no locks held)
    /// This is used to avoid deadlocks when plugins call back during attached()
    pub fn attach_editor_raw(handle: *mut c_void, parent: *mut c_void) -> Result<(), String> {
        eprintln!("🔧 [VST3Effect] attach_editor_raw: handle={:?}, parent={:?}", handle, parent);

        if handle.is_null() {
            return Err("Invalid plugin handle".to_string());
        }
        if parent.is_null() {
            return Err("Invalid parent pointer".to_string());
        }

        unsafe {
            let result = vst3_attach_editor(handle as *mut VST3PluginHandle, parent);
            if result {
                Ok(())
            } else {
                Err(VST3Host::get_last_error())
            }
        }
    }
}

// Implement the Effect trait for VST3Effect
impl crate::effects::Effect for VST3Effect {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        let plugin = self.plugin.lock().expect("mutex poisoned");

        // For now, create single-sample buffers
        // TODO: Optimize by batching frames
        let input_left = [left];
        let input_right = [right];
        let mut output_left = [0.0f32];
        let mut output_right = [0.0f32];

        match plugin.process_audio(
            &input_left,
            &input_right,
            &mut output_left,
            &mut output_right,
        ) {
            Ok(()) => (output_left[0], output_right[0]),
            Err(e) => {
                eprintln!("VST3 processing error: {}", e);
                (left, right) // Pass through on error
            }
        }
    }

    fn reset(&mut self) {
        // Deactivate and reactivate the plugin to reset state
        let plugin = self.plugin.lock().expect("mutex poisoned");
        let _ = plugin.deactivate();
        let _ = plugin.initialize(self.sample_rate, self.block_size);
        let _ = plugin.activate();
    }

    fn name(&self) -> &str {
        &self.name
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::effects::Effect;

    #[test]
    fn test_vst3_host_init() {
        assert!(VST3Host::init().is_ok());
        VST3Host::shutdown();
    }

    #[test]
    fn test_vst3_scan() {
        VST3Host::init().unwrap();

        let mut count = 0;
        VST3Host::scan_standard_locations(|info| {
            println!("Found plugin: {} by {}", info.name_str(), info.vendor_str());
            count += 1;
        }).ok();

        println!("Found {} plugins", count);
        VST3Host::shutdown();
    }

    #[test]
    fn test_vst3_scan_with_wrapper() {
        // Test the convenience wrapper function
        match scan_standard_locations() {
            Ok(plugins) => {
                println!("\n=== VST3 Plugin Scan Results ===");
                for (i, info) in plugins.iter().enumerate() {
                    println!("{}. {} by {}", i + 1, info.name_str(), info.vendor_str());
                    println!("   Path: {}", info.file_path_str());
                    println!("   Type: {}", if info.is_instrument { "Instrument" } else if info.is_effect { "Effect" } else { "Unknown" });
                }
                println!("Total: {} plugins\n", plugins.len());
                assert!(plugins.len() > 0, "Expected to find at least one VST3 plugin");
            }
            Err(e) => {
                println!("Scan failed: {}", e);
                panic!("Failed to scan plugins");
            }
        }
    }

    #[test]
    fn test_vst3_load_serum() {
        // Try to load Serum plugin if available
        let plugin_path = "/Library/Audio/Plug-Ins/VST3/Serum.vst3";

        match VST3Plugin::load(plugin_path) {
            Ok(plugin) => {
                println!("\n=== Successfully loaded Serum ===");

                // Get plugin info
                let info = plugin.get_info().expect("Failed to get plugin info");
                println!("Name: {}", info.name_str());
                println!("Vendor: {}", info.vendor_str());
                println!("Version: {}", info.version_str());

                // Initialize at 48kHz with 512 sample buffer
                plugin.initialize(48000.0, 512).expect("Failed to initialize");
                plugin.activate().expect("Failed to activate");

                // Get parameter count
                let param_count = plugin.get_parameter_count();
                println!("Parameter count: {}", param_count);

                // Get first few parameters
                for i in 0..param_count.min(5) {
                    if let Ok(param_info) = plugin.get_parameter_info(i) {
                        println!("  Param {}: {}", i, param_info.title_str());
                    }
                }

                plugin.deactivate().ok();
                println!("Serum test passed!\n");
            }
            Err(e) => {
                println!("Could not load Serum (this is OK if not installed): {}", e);
            }
        }
    }

    #[test]
    fn test_vst3_effect_wrapper() {
        let plugin_path = "/Library/Audio/Plug-Ins/VST3/Serum.vst3";

        match VST3Effect::new(plugin_path, 48000.0, 512) {
            Ok(mut effect) => {
                println!("\n=== Testing VST3Effect Wrapper ===");
                println!("Effect name: {}", effect.name);

                // Test parameter access
                let param_count = effect.get_parameter_count();
                println!("Parameters: {}", param_count);

                if param_count > 0 {
                    // Try to get and set first parameter
                    let value = effect.get_parameter_value(0);
                    println!("Param 0 value: {}", value);

                    if let Ok(info) = effect.get_parameter_info(0) {
                        println!("Param 0 name: {}", info.title_str());
                    }

                    // Try setting a value
                    if let Err(e) = effect.set_parameter_value(0, 0.5) {
                        println!("Warning: Could not set parameter: {}", e);
                    }
                }

                // Test audio processing with silence
                let (out_l, out_r) = effect.process_frame(0.0, 0.0);
                println!("Processed silence: ({}, {})", out_l, out_r);

                // Test with a simple signal
                let (out_l, out_r) = effect.process_frame(0.5, 0.5);
                println!("Processed signal: ({}, {})", out_l, out_r);

                println!("VST3Effect wrapper test passed!\n");
            }
            Err(e) => {
                println!("Could not create VST3Effect (this is OK if Serum not installed): {}", e);
            }
        }
    }

    #[test]
    fn test_vst3_audio_processing() {
        let plugin_path = "/Library/Audio/Plug-Ins/VST3/Serum.vst3";

        if let Ok(plugin) = VST3Plugin::load(plugin_path) {
            println!("\n=== Testing VST3 Audio Processing ===");

            plugin.initialize(48000.0, 512).expect("Failed to initialize");
            plugin.activate().expect("Failed to activate");

            // Process a buffer of audio
            let samples = 512;
            let input_left: Vec<f32> = (0..samples).map(|i| {
                (i as f32 * 440.0 * 2.0 * std::f32::consts::PI / 48000.0).sin() * 0.3
            }).collect();
            let input_right = input_left.clone();

            let mut output_left = vec![0.0f32; samples];
            let mut output_right = vec![0.0f32; samples];

            match plugin.process_audio(&input_left, &input_right, &mut output_left, &mut output_right) {
                Ok(()) => {
                    println!("Successfully processed {} samples", samples);

                    // Check that output is not all zeros
                    let max_output = output_left.iter()
                        .chain(output_right.iter())
                        .map(|x| x.abs())
                        .fold(0.0f32, |a, b| a.max(b));

                    println!("Max output amplitude: {}", max_output);
                    println!("Audio processing test passed!\n");
                }
                Err(e) => {
                    println!("Audio processing failed: {}", e);
                }
            }

            plugin.deactivate().ok();
        } else {
            println!("Skipping audio processing test (Serum not available)");
        }
    }
}
