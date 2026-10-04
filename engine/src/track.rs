use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::effects::EffectId;
use crate::midi::MidiClip;
/// Track system for M4: Mixing & Effects
///
/// This module implements the multi-track architecture including:
/// - Track types: Audio, MIDI, Return (FX bus), Group, Master
/// - Per-track controls: volume, pan, mute, solo
/// - Send routing (track → return track)
/// - FX chain (ordered list of effects per track)
use std::sync::Arc;

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
    /// Calculated as: `project_bpm` / `clip_original_bpm`
    pub stretch_factor: f32,
    /// Warp algorithm mode: 0 = warp (pitch preserved), 1 = repitch (pitch follows speed)
    pub warp_mode: u8,
    /// The clip's audio stretched to the project tempo (Warp mode) and/or
    /// pitch-shifted by its transpose; playback reads it at normal speed.
    /// `None` when neither applies. See [`TimelineClip::processed_audio`].
    pub stretched_cache: Option<Arc<AudioClip>>,
    /// Stretch and transpose the cache was built with (to reuse it).
    pub cached_stretch_factor: f32,
    pub cached_transpose_cents: i32,
    /// Transpose in semitones (-48 to +48)
    pub transpose_semitones: i32,
    /// Fine pitch adjustment in cents (-50 to +50)
    pub transpose_cents: i32,
    /// Play the clip's audible window backwards
    pub reversed: bool,
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

    /// Timeline seconds played into the clip's audible window, reflected when
    /// `reversed` so the warp/pitch math after it applies unchanged. Not
    /// including the trim offset: that is in seconds of the clip's own
    /// audio, which warp doesn't stretch. `effective_duration` is the clip's
    /// on-timeline duration (post-warp).
    pub fn progress_in_clip(&self, playhead_seconds: f64, effective_duration: f64) -> f64 {
        let progress = playhead_seconds - self.start_time;
        if self.reversed {
            // Reflect onto the window's LAST frame, not one past it: the
            // first reversed frame was silent and every frame after played
            // one late, so the window's first frame never played.
            let last_frame = effective_duration - 1.0 / f64::from(TARGET_SAMPLE_RATE);
            (last_frame - progress).max(0.0)
        } else {
            progress
        }
    }

    /// Get pitch shift ratio for playback
    /// Combines semitones and cents: ratio = 2^((semitones + cents/100) / 12)
    pub fn get_pitch_ratio(&self) -> f32 {
        let total_semitones =
            self.transpose_semitones as f32 + (self.transpose_cents as f32 / 100.0);
        2_f32.powf(total_semitones / 12.0)
    }

    fn transpose_total_cents(&self) -> i32 {
        self.transpose_semitones * 100 + self.transpose_cents
    }

    /// The stretch baked into the processed audio: Warp mode stretches it to
    /// the project tempo; Re-Pitch and unwarped clips are not stretched.
    pub(crate) fn processed_stretch(&self) -> f32 {
        if self.warp_enabled && self.warp_mode == 0 {
            self.stretch_factor
        } else {
            1.0
        }
    }

    /// The audio playback reads for these settings: stretched (Warp) and
    /// pitch-shifted (transpose), or `None` to read the source as it is.
    /// Transpose always goes through here, so it changes the pitch and never
    /// the timing. Reuses the current cache when nothing changed; otherwise
    /// it renders the whole clip, which is slow, so call it on a copy of the
    /// clip with no locks held, then [`Self::set_processed_audio`].
    pub fn processed_audio(&self) -> Option<Arc<AudioClip>> {
        let stretch = self.processed_stretch();
        let cents = self.transpose_total_cents();
        if (stretch - 1.0).abs() <= 0.001 && cents == 0 {
            return None;
        }
        if let Some(cache) = &self.stretched_cache {
            if (self.cached_stretch_factor - stretch).abs() <= 0.001
                && self.cached_transpose_cents == cents
            {
                return Some(cache.clone());
            }
        }
        Some(crate::stretch::process_audio(
            &self.clip,
            stretch,
            cents as f32 / 100.0,
        ))
    }

    /// Install audio from [`Self::processed_audio`] for the current settings.
    pub fn set_processed_audio(&mut self, audio: Option<Arc<AudioClip>>) {
        self.cached_stretch_factor = self.processed_stretch();
        self.cached_transpose_cents = self.transpose_total_cents();
        self.stretched_cache = audio;
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
    /// Deprecated: Use TrackType::Midi with sampler instrument instead.
    /// Kept only for loading old project files.
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
        Self {
            time_seconds,
            value_db,
        }
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
    /// Volume automation curve (sorted by `time_seconds`)
    /// When not empty, overrides static `volume_db` during playback
    pub volume_automation: Vec<AutomationPoint>,

    // --- Timeline visibility ---
    /// Whether this track appears as a row in the arrangement timeline
    pub timeline_visible: bool,
}

impl Track {
    /// Create a new track
    pub fn new(id: TrackId, track_type: TrackType, name: String) -> Self {
        // Audio and MIDI tracks are armed by default (ready to record)
        let armed = matches!(track_type, TrackType::Audio | TrackType::Midi);

        // Audio tracks get default input device (first device, channel 0)
        let input_device_index = if matches!(track_type, TrackType::Audio) {
            Some(0)
        } else {
            None
        };

        let timeline_visible = !matches!(track_type, TrackType::Master | TrackType::Return);

        Self {
            id,
            track_type,
            name,
            audio_clips: Vec::new(),
            midi_clips: Vec::new(),
            volume_db: 0.0, // Unity gain
            pan: 0.0,       // Center
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
            timeline_visible,
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
    /// Returns (`left_gain`, `right_gain`)
    ///
    /// Tracks use the equal-power panning law:
    /// - pan = -1.0 → (1.0, 0.0) = full left
    /// - pan =  0.0 → (0.707, 0.707) = center (-3 dB each)
    /// - pan = +1.0 → (0.0, 1.0) = full right
    ///
    /// The master is a balance control: unity at centre, turning one side
    /// down as it moves. Constant power on the master too cut every mix by
    /// a second 3 dB (a centred track played 6 dB under its source).
    pub fn get_pan_gains(&self) -> (f32, f32) {
        if self.track_type == TrackType::Master {
            return (
                (1.0 - self.pan).clamp(0.0, 1.0),
                (1.0 + self.pan).clamp(0.0, 1.0),
            );
        }
        let pan_normalized = f32::midpoint(self.pan, 1.0); // Map -1..1 to 0..1
        let pan_radians = pan_normalized * std::f32::consts::FRAC_PI_2; // 0 to π/2

        let left_gain = pan_radians.cos();
        let right_gain = pan_radians.sin();

        (left_gain, right_gain)
    }

    /// Update peak meters (called from audio thread).
    /// Accumulates the maximum level since last read.
    pub fn update_peaks(&mut self, left: f32, right: f32) {
        self.peak_left = self.peak_left.max(left.abs());
        self.peak_right = self.peak_right.max(right.abs());
    }

    /// Get peak levels in dB, then reset for next poll cycle.
    pub fn get_peak_db(&mut self) -> (f32, f32) {
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

        // Reset after reading so next poll gets fresh max
        self.peak_left = 0.0;
        self.peak_right = 0.0;

        (left_db, right_db)
    }

    /// Get interpolated volume at a specific time (in seconds)
    /// Uses linear interpolation between automation points
    /// Returns static `volume_db` if no automation exists
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
            let mid = usize::midpoint(low, high);
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
    /// Converts the dB value from `get_volume_at()` to linear gain
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
            a.time_seconds
                .partial_cmp(&b.time_seconds)
                .unwrap_or(std::cmp::Ordering::Equal)
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
    tracks: Vec<Arc<parking_lot::Mutex<Track>>>,
    /// Next track ID
    next_id: TrackId,
    /// Master track ID (always exists)
    master_track_id: TrackId,
}

impl Default for TrackManager {
    fn default() -> Self {
        Self::new()
    }
}

impl TrackManager {
    /// Create a new track manager with a master track
    pub fn new() -> Self {
        let master_track = Arc::new(parking_lot::Mutex::new(Track::new(
            0,
            TrackType::Master,
            "Master".to_string(),
        )));

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
        let track = Arc::new(parking_lot::Mutex::new(Track::new(id, track_type, name)));

        self.tracks.push(track);

        id
    }

    /// Insert a track under a caller-chosen id (used when restoring a saved
    /// project so tracks keep the ids the UI's layout data is filed under).
    ///
    /// Rejects id 0 (master) and ids already in use. Bumps the id counter past
    /// `id` so later `create_track` calls never collide with a restored id.
    pub fn insert_track_with_id(
        &mut self,
        id: TrackId,
        track_type: TrackType,
        name: String,
    ) -> Result<TrackId, String> {
        if id == self.master_track_id {
            return Err("track id 0 is reserved for the master track".to_string());
        }
        if self.tracks.iter().any(|t| t.lock().id == id) {
            return Err(format!("track id {id} is already in use"));
        }

        self.tracks
            .push(Arc::new(parking_lot::Mutex::new(Track::new(
                id, track_type, name,
            ))));
        self.next_id = self.next_id.max(id + 1);
        Ok(id)
    }

    /// Restart track numbering from 1. Only call when no non-master tracks
    /// exist (New Project / Close Project), so the first new track in every
    /// project gets the same id.
    pub fn reset_ids(&mut self) {
        debug_assert!(
            self.tracks
                .iter()
                .all(|t| t.lock().id == self.master_track_id),
            "reset_ids called while non-master tracks exist"
        );
        self.next_id = 1;
    }

    /// Get a track by ID
    pub fn get_track(&self, id: TrackId) -> Option<Arc<parking_lot::Mutex<Track>>> {
        self.tracks.iter().find(|t| t.lock().id == id).cloned()
    }

    /// Get master track
    pub fn get_master_track(&self) -> Arc<parking_lot::Mutex<Track>> {
        self.get_track(self.master_track_id).unwrap()
    }

    /// Get all tracks
    pub fn get_all_tracks(&self) -> Vec<Arc<parking_lot::Mutex<Track>>> {
        self.tracks.clone()
    }

    /// Remove a track (cannot remove master)
    pub fn remove_track(&mut self, id: TrackId) -> bool {
        if id == self.master_track_id {
            return false;
        }

        if let Some(pos) = self.tracks.iter().position(|t| t.lock().id == id) {
            self.tracks.remove(pos);
            true
        } else {
            false
        }
    }

    /// Check if any tracks are soloed
    pub fn has_solo(&self) -> bool {
        self.tracks.iter().any(|t| t.lock().solo)
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
        assert!(track.volume_db.abs() < f32::EPSILON);
        assert!(track.pan.abs() < f32::EPSILON);
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
        assert!(track.get_gain().abs() < f32::EPSILON);
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
    fn master_pan_is_a_balance_with_unity_at_centre() {
        let mut master = Track::new(0, TrackType::Master, "Master".to_string());
        master.pan = 0.0;
        assert_eq!(master.get_pan_gains(), (1.0, 1.0));
        master.pan = 0.5;
        assert_eq!(master.get_pan_gains(), (0.5, 1.0));
        master.pan = -1.0;
        assert_eq!(master.get_pan_gains(), (1.0, 0.0));
    }

    fn make_timeline_clip(start_time: f64, offset: f64, duration_seconds: f64) -> TimelineClip {
        let frames = (duration_seconds * 48000.0) as usize;
        let clip = AudioClip {
            samples: vec![0.0; frames],
            channels: 1,
            sample_rate: 48000,
            duration_seconds,
            file_path: String::new(),
        };
        TimelineClip {
            id: 1,
            clip: Arc::new(clip),
            start_time,
            offset,
            duration: None,
            gain_db: 0.0,
            warp_enabled: false,
            stretch_factor: 1.0,
            warp_mode: 0,
            stretched_cache: None,
            cached_stretch_factor: 0.0,
            cached_transpose_cents: 0,
            transpose_semitones: 0,
            transpose_cents: 0,
            reversed: false,
        }
    }

    #[test]
    fn test_progress_in_clip_forward() {
        let clip = make_timeline_clip(10.0, 0.5, 4.0);
        // 1.5s into the clip on the timeline (the 0.5s trim isn't included)
        assert!((clip.progress_in_clip(11.5, 4.0) - 1.5).abs() < 1e-9);
    }

    #[test]
    fn test_progress_in_clip_reversed_reflects_window() {
        let mut clip = make_timeline_clip(10.0, 0.5, 4.0);
        clip.reversed = true;
        let frame = 1.0 / 48_000.0;
        // At clip start, reversed playback reads the window's last frame
        assert!((clip.progress_in_clip(10.0, 4.0) - (4.0 - frame)).abs() < 1e-9);
        // 1.5s in → mirrored to 2.5s progress (less a frame)
        assert!((clip.progress_in_clip(11.5, 4.0) - (2.5 - frame)).abs() < 1e-9);
        // On the clip's last frame, reversed playback reads the window start
        assert!((clip.progress_in_clip(14.0 - frame, 4.0) - 0.0).abs() < 1e-9);
    }

    #[test]
    fn test_progress_in_clip_reversed_clamps_past_end() {
        let mut clip = make_timeline_clip(0.0, 0.0, 2.0);
        clip.reversed = true;
        // Past the clip window, progress reflection clamps at 0 (no negative reads)
        assert!((clip.progress_in_clip(5.0, 2.0) - 0.0).abs() < 1e-9);
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

    #[test]
    fn test_insert_track_with_id_keeps_ids_and_bumps_counter() {
        let mut manager = TrackManager::new();
        assert_eq!(
            manager.insert_track_with_id(7, TrackType::Audio, "A".to_string()),
            Ok(7)
        );
        assert_eq!(
            manager.insert_track_with_id(3, TrackType::Midi, "B".to_string()),
            Ok(3)
        );
        assert!(manager.get_track(7).is_some());
        assert!(manager.get_track(3).is_some());

        // Duplicates and the master id are rejected
        assert!(manager
            .insert_track_with_id(7, TrackType::Audio, "dup".to_string())
            .is_err());
        assert!(manager
            .insert_track_with_id(0, TrackType::Audio, "master".to_string())
            .is_err());

        // New tracks land above every restored id
        let next = manager.create_track(TrackType::Audio, "C".to_string());
        assert_eq!(next, 8);
    }

    #[test]
    fn test_reset_ids_restarts_numbering() {
        let mut manager = TrackManager::new();
        let id = manager.create_track(TrackType::Audio, "A".to_string());
        assert_eq!(id, 1);
        assert!(manager.remove_track(id));
        manager.reset_ids();
        assert_eq!(manager.create_track(TrackType::Audio, "B".to_string()), 1);
    }
}
