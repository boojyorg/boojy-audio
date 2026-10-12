//! Metadata embedding for audio files
//!
//! Supports `ID3v2` tags for MP3 files.

use super::options::ExportMetadata;
use id3::frame::{Picture, PictureType};
use id3::{Tag, TagLike, Version};
use std::path::Path;

/// Write `ID3v2` tags to an MP3 file
///
/// # Arguments
/// * `mp3_path` - Path to the MP3 file
/// * `metadata` - Metadata to embed
///
/// # Returns
/// Ok(()) on success
pub fn write_id3_tags(mp3_path: &Path, metadata: &ExportMetadata) -> Result<(), String> {
    if metadata.is_empty() {
        eprintln!("⚠️ [Metadata] No metadata to write");
        return Ok(());
    }

    eprintln!("🏷️ [Metadata] Writing ID3 tags to {}", mp3_path.display());

    let mut tag = Tag::new();

    // Set text frames
    if let Some(ref title) = metadata.title {
        tag.set_title(title);
        eprintln!("   Title: {title}");
    }

    if let Some(ref artist) = metadata.artist {
        tag.set_artist(artist);
        eprintln!("   Artist: {artist}");
    }

    if let Some(ref album) = metadata.album {
        tag.set_album(album);
        eprintln!("   Album: {album}");
    }

    if let Some(year) = metadata.year {
        tag.set_year(year as i32);
        eprintln!("   Year: {year}");
    }

    if let Some(ref genre) = metadata.genre {
        tag.set_genre(genre);
        eprintln!("   Genre: {genre}");
    }

    if let Some(track_number) = metadata.track_number {
        if let Some(track_total) = metadata.track_total {
            tag.set_track(track_number);
            tag.set_total_tracks(track_total);
        } else {
            tag.set_track(track_number);
        }
    }

    // BPM (TBPM frame)
    if let Some(bpm) = metadata.bpm {
        tag.add_frame(id3::frame::Frame::text("TBPM", bpm.to_string()));
        eprintln!("   BPM: {bpm}");
    }

    // Key (TKEY frame)
    if let Some(ref key) = metadata.key {
        tag.add_frame(id3::frame::Frame::text("TKEY", key.clone()));
        eprintln!("   Key: {key}");
    }

    // Copyright (TCOP frame)
    if let Some(ref copyright) = metadata.copyright {
        tag.add_frame(id3::frame::Frame::text("TCOP", copyright.clone()));
    }

    // Comments (COMM frame)
    if let Some(ref comments) = metadata.comments {
        tag.add_frame(id3::frame::Comment {
            lang: "eng".to_string(),
            description: String::new(),
            text: comments.clone(),
        });
    }

    // Cover art (APIC frame)
    if let Some(ref cover_data) = metadata.cover_art {
        let mime_type = metadata
            .cover_art_mime
            .clone()
            .unwrap_or_else(|| "image/jpeg".to_string());

        let picture = Picture {
            mime_type,
            picture_type: PictureType::CoverFront,
            description: String::new(),
            data: cover_data.clone(),
        };

        tag.add_frame(picture);
        eprintln!("   Cover art: {} bytes", cover_data.len());
    }

    // Write to file
    tag.write_to_path(mp3_path, Version::Id3v24)
        .map_err(|e| format!("Failed to write ID3 tags: {e}"))?;

    eprintln!("✅ [Metadata] ID3 tags written successfully");

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_metadata() {
        let metadata = ExportMetadata::default();
        assert!(metadata.is_empty());
    }

    #[test]
    fn test_metadata_roundtrip() {
        // This test requires an actual MP3 file
        // For unit testing, we just verify the metadata struct
        let metadata = ExportMetadata {
            title: Some("Test Song".to_string()),
            artist: Some("Test Artist".to_string()),
            album: Some("Test Album".to_string()),
            year: Some(2025),
            genre: Some("Electronic".to_string()),
            bpm: Some(120),
            key: Some("C Minor".to_string()),
            ..Default::default()
        };

        assert!(!metadata.is_empty());
        assert_eq!(metadata.title.as_deref(), Some("Test Song"));
        assert_eq!(metadata.bpm, Some(120));
    }
}
