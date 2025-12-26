//! Export progress tracking module
//!
//! Provides a polling-based progress system for long-running export operations.
//! Flutter can poll the progress state periodically to update the UI.

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::RwLock;

/// Global export progress state
static EXPORT_PROGRESS: ExportProgressState = ExportProgressState::new();

/// Export progress state that can be polled from Flutter
pub struct ExportProgressState {
    /// Progress value (0-100)
    progress: AtomicU32,
    /// Whether export is currently running
    is_running: AtomicBool,
    /// Whether export was cancelled
    is_cancelled: AtomicBool,
    /// Current status message
    status: RwLock<String>,
    /// Error message if export failed
    error: RwLock<Option<String>>,
}

impl ExportProgressState {
    const fn new() -> Self {
        Self {
            progress: AtomicU32::new(0),
            is_running: AtomicBool::new(false),
            is_cancelled: AtomicBool::new(false),
            status: RwLock::new(String::new()),
            error: RwLock::new(None),
        }
    }

    /// Start a new export operation
    pub fn start(&self, status: &str) {
        self.progress.store(0, Ordering::SeqCst);
        self.is_running.store(true, Ordering::SeqCst);
        self.is_cancelled.store(false, Ordering::SeqCst);
        if let Ok(mut s) = self.status.write() {
            *s = status.to_string();
        }
        if let Ok(mut e) = self.error.write() {
            *e = None;
        }
    }

    /// Update progress (0-100) and status message
    pub fn update(&self, progress: u32, status: &str) {
        self.progress.store(progress.min(100), Ordering::SeqCst);
        if let Ok(mut s) = self.status.write() {
            *s = status.to_string();
        }
    }

    /// Mark export as complete
    pub fn complete(&self) {
        self.progress.store(100, Ordering::SeqCst);
        self.is_running.store(false, Ordering::SeqCst);
        if let Ok(mut s) = self.status.write() {
            *s = "Export complete".to_string();
        }
    }

    /// Mark export as failed with error message
    pub fn fail(&self, error: &str) {
        self.is_running.store(false, Ordering::SeqCst);
        if let Ok(mut s) = self.status.write() {
            *s = "Export failed".to_string();
        }
        if let Ok(mut e) = self.error.write() {
            *e = Some(error.to_string());
        }
    }

    /// Request cancellation of current export
    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::SeqCst);
    }

    /// Check if cancellation was requested
    pub fn is_cancelled(&self) -> bool {
        self.is_cancelled.load(Ordering::SeqCst)
    }

    /// Check if export is running
    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }

    /// Get current progress (0-100)
    pub fn get_progress(&self) -> u32 {
        self.progress.load(Ordering::SeqCst)
    }

    /// Get current status message
    pub fn get_status(&self) -> String {
        self.status.read().map(|s| s.clone()).unwrap_or_default()
    }

    /// Get error message if any
    pub fn get_error(&self) -> Option<String> {
        self.error.read().ok().and_then(|e| e.clone())
    }

    /// Reset all state
    pub fn reset(&self) {
        self.progress.store(0, Ordering::SeqCst);
        self.is_running.store(false, Ordering::SeqCst);
        self.is_cancelled.store(false, Ordering::SeqCst);
        if let Ok(mut s) = self.status.write() {
            s.clear();
        }
        if let Ok(mut e) = self.error.write() {
            *e = None;
        }
    }
}

/// Get the global export progress state
pub fn export_progress() -> &'static ExportProgressState {
    &EXPORT_PROGRESS
}

/// Progress info returned to Flutter
#[derive(Debug, Clone)]
pub struct ExportProgressInfo {
    pub progress: u32,
    pub is_running: bool,
    pub is_cancelled: bool,
    pub status: String,
    pub error: Option<String>,
}

impl ExportProgressInfo {
    /// Get current progress info
    pub fn current() -> Self {
        let state = export_progress();
        Self {
            progress: state.get_progress(),
            is_running: state.is_running(),
            is_cancelled: state.is_cancelled(),
            status: state.get_status(),
            error: state.get_error(),
        }
    }

    /// Convert to JSON string
    pub fn to_json(&self) -> String {
        serde_json::json!({
            "progress": self.progress,
            "is_running": self.is_running,
            "is_cancelled": self.is_cancelled,
            "status": self.status,
            "error": self.error,
        })
        .to_string()
    }
}

/// Helper macro to check for cancellation and return early if cancelled
#[macro_export]
macro_rules! check_cancelled {
    () => {
        if $crate::export::export_progress().is_cancelled() {
            $crate::export::export_progress().fail("Export cancelled by user");
            return Err("Export cancelled".to_string());
        }
    };
}
