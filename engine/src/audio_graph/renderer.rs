/// Real-time audio render callback — runs on the audio thread
use super::{AudioGraph, TransportState, interpolate_automation_gain};
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::track::{AutomationPoint, TimelineClip, TimelineMidiClip, TrackId};
use crate::effects::Effect;
use std::collections::HashMap;
use std::sync::atomic::Ordering;

#[cfg(not(target_arch = "wasm32"))]
use cpal::traits::DeviceTrait;

impl AudioGraph {
    /// Create the audio output stream - native only
    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) fn create_audio_stream(&self) -> anyhow::Result<cpal::Stream> {
        use cpal::SupportedBufferSize;
        use cpal::traits::HostTrait;

        // Helper to find device by name from a host
        fn find_device_in_host<H: HostTrait>(host: &H, name: &str) -> Option<H::Device> {
            host.output_devices().ok()?.find(|d| {
                d.name().ok().as_ref().is_some_and(|n| n == name)
            })
        }

        // Check if a specific device is selected
        let selected_name = self.selected_output_device.lock()
            .clone();

        // Determine if we should use ASIO host and get the device
        #[cfg(all(windows, feature = "asio"))]
        let device = if let Some(ref name) = selected_name {
            if name.starts_with("[ASIO] ") {
                let actual_name = name.strip_prefix("[ASIO] ").unwrap();
                eprintln!("🔊 [AudioGraph] Attempting to use ASIO device: {}", actual_name);

                match cpal::host_from_id(cpal::HostId::Asio) {
                    Ok(asio_host) => {
                        match find_device_in_host(&asio_host, actual_name) {
                            Some(d) => {
                                eprintln!("🔊 [AudioGraph] Using ASIO device: {}", actual_name);
                                d
                            }
                            None => {
                                eprintln!("⚠️ [AudioGraph] ASIO device '{}' not found, falling back to default", actual_name);
                                cpal::default_host().default_output_device()
                                    .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                            }
                        }
                    }
                    Err(e) => {
                        eprintln!("⚠️ [AudioGraph] Failed to initialize ASIO host: {}, falling back to default", e);
                        cpal::default_host().default_output_device()
                            .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                    }
                }
            } else {
                // Non-ASIO device, use default host
                let host = cpal::default_host();
                match find_device_in_host(&host, name) {
                    Some(d) => {
                        eprintln!("🔊 [AudioGraph] Using selected output device: {}", name);
                        d
                    }
                    None => {
                        eprintln!("⚠️ [AudioGraph] Selected device '{}' not found, using default", name);
                        host.default_output_device()
                            .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                    }
                }
            }
        } else {
            cpal::default_host().default_output_device()
                .ok_or_else(|| anyhow::anyhow!("No output device available"))?
        };

        #[cfg(not(all(windows, feature = "asio")))]
        let device = {
            let host = cpal::default_host();
            if let Some(ref name) = selected_name {
                if let Some(d) = find_device_in_host(&host, name) {
                    eprintln!("🔊 [AudioGraph] Using selected output device: {name}");
                    d
                } else {
                    eprintln!("⚠️ [AudioGraph] Selected device '{name}' not found, using default");
                    host.default_output_device()
                        .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                }
            } else {
                host.default_output_device()
                    .ok_or_else(|| anyhow::anyhow!("No output device available"))?
            }
        };

        // Log device info
        if let Ok(name) = device.name() {
            eprintln!("🔊 [AudioGraph] Using device: {name}");
        }

        // Track snapshot data extracted from locked tracks for lock-free audio processing.
        // Defined at function scope so pre-allocated Vec<TrackSnapshot> can reference it.
        #[allow(clippy::items_after_statements)]
        struct TrackSnapshot {
            id: u64,
            audio_clips: Vec<TimelineClip>,
            midi_clips: Vec<TimelineMidiClip>,
            volume_gain: f32, // Static volume (used when no automation)
            pan_left: f32,
            pan_right: f32,
            muted: bool,
            soloed: bool,
            fx_chain: Vec<u64>,
            volume_automation: Vec<AutomationPoint>, // For per-frame interpolation
            armed: bool,
            input_monitoring: bool,
            input_channel: u32,
            is_audio_track: bool,
            monitoring_fade_gain: f64,
        }

        let supported_config = device.default_output_config()?;
        eprintln!("🔊 [AudioGraph] Device config: {supported_config:?}");

        // Get preferred buffer size
        let preferred_samples = self.preferred_buffer_size.lock()
            .samples();

        // Check if device supports our preferred buffer size
        let buffer_size = match supported_config.buffer_size() {
            SupportedBufferSize::Range { min, max } => {
                // Handle invalid range (e.g., iOS simulator reports [0-0])
                if *max == 0 {
                    eprintln!("🔊 [AudioGraph] Buffer size: device reports invalid range [{min}-{max}], using default");
                    None
                } else {
                    let clamped = preferred_samples.clamp(*min, *max);
                    eprintln!("🔊 [AudioGraph] Buffer size: requested={preferred_samples}, device range=[{min}-{max}], using={clamped}");
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

        // Latency test
        let latency_test = self.latency_test.clone();

        // Pre-allocate reusable buffers for the audio callback to avoid
        // per-callback allocations on the audio thread
        let mut snapshot_buf: Vec<TrackSnapshot> = Vec::with_capacity(16);
        let mut peak_buf: HashMap<TrackId, (f32, f32)> = HashMap::with_capacity(16);

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

                    // Get current playhead for latency test sample counting
                    let current_playhead = playhead_samples.load(Ordering::SeqCst);

                    // Lock synth manager once for the entire buffer
                    let mut synth_guard = Some(track_synth_manager.lock());

                    for frame_idx in 0..frames {
                        // Get input samples (if recording)
                        // Use try_lock() to avoid deadlock - if lock is held by API thread, just skip this frame
                        let (input_left, input_right) = if let Some(input_mgr) = input_manager.try_lock() {
                            let channels = input_mgr.get_input_channels();

                            if channels == 1 {
                                // Mono input: read 1 sample and duplicate to both channels
                                if let Some(samples) = input_mgr.read_samples(1) {
                                    let mono_sample = samples.first().copied().unwrap_or(0.0);
                                    (mono_sample, mono_sample)
                                } else {
                                    (0.0, 0.0)
                                }
                            } else {
                                // Stereo input: read 2 samples
                                if let Some(samples) = input_mgr.read_samples(2) {
                                    (samples.first().copied().unwrap_or(0.0),
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
                        let (met_left, met_right) = recorder_refs.process_frame(input_left, input_right, false, 0.0);

                        // Start with metronome output
                        let mut out_left = met_left;
                        let mut out_right = met_right;
                        let mut master_peak_left = 0.0f32;
                        let mut master_peak_right = 0.0f32;

                        // Process each track (synth + VST3 instruments + volume/pan + metering)
                        // This is necessary for:
                        // 1. Per-track synthesizer output from MIDI input
                        // 2. VST3 instruments that need continuous process() calls
                        // 3. Track-level metering for level meters in UI
                        { let effect_mgr = effect_manager.lock();
                            { let tm = track_manager.lock();
                                let has_solo = tm.has_solo();
                                for track_arc in tm.get_all_tracks() {
                                    { let mut track = track_arc.lock();
                                        // Skip master track in per-track processing
                                        if track.track_type == crate::track::TrackType::Master {
                                            continue;
                                        }

                                        // Get per-track synth output FIRST
                                        let mut track_left = 0.0f32;
                                        let mut track_right = 0.0f32;

                                        if let Some(ref mut synth_manager) = synth_guard {
                                            let (synth_left, synth_right) = synth_manager.process_sample_stereo(track.id);
                                            track_left += synth_left;
                                            track_right += synth_right;
                                        }

                                        // Input monitoring: mix live input for armed audio tracks
                                        // Uses fade gain for smooth transitions (20ms ramp avoids clicks)
                                        {
                                            let should_monitor = track.armed && track.input_monitoring
                                                && track.track_type == crate::track::TrackType::Audio;
                                            let target = if should_monitor { 1.0f64 } else { 0.0f64 };

                                            #[allow(clippy::float_cmp)]
                                            if track.monitoring_fade_gain != target {
                                                let step = 1.0 / (0.020 * f64::from(TARGET_SAMPLE_RATE));
                                                if target > track.monitoring_fade_gain {
                                                    track.monitoring_fade_gain = (track.monitoring_fade_gain + step).min(1.0);
                                                } else {
                                                    track.monitoring_fade_gain = (track.monitoring_fade_gain - step).max(0.0);
                                                }
                                            }

                                            if track.monitoring_fade_gain > 0.0 {
                                                let ch = track.input_channel as usize;
                                                let input_sample = if ch == 0 { input_left } else { input_right };
                                                track_left += input_sample * track.monitoring_fade_gain as f32;
                                                track_right += input_sample * track.monitoring_fade_gain as f32;
                                            }
                                        }

                                        // Handle mute/solo
                                        if track.mute {
                                            // Still process FX to keep VST3 alive, but don't mix
                                            for effect_id in &track.fx_chain {
                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                    { let mut effect = effect_arc.lock();
                                                        let _ = effect.process_frame(0.0, 0.0);
                                                    }
                                                }
                                            }
                                            // Update peaks to 0 for muted track
                                            if frame_idx == frames - 1 {
                                                track.update_peaks(0.0, 0.0);
                                            }
                                            continue;
                                        }
                                        if has_solo && !track.solo {
                                            // Still process FX to keep VST3 alive
                                            for effect_id in &track.fx_chain {
                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                    { let mut effect = effect_arc.lock();
                                                        let _ = effect.process_frame(0.0, 0.0);
                                                    }
                                                }
                                            }
                                            // Update peaks to 0 for non-soloed track
                                            if frame_idx == frames - 1 {
                                                track.update_peaks(0.0, 0.0);
                                            }
                                            continue;
                                        }

                                        // Process FX chain for this track (instruments generate audio from MIDI)
                                        for effect_id in &track.fx_chain {
                                            // Skip bypassed effects (audio passes through unchanged)
                                            if effect_mgr.is_bypassed(*effect_id) {
                                                continue;
                                            }
                                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                { let mut effect = effect_arc.lock();
                                                    let (fx_l, fx_r) = effect.process_frame(track_left, track_right);
                                                    track_left = fx_l;
                                                    track_right = fx_r;
                                                }
                                            }
                                        }

                                        // Apply track volume and pan AFTER FX chain
                                        let volume_gain = track.get_gain();
                                        let (pan_left, pan_right) = track.get_pan_gains();

                                        track_left *= volume_gain * pan_left;
                                        track_right *= volume_gain * pan_right;

                                        // Update track peak levels for metering
                                        // This allows UI to show level meters even when stopped
                                        let current_peak_left = track.peak_left;
                                        let current_peak_right = track.peak_right;
                                        track.update_peaks(
                                            current_peak_left.max(track_left.abs()),
                                            current_peak_right.max(track_right.abs())
                                        );

                                        // Mix into output
                                        out_left += track_left;
                                        out_right += track_right;
                                    }
                                }

                                // Update master track peaks
                                master_peak_left = master_peak_left.max(out_left.abs());
                                master_peak_right = master_peak_right.max(out_right.abs());

                                // Update master track peaks at end of buffer
                                if frame_idx == frames - 1 {
                                    let master_arc = tm.get_master_track();
                                    { let mut master = master_arc.lock();
                                        master.update_peaks(master_peak_left, master_peak_right);
                                    };
                                }
                            }
                        }

                        // Process latency test (if running)
                        let sample_idx = current_playhead.wrapping_add(frame_idx as u64);
                        latency_test.process_input(input_left, sample_idx);
                        let test_tone = latency_test.generate_output(sample_idx);
                        out_left += test_tone;
                        out_right += test_tone;

                        // Mix library preview audio (independent of transport)
                        let (preview_left, preview_right) = crate::api::preview::preview_process_sample();
                        out_left += preview_left;
                        out_right += preview_right;

                        // Output metronome + synths + VST3 + preview when not playing
                        data[frame_idx * 2] = out_left;
                        data[frame_idx * 2 + 1] = out_right;
                    }
                    return;
                }

                // frames already calculated at top of callback
                let current_playhead = playhead_samples.load(Ordering::SeqCst);

                // Get clips (lock briefly) - keeping for potential future use
                let _clips_snapshot = {
                    let clips_lock = clips.lock();
                    clips_lock.clone()
                };

                // Get MIDI clips (lock briefly) - kept for potential future use
                let _midi_clips_snapshot = {
                    let midi_clips_lock = midi_clips.lock();
                    midi_clips_lock.clone()
                };

                // Get current tempo for playback scaling
                // Timeline positions are tempo-dependent: at 120 BPM, 1 timeline second = 1 real second
                // At other tempos, the playhead must advance faster/slower through the timeline
                let current_tempo = *recorder_refs.tempo.lock();
                let tempo_ratio = current_tempo / 120.0;

                // NOTE: Legacy MIDI clip processing removed - all MIDI now handled per-track

                // M5.5: Track-based mixing (replaces legacy clip mixing)

                // Reuse pre-allocated buffers (clear without deallocating)
                snapshot_buf.clear();
                peak_buf.clear();

                let (has_solo, master_snapshot) = { let tm = track_manager.lock();
                    let has_solo_flag = tm.has_solo();
                    let all_tracks = tm.get_all_tracks();
                    let mut master_snap = None;

                    for track_arc in all_tracks {
                        { let track = track_arc.lock();
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
                                volume_automation: track.volume_automation.clone(),
                                armed: track.armed,
                                input_monitoring: track.input_monitoring,
                                input_channel: track.input_channel,
                                is_audio_track: track.track_type == crate::track::TrackType::Audio,
                                monitoring_fade_gain: track.monitoring_fade_gain,
                            };

                            if track.track_type == crate::track::TrackType::Master {
                                master_snap = Some(snap);
                            } else {
                                snapshot_buf.push(snap);
                            }
                        }
                    }

                    (has_solo_flag, master_snap)
                }; // All locks released here!
                let mut master_peak_left = 0.0f32;
                let mut master_peak_right = 0.0f32;

                // OPTIMIZATION: Lock synth manager ONCE before the frame loop
                // This prevents lock contention that causes audio dropouts
                let mut synth_guard = Some(track_synth_manager.lock());

                // Check if recording is active (skip clip playback on armed tracks)
                let is_recording = *recorder_refs.state.lock() == crate::recorder::RecordingState::Recording;

                // Process each frame (using snapshots - NO LOCKS in hot path!)
                for frame_idx in 0..frames {
                    let playhead_frame = current_playhead + frame_idx as u64;
                    // Apply tempo ratio: at 120 BPM, playhead advances 1:1 with real time
                    // At 100 BPM, playhead advances slower (0.833x) through timeline
                    // At 140 BPM, playhead advances faster (1.167x) through timeline
                    let real_seconds = playhead_frame as f64 / f64::from(TARGET_SAMPLE_RATE);
                    let playhead_seconds = real_seconds * tempo_ratio;

                    let mut mix_left = 0.0;
                    let mut mix_right = 0.0;

                    // Read input samples FIRST (needed for both recording and input monitoring)
                    let (input_left, input_right) = if let Some(input_mgr) = input_manager.try_lock() {
                        let channels = input_mgr.get_input_channels();
                        if channels == 1 {
                            if let Some(samples) = input_mgr.read_samples(1) {
                                let mono_sample = samples.first().copied().unwrap_or(0.0);
                                (mono_sample, mono_sample)
                            } else {
                                (0.0, 0.0)
                            }
                        } else if let Some(samples) = input_mgr.read_samples(2) {
                            (samples.first().copied().unwrap_or(0.0),
                             samples.get(1).copied().unwrap_or(0.0))
                        } else {
                            (0.0, 0.0)
                        }
                    } else {
                        (0.0, 0.0)
                    };

                    // Mix all tracks using snapshots (no locking!)
                    for track_snap in &mut snapshot_buf {
                        // Handle mute/solo logic
                        if track_snap.muted {
                            continue; // Muted tracks produce no sound
                        }
                        if has_solo && !track_snap.soloed {
                            continue; // If any track is soloed, skip non-soloed tracks
                        }

                        let mut track_left = 0.0;
                        let mut track_right = 0.0;

                        // Skip existing clip playback on armed tracks during recording
                        // (user should only hear new input, not old overlapping clips)
                        let skip_clips = track_snap.armed && is_recording;

                        // Mix all audio clips on this track
                        for timeline_clip in &track_snap.audio_clips {
                            if skip_clips { continue; }
                            let clip_duration = timeline_clip.duration
                                .unwrap_or(timeline_clip.clip.duration_seconds);
                            // When warp is enabled, the clip's timeline duration changes:
                            // stretch > 1 = faster playback = clip ends sooner
                            // stretch < 1 = slower playback = clip ends later
                            let effective_duration = if timeline_clip.warp_enabled {
                                clip_duration / f64::from(timeline_clip.stretch_factor)
                            } else {
                                clip_duration
                            };
                            let clip_end = timeline_clip.start_time + effective_duration;

                            if playhead_seconds >= timeline_clip.start_time
                                && playhead_seconds < clip_end
                            {
                                let time_in_clip = playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                                let clip_gain = timeline_clip.get_gain();

                                // Get pitch ratio for transpose (1.0 = no change)
                                let pitch_ratio = f64::from(timeline_clip.get_pitch_ratio());

                                // Determine which audio source to use and calculate frame index
                                let (frame_in_clip, source_clip): (usize, &AudioClip) = if timeline_clip.warp_enabled {
                                    if timeline_clip.warp_mode == 0 {
                                        // Warp mode: use pre-stretched cached audio (pitch preserved)
                                        // Apply pitch ratio to playback rate for transpose
                                        if let Some(ref stretched) = timeline_clip.stretched_cache {
                                            let frame = (time_in_clip * pitch_ratio * f64::from(TARGET_SAMPLE_RATE)) as usize;
                                            (frame, stretched.as_ref())
                                        } else {
                                            // Fallback to Re-Pitch if cache not ready
                                            let stretched_time = time_in_clip * f64::from(timeline_clip.stretch_factor) * pitch_ratio;
                                            ((stretched_time * f64::from(TARGET_SAMPLE_RATE)) as usize, &*timeline_clip.clip)
                                        }
                                    } else {
                                        // Re-Pitch mode: sample-rate shift (pitch follows speed)
                                        // Also apply any additional transpose
                                        let stretched_time = time_in_clip * f64::from(timeline_clip.stretch_factor) * pitch_ratio;
                                        ((stretched_time * f64::from(TARGET_SAMPLE_RATE)) as usize, &*timeline_clip.clip)
                                    }
                                } else {
                                    // No warp - apply pitch ratio for transpose
                                    ((time_in_clip * pitch_ratio * f64::from(TARGET_SAMPLE_RATE)) as usize, &*timeline_clip.clip)
                                };

                                if let Some(l) = source_clip.get_sample(frame_in_clip, 0) {
                                    track_left += l * clip_gain;
                                }
                                if source_clip.channels > 1 {
                                    if let Some(r) = source_clip.get_sample(frame_in_clip, 1) {
                                        track_right += r * clip_gain;
                                    }
                                } else {
                                    // Mono clip - duplicate to right
                                    if let Some(l) = source_clip.get_sample(frame_in_clip, 0) {
                                        track_right += l * clip_gain;
                                    }
                                }
                            }
                        }

                        // Process per-track MIDI clips (using pre-acquired synth lock)
                        // Route MIDI to EITHER built-in synth OR VST3 instruments (not both)
                        if let Some(ref mut synth_manager) = synth_guard {
                            // Check if track has VST3 plugins - if so, skip built-in synth
                            let has_vst3 = !track_snap.fx_chain.is_empty();

                            for timeline_midi_clip in &track_snap.midi_clips {
                                if skip_clips { continue; }
                                let clip_start_samples = (timeline_midi_clip.start_time * f64::from(TARGET_SAMPLE_RATE)) as u64;
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
                                                    // Send to built-in synth ONLY if no VST3 plugins
                                                    if !has_vst3 {
                                                        synth_manager.note_on(track_snap.id, note, velocity);
                                                    }

                                                    // Send to VST3 instruments in FX chain
                                                    if has_vst3 {
                                                        { let effect_mgr = effect_manager.lock();
                                                            for effect_id in &track_snap.fx_chain {
                                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                                    { let mut effect = effect_arc.lock();
                                                                        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                                                        if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                                            let _ = vst3.process_midi_event(0, 0, i32::from(note), i32::from(velocity), 0);
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                crate::midi::MidiEventType::NoteOff { note, velocity: _ } => {
                                                    // Send to built-in synth ONLY if no VST3 plugins
                                                    if !has_vst3 {
                                                        synth_manager.note_off(track_snap.id, note);
                                                    }

                                                    // Send to VST3 instruments in FX chain
                                                    if has_vst3 {
                                                        { let effect_mgr = effect_manager.lock();
                                                            for effect_id in &track_snap.fx_chain {
                                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                                    { let mut effect = effect_arc.lock();
                                                                        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                                                        if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                                            let _ = vst3.process_midi_event(1, 0, i32::from(note), 0, 0);
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
                            }

                            // Add per-track synthesizer output (M6) - no lock needed, already held
                            let (synth_left, synth_right) = synth_manager.process_sample_stereo(track_snap.id);
                            track_left += synth_left;
                            track_right += synth_right;
                        }

                        // Input monitoring: mix live input for armed audio tracks
                        // Uses fade gain for smooth transitions (20ms ramp avoids clicks)
                        {
                            let should_monitor = track_snap.armed && track_snap.input_monitoring && track_snap.is_audio_track;
                            let target = if should_monitor { 1.0f64 } else { 0.0f64 };

                            #[allow(clippy::float_cmp)]
                            if track_snap.monitoring_fade_gain != target {
                                let step = 1.0 / (0.020 * f64::from(TARGET_SAMPLE_RATE));
                                if target > track_snap.monitoring_fade_gain {
                                    track_snap.monitoring_fade_gain = (track_snap.monitoring_fade_gain + step).min(1.0);
                                } else {
                                    track_snap.monitoring_fade_gain = (track_snap.monitoring_fade_gain - step).max(0.0);
                                }
                            }

                            if track_snap.monitoring_fade_gain > 0.0 {
                                let ch = track_snap.input_channel as usize;
                                let input_sample = if ch == 0 { input_left } else { input_right };
                                track_left += input_sample * track_snap.monitoring_fade_gain as f32;
                                track_right += input_sample * track_snap.monitoring_fade_gain as f32;
                            }
                        }

                        // Process FX chain on this track BEFORE volume/pan
                        // This is important because VST3 instruments generate their own audio
                        // and we want the fader to control the post-FX output level
                        let mut fx_left = track_left;
                        let mut fx_right = track_right;

                        { let effect_mgr = effect_manager.lock();
                            for effect_id in &track_snap.fx_chain {
                                // Skip bypassed effects (audio passes through unchanged)
                                if effect_mgr.is_bypassed(*effect_id) {
                                    continue;
                                }
                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                    { let mut effect = effect_arc.lock();
                                        let (out_l, out_r) = effect.process_frame(fx_left, fx_right);
                                        fx_left = out_l;
                                        fx_right = out_r;
                                    }
                                }
                            }
                        }

                        // Apply track volume AFTER FX chain (from snapshot)
                        // This ensures VST3 instrument output is also affected by the fader
                        // Use automation curve if available, otherwise static volume_gain
                        let frame_volume_gain = if track_snap.volume_automation.is_empty() {
                            track_snap.volume_gain
                        } else {
                            // Interpolate volume from automation curve
                            interpolate_automation_gain(&track_snap.volume_automation, playhead_seconds)
                        };
                        fx_left *= frame_volume_gain;
                        fx_right *= frame_volume_gain;

                        // Apply track pan AFTER FX chain (from snapshot)
                        fx_left *= track_snap.pan_left;
                        fx_right *= track_snap.pan_right;

                        // Update track peak levels for metering
                        let entry = peak_buf.entry(track_snap.id).or_insert((0.0, 0.0));
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

                    // Process recording (metronome handled separately below)
                    let (met_left, met_right) = recorder_refs.process_frame(input_left, input_right, true, playhead_seconds);

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
                        { let effect_mgr = effect_manager.lock();
                            for effect_id in &master_snap.fx_chain {
                                // Skip bypassed effects (audio passes through unchanged)
                                if effect_mgr.is_bypassed(*effect_id) {
                                    continue;
                                }
                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                    { let mut effect = effect_arc.lock();
                                        let (out_l, out_r) = effect.process_frame(master_left, master_right);
                                        master_left = out_l;
                                        master_right = out_r;
                                    }
                                }
                            }
                        }
                    }

                    // Apply master limiter to prevent clipping
                    let (limited_left, limited_right) = { let mut limiter = master_limiter.lock();
                        limiter.process_frame(master_left, master_right)
                    };

                    // Update master peak levels for metering (before metronome is added)
                    master_peak_left = master_peak_left.max(limited_left.abs());
                    master_peak_right = master_peak_right.max(limited_right.abs());

                    // Add metronome AFTER metering so it doesn't affect the master meter
                    // Metronome goes directly to output, bypassing master volume/effects
                    let mut output_left = limited_left + met_left;
                    let mut output_right = limited_right + met_right;

                    // Process latency test (if running)
                    latency_test.process_input(input_left, playhead_frame);
                    let test_tone = latency_test.generate_output(playhead_frame);
                    output_left += test_tone;
                    output_right += test_tone;

                    // Mix library preview audio (independent of transport)
                    let (preview_left, preview_right) = crate::api::preview::preview_process_sample();
                    output_left += preview_left;
                    output_right += preview_right;

                    // Write to output buffer (interleaved stereo)
                    data[frame_idx * 2] = output_left;
                    data[frame_idx * 2 + 1] = output_right;
                }

                // Update track peak levels and monitoring fade gains (brief lock after buffer processing)
                { let tm = track_manager.lock();
                    for track_snap in &snapshot_buf {
                        if let Some(track_arc) = tm.get_track(track_snap.id) {
                            { let mut track = track_arc.lock();
                                track.monitoring_fade_gain = track_snap.monitoring_fade_gain;
                            }
                        }
                    }
                    for (track_id, (peak_l, peak_r)) in &peak_buf {
                        if let Some(track_arc) = tm.get_track(*track_id) {
                            { let mut track = track_arc.lock();
                                track.update_peaks(*peak_l, *peak_r);
                            }
                        }
                    }
                    // Update master track peaks
                    {
                        let master_arc = tm.get_master_track();
                        { let mut master = master_arc.lock();
                            master.update_peaks(master_peak_left, master_peak_right);
                        };
                    }
                }

                // Advance playhead
                playhead_samples.fetch_add(frames as u64, Ordering::SeqCst);
            },
            move |err| {
                eprintln!("Audio stream error: {err}");
            },
            None,
        )?;

        Ok(stream)
    }
}
