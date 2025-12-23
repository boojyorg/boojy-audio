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
use anyhow::{Context, Result};

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

fn default_true() -> bool { true }
fn default_count_in() -> u32 { 2 }
fn default_buffer_size() -> u32 { 2 } // Balanced

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
            count_in_bars: 2,
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
    /// Synthesizer settings (for MIDI tracks)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub synth_settings: Option<SynthData>,
    /// Send routing to return tracks
    #[serde(default)]
    pub sends: Vec<SendData>,
    /// Parent group track ID (for folder hierarchy)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_group_id: Option<u64>,
    /// Input monitoring enabled
    #[serde(default)]
    pub input_monitoring: bool,
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
    eprintln!("💾 [Project] Saving project to: {:?}", project_path);

    // Create project folder structure
    fs::create_dir_all(project_path)
        .context("Failed to create project directory")?;

    let audio_dir = project_path.join("audio");
    fs::create_dir_all(&audio_dir)
        .context("Failed to create audio directory")?;

    let cache_dir = project_path.join("cache");
    fs::create_dir_all(&cache_dir)
        .context("Failed to create cache directory")?;

    // Serialize project data to JSON
    let json = serde_json::to_string_pretty(project_data)
        .context("Failed to serialize project data")?;

    // Write project.json
    let json_path = project_path.join("project.json");
    fs::write(&json_path, json)
        .context("Failed to write project.json")?;

    eprintln!("✅ [Project] Saved successfully");
    Ok(())
}

/// Load project from `.audio` folder
pub fn load_project(project_path: &Path) -> Result<ProjectData> {
    eprintln!("📂 [Project] Loading project from: {:?}", project_path);

    // Read project.json
    let json_path = project_path.join("project.json");
    let json = fs::read_to_string(&json_path)
        .context("Failed to read project.json")?;

    // Deserialize project data
    let project_data: ProjectData = serde_json::from_str(&json)
        .context("Failed to parse project.json")?;

    eprintln!("✅ [Project] Loaded project: {}", project_data.name);
    eprintln!("   - {} tracks", project_data.tracks.len());
    eprintln!("   - {} audio files", project_data.audio_files.len());

    Ok(project_data)
}

/// Copy audio file into project folder
pub fn copy_audio_file_to_project(
    source_path: &Path,
    project_path: &Path,
    file_id: u64,
) -> Result<String> {
    let audio_dir = project_path.join("audio");
    fs::create_dir_all(&audio_dir)
        .context("Failed to create audio directory")?;

    // Generate filename: 001-filename.wav
    let original_name = source_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("audio.wav");

    let dest_filename = format!("{:03}-{}", file_id, original_name);
    let dest_path = audio_dir.join(&dest_filename);

    // Copy file
    fs::copy(source_path, &dest_path)
        .context("Failed to copy audio file")?;

    // Return relative path
    let relative_path = format!("audio/{}", dest_filename);
    eprintln!("📁 [Project] Copied audio file: {}", relative_path);
    Ok(relative_path)
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
        eprintln!("Project JSON:\n{}", json);

        let parsed: ProjectData = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.name, "Test Project");
        assert_eq!(parsed.tempo, 120.0);
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
        assert_eq!(loaded.tempo, 140.0);

        // Clean up
        fs::remove_dir_all(&temp_dir).unwrap();
    }
}
