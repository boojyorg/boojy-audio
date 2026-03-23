/// Project serialization: export_to_project_data, restore_from_project_data
use super::{AudioGraph, BufferSizePreset};
use crate::audio_file::TARGET_SAMPLE_RATE;
use crate::midi::MidiClip;
use crate::track::TimelineMidiClip;
use std::sync::Arc;

impl AudioGraph {
    // ========================================================================
    // M5: SAVE & LOAD PROJECT
    // ========================================================================

    /// Export current state to `ProjectData` (for saving) - native only (uses recorder)
    #[cfg(not(target_arch = "wasm32"))]
    pub fn export_to_project_data(&self, project_name: String) -> crate::project::ProjectData {
        use crate::project::{TrackData, EffectData, ClipData, SendData, Vst3PluginData, AudioFileData, ProjectData};
        use crate::effects::EffectType as ET;
        use std::collections::HashMap;
        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
        use base64::Engine as _;

        // Get all tracks
        let track_manager = self.track_manager.lock();
        let effect_manager = self.effect_manager.lock();
        let synth_manager = self.track_synth_manager.lock();

        let all_tracks = track_manager.get_all_tracks();
        let tracks_data: Vec<TrackData> = all_tracks.iter().map(|track_arc| {
            let track = track_arc.lock();

            // Get effect chain for this track
            let fx_chain: Vec<EffectData> = track.fx_chain.iter().filter_map(|effect_id| {
                // Get effect from effect manager
                if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                    let effect = effect_arc.lock();
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
                        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                        ET::VST3(_vst3) => {
                            effect_type_str = "vst3".to_string();
                            // VST3 state is saved/restored via separate FFI calls (get/set_vst3_state).
                            // This snapshot path serializes the effect slot type only.
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
                    / f64::from(timeline_clip.clip.sample_rate);

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
                .chain(midi_clips_data)
                .collect();

            // Get track type string
            let track_type_str = format!("{:?}", track.track_type);

            // Get instrument settings for MIDI tracks (synth or sampler)
            let synth_settings = synth_manager.get_synth_parameters(track.id);
            let sampler_settings = synth_manager.get_sampler_parameters(track.id);

            // Export send routing
            let sends: Vec<SendData> = track.sends.iter().map(|s| SendData {
                target_track_id: s.target_track_id,
                amount: s.amount,
                pre_fader: s.pre_fader,
            }).collect();

            // Collect VST3 plugin data with state
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            let vst3_plugins: Vec<Vst3PluginData> = track.fx_chain.iter().filter_map(|effect_id| {
                if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                    let effect = effect_arc.lock();
                    if let ET::VST3(vst3) = &*effect {
                        // Get plugin state
                        let state_data = vst3.get_state().unwrap_or_default();
                        let state_base64 = base64::engine::general_purpose::STANDARD.encode(&state_data);

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
                sampler_settings,
                sends,
                parent_group_id: track.parent_group,
                input_monitoring: track.input_monitoring,
                vst3_plugins,
            }
        }).collect();

        // Collect audio files from all tracks' audio clips (not the legacy self.clips)
        let audio_files: Vec<AudioFileData> = all_tracks.iter().flat_map(|track_arc| {
            let track = track_arc.lock();
            track.audio_clips.iter().map(|timeline_clip| {
                // Extract just the filename from the path for cleaner storage
                let filename = std::path::Path::new(&timeline_clip.clip.file_path)
                    .file_name().map_or_else(|| timeline_clip.clip.file_path.clone(), |f| f.to_string_lossy().to_string());
                AudioFileData {
                    id: timeline_clip.id,
                    original_name: filename.clone(),
                    relative_path: format!("audio/{:03}-{}", timeline_clip.id, filename),
                    duration: timeline_clip.clip.duration_seconds,
                    sample_rate: timeline_clip.clip.sample_rate,
                    channels: timeline_clip.clip.channels as u32,
                }
            }).collect::<Vec<_>>()
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

    /// Restore state from `ProjectData` (for loading) - native only (uses recorder)
    #[cfg(not(target_arch = "wasm32"))]
    pub fn restore_from_project_data(&mut self, project_data: crate::project::ProjectData) -> anyhow::Result<()> {
        use crate::effects::{ParametricEQ, EffectType, Compressor, Reverb, Delay, Chorus, Limiter};
        use crate::track::TrackType;

        // Stop playback
        let _ = self.stop();

        // Clear existing tracks (except master will be kept and updated)
        {
            let mut track_manager = self.track_manager.lock();
            let _effect_manager = self.effect_manager.lock();

            // Get all track IDs except master (ID 0)
            let all_tracks = track_manager.get_all_tracks();
            let track_ids_to_remove: Vec<u64> = all_tracks.iter()
                .filter_map(|track_arc| {
                    let track = track_arc.lock();
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
            eprintln!("⚠️  Failed to restore buffer size: {e}");
        } else {
            eprintln!("   - Buffer size: {buffer_preset:?}");
        }

        // Recreate tracks and effects
        for track_data in project_data.tracks {
            let track_manager = self.track_manager.lock();
            let mut effect_manager = self.effect_manager.lock();

            // Parse track type
            let track_type = match track_data.track_type.as_str() {
                "Audio" => TrackType::Audio,
                "Midi" | "Sampler" => TrackType::Midi,
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
                    let mut master = master_track_arc.lock();
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
                let mut tm = self.track_manager.lock();
                tm.create_track(track_type, track_data.name.clone())
            };

            // Update track properties
            {
                let tm = self.track_manager.lock();
                if let Some(track_arc) = tm.get_track(track_id) {
                    let mut track = track_arc.lock();
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

            // Restore instrument for MIDI tracks (synth or sampler)
            if track_type == TrackType::Midi {
                if let Some(synth_data) = &track_data.synth_settings {
                    let mut synth_manager = self.track_synth_manager.lock();
                    synth_manager.create_synth(track_id);
                    synth_manager.restore_synth_parameters(track_id, synth_data);
                } else if let Some(sampler_data) = &track_data.sampler_settings {
                    let mut synth_manager = self.track_synth_manager.lock();
                    synth_manager.create_sampler(track_id);
                    // Load the sample file first, then restore parameters
                    if !sampler_data.sample_path.is_empty() {
                        if let Ok(clip) = crate::audio_file::load_audio_file(&sampler_data.sample_path) {
                            synth_manager.load_sample(track_id, Arc::new(clip), sampler_data.root_note);
                        }
                    }
                    synth_manager.restore_sampler_parameters(track_id, sampler_data);
                } else if track_data.track_type == "Sampler" {
                    // Legacy: old project with Sampler type but no sampler_settings
                    let mut synth_manager = self.track_synth_manager.lock();
                    synth_manager.create_sampler(track_id);
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
                let tm = self.track_manager.lock();
                if let Some(track_arc) = tm.get_track(track_id) {
                    let mut track = track_arc.lock();
                    track.fx_chain.push(effect_id);
                }
            }

            // Restore VST3 plugins from vst3_plugins field
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            {
                use base64::Engine as _;
                use crate::vst3_host::VST3Effect;
                use crate::audio_file::TARGET_SAMPLE_RATE;

                for vst3_data in &track_data.vst3_plugins {
                    eprintln!("   - Restoring VST3 plugin: {} from {}", vst3_data.plugin_name, vst3_data.plugin_path);

                    // Load the VST3 plugin
                    let sample_rate = f64::from(TARGET_SAMPLE_RATE);
                    let block_size = 512; // Hardcoded: should come from user settings (v0.6.0)

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
                            let tm = self.track_manager.lock();
                            if let Some(track_arc) = tm.get_track(track_id) {
                                let mut track = track_arc.lock();
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
                    let clip_arc = Arc::new(midi_clip);

                    // Generate a new clip ID
                    let clip_id = {
                        let mut next_id = self.next_clip_id.lock();
                        let id = *next_id;
                        *next_id += 1;
                        id
                    };

                    // Add to global MIDI clips storage
                    {
                        let mut midi_clips = self.midi_clips.lock();
                        midi_clips.push(TimelineMidiClip {
                            id: clip_id,
                            clip: clip_arc.clone(),
                            start_time: clip_data.start_time,
                            track_id: Some(track_id),
                            volume_automation: Vec::new(),
                            pan_automation: Vec::new(),
                        });
                    }

                    // Add to track's MIDI clips
                    let tm = self.track_manager.lock();
                    if let Some(track_arc) = tm.get_track(track_id) {
                        let mut track = track_arc.lock();
                        track.midi_clips.push(TimelineMidiClip {
                            id: clip_id,
                            clip: clip_arc,
                            start_time: clip_data.start_time,
                            track_id: Some(track_id),
                            volume_automation: Vec::new(),
                            pan_automation: Vec::new(),
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
}

// ============================================================================
// MIDI SERIALIZATION HELPERS
// ============================================================================

/// Convert MIDI events (NoteOn/NoteOff pairs) to `MidiNoteData` for serialization
pub(crate) fn convert_midi_events_to_notes(
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
        let time_seconds = event.timestamp_samples as f64 / f64::from(sample_rate);
        match event.event_type {
            MidiEventType::NoteOn { note, velocity } if velocity > 0 => {
                active_notes.insert(note, (time_seconds, velocity));
            }
            // NoteOff or NoteOn with velocity 0 are both treated as NoteOff
            MidiEventType::NoteOff { note, .. }
            | MidiEventType::NoteOn { note, velocity: 0 } => {
                if let Some((start, vel)) = active_notes.remove(&note) {
                    notes.push(MidiNoteData {
                        note,
                        velocity: vel,
                        start_time: start,
                        duration: time_seconds - start,
                    });
                }
            }
            MidiEventType::NoteOn { .. } => {}
        }
    }

    // Sort by start time for consistency
    notes.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap_or(std::cmp::Ordering::Equal));
    notes
}

/// Reconstruct `MidiClip` from serialized `MidiNoteData`
pub(crate) fn reconstruct_midi_clip_from_notes(
    notes: &[crate::project::MidiNoteData],
    sample_rate: u32,
    saved_duration: Option<f64>,
) -> MidiClip {
    use crate::midi::{MidiClip, MidiEvent, MidiEventType};

    let mut events = Vec::new();

    for note in notes {
        let start_samples = (note.start_time * f64::from(sample_rate)) as u64;
        let end_samples = ((note.start_time + note.duration) * f64::from(sample_rate)) as u64;

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
        (dur * f64::from(sample_rate)) as u64
    } else {
        // Calculate duration as the end of the last note
        notes.iter()
            .map(|n| ((n.start_time + n.duration) * f64::from(sample_rate)) as u64)
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
