/// Audio graph and playback engine
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::audio_input::AudioInputManager;
use crate::recorder::Recorder;
use crate::midi::MidiClip;
use crate::midi_input::MidiInputManager;
use crate::midi_recorder::MidiRecorder;
use crate::synth::TrackSynthManager;
use crate::track::{ClipId, TimelineClip, TimelineMidiClip, TrackId, TrackManager};  // Import from track module
use crate::effects::{Effect, EffectManager, Limiter};  // Import from effects module
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering};

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

/// The main audio graph that manages playback
pub struct AudioGraph {
    /// All audio clips on the timeline (legacy - will migrate to tracks)
    clips: Arc<Mutex<Vec<TimelineClip>>>,
    /// All MIDI clips on the timeline (legacy - will migrate to tracks)
    midi_clips: Arc<Mutex<Vec<TimelineMidiClip>>>,
    /// Current playhead position in samples
    playhead_samples: Arc<AtomicU64>,
    /// Transport state (atomic: 0=Stopped, 1=Playing, 2=Paused)
    state: Arc<AtomicU8>,
    /// Audio output stream (kept alive)
    stream: Option<cpal::Stream>,
    /// Next clip ID
    next_clip_id: Arc<Mutex<ClipId>>,
    /// Audio input manager
    pub input_manager: Arc<Mutex<AudioInputManager>>,
    /// Audio recorder
    pub recorder: Arc<Recorder>,
    /// MIDI input manager
    pub midi_input_manager: Arc<Mutex<MidiInputManager>>,
    /// MIDI recorder
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
    preferred_buffer_size: Arc<Mutex<BufferSizePreset>>,
    /// Actual buffer size being used (set by audio callback)
    actual_buffer_size: Arc<std::sync::atomic::AtomicU32>,
}

// SAFETY: AudioGraph is only accessed through a Mutex in the API layer,
// ensuring thread-safe access even though cpal::Stream is not Send.
// The stream is created and used only within the context of the Mutex lock.
unsafe impl Send for AudioGraph {}

impl AudioGraph {
    /// Create a new audio graph
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
        };

        // Create audio stream immediately (prevents deadlock on first play)
        eprintln!("🔊 [AudioGraph] Creating audio stream during initialization...");
        let stream = graph.create_audio_stream()?;
        // Keep stream running even when stopped - needed for real-time MIDI preview
        // The callback checks transport state to decide whether to advance playhead
        stream.play()?;
        graph.stream = Some(stream);
        eprintln!("✅ [AudioGraph] Audio stream created and running (for MIDI preview)");

        Ok(graph)
    }

    /// Add a clip to the timeline
    pub fn add_clip(&self, clip: Arc<AudioClip>, start_time: f64) -> ClipId {
        let mut clips = self.clips.lock().expect("mutex poisoned");
        let id = {
            let mut next_id = self.next_clip_id.lock().expect("mutex poisoned");
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
        });

        id
    }

    /// Add a MIDI clip to the timeline
    pub fn add_midi_clip(&self, clip: Arc<MidiClip>, start_time: f64) -> ClipId {
        let mut midi_clips = self.midi_clips.lock().expect("mutex poisoned");
        let id = {
            let mut next_id = self.next_clip_id.lock().expect("mutex poisoned");
            let id = *next_id;
            *next_id += 1;
            id
        };

        midi_clips.push(TimelineMidiClip {
            id,
            clip,
            start_time,
            track_id: None, // Will be set when added to a track
        });

        id
    }

    /// Add an audio clip to a specific track (M5.5)
    pub fn add_clip_to_track(&self, track_id: TrackId, clip: Arc<AudioClip>, start_time: f64) -> Option<ClipId> {
        let id = {
            let mut next_id = self.next_clip_id.lock().expect("mutex poisoned");
            let id = *next_id;
            *next_id += 1;
            id
        };

        let track_manager = self.track_manager.lock().expect("mutex poisoned");
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock().expect("mutex poisoned");
            track.audio_clips.push(TimelineClip {
                id,
                clip,
                start_time,
                offset: 0.0,
                duration: None,
            });
            Some(id)
        } else {
            None
        }
    }

    /// Add a MIDI clip to a specific track (M5.5)
    /// Uses the provided clip_id to ensure consistency with global storage
    pub fn add_midi_clip_to_track(&self, track_id: TrackId, clip: Arc<MidiClip>, start_time: f64, clip_id: ClipId) -> Option<ClipId> {
        let track_manager = self.track_manager.lock().expect("mutex poisoned");
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock().expect("mutex poisoned");
            track.midi_clips.push(TimelineMidiClip {
                id: clip_id,  // Use the same ID as in global storage
                clip,
                start_time,
                track_id: Some(track_id),
            });
            Some(clip_id)
        } else {
            None
        }
    }

    /// Sync a MIDI clip from global storage to the track
    /// This is needed after modifying a clip because Arc::make_mut creates a new copy
    pub fn sync_midi_clip_to_track(&self, clip_id: ClipId) {
        // Get the updated clip from global storage
        let updated_clip = {
            let midi_clips = self.midi_clips.lock().expect("mutex poisoned");
            midi_clips.iter()
                .find(|c| c.id == clip_id)
                .map(|c| (c.clip.clone(), c.track_id, c.clip.events.len()))
        };

        if let Some((clip_arc, Some(track_id), _event_count)) = updated_clip {
            // Update the track's copy
            let track_manager = self.track_manager.lock().expect("mutex poisoned");
            if let Some(track_arc) = track_manager.get_track(track_id) {
                let mut track = track_arc.lock().expect("mutex poisoned");
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
            let mut clips = self.clips.lock().expect("mutex poisoned");
            if let Some(pos) = clips.iter().position(|c| c.id == clip_id) {
                clips.remove(pos);
                return true;
            }
        }

        // Try to remove from MIDI clips
        {
            let mut midi_clips = self.midi_clips.lock().expect("mutex poisoned");
            if let Some(pos) = midi_clips.iter().position(|c| c.id == clip_id) {
                midi_clips.remove(pos);
                return true;
            }
        }

        false
    }

    /// Remove all MIDI clips belonging to a specific track
    pub fn remove_midi_clips_for_track(&self, track_id: TrackId) -> usize {
        let mut midi_clips = self.midi_clips.lock().expect("mutex poisoned");
        let initial_count = midi_clips.len();
        midi_clips.retain(|clip| clip.track_id != Some(track_id));
        let removed_count = initial_count - midi_clips.len();
        removed_count
    }

    /// Get the current playhead position in seconds
    pub fn get_playhead_position(&self) -> f64 {
        let samples = self.playhead_samples.load(Ordering::SeqCst);
        // Simple conversion: samples to seconds (no tempo scaling)
        // The playhead tracks real time - tempo affects note/beat positions, not time itself
        samples as f64 / TARGET_SAMPLE_RATE as f64
    }

    /// Get the current playhead position in samples
    pub fn get_playhead_samples(&self) -> u64 {
        self.playhead_samples.load(Ordering::SeqCst)
    }

    /// Set the playhead position in samples (used for tempo change adjustment)
    pub fn set_playhead_samples(&self, samples: u64) {
        self.playhead_samples.store(samples, Ordering::SeqCst);
    }

    /// Seek to a specific position in seconds
    pub fn seek(&self, position_seconds: f64) {
        // Simple conversion: seconds to samples (no tempo scaling)
        let samples = (position_seconds * TARGET_SAMPLE_RATE as f64) as u64;
        self.playhead_samples.store(samples, Ordering::SeqCst);
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
        if let Ok(mut synth_manager) = self.track_synth_manager.lock() {
            synth_manager.all_notes_off_all_tracks();
            eprintln!("   All synth notes silenced");
        }

        // Silence all VST3 instruments to prevent stuck notes/drone
        if let Ok(track_mgr) = self.track_manager.lock() {
            if let Ok(effect_mgr) = self.effect_manager.lock() {
                for track_arc in track_mgr.get_all_tracks() {
                    if let Ok(track) = track_arc.lock() {
                        for effect_id in &track.fx_chain {
                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                if let Ok(mut effect) = effect_arc.lock() {
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

    /// Stop playback (resets to start) - lock-free state change
    pub fn stop(&mut self) -> anyhow::Result<()> {
        eprintln!("⏹️  [AudioGraph] stop() called - resetting playhead and metronome");

        self.state.store(TransportState::Stopped as u8, Ordering::SeqCst);
        // Stream keeps running for MIDI preview

        // Silence all synthesizers to prevent stuck notes/drone
        if let Ok(mut synth_manager) = self.track_synth_manager.lock() {
            synth_manager.all_notes_off_all_tracks();
            eprintln!("   All synth notes silenced");
        }

        // Silence all VST3 instruments to prevent stuck notes/drone
        if let Ok(track_mgr) = self.track_manager.lock() {
            if let Ok(effect_mgr) = self.effect_manager.lock() {
                for track_arc in track_mgr.get_all_tracks() {
                    if let Ok(track) = track_arc.lock() {
                        for effect_id in &track.fx_chain {
                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                if let Ok(mut effect) = effect_arc.lock() {
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

        // Reset playhead to start
        let old_playhead = self.playhead_samples.swap(0, Ordering::SeqCst);
        eprintln!("   Playhead reset: {} → 0", old_playhead);

        // Reset metronome beat position
        self.recorder.reset_metronome();

        Ok(())
    }

    // --- Latency Control Methods ---

    /// Set the preferred buffer size preset
    /// Requires restarting the audio stream to take effect
    pub fn set_buffer_size(&mut self, preset: BufferSizePreset) -> anyhow::Result<()> {
        {
            let mut current = self.preferred_buffer_size.lock().expect("mutex poisoned");
            if *current == preset {
                return Ok(()); // No change needed
            }
            *current = preset;
        }

        eprintln!("🔊 [AudioGraph] Setting buffer size to {:?} ({} samples, {:.1}ms)",
            preset, preset.samples(), preset.latency_ms());

        // Restart the audio stream with new buffer size
        self.restart_audio_stream()?;

        Ok(())
    }

    /// Get the current buffer size preset
    pub fn get_buffer_size_preset(&self) -> BufferSizePreset {
        *self.preferred_buffer_size.lock().expect("mutex poisoned")
    }

    /// Get the actual buffer size being used (in samples)
    pub fn get_actual_buffer_size(&self) -> u32 {
        self.actual_buffer_size.load(Ordering::SeqCst)
    }

    /// Get current audio latency info
    /// Returns: (buffer_size_samples, input_latency_ms, output_latency_ms, total_roundtrip_ms)
    pub fn get_latency_info(&self) -> (u32, f32, f32, f32) {
        let buffer_samples = self.get_actual_buffer_size();
        let sample_rate = TARGET_SAMPLE_RATE as f32;

        // Calculate latency based on buffer size
        // Output latency = buffer size / sample rate
        let output_latency_ms = buffer_samples as f32 / sample_rate * 1000.0;

        // Input latency is similar (assuming same buffer for input)
        let input_latency_ms = output_latency_ms;

        // Total roundtrip = input + output
        let total_roundtrip_ms = input_latency_ms + output_latency_ms;

        (buffer_samples, input_latency_ms, output_latency_ms, total_roundtrip_ms)
    }

    /// Restart the audio stream (used when changing buffer size)
    fn restart_audio_stream(&mut self) -> anyhow::Result<()> {
        // Stop current stream
        if let Some(stream) = self.stream.take() {
            let _ = stream.pause();
            drop(stream);
        }

        // Create new stream with updated settings
        eprintln!("🔊 [AudioGraph] Restarting audio stream...");
        let stream = self.create_audio_stream()?;

        // Always keep stream running for MIDI preview
        stream.play()?;

        self.stream = Some(stream);
        eprintln!("✅ [AudioGraph] Audio stream restarted");

        Ok(())
    }

    /// Create the audio output stream
    fn create_audio_stream(&self) -> anyhow::Result<cpal::Stream> {
        use cpal::SupportedBufferSize;

        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow::anyhow!("No output device available"))?;

        let supported_config = device.default_output_config()?;

        // Get preferred buffer size
        let preferred_samples = self.preferred_buffer_size.lock()
            .expect("mutex poisoned")
            .samples();

        // Check if device supports our preferred buffer size
        let buffer_size = match supported_config.buffer_size() {
            SupportedBufferSize::Range { min, max } => {
                // Handle invalid range (e.g., iOS simulator reports [0-0])
                if *max == 0 || *min == *max && *max == 0 {
                    eprintln!("🔊 [AudioGraph] Buffer size: device reports invalid range [{}-{}], using default",
                        min, max);
                    None
                } else {
                    let clamped = preferred_samples.clamp(*min, *max);
                    eprintln!("🔊 [AudioGraph] Buffer size: requested={}, device range=[{}-{}], using={}",
                        preferred_samples, min, max, clamped);
                    Some(cpal::BufferSize::Fixed(clamped))
                }
            }
            SupportedBufferSize::Unknown => {
                eprintln!("🔊 [AudioGraph] Buffer size: device doesn't report range, using default");
                None
            }
        };

        // Build stream config with our buffer size preference
        let mut config: cpal::StreamConfig = supported_config.into();
        if let Some(buf_size) = buffer_size {
            config.buffer_size = buf_size;
        }

        // Clone for tracking actual buffer size in callback
        let actual_buffer_size = self.actual_buffer_size.clone();

        // Clone Arcs for the audio callback
        let clips = self.clips.clone();
        let midi_clips = self.midi_clips.clone();
        let playhead_samples = self.playhead_samples.clone();
        let state = self.state.clone();
        let input_manager = self.input_manager.clone();
        let recorder_refs = self.recorder.get_callback_refs();

        // M4: Clone track and effect managers
        let track_manager = self.track_manager.clone();
        let effect_manager = self.effect_manager.clone();
        let master_limiter = self.master_limiter.clone();

        // M6: Clone track synth manager
        let track_synth_manager = self.track_synth_manager.clone();

        let stream = device.build_output_stream(
            &config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                // Track actual buffer size (frames = samples / 2 for stereo)
                let frames = data.len() / 2;
                actual_buffer_size.store(frames as u32, Ordering::Relaxed);

                // Check if we should be playing (lock-free atomic read)
                let is_playing = state.load(Ordering::SeqCst) == TransportState::Playing as u8;

                if !is_playing {
                    // Even when not playing, we might be recording or using virtual piano
                    // Process metronome, recording, AND synths (for real-time MIDI input)
                    // but DON'T advance playhead or trigger MIDI clips from timeline

                    // Debug: log that we're in stopped callback (once)
                    static LOGGED_STOPPED: AtomicBool = AtomicBool::new(false);
                    if !LOGGED_STOPPED.swap(true, Ordering::Relaxed) {
                        eprintln!("🔇 Audio callback: NOT PLAYING branch active");
                    }

                    // Log channel info once
                    static LOGGED_CHANNELS: AtomicBool = AtomicBool::new(false);

                    // Lock synth manager once for the entire buffer
                    let mut synth_guard = track_synth_manager.lock().ok();

                    // Debug: log if we got the lock
                    static LOGGED_LOCK: AtomicBool = AtomicBool::new(false);
                    if !LOGGED_LOCK.swap(true, Ordering::Relaxed) {
                        eprintln!("🔇 Synth guard acquired: {}", synth_guard.is_some());
                    }

                    for frame_idx in 0..frames {
                        // Get input samples (if recording)
                        let (input_left, input_right) = if let Ok(input_mgr) = input_manager.lock() {
                            let channels = input_mgr.get_input_channels();

                            // Log once for debugging
                            if !LOGGED_CHANNELS.swap(true, Ordering::Relaxed) {
                                eprintln!("🔊 [AudioGraph] Reading input with {} channels", channels);
                            }

                            if channels == 1 {
                                // Mono input: read 1 sample and duplicate to both channels
                                if let Some(samples) = input_mgr.read_samples(1) {
                                    let mono_sample = samples.get(0).copied().unwrap_or(0.0);
                                    (mono_sample, mono_sample)
                                } else {
                                    (0.0, 0.0)
                                }
                            } else {
                                // Stereo input: read 2 samples
                                if let Some(samples) = input_mgr.read_samples(2) {
                                    (samples.get(0).copied().unwrap_or(0.0),
                                     samples.get(1).copied().unwrap_or(0.0))
                                } else {
                                    (0.0, 0.0)
                                }
                            }
                        } else {
                            // Failed to acquire input manager lock - audio samples will be dropped
                            (0.0, 0.0)
                        };

                        // Process recording and get metronome output
                        let (met_left, met_right) = recorder_refs.process_frame(input_left, input_right, false);

                        // Process synths for real-time MIDI input (virtual piano)
                        // This allows synths to produce sound from real-time note_on/note_off calls
                        // without triggering notes from timeline MIDI clips
                        let mut synth_output = 0.0;
                        if let Some(ref mut synth_manager) = synth_guard {
                            synth_output = synth_manager.process_all_synths();
                        }

                        // Debug: log if synth is producing output (only first frame to avoid spam)
                        if frame_idx == 0 && synth_output.abs() > 0.001 {
                            static LAST_LOG: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                            let now = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_millis() as u64;
                            let last = LAST_LOG.load(Ordering::Relaxed);
                            if now - last > 100 { // Log every 100ms max
                                LAST_LOG.store(now, Ordering::Relaxed);
                                eprintln!("🔊 Synth output (stopped): {:.4}", synth_output);
                            }
                        }

                        // Start with metronome + synth (synth handles virtual keyboard when stopped)
                        let mut out_left = met_left + synth_output;
                        let mut out_right = met_right + synth_output;

                        // Process VST3 instruments in FX chains even when stopped
                        // This is necessary because VST3 instruments (like Serum) need
                        // continuous process() calls to stay active and respond to MIDI
                        //
                        // We process each track separately and apply volume/pan per track
                        if let Ok(effect_mgr) = effect_manager.lock() {
                            if let Ok(tm) = track_manager.lock() {
                                let has_solo = tm.has_solo();
                                for track_arc in tm.get_all_tracks() {
                                    if let Ok(track) = track_arc.lock() {
                                        // Skip master track in per-track processing
                                        if track.track_type == crate::track::TrackType::Master {
                                            continue;
                                        }

                                        // Handle mute/solo
                                        if track.mute {
                                            // Still process to keep VST3 alive, but don't mix
                                            for effect_id in &track.fx_chain {
                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                    if let Ok(mut effect) = effect_arc.lock() {
                                                        let _ = effect.process_frame(0.0, 0.0);
                                                    }
                                                }
                                            }
                                            continue;
                                        }
                                        if has_solo && !track.solo {
                                            // Still process to keep VST3 alive
                                            for effect_id in &track.fx_chain {
                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                    if let Ok(mut effect) = effect_arc.lock() {
                                                        let _ = effect.process_frame(0.0, 0.0);
                                                    }
                                                }
                                            }
                                            continue;
                                        }

                                        // Process FX chain for this track (instruments generate audio from MIDI)
                                        let mut track_left = 0.0f32;
                                        let mut track_right = 0.0f32;
                                        for effect_id in &track.fx_chain {
                                            // Skip bypassed effects (audio passes through unchanged)
                                            if effect_mgr.is_bypassed(*effect_id) {
                                                continue;
                                            }
                                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                if let Ok(mut effect) = effect_arc.lock() {
                                                    let (fx_l, fx_r) = effect.process_frame(track_left, track_right);
                                                    track_left = fx_l;
                                                    track_right = fx_r;
                                                }
                                            }
                                        }

                                        // Apply track volume and pan AFTER FX chain
                                        let volume_gain = track.get_gain();
                                        let (pan_left, pan_right) = track.get_pan_gains();

                                        // Debug: log volume application (only occasionally)
                                        let fx_chain_len = track.fx_chain.len();
                                        if frame_idx == 0 && (track_left.abs() > 0.001 || track_right.abs() > 0.001) {
                                            static LAST_VOL_LOG: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                                            let now = std::time::SystemTime::now()
                                                .duration_since(std::time::UNIX_EPOCH)
                                                .unwrap_or_default()
                                                .as_millis() as u64;
                                            let last = LAST_VOL_LOG.load(Ordering::Relaxed);
                                            if now - last > 500 {
                                                LAST_VOL_LOG.store(now, Ordering::Relaxed);
                                                eprintln!("🎚️ Track {} (fx_chain={}) pre-vol: L={:.4} R={:.4}, gain={:.4}, vol_db={:.1}",
                                                    track.id, fx_chain_len, track_left, track_right, volume_gain, track.volume_db);
                                            }
                                        }

                                        track_left *= volume_gain * pan_left;
                                        track_right *= volume_gain * pan_right;

                                        // Mix into output
                                        out_left += track_left;
                                        out_right += track_right;
                                    }
                                }
                            }
                        }

                        // Output metronome + synths + VST3 when not playing
                        data[frame_idx * 2] = out_left;
                        data[frame_idx * 2 + 1] = out_right;
                    }
                    return;
                }

                // frames already calculated at top of callback
                let current_playhead = playhead_samples.load(Ordering::SeqCst);

                // Get clips (lock briefly) - keeping for potential future use
                let _clips_snapshot = {
                    let clips_lock = clips.lock().expect("mutex poisoned");
                    clips_lock.clone()
                };

                // Get MIDI clips (lock briefly)
                let midi_clips_snapshot = {
                    let midi_clips_lock = midi_clips.lock().expect("mutex poisoned");
                    midi_clips_lock.clone()
                };

                // Get current tempo for MIDI playback scaling
                let current_tempo = *recorder_refs.tempo.lock().expect("mutex poisoned");
                let tempo_ratio = current_tempo / 120.0;

                // NOTE: Legacy MIDI clip processing removed - all MIDI now handled per-track

                // M5.5: Track-based mixing (replaces legacy clip mixing)

                // OPTIMIZATION: Lock tracks ONCE and extract all data before frame loop
                // This prevents locking for every frame (which causes UI freezing)

                struct TrackSnapshot {
                    id: u64,
                    audio_clips: Vec<TimelineClip>,
                    midi_clips: Vec<TimelineMidiClip>,
                    volume_gain: f32,
                    pan_left: f32,
                    pan_right: f32,
                    muted: bool,
                    soloed: bool,
                    fx_chain: Vec<u64>,
                }

                let track_data_option = if let Ok(tm) = track_manager.lock() {
                    let has_solo_flag = tm.has_solo();
                    let all_tracks = tm.get_all_tracks();
                    let mut snapshots = Vec::new();
                    let mut master_snap = None;

                    for track_arc in all_tracks {
                        if let Ok(track) = track_arc.lock() {
                            // Extract all data we need from this track
                            let snap = TrackSnapshot {
                                id: track.id,
                                audio_clips: track.audio_clips.clone(),
                                midi_clips: track.midi_clips.clone(),
                                volume_gain: track.get_gain(),
                                pan_left: track.get_pan_gains().0,
                                pan_right: track.get_pan_gains().1,
                                muted: track.mute,
                                soloed: track.solo,
                                fx_chain: track.fx_chain.clone(),
                            };

                            if track.track_type == crate::track::TrackType::Master {
                                master_snap = Some(snap);
                            } else {
                                snapshots.push(snap);
                            }
                        }
                    }

                    Some((snapshots, has_solo_flag, master_snap))
                } else {
                    None // Lock failed, use empty track list
                }; // All locks released here!

                let (track_snapshots, has_solo, master_snapshot) = track_data_option
                    .unwrap_or_else(|| (Vec::new(), false, None));

                // Track peak levels per track for metering (track_id -> (max_left, max_right))
                let mut track_peaks: HashMap<TrackId, (f32, f32)> = HashMap::new();
                let mut master_peak_left = 0.0f32;
                let mut master_peak_right = 0.0f32;

                // OPTIMIZATION: Lock synth manager ONCE before the frame loop
                // This prevents lock contention that causes audio dropouts
                let mut synth_guard = track_synth_manager.lock().ok();

                // Process each frame (using snapshots - NO LOCKS in hot path!)
                for frame_idx in 0..frames {
                    let playhead_frame = current_playhead + frame_idx as u64;
                    let playhead_seconds = playhead_frame as f64 / TARGET_SAMPLE_RATE as f64;

                    let mut mix_left = 0.0;
                    let mut mix_right = 0.0;

                    // Mix all tracks using snapshots (no locking!)
                    for track_snap in &track_snapshots {
                        // Handle mute/solo logic
                        if track_snap.muted {
                            continue; // Muted tracks produce no sound
                        }
                        if has_solo && !track_snap.soloed {
                            continue; // If any track is soloed, skip non-soloed tracks
                        }

                        let mut track_left = 0.0;
                        let mut track_right = 0.0;

                        // Mix all audio clips on this track
                        for timeline_clip in &track_snap.audio_clips {
                            let clip_duration = timeline_clip.duration
                                .unwrap_or(timeline_clip.clip.duration_seconds);
                            let clip_end = timeline_clip.start_time + clip_duration;

                            if playhead_seconds >= timeline_clip.start_time
                                && playhead_seconds < clip_end
                            {
                                let time_in_clip = playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                                let frame_in_clip = (time_in_clip * TARGET_SAMPLE_RATE as f64) as usize;

                                if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                                    track_left += l;
                                }
                                if timeline_clip.clip.channels > 1 {
                                    if let Some(r) = timeline_clip.clip.get_sample(frame_in_clip, 1) {
                                        track_right += r;
                                    }
                                } else {
                                    // Mono clip - duplicate to right
                                    if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                                        track_right += l;
                                    }
                                }
                            }
                        }

                        // Process per-track MIDI clips (using pre-acquired synth lock)
                        // Also send MIDI to VST3 instruments in the FX chain
                        if let Some(ref mut synth_manager) = synth_guard {
                            for timeline_midi_clip in &track_snap.midi_clips {
                                let clip_start_samples = (timeline_midi_clip.start_time * TARGET_SAMPLE_RATE as f64) as u64;
                                let clip_end_samples = clip_start_samples + timeline_midi_clip.clip.duration_samples;

                                // Check if clip is active at this frame
                                // Use <= for end boundary to ensure note-offs at exact clip end are triggered
                                if playhead_frame >= clip_start_samples && playhead_frame <= clip_end_samples {
                                    let frame_in_clip = playhead_frame - clip_start_samples;

                                    // Check for MIDI events that should trigger at this exact sample
                                    for event in &timeline_midi_clip.clip.events {
                                        if event.timestamp_samples == frame_in_clip {
                                            match event.event_type {
                                                crate::midi::MidiEventType::NoteOn { note, velocity } => {
                                                    // Send to built-in synth
                                                    synth_manager.note_on(track_snap.id, note, velocity);

                                                    // Send to VST3 instruments in FX chain
                                                    if let Ok(effect_mgr) = effect_manager.lock() {
                                                        for effect_id in &track_snap.fx_chain {
                                                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                                if let Ok(mut effect) = effect_arc.lock() {
                                                                    if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                                        let _ = vst3.process_midi_event(0, 0, note as i32, velocity as i32, 0);
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                crate::midi::MidiEventType::NoteOff { note, velocity: _ } => {
                                                    // Send to built-in synth
                                                    synth_manager.note_off(track_snap.id, note);

                                                    // Send to VST3 instruments in FX chain
                                                    if let Ok(effect_mgr) = effect_manager.lock() {
                                                        for effect_id in &track_snap.fx_chain {
                                                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                                if let Ok(mut effect) = effect_arc.lock() {
                                                                    if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                                        let _ = vst3.process_midi_event(1, 0, note as i32, 0, 0);
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Add per-track synthesizer output (M6) - no lock needed, already held
                            let synth_sample = synth_manager.process_sample(track_snap.id);
                            track_left += synth_sample;
                            track_right += synth_sample;
                        }

                        // Process FX chain on this track BEFORE volume/pan
                        // This is important because VST3 instruments generate their own audio
                        // and we want the fader to control the post-FX output level
                        let mut fx_left = track_left;
                        let mut fx_right = track_right;

                        if let Ok(effect_mgr) = effect_manager.lock() {
                            for effect_id in &track_snap.fx_chain {
                                // Skip bypassed effects (audio passes through unchanged)
                                if effect_mgr.is_bypassed(*effect_id) {
                                    continue;
                                }
                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                    if let Ok(mut effect) = effect_arc.lock() {
                                        let (out_l, out_r) = effect.process_frame(fx_left, fx_right);
                                        fx_left = out_l;
                                        fx_right = out_r;
                                    }
                                }
                            }
                        }

                        // Apply track volume AFTER FX chain (from snapshot)
                        // This ensures VST3 instrument output is also affected by the fader
                        fx_left *= track_snap.volume_gain;
                        fx_right *= track_snap.volume_gain;

                        // Apply track pan AFTER FX chain (from snapshot)
                        fx_left *= track_snap.pan_left;
                        fx_right *= track_snap.pan_right;

                        // Update track peak levels for metering
                        let entry = track_peaks.entry(track_snap.id).or_insert((0.0, 0.0));
                        entry.0 = entry.0.max(fx_left.abs());
                        entry.1 = entry.1.max(fx_right.abs());

                        // Accumulate to mix bus
                        mix_left += fx_left;
                        mix_right += fx_right;
                    }

                    // NOTE: Legacy synth output removed - all synth now per-track

                    // REMOVED: Legacy mixing that bypassed track controls
                    // All clips now go through tracks with proper volume/pan/mute/solo

                    /* LEGACY CODE REMOVED FOR MIXER FIX
                    for timeline_clip in &clips_snapshot {
                        let clip_duration = timeline_clip.duration
                            .unwrap_or(timeline_clip.clip.duration_seconds);
                        let clip_end = timeline_clip.start_time + clip_duration;

                        if playhead_seconds >= timeline_clip.start_time
                            && playhead_seconds < clip_end
                        {
                            let time_in_clip = playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                            let frame_in_clip = (time_in_clip * TARGET_SAMPLE_RATE as f64) as usize;

                            if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                                mix_left += l;
                            }
                            if timeline_clip.clip.channels > 1 {
                                if let Some(r) = timeline_clip.clip.get_sample(frame_in_clip, 1) {
                                    mix_right += r;
                                }
                            } else {
                                if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                                    mix_right += l;
                                }
                            }
                        }
                    }
                    */ // END LEGACY CODE REMOVAL

                    // Get input samples (if recording)
                    let (input_left, input_right) = if let Ok(input_mgr) = input_manager.lock() {
                        let channels = input_mgr.get_input_channels();
                        if channels == 1 {
                            if let Some(samples) = input_mgr.read_samples(1) {
                                let mono_sample = samples.get(0).copied().unwrap_or(0.0);
                                (mono_sample, mono_sample)
                            } else {
                                (0.0, 0.0)
                            }
                        } else {
                            if let Some(samples) = input_mgr.read_samples(2) {
                                (samples.get(0).copied().unwrap_or(0.0),
                                 samples.get(1).copied().unwrap_or(0.0))
                            } else {
                                (0.0, 0.0)
                            }
                        }
                    } else {
                        (0.0, 0.0)
                    };

                    // Process recording (metronome handled separately below)
                    let (met_left, met_right) = recorder_refs.process_frame(input_left, input_right, true);

                    // Apply master track processing (using snapshot - no locks!)
                    let mut master_left = mix_left;
                    let mut master_right = mix_right;

                    if let Some(ref master_snap) = master_snapshot {
                        // Apply master volume
                        master_left *= master_snap.volume_gain;
                        master_right *= master_snap.volume_gain;

                        // Apply master pan
                        master_left *= master_snap.pan_left;
                        master_right *= master_snap.pan_right;

                        // Process master FX chain
                        if let Ok(effect_mgr) = effect_manager.lock() {
                            for effect_id in &master_snap.fx_chain {
                                // Skip bypassed effects (audio passes through unchanged)
                                if effect_mgr.is_bypassed(*effect_id) {
                                    continue;
                                }
                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                    if let Ok(mut effect) = effect_arc.lock() {
                                        let (out_l, out_r) = effect.process_frame(master_left, master_right);
                                        master_left = out_l;
                                        master_right = out_r;
                                    }
                                }
                            }
                        }
                    }

                    // Apply master limiter to prevent clipping
                    let (limited_left, limited_right) = if let Ok(mut limiter) = master_limiter.lock() {
                        limiter.process_frame(master_left, master_right)
                    } else {
                        (master_left.clamp(-1.0, 1.0), master_right.clamp(-1.0, 1.0))
                    };

                    // Update master peak levels for metering (before metronome is added)
                    master_peak_left = master_peak_left.max(limited_left.abs());
                    master_peak_right = master_peak_right.max(limited_right.abs());

                    // Add metronome AFTER metering so it doesn't affect the master meter
                    // Metronome goes directly to output, bypassing master volume/effects
                    let output_left = limited_left + met_left;
                    let output_right = limited_right + met_right;

                    // Write to output buffer (interleaved stereo)
                    data[frame_idx * 2] = output_left;
                    data[frame_idx * 2 + 1] = output_right;
                }

                // Update track peak levels in track manager (brief lock after buffer processing)
                if let Ok(tm) = track_manager.lock() {
                    for (track_id, (peak_l, peak_r)) in &track_peaks {
                        if let Some(track_arc) = tm.get_track(*track_id) {
                            if let Ok(mut track) = track_arc.lock() {
                                track.update_peaks(*peak_l, *peak_r);
                            }
                        }
                    }
                    // Update master track peaks
                    {
                        let master_arc = tm.get_master_track();
                        if let Ok(mut master) = master_arc.lock() {
                            master.update_peaks(master_peak_left, master_peak_right);
                        };
                    }
                }

                // Advance playhead
                playhead_samples.fetch_add(frames as u64, Ordering::SeqCst);
            },
            move |err| {
                eprintln!("Audio stream error: {}", err);
            },
            None,
        )?;

        Ok(stream)
    }

    /// Get number of audio clips
    pub fn clip_count(&self) -> usize {
        self.clips.lock().expect("mutex poisoned").len()
    }

    /// Get number of MIDI clips
    pub fn midi_clip_count(&self) -> usize {
        self.midi_clips.lock().expect("mutex poisoned").len()
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

    // ========================================================================
    // M5: SAVE & LOAD PROJECT
    // ========================================================================

    /// Export current state to ProjectData (for saving)
    pub fn export_to_project_data(&self, project_name: String) -> crate::project::ProjectData {
        use crate::project::*;
        use crate::effects::EffectType as ET;
        use std::collections::HashMap;
        use base64::Engine as _;

        // Get all tracks
        let track_manager = self.track_manager.lock().expect("mutex poisoned");
        let effect_manager = self.effect_manager.lock().expect("mutex poisoned");
        let synth_manager = self.track_synth_manager.lock().expect("mutex poisoned");

        let all_tracks = track_manager.get_all_tracks();
        let tracks_data: Vec<TrackData> = all_tracks.iter().map(|track_arc| {
            let track = track_arc.lock().expect("mutex poisoned");

            // Get effect chain for this track
            let fx_chain: Vec<EffectData> = track.fx_chain.iter().filter_map(|effect_id| {
                // Get effect from effect manager
                if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                    let effect = effect_arc.lock().expect("mutex poisoned");
                    let mut parameters = HashMap::new();
                    let effect_type_str;

                    // Get parameters based on effect type
                    match &*effect {
                        ET::EQ(eq) => {
                            effect_type_str = "eq".to_string();
                            parameters.insert("low_freq".to_string(), eq.low_freq);
                            parameters.insert("low_gain_db".to_string(), eq.low_gain_db);
                            parameters.insert("mid1_freq".to_string(), eq.mid1_freq);
                            parameters.insert("mid1_gain_db".to_string(), eq.mid1_gain_db);
                            parameters.insert("mid1_q".to_string(), eq.mid1_q);
                            parameters.insert("mid2_freq".to_string(), eq.mid2_freq);
                            parameters.insert("mid2_gain_db".to_string(), eq.mid2_gain_db);
                            parameters.insert("mid2_q".to_string(), eq.mid2_q);
                            parameters.insert("high_freq".to_string(), eq.high_freq);
                            parameters.insert("high_gain_db".to_string(), eq.high_gain_db);
                        }
                        ET::Compressor(comp) => {
                            effect_type_str = "compressor".to_string();
                            parameters.insert("threshold_db".to_string(), comp.threshold_db);
                            parameters.insert("ratio".to_string(), comp.ratio);
                            parameters.insert("attack_ms".to_string(), comp.attack_ms);
                            parameters.insert("release_ms".to_string(), comp.release_ms);
                            parameters.insert("makeup_gain_db".to_string(), comp.makeup_gain_db);
                        }
                        ET::Reverb(rev) => {
                            effect_type_str = "reverb".to_string();
                            parameters.insert("room_size".to_string(), rev.room_size);
                            parameters.insert("damping".to_string(), rev.damping);
                            parameters.insert("wet_dry_mix".to_string(), rev.wet_dry_mix);
                        }
                        ET::Delay(dly) => {
                            effect_type_str = "delay".to_string();
                            parameters.insert("delay_time_ms".to_string(), dly.delay_time_ms);
                            parameters.insert("feedback".to_string(), dly.feedback);
                            parameters.insert("wet_dry_mix".to_string(), dly.wet_dry_mix);
                        }
                        ET::Chorus(chr) => {
                            effect_type_str = "chorus".to_string();
                            parameters.insert("rate_hz".to_string(), chr.rate_hz);
                            parameters.insert("depth".to_string(), chr.depth);
                            parameters.insert("wet_dry_mix".to_string(), chr.wet_dry_mix);
                        }
                        ET::Limiter(_) => {
                            effect_type_str = "limiter".to_string();
                            // Limiter has no user-adjustable parameters
                        }
                        #[cfg(not(target_os = "ios"))]
                        ET::VST3(_vst3) => {
                            effect_type_str = "vst3".to_string();
                            // TODO M7: Save VST3 plugin path and state
                            // For now, just mark the type - full state persistence coming later
                            parameters.insert("name".to_string(), 0.0); // Placeholder
                        }
                    }

                    Some(EffectData {
                        id: *effect_id,
                        effect_type: effect_type_str,
                        parameters,
                    })
                } else {
                    None
                }
            }).collect();

            // Get audio clips on this track
            let audio_clips_data: Vec<ClipData> = track.audio_clips.iter().map(|timeline_clip| {
                ClipData {
                    id: timeline_clip.id,
                    start_time: timeline_clip.start_time,
                    offset: timeline_clip.offset,
                    duration: timeline_clip.duration,
                    audio_file_id: Some(timeline_clip.id), // Simplified: use clip ID as file ID
                    midi_notes: None,
                }
            }).collect();

            // Get MIDI clips on this track - convert events to note data
            let midi_clips_data: Vec<ClipData> = track.midi_clips.iter().map(|timeline_clip| {
                let midi_notes = convert_midi_events_to_notes(
                    &timeline_clip.clip.events,
                    timeline_clip.clip.sample_rate
                );
                let duration_seconds = timeline_clip.clip.duration_samples as f64
                    / timeline_clip.clip.sample_rate as f64;

                ClipData {
                    id: timeline_clip.id,
                    start_time: timeline_clip.start_time,
                    offset: 0.0,
                    duration: Some(duration_seconds),
                    audio_file_id: None, // MIDI clip, not audio
                    midi_notes: Some(midi_notes),
                }
            }).collect();

            // Combine audio and MIDI clips
            let clips_data: Vec<ClipData> = audio_clips_data.into_iter()
                .chain(midi_clips_data.into_iter())
                .collect();

            // Get track type string
            let track_type_str = format!("{:?}", track.track_type);

            // Get synth settings for MIDI tracks
            let synth_settings = if track_type_str == "Midi" {
                synth_manager.get_synth_parameters(track.id)
            } else {
                None
            };

            // Export send routing
            let sends: Vec<SendData> = track.sends.iter().map(|s| SendData {
                target_track_id: s.target_track_id,
                amount: s.amount,
                pre_fader: s.pre_fader,
            }).collect();

            // Collect VST3 plugin data with state
            #[cfg(not(target_os = "ios"))]
            let vst3_plugins: Vec<Vst3PluginData> = track.fx_chain.iter().filter_map(|effect_id| {
                if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                    let effect = effect_arc.lock().expect("mutex poisoned");
                    if let ET::VST3(vst3) = &*effect {
                        // Get plugin state
                        let state_data = vst3.get_state().unwrap_or_default();
                        let state_base64 = base64::Engine::encode(
                            &base64::engine::general_purpose::STANDARD,
                            &state_data
                        );

                        Some(Vst3PluginData {
                            effect_id: *effect_id,
                            plugin_path: vst3.get_plugin_path().to_string(),
                            plugin_name: vst3.get_name().to_string(),
                            is_instrument: vst3.is_instrument,
                            state_base64,
                        })
                    } else {
                        None
                    }
                } else {
                    None
                }
            }).collect();

            #[cfg(target_os = "ios")]
            let vst3_plugins: Vec<Vst3PluginData> = Vec::new();

            TrackData {
                id: track.id,
                name: track.name.clone(),
                track_type: track_type_str,
                volume_db: track.volume_db,
                pan: track.pan,
                mute: track.mute,
                solo: track.solo,
                armed: track.armed,
                clips: clips_data,
                fx_chain,
                synth_settings,
                sends,
                parent_group_id: track.parent_group,
                input_monitoring: track.input_monitoring,
                vst3_plugins,
            }
        }).collect();

        // Collect audio files (simplified - get from global timeline for now)
        let clips_lock = self.clips.lock().expect("mutex poisoned");
        let audio_files: Vec<AudioFileData> = clips_lock.iter().map(|timeline_clip| {
            AudioFileData {
                id: timeline_clip.id,
                original_name: timeline_clip.clip.file_path.clone(),
                relative_path: format!("audio/{:03}-{}", timeline_clip.id, timeline_clip.clip.file_path),
                duration: timeline_clip.clip.duration_seconds,
                sample_rate: timeline_clip.clip.sample_rate,
                channels: timeline_clip.clip.channels as u32,
            }
        }).collect();

        eprintln!("   - {} tracks", tracks_data.len());
        eprintln!("   - {} audio files", audio_files.len());

        // Get project-level settings
        let metronome_enabled = self.recorder.is_metronome_enabled();
        let count_in_bars = self.recorder.get_count_in_bars();
        let buffer_size_preset = match self.get_buffer_size_preset() {
            BufferSizePreset::Lowest => 0,
            BufferSizePreset::Low => 1,
            BufferSizePreset::Balanced => 2,
            BufferSizePreset::Safe => 3,
            BufferSizePreset::HighStability => 4,
        };

        ProjectData {
            version: "1.0".to_string(),
            name: project_name,
            tempo: self.recorder.get_tempo(),
            sample_rate: TARGET_SAMPLE_RATE,
            time_sig_numerator: 4,
            time_sig_denominator: 4,
            tracks: tracks_data,
            audio_files,
            metronome_enabled,
            count_in_bars,
            buffer_size_preset,
        }
    }

    /// Restore state from ProjectData (for loading)
    pub fn restore_from_project_data(&mut self, project_data: crate::project::ProjectData) -> anyhow::Result<()> {
        use crate::effects::*;
        use crate::track::TrackType;

        // Stop playback
        let _ = self.stop();

        // Clear existing tracks (except master will be kept and updated)
        {
            let mut track_manager = self.track_manager.lock().expect("mutex poisoned");
            let _effect_manager = self.effect_manager.lock().expect("mutex poisoned");

            // Get all track IDs except master (ID 0)
            let all_tracks = track_manager.get_all_tracks();
            let track_ids_to_remove: Vec<u64> = all_tracks.iter()
                .filter_map(|track_arc| {
                    let track = track_arc.lock().expect("mutex poisoned");
                    if track.id != 0 { Some(track.id) } else { None }
                })
                .collect();

            // Remove non-master tracks
            for track_id in track_ids_to_remove {
                track_manager.remove_track(track_id);
            }

            eprintln!("   - Cleared existing tracks");
        }

        // Restore tempo (via recorder)
        self.recorder.set_tempo(project_data.tempo);
        eprintln!("   - Tempo: {} BPM", project_data.tempo);

        // Restore metronome and count-in settings
        self.recorder.set_metronome_enabled(project_data.metronome_enabled);
        self.recorder.set_count_in_bars(project_data.count_in_bars);
        eprintln!("   - Metronome: {}, Count-in: {} bars",
            if project_data.metronome_enabled { "ON" } else { "OFF" },
            project_data.count_in_bars);

        // Restore buffer size preset
        let buffer_preset = match project_data.buffer_size_preset {
            0 => BufferSizePreset::Lowest,
            1 => BufferSizePreset::Low,
            2 => BufferSizePreset::Balanced,
            3 => BufferSizePreset::Safe,
            _ => BufferSizePreset::HighStability,
        };
        if let Err(e) = self.set_buffer_size(buffer_preset) {
            eprintln!("⚠️  Failed to restore buffer size: {}", e);
        } else {
            eprintln!("   - Buffer size: {:?}", buffer_preset);
        }

        // Recreate tracks and effects
        for track_data in project_data.tracks {
            let track_manager = self.track_manager.lock().expect("mutex poisoned");
            let mut effect_manager = self.effect_manager.lock().expect("mutex poisoned");

            // Parse track type
            let track_type = match track_data.track_type.as_str() {
                "Audio" => TrackType::Audio,
                "Midi" => TrackType::Midi,
                "Return" => TrackType::Return,
                "Group" => TrackType::Group,
                "Master" => TrackType::Master,
                _ => {
                    eprintln!("⚠️  Unknown track type: {}, defaulting to Audio", track_data.track_type);
                    TrackType::Audio
                }
            };

            // Handle master track specially (update existing)
            if track_type == TrackType::Master {
                if let Some(master_track_arc) = track_manager.get_track(0) {
                    let mut master = master_track_arc.lock().expect("mutex poisoned");
                    master.volume_db = track_data.volume_db;
                    master.pan = track_data.pan;
                    master.mute = track_data.mute;
                    master.solo = track_data.solo;
                    eprintln!("   - Updated Master track");
                }
                continue;
            }

            // Create new track
            drop(track_manager); // Release lock before creating track
            let track_id = {
                let mut tm = self.track_manager.lock().expect("mutex poisoned");
                tm.create_track(track_type, track_data.name.clone())
            };

            // Update track properties
            {
                let tm = self.track_manager.lock().expect("mutex poisoned");
                if let Some(track_arc) = tm.get_track(track_id) {
                    let mut track = track_arc.lock().expect("mutex poisoned");
                    track.volume_db = track_data.volume_db;
                    track.pan = track_data.pan;
                    track.mute = track_data.mute;
                    track.solo = track_data.solo;
                    track.armed = track_data.armed;

                    // Restore parent group and input monitoring
                    track.parent_group = track_data.parent_group_id;
                    track.input_monitoring = track_data.input_monitoring;

                    // Restore send routing
                    for send_data in &track_data.sends {
                        track.sends.push(crate::track::Send {
                            target_track_id: send_data.target_track_id,
                            amount: send_data.amount,
                            pre_fader: send_data.pre_fader,
                        });
                    }
                }
            }

            // Create and restore synth for MIDI tracks
            if track_type == TrackType::Midi {
                let mut synth_manager = self.track_synth_manager.lock().expect("mutex poisoned");
                synth_manager.create_synth(track_id);

                // Restore synth parameters if saved
                if let Some(synth_data) = &track_data.synth_settings {
                    synth_manager.restore_synth_parameters(track_id, synth_data);
                }
            }

            // Recreate effects on this track
            for effect_data in &track_data.fx_chain {
                // Skip VST3 effects in fx_chain - they are restored from vst3_plugins
                if effect_data.effect_type == "vst3" {
                    continue;
                }

                let effect = match effect_data.effect_type.as_str() {
                    "eq" => {
                        let mut eq = ParametricEQ::new();
                        if let Some(&v) = effect_data.parameters.get("low_freq") { eq.low_freq = v; }
                        if let Some(&v) = effect_data.parameters.get("low_gain_db") { eq.low_gain_db = v; }
                        if let Some(&v) = effect_data.parameters.get("mid1_freq") { eq.mid1_freq = v; }
                        if let Some(&v) = effect_data.parameters.get("mid1_gain_db") { eq.mid1_gain_db = v; }
                        if let Some(&v) = effect_data.parameters.get("mid1_q") { eq.mid1_q = v; }
                        if let Some(&v) = effect_data.parameters.get("mid2_freq") { eq.mid2_freq = v; }
                        if let Some(&v) = effect_data.parameters.get("mid2_gain_db") { eq.mid2_gain_db = v; }
                        if let Some(&v) = effect_data.parameters.get("mid2_q") { eq.mid2_q = v; }
                        if let Some(&v) = effect_data.parameters.get("high_freq") { eq.high_freq = v; }
                        if let Some(&v) = effect_data.parameters.get("high_gain_db") { eq.high_gain_db = v; }
                        eq.update_coefficients();
                        EffectType::EQ(eq)
                    }
                    "compressor" => {
                        let mut comp = Compressor::new();
                        if let Some(&v) = effect_data.parameters.get("threshold_db") { comp.threshold_db = v; }
                        if let Some(&v) = effect_data.parameters.get("ratio") { comp.ratio = v; }
                        if let Some(&v) = effect_data.parameters.get("attack_ms") { comp.attack_ms = v; }
                        if let Some(&v) = effect_data.parameters.get("release_ms") { comp.release_ms = v; }
                        if let Some(&v) = effect_data.parameters.get("makeup_gain_db") { comp.makeup_gain_db = v; }
                        comp.update_coefficients();
                        EffectType::Compressor(comp)
                    }
                    "reverb" => {
                        let mut rev = Reverb::new();
                        if let Some(&v) = effect_data.parameters.get("room_size") { rev.room_size = v; }
                        if let Some(&v) = effect_data.parameters.get("damping") { rev.damping = v; }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") { rev.wet_dry_mix = v; }
                        EffectType::Reverb(rev)
                    }
                    "delay" => {
                        let mut dly = Delay::new();
                        if let Some(&v) = effect_data.parameters.get("delay_time_ms") { dly.delay_time_ms = v; }
                        if let Some(&v) = effect_data.parameters.get("feedback") { dly.feedback = v; }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") { dly.wet_dry_mix = v; }
                        EffectType::Delay(dly)
                    }
                    "chorus" => {
                        let mut chr = Chorus::new();
                        if let Some(&v) = effect_data.parameters.get("rate_hz") { chr.rate_hz = v; }
                        if let Some(&v) = effect_data.parameters.get("depth") { chr.depth = v; }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") { chr.wet_dry_mix = v; }
                        EffectType::Chorus(chr)
                    }
                    "limiter" => EffectType::Limiter(Limiter::new()),
                    _ => {
                        eprintln!("⚠️  Unknown effect type: {}", effect_data.effect_type);
                        continue;
                    }
                };

                // Add effect to effect manager
                let effect_id = effect_manager.create_effect(effect);

                // Add to track's FX chain
                let tm = self.track_manager.lock().expect("mutex poisoned");
                if let Some(track_arc) = tm.get_track(track_id) {
                    let mut track = track_arc.lock().expect("mutex poisoned");
                    track.fx_chain.push(effect_id);
                }
            }

            // Restore VST3 plugins from vst3_plugins field
            #[cfg(not(target_os = "ios"))]
            {
                use base64::Engine as _;
                use crate::vst3_host::VST3Effect;
                use crate::audio_file::TARGET_SAMPLE_RATE;

                for vst3_data in &track_data.vst3_plugins {
                    eprintln!("   - Restoring VST3 plugin: {} from {}", vst3_data.plugin_name, vst3_data.plugin_path);

                    // Load the VST3 plugin
                    let sample_rate = TARGET_SAMPLE_RATE as f64;
                    let block_size = 512; // TODO: Get from config

                    match VST3Effect::new(&vst3_data.plugin_path, sample_rate, block_size) {
                        Ok(mut vst3_effect) => {
                            // Initialize the plugin
                            if let Err(e) = vst3_effect.initialize() {
                                eprintln!("⚠️  Failed to initialize VST3 plugin {}: {}", vst3_data.plugin_name, e);
                                continue;
                            }

                            // Restore plugin state
                            if !vst3_data.state_base64.is_empty() {
                                match base64::engine::general_purpose::STANDARD.decode(&vst3_data.state_base64) {
                                    Ok(state_bytes) => {
                                        if let Err(e) = vst3_effect.set_state(&state_bytes) {
                                            eprintln!("⚠️  Failed to restore VST3 state for {}: {}", vst3_data.plugin_name, e);
                                        } else {
                                            eprintln!("   ✅ Restored VST3 state ({} bytes)", state_bytes.len());
                                        }
                                    }
                                    Err(e) => {
                                        eprintln!("⚠️  Failed to decode VST3 state for {}: {}", vst3_data.plugin_name, e);
                                    }
                                }
                            }

                            // Add to effect manager
                            let effect = EffectType::VST3(vst3_effect);
                            let effect_id = effect_manager.create_effect(effect);

                            // Add to track's FX chain
                            let tm = self.track_manager.lock().expect("mutex poisoned");
                            if let Some(track_arc) = tm.get_track(track_id) {
                                let mut track = track_arc.lock().expect("mutex poisoned");
                                track.fx_chain.push(effect_id);
                            }

                            eprintln!("   ✅ Loaded VST3 plugin {} (effect_id={})", vst3_data.plugin_name, effect_id);
                        }
                        Err(e) => {
                            eprintln!("⚠️  Failed to load VST3 plugin {}: {}", vst3_data.plugin_name, e);
                        }
                    }
                }
            }

            // Restore MIDI clips for this track
            let mut midi_clip_count = 0;
            for clip_data in &track_data.clips {
                if let Some(midi_notes) = &clip_data.midi_notes {
                    // Reconstruct MIDI clip from serialized notes (with saved duration)
                    let midi_clip = reconstruct_midi_clip_from_notes(
                        midi_notes,
                        project_data.sample_rate,
                        clip_data.duration,
                    );
                    let clip_arc = std::sync::Arc::new(midi_clip);

                    // Generate a new clip ID
                    let clip_id = {
                        let mut next_id = self.next_clip_id.lock().expect("mutex poisoned");
                        let id = *next_id;
                        *next_id += 1;
                        id
                    };

                    // Add to global MIDI clips storage
                    {
                        let mut midi_clips = self.midi_clips.lock().expect("mutex poisoned");
                        midi_clips.push(TimelineMidiClip {
                            id: clip_id,
                            clip: clip_arc.clone(),
                            start_time: clip_data.start_time,
                            track_id: Some(track_id),
                        });
                    }

                    // Add to track's MIDI clips
                    let tm = self.track_manager.lock().expect("mutex poisoned");
                    if let Some(track_arc) = tm.get_track(track_id) {
                        let mut track = track_arc.lock().expect("mutex poisoned");
                        track.midi_clips.push(TimelineMidiClip {
                            id: clip_id,
                            clip: clip_arc,
                            start_time: clip_data.start_time,
                            track_id: Some(track_id),
                        });
                    }

                    midi_clip_count += 1;
                }
                // Note: Audio clips are restored in the API layer after audio files are loaded
            }

            eprintln!("   - Created track '{}' (type: {:?}, {} effects, {} MIDI clips)",
                track_data.name, track_type, track_data.fx_chain.len(), midi_clip_count);
        }

        // Note: Audio clips are restored in the API layer (load_project)
        // because they need access to the loaded AudioClip objects

        Ok(())
    }

    // --- Offline Rendering (Export) ---

    /// Render the entire project offline to a buffer of stereo f32 samples
    /// Returns interleaved stereo audio (L, R, L, R, ...)
    pub fn render_offline(&self, duration_seconds: f64) -> Vec<f32> {
        let sample_rate = TARGET_SAMPLE_RATE;
        let total_frames = (duration_seconds * sample_rate as f64) as usize;
        let mut output = Vec::with_capacity(total_frames * 2); // stereo interleaved

        eprintln!("🎵 [AudioGraph] Starting offline render: {:.2}s ({} frames)", duration_seconds, total_frames);

        // Create track snapshots (same as real-time rendering)
        struct TrackSnapshot {
            id: u64,
            audio_clips: Vec<TimelineClip>,
            midi_clips: Vec<TimelineMidiClip>,
            volume_gain: f32,
            pan_left: f32,
            pan_right: f32,
            muted: bool,
            soloed: bool,
            fx_chain: Vec<u64>,
        }

        let (track_snapshots, has_solo, master_snapshot) = {
            let tm = self.track_manager.lock().expect("mutex poisoned");
            let has_solo_flag = tm.has_solo();
            let all_tracks = tm.get_all_tracks();
            let mut snapshots = Vec::new();
            let mut master_snap = None;

            for track_arc in all_tracks {
                if let Ok(track) = track_arc.lock() {
                    let snap = TrackSnapshot {
                        id: track.id,
                        audio_clips: track.audio_clips.clone(),
                        midi_clips: track.midi_clips.clone(),
                        volume_gain: track.get_gain(),
                        pan_left: track.get_pan_gains().0,
                        pan_right: track.get_pan_gains().1,
                        muted: track.mute,
                        soloed: track.solo,
                        fx_chain: track.fx_chain.clone(),
                    };

                    if track.track_type == crate::track::TrackType::Master {
                        master_snap = Some(snap);
                    } else {
                        snapshots.push(snap);
                    }
                }
            }

            (snapshots, has_solo_flag, master_snap)
        };

        eprintln!("🎵 [AudioGraph] Rendering {} tracks", track_snapshots.len());

        // Process each frame
        for frame_idx in 0..total_frames {
            let playhead_seconds = frame_idx as f64 / sample_rate as f64;

            let mut mix_left = 0.0f32;
            let mut mix_right = 0.0f32;

            // Mix all tracks
            for track_snap in &track_snapshots {
                // Handle mute/solo logic
                if track_snap.muted {
                    continue;
                }
                if has_solo && !track_snap.soloed {
                    continue;
                }

                let mut track_left = 0.0f32;
                let mut track_right = 0.0f32;

                // Mix all audio clips on this track
                for timeline_clip in &track_snap.audio_clips {
                    let clip_duration = timeline_clip.duration
                        .unwrap_or(timeline_clip.clip.duration_seconds);
                    let clip_end = timeline_clip.start_time + clip_duration;

                    if playhead_seconds >= timeline_clip.start_time
                        && playhead_seconds < clip_end
                    {
                        let time_in_clip = playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                        let frame_in_clip = (time_in_clip * sample_rate as f64) as usize;

                        if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                            track_left += l;
                        }
                        if timeline_clip.clip.channels > 1 {
                            if let Some(r) = timeline_clip.clip.get_sample(frame_in_clip, 1) {
                                track_right += r;
                            }
                        } else {
                            // Mono clip - duplicate to right
                            if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                                track_right += l;
                            }
                        }
                    }
                }

                // Process MIDI clips through track synthesizer
                for timeline_midi_clip in &track_snap.midi_clips {
                    let clip_start_samples = (timeline_midi_clip.start_time * sample_rate as f64) as u64;
                    let clip_end_samples = clip_start_samples + timeline_midi_clip.clip.duration_samples;

                    // Check if clip is active at this frame
                    // Use <= for end boundary to ensure note-offs at exact clip end are triggered
                    if frame_idx as u64 >= clip_start_samples && (frame_idx as u64) <= clip_end_samples {
                        let frame_in_clip = frame_idx as u64 - clip_start_samples;

                        // Check for MIDI events at this exact frame
                        for event in &timeline_midi_clip.clip.events {
                            if event.timestamp_samples == frame_in_clip {
                                if let Ok(mut synth_manager) = self.track_synth_manager.lock() {
                                    match event.event_type {
                                        crate::midi::MidiEventType::NoteOn { note, velocity } => {
                                            synth_manager.note_on(track_snap.id, note, velocity);
                                        }
                                        crate::midi::MidiEventType::NoteOff { note, velocity: _ } => {
                                            synth_manager.note_off(track_snap.id, note);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Add synthesizer output
                if let Ok(mut synth_manager) = self.track_synth_manager.lock() {
                    let synth_sample = synth_manager.process_sample(track_snap.id);
                    track_left += synth_sample;
                    track_right += synth_sample;
                }

                // Apply track volume
                track_left *= track_snap.volume_gain;
                track_right *= track_snap.volume_gain;

                // Apply track pan
                track_left *= track_snap.pan_left;
                track_right *= track_snap.pan_right;

                // Process FX chain on this track
                let mut fx_left = track_left;
                let mut fx_right = track_right;

                if let Ok(effect_mgr) = self.effect_manager.lock() {
                    for effect_id in &track_snap.fx_chain {
                        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                            if let Ok(mut effect) = effect_arc.lock() {
                                let (out_l, out_r) = effect.process_frame(fx_left, fx_right);
                                fx_left = out_l;
                                fx_right = out_r;
                            }
                        }
                    }
                }

                // Accumulate to mix bus
                mix_left += fx_left;
                mix_right += fx_right;
            }

            // Apply master track processing
            let mut master_left = mix_left;
            let mut master_right = mix_right;

            if let Some(ref master_snap) = master_snapshot {
                // Apply master volume
                master_left *= master_snap.volume_gain;
                master_right *= master_snap.volume_gain;

                // Apply master pan
                let temp_l = master_left * master_snap.pan_left + master_right * master_snap.pan_left;
                let temp_r = master_left * master_snap.pan_right + master_right * master_snap.pan_right;
                master_left = temp_l;
                master_right = temp_r;

                // Process master FX chain
                if let Ok(effect_mgr) = self.effect_manager.lock() {
                    for effect_id in &master_snap.fx_chain {
                        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                            if let Ok(mut effect) = effect_arc.lock() {
                                let (out_l, out_r) = effect.process_frame(master_left, master_right);
                                master_left = out_l;
                                master_right = out_r;
                            }
                        }
                    }
                }
            }

            // Apply master limiter
            let (limited_left, limited_right) = if let Ok(mut limiter) = self.master_limiter.lock() {
                limiter.process_frame(master_left, master_right)
            } else {
                (master_left.clamp(-1.0, 1.0), master_right.clamp(-1.0, 1.0))
            };

            // Write to output buffer (interleaved stereo)
            output.push(limited_left);
            output.push(limited_right);

            // Progress logging every 10%
            if frame_idx % (total_frames / 10).max(1) == 0 {
                let progress = (frame_idx as f64 / total_frames as f64 * 100.0) as i32;
                eprintln!("   {}% complete...", progress);
            }
        }

        eprintln!("✅ [AudioGraph] Offline render complete: {} samples", output.len());
        output
    }

    /// Render a single track offline to a buffer of stereo f32 samples
    /// Returns interleaved stereo audio (L, R, L, R, ...)
    /// This renders the track in isolation without master bus processing
    pub fn render_track_offline(&self, track_id: u64, duration_seconds: f64) -> Vec<f32> {
        let sample_rate = TARGET_SAMPLE_RATE;
        let total_frames = (duration_seconds * sample_rate as f64) as usize;
        let mut output = Vec::with_capacity(total_frames * 2);

        eprintln!(
            "🎚️ [AudioGraph] Starting track {} offline render: {:.2}s ({} frames)",
            track_id, duration_seconds, total_frames
        );

        // Get track snapshot
        struct TrackSnapshot {
            audio_clips: Vec<TimelineClip>,
            midi_clips: Vec<TimelineMidiClip>,
            volume_gain: f32,
            pan_left: f32,
            pan_right: f32,
            fx_chain: Vec<u64>,
        }

        let track_snapshot = {
            let tm = self.track_manager.lock().expect("mutex poisoned");
            let mut snapshot = None;

            for track_arc in tm.get_all_tracks() {
                if let Ok(track) = track_arc.lock() {
                    if track.id == track_id {
                        snapshot = Some(TrackSnapshot {
                            audio_clips: track.audio_clips.clone(),
                            midi_clips: track.midi_clips.clone(),
                            volume_gain: track.get_gain(),
                            pan_left: track.get_pan_gains().0,
                            pan_right: track.get_pan_gains().1,
                            fx_chain: track.fx_chain.clone(),
                        });
                        break;
                    }
                }
            }

            snapshot
        };

        let Some(track_snap) = track_snapshot else {
            eprintln!("❌ [AudioGraph] Track {} not found for stem export", track_id);
            return output;
        };

        // Process each frame
        for frame_idx in 0..total_frames {
            let playhead_seconds = frame_idx as f64 / sample_rate as f64;

            let mut track_left = 0.0f32;
            let mut track_right = 0.0f32;

            // Mix all audio clips on this track
            for timeline_clip in &track_snap.audio_clips {
                let clip_duration = timeline_clip
                    .duration
                    .unwrap_or(timeline_clip.clip.duration_seconds);
                let clip_end = timeline_clip.start_time + clip_duration;

                if playhead_seconds >= timeline_clip.start_time && playhead_seconds < clip_end {
                    let time_in_clip =
                        playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                    let frame_in_clip = (time_in_clip * sample_rate as f64) as usize;

                    if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                        track_left += l;
                    }
                    if timeline_clip.clip.channels > 1 {
                        if let Some(r) = timeline_clip.clip.get_sample(frame_in_clip, 1) {
                            track_right += r;
                        }
                    } else {
                        // Mono clip - duplicate to right
                        if let Some(l) = timeline_clip.clip.get_sample(frame_in_clip, 0) {
                            track_right += l;
                        }
                    }
                }
            }

            // Process MIDI clips through track synthesizer
            for timeline_midi_clip in &track_snap.midi_clips {
                let clip_start_samples = (timeline_midi_clip.start_time * sample_rate as f64) as u64;
                let clip_end_samples =
                    clip_start_samples + timeline_midi_clip.clip.duration_samples;

                if frame_idx as u64 >= clip_start_samples && (frame_idx as u64) <= clip_end_samples
                {
                    let frame_in_clip = frame_idx as u64 - clip_start_samples;

                    for event in &timeline_midi_clip.clip.events {
                        if event.timestamp_samples == frame_in_clip {
                            if let Ok(mut synth_manager) = self.track_synth_manager.lock() {
                                match event.event_type {
                                    crate::midi::MidiEventType::NoteOn { note, velocity } => {
                                        synth_manager.note_on(track_id, note, velocity);
                                    }
                                    crate::midi::MidiEventType::NoteOff { note, velocity: _ } => {
                                        synth_manager.note_off(track_id, note);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Add synthesizer output
            if let Ok(mut synth_manager) = self.track_synth_manager.lock() {
                let synth_sample = synth_manager.process_sample(track_id);
                track_left += synth_sample;
                track_right += synth_sample;
            }

            // Apply track volume
            track_left *= track_snap.volume_gain;
            track_right *= track_snap.volume_gain;

            // Apply track pan
            track_left *= track_snap.pan_left;
            track_right *= track_snap.pan_right;

            // Process FX chain on this track
            let mut fx_left = track_left;
            let mut fx_right = track_right;

            if let Ok(effect_mgr) = self.effect_manager.lock() {
                for effect_id in &track_snap.fx_chain {
                    if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                        if let Ok(mut effect) = effect_arc.lock() {
                            let (out_l, out_r) = effect.process_frame(fx_left, fx_right);
                            fx_left = out_l;
                            fx_right = out_r;
                        }
                    }
                }
            }

            // Write to output buffer (interleaved stereo)
            output.push(fx_left);
            output.push(fx_right);

            // Progress logging every 25%
            if frame_idx % (total_frames / 4).max(1) == 0 && frame_idx > 0 {
                let progress = (frame_idx as f64 / total_frames as f64 * 100.0) as i32;
                eprintln!("   Track {} - {}% complete...", track_id, progress);
            }
        }

        eprintln!(
            "✅ [AudioGraph] Track {} offline render complete: {} samples",
            track_id,
            output.len()
        );
        output
    }

    /// Get track info for stem export (id, name, type)
    pub fn get_tracks_for_stem_export(&self) -> Vec<(u64, String, String)> {
        let mut tracks = Vec::new();

        if let Ok(tm) = self.track_manager.lock() {
            for track_arc in tm.get_all_tracks() {
                if let Ok(track) = track_arc.lock() {
                    // Skip master track
                    if track.track_type == crate::track::TrackType::Master {
                        continue;
                    }

                    let type_str = match track.track_type {
                        crate::track::TrackType::Audio => "audio",
                        crate::track::TrackType::Midi => "midi",
                        crate::track::TrackType::Return => "return",
                        crate::track::TrackType::Group => "group",
                        crate::track::TrackType::Master => "master",
                    };

                    tracks.push((track.id, track.name.clone(), type_str.to_string()));
                }
            }
        }

        tracks
    }

    /// Calculate the total duration of the project based on clips
    pub fn calculate_project_duration(&self) -> f64 {
        let mut max_end_time = 0.0f64;

        // Check all tracks for clips
        if let Ok(tm) = self.track_manager.lock() {
            for track_arc in tm.get_all_tracks() {
                if let Ok(track) = track_arc.lock() {
                    // Audio clips
                    for clip in &track.audio_clips {
                        let clip_end = clip.start_time + clip.duration.unwrap_or(clip.clip.duration_seconds);
                        if clip_end > max_end_time {
                            max_end_time = clip_end;
                        }
                    }
                    // MIDI clips
                    for clip in &track.midi_clips {
                        let clip_end = clip.start_time + clip.clip.duration_seconds();
                        if clip_end > max_end_time {
                            max_end_time = clip_end;
                        }
                    }
                }
            }
        }

        // Add a small tail for reverb/delay to decay (1 second)
        max_end_time + 1.0
    }

    // --- Audio Device Management ---

    /// Get list of available audio output devices
    /// Returns: Vec of (id, name, is_default)
    pub fn get_output_devices() -> Vec<(String, String, bool)> {
        let host = cpal::default_host();
        let default_name = host.default_output_device()
            .and_then(|d| d.name().ok());

        match host.output_devices() {
            Ok(devices) => {
                devices.filter_map(|d| {
                    d.name().ok().map(|name| {
                        let is_default = default_name.as_ref() == Some(&name);
                        (name.clone(), name, is_default)
                    })
                }).collect()
            }
            Err(e) => {
                eprintln!("❌ [AudioGraph] Failed to enumerate output devices: {}", e);
                Vec::new()
            }
        }
    }

    /// Get list of available audio input devices
    /// Returns: Vec of (id, name, is_default)
    pub fn get_input_devices() -> Vec<(String, String, bool)> {
        let host = cpal::default_host();
        let default_name = host.default_input_device()
            .and_then(|d| d.name().ok());

        match host.input_devices() {
            Ok(devices) => {
                devices.filter_map(|d| {
                    d.name().ok().map(|name| {
                        let is_default = default_name.as_ref() == Some(&name);
                        (name.clone(), name, is_default)
                    })
                }).collect()
            }
            Err(e) => {
                eprintln!("❌ [AudioGraph] Failed to enumerate input devices: {}", e);
                Vec::new()
            }
        }
    }

    /// Get current sample rate
    pub fn get_sample_rate() -> u32 {
        TARGET_SAMPLE_RATE
    }
}

// ============================================================================
// MIDI SERIALIZATION HELPERS
// ============================================================================

/// Convert MIDI events (NoteOn/NoteOff pairs) to MidiNoteData for serialization
fn convert_midi_events_to_notes(
    events: &[crate::midi::MidiEvent],
    sample_rate: u32,
) -> Vec<crate::project::MidiNoteData> {
    use crate::midi::MidiEventType;
    use crate::project::MidiNoteData;
    use std::collections::HashMap;

    // Track active notes: note_number -> (start_time_seconds, velocity)
    let mut active_notes: HashMap<u8, (f64, u8)> = HashMap::new();
    let mut notes = Vec::new();

    for event in events {
        let time_seconds = event.timestamp_samples as f64 / sample_rate as f64;
        match event.event_type {
            MidiEventType::NoteOn { note, velocity } if velocity > 0 => {
                active_notes.insert(note, (time_seconds, velocity));
            }
            MidiEventType::NoteOff { note, .. } => {
                if let Some((start, vel)) = active_notes.remove(&note) {
                    notes.push(MidiNoteData {
                        note,
                        velocity: vel,
                        start_time: start,
                        duration: time_seconds - start,
                    });
                }
            }
            // NoteOn with velocity 0 is treated as NoteOff
            MidiEventType::NoteOn { note, velocity: 0 } => {
                if let Some((start, vel)) = active_notes.remove(&note) {
                    notes.push(MidiNoteData {
                        note,
                        velocity: vel,
                        start_time: start,
                        duration: time_seconds - start,
                    });
                }
            }
            _ => {}
        }
    }

    // Sort by start time for consistency
    notes.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap_or(std::cmp::Ordering::Equal));
    notes
}

/// Reconstruct MidiClip from serialized MidiNoteData
fn reconstruct_midi_clip_from_notes(
    notes: &[crate::project::MidiNoteData],
    sample_rate: u32,
    saved_duration: Option<f64>,
) -> crate::midi::MidiClip {
    use crate::midi::{MidiClip, MidiEvent, MidiEventType};

    let mut events = Vec::new();

    for note in notes {
        let start_samples = (note.start_time * sample_rate as f64) as u64;
        let end_samples = ((note.start_time + note.duration) * sample_rate as f64) as u64;

        events.push(MidiEvent::new(
            MidiEventType::NoteOn { note: note.note, velocity: note.velocity },
            start_samples,
        ));
        events.push(MidiEvent::new(
            MidiEventType::NoteOff { note: note.note, velocity: 0 },
            end_samples,
        ));
    }

    // Sort events by timestamp
    events.sort_by_key(|e| e.timestamp_samples);

    // Use saved duration if available, otherwise calculate from notes
    let duration_samples = if let Some(dur) = saved_duration {
        (dur * sample_rate as f64) as u64
    } else {
        // Calculate duration as the end of the last note
        notes.iter()
            .map(|n| ((n.start_time + n.duration) * sample_rate as f64) as u64)
            .max()
            .unwrap_or(0)
    };

    // Apply snap_to_bar to ensure proper alignment
    let snapped_duration = MidiClip::snap_to_bar(duration_samples, sample_rate);

    MidiClip {
        events,
        duration_samples: snapped_duration,
        sample_rate,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio_file::AudioClip;

    fn create_test_clip(duration: f64) -> AudioClip {
        let frames = (duration * TARGET_SAMPLE_RATE as f64) as usize;
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

