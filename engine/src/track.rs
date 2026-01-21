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
    /// Input monitoring enabled
    pub input_monitoring: bool,

    // --- Metering ---
    /// Peak level for left channel (for meters)
    pub peak_left: f32,
    /// Peak level for right channel
    pub peak_right: f32,
}

impl Track {
    /// Create a new track
    pub fn new(id: TrackId, track_type: TrackType, name: String) -> Self {
        // Audio, MIDI, and Sampler tracks are armed by default (ready to record)
        let armed = matches!(track_type, TrackType::Audio | TrackType::Midi | TrackType::Sampler);

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
            input_monitoring: false,
            peak_left: 0.0,
            peak_right: 0.0,
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
