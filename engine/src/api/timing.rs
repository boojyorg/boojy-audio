//! Timing and metronome API functions
//!
//! Functions for tempo control and metronome settings.

use super::helpers::get_audio_graph;

// ============================================================================
// TEMPO CONTROL
// ============================================================================

/// Set tempo in BPM
/// Adjusts playhead position so visual position stays the same (no jump when tempo changes)
pub fn set_tempo(bpm: f64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get current tempo and playhead before changing
    let old_tempo = graph.recorder.get_tempo();
    let current_samples = graph.get_playhead_samples();

    // Calculate ratio adjustment to keep visual position stable
    // visual_pos = samples * tempo_ratio / sample_rate
    // To keep visual_pos same: new_samples = samples * old_ratio / new_ratio
    let old_ratio = old_tempo / 120.0;
    let new_ratio = bpm / 120.0;
    let adjusted_samples = (current_samples as f64 * old_ratio / new_ratio) as u64;

    // Update tempo
    graph.recorder.set_tempo(bpm);

    // Adjust playhead to maintain visual position
    graph.set_playhead_samples(adjusted_samples);

    Ok(format!("Tempo set to {:.1} BPM", bpm))
}

/// Get tempo in BPM
pub fn get_tempo() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.get_tempo())
}

// ============================================================================
// METRONOME CONTROL
// ============================================================================

/// Enable or disable metronome
pub fn set_metronome_enabled(enabled: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    graph.recorder.set_metronome_enabled(enabled);
    Ok(format!("Metronome {}", if enabled { "enabled" } else { "disabled" }))
}

/// Check if metronome is enabled
pub fn is_metronome_enabled() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.is_metronome_enabled())
}
