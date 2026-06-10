//! Timing and metronome API functions
//!
//! Functions for tempo control and metronome settings.

use super::helpers::get_audio_graph;

// ============================================================================
// TEMPO CONTROL
// ============================================================================

/// Set tempo in BPM
/// Rescales the playhead so it stays on the same BEAT (the UI rescales all
/// clip positions the same way, so nothing visually jumps).
pub fn set_tempo(bpm: f64) -> Result<String, String> {
    // Match the recorder's stored clamp BEFORE the playhead math below —
    // rescaling by an out-of-range bpm while the recorder stores the clamped
    // value would silently shift the playhead off its beat.
    let bpm = bpm.clamp(20.0, 300.0);

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    // Get current tempo and playhead before changing
    let old_tempo = graph.recorder.get_tempo();
    let current_samples = graph.get_playhead_samples();

    // A position at beat B sits at B * 60/tempo seconds, so keeping the beat
    // means scaling the sample position by old_tempo / new_tempo.
    let adjusted_samples = (current_samples as f64 * old_tempo / bpm) as u64;

    // Update tempo
    graph.recorder.set_tempo(bpm);

    // Move playhead to the same beat under the new tempo
    graph.set_playhead_samples(adjusted_samples);

    // Keep the metronome's beat counter on that beat too — it shares the
    // playhead's sample clock, and its beat length just changed. Without
    // this, clicks drift out of phase after a live tempo change until the
    // transport stops (the counter held a position measured in OLD-tempo
    // beats).
    graph.recorder.seek_metronome(adjusted_samples);

    Ok(format!("Tempo set to {bpm:.1} BPM"))
}

/// Get tempo in BPM
pub fn get_tempo() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.recorder.get_tempo())
}

// ============================================================================
// METRONOME CONTROL
// ============================================================================

/// Enable or disable metronome
pub fn set_metronome_enabled(enabled: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    graph.recorder.set_metronome_enabled(enabled);
    Ok(format!(
        "Metronome {}",
        if enabled { "enabled" } else { "disabled" }
    ))
}

/// Check if metronome is enabled
pub fn is_metronome_enabled() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.recorder.is_metronome_enabled())
}

// ============================================================================
// TIME SIGNATURE CONTROL
// ============================================================================

/// Set time signature (beats per bar)
pub fn set_time_signature(beats_per_bar: u32) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    graph.recorder.set_time_signature(beats_per_bar);
    Ok(format!("Time signature set to {beats_per_bar}/4"))
}

/// Get time signature (beats per bar)
pub fn get_time_signature() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.recorder.get_time_signature())
}
