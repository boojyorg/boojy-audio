//! Transport control API functions
//!
//! Functions for playback control: play, pause, stop, seek, and state queries.

use crate::audio_graph::TransportState;
use super::helpers::{get_audio_graph, with_graph, AUDIO_GRAPH};

// ============================================================================
// TRANSPORT CONTROL
// ============================================================================

/// Start playback (non-blocking: uses try_lock to avoid UI freeze)
pub fn transport_play() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;

    match graph_mutex.try_lock() {
        Ok(mut graph) => {
            graph.play().map_err(|e| e.to_string())?;
            Ok("Playing".to_string())
        }
        Err(_) => {
            eprintln!("⚠️ [API] transport_play: lock busy, spawning thread");
            std::thread::spawn(|| {
                if let Some(m) = AUDIO_GRAPH.get() {
                    if let Ok(mut g) = m.lock() {
                        let _ = g.play();
                        eprintln!("✅ [API] transport_play: completed in background thread");
                    }
                }
            });
            Ok("Play queued".to_string())
        }
    }
}

/// Pause playback (non-blocking: uses try_lock to avoid UI freeze)
pub fn transport_pause() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;

    match graph_mutex.try_lock() {
        Ok(mut graph) => {
            graph.pause().map_err(|e| e.to_string())?;
            Ok("Paused".to_string())
        }
        Err(_) => {
            eprintln!("⚠️ [API] transport_pause: lock busy, spawning thread");
            std::thread::spawn(|| {
                if let Some(m) = AUDIO_GRAPH.get() {
                    if let Ok(mut g) = m.lock() {
                        let _ = g.pause();
                    }
                }
            });
            Ok("Pause queued".to_string())
        }
    }
}

/// Stop playback and reset to start (non-blocking: uses try_lock to avoid UI freeze)
pub fn transport_stop() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;

    match graph_mutex.try_lock() {
        Ok(mut graph) => {
            graph.stop().map_err(|e| e.to_string())?;
            Ok("Stopped".to_string())
        }
        Err(_) => {
            eprintln!("⚠️ [API] transport_stop: lock busy, spawning thread");
            std::thread::spawn(|| {
                if let Some(m) = AUDIO_GRAPH.get() {
                    if let Ok(mut g) = m.lock() {
                        let _ = g.stop();
                    }
                }
            });
            Ok("Stop queued".to_string())
        }
    }
}

/// Seek to a position in seconds
pub fn transport_seek(position_seconds: f64) -> Result<String, String> {
    with_graph(|graph| {
        graph.seek(position_seconds);
        Ok(format!("Seeked to {:.2}s", position_seconds))
    })
}

/// Get current playhead position in seconds
pub fn get_playhead_position() -> Result<f64, String> {
    with_graph(|graph| Ok(graph.get_playhead_position()))
}

/// Get transport state (0=Stopped, 1=Playing, 2=Paused)
pub fn get_transport_state() -> Result<i32, String> {
    with_graph(|graph| {
        let state = match graph.get_state() {
            TransportState::Stopped => 0,
            TransportState::Playing => 1,
            TransportState::Paused => 2,
        };
        Ok(state)
    })
}
