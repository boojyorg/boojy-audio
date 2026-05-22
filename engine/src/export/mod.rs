//! Export module for audio rendering and file encoding
//!
//! This module provides comprehensive audio export functionality including:
//! - WAV export with configurable bit depth (16-bit, 24-bit, 32-bit float)
//! - MP3 export with configurable bitrate (128, 192, 320 kbps)
//! - Sample rate conversion (48kHz to 44.1kHz)
//! - Dithering for bit depth reduction
//! - Normalization (peak and LUFS-based)
//! - Stem export (per-track rendering)
//! - Metadata embedding (ID3 tags)
//! - Progress tracking (polling-based)

mod dither;
mod metadata;
mod mp3;
mod normalize;
mod options;
mod progress;
mod resample;
mod stems;
mod wav;

pub use dither::*;
pub use metadata::*;
pub use mp3::*;
pub use normalize::*;
pub use options::*;
pub use progress::*;
pub use resample::*;
pub use stems::*;
pub use wav::*;
