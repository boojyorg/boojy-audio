//! Latency and buffer control API functions
//!
//! Functions for audio latency configuration and waveform visualization.

use super::helpers::{get_audio_clips, with_graph_mut};
use crate::audio_graph::BufferSizePreset;

// ============================================================================
// BUFFER SIZE CONTROL
// ============================================================================

/// Set buffer size preset
/// 0=Lowest (64), 1=Low (128), 2=Balanced (256), 3=Safe (512), 4=HighStability (1024)
pub fn set_buffer_size(preset: i32) -> Result<String, String> {
    let buffer_preset = match preset {
        0 => BufferSizePreset::Lowest,
        1 => BufferSizePreset::Low,
        2 => BufferSizePreset::Balanced,
        3 => BufferSizePreset::Safe,
        4 => BufferSizePreset::HighStability,
        _ => return Err(format!("Invalid buffer size preset: {preset}")),
    };

    with_graph_mut(|graph| {
        graph
            .set_buffer_size(buffer_preset)
            .map_err(|e| e.to_string())?;

        Ok(format!(
            "Buffer size set to {:?} ({} samples, {:.1}ms)",
            buffer_preset,
            buffer_preset.samples(),
            buffer_preset.latency_ms()
        ))
    })
}

// ============================================================================
// WAVEFORM VISUALIZATION
// ============================================================================

/// Get waveform peaks for visualization
/// Returns downsampled peaks (min/max pairs) for rendering
pub fn get_waveform_peaks(clip_id: u64, resolution: usize) -> Result<Vec<f32>, String> {
    let clips_mutex = get_audio_clips()?;
    let clips_map = clips_mutex.lock();

    let clip = clips_map
        .get(&clip_id)
        .ok_or_else(|| format!("Clip {clip_id} not found"))?;

    // Downsample to resolution peaks
    let frames = clip.frame_count();
    let samples_per_peak = (frames / resolution).max(1);

    let mut peaks = Vec::with_capacity(resolution * 2); // min/max pairs

    for i in 0..resolution {
        let start = i * samples_per_peak;
        let end = ((i + 1) * samples_per_peak).min(frames);

        if start >= frames {
            break;
        }

        let mut min: f32 = 1.0;
        let mut max: f32 = -1.0;

        // Find min/max in this window (use left channel for mono visualization)
        for frame in start..end {
            if let Some(sample) = clip.get_sample(frame, 0) {
                min = min.min(sample);
                max = max.max(sample);
            }
        }

        peaks.push(min);
        peaks.push(max);
    }

    Ok(peaks)
}

/// Get clip duration in seconds
pub fn get_clip_duration(clip_id: u64) -> Result<f64, String> {
    let clips_mutex = get_audio_clips()?;
    let clips_map = clips_mutex.lock();

    let clip = clips_map
        .get(&clip_id)
        .ok_or_else(|| format!("Clip {clip_id} not found"))?;

    Ok(clip.duration_seconds)
}
