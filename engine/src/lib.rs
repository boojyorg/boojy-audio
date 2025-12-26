// Audio engine modules
mod api;
mod ffi;
mod audio_file;
mod audio_graph;
mod audio_input;
mod recorder;
mod midi;
mod midi_input;
mod midi_recorder;
mod synth;
mod track;      // M4: Track system
mod effects;    // M4: Audio effects
mod project;    // M5: Project serialization
mod export;     // M8: Audio export (WAV, MP3, stems)

// VST3 plugin hosting - desktop only (not available on iOS)
#[cfg(not(target_os = "ios"))]
mod vst3_host;

// Re-export API functions
// Allow ambiguous re-exports - the API module is the canonical source
#[allow(ambiguous_glob_reexports)]
pub use api::*;
pub use audio_file::*;
pub use audio_graph::*;
pub use audio_input::*;
pub use recorder::*;
pub use midi::*;
pub use midi_input::*;
pub use midi_recorder::*;
pub use synth::*;
pub use track::*;
pub use effects::*;
pub use project::*;
pub use export::*;

#[cfg(not(target_os = "ios"))]
pub use vst3_host::*;
// FFI exports are handled by #[no_mangle] in ffi.rs

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Stream;
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};

/// Simple audio engine that outputs silence to default device
pub struct AudioEngine {
    is_running: Arc<AtomicBool>,
    // Store stream to prevent it from being dropped (and to allow proper cleanup)
    stream: Arc<Mutex<Option<Stream>>>,
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = AudioEngine::new();
        assert!(engine.is_ok());
    }
}
