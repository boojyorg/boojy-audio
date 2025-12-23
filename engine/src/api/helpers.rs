//! Shared helpers for API modules
//!
//! This module contains the global state and helper functions used across all API modules.

use crate::audio_file::AudioClip;
use crate::audio_graph::AudioGraph;
use crate::track::ClipId;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

// ============================================================================
// GLOBAL STATE
// ============================================================================

/// Global audio graph instance (thread-safe, lazy-initialized)
pub static AUDIO_GRAPH: OnceLock<Mutex<AudioGraph>> = OnceLock::new();

/// Map of loaded audio clips (thread-safe, lazy-initialized)
pub static AUDIO_CLIPS: OnceLock<Mutex<HashMap<ClipId, Arc<AudioClip>>>> = OnceLock::new();

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Get a reference to the audio graph mutex, returning an error if not initialized
#[inline]
pub fn get_audio_graph() -> Result<&'static Mutex<AudioGraph>, String> {
    AUDIO_GRAPH.get().ok_or_else(|| "Audio graph not initialized".to_string())
}

/// Get a reference to the audio clips mutex, returning an error if not initialized
#[inline]
pub fn get_audio_clips() -> Result<&'static Mutex<HashMap<ClipId, Arc<AudioClip>>>, String> {
    AUDIO_CLIPS.get().ok_or_else(|| "Audio graph not initialized".to_string())
}

/// Execute a closure with a locked audio graph (immutable access)
pub fn with_graph<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&AudioGraph) -> Result<R, String>,
{
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    f(&graph)
}

/// Execute a closure with a locked audio graph (mutable access)
pub fn with_graph_mut<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&mut AudioGraph) -> Result<R, String>,
{
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    f(&mut graph)
}

/// Try to execute a closure with a locked audio graph, spawning a background thread if busy
/// Returns Ok with result if lock acquired immediately, or spawns thread and returns queued message
pub fn try_with_graph_mut<F>(action_name: &str, queued_msg: &str, f: F) -> Result<String, String>
where
    F: FnOnce(&mut AudioGraph) -> Result<String, String> + Send + 'static,
{
    let graph_mutex = get_audio_graph()?;

    match graph_mutex.try_lock() {
        Ok(mut graph) => f(&mut graph),
        Err(_) => {
            // Lock is busy - spawn thread to retry (UI won't freeze)
            let action = action_name.to_string();
            eprintln!("⚠️ [API] {}: lock busy, spawning thread", action);
            std::thread::spawn(move || {
                if let Some(m) = AUDIO_GRAPH.get() {
                    if let Ok(mut g) = m.lock() {
                        let _ = f(&mut g);
                        eprintln!("✅ [API] {}: completed in background thread", action);
                    }
                }
            });
            Ok(queued_msg.to_string())
        }
    }
}
