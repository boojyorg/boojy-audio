//! Shared helpers for API modules
//!
//! This module contains the global state and helper functions used across all API modules.

use crate::audio_file::AudioClip;
use crate::audio_graph::AudioGraph;
use crate::track::ClipId;
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

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
    AUDIO_GRAPH
        .get()
        .ok_or_else(|| "Audio graph not initialized".to_string())
}

/// Get a reference to the audio clips mutex, returning an error if not initialized
#[inline]
pub fn get_audio_clips() -> Result<&'static Mutex<HashMap<ClipId, Arc<AudioClip>>>, String> {
    AUDIO_CLIPS
        .get()
        .ok_or_else(|| "Audio graph not initialized".to_string())
}

/// Execute a closure with a locked audio graph (immutable access)
pub fn with_graph<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&AudioGraph) -> Result<R, String>,
{
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    f(&graph)
}

/// Execute a closure with a locked audio graph (mutable access)
pub fn with_graph_mut<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&mut AudioGraph) -> Result<R, String>,
{
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock();
    f(&mut graph)
}

/// Try to execute a closure with a locked audio graph, spawning a background thread if busy
/// Returns Ok with result if lock acquired immediately, or spawns thread and returns queued message
pub fn try_with_graph_mut<F>(action_name: &str, queued_msg: &str, f: F) -> Result<String, String>
where
    F: FnOnce(&mut AudioGraph) -> Result<String, String> + Send + 'static,
{
    let graph_mutex = get_audio_graph()?;

    if let Some(mut graph) = graph_mutex.try_lock() {
        f(&mut graph)
    } else {
        // Lock is busy - spawn thread to retry (UI won't freeze)
        let action = action_name.to_string();
        eprintln!("⚠️ [API] {action}: lock busy, spawning thread");
        std::thread::spawn(move || {
            if let Some(m) = AUDIO_GRAPH.get() {
                let mut g = m.lock();
                // Surface a background failure instead of dropping it on the
                // floor — the caller already received `queued_msg` and can't see
                // this Result, so logging is the only signal the deferred action
                // failed. (C46)
                match f(&mut g) {
                    Ok(_) => eprintln!("✅ [API] {action}: completed in background thread"),
                    Err(e) => eprintln!("❌ [API] {action}: failed in background thread: {e}"),
                }
            }
        });
        Ok(queued_msg.to_string())
    }
}

/// Percent-encode a free-text field (e.g. a track name) for the engine's
/// `,`/`;`-delimited CSV result strings (C34). Encodes `%`, `,` and `;` so a
/// name like "Drums, Kit" can't shift later fields or split entries. The Dart
/// side decodes with `decodeCsvField` (ui/lib/utils/csv_field.dart) — keep the
/// two in sync.
pub fn encode_csv_field(s: &str) -> String {
    // '%' first, so the escapes we insert aren't re-encoded.
    s.replace('%', "%25")
        .replace(',', "%2C")
        .replace(';', "%3B")
}

#[cfg(test)]
mod tests {
    use super::encode_csv_field;

    #[test]
    fn encode_csv_field_passes_plain_names_through() {
        assert_eq!(encode_csv_field("Drums"), "Drums");
        assert_eq!(encode_csv_field("Vocal Take 3"), "Vocal Take 3");
    }

    #[test]
    fn encode_csv_field_escapes_delimiters_and_percent() {
        assert_eq!(encode_csv_field("Drums, Kit"), "Drums%2C Kit");
        assert_eq!(encode_csv_field("a;b"), "a%3Bb");
        assert_eq!(encode_csv_field("100%"), "100%25");
        // A name that already looks like an escape round-trips unambiguously.
        assert_eq!(encode_csv_field("%2C"), "%252C");
    }
}
