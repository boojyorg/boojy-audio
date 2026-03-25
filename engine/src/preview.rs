/// Preview player - dedicated audio preview for library panel
/// Plays audio files independently of the main timeline transport
///
/// Features:
/// - Load and play audio files for preview
/// - Looping for short files (< 3 seconds)
/// - Fade in/out to prevent clicks
/// - Waveform peak extraction for UI
use crate::audio_file::{load_wav_for_preview, start_streaming_decode, AudioClip, RawPreviewClip, StreamingPreviewClip, TARGET_SAMPLE_RATE};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

const FADE_SAMPLES: usize = 882; // ~20ms at 44.1kHz, ~18ms at 48kHz

/// Either a raw preview clip (WAV), decoded clip, or streaming clip (MP3/FLAC)
enum PreviewClipData {
    Raw(RawPreviewClip),
    Decoded(AudioClip),
    Streaming(StreamingPreviewClip),
}

impl PreviewClipData {
    #[inline]
    fn get_sample(&self, frame: usize, channel: usize) -> f32 {
        match self {
            Self::Raw(c) => c.get_sample(frame, channel),
            Self::Decoded(c) => c.get_sample(frame, channel).unwrap_or(0.0),
            Self::Streaming(c) => c.get_sample(frame, channel),
        }
    }

    fn frame_count(&self) -> usize {
        match self {
            Self::Raw(c) => c.frame_count,
            Self::Decoded(c) => c.frame_count(),
            Self::Streaming(c) => c.frame_count(),
        }
    }

    fn channels(&self) -> usize {
        match self {
            Self::Raw(c) => c.channels,
            Self::Decoded(c) => c.channels,
            Self::Streaming(c) => c.channels,
        }
    }

    fn sample_rate(&self) -> u32 {
        match self {
            Self::Raw(c) => c.sample_rate,
            Self::Decoded(c) => c.sample_rate,
            Self::Streaming(c) => c.sample_rate,
        }
    }

    fn duration_seconds(&self) -> f64 {
        match self {
            Self::Raw(c) => c.duration_seconds,
            Self::Decoded(c) => c.duration_seconds,
            Self::Streaming(c) => c.duration_seconds(),
        }
    }
}

/// Result of an async load operation
struct AsyncLoadResult {
    clip: PreviewClipData,
    path: String,
}

/// Preview player state
pub struct PreviewPlayer {
    /// Loaded audio clip (raw bytes for WAV, decoded for other formats)
    clip: Option<Arc<PreviewClipData>>,
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
    /// Playback rate adjustment (clip_rate / output_rate). 1.0 if rates match.
    playback_rate: f64,
    /// Fractional sample position for non-integer rate playback
    position_frac: f64,
    /// Whether an async load is in progress
    async_loading: Arc<AtomicBool>,
    /// Result of async load, ready to be swapped in
    pending_load: Arc<parking_lot::Mutex<Option<AsyncLoadResult>>>,
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
            playback_rate: 1.0,
            position_frac: 0.0,
            async_loading: Arc::new(AtomicBool::new(false)),
            pending_load: Arc::new(parking_lot::Mutex::new(None)),
        }
    }

    /// Load an audio file for preview
    pub fn load_file(&mut self, path: &str) -> Result<(), String> {
        // Stop any current playback
        self.stop();

        // Load the audio file
        let clip = crate::audio_file::load_audio_file(path).map_err(|e| e.to_string())?;
        let total_samples = (clip.duration_seconds * f64::from(TARGET_SAMPLE_RATE)) as u64;

        let should_loop = clip.duration_seconds < 3.0;
        self.is_looping.store(should_loop, Ordering::SeqCst);

        self.waveform_peaks = extract_waveform_peaks_from_clip(&clip, 200);

        self.clip = Some(Arc::new(PreviewClipData::Decoded(clip)));
        self.total_samples = total_samples;
        self.position_samples.store(0, Ordering::SeqCst);
        self.loaded_path = Some(path.to_string());
        self.playback_rate = 1.0; // sync load always resamples to 48kHz
        self.position_frac = 0.0;

        Ok(())
    }

    /// Start loading an audio file asynchronously (returns immediately)
    pub fn load_file_async(&mut self, path: &str) {
        // Stop any current playback
        self.stop();

        // Clear pending results from any previous async load
        *self.pending_load.lock() = None;
        self.async_loading.store(true, Ordering::SeqCst);

        let loading_flag = Arc::clone(&self.async_loading);
        let pending = Arc::clone(&self.pending_load);
        let path_owned = path.to_string();

        std::thread::spawn(move || {
            let t0 = std::time::Instant::now();

            // Try fast raw WAV path first
            let path = std::path::Path::new(&path_owned);
            let is_wav = path.extension()
                .and_then(|e| e.to_str())
                .is_some_and(|e| e.eq_ignore_ascii_case("wav") || e.eq_ignore_ascii_case("wave"));

            if is_wav {
                match load_wav_for_preview(&path_owned) {
                    Ok(raw_clip) => {
                        eprintln!("[PREVIEW] raw WAV read: {:?} ({} frames, {}Hz)", t0.elapsed(), raw_clip.frame_count, raw_clip.sample_rate);
                        // Peaks deferred — playback starts immediately
                        *pending.lock() = Some(AsyncLoadResult {
                            clip: PreviewClipData::Raw(raw_clip),
                            path: path_owned,
                        });
                        loading_flag.store(false, Ordering::SeqCst);
                        return;
                    }
                    Err(e) => {
                        eprintln!("[PREVIEW] raw WAV failed: {e}, trying Symphonia");
                    }
                }
            }

            // Streaming decode: start decoding, make clip available after first ~1s of data
            match start_streaming_decode(&path_owned) {
                Ok(streaming_clip) => {
                    // Wait until at least 1 second of audio is decoded before making available
                    let min_frames = streaming_clip.sample_rate as usize;
                    let decoded = &streaming_clip.decoded_frames;
                    let fully_done = &streaming_clip.fully_decoded;

                    // Spin-wait for initial data (typically < 100ms for MP3)
                    while decoded.load(Ordering::Acquire) < min_frames
                        && !fully_done.load(Ordering::Acquire) {
                        std::thread::sleep(std::time::Duration::from_millis(5));
                    }

                    eprintln!("[PREVIEW] streaming ready: {:?} ({} frames decoded so far, {}Hz)",
                        t0.elapsed(), decoded.load(Ordering::Relaxed), streaming_clip.sample_rate);

                    *pending.lock() = Some(AsyncLoadResult {
                        clip: PreviewClipData::Streaming(streaming_clip),
                        path: path_owned,
                    });
                }
                Err(e) => {
                    eprintln!("[PREVIEW] streaming decode error: {e}");
                }
            }
            loading_flag.store(false, Ordering::SeqCst);
        });
    }

    /// Check if an async load has completed and swap the result in
    /// Returns true if a new clip is now ready
    pub fn check_async_loaded(&mut self) -> bool {
        if self.async_loading.load(Ordering::SeqCst) {
            return false; // Still loading
        }

        let result = self.pending_load.lock().take();
        if let Some(loaded) = result {
            let clip_rate = loaded.clip.sample_rate();
            let total_frames = loaded.clip.frame_count() as u64;
            self.playback_rate = f64::from(clip_rate) / f64::from(TARGET_SAMPLE_RATE);
            self.position_frac = 0.0;
            self.is_looping.store(false, Ordering::SeqCst);
            self.waveform_peaks = Vec::new(); // Deferred — computed after playback starts
            self.total_samples = total_frames;
            self.clip = Some(Arc::new(loaded.clip));
            self.position_samples.store(0, Ordering::SeqCst);
            self.loaded_path = Some(loaded.path);
            return true;
        }

        false
    }

    /// Check if a full clip is ready to hot-swap (after partial decode started playing)
    /// Whether an async load is currently in progress
    pub fn is_async_loading(&self) -> bool {
        self.async_loading.load(Ordering::SeqCst)
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
        let clip_rate = self.clip.as_ref().map_or(TARGET_SAMPLE_RATE, |c| c.sample_rate());
        let sample_pos = (position_seconds * f64::from(clip_rate)) as u64;
        let clamped = sample_pos.min(self.total_samples);
        self.position_samples.store(clamped, Ordering::SeqCst);
        self.position_frac = 0.0;
    }

    /// Get current playback position in seconds
    pub fn get_position(&self) -> f64 {
        let clip_rate = self.clip.as_ref().map_or(TARGET_SAMPLE_RATE, |c| c.sample_rate());
        let samples = self.position_samples.load(Ordering::SeqCst);
        samples as f64 / f64::from(clip_rate)
    }

    /// Get total duration in seconds
    pub fn get_duration(&self) -> f64 {
        self.clip
            .as_ref()
            .map_or(0.0, |c| c.duration_seconds())
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

    /// Get waveform peaks for UI display.
    /// Computes lazily from the loaded clip if not yet cached.
    pub fn get_waveform_peaks(&mut self, resolution: usize) -> Vec<f32> {
        if self.waveform_peaks.is_empty() {
            // Compute from loaded clip
            if let Some(clip) = &self.clip {
                let frame_count = clip.frame_count();
                if frame_count > 0 {
                    let frames_per_peak = (frame_count as f64 / resolution as f64).max(1.0);
                    let mut peaks = Vec::with_capacity(resolution);
                    let ch = clip.channels();
                    for i in 0..resolution {
                        let start = (i as f64 * frames_per_peak) as usize;
                        let end = (((i + 1) as f64 * frames_per_peak) as usize).min(frame_count);
                        let mut max_amp = 0.0f32;
                        for frame in start..end {
                            let l = clip.get_sample(frame, 0).abs();
                            let r = if ch > 1 { clip.get_sample(frame, 1).abs() } else { l };
                            max_amp = max_amp.max(l).max(r);
                        }
                        peaks.push(max_amp);
                    }
                    self.waveform_peaks = peaks;
                }
            }
            if self.waveform_peaks.is_empty() {
                return vec![0.0; resolution];
            }
        }

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

        let Some(clip) = &self.clip else {
            return (0.0, 0.0);
        };

        let position = self.position_samples.load(Ordering::SeqCst);
        let frame_count = clip.frame_count();

        // Handle end of decoded data
        if position as usize >= frame_count {
            // Check if clip is still streaming (more data coming)
            let still_streaming = matches!(clip.as_ref(), PreviewClipData::Streaming(s) if !s.is_fully_decoded());
            if still_streaming {
                // Output silence while waiting for more decoded data
                return (0.0, 0.0);
            }
            // Clip is fully loaded — handle end normally
            if self.is_looping.load(Ordering::SeqCst) {
                self.position_samples.store(0, Ordering::SeqCst);
            } else {
                self.is_playing.store(false, Ordering::SeqCst);
                return (0.0, 0.0);
            }
        }

        // Get sample at current position (linear interpolation for rate conversion)
        let frame_idx = position as usize;
        let frac = self.position_frac as f32;

        let left = if frac > 0.0 && frame_idx + 1 < frame_count {
            let a = clip.get_sample(frame_idx, 0);
            let b = clip.get_sample(frame_idx + 1, 0);
            a + (b - a) * frac
        } else {
            clip.get_sample(frame_idx, 0)
        };
        let right = if clip.channels() > 1 {
            if frac > 0.0 && frame_idx + 1 < frame_count {
                let a = clip.get_sample(frame_idx, 1);
                let b = clip.get_sample(frame_idx + 1, 1);
                a + (b - a) * frac
            } else {
                clip.get_sample(frame_idx, 1)
            }
        } else {
            left
        };

        // Calculate fade envelope
        let fade_gain = self.calculate_fade_gain();

        // Advance position by playback rate (handles sample rate mismatch)
        // For 44.1k→48k: rate=0.91875, so we advance <1 sample per output frame
        // Fractional accumulator ensures correct average rate
        self.position_frac += self.playback_rate;
        let advance = self.position_frac as u64;
        self.position_frac -= advance as f64;
        if advance > 0 {
            self.position_samples.fetch_add(advance, Ordering::SeqCst);
        }

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

        // Clamp to prevent clipping from interpolation
        ((left * fade_gain).clamp(-1.0, 1.0), (right * fade_gain).clamp(-1.0, 1.0))
    }

    /// Calculate fade gain (0.0 to 1.0)
    fn calculate_fade_gain(&self) -> f32 {
        match self.fade_samples_remaining.cmp(&0) {
            std::cmp::Ordering::Greater => {
                // Fade in: progress from 0 to 1
                let progress = 1.0 - (self.fade_samples_remaining as f32 / FADE_SAMPLES as f32);
                progress.clamp(0.0, 1.0)
            }
            std::cmp::Ordering::Less => {
                // Fade out: progress from 1 to 0
                let remaining = (-self.fade_samples_remaining) as f32;
                (remaining / FADE_SAMPLES as f32).clamp(0.0, 1.0)
            }
            std::cmp::Ordering::Equal => 1.0, // No fade active
        }
    }
}

impl Default for PreviewPlayer {
    fn default() -> Self {
        Self::new()
    }
}

/// Extract waveform peaks from a decoded AudioClip
pub(crate) fn extract_waveform_peaks_from_clip(clip: &AudioClip, resolution: usize) -> Vec<f32> {
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
