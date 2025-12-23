//! Initialization API functions
//!
//! Functions for initializing the audio engine and graph.

use crate::audio_graph::AudioGraph;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::collections::HashMap;
use std::f32::consts::PI;
use std::sync::{Arc, Mutex};

use super::helpers::{AUDIO_CLIPS, AUDIO_GRAPH};

// ============================================================================
// SINE WAVE TEST (Legacy M0)
// ============================================================================

/// Play a sine wave at the specified frequency for the given duration
///
/// # Arguments
/// * `frequency` - Frequency in Hz (e.g., 440 for A4)
/// * `duration_ms` - Duration in milliseconds
pub fn play_sine_wave(frequency: f32, duration_ms: u32) -> Result<String, String> {
    std::thread::spawn(move || {
        if let Err(e) = play_sine_wave_internal(frequency, duration_ms) {
            eprintln!("Error playing sine wave: {}", e);
        }
    });

    Ok(format!(
        "Playing {} Hz sine wave for {} ms",
        frequency, duration_ms
    ))
}

fn play_sine_wave_internal(frequency: f32, duration_ms: u32) -> Result<(), String> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or("No output device available")?;

    let config = device
        .default_output_config()
        .map_err(|e| format!("Failed to get output config: {}", e))?;

    let sample_rate = config.sample_rate().0 as f32;
    let channels = config.channels() as usize;

    let samples_to_play = (sample_rate * duration_ms as f32 / 1000.0) as usize;
    let sample_count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let sample_count_clone = sample_count.clone();

    let stream = device
        .build_output_stream(
            &config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                let count = sample_count_clone.load(std::sync::atomic::Ordering::SeqCst);
                let num_frames = data.len() / channels;

                for i in 0..num_frames {
                    let current_sample = count + i;

                    let value = if current_sample >= samples_to_play {
                        0.0
                    } else {
                        let t = current_sample as f32 / sample_rate;
                        (t * frequency * 2.0 * PI).sin() * 0.3
                    };

                    for ch in 0..channels {
                        data[i * channels + ch] = value;
                    }
                }

                sample_count_clone.fetch_add(num_frames, std::sync::atomic::Ordering::SeqCst);
            },
            |err| {
                eprintln!("Audio stream error: {}", err);
            },
            None,
        )
        .map_err(|e| format!("Failed to build output stream: {}", e))?;

    stream
        .play()
        .map_err(|e| format!("Failed to play stream: {}", e))?;

    std::thread::sleep(std::time::Duration::from_millis(duration_ms as u64));

    Ok(())
}

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

    Ok(format!("Audio engine initialized. Device: {}", device_name))
}

/// Initialize the audio graph for playback
pub fn init_audio_graph() -> Result<String, String> {
    // Initialize VST3 host first (required before loading any VST3 plugins)
    #[cfg(not(target_os = "ios"))]
    {
        use crate::vst3_host::VST3Host;
        VST3Host::init().map_err(|e| format!("VST3 host init failed: {}", e))?;
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
