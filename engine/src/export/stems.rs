//! Stem export - per-track audio rendering
//!
//! Exports each track as a separate audio file.

use super::mp3::export_mp3;
use super::options::{ExportOptions, ExportResult};
use super::partial::PartialFiles;
use super::wav::export_wav;
use std::path::Path;

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

/// A track name with the characters a filename can't hold replaced.
fn safe_track_name(track_name: &str) -> String {
    track_name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect()
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
    format!("{base_name} - {}.{extension}", safe_track_name(track_name))
}

/// The names stems get in their filenames, one per track and in the same
/// order, each different from the others: a name already taken gets a
/// number ("Drums", "Drums 2", "Drums 3").
///
/// Two names are the same file when they differ only in case (macOS and
/// Windows don't tell `Drums.wav` from `drums.wav`) or in characters the
/// filename can't hold (`Lead/Synth` and `Lead_Synth`). Sharing one name,
/// the second stem replaced the first while they were written and the
/// export then failed moving a file that was gone.
pub fn unique_stem_names<'a>(track_names: impl IntoIterator<Item = &'a str>) -> Vec<String> {
    let mut taken = std::collections::HashSet::new();
    track_names
        .into_iter()
        .map(|track_name| {
            let safe = safe_track_name(track_name);
            let mut name = safe.clone();
            let mut number = 2;
            while !taken.insert(name.to_lowercase()) {
                name = format!("{safe} {number}");
                number += 1;
            }
            name
        })
        .collect()
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

    let selected_tracks: Vec<_> = tracks.iter().filter(|(info, _)| info.selected).collect();
    let stem_names = unique_stem_names(selected_tracks.iter().map(|(info, _)| info.name.as_str()));

    for (i, ((track_info, samples), stem_name)) in
        selected_tracks.iter().zip(&stem_names).enumerate()
    {
        let output_path = output_dir.join(generate_stem_filename(
            base_name,
            stem_name,
            options.file_extension(),
        ));

        // Written under a temporary name; the caller moves every stem into
        // place once all are done ([`PartialFiles::commit`]).
        // This stem's share of the progress.
        let share = |done: f64| (i as f64 + done) / selected_tracks.len() as f64;
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
    fn mp3_stem_progress_only_moves_forward() {
        // Review of #207: the last, shorter block of each stem counted as a
        // whole one, so 3.2 s stems went 0 → 62% → 50% → …
        let audio: Vec<f32> = (0..(3.2 * 48_000.0) as usize * 2)
            .map(|i| 0.3 * ((i / 2) as f32 * 0.05).sin())
            .collect();
        let tracks: Vec<_> = (1..=2)
            .map(|id| {
                let info = StemTrackInfo {
                    id,
                    name: format!("Track {id}"),
                    selected: true,
                };
                (info, audio.clone())
            })
            .collect();
        let dir = std::env::temp_dir().join("stem_progress_forward");
        let options =
            ExportOptions::mp3(super::super::options::Mp3Bitrate::Kbps128).with_sample_rate(48_000);
        let mut seen = Vec::new();

        export_stems(
            &tracks,
            &dir,
            "Song",
            &options,
            &mut PartialFiles::default(),
            &mut |done| {
                seen.push(done);
                true
            },
        )
        .unwrap();

        assert!(seen.windows(2).all(|w| w[0] <= w[1]), "{seen:?}");
        assert_eq!(seen.last(), Some(&1.0), "{seen:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Exports one short stem per name and returns the files left in the
    /// folder once they have moved into place.
    fn exported_stem_files(folder: &str, track_names: &[&str]) -> Vec<String> {
        let audio: Vec<f32> = (0..4_800 * 2)
            .map(|i| 0.3 * ((i / 2) as f32 * 0.05).sin())
            .collect();
        let tracks: Vec<_> = track_names
            .iter()
            .zip(1..)
            .map(|(name, id)| {
                let info = StemTrackInfo {
                    id,
                    name: (*name).to_string(),
                    selected: true,
                };
                (info, audio.clone())
            })
            .collect();
        let dir = std::env::temp_dir().join(folder);
        let _ = std::fs::remove_dir_all(&dir);
        let mut files = PartialFiles::default();

        let result = export_stems(
            &tracks,
            &dir,
            "Song",
            &ExportOptions::wav(super::super::options::WavBitDepth::Int16),
            &mut files,
            &mut |_| true,
        )
        .unwrap();
        files
            .commit(&super::super::ExportProgressState::new())
            .unwrap();

        let mut found: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        found.sort();
        let mut reported: Vec<String> = result
            .stems
            .iter()
            .map(|stem| {
                let path = Path::new(&stem.path);
                path.file_name().unwrap().to_string_lossy().into_owned()
            })
            .collect();
        reported.sort();
        assert_eq!(found, reported, "the result lists the files written");
        let _ = std::fs::remove_dir_all(&dir);
        found
    }

    #[test]
    fn two_tracks_with_the_same_name_export_two_stems() {
        assert_eq!(
            exported_stem_files("stems_same_name", &["Drums", "Drums"]),
            ["Song - Drums 2.wav", "Song - Drums.wav"]
        );
    }

    #[test]
    fn names_differing_only_in_case_or_dropped_characters_export_separately() {
        assert_eq!(
            exported_stem_files(
                "stems_same_file",
                &["Lead/Synth", "lead_synth", "LEAD:SYNTH"]
            ),
            [
                "Song - LEAD_SYNTH 3.wav",
                "Song - Lead_Synth.wav",
                "Song - lead_synth 2.wav"
            ]
        );
    }

    #[test]
    fn a_numbered_name_never_takes_a_name_another_track_has() {
        assert_eq!(
            unique_stem_names(["Drums", "Drums", "Drums 2", "Bass"]),
            ["Drums", "Drums 2", "Drums 2 2", "Bass"]
        );
    }

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
