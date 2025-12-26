//! Export options and configuration types

use serde::{Deserialize, Serialize};

/// WAV bit depth options
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WavBitDepth {
    /// 16-bit integer (CD quality)
    Int16,
    /// 24-bit integer (studio quality)
    Int24,
    /// 32-bit float (maximum quality)
    Float32,
}

impl Default for WavBitDepth {
    fn default() -> Self {
        Self::Int16
    }
}

impl WavBitDepth {
    /// Get bits per sample for hound WavSpec
    pub fn bits_per_sample(&self) -> u16 {
        match self {
            WavBitDepth::Int16 => 16,
            WavBitDepth::Int24 => 24,
            WavBitDepth::Float32 => 32,
        }
    }

    /// Parse from string
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "16" | "int16" | "16-bit" => Some(Self::Int16),
            "24" | "int24" | "24-bit" => Some(Self::Int24),
            "32" | "float32" | "32-bit" | "32-bit float" => Some(Self::Float32),
            _ => None,
        }
    }
}

/// MP3 bitrate options
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Mp3Bitrate {
    /// 128 kbps (smallest file, noticeable quality loss)
    Kbps128,
    /// 192 kbps (balanced)
    Kbps192,
    /// 320 kbps (best MP3 quality)
    Kbps320,
}

impl Default for Mp3Bitrate {
    fn default() -> Self {
        Self::Kbps320
    }
}

impl Mp3Bitrate {
    /// Get bitrate value in kbps
    pub fn kbps(&self) -> u32 {
        match self {
            Mp3Bitrate::Kbps128 => 128,
            Mp3Bitrate::Kbps192 => 192,
            Mp3Bitrate::Kbps320 => 320,
        }
    }

    /// Parse from integer kbps value
    pub fn from_kbps(kbps: u32) -> Option<Self> {
        match kbps {
            128 => Some(Self::Kbps128),
            192 => Some(Self::Kbps192),
            320 => Some(Self::Kbps320),
            _ => None,
        }
    }
}

/// Platform loudness targets (LUFS)
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum PlatformTarget {
    /// No loudness adjustment
    None,
    /// Spotify: -14 LUFS
    Spotify,
    /// YouTube: -14 LUFS
    YouTube,
    /// Apple Music: -16 LUFS
    AppleMusic,
    /// SoundCloud: -14 LUFS
    SoundCloud,
    /// Custom LUFS target
    Custom(f64),
}

impl Default for PlatformTarget {
    fn default() -> Self {
        Self::None
    }
}

impl PlatformTarget {
    /// Get target LUFS value (None if no adjustment)
    pub fn target_lufs(&self) -> Option<f64> {
        match self {
            PlatformTarget::None => None,
            PlatformTarget::Spotify => Some(-14.0),
            PlatformTarget::YouTube => Some(-14.0),
            PlatformTarget::AppleMusic => Some(-16.0),
            PlatformTarget::SoundCloud => Some(-14.0),
            PlatformTarget::Custom(lufs) => Some(*lufs),
        }
    }
}

/// Export format specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ExportFormat {
    /// WAV format with specified bit depth
    Wav { bit_depth: WavBitDepth },
    /// MP3 format with specified bitrate
    Mp3 { bitrate: Mp3Bitrate },
}

impl Default for ExportFormat {
    fn default() -> Self {
        Self::Mp3 {
            bitrate: Mp3Bitrate::Kbps320,
        }
    }
}

/// Comprehensive export options
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportOptions {
    /// Output format (WAV or MP3)
    pub format: ExportFormat,
    /// Sample rate in Hz (44100 or 48000)
    pub sample_rate: u32,
    /// Apply peak normalization to -0.1 dBFS
    pub normalize: bool,
    /// Apply dithering when reducing bit depth
    pub dither: bool,
    /// Mix down to mono
    pub mono: bool,
    /// Start time for loop region export (None = 0)
    pub start_time: Option<f64>,
    /// End time for loop region export (None = project end)
    pub end_time: Option<f64>,
    /// Platform loudness target
    pub platform_target: PlatformTarget,
}

impl Default for ExportOptions {
    fn default() -> Self {
        Self {
            format: ExportFormat::default(),
            sample_rate: 44100,
            normalize: false,
            dither: false,
            mono: false,
            start_time: None,
            end_time: None,
            platform_target: PlatformTarget::None,
        }
    }
}

impl ExportOptions {
    /// Create WAV export options with default settings
    pub fn wav(bit_depth: WavBitDepth) -> Self {
        Self {
            format: ExportFormat::Wav { bit_depth },
            ..Default::default()
        }
    }

    /// Create MP3 export options with default settings
    pub fn mp3(bitrate: Mp3Bitrate) -> Self {
        Self {
            format: ExportFormat::Mp3 { bitrate },
            ..Default::default()
        }
    }

    /// Set sample rate
    pub fn with_sample_rate(mut self, sample_rate: u32) -> Self {
        self.sample_rate = sample_rate;
        self
    }

    /// Enable normalization
    pub fn with_normalize(mut self, normalize: bool) -> Self {
        self.normalize = normalize;
        self
    }

    /// Enable dithering
    pub fn with_dither(mut self, dither: bool) -> Self {
        self.dither = dither;
        self
    }

    /// Enable mono mixdown
    pub fn with_mono(mut self, mono: bool) -> Self {
        self.mono = mono;
        self
    }

    /// Set time range for loop region export
    pub fn with_range(mut self, start: f64, end: f64) -> Self {
        self.start_time = Some(start);
        self.end_time = Some(end);
        self
    }

    /// Set platform target for LUFS normalization
    pub fn with_platform(mut self, platform: PlatformTarget) -> Self {
        self.platform_target = platform;
        self
    }

    /// Get file extension for this format
    pub fn file_extension(&self) -> &str {
        match &self.format {
            ExportFormat::Wav { .. } => "wav",
            ExportFormat::Mp3 { .. } => "mp3",
        }
    }

    /// Check if this is a WAV export
    pub fn is_wav(&self) -> bool {
        matches!(self.format, ExportFormat::Wav { .. })
    }

    /// Check if this is an MP3 export
    pub fn is_mp3(&self) -> bool {
        matches!(self.format, ExportFormat::Mp3 { .. })
    }

    /// Parse options from JSON string
    pub fn from_json(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| format!("Failed to parse export options: {}", e))
    }

    /// Serialize options to JSON string
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string(self).map_err(|e| format!("Failed to serialize export options: {}", e))
    }
}

/// Metadata for audio file embedding
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ExportMetadata {
    /// Track title
    pub title: Option<String>,
    /// Artist name
    pub artist: Option<String>,
    /// Album name
    pub album: Option<String>,
    /// Release year
    pub year: Option<u32>,
    /// Genre
    pub genre: Option<String>,
    /// Track number
    pub track_number: Option<u32>,
    /// Total tracks in album
    pub track_total: Option<u32>,
    /// BPM (tempo)
    pub bpm: Option<u32>,
    /// Musical key (e.g., "C Minor")
    pub key: Option<String>,
    /// Copyright notice
    pub copyright: Option<String>,
    /// Comments
    pub comments: Option<String>,
    /// Cover art as JPEG/PNG bytes
    pub cover_art: Option<Vec<u8>>,
    /// Cover art MIME type (e.g., "image/jpeg")
    pub cover_art_mime: Option<String>,
}

impl ExportMetadata {
    /// Check if any metadata is set
    pub fn is_empty(&self) -> bool {
        self.title.is_none()
            && self.artist.is_none()
            && self.album.is_none()
            && self.year.is_none()
            && self.genre.is_none()
            && self.bpm.is_none()
            && self.cover_art.is_none()
    }

    /// Parse metadata from JSON string
    pub fn from_json(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| format!("Failed to parse metadata: {}", e))
    }

    /// Serialize metadata to JSON string
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string(self).map_err(|e| format!("Failed to serialize metadata: {}", e))
    }
}

/// Export result information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportResult {
    /// Output file path
    pub path: String,
    /// File size in bytes
    pub file_size: u64,
    /// Audio duration in seconds
    pub duration: f64,
    /// Sample rate used
    pub sample_rate: u32,
    /// Format description (e.g., "WAV 16-bit" or "MP3 320kbps")
    pub format_description: String,
}

impl ExportResult {
    /// Create a new export result
    pub fn new(path: String, file_size: u64, duration: f64, sample_rate: u32, format_description: String) -> Self {
        Self {
            path,
            file_size,
            duration,
            sample_rate,
            format_description,
        }
    }

    /// Serialize to JSON
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_options() {
        let options = ExportOptions::default();
        assert!(options.is_mp3());
        assert_eq!(options.sample_rate, 44100);
        assert!(!options.normalize);
        assert!(!options.dither);
    }

    #[test]
    fn test_wav_options() {
        let options = ExportOptions::wav(WavBitDepth::Int16)
            .with_sample_rate(48000)
            .with_normalize(true)
            .with_dither(true);

        assert!(options.is_wav());
        assert_eq!(options.sample_rate, 48000);
        assert!(options.normalize);
        assert!(options.dither);
    }

    #[test]
    fn test_mp3_bitrate() {
        assert_eq!(Mp3Bitrate::Kbps128.kbps(), 128);
        assert_eq!(Mp3Bitrate::Kbps192.kbps(), 192);
        assert_eq!(Mp3Bitrate::Kbps320.kbps(), 320);
    }

    #[test]
    fn test_platform_lufs() {
        assert_eq!(PlatformTarget::Spotify.target_lufs(), Some(-14.0));
        assert_eq!(PlatformTarget::AppleMusic.target_lufs(), Some(-16.0));
        assert_eq!(PlatformTarget::None.target_lufs(), None);
    }

    #[test]
    fn test_json_serialization() {
        let options = ExportOptions::wav(WavBitDepth::Int24);
        let json = options.to_json().unwrap();
        let parsed = ExportOptions::from_json(&json).unwrap();
        assert!(parsed.is_wav());
    }
}
