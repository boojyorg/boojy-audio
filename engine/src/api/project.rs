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
