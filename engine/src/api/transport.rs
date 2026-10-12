//! Transport control API functions
//!
//! Functions for playback control: play, pause, stop, seek, and state queries.

use super::helpers::{with_graph, with_graph_mut};

// ============================================================================
// TRANSPORT CONTROL
// ============================================================================

// Transport state changes block on the graph lock (like the rest of the API)
// rather than the old try_lock + detached-thread fallback. That fallback had no
// ordering guarantee: a pause whose lock was busy got queued onto a background
// thread and could land *after* a later play, leaving the engine paused while
// the UI believed it was playing — the intermittent "stuck on pause" bug. The
// audio render thread holds only cloned atomic handles (see renderer.rs), never
// this mutex, so blocking here waits at most on another short API call, never on
// audio. Sequential UI clicks therefore apply to the engine in the order issued.

/// Start playback
pub fn transport_play() -> Result<String, String> {
    with_graph_mut(|graph| {
        graph.play().map_err(|e| e.to_string())?;
        Ok("Playing".to_string())
    })
}

/// Pause playback (keeps position)
pub fn transport_pause() -> Result<String, String> {
    with_graph_mut(|graph| {
        graph.pause().map_err(|e| e.to_string())?;
        Ok("Paused".to_string())
    })
}

/// Stop playback and reset to start
pub fn transport_stop() -> Result<String, String> {
    with_graph_mut(|graph| {
        graph.stop().map_err(|e| e.to_string())?;
        Ok("Stopped".to_string())
    })
}

/// Seek to a position in seconds
pub fn transport_seek(position_seconds: f64) -> Result<String, String> {
    with_graph(|graph| {
        graph.seek(position_seconds);
        Ok(format!("Seeked to {position_seconds:.2}s"))
    })
}

/// Get current playhead position in seconds
pub fn get_playhead_position() -> Result<f64, String> {
    with_graph(|graph| Ok(graph.get_playhead_position()))
}
