/// Project serialization: export_to_project_data, restore_from_project_data
use super::{AudioGraph, BufferSizePreset};
use crate::audio_file::TARGET_SAMPLE_RATE;
use crate::midi::MidiClip;
use crate::track::TimelineMidiClip;
use std::collections::HashMap;
use std::sync::Arc;

impl AudioGraph {
    // ========================================================================
    // M5: SAVE & LOAD PROJECT
    // ========================================================================

    /// Export current state to `ProjectData` (for saving) - native only (uses recorder)
    pub fn export_to_project_data(&self, project_name: String) -> crate::project::ProjectData {
        use crate::effects::EffectType as ET;
        use crate::project::{
            AudioFileData, ClipData, EffectData, ProjectData, SendData, TrackData, Vst3PluginData,
        };
        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
        use base64::Engine as _;
        use std::collections::HashMap;

        // Lock order: synth → track → effect — the same order as the audio
        // callback, which holds track_synth_manager across the whole buffer
        // and only then takes track_manager/effect_manager. Acquiring
        // synth_manager LAST here (while already holding the other two)
        // deadlocks against a concurrent callback: it holds synth and waits
        // for track, we hold track+effect and wait for synth. parking_lot
        // freezes silently — every save was a tiny-window dice roll.
        let synth_manager = self.track_synth_manager.lock();
        let track_manager = self.track_manager.lock();
        let effect_manager = self.effect_manager.lock();

        let all_tracks = track_manager.get_all_tracks();
        let tracks_data: Vec<TrackData> = all_tracks
            .iter()
            .map(|track_arc| {
                let track = track_arc.lock();

                // Get effect chain for this track
                let fx_chain: Vec<EffectData> = track
                    .fx_chain
                    .iter()
                    .filter_map(|effect_id| {
                        // Get effect from effect manager
                        if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                            let effect = effect_arc.lock();
                            let mut parameters = HashMap::new();
                            let effect_type_str;

                            // Get parameters based on effect type
                            match &*effect {
                                ET::EQ(eq) => {
                                    // Keep the type key "eq" so older builds don't drop the
                                    // effect; the variable band list rides in the param map.
                                    effect_type_str = "eq".to_string();
                                    eq.write_params(&mut |k, v| {
                                        parameters.insert(k.to_string(), v);
                                    });
                                }
                                ET::Compressor(comp) => {
                                    effect_type_str = "compressor".to_string();
                                    parameters
                                        .insert("threshold_db".to_string(), comp.threshold_db);
                                    parameters.insert("ratio".to_string(), comp.ratio);
                                    parameters.insert("attack_ms".to_string(), comp.attack_ms);
                                    parameters.insert("release_ms".to_string(), comp.release_ms);
                                    parameters
                                        .insert("makeup_gain_db".to_string(), comp.makeup_gain_db);
                                    parameters.insert("wet_dry_mix".to_string(), comp.wet_dry_mix);
                                }
                                ET::Reverb(rev) => {
                                    effect_type_str = "reverb".to_string();
                                    parameters.insert("room_size".to_string(), rev.room_size);
                                    parameters.insert("damping".to_string(), rev.damping);
                                    parameters.insert("wet_dry_mix".to_string(), rev.wet_dry_mix);
                                }
                                ET::Delay(dly) => {
                                    effect_type_str = "delay".to_string();
                                    parameters
                                        .insert("delay_time_ms".to_string(), dly.delay_time_ms);
                                    parameters.insert("feedback".to_string(), dly.feedback);
                                    parameters.insert("wet_dry_mix".to_string(), dly.wet_dry_mix);
                                }
                                ET::Chorus(chr) => {
                                    effect_type_str = "chorus".to_string();
                                    parameters.insert("rate_hz".to_string(), chr.rate_hz);
                                    parameters.insert("depth".to_string(), chr.depth);
                                    parameters.insert("wet_dry_mix".to_string(), chr.wet_dry_mix);
                                }
                                ET::Limiter(lim) => {
                                    effect_type_str = "limiter".to_string();
                                    parameters.insert("threshold_db".to_string(), lim.threshold_db);
                                    parameters.insert("release_ms".to_string(), lim.release_ms);
                                    parameters.insert("wet_dry_mix".to_string(), lim.wet_dry_mix);
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
                    })
                    .collect();

                // Get audio clips on this track
                let audio_clips_data: Vec<ClipData> = track
                    .audio_clips
                    .iter()
                    .map(|timeline_clip| {
                        ClipData {
                            id: timeline_clip.id,
                            start_time: timeline_clip.start_time,
                            offset: timeline_clip.offset,
                            duration: timeline_clip.duration,
                            audio_file_id: Some(timeline_clip.id), // Simplified: use clip ID as file ID
                            midi_notes: None,
                            midi_cc: None,
                        }
                    })
                    .collect();

                // Get MIDI clips on this track - convert events to note data
                let midi_clips_data: Vec<ClipData> = track
                    .midi_clips
                    .iter()
                    .map(|timeline_clip| {
                        let duration_seconds = timeline_clip.clip.duration_samples as f64
                            / f64::from(timeline_clip.clip.sample_rate);
                        let midi_notes = convert_midi_events_to_notes(
                            &timeline_clip.clip.events,
                            timeline_clip.clip.sample_rate,
                            duration_seconds,
                        );
                        let midi_cc = convert_midi_events_to_cc(
                            &timeline_clip.clip.events,
                            timeline_clip.clip.sample_rate,
                        );

                        ClipData {
                            id: timeline_clip.id,
                            start_time: timeline_clip.start_time,
                            offset: 0.0,
                            duration: Some(duration_seconds),
                            audio_file_id: None, // MIDI clip, not audio
                            midi_notes: Some(midi_notes),
                            midi_cc: if midi_cc.is_empty() {
                                None
                            } else {
                                Some(midi_cc)
                            },
                        }
                    })
                    .collect();

                // Combine audio and MIDI clips
                let clips_data: Vec<ClipData> = audio_clips_data
                    .into_iter()
                    .chain(midi_clips_data)
                    .collect();

                // Get track type string
                let track_type_str = format!("{:?}", track.track_type);

                // Get instrument settings for MIDI tracks (synth, sampler, or drum kit)
                let synth_settings = synth_manager.get_synth_parameters(track.id);
                let sampler_settings = synth_manager.get_sampler_parameters(track.id);
                let drum_kit_settings = synth_manager.get_drum_kit_parameters(track.id);

                // Export send routing
                let sends: Vec<SendData> = track
                    .sends
                    .iter()
                    .map(|s| SendData {
                        target_track_id: s.target_track_id,
                        amount: s.amount,
                        pre_fader: s.pre_fader,
                    })
                    .collect();

                // Collect VST3 plugin data with state
                #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                let vst3_plugins: Vec<Vst3PluginData> = track
                    .fx_chain
                    .iter()
                    .filter_map(|effect_id| {
                        if let Some(effect_arc) = effect_manager.get_effect(*effect_id) {
                            let effect = effect_arc.lock();
                            if let ET::VST3(vst3) = &*effect {
                                // Get plugin state
                                let state_data = vst3.get_state().unwrap_or_default();
                                let state_base64 =
                                    base64::engine::general_purpose::STANDARD.encode(&state_data);

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
                    })
                    .collect();

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
                    drum_kit_settings,
                    sends,
                    parent_group_id: track.parent_group,
                    input_monitoring: track.input_monitoring,
                    vst3_plugins,
                    timeline_visible: track.timeline_visible,
                }
            })
            .collect();

        // Collect audio files from all tracks' audio clips (not the legacy self.clips)
        let audio_files: Vec<AudioFileData> = all_tracks
            .iter()
            .flat_map(|track_arc| {
                let track = track_arc.lock();
                track
                    .audio_clips
                    .iter()
                    .map(|timeline_clip| {
                        // Just the file name, without any `NNN-` prefix an earlier
                        // save added inside a project's audio/ folder.
                        let filename = crate::project::clean_audio_file_name(std::path::Path::new(
                            &timeline_clip.clip.file_path,
                        ));
                        AudioFileData {
                            id: timeline_clip.id,
                            original_name: filename.clone(),
                            relative_path: format!("audio/{:03}-{}", timeline_clip.id, filename),
                            duration: timeline_clip.clip.duration_seconds,
                            sample_rate: timeline_clip.clip.sample_rate,
                            channels: timeline_clip.clip.channels as u32,
                        }
                    })
                    .collect::<Vec<_>>()
            })
            .collect();

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
            // Numerator (beats per bar) is the value the engine actually uses for
            // bar math/metronome — persist the live value, not a hardcoded 4. The
            // denominator (beat unit) is display-only and owned by the UI layer
            // (ui_layout.json), so the engine keeps it at its quarter-note default.
            time_sig_numerator: self.recorder.get_time_signature(),
            time_sig_denominator: 4,
            tracks: tracks_data,
            audio_files,
            metronome_enabled,
            count_in_bars,
            buffer_size_preset,
        }
    }

    /// Remove everything a project owns, leaving only the master track, and
    /// restart track and clip numbering. Used by New/Close Project
    /// (`clear_all_tracks`) and at the start of `restore_from_project_data`.
    ///
    /// Because a reopened project keeps its saved track and clip ids, anything
    /// left behind here (an instrument, a bypass flag, an effect, a MIDI clip)
    /// would silently attach itself to the new project's tracks.
    ///
    /// Lock order follows the audio callback (synth → track → effect), and
    /// each manager is locked on its own, never nested.
    pub fn teardown_project_state(&mut self) {
        let _ = self.stop();

        // Snapshot what to remove (non-master tracks and their effects).
        let (track_ids, effect_ids): (Vec<u64>, Vec<u64>) = {
            let track_manager = self.track_manager.lock();
            let mut track_ids = Vec::new();
            let mut effect_ids = Vec::new();
            for track_arc in track_manager.get_all_tracks() {
                let track = track_arc.lock();
                if track.id != 0 {
                    track_ids.push(track.id);
                    effect_ids.extend(track.fx_chain.iter().copied());
                }
            }
            (track_ids, effect_ids)
        };

        // 1. synth: every per-track instrument and bypass flag.
        self.track_synth_manager.lock().clear_all();

        // Global MIDI clip storage (clips never attached to a track included)
        // and the legacy audio timeline.
        self.midi_clips.lock().clear();
        self.clips.lock().clear();

        // 2. track: remove tracks, restart numbering at 1.
        {
            let mut track_manager = self.track_manager.lock();
            for track_id in &track_ids {
                track_manager.remove_track(*track_id);
            }
            track_manager.reset_ids();
        }

        // 3. effect: remove the effects (VST3 included) those tracks owned.
        if !effect_ids.is_empty() {
            let mut effect_manager = self.effect_manager.lock();
            for effect_id in &effect_ids {
                effect_manager.remove_effect(*effect_id);
            }
            eprintln!(
                "🧹 [Graph] Removed {} effects from cleared tracks",
                effect_ids.len()
            );
        }

        self.reset_clip_ids();
    }

    /// Restore graph state from project data (for loading) - native only (uses recorder).
    ///
    /// Tracks and MIDI clips keep the ids they were saved with, so UI data
    /// filed under those ids (colours, automation, clip names) still lines up.
    /// Returns a map of save-time track IDs to restored track IDs: the
    /// identity for a healthy project, and only different if a damaged file
    /// had a duplicate or reserved (0) track id that needed a fresh one.
    pub fn restore_from_project_data(
        &mut self,
        project_data: crate::project::ProjectData,
    ) -> anyhow::Result<HashMap<u64, u64>> {
        use crate::effects::{
            Chorus, Compressor, Delay, EffectType, Limiter, ParametricEQ, Reverb,
        };
        use crate::track::TrackType;

        // Stop playback
        let _ = self.stop();

        // Fully tear down the previous project (tracks, instruments, effects,
        // stray MIDI clips, id counters). Tracks and clips keep their SAVED ids
        // below, so anything left over would attach itself to the new project.
        self.teardown_project_state();
        eprintln!("   - Cleared existing project state");

        // Restore tempo (via recorder)
        self.recorder.set_tempo(project_data.tempo);
        eprintln!("   - Tempo: {} BPM", project_data.tempo);

        // Restore time signature numerator (beats per bar). Previously this was
        // never restored, so 3/4 or 6/8 projects silently reopened in 4/4. Guard
        // against a zero numerator (would break bar math).
        if project_data.time_sig_numerator > 0 {
            self.recorder
                .set_time_signature(project_data.time_sig_numerator);
            eprintln!(
                "   - Time signature: {} beats/bar",
                project_data.time_sig_numerator
            );
        }

        // Restore metronome and count-in settings
        self.recorder
            .set_metronome_enabled(project_data.metronome_enabled);
        self.recorder.set_count_in_bars(project_data.count_in_bars);
        eprintln!(
            "   - Metronome: {}, Count-in: {} bars",
            if project_data.metronome_enabled {
                "ON"
            } else {
                "OFF"
            },
            project_data.count_in_bars
        );

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

        // Save-time track ids to restored track ids. Healthy projects map every
        // id to itself; the map exists so sends and group parents still resolve
        // if a damaged file forced a fresh id. Master is always id 0.
        let mut id_map: HashMap<u64, u64> = HashMap::new();
        id_map.insert(0, 0);

        // Clip ids that are safe to keep as saved (unique across the project),
        // and make sure the counter is above every saved id up front so fresh
        // ids handed out for damaged duplicates can never collide with one.
        let keepable_clip_ids = crate::project::unique_saved_clip_ids(&project_data);
        if let Some(max_clip_id) = project_data
            .tracks
            .iter()
            .flat_map(|t| t.clips.iter().map(|c| c.id))
            .max()
        {
            self.ensure_next_clip_id_above(max_clip_id);
        }
        // Fresh track ids for the rare damaged case start above every saved id.
        let mut fallback_track_id = project_data.tracks.iter().map(|t| t.id).max().unwrap_or(0) + 1;
        // Group parents are resolved after all tracks exist (a parent can be
        // listed after its child).
        let mut pending_parents: Vec<(u64, u64)> = Vec::new();
        // Sends are restored AFTER all tracks are created so target IDs can
        // be remapped via `id_map` (the target return might be created later
        // in the loop than the source track).
        let mut pending_sends: Vec<(u64, Vec<crate::project::SendData>)> = Vec::new();

        // Recreate tracks and effects
        for track_data in project_data.tracks {
            // effect_manager is deliberately NOT locked for the whole
            // iteration: the synth-restore section below acquires
            // track_synth_manager, and holding effect_manager across that
            // inverts the callback's synth → track → effect lock order
            // (same deadlock as the save path above). create_effect calls
            // take short scoped locks instead.
            let track_manager = self.track_manager.lock();

            // Parse track type
            let track_type = match track_data.track_type.as_str() {
                "Audio" => TrackType::Audio,
                "Midi" | "Sampler" => TrackType::Midi,
                "Return" => TrackType::Return,
                "Group" => TrackType::Group,
                "Master" => TrackType::Master,
                _ => {
                    eprintln!(
                        "⚠️  Unknown track type: {}, defaulting to Audio",
                        track_data.track_type
                    );
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
                    master.timeline_visible = track_data.timeline_visible;
                    if !master.volume_automation.is_empty() {
                        master.timeline_visible = true;
                    }
                    eprintln!("   - Updated Master track");
                }
                continue;
            }

            // Create new track
            drop(track_manager); // Release lock before creating track
            let track_id = {
                let mut tm = self.track_manager.lock();
                match tm.insert_track_with_id(track_data.id, track_type, track_data.name.clone()) {
                    Ok(id) => id,
                    Err(reason) => {
                        // Damaged file (duplicate or reserved id): give this
                        // track a fresh id above every saved one.
                        let fresh = fallback_track_id;
                        fallback_track_id += 1;
                        eprintln!(
                            "⚠️  [restore] track '{}': {reason}; using fresh id {fresh}",
                            track_data.name
                        );
                        tm.insert_track_with_id(fresh, track_type, track_data.name.clone())
                            .expect("fresh track id is above every saved id")
                    }
                }
            };
            id_map.entry(track_data.id).or_insert(track_id);

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

                    // Restore input monitoring (parent group is resolved below,
                    // once every track exists)
                    if let Some(parent) = track_data.parent_group_id {
                        pending_parents.push((track_id, parent));
                    }
                    track.input_monitoring = track_data.input_monitoring;
                    track.timeline_visible = if track_type == TrackType::Return {
                        false
                    } else {
                        track_data.timeline_visible
                    };
                }
            }

            // Defer send restoration until after all tracks exist so target IDs
            // can be remapped via id_map.
            if !track_data.sends.is_empty() {
                pending_sends.push((track_id, track_data.sends.clone()));
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
                        if let Ok(clip) =
                            crate::audio_file::load_audio_file(&sampler_data.sample_path)
                        {
                            synth_manager.load_sample(
                                track_id,
                                Arc::new(clip),
                                sampler_data.root_note,
                            );
                        }
                    }
                    synth_manager.restore_sampler_parameters(track_id, sampler_data);
                } else if let Some(drum_kit_data) = &track_data.drum_kit_settings {
                    let mut synth_manager = self.track_synth_manager.lock();
                    synth_manager.create_drum_kit(track_id);
                    for slot in &drum_kit_data.slots {
                        // Restore pad metadata, load its sample file (if any), then restore the
                        // pad's sampler params — same order as the single-sampler restore above.
                        synth_manager.restore_drum_pad_meta(track_id, slot);
                        if let Some(path) = crate::drum_kit::DrumKit::slot_sample_path(slot) {
                            if let Ok(clip) = crate::audio_file::load_audio_file(path) {
                                synth_manager.load_drum_pad_sample(
                                    track_id,
                                    slot.pad_index,
                                    Arc::new(clip),
                                );
                            }
                        }
                        if let Some(sampler_data) = &slot.sampler {
                            synth_manager.restore_drum_pad_sampler(
                                track_id,
                                slot.pad_index,
                                sampler_data,
                            );
                        }
                    }
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
                        // New-format projects carry a band list (band_count + band_N_*).
                        // Old-format projects (low_freq/mid1_*/…) have no band_count, so
                        // load_params returns false and the EQ keeps its flat defaults
                        // rather than being dropped.
                        eq.load_params(&|k| effect_data.parameters.get(k).copied());
                        EffectType::EQ(eq)
                    }
                    "compressor" => {
                        let mut comp = Compressor::new();
                        if let Some(&v) = effect_data.parameters.get("threshold_db") {
                            comp.threshold_db = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("ratio") {
                            comp.ratio = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("attack_ms") {
                            comp.attack_ms = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("release_ms") {
                            comp.release_ms = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("makeup_gain_db") {
                            comp.makeup_gain_db = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") {
                            comp.wet_dry_mix = v;
                        }
                        comp.update_coefficients();
                        EffectType::Compressor(comp)
                    }
                    "reverb" => {
                        let mut rev = Reverb::new();
                        if let Some(&v) = effect_data.parameters.get("room_size") {
                            rev.room_size = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("damping") {
                            rev.damping = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") {
                            rev.wet_dry_mix = v;
                        }
                        EffectType::Reverb(rev)
                    }
                    "delay" => {
                        let mut dly = Delay::new();
                        if let Some(&v) = effect_data.parameters.get("delay_time_ms") {
                            dly.delay_time_ms = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("feedback") {
                            dly.feedback = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") {
                            dly.wet_dry_mix = v;
                        }
                        EffectType::Delay(dly)
                    }
                    "chorus" => {
                        let mut chr = Chorus::new();
                        if let Some(&v) = effect_data.parameters.get("rate_hz") {
                            chr.rate_hz = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("depth") {
                            chr.depth = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") {
                            chr.wet_dry_mix = v;
                        }
                        EffectType::Chorus(chr)
                    }
                    "limiter" => {
                        let mut lim = Limiter::new();
                        if let Some(&v) = effect_data.parameters.get("threshold_db") {
                            lim.threshold_db = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("release_ms") {
                            lim.release_ms = v;
                        }
                        if let Some(&v) = effect_data.parameters.get("wet_dry_mix") {
                            lim.wet_dry_mix = v;
                        }
                        lim.update_coefficients();
                        EffectType::Limiter(lim)
                    }
                    _ => {
                        eprintln!("⚠️  Unknown effect type: {}", effect_data.effect_type);
                        continue;
                    }
                };

                // Add effect to effect manager (scoped lock — see loop-top note)
                let effect_id = self.effect_manager.lock().create_effect(effect);

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
                use crate::audio_file::TARGET_SAMPLE_RATE;
                use crate::vst3_host::VST3Effect;
                use base64::Engine as _;

                for vst3_data in &track_data.vst3_plugins {
                    eprintln!(
                        "   - Restoring VST3 plugin: {} from {}",
                        vst3_data.plugin_name, vst3_data.plugin_path
                    );

                    // Load the VST3 plugin.
                    //
                    // C21/C62: maxSamplesPerBlock honours the project's
                    // restored buffer preset instead of a hardcoded 512. The
                    // host never hands a plugin more than 512 frames per call
                    // (live renderer MAX_VST3_BLOCK and offline export
                    // OFFLINE_BLOCK both sub-block), so the floor stays 512 —
                    // going lower would break that contract for plugins that
                    // pre-size internal buffers at init.
                    let sample_rate = f64::from(TARGET_SAMPLE_RATE);
                    let block_size = buffer_preset.samples().max(512) as i32;

                    match VST3Effect::new(&vst3_data.plugin_path, sample_rate, block_size) {
                        Ok(mut vst3_effect) => {
                            // Initialize the plugin
                            if let Err(e) = vst3_effect.initialize() {
                                eprintln!(
                                    "⚠️  Failed to initialize VST3 plugin {}: {}",
                                    vst3_data.plugin_name, e
                                );
                                continue;
                            }

                            // Restore plugin state
                            if !vst3_data.state_base64.is_empty() {
                                match base64::engine::general_purpose::STANDARD
                                    .decode(&vst3_data.state_base64)
                                {
                                    Ok(state_bytes) => {
                                        if let Err(e) = vst3_effect.set_state(&state_bytes) {
                                            eprintln!(
                                                "⚠️  Failed to restore VST3 state for {}: {}",
                                                vst3_data.plugin_name, e
                                            );
                                        } else {
                                            eprintln!(
                                                "   ✅ Restored VST3 state ({} bytes)",
                                                state_bytes.len()
                                            );
                                        }
                                    }
                                    Err(e) => {
                                        eprintln!(
                                            "⚠️  Failed to decode VST3 state for {}: {}",
                                            vst3_data.plugin_name, e
                                        );
                                    }
                                }
                            }

                            // Add to effect manager (scoped lock — see loop-top note)
                            let effect = EffectType::VST3(vst3_effect);
                            let effect_id = self.effect_manager.lock().create_effect(effect);

                            // Add to track's FX chain
                            let tm = self.track_manager.lock();
                            if let Some(track_arc) = tm.get_track(track_id) {
                                let mut track = track_arc.lock();
                                track.fx_chain.push(effect_id);
                            }

                            eprintln!(
                                "   ✅ Loaded VST3 plugin {} (effect_id={})",
                                vst3_data.plugin_name, effect_id
                            );
                        }
                        Err(e) => {
                            eprintln!(
                                "⚠️  Failed to load VST3 plugin {}: {}",
                                vst3_data.plugin_name, e
                            );
                        }
                    }
                }
            }

            // Restore MIDI clips for this track
            let mut midi_clip_count = 0;
            for clip_data in &track_data.clips {
                if let Some(midi_notes) = &clip_data.midi_notes {
                    // Reconstruct MIDI clip from serialized notes + CC (with saved duration)
                    let midi_clip = reconstruct_midi_clip_from_notes(
                        midi_notes,
                        clip_data.midi_cc.as_deref().unwrap_or(&[]),
                        project_data.sample_rate,
                        clip_data.duration,
                    );
                    let clip_arc = Arc::new(midi_clip);

                    // Keep the saved clip id (UI data such as the clip's name,
                    // mute and loop settings is filed under it). Only a
                    // duplicated id in a damaged file gets a fresh one.
                    let clip_id = if keepable_clip_ids.contains(&clip_data.id) {
                        clip_data.id
                    } else {
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
                        });
                    }

                    midi_clip_count += 1;
                }
                // Note: Audio clips are restored in the API layer after audio files are loaded
            }

            eprintln!(
                "   - Created track '{}' (type: {:?}, {} effects, {} MIDI clips)",
                track_data.name,
                track_type,
                track_data.fx_chain.len(),
                midi_clip_count
            );
        }

        // Second pass: restore sends with remapped target_track_ids.
        // Save-time target IDs are remapped to new fresh-load IDs via id_map.
        for (new_track_id, sends) in pending_sends {
            let tm = self.track_manager.lock();
            if let Some(track_arc) = tm.get_track(new_track_id) {
                let mut track = track_arc.lock();
                for send_data in sends {
                    match id_map.get(&send_data.target_track_id).copied() {
                        Some(new_target) => {
                            track.sends.push(crate::track::Send {
                                target_track_id: new_target,
                                amount: send_data.amount,
                                pre_fader: send_data.pre_fader,
                            });
                        }
                        None => {
                            eprintln!(
                                "⚠️  [restore] send from track {new_track_id} → saved target {} not found in id_map, skipping",
                                send_data.target_track_id
                            );
                        }
                    }
                }
            }
        }

        // Resolve group parents through the id map.
        for (child_id, saved_parent) in pending_parents {
            let Some(parent_id) = id_map.get(&saved_parent).copied() else {
                eprintln!(
                    "⚠️  [restore] track {child_id}: parent group {saved_parent} not found, leaving ungrouped"
                );
                continue;
            };
            let tm = self.track_manager.lock();
            if let Some(track_arc) = tm.get_track(child_id) {
                track_arc.lock().parent_group = Some(parent_id);
            }
        }

        // Note: Audio clips are restored in the API layer (load_project)
        // because they need access to the loaded AudioClip objects.
        // Return id_map so the API layer can remap saved track IDs.

        Ok(id_map)
    }
}

// ============================================================================
// MIDI SERIALIZATION HELPERS
// ============================================================================

/// Convert MIDI events (NoteOn/NoteOff pairs) to `MidiNoteData` for serialization.
///
/// `clip_end_seconds` is the clip's duration: notes still held at the end of
/// the event list (no NoteOff yet — e.g. saving while a long note sustains)
/// are flushed with the clip end as their off time instead of being silently
/// dropped.
pub(crate) fn convert_midi_events_to_notes(
    events: &[crate::midi::MidiEvent],
    sample_rate: u32,
    clip_end_seconds: f64,
) -> Vec<crate::project::MidiNoteData> {
    use crate::midi::MidiEventType;
    use crate::project::MidiNoteData;
    use std::collections::{HashMap, VecDeque};

    // Notes still sounding, per note number, oldest first: (start_seconds,
    // velocity). A queue, not one slot: two overlapping notes of the same
    // pitch each keep their own start (a single slot let the second
    // overwrite the first, so a save and reopen lost one of them).
    let mut active_notes: HashMap<u8, VecDeque<(f64, u8)>> = HashMap::new();
    let mut notes = Vec::new();

    for event in events {
        let time_seconds = event.timestamp_samples as f64 / f64::from(sample_rate);
        match event.event_type {
            MidiEventType::NoteOn { note, velocity } if velocity > 0 => {
                active_notes
                    .entry(note)
                    .or_default()
                    .push_back((time_seconds, velocity));
            }
            // NoteOff or NoteOn with velocity 0 are both treated as NoteOff;
            // it ends the oldest sounding note of that pitch.
            MidiEventType::NoteOff { note, .. } | MidiEventType::NoteOn { note, velocity: 0 } => {
                if let Some((start, vel)) =
                    active_notes.get_mut(&note).and_then(VecDeque::pop_front)
                {
                    notes.push(MidiNoteData {
                        note,
                        velocity: vel,
                        start_time: start,
                        duration: time_seconds - start,
                    });
                }
            }
            MidiEventType::NoteOn { .. } | MidiEventType::ControlChange { .. } => {}
        }
    }

    // Flush notes still held at end-of-clip (no NoteOff recorded yet) so a
    // save during a sustained note doesn't silently drop it.
    for (note, (start, vel)) in active_notes
        .into_iter()
        .flat_map(|(note, held)| held.into_iter().map(move |h| (note, h)))
    {
        notes.push(MidiNoteData {
            note,
            velocity: vel,
            start_time: start,
            duration: (clip_end_seconds - start).max(0.0),
        });
    }

    // Sort by start time for consistency
    notes.sort_by(|a, b| {
        a.start_time
            .partial_cmp(&b.start_time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    notes
}

/// Convert MIDI events to `MidiCcData` for serialization. Counterpart to
/// `convert_midi_events_to_notes` — without this, recorded control-change
/// automation (sustain, mod wheel, expression) was silently dropped on save.
pub(crate) fn convert_midi_events_to_cc(
    events: &[crate::midi::MidiEvent],
    sample_rate: u32,
) -> Vec<crate::project::MidiCcData> {
    use crate::midi::MidiEventType;
    use crate::project::MidiCcData;

    events
        .iter()
        .filter_map(|event| {
            if let MidiEventType::ControlChange { controller, value } = event.event_type {
                Some(MidiCcData {
                    controller,
                    value,
                    time: event.timestamp_samples as f64 / f64::from(sample_rate),
                })
            } else {
                None
            }
        })
        .collect()
}

/// Reconstruct `MidiClip` from serialized `MidiNoteData` + `MidiCcData`
pub(crate) fn reconstruct_midi_clip_from_notes(
    notes: &[crate::project::MidiNoteData],
    cc: &[crate::project::MidiCcData],
    sample_rate: u32,
    saved_duration: Option<f64>,
) -> MidiClip {
    use crate::midi::{MidiClip, MidiEvent, MidiEventType};

    let mut events = Vec::new();

    for note in notes {
        let start_samples = (note.start_time * f64::from(sample_rate)) as u64;
        let end_samples = ((note.start_time + note.duration) * f64::from(sample_rate)) as u64;

        events.push(MidiEvent::new(
            MidiEventType::NoteOn {
                note: note.note,
                velocity: note.velocity,
            },
            start_samples,
        ));
        events.push(MidiEvent::new(
            MidiEventType::NoteOff {
                note: note.note,
                velocity: 0,
            },
            end_samples,
        ));
    }

    // Restore recorded control-change events alongside the notes.
    for c in cc {
        events.push(MidiEvent::new(
            MidiEventType::ControlChange {
                controller: c.controller,
                value: c.value,
            },
            (c.time * f64::from(sample_rate)) as u64,
        ));
    }

    // Sort events by timestamp
    events.sort_by_key(|e| e.timestamp_samples);

    // Use saved duration if available, otherwise calculate from notes
    let duration_samples = if let Some(dur) = saved_duration {
        (dur * f64::from(sample_rate)) as u64
    } else {
        // Calculate duration as the end of the last note
        notes
            .iter()
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

#[cfg(test)]
mod tests {
    use super::{
        convert_midi_events_to_cc, convert_midi_events_to_notes, reconstruct_midi_clip_from_notes,
    };
    use crate::midi::{MidiEvent, MidiEventType};
    use crate::project::{MidiCcData, MidiNoteData};

    const SR: u32 = 48_000;
    const SR64: u64 = SR as u64;

    #[test]
    fn overlapping_notes_of_the_same_pitch_all_survive() {
        // Three C4s: two overlapping (0–1 s and 0.5–1.5 s) and one alone.
        use crate::midi::MidiEvent;
        let sr = 48_000;
        let at = |s: f64| (s * f64::from(sr)) as u64;
        let mut events = vec![
            MidiEvent::note_on(60, 100, at(0.0)),
            MidiEvent::note_on(60, 90, at(0.5)),
            MidiEvent::note_off(60, 0, at(1.0)),
            MidiEvent::note_off(60, 0, at(1.5)),
            MidiEvent::note_on(60, 80, at(2.0)),
            MidiEvent::note_off(60, 0, at(2.5)),
        ];
        events.sort();
        let notes = convert_midi_events_to_notes(&events, sr, 4.0);
        let got: Vec<(f64, f64, u8)> = notes
            .iter()
            .map(|n| (n.start_time, n.duration, n.velocity))
            .collect();
        assert_eq!(got, vec![(0.0, 1.0, 100), (0.5, 1.0, 90), (2.0, 0.5, 80)]);
    }

    #[test]
    fn held_note_without_note_off_is_flushed_at_clip_end() {
        // NoteOn at 1.0s with no matching NoteOff — e.g. saving while the
        // note still sustains. It must be kept, ending at the clip end.
        let events = vec![
            MidiEvent::note_on(60, 100, 0),
            MidiEvent::note_off(60, 0, SR64), // closed pair: 0.0s–1.0s
            MidiEvent::note_on(64, 90, SR64), // held: never released
        ];

        let notes = convert_midi_events_to_notes(&events, SR, 4.0);

        assert_eq!(notes.len(), 2, "the held note must not be dropped");
        let held = notes.iter().find(|n| n.note == 64).expect("held note");
        assert_eq!(held.velocity, 90);
        assert!((held.start_time - 1.0).abs() < 1e-6);
        assert!((held.duration - 3.0).abs() < 1e-6, "runs to clip end");
    }

    #[test]
    fn flushed_note_duration_clamps_at_zero() {
        // Pathological: NoteOn at/after the clip end must not yield a
        // negative duration.
        let events = vec![MidiEvent::note_on(60, 100, 2 * SR64)];

        let notes = convert_midi_events_to_notes(&events, SR, 1.0);

        assert_eq!(notes.len(), 1);
        assert!(notes[0].duration.abs() < 1e-9);
    }

    #[test]
    fn extracts_control_change_events() {
        let events = vec![
            MidiEvent::note_on(60, 100, 0),
            MidiEvent::control_change(1, 64, SR64), // mod wheel at 1.0s
            MidiEvent::note_off(60, 0, SR64),
            MidiEvent::control_change(64, 127, 2 * SR64), // sustain at 2.0s
        ];

        let cc = convert_midi_events_to_cc(&events, SR);

        assert_eq!(cc.len(), 2);
        assert_eq!(cc[0].controller, 1);
        assert_eq!(cc[0].value, 64);
        assert!((cc[0].time - 1.0).abs() < 1e-6);
        assert_eq!(cc[1].controller, 64);
    }

    #[test]
    fn reconstruct_reemits_control_change_events() {
        let notes = vec![MidiNoteData {
            note: 60,
            velocity: 100,
            start_time: 0.0,
            duration: 1.0,
        }];
        let cc = vec![MidiCcData {
            controller: 1,
            value: 100,
            time: 0.5,
        }];

        let clip = reconstruct_midi_clip_from_notes(&notes, &cc, SR, Some(2.0));

        let cc_events = clip
            .events
            .iter()
            .filter(|e| matches!(e.event_type, MidiEventType::ControlChange { .. }))
            .count();
        assert_eq!(cc_events, 1, "the recorded CC event must be restored");
    }

    #[test]
    fn reconstruct_without_cc_is_notes_only() {
        let notes = vec![MidiNoteData {
            note: 60,
            velocity: 100,
            start_time: 0.0,
            duration: 1.0,
        }];

        let clip = reconstruct_midi_clip_from_notes(&notes, &[], SR, Some(2.0));

        let has_cc = clip
            .events
            .iter()
            .any(|e| matches!(e.event_type, MidiEventType::ControlChange { .. }));
        assert!(!has_cc);
    }
}
