/// Preview player - dedicated audio preview for library panel
/// Plays audio files independently of the main timeline transport
///
/// Features:
/// - Load and play audio files for preview
/// - Looping for short files (< 3 seconds)
/// - Fade in/out to prevent clicks
/// - Waveform peak extraction for UI

use crate::audio_file::{load_audio_file, AudioClip, TARGET_SAMPLE_RATE};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

const FADE_SAMPLES: usize = 882; // ~20ms at 44.1kHz, ~18ms at 48kHz

/// Preview player state
pub struct PreviewPlayer {
    /// Loaded audio clip
    clip: Option<Arc<AudioClip>>,
    /// Current playback position in samples (for lock-free reads)
    position_samples: Arc<AtomicU64>,
    /// Whether currently playing (atomic for lock-free callback access)
    is_playing: Arc<AtomicBool>,
    /// Whether to loop playback
    is_looping: Arc<AtomicBool>,
    /// Fade state: positive = fade in remaining, negative = fade out remaining
    fade_samples_remaining: i32,
    /// Total samples in loaded clip
    total_samples: u64,
    /// Cached waveform peaks for UI display
    waveform_peaks: Vec<f32>,
    /// File path of loaded clip (for UI display)
    loaded_path: Option<String>,
}

impl PreviewPlayer {
    /// Create a new preview player
    pub fn new() -> Self {
        Self {
            clip: None,
            position_samples: Arc::new(AtomicU64::new(0)),
            is_playing: Arc::new(AtomicBool::new(false)),
            is_looping: Arc::new(AtomicBool::new(false)),
            fade_samples_remaining: 0,
            total_samples: 0,
            waveform_peaks: Vec::new(),
            loaded_path: None,
        }
    }

    /// Load an audio file for preview
    pub fn load_file(&mut self, path: &str) -> Result<(), String> {
        // Stop any current playback
        self.stop();

        // Load the audio file
        let clip = load_audio_file(path).map_err(|e| e.to_string())?;
        let total_samples = (clip.duration_seconds * TARGET_SAMPLE_RATE as f64) as u64;

        // Auto-enable looping for short files (< 3 seconds)
        let should_loop = clip.duration_seconds < 3.0;
        self.is_looping.store(should_loop, Ordering::SeqCst);

        // Extract waveform peaks (200 peaks for preview display)
        self.waveform_peaks = extract_waveform_peaks(&clip, 200);

        self.clip = Some(Arc::new(clip));
        self.total_samples = total_samples;
        self.position_samples.store(0, Ordering::SeqCst);
        self.loaded_path = Some(path.to_string());

        Ok(())
    }

    /// Start or resume playback
    pub fn play(&mut self) {
        if self.clip.is_some() {
            // Start fade in
            self.fade_samples_remaining = FADE_SAMPLES as i32;
            self.is_playing.store(true, Ordering::SeqCst);
        }
    }

    /// Stop playback with fade out
    pub fn stop(&mut self) {
        if self.is_playing.load(Ordering::SeqCst) {
            // Start fade out (negative = fade out)
            self.fade_samples_remaining = -(FADE_SAMPLES as i32);
        }
    }

    /// Seek to a position in seconds
    pub fn seek(&mut self, position_seconds: f64) {
        let sample_pos = (position_seconds * TARGET_SAMPLE_RATE as f64) as u64;
        let clamped = sample_pos.min(self.total_samples);
        self.position_samples.store(clamped, Ordering::SeqCst);
    }

    /// Get current playback position in seconds
    pub fn get_position(&self) -> f64 {
        let samples = self.position_samples.load(Ordering::SeqCst);
        samples as f64 / TARGET_SAMPLE_RATE as f64
    }

    /// Get total duration in seconds
    pub fn get_duration(&self) -> f64 {
        self.clip
            .as_ref()
            .map(|c| c.duration_seconds)
            .unwrap_or(0.0)
    }

    /// Check if currently playing
    pub fn is_playing(&self) -> bool {
        self.is_playing.load(Ordering::SeqCst)
    }

    /// Set looping mode
    pub fn set_looping(&mut self, should_loop: bool) {
        self.is_looping.store(should_loop, Ordering::SeqCst);
    }

    /// Get looping mode
    pub fn is_looping(&self) -> bool {
        self.is_looping.load(Ordering::SeqCst)
    }

    /// Get waveform peaks for UI display
    pub fn get_waveform_peaks(&self, resolution: usize) -> Vec<f32> {
        if self.waveform_peaks.is_empty() {
            return vec![0.0; resolution];
        }

        // Resample cached peaks to requested resolution
        resample_peaks(&self.waveform_peaks, resolution)
    }

    /// Get the loaded file path
    #[allow(dead_code)]
    pub fn get_loaded_path(&self) -> Option<&str> {
        self.loaded_path.as_deref()
    }

    /// Process a single stereo sample frame
    /// Called from audio callback - must be lock-free and fast
    pub fn process_sample(&mut self) -> (f32, f32) {
        // Fast path: not playing
        if !self.is_playing.load(Ordering::SeqCst) {
            return (0.0, 0.0);
        }

        let clip = match &self.clip {
            Some(c) => c,
            None => return (0.0, 0.0),
        };

        let position = self.position_samples.load(Ordering::SeqCst);
        let frame_count = clip.frame_count();

        // Handle end of file
        if position as usize >= frame_count {
            if self.is_looping.load(Ordering::SeqCst) {
                // Loop back to start
                self.position_samples.store(0, Ordering::SeqCst);
            } else {
                // Stop playback
                self.is_playing.store(false, Ordering::SeqCst);
                return (0.0, 0.0);
            }
        }

        // Get sample at current position
        let frame_idx = position as usize;
        let left = clip.get_sample(frame_idx, 0).unwrap_or(0.0);
        let right = if clip.channels > 1 {
            clip.get_sample(frame_idx, 1).unwrap_or(left)
        } else {
            left // Mono: duplicate to both channels
        };

        // Calculate fade envelope
        let fade_gain = self.calculate_fade_gain();

        // Advance position
        self.position_samples.fetch_add(1, Ordering::SeqCst);

        // Check if fade out completed
        if self.fade_samples_remaining < 0 && self.fade_samples_remaining >= -(FADE_SAMPLES as i32) {
            self.fade_samples_remaining += 1;
            if self.fade_samples_remaining == 0 {
                // Fade out complete, stop playback
                self.is_playing.store(false, Ordering::SeqCst);
                self.position_samples.store(0, Ordering::SeqCst);
            }
        } else if self.fade_samples_remaining > 0 {
            self.fade_samples_remaining -= 1;
        }

        (left * fade_gain, right * fade_gain)
    }

    /// Calculate fade gain (0.0 to 1.0)
    fn calculate_fade_gain(&self) -> f32 {
        if self.fade_samples_remaining > 0 {
            // Fade in: progress from 0 to 1
            let progress = 1.0 - (self.fade_samples_remaining as f32 / FADE_SAMPLES as f32);
            progress.clamp(0.0, 1.0)
        } else if self.fade_samples_remaining < 0 {
            // Fade out: progress from 1 to 0
            let remaining = (-self.fade_samples_remaining) as f32;
            (remaining / FADE_SAMPLES as f32).clamp(0.0, 1.0)
        } else {
            1.0 // No fade active
        }
    }
}

impl Default for PreviewPlayer {
    fn default() -> Self {
        Self::new()
    }
}

/// Extract waveform peaks from an audio clip
fn extract_waveform_peaks(clip: &AudioClip, resolution: usize) -> Vec<f32> {
    let frame_count = clip.frame_count();
    if frame_count == 0 || resolution == 0 {
        return vec![0.0; resolution];
    }

    let frames_per_peak = (frame_count as f64 / resolution as f64).max(1.0);
    let mut peaks = Vec::with_capacity(resolution);

    for i in 0..resolution {
        let start_frame = (i as f64 * frames_per_peak) as usize;
        let end_frame = ((i + 1) as f64 * frames_per_peak) as usize;
        let end_frame = end_frame.min(frame_count);

        let mut max_amplitude = 0.0f32;
        for frame in start_frame..end_frame {
            let left = clip.get_sample(frame, 0).unwrap_or(0.0).abs();
            let right = if clip.channels > 1 {
                clip.get_sample(frame, 1).unwrap_or(0.0).abs()
            } else {
                left
            };
            max_amplitude = max_amplitude.max(left).max(right);
        }
        peaks.push(max_amplitude);
    }

    peaks
}

/// Resample peaks to a different resolution
fn resample_peaks(peaks: &[f32], target_resolution: usize) -> Vec<f32> {
    if peaks.is_empty() || target_resolution == 0 {
        return vec![0.0; target_resolution];
    }

    if peaks.len() == target_resolution {
        return peaks.to_vec();
    }

    let ratio = peaks.len() as f64 / target_resolution as f64;
    let mut result = Vec::with_capacity(target_resolution);

    for i in 0..target_resolution {
        let src_start = (i as f64 * ratio) as usize;
        let src_end = ((i + 1) as f64 * ratio) as usize;
        let src_end = src_end.min(peaks.len());

        if src_start >= peaks.len() {
            result.push(0.0);
        } else if src_end <= src_start {
            result.push(peaks[src_start]);
        } else {
            // Take max in range
            let max_val = peaks[src_start..src_end]
                .iter()
                .copied()
                .fold(0.0f32, f32::max);
            result.push(max_val);
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preview_player_creation() {
        let player = PreviewPlayer::new();
        assert!(!player.is_playing());
        assert_eq!(player.get_position(), 0.0);
        assert_eq!(player.get_duration(), 0.0);
    }

    #[test]
    fn test_fade_gain_calculation() {
        let mut player = PreviewPlayer::new();

        // No fade
        player.fade_samples_remaining = 0;
        assert_eq!(player.calculate_fade_gain(), 1.0);

        // Fade in at start
        player.fade_samples_remaining = FADE_SAMPLES as i32;
        assert!(player.calculate_fade_gain() < 0.1);

        // Fade in at end
        player.fade_samples_remaining = 1;
        assert!(player.calculate_fade_gain() > 0.9);

        // Fade out at start
        player.fade_samples_remaining = -(FADE_SAMPLES as i32);
        assert!(player.calculate_fade_gain() > 0.9);

        // Fade out at end
        player.fade_samples_remaining = -1;
        assert!(player.calculate_fade_gain() < 0.1);
    }

    #[test]
    fn test_resample_peaks() {
        let peaks = vec![0.5, 1.0, 0.3, 0.8];

        // Same size
        let result = resample_peaks(&peaks, 4);
        assert_eq!(result.len(), 4);

        // Smaller
        let result = resample_peaks(&peaks, 2);
        assert_eq!(result.len(), 2);

        // Larger
        let result = resample_peaks(&peaks, 8);
        assert_eq!(result.len(), 8);
    }
}
