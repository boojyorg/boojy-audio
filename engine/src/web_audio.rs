//! Web Audio API backend for WASM target
//!
//! This module provides audio output capabilities using the Web Audio API
//! when running in a browser environment via WebAssembly.

use wasm_bindgen::prelude::*;
use web_sys::{AudioContext, AudioContextOptions, AudioContextState, GainNode, AudioParam};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// Web Audio backend for browser-based audio output
pub struct WebAudioBackend {
    context: Option<AudioContext>,
    gain_node: Option<GainNode>,
    is_running: Arc<AtomicBool>,
    sample_rate: f32,
}

impl WebAudioBackend {
    /// Create a new Web Audio backend
    pub fn new() -> Result<Self, JsValue> {
        Ok(Self {
            context: None,
            gain_node: None,
            is_running: Arc::new(AtomicBool::new(false)),
            sample_rate: 48000.0,
        })
    }

    /// Initialize the Web Audio context
    /// Note: This must be called from a user gesture (click, keypress) due to browser autoplay policies
    pub fn init(&mut self) -> Result<(), JsValue> {
        // Create AudioContext with desired sample rate
        let mut options = AudioContextOptions::new();
        options.sample_rate(self.sample_rate);

        let context = AudioContext::new_with_context_options(&options)?;
        self.sample_rate = context.sample_rate();

        // Create master gain node
        let gain_node = context.create_gain()?;
        gain_node.gain().set_value(1.0);
        gain_node.connect_with_audio_node(&context.destination())?;

        self.context = Some(context);
        self.gain_node = Some(gain_node);

        web_sys::console::log_1(&format!(
            "Web Audio initialized: sample_rate={}",
            self.sample_rate
        ).into());

        Ok(())
    }

    /// Resume the audio context (required after user gesture)
    pub async fn resume(&self) -> Result<(), JsValue> {
        if let Some(ref context) = self.context {
            if context.state() == AudioContextState::Suspended {
                wasm_bindgen_futures::JsFuture::from(context.resume()?).await?;
            }
        }
        Ok(())
    }

    /// Start audio playback
    pub fn start(&self) -> Result<(), JsValue> {
        self.is_running.store(true, Ordering::SeqCst);
        web_sys::console::log_1(&"Web Audio started".into());
        Ok(())
    }

    /// Stop audio playback
    pub fn stop(&self) -> Result<(), JsValue> {
        self.is_running.store(false, Ordering::SeqCst);
        web_sys::console::log_1(&"Web Audio stopped".into());
        Ok(())
    }

    /// Check if audio is currently running
    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }

    /// Get the current sample rate
    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }

    /// Get the audio context (for advanced operations)
    pub fn context(&self) -> Option<&AudioContext> {
        self.context.as_ref()
    }

    /// Get the master gain node
    pub fn gain_node(&self) -> Option<&GainNode> {
        self.gain_node.as_ref()
    }

    /// Set master volume (0.0 to 1.0)
    pub fn set_volume(&self, volume: f32) -> Result<(), JsValue> {
        if let Some(ref gain) = self.gain_node {
            gain.gain().set_value(volume.clamp(0.0, 1.0));
        }
        Ok(())
    }

    /// Get current time from audio context (in seconds)
    pub fn current_time(&self) -> f64 {
        self.context
            .as_ref()
            .map(|ctx| ctx.current_time())
            .unwrap_or(0.0)
    }
}

impl Default for WebAudioBackend {
    fn default() -> Self {
        Self::new().expect("Failed to create WebAudioBackend")
    }
}

/// Log a message to the browser console
pub fn console_log(msg: &str) {
    web_sys::console::log_1(&msg.into());
}

/// Log an error to the browser console
pub fn console_error(msg: &str) {
    web_sys::console::error_1(&msg.into());
}
