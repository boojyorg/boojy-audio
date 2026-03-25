/// Audio device selection, buffer size management, and latency control
use super::{AudioGraph, BufferSizePreset};
use crate::audio_file::TARGET_SAMPLE_RATE;
use std::sync::atomic::Ordering;

#[cfg(not(target_arch = "wasm32"))]
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

impl AudioGraph {
    // --- Latency Control Methods ---

    /// Set the preferred buffer size preset
    /// Requires restarting the audio stream to take effect (native only)
    #[cfg(not(target_arch = "wasm32"))]
    pub fn set_buffer_size(&mut self, preset: BufferSizePreset) -> anyhow::Result<()> {
        {
            let mut current = self.preferred_buffer_size.lock();
            if *current == preset {
                return Ok(()); // No change needed
            }
            *current = preset;
        }

        eprintln!("🔊 [AudioGraph] Setting buffer size to {:?} ({} samples, {:.1}ms)",
            preset, preset.samples(), preset.latency_ms());

        // Restart the audio stream with new buffer size
        self.restart_audio_stream()?;

        Ok(())
    }

    /// Get the current buffer size preset
    pub fn get_buffer_size_preset(&self) -> BufferSizePreset {
        *self.preferred_buffer_size.lock()
    }

    /// Get the actual buffer size being used (in samples)
    pub fn get_actual_buffer_size(&self) -> u32 {
        self.actual_buffer_size.load(Ordering::SeqCst)
    }

    /// Get current audio latency info
    /// Returns: (`buffer_size_samples`, `input_latency_ms`, `output_latency_ms`, `total_roundtrip_ms`)
    pub fn get_latency_info(&self) -> (u32, f32, f32, f32) {
        let buffer_samples = self.get_actual_buffer_size();

        // Use hardware-measured latency values (queried from CoreAudio on macOS)
        let input_latency_ms = *self.hardware_input_latency_ms.lock();
        let output_latency_ms = *self.hardware_output_latency_ms.lock();

        // Total roundtrip = input + output + buffer latency
        let buffer_latency_ms = buffer_samples as f32 / TARGET_SAMPLE_RATE as f32 * 1000.0;
        let total_roundtrip_ms = input_latency_ms + output_latency_ms + buffer_latency_ms;

        (buffer_samples, input_latency_ms, output_latency_ms, total_roundtrip_ms)
    }

    /// Query hardware audio latency from `CoreAudio` device (macOS only)
    /// Updates the `hardware_input_latency_ms` and `hardware_output_latency_ms` fields
    #[cfg(target_os = "macos")]
    pub(crate) fn query_coreaudio_latency(&self) -> anyhow::Result<()> {
        use coreaudio::audio_unit::{
            macos_helpers::get_default_device_id,
        };
        use coreaudio::sys::{
            kAudioDevicePropertyLatency,
            kAudioDevicePropertySafetyOffset,
            kAudioObjectPropertyScopeInput,
            kAudioObjectPropertyScopeOutput,
            AudioObjectGetPropertyData,
            AudioObjectPropertyAddress,
        };
        use std::mem::size_of;

        // Get the default output device ID
        let device_id = get_default_device_id(false) // false = output device
            .ok_or_else(|| anyhow::anyhow!("Failed to get default output device"))?;

        // Query output latency
        let mut output_latency_frames: u32 = 0;
        let mut output_safety_offset: u32 = 0;
        let mut property_size = size_of::<u32>() as u32;

        unsafe {
            // Get device latency (output)
            let mut address = AudioObjectPropertyAddress {
                mSelector: kAudioDevicePropertyLatency,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: 0,
            };
            let status = AudioObjectGetPropertyData(
                device_id,
                &raw const address,
                0,
                std::ptr::null(),
                &raw mut property_size,
                (&raw mut output_latency_frames).cast(),
            );

            if status != 0 {
                eprintln!("⚠️ [LATENCY] Failed to get output latency (status: {status})");
            } else {
                eprintln!("🎚️ [LATENCY] Output device latency: {output_latency_frames} frames");
            }

            // Get safety offset (output)
            address.mSelector = kAudioDevicePropertySafetyOffset;
            property_size = size_of::<u32>() as u32;
            let status = AudioObjectGetPropertyData(
                device_id,
                &raw const address,
                0,
                std::ptr::null(),
                &raw mut property_size,
                (&raw mut output_safety_offset).cast(),
            );

            if status != 0 {
                eprintln!("⚠️ [LATENCY] Failed to get output safety offset (status: {status})");
            } else {
                eprintln!("🎚️ [LATENCY] Output safety offset: {output_safety_offset} frames");
            }
        }

        // Query input latency
        let mut input_latency_frames: u32 = 0;
        let mut input_safety_offset: u32 = 0;

        unsafe {
            // Get device latency (input)
            let mut address = AudioObjectPropertyAddress {
                mSelector: kAudioDevicePropertyLatency,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: 0,
            };
            property_size = size_of::<u32>() as u32;
            let status = AudioObjectGetPropertyData(
                device_id,
                &raw const address,
                0,
                std::ptr::null(),
                &raw mut property_size,
                (&raw mut input_latency_frames).cast(),
            );

            if status != 0 {
                eprintln!("⚠️ [LATENCY] Failed to get input latency (status: {status})");
            } else {
                eprintln!("🎚️ [LATENCY] Input device latency: {input_latency_frames} frames");
            }

            // Get safety offset (input)
            address.mSelector = kAudioDevicePropertySafetyOffset;
            property_size = size_of::<u32>() as u32;
            let status = AudioObjectGetPropertyData(
                device_id,
                &raw const address,
                0,
                std::ptr::null(),
                &raw mut property_size,
                (&raw mut input_safety_offset).cast(),
            );

            if status != 0 {
                eprintln!("⚠️ [LATENCY] Failed to get input safety offset (status: {status})");
            } else {
                eprintln!("🎚️ [LATENCY] Input safety offset: {input_safety_offset} frames");
            }
        }

        // Convert frames to milliseconds
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        let input_latency_ms = (input_latency_frames + input_safety_offset) as f32 / sample_rate * 1000.0;
        let output_latency_ms = (output_latency_frames + output_safety_offset) as f32 / sample_rate * 1000.0;

        eprintln!("🎚️ [LATENCY] Hardware latency: input={input_latency_ms:.2}ms, output={output_latency_ms:.2}ms");

        // Update stored values
        *self.hardware_input_latency_ms.lock() = input_latency_ms;
        *self.hardware_output_latency_ms.lock() = output_latency_ms;

        Ok(())
    }

    /// Fallback for non-macOS platforms - estimates latency from buffer size
    #[cfg(not(target_os = "macos"))]
    pub(crate) fn query_coreaudio_latency(&self) -> anyhow::Result<()> {
        let buffer_samples = self.get_actual_buffer_size();
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        let estimated_latency_ms = buffer_samples as f32 / sample_rate * 1000.0;

        *self.hardware_input_latency_ms.lock() = estimated_latency_ms;
        *self.hardware_output_latency_ms.lock() = estimated_latency_ms;

        eprintln!("🎚️ [LATENCY] Estimated latency (non-macOS): {:.2}ms", estimated_latency_ms);
        Ok(())
    }

    /// Restart the audio stream (used when changing buffer size) - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) fn restart_audio_stream(&mut self) -> anyhow::Result<()> {
        // Stop current stream
        if let Some(stream) = self.stream.take() {
            let _ = stream.pause();
            drop(stream);
        }

        // Create new stream with updated settings
        eprintln!("🔊 [AudioGraph] Restarting audio stream...");
        let stream = self.create_audio_stream()?;

        // Always keep stream running for MIDI preview
        stream.play()?;

        self.stream = Some(stream);
        eprintln!("✅ [AudioGraph] Audio stream restarted");

        // Re-query hardware latency after stream change
        if let Err(e) = self.query_coreaudio_latency() {
            eprintln!("⚠️ [AudioGraph] Failed to query hardware latency: {e}");
        }

        Ok(())
    }

    // --- Audio Device Management --- (native only)

    /// Get list of available audio output devices - native only
    /// Returns: Vec of (id, name, `is_default`)
    /// When ASIO feature is enabled, ASIO devices are listed first with [ASIO] prefix
    #[cfg(not(target_arch = "wasm32"))]
    pub fn get_output_devices() -> Vec<(String, String, bool)> {
        let mut all_devices = Vec::new();

        // ASIO devices (when feature enabled, Windows only)
        #[cfg(all(windows, feature = "asio"))]
        {
            eprintln!("🔊 [AudioGraph] Enumerating ASIO devices...");
            if let Ok(asio_host) = cpal::host_from_id(cpal::HostId::Asio) {
                let asio_default = asio_host.default_output_device()
                    .and_then(|d| d.name().ok());

                if let Ok(devices) = asio_host.output_devices() {
                    for device in devices {
                        if let Ok(name) = device.name() {
                            let is_default = asio_default.as_ref() == Some(&name);
                            let prefixed_name = format!("[ASIO] {}", name);
                            eprintln!("  🎛️ ASIO: {} {}", name, if is_default { "(default)" } else { "" });
                            all_devices.push((prefixed_name.clone(), prefixed_name, is_default));
                        }
                    }
                }
                eprintln!("🔊 [AudioGraph] Found {} ASIO devices", all_devices.len());
            } else {
                eprintln!("⚠️ [AudioGraph] ASIO host not available");
            }
        }

        // Standard devices (WASAPI on Windows, CoreAudio on macOS, etc.)
        let host = cpal::default_host();
        eprintln!("🔊 [AudioGraph] Enumerating standard output devices...");

        let default_name = host.default_output_device()
            .and_then(|d| d.name().ok());
        eprintln!("🔊 [AudioGraph] Default output device: {default_name:?}");

        match host.output_devices() {
            Ok(devices) => {
                let standard_devices: Vec<_> = devices.filter_map(|d| {
                    d.name().ok().map(|name| {
                        let is_default = default_name.as_ref() == Some(&name);
                        eprintln!("  📢 Output: {} {}", name, if is_default { "(default)" } else { "" });
                        (name.clone(), name, is_default)
                    })
                }).collect();
                eprintln!("🔊 [AudioGraph] Found {} standard output devices", standard_devices.len());
                all_devices.extend(standard_devices);
            }
            Err(e) => {
                eprintln!("❌ [AudioGraph] Failed to enumerate output devices: {e}");
            }
        }

        eprintln!("🔊 [AudioGraph] Total devices: {}", all_devices.len());
        all_devices
    }

    /// Get list of available audio input devices - native only
    /// Returns: Vec of (id, name, `is_default`)
    #[cfg(not(target_arch = "wasm32"))]
    pub fn get_input_devices() -> Vec<(String, String, bool)> {
        let host = cpal::default_host();
        let default_name = host.default_input_device()
            .and_then(|d| d.name().ok());

        match host.input_devices() {
            Ok(devices) => {
                devices.filter_map(|d| {
                    d.name().ok().map(|name| {
                        let is_default = default_name.as_ref() == Some(&name);
                        (name.clone(), name, is_default)
                    })
                }).collect()
            }
            Err(e) => {
                eprintln!("❌ [AudioGraph] Failed to enumerate input devices: {e}");
                Vec::new()
            }
        }
    }

    /// Set the audio output device by name - native only
    /// Pass empty string or None to use system default
    #[cfg(not(target_arch = "wasm32"))]
    pub fn set_output_device(&mut self, device_name: Option<String>) -> anyhow::Result<()> {
        let device_name = device_name.filter(|s| !s.is_empty());

        eprintln!("🔊 [AudioGraph] Setting output device to: {device_name:?}");

        // Update selected device
        {
            let mut selected = self.selected_output_device.lock();
            (*selected).clone_from(&device_name);
        }

        // Restart stream to apply new device
        self.restart_audio_stream()?;

        if let Some(ref name) = device_name {
            eprintln!("✅ [AudioGraph] Output device changed to: {name}");
        } else {
            eprintln!("✅ [AudioGraph] Output device changed to system default");
        }

        Ok(())
    }

    /// Get the currently selected output device name (None = system default)
    pub fn get_selected_output_device(&self) -> Option<String> {
        self.selected_output_device.lock()
            .clone()
    }
}
