//! Initialization API functions
//!
//! Functions for initializing the audio engine and graph.

use crate::audio_graph::AudioGraph;
use cpal::traits::{DeviceTrait, HostTrait};
use parking_lot::Mutex;
use std::collections::HashMap;

use super::helpers::{AUDIO_CLIPS, AUDIO_GRAPH};

// ============================================================================
// ENGINE INITIALIZATION
// ============================================================================

/// Initialize the audio engine (verify devices are available)
pub fn init_audio_engine() -> Result<String, String> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or("No output device available")?;

    let device_name = device
        .name()
        .unwrap_or_else(|_| "Unknown Device".to_string());

    Ok(format!("Audio engine initialized. Device: {device_name}"))
}

/// Initialize the audio graph for playback
pub fn init_audio_graph() -> Result<String, String> {
    // Already running (a hot restart of the app, or a second test in the same
    // process): reuse it. Starting over would open a second output stream
    // only to drop it, and the app treated the error as a failed start.
    if AUDIO_GRAPH.get().is_some() {
        return Ok("Audio graph already initialized".to_string());
    }

    // Initialize VST3 host first (required before loading any VST3 plugins)
    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
    {
        use crate::vst3_host::VST3Host;
        VST3Host::init().map_err(|e| format!("VST3 host init failed: {e}"))?;
    }

    let graph = AudioGraph::new().map_err(|e| e.to_string())?;
    AUDIO_GRAPH
        .set(Mutex::new(graph))
        .map_err(|_| "Audio graph already initialized")?;

    AUDIO_CLIPS
        .set(Mutex::new(HashMap::new()))
        .map_err(|_| "Audio clips already initialized")?;

    Ok("Audio graph initialized".to_string())
}
