/// Audio graph and playback engine
///
/// Split into focused modules:
/// - `renderer` — Real-time audio render callback (audio thread)
/// - `offline` — Offline rendering for export/bounce
/// - `project` — Project serialization (save/load)
/// - `device` — Audio device selection, buffer size, latency
mod renderer;
mod offline;
mod project;
mod device;

use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::midi::MidiClip;
use crate::synth::TrackSynthManager;
use crate::track::{AutomationPoint, ClipId, TimelineClip, TimelineMidiClip, TrackId, TrackManager};  // Import from track module
use crate::effects::{EffectManager, Limiter};  // Import from effects module
use std::sync::Arc;
use parking_lot::Mutex;
use std::sync::atomic::{AtomicU8, AtomicU64, Ordering};

// Native-only imports
#[cfg(not(target_arch = "wasm32"))]
use crate::audio_input::AudioInputManager;
#[cfg(not(target_arch = "wasm32"))]
use crate::recorder::Recorder;
#[cfg(not(target_arch = "wasm32"))]
use crate::midi_input::MidiInputManager;
#[cfg(not(target_arch = "wasm32"))]
use crate::midi_recorder::MidiRecorder;
#[cfg(not(target_arch = "wasm32"))]
use cpal::traits::StreamTrait;

/// Transport state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportState {
    Stopped = 0,
    Playing = 1,
    Paused = 2,
}

impl TransportState {
    /// Convert from atomic u8 value
    fn from_u8(value: u8) -> Self {
        match value {
            1 => TransportState::Playing,
            2 => TransportState::Paused,
            _ => TransportState::Stopped,
        }
    }
}

/// Buffer size presets for audio latency control
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BufferSizePreset {
    /// 64 samples = ~1.3ms @ 48kHz (lowest latency, highest CPU)
    Lowest = 64,
    /// 128 samples = ~2.7ms @ 48kHz (low latency)
    Low = 128,
    /// 256 samples = ~5.3ms @ 48kHz (balanced)
    Balanced = 256,
    /// 512 samples = ~10.7ms @ 48kHz (safe)
    Safe = 512,
    /// 1024 samples = ~21.3ms @ 48kHz (highest stability)
    HighStability = 1024,
}

impl BufferSizePreset {
    /// Get latency in milliseconds at 48kHz
    pub fn latency_ms(&self) -> f32 {
        (*self as u32) as f32 / TARGET_SAMPLE_RATE as f32 * 1000.0
    }

    /// Get buffer size in samples
    pub fn samples(&self) -> u32 {
        *self as u32
    }

    /// Create from sample count (rounds to nearest preset)
    pub fn from_samples(samples: u32) -> Self {
        match samples {
            0..=96 => BufferSizePreset::Lowest,
            97..=192 => BufferSizePreset::Low,
            193..=384 => BufferSizePreset::Balanced,
            385..=768 => BufferSizePreset::Safe,
            _ => BufferSizePreset::HighStability,
        }
    }
}

/// Interpolate volume gain from automation curve at a specific time
/// Uses binary search and linear interpolation for efficient per-frame lookup
pub(crate) fn interpolate_automation_gain(automation: &[AutomationPoint], time_seconds: f64) -> f32 {
    if automation.is_empty() {
        return 1.0; // Unity gain fallback
    }

    // Before first point - use first point's value
    if time_seconds <= automation[0].time_seconds {
        let db = automation[0].value_db;
        return if db <= -96.0 { 0.0 } else { 10_f32.powf(db / 20.0) };
    }

    // After last point - use last point's value
    let last_idx = automation.len() - 1;
    if time_seconds >= automation[last_idx].time_seconds {
        let db = automation[last_idx].value_db;
        return if db <= -96.0 { 0.0 } else { 10_f32.powf(db / 20.0) };
    }

    // Binary search for surrounding points
    let mut low = 0usize;
    let mut high = automation.len() - 1;

    while low < high - 1 {
        let mid = usize::midpoint(low, high);
        if automation[mid].time_seconds <= time_seconds {
            low = mid;
        } else {
            high = mid;
        }
    }

    // Linear interpolation between automation[low] and automation[high]
    let p1 = &automation[low];
    let p2 = &automation[high];
    let t = (time_seconds - p1.time_seconds) / (p2.time_seconds - p1.time_seconds);
    let db = p1.value_db + (p2.value_db - p1.value_db) * t as f32;

    if db <= -96.0 { 0.0 } else { 10_f32.powf(db / 20.0) }
}

/// The main audio graph that manages playback
pub struct AudioGraph {
    /// All audio clips on the timeline (legacy - will migrate to tracks)
    pub(crate) clips: Arc<Mutex<Vec<TimelineClip>>>,
    /// All MIDI clips on the timeline (legacy - will migrate to tracks)
    pub(crate) midi_clips: Arc<Mutex<Vec<TimelineMidiClip>>>,
    /// Current playhead position in samples
    pub playhead_samples: Arc<AtomicU64>,
    /// Position when Play was pressed (for Stop button to return to)
    pub(crate) play_start_position_samples: Arc<AtomicU64>,
    /// Position when recording actually started (after count-in, for Stop button during recording)
    pub(crate) record_start_position_samples: Arc<AtomicU64>,
    /// Transport state (atomic: 0=Stopped, 1=Playing, 2=Paused)
    pub(crate) state: Arc<AtomicU8>,
    /// Audio output stream (kept alive) - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) stream: Option<cpal::Stream>,
    /// Next clip ID
    pub(crate) next_clip_id: Arc<Mutex<ClipId>>,
    /// Audio input manager - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub input_manager: Arc<Mutex<AudioInputManager>>,
    /// Audio recorder - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub recorder: Arc<Recorder>,
    /// MIDI input manager - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub midi_input_manager: Arc<Mutex<MidiInputManager>>,
    /// MIDI recorder - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub midi_recorder: Arc<Mutex<MidiRecorder>>,
    // --- M4: Mixing & Effects ---
    /// Track manager (handles all tracks)
    pub track_manager: Arc<Mutex<TrackManager>>,
    /// Effect manager (handles all effect instances)
    pub effect_manager: Arc<Mutex<EffectManager>>,
    /// Master limiter (prevents clipping)
    pub master_limiter: Arc<Mutex<Limiter>>,

    // --- M6: Per-Track Synthesizers ---
    /// Per-track synthesizer manager
    pub track_synth_manager: Arc<Mutex<TrackSynthManager>>,

    // --- Latency Control ---
    /// Preferred buffer size for audio output
    pub(crate) preferred_buffer_size: Arc<Mutex<BufferSizePreset>>,
    /// Actual buffer size being used (set by audio callback)
    pub(crate) actual_buffer_size: Arc<std::sync::atomic::AtomicU32>,
    /// Hardware input latency in milliseconds (measured from device, not estimated)
    pub hardware_input_latency_ms: Arc<Mutex<f32>>,
    /// Hardware output latency in milliseconds (measured from device, not estimated)
    pub hardware_output_latency_ms: Arc<Mutex<f32>>,

    // --- Device Selection ---
    /// Selected output device name (None = use system default)
    pub(crate) selected_output_device: Arc<Mutex<Option<String>>>,

    // --- Latency Testing --- (native only)
    #[cfg(not(target_arch = "wasm32"))]
    pub latency_test: Arc<crate::latency_test::LatencyTest>,
}

// SAFETY: AudioGraph is stored in a Mutex<Option<AudioGraph>> in the API layer.
// cpal::Stream is !Send because it contains platform-specific thread handles,
// but we only create and drop it on the main thread while holding the API mutex.
// The audio callback runs on a separate OS thread but communicates only through
// Arc<AtomicU64>/Arc<Mutex<_>> fields that are independently Send+Sync.
// The Stream itself is never moved between threads after construction.
unsafe impl Send for AudioGraph {}

impl AudioGraph {
    /// Create a new audio graph (native platforms)
    #[cfg(not(target_arch = "wasm32"))]
    pub fn new() -> anyhow::Result<Self> {
        let mut input_manager = AudioInputManager::new()?;
        // Enumerate devices on creation
        let _ = input_manager.enumerate_devices();

        // Create MIDI input manager
        let midi_input_manager = MidiInputManager::new()?;

        // Create playhead for MIDI recorder
        let playhead_samples = Arc::new(AtomicU64::new(0));
        let midi_recorder = MidiRecorder::new(playhead_samples.clone());

        // Create M4 managers
        let track_manager = TrackManager::new(); // Creates with master track
        let effect_manager = EffectManager::new();
        let master_limiter = Limiter::new();

        let mut graph = Self {
            clips: Arc::new(Mutex::new(Vec::new())),
            midi_clips: Arc::new(Mutex::new(Vec::new())),
            playhead_samples,
            play_start_position_samples: Arc::new(AtomicU64::new(0)),
            record_start_position_samples: Arc::new(AtomicU64::new(0)),
            state: Arc::new(AtomicU8::new(TransportState::Stopped as u8)),
            stream: None,
            next_clip_id: Arc::new(Mutex::new(0)),
            input_manager: Arc::new(Mutex::new(input_manager)),
            recorder: Arc::new(Recorder::new()),
            midi_input_manager: Arc::new(Mutex::new(midi_input_manager)),
            midi_recorder: Arc::new(Mutex::new(midi_recorder)),
            track_manager: Arc::new(Mutex::new(track_manager)),
            effect_manager: Arc::new(Mutex::new(effect_manager)),
            master_limiter: Arc::new(Mutex::new(master_limiter)),
            track_synth_manager: Arc::new(Mutex::new(TrackSynthManager::new(TARGET_SAMPLE_RATE as f32))),
            preferred_buffer_size: Arc::new(Mutex::new(BufferSizePreset::Balanced)),
            actual_buffer_size: Arc::new(std::sync::atomic::AtomicU32::new(0)),
            hardware_input_latency_ms: Arc::new(Mutex::new(0.0)),
            hardware_output_latency_ms: Arc::new(Mutex::new(0.0)),
            selected_output_device: Arc::new(Mutex::new(None)),
            latency_test: Arc::new(crate::latency_test::LatencyTest::new(TARGET_SAMPLE_RATE)),
        };

        // Create audio stream immediately (prevents deadlock on first play)
        eprintln!("🔊 [AudioGraph] Creating audio stream during initialization...");
        let stream = graph.create_audio_stream()?;
        // Keep stream running even when stopped - needed for real-time MIDI preview
        // The callback checks transport state to decide whether to advance playhead
        stream.play()?;
        graph.stream = Some(stream);
        eprintln!("✅ [AudioGraph] Audio stream created and running (for MIDI preview)");

        // Query hardware latency from CoreAudio device
        if let Err(e) = graph.query_coreaudio_latency() {
            eprintln!("⚠️ [AudioGraph] Failed to query hardware latency: {e}");
        }

        Ok(graph)
    }

    /// Create a new audio graph (web/WASM platforms)
    #[cfg(target_arch = "wasm32")]
    pub fn new() -> anyhow::Result<Self> {
        // Create playhead
        let playhead_samples = Arc::new(AtomicU64::new(0));

        // Create M4 managers
        let track_manager = TrackManager::new();
        let effect_manager = EffectManager::new();
        let master_limiter = Limiter::new();

        let graph = Self {
            clips: Arc::new(Mutex::new(Vec::new())),
            midi_clips: Arc::new(Mutex::new(Vec::new())),
            playhead_samples,
            play_start_position_samples: Arc::new(AtomicU64::new(0)),
            record_start_position_samples: Arc::new(AtomicU64::new(0)),
            state: Arc::new(AtomicU8::new(TransportState::Stopped as u8)),
            next_clip_id: Arc::new(Mutex::new(0)),
            track_manager: Arc::new(Mutex::new(track_manager)),
            effect_manager: Arc::new(Mutex::new(effect_manager)),
            master_limiter: Arc::new(Mutex::new(master_limiter)),
            track_synth_manager: Arc::new(Mutex::new(TrackSynthManager::new(TARGET_SAMPLE_RATE as f32))),
            preferred_buffer_size: Arc::new(Mutex::new(BufferSizePreset::Balanced)),
            actual_buffer_size: Arc::new(std::sync::atomic::AtomicU32::new(0)),
            hardware_input_latency_ms: Arc::new(Mutex::new(0.0)),
            hardware_output_latency_ms: Arc::new(Mutex::new(0.0)),
            selected_output_device: Arc::new(Mutex::new(None)),
        };

        Ok(graph)
    }

    /// Add a clip to the timeline
    pub fn add_clip(&self, clip: Arc<AudioClip>, start_time: f64) -> ClipId {
        let mut clips = self.clips.lock();
        let id = {
            let mut next_id = self.next_clip_id.lock();
            let id = *next_id;
            *next_id += 1;
            id
        };

        clips.push(TimelineClip {
            id,
            clip,
            start_time,
            offset: 0.0,
            duration: None,
            gain_db: 0.0,
            warp_enabled: false,
            stretch_factor: 1.0,
            warp_mode: 0,
            stretched_cache: None,
            cached_stretch_factor: 0.0,
            transpose_semitones: 0,
            transpose_cents: 0,
            volume_automation: Vec::new(),
            pan_automation: Vec::new(),
        });

        id
    }

    /// Add a MIDI clip to the timeline
    pub fn add_midi_clip(&self, clip: Arc<MidiClip>, start_time: f64) -> ClipId {
        let mut midi_clips = self.midi_clips.lock();
        let id = {
            let mut next_id = self.next_clip_id.lock();
            let id = *next_id;
            *next_id += 1;
            id
        };

        midi_clips.push(TimelineMidiClip {
            id,
            clip,
            start_time,
            track_id: None, // Will be set when added to a track
            volume_automation: Vec::new(),
            pan_automation: Vec::new(),
        });

        id
    }

    /// Add an audio clip to a specific track (M5.5)
    pub fn add_clip_to_track(&self, track_id: TrackId, clip: Arc<AudioClip>, start_time: f64) -> Option<ClipId> {
        self.add_clip_to_track_with_params(track_id, clip, start_time, 0.0, None)
    }

    /// Add an audio clip to a specific track with offset and duration parameters
    /// Used when restoring clips from a saved project
    pub fn add_clip_to_track_with_params(
        &self,
        track_id: TrackId,
        clip: Arc<AudioClip>,
        start_time: f64,
        offset: f64,
        duration: Option<f64>,
    ) -> Option<ClipId> {
        let id = {
            let mut next_id = self.next_clip_id.lock();
            let id = *next_id;
            *next_id += 1;
            id
        };

        let track_manager = self.track_manager.lock();
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock();
            track.audio_clips.push(TimelineClip {
                id,
                clip,
                start_time,
                offset,
                duration,
                gain_db: 0.0,
                warp_enabled: false,
                stretch_factor: 1.0,
                warp_mode: 0,
                stretched_cache: None,
                cached_stretch_factor: 0.0,
                transpose_semitones: 0,
                transpose_cents: 0,
                volume_automation: Vec::new(),
                pan_automation: Vec::new(),
            });
            Some(id)
        } else {
            None
        }
    }

    /// Re-add an audio clip to a track with a specific clip ID.
    /// Used for undo/redo to preserve clip ID consistency.
    pub fn add_clip_to_track_with_id(
        &self,
        track_id: TrackId,
        clip_id: ClipId,
        clip: Arc<AudioClip>,
        start_time: f64,
        offset: f64,
        duration: Option<f64>,
    ) -> bool {
        let track_manager = self.track_manager.lock();
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock();
            track.audio_clips.push(TimelineClip {
                id: clip_id,
                clip,
                start_time,
                offset,
                duration,
                gain_db: 0.0,
                warp_enabled: false,
                stretch_factor: 1.0,
                warp_mode: 0,
                stretched_cache: None,
                cached_stretch_factor: 0.0,
                transpose_semitones: 0,
                transpose_cents: 0,
                volume_automation: Vec::new(),
                pan_automation: Vec::new(),
            });
            true
        } else {
            false
        }
    }

    /// Add a MIDI clip to a specific track (M5.5)
    /// Uses the provided `clip_id` to ensure consistency with global storage
    pub fn add_midi_clip_to_track(&self, track_id: TrackId, clip: Arc<MidiClip>, start_time: f64, clip_id: ClipId) -> Option<ClipId> {
        let track_manager = self.track_manager.lock();
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock();
            track.midi_clips.push(TimelineMidiClip {
                id: clip_id,  // Use the same ID as in global storage
                clip,
                start_time,
                track_id: Some(track_id),
                volume_automation: Vec::new(),
                pan_automation: Vec::new(),
            });
            Some(clip_id)
        } else {
            None
        }
    }

    /// Sync a MIDI clip from global storage to the track
    /// This is needed after modifying a clip because `Arc::make_mut` creates a new copy
    pub fn sync_midi_clip_to_track(&self, clip_id: ClipId) {
        // Get the updated clip from global storage
        let updated_clip = {
            let midi_clips = self.midi_clips.lock();
            midi_clips.iter()
                .find(|c| c.id == clip_id)
                .map(|c| (c.clip.clone(), c.track_id, c.clip.events.len()))
        };

        if let Some((clip_arc, Some(track_id), _event_count)) = updated_clip {
            // Update the track's copy
            let track_manager = self.track_manager.lock();
            if let Some(track_arc) = track_manager.get_track(track_id) {
                let mut track = track_arc.lock();
                // Find and update the MIDI clip in the track
                if let Some(timeline_clip) = track.midi_clips.iter_mut().find(|c| c.id == clip_id) {
                    timeline_clip.clip = clip_arc;
                }
            }
        }
    }

    /// Remove a clip from the timeline (audio or MIDI)
    pub fn remove_clip(&self, clip_id: ClipId) -> bool {
        // Try to remove from audio clips
        {
            let mut clips = self.clips.lock();
            if let Some(pos) = clips.iter().position(|c| c.id == clip_id) {
                clips.remove(pos);
                return true;
            }
        }

        // Try to remove from MIDI clips
        {
            let mut midi_clips = self.midi_clips.lock();
            if let Some(pos) = midi_clips.iter().position(|c| c.id == clip_id) {
                midi_clips.remove(pos);
                return true;
            }
        }

        false
    }

    /// Remove all MIDI clips belonging to a specific track
    pub fn remove_midi_clips_for_track(&self, track_id: TrackId) -> usize {
        let mut midi_clips = self.midi_clips.lock();
        let initial_count = midi_clips.len();
        midi_clips.retain(|clip| clip.track_id != Some(track_id));

        initial_count - midi_clips.len()
    }

    /// Get the current playhead position in seconds
    pub fn get_playhead_position(&self) -> f64 {
        let samples = self.playhead_samples.load(Ordering::SeqCst);
        // Simple conversion: samples to seconds (no tempo scaling)
        // The playhead tracks real time - tempo affects note/beat positions, not time itself
        samples as f64 / f64::from(TARGET_SAMPLE_RATE)
    }

    /// Get the current playhead position in samples
    pub fn get_playhead_samples(&self) -> u64 {
        self.playhead_samples.load(Ordering::SeqCst)
    }

    /// Set the playhead position in samples (used for tempo change adjustment)
    pub fn set_playhead_samples(&self, samples: u64) {
        self.playhead_samples.store(samples, Ordering::SeqCst);
    }

    /// Get the position when Play was pressed (in seconds)
    pub fn get_play_start_position(&self) -> f64 {
        let samples = self.play_start_position_samples.load(Ordering::SeqCst);
        samples as f64 / f64::from(TARGET_SAMPLE_RATE)
    }

    /// Set the position when Play was pressed (in seconds)
    pub fn set_play_start_position(&self, position_seconds: f64) {
        let samples = (position_seconds * f64::from(TARGET_SAMPLE_RATE)) as u64;
        self.play_start_position_samples.store(samples, Ordering::SeqCst);
    }

    /// Get the position when recording started (after count-in, in seconds)
    pub fn get_record_start_position(&self) -> f64 {
        let samples = self.record_start_position_samples.load(Ordering::SeqCst);
        samples as f64 / f64::from(TARGET_SAMPLE_RATE)
    }

    /// Set the position when recording started (after count-in, in seconds)
    pub fn set_record_start_position(&self, position_seconds: f64) {
        let samples = (position_seconds * f64::from(TARGET_SAMPLE_RATE)) as u64;
        self.record_start_position_samples.store(samples, Ordering::SeqCst);
    }

    /// Seek to a specific position in seconds
    pub fn seek(&self, position_seconds: f64) {
        // Silence all synthesizers to prevent stuck notes/drone when loop wraps
        // This ensures notes that were playing at the old position don't continue
        // droning after we jump to a new position
        { let mut synth_manager = self.track_synth_manager.lock();
            synth_manager.all_notes_off_all_tracks();
        }

        // Simple conversion: seconds to samples (no tempo scaling)
        let samples = (position_seconds * f64::from(TARGET_SAMPLE_RATE)) as u64;
        self.playhead_samples.store(samples, Ordering::SeqCst);
        // Sync metronome to the same position so beats stay on beat after seek/loop (native only)
        #[cfg(not(target_arch = "wasm32"))]
        self.recorder.seek_metronome(samples);
    }

    /// Get current transport state
    pub fn get_state(&self) -> TransportState {
        TransportState::from_u8(self.state.load(Ordering::SeqCst))
    }

    /// Start playback (lock-free state change)
    pub fn play(&mut self) -> anyhow::Result<()> {
        // Use atomic compare-exchange to avoid starting if already playing
        let current = self.state.load(Ordering::SeqCst);
        if current == TransportState::Playing as u8 {
            return Ok(()); // Already playing
        }

        // Save current playhead position as play start position
        let current_pos = self.playhead_samples.load(Ordering::SeqCst);
        self.play_start_position_samples.store(current_pos, Ordering::SeqCst);
        eprintln!("▶️  [AudioGraph] play() - saving play_start_position: {} samples ({:.3}s)",
            current_pos, current_pos as f64 / f64::from(TARGET_SAMPLE_RATE));

        self.state.store(TransportState::Playing as u8, Ordering::SeqCst);

        // Stream is always running (for MIDI preview) - no need to start/stop it
        // The callback checks transport state to decide what to process

        Ok(())
    }

    /// Pause playback (keeps position) - lock-free state change
    pub fn pause(&mut self) -> anyhow::Result<()> {
        eprintln!("⏸️  [AudioGraph] pause() called");
        self.state.store(TransportState::Paused as u8, Ordering::SeqCst);
        // Stream keeps running for MIDI preview

        // Silence all synthesizers to prevent stuck notes/drone
        { let mut synth_manager = self.track_synth_manager.lock();
            synth_manager.all_notes_off_all_tracks();
            eprintln!("   All synth notes silenced");
        }

        // Silence all VST3 instruments to prevent stuck notes/drone
        { let track_mgr = self.track_manager.lock();
            { let effect_mgr = self.effect_manager.lock();
                for track_arc in track_mgr.get_all_tracks() {
                    { let track = track_arc.lock();
                        for effect_id in &track.fx_chain {
                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                { let mut effect = effect_arc.lock();
                                    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                    if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                        // Send note-off for all 128 MIDI notes
                                        for note in 0..128i32 {
                                            let _ = vst3.process_midi_event(1, 0, note, 0, 0);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                eprintln!("   All VST3 notes silenced");
            }
        }

        Ok(())
    }

    /// Stop playback - lock-free state change
    /// Note: Playhead position is managed by `transportSeek()` from Dart layer
    pub fn stop(&mut self) -> anyhow::Result<()> {
        eprintln!("⏹️  [AudioGraph] stop() called - silencing notes and stopping metronome");

        self.state.store(TransportState::Stopped as u8, Ordering::SeqCst);
        // Stream keeps running for MIDI preview

        // Silence all synthesizers to prevent stuck notes/drone
        { let mut synth_manager = self.track_synth_manager.lock();
            synth_manager.all_notes_off_all_tracks();
            eprintln!("   All synth notes silenced");
        }

        // Silence all VST3 instruments to prevent stuck notes/drone
        { let track_mgr = self.track_manager.lock();
            { let effect_mgr = self.effect_manager.lock();
                for track_arc in track_mgr.get_all_tracks() {
                    { let track = track_arc.lock();
                        for effect_id in &track.fx_chain {
                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                { let mut effect = effect_arc.lock();
                                    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                    if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                        // Send note-off for all 128 MIDI notes
                                        for note in 0..128i32 {
                                            let _ = vst3.process_midi_event(1, 0, note, 0, 0);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                eprintln!("   All VST3 notes silenced");
            }
        }

        // Note: Playhead position is NOT reset here - it's managed by transportSeek()
        // from the Dart layer, which allows flexible stop behavior (return to bar 1,
        // playStartPosition, or recordStartPosition depending on context)

        // Reset metronome beat position to match current playhead (native only)
        #[cfg(not(target_arch = "wasm32"))]
        self.recorder.reset_metronome();

        Ok(())
    }

    /// Get number of audio clips
    pub fn clip_count(&self) -> usize {
        self.clips.lock().len()
    }

    /// Get number of MIDI clips
    pub fn midi_clip_count(&self) -> usize {
        self.midi_clips.lock().len()
    }

    /// Get access to audio clips (for editing in API)
    pub fn get_clips(&self) -> &Arc<Mutex<Vec<TimelineClip>>> {
        &self.clips
    }

    /// Get access to MIDI clips (for editing in API)
    pub fn get_midi_clips(&self) -> &Arc<Mutex<Vec<TimelineMidiClip>>> {
        &self.midi_clips
    }

    /// Get total number of clips (audio + MIDI)
    pub fn total_clip_count(&self) -> usize {
        self.clip_count() + self.midi_clip_count()
    }

    /// Get current sample rate
    pub fn get_sample_rate() -> u32 {
        TARGET_SAMPLE_RATE
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio_file::AudioClip;

    fn create_test_clip(duration: f64) -> AudioClip {
        let frames = (duration * f64::from(TARGET_SAMPLE_RATE)) as usize;
        let samples = vec![0.1; frames * 2]; // Stereo
        AudioClip {
            samples,
            channels: 2,
            sample_rate: TARGET_SAMPLE_RATE,
            duration_seconds: duration,
            file_path: "test.wav".to_string(),
        }
    }

    #[test]
    fn test_audio_graph_creation() {
        let graph = AudioGraph::new();
        assert!(graph.is_ok());
    }

    #[test]
    fn test_add_clip() {
        let graph = AudioGraph::new().unwrap();
        let clip = Arc::new(create_test_clip(1.0));
        let id = graph.add_clip(clip, 0.0);
        assert_eq!(graph.clip_count(), 1);
        assert_eq!(id, 0);
    }

    #[test]
    fn test_remove_clip() {
        let graph = AudioGraph::new().unwrap();
        let clip = Arc::new(create_test_clip(1.0));
        let id = graph.add_clip(clip, 0.0);
        assert_eq!(graph.clip_count(), 1);

        let removed = graph.remove_clip(id);
        assert!(removed);
        assert_eq!(graph.clip_count(), 0);
    }

    #[test]
    fn test_playhead_position() {
        let graph = AudioGraph::new().unwrap();
        assert_eq!(graph.get_playhead_position(), 0.0);

        graph.seek(5.5);
        assert!((graph.get_playhead_position() - 5.5).abs() < 0.001);
    }

    #[test]
    fn test_transport_state() {
        let mut graph = AudioGraph::new().unwrap();
        assert_eq!(graph.get_state(), TransportState::Stopped);

        // Note: We can't test play() without audio device in CI
        // Just test state management
        graph.stop().unwrap();
        assert_eq!(graph.get_state(), TransportState::Stopped);
    }
}
