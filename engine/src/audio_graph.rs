/// Audio graph and playback engine
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::audio_input::AudioInputManager;
use crate::recorder::Recorder;
use crate::midi::MidiClip;
use crate::midi_input::MidiInputManager;
use crate::midi_recorder::MidiRecorder;
use crate::synth::{Synthesizer, TrackSynthManager};
use crate::track::{ClipId, TimelineClip, TimelineMidiClip, TrackId, TrackManager};  // Import from track module
use crate::effects::{Effect, EffectManager, Limiter};  // Import from effects module
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

/// Transport state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportState {
    Stopped,
    Playing,
    Paused,
}

/// The main audio graph that manages playback
pub struct AudioGraph {
    /// All audio clips on the timeline (legacy - will migrate to tracks)
    clips: Arc<Mutex<Vec<TimelineClip>>>,
    /// All MIDI clips on the timeline (legacy - will migrate to tracks)
    midi_clips: Arc<Mutex<Vec<TimelineMidiClip>>>,
    /// Current playhead position in samples
    playhead_samples: Arc<AtomicU64>,
    /// Transport state
    state: Arc<Mutex<TransportState>>,
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
    /// Built-in synthesizer
    pub synthesizer: Arc<Mutex<Synthesizer>>,

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
            state: Arc::new(Mutex::new(TransportState::Stopped)),
            stream: None,
            next_clip_id: Arc::new(Mutex::new(0)),
            input_manager: Arc::new(Mutex::new(input_manager)),
            recorder: Arc::new(Recorder::new()),
            midi_input_manager: Arc::new(Mutex::new(midi_input_manager)),
            midi_recorder: Arc::new(Mutex::new(midi_recorder)),
            synthesizer: Arc::new(Mutex::new(Synthesizer::new())),
            track_manager: Arc::new(Mutex::new(track_manager)),
            effect_manager: Arc::new(Mutex::new(effect_manager)),
            master_limiter: Arc::new(Mutex::new(master_limiter)),
            track_synth_manager: Arc::new(Mutex::new(TrackSynthManager::new(TARGET_SAMPLE_RATE as f32))),
        };

        // Create audio stream immediately (prevents deadlock on first play)
        eprintln!("🔊 [AudioGraph] Creating audio stream during initialization...");
        let stream = graph.create_audio_stream()?;
        // Pause immediately - stream will be started on play()
        stream.pause()?;
        graph.stream = Some(stream);
        eprintln!("✅ [AudioGraph] Audio stream created and paused");

        Ok(graph)
    }

    /// Add a clip to the timeline
    pub fn add_clip(&self, clip: Arc<AudioClip>, start_time: f64) -> ClipId {
        let mut clips = self.clips.lock().unwrap();
        let id = {
            let mut next_id = self.next_clip_id.lock().unwrap();
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
        let mut midi_clips = self.midi_clips.lock().unwrap();
        let id = {
            let mut next_id = self.next_clip_id.lock().unwrap();
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
            let mut next_id = self.next_clip_id.lock().unwrap();
            let id = *next_id;
            *next_id += 1;
            id
        };

        let track_manager = self.track_manager.lock().unwrap();
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock().unwrap();
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
    pub fn add_midi_clip_to_track(&self, track_id: TrackId, clip: Arc<MidiClip>, start_time: f64) -> Option<ClipId> {
        let id = {
            let mut next_id = self.next_clip_id.lock().unwrap();
            let id = *next_id;
            *next_id += 1;
            id
        };

        let track_manager = self.track_manager.lock().unwrap();
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock().unwrap();
            track.midi_clips.push(TimelineMidiClip {
                id,
                clip,
                start_time,
                track_id: Some(track_id),
            });
            Some(id)
        } else {
            None
        }
    }

    /// Remove a clip from the timeline (audio or MIDI)
    pub fn remove_clip(&self, clip_id: ClipId) -> bool {
        // Try to remove from audio clips
        {
            let mut clips = self.clips.lock().unwrap();
            if let Some(pos) = clips.iter().position(|c| c.id == clip_id) {
                clips.remove(pos);
                return true;
            }
        }

        // Try to remove from MIDI clips
        {
            let mut midi_clips = self.midi_clips.lock().unwrap();
            if let Some(pos) = midi_clips.iter().position(|c| c.id == clip_id) {
                midi_clips.remove(pos);
                return true;
            }
        }

        false
    }

    /// Remove all MIDI clips belonging to a specific track
    pub fn remove_midi_clips_for_track(&self, track_id: TrackId) -> usize {
        let mut midi_clips = self.midi_clips.lock().unwrap();
        let initial_count = midi_clips.len();
        midi_clips.retain(|clip| clip.track_id != Some(track_id));
        let removed_count = initial_count - midi_clips.len();
        removed_count
    }

    /// Get the current playhead position in seconds
    pub fn get_playhead_position(&self) -> f64 {
        let samples = self.playhead_samples.load(Ordering::SeqCst);
        samples as f64 / TARGET_SAMPLE_RATE as f64
    }

    /// Seek to a specific position in seconds
    pub fn seek(&self, position_seconds: f64) {
        let samples = (position_seconds * TARGET_SAMPLE_RATE as f64) as u64;
        self.playhead_samples.store(samples, Ordering::SeqCst);
    }

    /// Get current transport state
    pub fn get_state(&self) -> TransportState {
        *self.state.lock().unwrap()
    }

    /// Start playback
    pub fn play(&mut self) -> anyhow::Result<()> {
        {
            let mut state = self.state.lock().unwrap();
            if *state == TransportState::Playing {
                return Ok(()); // Already playing
            }
            *state = TransportState::Playing;
        }

        // Stream is pre-created during initialization
        if let Some(stream) = &self.stream {
            stream.play()?;
        } else {
            return Err(anyhow::anyhow!("Audio stream not initialized"));
        }

        Ok(())
    }

    /// Pause playback (keeps position)
    pub fn pause(&mut self) -> anyhow::Result<()> {
        {
            let mut state = self.state.lock().unwrap();
            *state = TransportState::Paused;
        }

        if let Some(stream) = &self.stream {
            stream.pause()?;
        }

        Ok(())
    }

    /// Stop playback (resets to start)
    pub fn stop(&mut self) -> anyhow::Result<()> {
        eprintln!("⏹️  [AudioGraph] stop() called - resetting playhead and metronome");

        {
            let mut state = self.state.lock().unwrap();
            *state = TransportState::Stopped;
        }

        if let Some(stream) = &self.stream {
            stream.pause()?;
        }

        // Reset playhead to start
        let old_playhead = self.playhead_samples.swap(0, Ordering::SeqCst);
        eprintln!("   Playhead reset: {} → 0", old_playhead);

        // Reset metronome beat position
        self.recorder.reset_metronome();

        Ok(())
    }

    /// Create the audio output stream
    fn create_audio_stream(&self) -> anyhow::Result<cpal::Stream> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow::anyhow!("No output device available"))?;

        let config = device.default_output_config()?;

        // Clone Arcs for the audio callback
        let clips = self.clips.clone();
        let midi_clips = self.midi_clips.clone();
        let playhead_samples = self.playhead_samples.clone();
        let state = self.state.clone();
        let input_manager = self.input_manager.clone();
        let recorder_refs = self.recorder.get_callback_refs();
        let synthesizer = self.synthesizer.clone();

        // M4: Clone track and effect managers
        let track_manager = self.track_manager.clone();
        let effect_manager = self.effect_manager.clone();
        let master_limiter = self.master_limiter.clone();

        // M6: Clone track synth manager
        let track_synth_manager = self.track_synth_manager.clone();

        let stream = device.build_output_stream(
            &config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                // Check if we should be playing
                let is_playing = {
                    let s = state.lock().unwrap();
                    *s == TransportState::Playing
                };

                if !is_playing {
                    // Even when not playing, we might be recording
                    // Process metronome and recording
                    let frames = data.len() / 2;
                    
                    // Log channel info once
                    static LOGGED_CHANNELS: AtomicBool = AtomicBool::new(false);

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

                        // Output only metronome when not playing
                        data[frame_idx * 2] = met_left;
                        data[frame_idx * 2 + 1] = met_right;
                    }
                    return;
                }

                // Calculate how many frames we need (stereo = 2 samples per frame)
                let frames = data.len() / 2;
                let current_playhead = playhead_samples.load(Ordering::SeqCst);

                // Get clips (lock briefly)
                let clips_snapshot = {
                    let clips_lock = clips.lock().unwrap();
                    clips_lock.clone()
                };

                // Get MIDI clips (lock briefly)
                let midi_clips_snapshot = {
                    let midi_clips_lock = midi_clips.lock().unwrap();
                    midi_clips_lock.clone()
                };

                // Process MIDI events for this buffer
                // We need to check all MIDI clips for events in this time range
                for timeline_midi_clip in &midi_clips_snapshot {
                    let clip_start_samples = (timeline_midi_clip.start_time * TARGET_SAMPLE_RATE as f64) as u64;

                    // Get events for this buffer range
                    let buffer_start = current_playhead;
                    let buffer_end = current_playhead + frames as u64;

                    // Check if clip is active in this buffer
                    let clip_end_samples = clip_start_samples + timeline_midi_clip.clip.duration_samples;
                    if clip_end_samples <= buffer_start || clip_start_samples >= buffer_end {
                        continue; // Clip not active in this buffer
                    }

                    // Process events within the clip
                    for event in &timeline_midi_clip.clip.events {
                        // Convert event timestamp from clip-relative to absolute timeline
                        let event_absolute_samples = clip_start_samples + event.timestamp_samples;

                        // Check if event is in this buffer
                        if event_absolute_samples >= buffer_start && event_absolute_samples < buffer_end {
                            // Send event to synthesizer
                            if let Ok(mut synth) = synthesizer.lock() {
                                synth.process_event(event);
                            }
                        }
                    }
                }

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

                // DEBUG: Log track info periodically (every ~2 seconds)
                static DEBUG_COUNTER: AtomicUsize = AtomicUsize::new(0);
                let counter = DEBUG_COUNTER.fetch_add(1, Ordering::Relaxed);
                // Print every ~2 seconds (48000 samples/sec, 512 frames/buffer = ~94 buffers/sec, so every 188 buffers)
                if counter % 188 == 0 {
                    eprintln!("\n🎵 [AudioCallback] Processing {} tracks (playhead: {:.2}s)",
                        track_snapshots.len(), current_playhead as f64 / TARGET_SAMPLE_RATE as f64);
                    for snap in &track_snapshots {
                        eprintln!("   - Track {}: {} audio clips, {} MIDI clips, vol={:.2}, pan: L={:.3} R={:.3}",
                            snap.id, snap.audio_clips.len(), snap.midi_clips.len(),
                            snap.volume_gain, snap.pan_left, snap.pan_right);
                    }
                    if let Some(ref master) = master_snapshot {
                        eprintln!("   - Master: vol={:.2}, pan: L={:.3} R={:.3}",
                            master.volume_gain, master.pan_left, master.pan_right);
                    }
                }

                // Process each frame (using snapshots - NO LOCKS!)
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

                        // Add per-track synthesizer output (M6)
                        if let Ok(mut synth_manager) = track_synth_manager.lock() {
                            let synth_sample = synth_manager.process_sample(track_snap.id);
                            track_left += synth_sample;
                            track_right += synth_sample;
                        }

                        // Apply track volume (from snapshot)
                        track_left *= track_snap.volume_gain;
                        track_right *= track_snap.volume_gain;

                        // Apply track pan (from snapshot) - stereo balance approach
                        track_left *= track_snap.pan_left;
                        track_right *= track_snap.pan_right;

                        // Process FX chain on this track
                        let mut fx_left = track_left;
                        let mut fx_right = track_right;

                        if let Ok(effect_mgr) = effect_manager.lock() {
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

                    // Add synthesizer output (MIDI playback)
                    // Note: MIDI events are processed above, synth generates audio here
                    if let Ok(mut synth) = synthesizer.lock() {
                        let synth_sample = synth.process_sample();
                        mix_left += synth_sample;
                        mix_right += synth_sample;
                    }

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

                    // Process recording and get metronome output
                    let (met_left, met_right) = recorder_refs.process_frame(input_left, input_right, true);

                    // Mix playback + metronome
                    mix_left += met_left;
                    mix_right += met_right;

                    // Apply master track processing (using snapshot - no locks!)
                    let mut master_left = mix_left;
                    let mut master_right = mix_right;

                    if let Some(ref master_snap) = master_snapshot {
                        // Apply master volume
                        master_left *= master_snap.volume_gain;
                        master_right *= master_snap.volume_gain;

                        // Apply master pan - stereo balance approach
                        master_left *= master_snap.pan_left;
                        master_right *= master_snap.pan_right;

                        // Process master FX chain
                        if let Ok(effect_mgr) = effect_manager.lock() {
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

                    // Apply master limiter to prevent clipping
                    let (limited_left, limited_right) = if let Ok(mut limiter) = master_limiter.lock() {
                        limiter.process_frame(master_left, master_right)
                    } else {
                        (master_left.clamp(-1.0, 1.0), master_right.clamp(-1.0, 1.0))
                    };

                    // Write to output buffer (interleaved stereo)
                    data[frame_idx * 2] = limited_left;
                    data[frame_idx * 2 + 1] = limited_right;
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
        self.clips.lock().unwrap().len()
    }

    /// Get number of MIDI clips
    pub fn midi_clip_count(&self) -> usize {
        self.midi_clips.lock().unwrap().len()
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

        // Get all tracks
        let track_manager = self.track_manager.lock().unwrap();
        let effect_manager = self.effect_manager.lock().unwrap();

        let all_tracks = track_manager.get_all_tracks();
        let tracks_data: Vec<TrackData> = all_tracks.iter().map(|track_arc| {
            let track = track_arc.lock().unwrap();

            // Get effect chain for this track
            let fx_chain: Vec<EffectData> = track.fx_chain.iter().filter_map(|effect_id| {
                // Get effect from effect manager
                if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                    let effect = effect_arc.lock().unwrap();
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
                        ET::VST3(vst3) => {
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

            // Get clips on this track
            let clips_data: Vec<ClipData> = track.audio_clips.iter().map(|timeline_clip| {
                ClipData {
                    id: timeline_clip.id,
                    start_time: timeline_clip.start_time,
                    offset: timeline_clip.offset,
                    duration: timeline_clip.duration,
                    audio_file_id: Some(timeline_clip.id), // Simplified: use clip ID as file ID
                    midi_notes: None,
                }
            }).collect();
            // TODO: Add MIDI clip serialization
            // MIDI clips use Note On/Note Off events, need to pair them into notes with duration

            TrackData {
                id: track.id,
                name: track.name.clone(),
                track_type: format!("{:?}", track.track_type), // "Audio", "MIDI", etc.
                volume_db: track.volume_db,
                pan: track.pan,
                mute: track.mute,
                solo: track.solo,
                armed: track.armed,
                clips: clips_data,
                fx_chain,
            }
        }).collect();

        // Collect audio files (simplified - get from global timeline for now)
        let clips_lock = self.clips.lock().unwrap();
        let audio_files: Vec<AudioFileData> = clips_lock.iter().enumerate().map(|(idx, timeline_clip)| {
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

        ProjectData {
            version: "1.0".to_string(),
            name: project_name,
            tempo: 120.0, // TODO: Get from actual tempo setting
            sample_rate: TARGET_SAMPLE_RATE,
            time_sig_numerator: 4,
            time_sig_denominator: 4,
            tracks: tracks_data,
            audio_files,
        }
    }

    /// Restore state from ProjectData (for loading)
    pub fn restore_from_project_data(&mut self, project_data: crate::project::ProjectData) -> anyhow::Result<()> {
        use crate::project::*;
        use crate::effects::*;
        use crate::track::TrackType;

        // Stop playback
        let _ = self.stop();

        // Clear existing tracks (except master will be kept and updated)
        {
            let mut track_manager = self.track_manager.lock().unwrap();
            let mut effect_manager = self.effect_manager.lock().unwrap();

            // Get all track IDs except master (ID 0)
            let all_tracks = track_manager.get_all_tracks();
            let track_ids_to_remove: Vec<u64> = all_tracks.iter()
                .filter_map(|track_arc| {
                    let track = track_arc.lock().unwrap();
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

        // Recreate tracks and effects
        for track_data in project_data.tracks {
            let track_manager = self.track_manager.lock().unwrap();
            let mut effect_manager = self.effect_manager.lock().unwrap();

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
                    let mut master = master_track_arc.lock().unwrap();
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
                let mut tm = self.track_manager.lock().unwrap();
                tm.create_track(track_type, track_data.name.clone())
            };

            // Update track properties
            {
                let tm = self.track_manager.lock().unwrap();
                if let Some(track_arc) = tm.get_track(track_id) {
                    let mut track = track_arc.lock().unwrap();
                    track.volume_db = track_data.volume_db;
                    track.pan = track_data.pan;
                    track.mute = track_data.mute;
                    track.solo = track_data.solo;
                    track.armed = track_data.armed;
                }
            }

            // Recreate effects on this track
            for effect_data in &track_data.fx_chain {
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
                let tm = self.track_manager.lock().unwrap();
                if let Some(track_arc) = tm.get_track(track_id) {
                    let mut track = track_arc.lock().unwrap();
                    track.fx_chain.push(effect_id);
                }
            }

            eprintln!("   - Created track '{}' (type: {:?}, {} effects)",
                track_data.name, track_type, track_data.fx_chain.len());
        }

        // TODO: Restore clips to tracks
        // This is deferred because we need access to the loaded AudioClip objects
        // which are handled in the API layer

        Ok(())
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

