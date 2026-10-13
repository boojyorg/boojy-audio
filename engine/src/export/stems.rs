//! Stem export - per-track audio rendering
//!
//! Exports each track as a separate audio file.

use super::mp3::export_mp3;
use super::options::{ExportOptions, ExportResult};
use super::partial::PartialFiles;
use super::wav::export_wav;
use std::path::{Path, PathBuf};

/// Information about a track for stem export
#[derive(Debug, Clone)]
pub struct StemTrackInfo {
    /// Track ID
    pub id: u64,
    /// Track name (used in filename)
    pub name: String,
    /// Whether to include this track in stem export
    pub selected: bool,
}

/// Result of exporting all stems
#[derive(Debug)]
pub struct StemExportResult {
    /// Individual stem results
    pub stems: Vec<ExportResult>,
    /// Total number of stems exported
    pub count: usize,
    /// Total file size of all stems
    pub total_size: u64,
}

impl StemExportResult {
    /// Create a new empty stem export result
    pub fn new() -> Self {
        Self {
            stems: Vec::new(),
            count: 0,
            total_size: 0,
        }
    }

    /// Add a stem result
    pub fn add(&mut self, result: ExportResult) {
        self.total_size += result.file_size;
        self.count += 1;
        self.stems.push(result);
    }

    /// Serialize to JSON
    pub fn to_json(&self) -> String {
        serde_json::to_string(&self.stems).unwrap_or_else(|_| "[]".to_string())
    }
}

impl Default for StemExportResult {
    fn default() -> Self {
        Self::new()
    }
}

/// Generate stem filename from base name and track name
///
/// # Arguments
/// * `base_name` - Base filename (e.g., "Summer Vibes")
/// * `track_name` - Track name (e.g., "Drums")
/// * `extension` - File extension (e.g., "wav" or "mp3")
///
/// # Returns
/// Filename like "Summer Vibes - Drums.wav"
pub fn generate_stem_filename(base_name: &str, track_name: &str, extension: &str) -> String {
    // Sanitize track name for filesystem
    let safe_track_name: String = track_name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect();

    format!("{base_name} - {safe_track_name}.{extension}")
}

/// Generate stem output path
///
/// # Arguments
/// * `output_dir` - Output directory path
/// * `base_name` - Base filename
/// * `track_name` - Track name
/// * `options` - Export options (for extension)
///
/// # Returns
/// Full path for the stem file
pub fn generate_stem_path(
    output_dir: &Path,
    base_name: &str,
    track_name: &str,
    options: &ExportOptions,
) -> PathBuf {
    let filename = generate_stem_filename(base_name, track_name, options.file_extension());
    output_dir.join(filename)
}

/// Export a single stem (track audio)
///
/// # Arguments
/// * `samples` - Rendered audio for this track (stereo interleaved)
/// * `output_path` - Path to output file
/// * `options` - Export options
/// * `on_block` - MP3 encoding progress (0–1); `false` stops it
///
/// # Returns
/// Export result
pub fn export_stem(
    samples: &[f32],
    output_path: &Path,
    options: &ExportOptions,
    on_block: &mut dyn FnMut(f64) -> bool,
) -> Result<ExportResult, String> {
    eprintln!(
        "🎚️ [Stem Export] Exporting stem to {}",
        output_path.display()
    );

    match &options.format {
        super::options::ExportFormat::Wav { .. } => export_wav(samples, output_path, options),
        super::options::ExportFormat::Mp3 { .. } => {
            export_mp3(samples, output_path, options, on_block)
        }
    }
}

/// Export multiple stems to a directory
///
/// # Arguments
/// * `tracks` - List of (`track_info`, `rendered_samples`) pairs
/// * `output_dir` - Output directory path
/// * `base_name` - Base filename
/// * `options` - Export options
/// * `files` - Where the stems are written until they're all done
/// * `on_block` - Progress through all the stems (0–1); `false` stops the
///   export with "Export cancelled"
///
/// # Returns
/// Stem export result with all exported files
pub fn export_stems(
    tracks: &[(StemTrackInfo, Vec<f32>)],
    output_dir: &Path,
    base_name: &str,
    options: &ExportOptions,
    files: &mut PartialFiles,
    on_block: &mut dyn FnMut(f64) -> bool,
) -> Result<StemExportResult, String> {
    eprintln!(
        "🎚️ [Stem Export] Exporting {} tracks to {}",
        tracks.len(),
        output_dir.display()
    );

    // Create output directory if it doesn't exist
    std::fs::create_dir_all(output_dir)
        .map_err(|e| format!("Failed to create output directory: {e}"))?;

    let mut result = StemExportResult::new();
    let selected = tracks.iter().filter(|(info, _)| info.selected).count();

    for (i, (track_info, samples)) in tracks.iter().filter(|(info, _)| info.selected).enumerate() {
        let output_path = generate_stem_path(output_dir, base_name, &track_info.name, options);

        // Written under a temporary name; the caller moves every stem into
        // place once all are done ([`PartialFiles::commit`]).
        // This stem's share of the progress.
        let share = |done: f64| (i as f64 + done) / selected as f64;
        let mut on_stem_block = |done| on_block(share(done));
        match export_stem(
            samples,
            &files.path_for(&output_path),
            options,
            &mut on_stem_block,
        ) {
            Ok(mut stem_result) => {
                stem_result.path = output_path.to_string_lossy().to_string();
                eprintln!(
                    "   ✅ {} - {:.2} MB",
                    track_info.name,
                    stem_result.file_size as f64 / 1024.0 / 1024.0
                );
                result.add(stem_result);
                if !on_block(share(1.0)) {
                    return Err("Export cancelled".to_string());
                }
            }
            Err(e) if e == "Export cancelled" => return Err(e),
            Err(e) => {
                eprintln!("   ❌ {} - {}", track_info.name, e);
                return Err(format!(
                    "Failed to export stem '{}': {}",
                    track_info.name, e
                ));
            }
        }
    }

    eprintln!(
        "✅ [Stem Export] Completed: {} stems, {:.2} MB total",
        result.count,
        result.total_size as f64 / 1024.0 / 1024.0
    );

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_stem_filename() {
        assert_eq!(
            generate_stem_filename("Song", "Drums", "wav"),
            "Song - Drums.wav"
        );

        assert_eq!(
            generate_stem_filename("My Song", "Lead/Synth", "mp3"),
            "My Song - Lead_Synth.mp3"
        );
    }

    #[test]
    fn test_stem_export_result() {
        let mut result = StemExportResult::new();
        assert_eq!(result.count, 0);

        result.add(ExportResult::new(
            "/path/test.wav".to_string(),
            1000,
            5.0,
            44100,
            "WAV 16-bit".to_string(),
        ));

        assert_eq!(result.count, 1);
        assert_eq!(result.total_size, 1000);
    }
}
