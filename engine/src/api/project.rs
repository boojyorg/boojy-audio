//! Project save/load/export API functions
//!
//! Functions for saving, loading, and exporting projects.

use super::helpers::{get_audio_clips, get_audio_graph};
use std::path::Path;
use std::sync::Arc;

// ============================================================================
// PROJECT SAVE/LOAD API
// ============================================================================

/// Save project to .audio folder
///
/// # Arguments
/// * `project_name` - Name of the project
/// * `project_path_str` - Path to the .audio folder (e.g., "/path/to/MyProject.audio")
///
/// # Returns
/// Success message on completion
pub fn save_project(project_name: String, project_path_str: String) -> Result<String, String> {
    use crate::project;

    let project_path = Path::new(&project_path_str);

    eprintln!(
        "💾 [API] Saving project '{}' to {:?}",
        project_name, project_path
    );

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Export audio graph state to ProjectData
    let mut project_data = graph.export_to_project_data(project_name);

    // Copy audio files to project folder and update paths
    let clips_mutex = get_audio_clips()?;
    let clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;

    for audio_file in &mut project_data.audio_files {
        // Find the corresponding clip
        if let Some(clip_arc) = clips_map.get(&audio_file.id) {
            let source_path = Path::new(&clip_arc.file_path);

            // Copy file to project folder
            let relative_path =
                project::copy_audio_file_to_project(source_path, project_path, audio_file.id)
                    .map_err(|e| e.to_string())?;

            // Update the relative path in project data
            audio_file.relative_path = relative_path;
        }
    }

    // Save project data to JSON
    project::save_project(&project_data, project_path).map_err(|e| e.to_string())?;

    eprintln!("✅ [API] Project saved successfully");
    Ok(format!("Project saved to {:?}", project_path))
}

/// Load project from .audio folder
///
/// # Arguments
/// * `project_path_str` - Path to the .audio folder
///
/// # Returns
/// Success message with project name
pub fn load_project(project_path_str: String) -> Result<String, String> {
    use crate::audio_file::load_audio_file;
    use crate::project;

    let project_path = Path::new(&project_path_str);

    eprintln!("📂 [API] Loading project from {:?}", project_path);

    // Load project data from JSON
    let project_data = project::load_project(project_path).map_err(|e| e.to_string())?;

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Stop playback if running
    let _ = graph.stop();

    // Clear existing clips and tracks (except master)
    // TODO: Add proper clear methods to AudioGraph

    // Load audio files from project folder
    let clips_mutex = get_audio_clips()?;
    let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;

    // Clear existing clips
    clips_map.clear();

    for audio_file_data in &project_data.audio_files {
        let audio_file_path =
            project::resolve_audio_file_path(project_path, &audio_file_data.relative_path);

        eprintln!("📁 [API] Loading audio file: {:?}", audio_file_path);

        // Load the audio file
        let clip = load_audio_file(&audio_file_path)
            .map_err(|e| format!("Failed to load audio file {:?}: {}", audio_file_path, e))?;

        let clip_arc = Arc::new(clip);
        clips_map.insert(audio_file_data.id, clip_arc);
    }

    // Restore audio graph state from project data
    graph
        .restore_from_project_data(project_data.clone())
        .map_err(|e| e.to_string())?;

    eprintln!("✅ [API] Project loaded successfully");
    Ok(format!("Loaded project: {}", project_data.name))
}

/// Export project to WAV file
///
/// # Arguments
/// * `output_path_str` - Path to output WAV file
/// * `normalize` - Whether to normalize the output to -0.1 dBFS
///
/// # Returns
/// Success message with file path
pub fn export_to_wav(output_path_str: String, normalize: bool) -> Result<String, String> {
    let output_path = Path::new(&output_path_str);

    eprintln!("🎵 [API] Exporting to WAV: {:?}", output_path);

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Calculate project duration
    let duration = graph.calculate_project_duration();
    if duration <= 1.0 {
        return Err("No audio content to export".to_string());
    }

    eprintln!("🎵 [API] Project duration: {:.2}s", duration);

    // Render offline
    let samples = graph.render_offline(duration);

    if samples.is_empty() {
        return Err("Render produced no audio".to_string());
    }

    // Optionally normalize to -0.1 dBFS (about 0.989 amplitude)
    let final_samples = if normalize {
        let max_amplitude = samples
            .iter()
            .map(|s| s.abs())
            .fold(0.0f32, |a, b| a.max(b));

        if max_amplitude > 0.0 {
            let target_amplitude = 0.989f32; // -0.1 dBFS
            let gain = target_amplitude / max_amplitude;
            eprintln!(
                "🎵 [API] Normalizing: max={:.4}, gain={:.4}",
                max_amplitude, gain
            );
            samples.iter().map(|s| s * gain).collect()
        } else {
            samples
        }
    } else {
        samples
    };

    // Write WAV using hound
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: 48000,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };

    let mut writer =
        hound::WavWriter::create(output_path, spec).map_err(|e| format!("Failed to create WAV file: {}", e))?;

    for sample in &final_samples {
        writer
            .write_sample(*sample)
            .map_err(|e| format!("Failed to write sample: {}", e))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV file: {}", e))?;

    let file_size = std::fs::metadata(output_path)
        .map(|m| m.len())
        .unwrap_or(0);

    eprintln!(
        "✅ [API] WAV export complete: {} samples, {:.2} MB",
        final_samples.len(),
        file_size as f64 / 1024.0 / 1024.0
    );

    Ok(format!("Exported to {}", output_path_str))
}

// ============================================================================
// ENHANCED EXPORT API (M8)
// ============================================================================

/// Check if ffmpeg is available for MP3 encoding
pub fn is_ffmpeg_available() -> bool {
    crate::export::is_ffmpeg_available()
}

/// Export project with configurable options (WAV or MP3)
///
/// # Arguments
/// * `output_path_str` - Path to output file
/// * `options_json` - JSON string of ExportOptions
///
/// # Returns
/// JSON string with ExportResult on success
pub fn export_audio(output_path_str: String, options_json: String) -> Result<String, String> {
    use crate::export::{export_mp3, export_wav, ExportFormat, ExportOptions};

    let output_path = Path::new(&output_path_str);

    eprintln!("🎵 [API] Exporting audio to: {:?}", output_path);
    eprintln!("🎵 [API] Options: {}", options_json);

    // Parse options from JSON
    let options: ExportOptions =
        serde_json::from_str(&options_json).map_err(|e| format!("Invalid options JSON: {}", e))?;

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Calculate project duration
    let duration = graph.calculate_project_duration();
    if duration <= 1.0 {
        return Err("No audio content to export".to_string());
    }

    eprintln!("🎵 [API] Project duration: {:.2}s", duration);

    // Render offline
    let samples = graph.render_offline(duration);

    if samples.is_empty() {
        return Err("Render produced no audio".to_string());
    }

    // Export based on format
    let result = match &options.format {
        ExportFormat::Wav { .. } => export_wav(&samples, output_path, &options)?,
        ExportFormat::Mp3 { .. } => export_mp3(&samples, output_path, &options)?,
    };

    // Return result as JSON
    Ok(result.to_json())
}

/// Export project to WAV with configurable options
///
/// # Arguments
/// * `output_path_str` - Path to output WAV file
/// * `bit_depth` - Bit depth: 16, 24, or 32 (float)
/// * `sample_rate` - Sample rate: 44100 or 48000
/// * `normalize` - Whether to normalize the output
/// * `dither` - Whether to apply dithering (for 16/24-bit)
/// * `mono` - Whether to mixdown to mono
///
/// # Returns
/// JSON string with ExportResult on success
pub fn export_wav_with_options(
    output_path_str: String,
    bit_depth: i32,
    sample_rate: u32,
    normalize: bool,
    dither: bool,
    mono: bool,
) -> Result<String, String> {
    use crate::export::{export_progress, export_wav, ExportOptions, WavBitDepth};

    let progress = export_progress();
    progress.start("Preparing WAV export...");

    let output_path = Path::new(&output_path_str);

    let bit_depth_enum = match bit_depth {
        16 => WavBitDepth::Int16,
        24 => WavBitDepth::Int24,
        32 => WavBitDepth::Float32,
        _ => {
            progress.fail("Invalid bit depth");
            return Err(format!("Invalid bit depth: {}. Use 16, 24, or 32", bit_depth));
        }
    };

    let options = ExportOptions::wav(bit_depth_enum)
        .with_sample_rate(sample_rate)
        .with_normalize(normalize)
        .with_dither(dither)
        .with_mono(mono);

    eprintln!(
        "🎵 [API] Exporting WAV: {:?}, {}-bit, {}Hz",
        output_path, bit_depth, sample_rate
    );

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(10, "Accessing audio graph...");

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Calculate project duration
    let duration = graph.calculate_project_duration();
    if duration <= 1.0 {
        progress.fail("No audio content");
        return Err("No audio content to export".to_string());
    }

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(20, "Rendering audio...");

    // Render offline
    let samples = graph.render_offline(duration);

    if samples.is_empty() {
        progress.fail("Render produced no audio");
        return Err("Render produced no audio".to_string());
    }

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(70, "Encoding WAV file...");

    // Export
    let result = match export_wav(&samples, output_path, &options) {
        Ok(r) => r,
        Err(e) => {
            progress.fail(&e);
            return Err(e);
        }
    };

    progress.complete();

    Ok(result.to_json())
}

/// Export project to MP3 with configurable options
///
/// # Arguments
/// * `output_path_str` - Path to output MP3 file
/// * `bitrate` - Bitrate: 128, 192, or 320 kbps
/// * `sample_rate` - Sample rate: 44100 or 48000
/// * `normalize` - Whether to normalize the output
/// * `mono` - Whether to mixdown to mono
///
/// # Returns
/// JSON string with ExportResult on success
pub fn export_mp3_with_options(
    output_path_str: String,
    bitrate: i32,
    sample_rate: u32,
    normalize: bool,
    mono: bool,
) -> Result<String, String> {
    use crate::export::{export_mp3, export_progress, ExportOptions, Mp3Bitrate};

    let progress = export_progress();
    progress.start("Preparing MP3 export...");

    let output_path = Path::new(&output_path_str);

    let bitrate_enum = match bitrate {
        128 => Mp3Bitrate::Kbps128,
        192 => Mp3Bitrate::Kbps192,
        320 => Mp3Bitrate::Kbps320,
        _ => {
            progress.fail("Invalid bitrate");
            return Err(format!("Invalid bitrate: {}. Use 128, 192, or 320", bitrate));
        }
    };

    let options = ExportOptions::mp3(bitrate_enum)
        .with_sample_rate(sample_rate)
        .with_normalize(normalize)
        .with_mono(mono);

    eprintln!(
        "🎵 [API] Exporting MP3: {:?}, {} kbps, {}Hz",
        output_path, bitrate, sample_rate
    );

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(10, "Accessing audio graph...");

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Calculate project duration
    let duration = graph.calculate_project_duration();
    if duration <= 1.0 {
        progress.fail("No audio content");
        return Err("No audio content to export".to_string());
    }

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(20, "Rendering audio...");

    // Render offline
    let samples = graph.render_offline(duration);

    if samples.is_empty() {
        progress.fail("Render produced no audio");
        return Err("Render produced no audio".to_string());
    }

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(60, "Encoding MP3 file...");

    // Export
    let result = match export_mp3(&samples, output_path, &options) {
        Ok(r) => r,
        Err(e) => {
            progress.fail(&e);
            return Err(e);
        }
    };

    progress.complete();

    Ok(result.to_json())
}

/// Write ID3 metadata to an MP3 file
///
/// # Arguments
/// * `file_path_str` - Path to the MP3 file
/// * `metadata_json` - JSON string of ExportMetadata
///
/// # Returns
/// Success message
pub fn write_mp3_metadata(file_path_str: String, metadata_json: String) -> Result<String, String> {
    use crate::export::{write_id3_tags, ExportMetadata};

    let file_path = Path::new(&file_path_str);

    let metadata: ExportMetadata = serde_json::from_str(&metadata_json)
        .map_err(|e| format!("Invalid metadata JSON: {}", e))?;

    write_id3_tags(file_path, &metadata)?;

    Ok("Metadata written successfully".to_string())
}

// ============================================================================
// STEM EXPORT API
// ============================================================================

/// Get list of tracks available for stem export
/// Returns JSON array of {id, name, type} objects
pub fn get_tracks_for_stems() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let tracks = graph.get_tracks_for_stem_export();

    let json_tracks: Vec<serde_json::Value> = tracks
        .iter()
        .map(|(id, name, track_type)| {
            serde_json::json!({
                "id": id,
                "name": name,
                "type": track_type
            })
        })
        .collect();

    serde_json::to_string(&json_tracks).map_err(|e| e.to_string())
}

/// Export stems (individual tracks) to a directory
///
/// # Arguments
/// * `output_dir` - Directory to export stems to
/// * `base_name` - Base filename for stems (e.g., "My Song")
/// * `track_ids_json` - JSON array of track IDs to export, or null for all tracks
/// * `options_json` - JSON string of ExportOptions
///
/// # Returns
/// JSON string with StemExportResult
pub fn export_stems(
    output_dir: String,
    base_name: String,
    track_ids_json: String,
    options_json: String,
) -> Result<String, String> {
    use crate::export::{
        export_progress, export_stems as do_export_stems, ExportOptions, StemTrackInfo,
    };

    let progress = export_progress();
    progress.start("Preparing stem export...");

    let output_path = Path::new(&output_dir);

    eprintln!("🎚️ [API] Exporting stems to: {:?}", output_path);

    // Parse options
    let options: ExportOptions = match serde_json::from_str(&options_json) {
        Ok(o) => o,
        Err(e) => {
            progress.fail("Invalid options");
            return Err(format!("Invalid options JSON: {}", e));
        }
    };

    // Parse track IDs (null or empty array means all tracks)
    let selected_track_ids: Option<Vec<u64>> = if track_ids_json.is_empty()
        || track_ids_json == "null"
        || track_ids_json == "[]"
    {
        None
    } else {
        match serde_json::from_str(&track_ids_json) {
            Ok(ids) => Some(ids),
            Err(e) => {
                progress.fail("Invalid track IDs");
                return Err(format!("Invalid track IDs: {}", e));
            }
        }
    };

    // Check for cancellation
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(5, "Accessing audio graph...");

    // Get audio graph
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Calculate project duration
    let duration = graph.calculate_project_duration();
    if duration <= 1.0 {
        progress.fail("No audio content");
        return Err("No audio content to export".to_string());
    }

    // Get tracks for export
    let all_tracks = graph.get_tracks_for_stem_export();

    // Filter to selected tracks
    let tracks_to_export: Vec<_> = all_tracks
        .iter()
        .filter(|(track_id, _, _)| match &selected_track_ids {
            Some(ids) => ids.contains(track_id),
            None => true,
        })
        .collect();

    let total_tracks = tracks_to_export.len();
    if total_tracks == 0 {
        progress.fail("No tracks selected");
        return Err("No tracks selected for export".to_string());
    }

    // Render each track
    let mut tracks_with_samples: Vec<(StemTrackInfo, Vec<f32>)> = Vec::new();

    for (i, (track_id, track_name, _track_type)) in tracks_to_export.iter().enumerate() {
        // Check for cancellation
        if progress.is_cancelled() {
            progress.fail("Export cancelled");
            return Err("Export cancelled".to_string());
        }

        // Progress: 10% to 70% is rendering tracks
        let track_progress = 10 + (i as u32 * 60 / total_tracks as u32);
        progress.update(
            track_progress,
            &format!("Rendering track {} of {}: {}", i + 1, total_tracks, track_name),
        );

        eprintln!(
            "🎚️ [API] Rendering track '{}' (ID: {})",
            track_name, track_id
        );

        let samples = graph.render_track_offline(*track_id, duration);

        // Skip empty tracks
        if samples.iter().all(|&s| s.abs() < 0.0001) {
            eprintln!("   ⏭️ Track '{}' is silent, skipping", track_name);
            continue;
        }

        tracks_with_samples.push((
            StemTrackInfo {
                id: *track_id,
                name: track_name.clone(),
                selected: true,
            },
            samples,
        ));
    }

    if tracks_with_samples.is_empty() {
        progress.fail("No audio content in selected tracks");
        return Err("No tracks with audio content to export".to_string());
    }

    // Check for cancellation before encoding
    if progress.is_cancelled() {
        progress.fail("Export cancelled");
        return Err("Export cancelled".to_string());
    }

    progress.update(75, "Encoding stem files...");

    // Export stems
    let result = match do_export_stems(&tracks_with_samples, output_path, &base_name, &options) {
        Ok(r) => r,
        Err(e) => {
            progress.fail(&e);
            return Err(e);
        }
    };

    progress.complete();

    eprintln!(
        "✅ [API] Stem export complete: {} stems, {:.2} MB total",
        result.count,
        result.total_size as f64 / 1024.0 / 1024.0
    );

    Ok(result.to_json())
}
