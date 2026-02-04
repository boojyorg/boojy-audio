/// Track system for M4: Mixing & Effects
///
/// This module implements the multi-track architecture including:
/// - Track types: Audio, MIDI, Return (FX bus), Group, Master
/// - Per-track controls: volume, pan, mute, solo
/// - Send routing (track → return track)
/// - FX chain (ordered list of effects per track)

use std::sync::Arc;
use crate::audio_file::AudioClip;
use crate::midi::MidiClip;
use crate::effects::EffectId;

/// Unique identifier for tracks
pub type TrackId = u64;

/// Unique identifier for clips (both audio and MIDI)
pub type ClipId = u64;

/// Represents an audio clip placed on a track's timeline
#[derive(Clone)]
pub struct TimelineClip {
    pub id: ClipId,
    pub clip: Arc<AudioClip>,
    /// Position on timeline in seconds
    pub start_time: f64,
    /// Offset into the clip in seconds (for trimming start)
    pub offset: f64,
    /// Duration to play (None = play entire clip)
    pub duration: Option<f64>,
    /// Per-clip gain in dB (default 0.0 = unity)
    pub gain_db: f32,
    /// Warp/tempo sync enabled (stretch to match project tempo)
    pub warp_enabled: bool,
    /// Stretch factor for time-stretching (1.0 = normal, 2.0 = double speed)
    /// Calculated as: project_bpm / clip_original_bpm
    pub stretch_factor: f32,
    /// Warp algorithm mode: 0 = warp (pitch preserved), 1 = repitch (pitch follows speed)
    pub warp_mode: u8,
    /// Cached stretched audio for Warp mode (pitch-preserved time-stretching)
    /// Only used when warp_enabled=true AND warp_mode=0 (Warp)
    pub stretched_cache: Option<Arc<AudioClip>>,
    /// Stretch factor used when the cache was built (to detect when rebuild is needed)
    pub cached_stretch_factor: f32,
    /// Transpose in semitones (-48 to +48)
    pub transpose_semitones: i32,
    /// Fine pitch adjustment in cents (-50 to +50)
    pub transpose_cents: i32,

    // --- Clip-based Automation ---
    /// Volume automation curve (time in beats relative to clip start)
    /// When not empty, modulates the clip's gain during playback
    pub volume_automation: Vec<ClipAutomationPoint>,
    /// Pan automation curve (time in beats relative to clip start)
    /// Values: 0.0 = full left, 0.5 = center, 1.0 = full right
    pub pan_automation: Vec<ClipAutomationPoint>,
}

impl TimelineClip {
    /// Convert clip gain from dB to linear
    /// -70 dB → 0.0 (silent)
    /// 0 dB → 1.0 (unity)
    /// +24 dB → ~15.85
    pub fn get_gain(&self) -> f32 {
        if self.gain_db <= -70.0 {
            0.0
        } else {
            10_f32.powf(self.gain_db / 20.0)
        }
    }

    /// Get pitch shift ratio for playback
    /// Combines semitones and cents: ratio = 2^((semitones + cents/100) / 12)
    pub fn get_pitch_ratio(&self) -> f32 {
        let total_semitones = self.transpose_semitones as f32 + (self.transpose_cents as f32 / 100.0);
        2_f32.powf(total_semitones / 12.0)
    }

    /// Rebuild the stretched audio cache for Warp mode (pitch-preserved time-stretching).
    /// Call this when warp settings change (warp_enabled, stretch_factor, warp_mode).
    pub fn rebuild_stretched_cache(&mut self) {
        use crate::stretch::stretch_audio_preserve_pitch;

        // Only build cache for Warp mode (warp_mode=0) when warp is enabled
        if self.warp_enabled && self.warp_mode == 0 {
            // Check if we need to rebuild (stretch factor changed)
            if self.stretched_cache.is_none()
                || (self.cached_stretch_factor - self.stretch_factor).abs() > 0.001
            {
                self.stretched_cache = Some(stretch_audio_preserve_pitch(&self.clip, self.stretch_factor));
                self.cached_stretch_factor = self.stretch_factor;
            }
        } else {
            // Clear cache for Re-Pitch mode or when warp is disabled
            self.stretched_cache = None;
            self.cached_stretch_factor = 0.0;
        }
    }

    /// Clear the stretched cache (call when clip is replaced or removed)
    pub fn clear_stretched_cache(&mut self) {
        self.stretched_cache = None;
        self.cached_stretch_factor = 0.0;
    }

    /// Check if clip has volume automation
    pub fn has_volume_automation(&self) -> bool {
        !self.volume_automation.is_empty()
    }

    /// Check if clip has pan automation
    pub fn has_pan_automation(&self) -> bool {
        !self.pan_automation.is_empty()
    }

    /// Get interpolated volume value at a specific beat position (relative to clip start).
    /// Returns normalized value 0-1.
    /// Edge behavior: holds first/last point values outside automation range.
    pub fn get_volume_at_beat(&self, beat: f64) -> f32 {
        Self::interpolate_clip_automation(&self.volume_automation, beat, 0.833) // 0.833 ≈ 0 dB
    }

    /// Get interpolated pan value at a specific beat position (relative to clip start).
    /// Returns normalized value 0-1 (0.0 = left, 0.5 = center, 1.0 = right).
    /// Edge behavior: holds first/last point values outside automation range.
    pub fn get_pan_at_beat(&self, beat: f64) -> f32 {
        Self::interpolate_clip_automation(&self.pan_automation, beat, 0.5) // 0.5 = center
    }

    /// Generic automation interpolation with edge hold behavior.
    /// Returns default_value if automation is empty.
    /// Public so TimelineMidiClip can reuse it.
    pub fn interpolate_clip_automation(points: &[ClipAutomationPoint], beat: f64, default_value: f32) -> f32 {
        if points.is_empty() {
            return default_value;
        }

        // Before first point - hold first point's value
        if beat <= points[0].time_beats {
            return points[0].value;
        }

        // After last point - hold last point's value
        if beat >= points[points.len() - 1].time_beats {
            return points[points.len() - 1].value;
        }

        // Binary search for surrounding points
        let mut low = 0usize;
        let mut high = points.len() - 1;

        while low < high - 1 {
            let mid = (low + high) / 2;
            if points[mid].time_beats <= beat {
                low = mid;
            } else {
                high = mid;
            }
        }

        // Linear interpolation between points[low] and points[high]
        let p1 = &points[low];
        let p2 = &points[high];
        let t = (beat - p1.time_beats) / (p2.time_beats - p1.time_beats);
        p1.value + (p2.value - p1.value) * t as f32
    }

    /// Set volume automation from CSV string.
    /// Format: "beat,value;beat,value;..." where beat is relative to clip start
    /// and value is normalized 0-1.
    pub fn set_volume_automation_csv(&mut self, csv: &str) {
        self.volume_automation = Self::parse_clip_automation_csv(csv);
    }

    /// Set pan automation from CSV string.
    /// Format: "beat,value;beat,value;..." where beat is relative to clip start
    /// and value is normalized 0-1 (0=left, 0.5=center, 1=right).
    pub fn set_pan_automation_csv(&mut self, csv: &str) {
        self.pan_automation = Self::parse_clip_automation_csv(csv);
    }

    /// Parse automation CSV into points, sorted by time.
    /// Public so TimelineMidiClip can reuse it.
    pub fn parse_clip_automation_csv(csv: &str) -> Vec<ClipAutomationPoint> {
        if csv.is_empty() {
            return Vec::new();
        }

        let mut points: Vec<ClipAutomationPoint> = csv
            .split(';')
            .filter_map(|pair| {
                let parts: Vec<&str> = pair.split(',').collect();
                if parts.len() == 2 {
                    if let (Ok(beat), Ok(value)) = (parts[0].parse::<f64>(), parts[1].parse::<f32>()) {
                        return Some(ClipAutomationPoint::new(beat, value.clamp(0.0, 1.0)));
                    }
                }
                None
            })
            .collect();

        // Sort by time
        points.sort_by(|a, b| {
            a.time_beats.partial_cmp(&b.time_beats).unwrap_or(std::cmp::Ordering::Equal)
        });

        points
    }
}

/// Represents a MIDI clip placed on a track's timeline
#[derive(Clone)]
pub struct TimelineMidiClip {
    pub id: ClipId,
    pub clip: Arc<MidiClip>,
    /// Position on timeline in seconds
    pub start_time: f64,
    /// Track ID this clip belongs to (for cleanup on track deletion)
    pub track_id: Option<TrackId>,

    // --- Clip-based Automation ---
    /// Volume automation curve (time in beats relative to clip start)
    pub volume_automation: Vec<ClipAutomationPoint>,
    /// Pan automation curve (time in beats relative to clip start)
    pub pan_automation: Vec<ClipAutomationPoint>,
}

impl TimelineMidiClip {
    /// Check if clip has volume automation
    pub fn has_volume_automation(&self) -> bool {
        !self.volume_automation.is_empty()
    }

    /// Check if clip has pan automation
    pub fn has_pan_automation(&self) -> bool {
        !self.pan_automation.is_empty()
    }

    /// Get interpolated volume value at a specific beat position (relative to clip start).
    /// Returns normalized value 0-1.
    pub fn get_volume_at_beat(&self, beat: f64) -> f32 {
        TimelineClip::interpolate_clip_automation(&self.volume_automation, beat, 0.833)
    }

    /// Get interpolated pan value at a specific beat position (relative to clip start).
    /// Returns normalized value 0-1.
    pub fn get_pan_at_beat(&self, beat: f64) -> f32 {
        TimelineClip::interpolate_clip_automation(&self.pan_automation, beat, 0.5)
    }

    /// Set volume automation from CSV string
    pub fn set_volume_automation_csv(&mut self, csv: &str) {
        self.volume_automation = TimelineClip::parse_clip_automation_csv(csv);
    }

    /// Set pan automation from CSV string
    pub fn set_pan_automation_csv(&mut self, csv: &str) {
        self.pan_automation = TimelineClip::parse_clip_automation_csv(csv);
    }
}

/// Track types supported in Boojy Audio
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackType {
    /// Audio track: holds audio clips
    Audio,
    /// MIDI track: holds MIDI clips, routed to instruments
    Midi,
    /// Sampler track: MIDI track with sampler instrument for sample playback
    Sampler,
    /// Return track: receives audio from send buses (no clips)
    Return,
    /// Group track: combines multiple tracks (folder/bus)
    Group,
    /// Master track: final output (only one per project)
    Master,
}

/// Send configuration: how much signal to send to a Return track
#[derive(Debug, Clone)]
pub struct Send {
    /// Target Return track ID
    pub target_track_id: TrackId,
    /// Send amount (0.0 = silent, 1.0 = full)
    pub amount: f32,
    /// Pre/post fader
    pub pre_fader: bool,
}

/// Automation point: a single point in an automation curve
#[derive(Debug, Clone, Copy)]
pub struct AutomationPoint {
    /// Time position in seconds
    pub time_seconds: f64,
    /// Value in dB (for volume automation)
    pub value_db: f32,
}

impl AutomationPoint {
    /// Create a new automation point
    pub fn new(time_seconds: f64, value_db: f32) -> Self {
        Self { time_seconds, value_db }
    }
}

/// Clip-level automation point: time is relative to clip start (in beats)
#[derive(Debug, Clone, Copy)]
pub struct ClipAutomationPoint {
    /// Time position in beats, relative to clip start
    pub time_beats: f64,
    /// Value normalized 0-1
    pub value: f32,
}

impl ClipAutomationPoint {
    /// Create a new clip automation point
    pub fn new(time_beats: f64, value: f32) -> Self {
        Self { time_beats, value }
    }
}

/// A track in the DAW
pub struct Track {
    /// Unique ID
    pub id: TrackId,
    /// Track type
    pub track_type: TrackType,
    /// Display name
    pub name: String,

    // --- Clips ---
    /// Audio clips on this track (for Audio tracks)
    pub audio_clips: Vec<TimelineClip>,
    /// MIDI clips on this track (for MIDI tracks)
    pub midi_clips: Vec<TimelineMidiClip>,

    // --- Mixer Controls ---
    /// Volume in dB (-∞ to +6 dB)
    /// -∞ = silent, 0 dB = unity, +6 dB = 2x gain
    pub volume_db: f32,
    /// Pan position (-1.0 = full left, 0.0 = center, +1.0 = full right)
    pub pan: f32,
    /// Mute state
    pub mute: bool,
    /// Solo state
    pub solo: bool,

    // --- Routing ---
    /// Send destinations (to Return tracks)
    pub sends: Vec<Send>,
    /// Parent group track (None = top-level)
    pub parent_group: Option<TrackId>,

    // --- Effects ---
    /// Effect chain (processed in order)
    pub fx_chain: Vec<EffectId>,

    // --- Recording ---
    /// Armed for recording (Audio/MIDI tracks only)
    pub armed: bool,
    /// Input monitoring enabled (hear input through track when armed)
    pub input_monitoring: bool,
    /// Fade gain for monitoring transitions (0.0-1.0, avoids clicks on arm/disarm)
    pub monitoring_fade_gain: f64,

    // --- Input Routing ---
    /// Audio input device index (None = no input assigned)
    pub input_device_index: Option<usize>,
    /// Audio input channel within the device (0-based, mono)
    pub input_channel: u32,

    // --- Metering ---
    /// Peak level for left channel (for meters)
    pub peak_left: f32,
    /// Peak level for right channel
    pub peak_right: f32,

    // --- Automation ---
    /// Volume automation curve (sorted by time_seconds)
    /// When not empty, overrides static volume_db during playback
    pub volume_automation: Vec<AutomationPoint>,
}

impl Track {
    /// Create a new track
    pub fn new(id: TrackId, track_type: TrackType, name: String) -> Self {
        // Audio, MIDI, and Sampler tracks are armed by default (ready to record)
        let armed = matches!(track_type, TrackType::Audio | TrackType::Midi | TrackType::Sampler);

        // Audio tracks get default input device (first device, channel 0)
        let input_device_index = if matches!(track_type, TrackType::Audio | TrackType::Sampler) {
            Some(0)
        } else {
            None
        };

        Self {
            id,
            track_type,
            name,
            audio_clips: Vec::new(),
            midi_clips: Vec::new(),
            volume_db: 0.0, // Unity gain
            pan: 0.0,        // Center
            mute: false,
            solo: false,
            sends: Vec::new(),
            parent_group: None,
            fx_chain: Vec::new(),
            armed,
            input_monitoring: armed,
            monitoring_fade_gain: if armed { 1.0 } else { 0.0 },
            input_device_index,
            input_channel: 0,
            peak_left: 0.0,
            peak_right: 0.0,
            volume_automation: Vec::new(),
        }
    }

    /// Convert volume from dB to linear gain
    /// -∞ dB → 0.0
    /// 0 dB → 1.0
    /// +6 dB → 2.0
    pub fn get_gain(&self) -> f32 {
        if self.volume_db <= -96.0 {
            0.0 // Treat anything below -96 dB as silent
        } else {
            10_f32.powf(self.volume_db / 20.0)
        }
    }

    /// Get pan coefficients for stereo panning
    /// Returns (left_gain, right_gain)
    ///
    /// Uses equal-power panning law:
    /// - pan = -1.0 → (1.0, 0.0) = full left
    /// - pan =  0.0 → (0.707, 0.707) = center (-3 dB each)
    /// - pan = +1.0 → (0.0, 1.0) = full right
    pub fn get_pan_gains(&self) -> (f32, f32) {
        let pan_normalized = (self.pan + 1.0) / 2.0; // Map -1..1 to 0..1
        let pan_radians = pan_normalized * std::f32::consts::FRAC_PI_2; // 0 to π/2

        let left_gain = pan_radians.cos();
        let right_gain = pan_radians.sin();

        (left_gain, right_gain)
    }

    /// Update peak meters (called from audio thread)
    pub fn update_peaks(&mut self, left: f32, right: f32) {
        self.peak_left = left.abs();
        self.peak_right = right.abs();
    }

    /// Get peak levels in dB
    pub fn get_peak_db(&self) -> (f32, f32) {
        let left_db = if self.peak_left > 0.0 {
            20.0 * self.peak_left.log10()
        } else {
            -96.0 // -∞ dB
        };

        let right_db = if self.peak_right > 0.0 {
            20.0 * self.peak_right.log10()
        } else {
            -96.0
        };

        (left_db, right_db)
    }

    /// Get interpolated volume at a specific time (in seconds)
    /// Uses linear interpolation between automation points
    /// Returns static volume_db if no automation exists
    pub fn get_volume_at(&self, time_seconds: f64) -> f32 {
        if self.volume_automation.is_empty() {
            return self.volume_db;
        }

        let points = &self.volume_automation;

        // Before first point - use first point's value
        if time_seconds <= points[0].time_seconds {
            return points[0].value_db;
        }

        // After last point - use last point's value
        if time_seconds >= points[points.len() - 1].time_seconds {
            return points[points.len() - 1].value_db;
        }

        // Find surrounding points and interpolate (binary search for efficiency)
        let mut low = 0usize;
        let mut high = points.len() - 1;

        while low < high - 1 {
            let mid = (low + high) / 2;
            if points[mid].time_seconds <= time_seconds {
                low = mid;
            } else {
                high = mid;
            }
        }

        // Linear interpolation between points[low] and points[high]
        let p1 = &points[low];
        let p2 = &points[high];
        let t = (time_seconds - p1.time_seconds) / (p2.time_seconds - p1.time_seconds);
        p1.value_db + (p2.value_db - p1.value_db) * t as f32
    }

    /// Get interpolated gain (linear) at a specific time
    /// Converts the dB value from get_volume_at() to linear gain
    pub fn get_gain_at(&self, time_seconds: f64) -> f32 {
        let db = self.get_volume_at(time_seconds);
        if db <= -96.0 {
            0.0
        } else {
            10_f32.powf(db / 20.0)
        }
    }

    /// Set volume automation curve from a CSV string
    /// Format: "time,db;time,db;..." where time is in seconds
    /// Empty string clears the automation
    pub fn set_volume_automation_csv(&mut self, csv: &str) {
        self.volume_automation.clear();

        if csv.is_empty() {
            return;
        }

        for pair in csv.split(';') {
            let parts: Vec<&str> = pair.split(',').collect();
            if parts.len() == 2 {
                if let (Ok(time), Ok(db)) = (parts[0].parse::<f64>(), parts[1].parse::<f32>()) {
                    self.volume_automation.push(AutomationPoint::new(time, db));
                }
            }
        }

        // Sort by time (should already be sorted, but ensure it)
        self.volume_automation.sort_by(|a, b| {
            a.time_seconds.partial_cmp(&b.time_seconds).unwrap_or(std::cmp::Ordering::Equal)
        });
    }

    /// Check if track has volume automation
    pub fn has_volume_automation(&self) -> bool {
        !self.volume_automation.is_empty()
    }
}

/// Track manager: handles all tracks in a project
pub struct TrackManager {
    /// All tracks (including master)
    tracks: Vec<Arc<std::sync::Mutex<Track>>>,
    /// Next track ID
    next_id: TrackId,
    /// Master track ID (always exists)
    master_track_id: TrackId,
}

impl TrackManager {
    /// Create a new track manager with a master track
    pub fn new() -> Self {
        let master_track = Arc::new(std::sync::Mutex::new(
            Track::new(0, TrackType::Master, "Master".to_string())
        ));

        Self {
            tracks: vec![master_track],
            next_id: 1,
            master_track_id: 0,
        }
    }

    /// Create a new track
    pub fn create_track(&mut self, track_type: TrackType, name: String) -> TrackId {
        let id = self.next_id;
        self.next_id += 1;

        // New tracks are armed by default (Ableton-style)
        // Multiple tracks can be armed simultaneously
        let track = Arc::new(std::sync::Mutex::new(
            Track::new(id, track_type, name)
        ));

        self.tracks.push(track);

        id
    }

    /// Get a track by ID
    pub fn get_track(&self, id: TrackId) -> Option<Arc<std::sync::Mutex<Track>>> {
        self.tracks.iter()
            .find(|t| t.lock().expect("mutex poisoned").id == id)
            .cloned()
    }

    /// Get master track
    pub fn get_master_track(&self) -> Arc<std::sync::Mutex<Track>> {
        self.get_track(self.master_track_id).unwrap()
    }

    /// Get all tracks
    pub fn get_all_tracks(&self) -> Vec<Arc<std::sync::Mutex<Track>>> {
        self.tracks.clone()
    }

    /// Remove a track (cannot remove master)
    pub fn remove_track(&mut self, id: TrackId) -> bool {
        if id == self.master_track_id {
            return false;
        }

        if let Some(pos) = self.tracks.iter().position(|t| t.lock().expect("mutex poisoned").id == id) {
            self.tracks.remove(pos);
            true
        } else {
            false
        }
    }

    /// Check if any tracks are soloed
    pub fn has_solo(&self) -> bool {
        self.tracks.iter()
            .any(|t| t.lock().expect("mutex poisoned").solo)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_track_creation() {
        let track = Track::new(1, TrackType::Audio, "Audio 1".to_string());
        assert_eq!(track.id, 1);
        assert_eq!(track.track_type, TrackType::Audio);
        assert_eq!(track.name, "Audio 1");
        assert_eq!(track.volume_db, 0.0);
        assert_eq!(track.pan, 0.0);
    }

    #[test]
    fn test_volume_to_gain() {
        let mut track = Track::new(1, TrackType::Audio, "Test".to_string());

        // 0 dB = unity gain
        track.volume_db = 0.0;
        assert!((track.get_gain() - 1.0).abs() < 0.001);

        // +6 dB = 2x gain
        track.volume_db = 6.0;
        assert!((track.get_gain() - 2.0).abs() < 0.01);

        // -∞ dB = 0 gain
        track.volume_db = -100.0;
        assert_eq!(track.get_gain(), 0.0);
    }

    #[test]
    fn test_pan_gains() {
        let mut track = Track::new(1, TrackType::Audio, "Test".to_string());

        // Center pan
        track.pan = 0.0;
        let (left, right) = track.get_pan_gains();
        assert!((left - 0.707).abs() < 0.01);
        assert!((right - 0.707).abs() < 0.01);

        // Full left
        track.pan = -1.0;
        let (left, right) = track.get_pan_gains();
        assert!((left - 1.0).abs() < 0.01);
        assert!(right < 0.01);

        // Full right
        track.pan = 1.0;
        let (left, right) = track.get_pan_gains();
        assert!(left < 0.01);
        assert!((right - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_track_manager() {
        let mut manager = TrackManager::new();

        // Should have master track
        assert_eq!(manager.tracks.len(), 1);

        // Create audio track
        let id = manager.create_track(TrackType::Audio, "Audio 1".to_string());
        assert_eq!(id, 1);
        assert_eq!(manager.tracks.len(), 2);

        // Get track
        let track = manager.get_track(id);
        assert!(track.is_some());

        // Remove track
        assert!(manager.remove_track(id));
        assert_eq!(manager.tracks.len(), 1);

        // Cannot remove master
        assert!(!manager.remove_track(0));
    }
}
