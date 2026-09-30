use anyhow::{Context, Result};
/// Project serialization for M5: Save & Export
///
/// This module handles saving and loading Boojy Audio projects in `.audio` format.
/// Projects are saved as folders containing:
/// - project.json (all metadata)
/// - audio/ (imported audio files)
/// - cache/ (waveform peaks, etc.)
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

// ========================================================================
// PROJECT DATA STRUCTURES
// ========================================================================

/// Main project data structure
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ProjectData {
    /// Project format version (for future compatibility)
    pub version: String,
    /// Project name
    pub name: String,
    /// Tempo in BPM
    pub tempo: f64,
    /// Sample rate (Hz)
    pub sample_rate: u32,
    /// Time signature (numerator)
    pub time_sig_numerator: u32,
    /// Time signature (denominator)
    pub time_sig_denominator: u32,
    /// All tracks in the project
    pub tracks: Vec<TrackData>,
    /// All audio files referenced in the project
    pub audio_files: Vec<AudioFileData>,
    /// Metronome enabled state
    #[serde(default = "default_true")]
    pub metronome_enabled: bool,
    /// Count-in duration in bars
    #[serde(default = "default_count_in")]
    pub count_in_bars: u32,
    /// Buffer size preset (0=Lowest, 1=Low, 2=Balanced, 3=Safe, 4=High)
    #[serde(default = "default_buffer_size")]
    pub buffer_size_preset: u32,
}

fn default_true() -> bool {
    true
}
fn default_count_in() -> u32 {
    1
}
fn default_buffer_size() -> u32 {
    2
} // Balanced

impl ProjectData {
    /// Create a new empty project
    pub fn new(name: String) -> Self {
        Self {
            version: "1.0".to_string(),
            name,
            tempo: 120.0,
            sample_rate: 48000,
            time_sig_numerator: 4,
            time_sig_denominator: 4,
            tracks: Vec::new(),
            audio_files: Vec::new(),
            metronome_enabled: true,
            count_in_bars: 1,
            buffer_size_preset: 2, // Balanced
        }
    }
}

/// Track data for serialization
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct TrackData {
    /// Track ID
    pub id: u64,
    /// Track name
    pub name: String,
    /// Track type: "Audio", "MIDI", "Return", "Group", "Master"
    pub track_type: String,
    /// Volume in dB
    pub volume_db: f32,
    /// Pan (-1.0 to +1.0)
    pub pan: f32,
    /// Mute state
    pub mute: bool,
    /// Solo state
    pub solo: bool,
    /// Armed for recording
    pub armed: bool,
    /// Clips on this track
    pub clips: Vec<ClipData>,
    /// Effect chain
    pub fx_chain: Vec<EffectData>,
    /// Synthesizer settings (for MIDI tracks with synth instrument)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub synth_settings: Option<SynthData>,
    /// Sampler settings (for MIDI tracks with sampler instrument)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sampler_settings: Option<crate::sampler::SamplerData>,
    /// Drum-kit settings (for MIDI tracks with a drum-kit instrument)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub drum_kit_settings: Option<crate::drum_kit::DrumKitData>,
    /// Send routing to return tracks
    #[serde(default)]
    pub sends: Vec<SendData>,
    /// Parent group track ID (for folder hierarchy)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_group_id: Option<u64>,
    /// Input monitoring enabled
    #[serde(default)]
    pub input_monitoring: bool,
    /// VST3 plugins on this track
    #[serde(default)]
    pub vst3_plugins: Vec<Vst3PluginData>,
    /// Whether this track appears as a row in the arrangement timeline
    #[serde(default = "default_true")]
    pub timeline_visible: bool,
}

/// Clip data (audio or MIDI)
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ClipData {
    /// Clip ID
    pub id: u64,
    /// Start time on timeline (seconds)
    pub start_time: f64,
    /// Offset into the clip (seconds)
    pub offset: f64,
    /// Duration to play (None = full clip)
    pub duration: Option<f64>,
    /// Audio file ID (for audio clips)
    pub audio_file_id: Option<u64>,
    /// MIDI notes (for MIDI clips)
    pub midi_notes: Option<Vec<MidiNoteData>>,
    /// Recorded MIDI control-change events (for MIDI clips: sustain, mod wheel,
    /// expression, etc.). `#[serde(default)]` keeps older projects loadable.
    #[serde(default)]
    pub midi_cc: Option<Vec<MidiCcData>>,
}

/// MIDI note data
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MidiNoteData {
    /// MIDI note number (0-127)
    pub note: u8,
    /// Velocity (0-127)
    pub velocity: u8,
    /// Start time (seconds from clip start)
    pub start_time: f64,
    /// Duration (seconds)
    pub duration: f64,
}

/// Recorded MIDI control-change event
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MidiCcData {
    /// CC controller number (0-127), e.g. 1 = mod wheel, 64 = sustain
    pub controller: u8,
    /// CC value (0-127)
    pub value: u8,
    /// Time (seconds from clip start)
    pub time: f64,
}

/// Audio file metadata
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AudioFileData {
    /// Audio file ID
    pub id: u64,
    /// Original file name
    pub original_name: String,
    /// Relative path within project (e.g., "audio/001-drums.wav")
    pub relative_path: String,
    /// Duration in seconds
    pub duration: f64,
    /// Sample rate
    pub sample_rate: u32,
    /// Number of channels
    pub channels: u32,
}

/// Effect data
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct EffectData {
    /// Effect ID
    pub id: u64,
    /// Effect type: "eq", "compressor", "reverb", "delay", "chorus", "limiter"
    pub effect_type: String,
    /// Effect parameters
    pub parameters: HashMap<String, f32>,
}

/// Send routing data for serialization
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SendData {
    /// Target return track ID
    pub target_track_id: u64,
    /// Send amount (0.0 - 1.0)
    pub amount: f32,
    /// Pre-fader send
    pub pre_fader: bool,
}

/// VST3 plugin data for serialization
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Vst3PluginData {
    /// Effect ID in the audio graph (runtime identifier)
    pub effect_id: u64,
    /// Plugin file path (to reload the plugin)
    pub plugin_path: String,
    /// Plugin name
    pub plugin_name: String,
    /// Is this an instrument (vs effect)?
    pub is_instrument: bool,
    /// Base64-encoded plugin state blob
    pub state_base64: String,
}

/// Synthesizer settings data
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SynthData {
    /// Oscillator type: "sine", "saw", "square", "triangle"
    pub osc_type: String,
    /// Filter cutoff (0.0 - 1.0)
    pub filter_cutoff: f32,
    /// Envelope attack time (seconds)
    pub attack: f32,
    /// Envelope decay time (seconds)
    pub decay: f32,
    /// Envelope sustain level (0.0 - 1.0)
    pub sustain: f32,
    /// Envelope release time (seconds)
    pub release: f32,
}

impl Default for SynthData {
    fn default() -> Self {
        Self {
            osc_type: "saw".to_string(),
            filter_cutoff: 1.0,
            attack: 0.01,
            decay: 0.1,
            sustain: 0.7,
            release: 0.3,
        }
    }
}

// ========================================================================
// PROJECT FILE OPERATIONS
// ========================================================================

/// Save project to `.audio` folder
pub fn save_project(project_data: &ProjectData, project_path: &Path) -> Result<()> {
    eprintln!("💾 [Project] Saving project to: {}", project_path.display());

    // Create project folder structure
    fs::create_dir_all(project_path).context("Failed to create project directory")?;

    let audio_dir = project_path.join("audio");
    fs::create_dir_all(&audio_dir).context("Failed to create audio directory")?;

    let cache_dir = project_path.join("cache");
    fs::create_dir_all(&cache_dir).context("Failed to create cache directory")?;

    // Serialize project data to JSON
    let json =
        serde_json::to_string_pretty(project_data).context("Failed to serialize project data")?;

    // Write project.json
    let json_path = project_path.join("project.json");
    fs::write(&json_path, json).context("Failed to write project.json")?;

    eprintln!("✅ [Project] Saved successfully");
    Ok(())
}

/// Load project from `.audio` folder
pub fn load_project(project_path: &Path) -> Result<ProjectData> {
    eprintln!(
        "📂 [Project] Loading project from: {}",
        project_path.display()
    );

    // Read project.json
    let json_path = project_path.join("project.json");
    let json = fs::read_to_string(&json_path).context("Failed to read project.json")?;

    // Deserialize project data
    let project_data: ProjectData =
        serde_json::from_str(&json).context("Failed to parse project.json")?;

    eprintln!("✅ [Project] Loaded project: {}", project_data.name);
    eprintln!("   - {} tracks", project_data.tracks.len());
    eprintln!("   - {} audio files", project_data.audio_files.len());

    Ok(project_data)
}

/// True when `path` is a file directly inside some project's `audio/` folder
/// (`<Name>.audio/audio/<file>`), i.e. it was put there by an earlier save.
fn is_in_project_audio_dir(path: &Path) -> bool {
    let Some(audio_dir) = path.parent() else {
        return false;
    };
    if audio_dir.file_name().and_then(|n| n.to_str()) != Some("audio") {
        return false;
    }
    audio_dir
        .parent()
        .and_then(|p| p.extension())
        .and_then(|e| e.to_str())
        == Some("audio")
}

/// Remove any leading `NNN-` id prefixes (three or more digits then a dash)
/// that earlier saves stacked onto a file name: `014-010-kick.wav` becomes
/// `kick.wav`. A name that is nothing but prefixes is returned unchanged.
pub fn strip_id_prefixes(name: &str) -> &str {
    let mut rest = name;
    loop {
        let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
        if digits >= 3 && rest.as_bytes().get(digits) == Some(&b'-') && digits + 1 < rest.len() {
            rest = &rest[digits + 1..];
        } else {
            return rest;
        }
    }
}

/// The clean, human file name for an audio file on disk. Files that live in a
/// project's `audio/` folder carry an id prefix added by a save, which is
/// stripped; a user's own file (`808-kick.wav` in their sample folder) is left
/// exactly as named.
pub fn clean_audio_file_name(path: &Path) -> String {
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("audio.wav");
    if is_in_project_audio_dir(path) {
        strip_id_prefixes(name).to_string()
    } else {
        name.to_string()
    }
}

/// If `source_path` already sits in `project_path`'s own `audio/` folder,
/// return its project-relative path (`audio/<file>`) so a save can reuse it
/// instead of copying it again under a longer name.
fn existing_project_audio_path(source_path: &Path, project_path: &Path) -> Option<String> {
    let audio_dir = project_path.join("audio");
    let source_dir = source_path.parent()?;
    let same_dir = match (source_dir.canonicalize(), audio_dir.canonicalize()) {
        (Ok(a), Ok(b)) => a == b,
        _ => source_dir == audio_dir,
    };
    if !same_dir || !source_path.is_file() {
        return None;
    }
    let file_name = source_path.file_name()?.to_str()?;
    Some(format!("audio/{file_name}"))
}

/// `name` with `-{n}` inserted before the extension: `014-kick.wav` -> `014-kick-2.wav`.
fn with_numeric_suffix(name: &str, n: u32) -> String {
    let path = Path::new(name);
    match (
        path.file_stem().and_then(|s| s.to_str()),
        path.extension().and_then(|e| e.to_str()),
    ) {
        (Some(stem), Some(ext)) => format!("{stem}-{n}.{ext}"),
        _ => format!("{name}-{n}"),
    }
}

/// True when the two files have exactly the same bytes (compared in chunks).
fn files_identical(a: &Path, b: &Path) -> bool {
    use std::io::Read;
    let (Ok(fa), Ok(fb)) = (fs::File::open(a), fs::File::open(b)) else {
        return false;
    };
    let (Ok(ma), Ok(mb)) = (fa.metadata(), fb.metadata()) else {
        return false;
    };
    if ma.len() != mb.len() {
        return false;
    }
    let mut ra = std::io::BufReader::new(fa);
    let mut rb = std::io::BufReader::new(fb);
    let (mut ba, mut bb) = (vec![0u8; 64 * 1024], vec![0u8; 64 * 1024]);
    loop {
        let Ok(na) = ra.read(&mut ba) else {
            return false;
        };
        if na == 0 {
            return true;
        }
        if rb.read_exact(&mut bb[..na]).is_err() || ba[..na] != bb[..na] {
            return false;
        }
    }
}

/// Copy audio file into project folder.
///
/// A file that is already inside this project's `audio/` folder is reused as
/// is (no copy, no rename). Otherwise it is copied as `audio/{id:03}-{name}`,
/// with any id prefixes from a previous project's folder stripped first so
/// names never stack up.
pub fn copy_audio_file_to_project(
    source_path: &Path,
    project_path: &Path,
    file_id: u64,
) -> Result<String> {
    if let Some(relative_path) = existing_project_audio_path(source_path, project_path) {
        eprintln!("📁 [Project] Reusing audio file already in project: {relative_path}");
        return Ok(relative_path);
    }

    let audio_dir = project_path.join("audio");
    fs::create_dir_all(&audio_dir).context("Failed to create audio directory")?;

    // Generate filename: 001-filename.wav
    let original_name = clean_audio_file_name(source_path);

    let wanted = format!("{file_id:03}-{original_name}");

    // Never overwrite a file already in audio/: it may belong to another clip
    // (names carry ids from earlier sessions). Use the first free name; a file
    // with identical bytes is this same audio saved before, so reuse it.
    let mut n = 1;
    loop {
        let dest_filename = if n == 1 {
            wanted.clone()
        } else {
            with_numeric_suffix(&wanted, n)
        };
        let dest_path = audio_dir.join(&dest_filename);
        if !dest_path.exists() {
            fs::copy(source_path, &dest_path).context("Failed to copy audio file")?;
            let relative_path = format!("audio/{dest_filename}");
            eprintln!("📁 [Project] Copied audio file: {relative_path}");
            return Ok(relative_path);
        }
        if files_identical(source_path, &dest_path) {
            let relative_path = format!("audio/{dest_filename}");
            eprintln!("📁 [Project] Reusing identical audio file: {relative_path}");
            return Ok(relative_path);
        }
        n += 1;
    }
}

/// Write an in-memory audio clip's samples into the project folder as a WAV.
///
/// Used for clips that have no real source file on disk — e.g. freshly recorded
/// clips, whose `file_path` is only a synthetic in-memory name
/// (`recorded_t{id}_{ts}.wav`). Copying that path with `fs::copy` would fail and
/// abort the whole save, silently losing the recording. Writing the decoded
/// samples directly is the correct path for these clips.
pub fn write_audio_clip_to_project(
    clip: &crate::audio_file::AudioClip,
    project_path: &Path,
    file_id: u64,
) -> Result<String> {
    let audio_dir = project_path.join("audio");
    fs::create_dir_all(&audio_dir).context("Failed to create audio directory")?;

    // Mirror copy_audio_file_to_project's naming: 001-filename.wav
    let original_name = clean_audio_file_name(Path::new(&clip.file_path));
    let wanted = format!("{file_id:03}-{original_name}");

    // Write to a scratch file first, then settle on a name that never
    // overwrites anything: the first free name, or an existing file with
    // identical bytes (this clip saved before).
    let temp_path = audio_dir.join(format!(".saving-{file_id:03}.tmp"));
    let spec = hound::WavSpec {
        channels: clip.channels as u16,
        sample_rate: clip.sample_rate,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };
    let mut writer =
        hound::WavWriter::create(&temp_path, spec).context("Failed to create WAV file")?;
    for sample in &clip.samples {
        writer
            .write_sample(*sample)
            .context("Failed to write audio sample")?;
    }
    writer.finalize().context("Failed to finalize WAV file")?;

    let mut n = 1;
    loop {
        let dest_filename = if n == 1 {
            wanted.clone()
        } else {
            with_numeric_suffix(&wanted, n)
        };
        let dest_path = audio_dir.join(&dest_filename);
        if !dest_path.exists() {
            fs::rename(&temp_path, &dest_path).context("Failed to place WAV file")?;
        } else if files_identical(&temp_path, &dest_path) {
            // Our own scratch file, not a project file.
            let _ = fs::remove_file(&temp_path);
        } else {
            n += 1;
            continue;
        }
        let relative_path = format!("audio/{dest_filename}");
        eprintln!("📁 [Project] Wrote in-memory audio clip: {relative_path}");
        return Ok(relative_path);
    }
}

/// Saved clip ids that are safe to keep on load: those that appear exactly
/// once across every track's clips (audio and MIDI share one id space).
/// A damaged file with duplicate ids gets fresh ids for the duplicates
/// instead of two clips fighting over one id.
pub fn unique_saved_clip_ids(project_data: &ProjectData) -> std::collections::HashSet<u64> {
    let mut counts: HashMap<u64, usize> = HashMap::new();
    for track in &project_data.tracks {
        for clip in &track.clips {
            *counts.entry(clip.id).or_insert(0) += 1;
        }
    }
    counts
        .into_iter()
        .filter_map(|(id, n)| (n == 1).then_some(id))
        .collect()
}

/// Resolve audio file path (relative to project folder)
pub fn resolve_audio_file_path(project_path: &Path, relative_path: &str) -> PathBuf {
    project_path.join(relative_path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_project_serialization() {
        let project = ProjectData::new("Test Project".to_string());
        let json = serde_json::to_string_pretty(&project).unwrap();
        eprintln!("Project JSON:\n{json}");

        let parsed: ProjectData = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.name, "Test Project");
        assert!((parsed.tempo - 120.0).abs() < 1e-6);
    }

    #[test]
    fn test_save_load_project() {
        let temp_dir = env::temp_dir().join("boojy_test_project.audio");
        let _ = fs::remove_dir_all(&temp_dir); // Clean up if exists

        let mut project = ProjectData::new("Test Save/Load".to_string());
        project.tempo = 140.0;

        // Save
        save_project(&project, &temp_dir).unwrap();
        assert!(temp_dir.join("project.json").exists());
        assert!(temp_dir.join("audio").exists());
        assert!(temp_dir.join("cache").exists());

        // Load
        let loaded = load_project(&temp_dir).unwrap();
        assert_eq!(loaded.name, "Test Save/Load");
        assert!((loaded.tempo - 140.0).abs() < 1e-6);

        // Clean up
        fs::remove_dir_all(&temp_dir).unwrap();
    }

    #[test]
    fn test_write_in_memory_audio_clip() {
        // Regression: recorded clips have a synthetic file_path that never
        // exists on disk; save must write their samples out rather than copying.
        let temp_dir = env::temp_dir().join("boojy_test_inmem_clip.audio");
        let _ = fs::remove_dir_all(&temp_dir);
        fs::create_dir_all(&temp_dir).unwrap();

        let clip = crate::audio_file::AudioClip {
            samples: vec![0.1, -0.1, 0.2, -0.2], // 2 stereo frames
            channels: 2,
            sample_rate: 48000,
            duration_seconds: 0.0,
            file_path: "recorded_t1_123456.wav".to_string(),
        };

        let rel = write_audio_clip_to_project(&clip, &temp_dir, 1).unwrap();
        assert_eq!(rel, "audio/001-recorded_t1_123456.wav");

        let written = resolve_audio_file_path(&temp_dir, &rel);
        assert!(written.exists());

        // The samples must round-trip through hound.
        let loaded = crate::audio_file::load_audio_file(&written).unwrap();
        assert_eq!(loaded.channels, 2);
        assert_eq!(loaded.samples.len(), clip.samples.len());
        for (a, b) in loaded.samples.iter().zip(clip.samples.iter()) {
            assert!((a - b).abs() < 1e-6);
        }

        fs::remove_dir_all(&temp_dir).unwrap();
    }

    #[test]
    fn test_strip_id_prefixes() {
        assert_eq!(strip_id_prefixes("014-010-007-005-kick.wav"), "kick.wav");
        assert_eq!(strip_id_prefixes("003-kick.wav"), "kick.wav");
        assert_eq!(strip_id_prefixes("1234-kick.wav"), "kick.wav");
        // Not id prefixes: too few digits, or no dash, or nothing after it
        assert_eq!(strip_id_prefixes("12-kick.wav"), "12-kick.wav");
        assert_eq!(strip_id_prefixes("kick.wav"), "kick.wav");
        assert_eq!(strip_id_prefixes("808kick.wav"), "808kick.wav");
        assert_eq!(strip_id_prefixes("003-"), "003-");
    }

    #[test]
    fn test_clean_audio_file_name_only_strips_inside_a_project() {
        // Saved by an earlier project save: prefix removed
        assert_eq!(
            clean_audio_file_name(Path::new("/x/MySong.audio/audio/012-007-snare.wav")),
            "snare.wav"
        );
        // The user's own sample named like an id prefix: left alone
        assert_eq!(
            clean_audio_file_name(Path::new("/samples/808-kick.wav")),
            "808-kick.wav"
        );
    }

    #[test]
    fn test_copy_reuses_file_already_in_project_audio_dir() {
        let project = env::temp_dir().join("boojy_test_reuse.audio");
        let _ = fs::remove_dir_all(&project);
        fs::create_dir_all(project.join("audio")).unwrap();
        let file = project.join("audio/005-kick.wav");
        fs::write(&file, b"x").unwrap();

        // Same project: reused, nothing new on disk, even under a different id
        let rel = copy_audio_file_to_project(&file, &project, 9).unwrap();
        assert_eq!(rel, "audio/005-kick.wav");
        assert_eq!(fs::read_dir(project.join("audio")).unwrap().count(), 1);

        // Another project: copied with the prefix replaced, not stacked
        let other = env::temp_dir().join("boojy_test_reuse_other.audio");
        let _ = fs::remove_dir_all(&other);
        let rel = copy_audio_file_to_project(&file, &other, 9).unwrap();
        assert_eq!(rel, "audio/009-kick.wav");

        fs::remove_dir_all(&project).unwrap();
        fs::remove_dir_all(&other).unwrap();
    }

    #[test]
    fn test_copy_never_overwrites_an_existing_audio_file() {
        let root = env::temp_dir().join("boojy_test_no_overwrite");
        let _ = fs::remove_dir_all(&root);
        let project = root.join("P.audio");
        fs::create_dir_all(project.join("audio")).unwrap();
        fs::write(project.join("audio/014-kick.wav"), b"AAAA").unwrap();

        let source = root.join("kick.wav");
        fs::write(&source, b"BBBB").unwrap();

        let rel = copy_audio_file_to_project(&source, &project, 14).unwrap();
        assert_eq!(rel, "audio/014-kick-2.wav");
        assert_eq!(
            fs::read(project.join("audio/014-kick.wav")).unwrap(),
            b"AAAA"
        );
        assert_eq!(fs::read(project.join(&rel)).unwrap(), b"BBBB");

        // Saving the same source again reuses its copy instead of piling up
        let again = copy_audio_file_to_project(&source, &project, 14).unwrap();
        assert_eq!(again, rel);

        // A third different file takes the next free name
        let other = root.join("other/kick.wav");
        fs::create_dir_all(other.parent().unwrap()).unwrap();
        fs::write(&other, b"CCCC").unwrap();
        let third = copy_audio_file_to_project(&other, &project, 14).unwrap();
        assert_eq!(third, "audio/014-kick-3.wav");
        assert_eq!(
            fs::read(project.join("audio/014-kick.wav")).unwrap(),
            b"AAAA"
        );

        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn test_write_in_memory_clip_never_overwrites_an_existing_audio_file() {
        let root = env::temp_dir().join("boojy_test_no_overwrite_inmem");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("audio")).unwrap();
        fs::write(root.join("audio/014-take.wav"), b"AAAA").unwrap();

        let clip = crate::audio_file::AudioClip {
            samples: vec![0.1, -0.1, 0.2, -0.2],
            channels: 2,
            sample_rate: 48000,
            duration_seconds: 0.0,
            file_path: "take.wav".to_string(),
        };

        let rel = write_audio_clip_to_project(&clip, &root, 14).unwrap();
        assert_eq!(rel, "audio/014-take-2.wav");
        assert_eq!(fs::read(root.join("audio/014-take.wav")).unwrap(), b"AAAA");
        assert!(root.join(&rel).exists());

        // Saving the same clip again reuses the file; no scratch file is left
        let again = write_audio_clip_to_project(&clip, &root, 14).unwrap();
        assert_eq!(again, rel);
        let mut names: Vec<String> = fs::read_dir(root.join("audio"))
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        assert_eq!(names, vec!["014-take-2.wav", "014-take.wav"]);

        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn test_time_signature_roundtrips() {
        let mut project = ProjectData::new("Waltz".to_string());
        project.time_sig_numerator = 3;
        project.time_sig_denominator = 4;

        let json = serde_json::to_string(&project).unwrap();
        let parsed: ProjectData = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.time_sig_numerator, 3);
        assert_eq!(parsed.time_sig_denominator, 4);
    }

    #[test]
    fn test_midi_cc_roundtrips_on_clip() {
        let clip = ClipData {
            id: 1,
            start_time: 0.0,
            offset: 0.0,
            duration: Some(4.0),
            audio_file_id: None,
            midi_notes: Some(vec![]),
            midi_cc: Some(vec![MidiCcData {
                controller: 1, // mod wheel
                value: 64,
                time: 1.5,
            }]),
        };

        let json = serde_json::to_string(&clip).unwrap();
        let parsed: ClipData = serde_json::from_str(&json).unwrap();

        let cc = parsed.midi_cc.expect("CC should survive round-trip");
        assert_eq!(cc.len(), 1);
        assert_eq!(cc[0].controller, 1);
        assert_eq!(cc[0].value, 64);
    }

    #[test]
    fn test_old_clip_without_midi_cc_still_loads() {
        // Older projects predate the midi_cc field; #[serde(default)] must keep
        // them loadable rather than failing deserialization.
        let json = r#"{
            "id": 1,
            "start_time": 0.0,
            "offset": 0.0,
            "duration": 4.0,
            "audio_file_id": null,
            "midi_notes": []
        }"#;

        let parsed: ClipData = serde_json::from_str(json).unwrap();
        assert!(parsed.midi_cc.is_none());
    }
}
