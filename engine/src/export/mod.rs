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

mod options;
mod wav;
mod mp3;
mod dither;
mod resample;
mod normalize;
mod stems;
mod metadata;
mod progress;

pub use options::*;
pub use wav::*;
pub use mp3::*;
pub use dither::*;
pub use resample::*;
pub use normalize::*;
pub use stems::*;
pub use metadata::*;
pub use progress::*;
