// Rust linting configuration
#![warn(
    rust_2018_idioms,
    unused_lifetimes,
    unused_qualifications,
    clippy::all,
    clippy::pedantic
)]
#![allow(
    hidden_glob_reexports,
    clippy::module_name_repetitions,
    clippy::must_use_candidate,
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::too_many_lines,
    clippy::similar_names
)]

// ============================================
// Core modules (shared across all platforms)
// ============================================
mod audio_file;
mod audio_graph;
mod midi;
mod synth;
mod sampler;    // Sampler instrument (plays samples via MIDI)
mod track;      // M4: Track system
mod effects;    // M4: Audio effects
mod project;    // M5: Project serialization
mod export;     // M8: Audio export (WAV, MP3, stems)

// ============================================
// Native platform modules (non-WASM)
// ============================================
#[cfg(not(target_arch = "wasm32"))]
mod api;
#[cfg(not(target_arch = "wasm32"))]
mod ffi;
#[cfg(not(target_arch = "wasm32"))]
mod audio_input;
#[cfg(not(target_arch = "wasm32"))]
mod latency_test;
#[cfg(not(target_arch = "wasm32"))]
mod recorder;
#[cfg(not(target_arch = "wasm32"))]
mod midi_input;
#[cfg(not(target_arch = "wasm32"))]
mod midi_recorder;

// VST3 plugin hosting - desktop only (not available on iOS/WASM) and requires vst3 feature
#[cfg(all(feature = "vst3", not(target_os = "ios"), not(target_arch = "wasm32")))]
mod vst3_host;

// ============================================
// Web/WASM platform modules
// ============================================
#[cfg(target_arch = "wasm32")]
mod web_audio;
#[cfg(target_arch = "wasm32")]
mod web_bindings;

// ============================================
// Re-exports: Core (all platforms)
// ============================================
pub use audio_file::*;
pub use audio_graph::*;
pub use midi::*;
pub use synth::*;
pub use sampler::*;
pub use track::*;
pub use effects::*;
pub use project::*;
pub use export::*;

// ============================================
// Re-exports: Native platform only
// ============================================
#[cfg(not(target_arch = "wasm32"))]
#[allow(ambiguous_glob_reexports)]
pub use api::*;
#[cfg(not(target_arch = "wasm32"))]
pub use audio_input::*;
#[cfg(not(target_arch = "wasm32"))]
pub use recorder::*;
#[cfg(not(target_arch = "wasm32"))]
pub use midi_input::*;
#[cfg(not(target_arch = "wasm32"))]
pub use midi_recorder::*;
#[cfg(not(target_arch = "wasm32"))]
pub use latency_test::*;

#[cfg(all(feature = "vst3", not(target_os = "ios"), not(target_arch = "wasm32")))]
pub use vst3_host::*;

// ============================================
// Re-exports: Web/WASM platform only
// ============================================
#[cfg(target_arch = "wasm32")]
pub use web_audio::*;
#[cfg(target_arch = "wasm32")]
pub use web_bindings::*;

// ============================================
// Native AudioEngine (cpal-based)
// ============================================
#[cfg(not(target_arch = "wasm32"))]
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
#[cfg(not(target_arch = "wasm32"))]
use cpal::Stream;
// ============================================
// Native AudioEngine implementation (cpal-based)
// ============================================
#[cfg(not(target_arch = "wasm32"))]
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};

/// Simple audio engine that outputs silence to default device (native platforms)
#[cfg(not(target_arch = "wasm32"))]
pub struct AudioEngine {
    is_running: Arc<AtomicBool>,
    // Store stream to prevent it from being dropped (and to allow proper cleanup)
    stream: Arc<Mutex<Option<Stream>>>,
}

#[cfg(not(target_arch = "wasm32"))]
impl AudioEngine {
    pub fn new() -> Result<Self, anyhow::Error> {
        Ok(Self {
            is_running: Arc::new(AtomicBool::new(false)),
            stream: Arc::new(Mutex::new(None)),
        })
    }

    /// Start audio output (currently just silence)
    pub fn start(&self) -> Result<(), anyhow::Error> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow::anyhow!("No output device available"))?;

        let config = device.default_output_config()?;

        println!("Audio device: {}", device.name()?);
        println!("Audio config: {:?}", config);

        // Create stream that outputs silence
        let stream = device.build_output_stream(
            &config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                // Output silence (zeros)
                for sample in data.iter_mut() {
                    *sample = 0.0;
                }
            },
            move |err| {
                eprintln!("Audio stream error: {}", err);
            },
            None,
        )?;

        stream.play()?;
        self.is_running.store(true, Ordering::SeqCst);

        // Store stream to keep it alive (and allow cleanup on drop)
        if let Ok(mut stream_guard) = self.stream.lock() {
            *stream_guard = Some(stream);
        }

        Ok(())
    }

    /// Stop audio output
    pub fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
        // Drop the stream to release audio resources
        if let Ok(mut stream_guard) = self.stream.lock() {
            *stream_guard = None;
        }
    }

    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = AudioEngine::new();
        assert!(engine.is_ok());
    }
}
