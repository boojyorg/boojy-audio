# Export Feature Implementation Summary

**Date:** December 26, 2025
**Status:** COMPLETE
**Milestone:** M5.8 - Advanced Audio Export

---

## Overview

Comprehensive audio export functionality with MP3/WAV formats, stem export, metadata embedding, LUFS normalization, and real-time progress tracking. Implements Export Spec v1.0.

---

## What Was Built

### Rust Engine (engine/src/export/)

#### Module Structure
```
engine/src/export/
├── mod.rs         # Module exports
├── options.rs     # ExportOptions, enums, structs
├── wav.rs         # WAV export with bit depth conversion
├── mp3.rs         # MP3 encoding via ffmpeg
├── dither.rs      # TPDF dithering algorithm
├── resample.rs    # Sample rate conversion (48kHz → 44.1kHz)
├── normalize.rs   # Peak and LUFS normalization
├── stems.rs       # Per-track stem export
├── metadata.rs    # ID3 tag writing for MP3
└── progress.rs    # Polling-based progress tracking
```

#### Export Options (`options.rs`)
```rust
pub struct ExportOptions {
    pub format: ExportFormat,        // Mp3 or Wav
    pub sample_rate: u32,            // 44100 or 48000
    pub normalize: bool,
    pub dither: bool,
    pub mono: bool,
}

pub enum ExportFormat {
    Wav { bit_depth: WavBitDepth },   // Int16, Int24, Float32
    Mp3 { bitrate: Mp3Bitrate },      // Kbps128, Kbps192, Kbps320
}
```

#### WAV Export (`wav.rs`)
- 16-bit integer (CD quality)
- 24-bit integer (high quality)
- 32-bit float (studio quality)
- Optional TPDF dithering for bit depth reduction

#### MP3 Export (`mp3.rs`)
- Encoding via ffmpeg (commonly available on macOS/Linux)
- Bitrate options: 128, 192, 320 kbps
- Sample rate conversion if needed
- Returns structured ExportResult with file info

#### Dithering (`dither.rs`)
- TPDF (Triangular Probability Density Function)
- Reduces quantization noise when converting to lower bit depths
- Applied before 16-bit or 24-bit conversion

#### Sample Rate Conversion (`resample.rs`)
- Uses `rubato` crate for high-quality resampling
- Converts 48kHz → 44.1kHz for CD-quality exports
- Preserves audio quality with anti-aliasing

#### Normalization (`normalize.rs`)
- **Peak normalization**: Scale to target peak level
- **LUFS normalization**: ITU-R BS.1770-4 compliant
- Platform presets:
  - Spotify: -14 LUFS
  - YouTube: -14 LUFS
  - Apple Music: -16 LUFS
  - SoundCloud: -14 LUFS

#### Stem Export (`stems.rs`)
```rust
pub fn export_stems(
    tracks: &[(StemTrackInfo, Vec<f32>)],
    output_dir: &Path,
    base_name: &str,
    options: &ExportOptions,
) -> Result<StemExportResult, String>
```
- Exports each track as separate file
- Naming: `{base_name} - {track_name}.{ext}`
- Supports both WAV and MP3 formats
- Returns total count and file sizes

#### Metadata (`metadata.rs`)
```rust
pub struct ExportMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub year: Option<u32>,
    pub genre: Option<String>,
    pub bpm: Option<u32>,
    pub cover_art: Option<Vec<u8>>,
}
```
- ID3v2 tag writing using `id3` crate
- Embeds metadata in MP3 files after encoding

#### Progress Tracking (`progress.rs`)
```rust
pub struct ExportProgressState {
    progress: AtomicU32,        // 0-100
    is_running: AtomicBool,
    is_cancelled: AtomicBool,
    status: RwLock<String>,
    error: RwLock<Option<String>>,
}
```
- Global atomic state for thread-safe updates
- Polling-based (Flutter polls every 100ms)
- Methods: `start()`, `update()`, `complete()`, `fail()`, `cancel()`
- Returns JSON for FFI: `ExportProgressInfo::to_json()`

### FFI Layer (engine/src/ffi.rs)

New FFI functions:
```rust
// Export functions
pub extern "C" fn is_ffmpeg_available_ffi() -> i32
pub extern "C" fn export_audio_ffi(output_path, options_json) -> *mut c_char
pub extern "C" fn export_wav_with_options_ffi(...) -> *mut c_char
pub extern "C" fn export_mp3_with_options_ffi(...) -> *mut c_char
pub extern "C" fn write_mp3_metadata_ffi(file_path, metadata_json) -> *mut c_char

// Stem export
pub extern "C" fn get_tracks_for_stems_ffi() -> *mut c_char
pub extern "C" fn export_stems_ffi(output_dir, base_name, track_ids_json, options_json) -> *mut c_char

// Progress tracking
pub extern "C" fn get_export_progress_ffi() -> *mut c_char
pub extern "C" fn cancel_export_ffi()
pub extern "C" fn reset_export_progress_ffi()
```

### Flutter UI (ui/lib/)

#### AudioEngine Bindings (audio_engine.dart)
```dart
// Export methods
bool isFfmpegAvailable()
String exportWavWithOptions({...})
String exportMp3WithOptions({...})
String exportStems({...})
void writeMp3Metadata(String path, String metadataJson)
String getTracksForStems()

// Progress methods
String getExportProgress()
void cancelExport()
void resetExportProgress()
```

#### Export Dialog (widgets/export_dialog.dart)

**ExportOptions Model:**
- Format selection (MP3/WAV/both)
- MP3 bitrate (128/192/320 kbps)
- WAV bit depth (16/24/32-bit)
- Sample rate (44.1/48 kHz)
- Normalize, dither, mono options
- Stem export with track selection
- Metadata fields (title, artist, album, year, genre)

**ExportProgressDialog Widget:**
- Real-time progress bar with percentage
- Status text updates ("Rendering audio...", "Encoding MP3...")
- Cancel button
- Error state display
- Success confirmation

**UI Sections:**
1. **Format Section** - MP3/WAV checkboxes with quality dropdowns
2. **Quality Section** - Sample rate, platform presets
3. **Stem Export Section** - Track selection with Select All/Deselect All
4. **Metadata Section** - Collapsible form for ID3 tags
5. **Advanced Section** - Normalize, dither, mono options

#### Settings Persistence (services/user_settings.dart)

Export settings saved via SharedPreferences:
```dart
// Keys
export_format         // 'mp3', 'wav', 'both'
export_mp3_bitrate    // 128, 192, 320
export_wav_bit_depth  // 16, 24, 32
export_sample_rate    // 44100, 48000
export_normalize      // bool
export_dither         // bool
export_artist         // String (if remember enabled)
export_remember_artist // bool
```

---

## User Workflow

### Standard Export:
1. File → Export... (or Cmd+E)
2. Export dialog opens with saved preferences
3. Choose format (MP3, WAV, or both)
4. Adjust quality settings if needed
5. Optionally add metadata
6. Click "Export"
7. Choose file location (macOS save dialog)
8. Progress dialog shows real-time updates
9. Success dialog with file info

### Stem Export:
1. Enable "Export Individual Tracks"
2. Select which tracks to export
3. Click "Export"
4. Choose output folder
5. Each track exported as separate file
6. Named: `ProjectName - TrackName.mp3/wav`

### Cancellation:
1. Click "Cancel" during export
2. Engine checks cancellation flag
3. Export stops gracefully
4. Dialog closes

---

## Technical Details

### Dependencies (Cargo.toml)
```toml
hound = "3.5"        # WAV encoding/decoding
id3 = "1.14"         # ID3v2 tag writing
rubato = "0.14"      # Sample rate conversion
# Note: MP3 encoding uses ffmpeg via command line
```

### Progress Update Flow
```
Flutter                    Rust Engine
   │                           │
   │ resetExportProgress()     │
   ├──────────────────────────►│
   │                           │
   │ exportMp3WithOptions()    │
   ├──────────────────────────►│ progress.start()
   │                           │
   │ [Timer: 100ms]            │ progress.update(10, "...")
   │ getExportProgress() ──────►│ progress.update(20, "...")
   │◄───────────────── JSON    │ progress.update(60, "...")
   │                           │
   │ [Update UI]               │ progress.complete()
   │                           │
   │ getExportProgress() ──────►│
   │◄───────────────── JSON    │
   │                           │
   │ [Close dialog]            │
   │                           │
```

### Error Handling
- FFI returns "Error: message" strings on failure
- Flutter catches and displays errors in dialog
- Progress state tracks error messages
- User can retry after errors

---

## Export Formats Summary

| Format | Quality Options | Use Case |
|--------|-----------------|----------|
| MP3 320 kbps | Highest MP3 | Streaming, sharing |
| MP3 192 kbps | Good quality | Podcasts, drafts |
| MP3 128 kbps | Smaller files | Voice, previews |
| WAV 16-bit | CD quality | Distribution, masters |
| WAV 24-bit | High quality | Professional masters |
| WAV 32-bit | Studio quality | Archives, remixing |

---

## Default Settings

| Setting | Default |
|---------|---------|
| Format | MP3 only |
| MP3 Quality | High (320 kbps) |
| WAV Bit Depth | 16-bit |
| Sample Rate | 44100 Hz |
| Normalize | Off |
| Dither | Off |
| Mono | Off |
| Export Stems | Off |

---

## Files Created/Modified

### New Files:
- `engine/src/export/mod.rs`
- `engine/src/export/options.rs`
- `engine/src/export/wav.rs`
- `engine/src/export/mp3.rs`
- `engine/src/export/dither.rs`
- `engine/src/export/resample.rs`
- `engine/src/export/normalize.rs`
- `engine/src/export/stems.rs`
- `engine/src/export/metadata.rs`
- `engine/src/export/progress.rs`
- `ui/lib/widgets/export_dialog.dart`
- `docs/M5/EXPORT_FEATURE_SUMMARY.md` (this file)

### Modified Files:
- `engine/Cargo.toml` - Added id3 crate
- `engine/src/lib.rs` - Added export module
- `engine/src/api/project.rs` - Export functions with progress
- `engine/src/api/mod.rs` - Export API exports
- `engine/src/ffi.rs` - Export FFI bindings
- `ui/lib/audio_engine.dart` - Export method bindings
- `ui/lib/services/user_settings.dart` - Export settings persistence

---

## Testing Checklist

- [x] MP3 128/192/320 kbps export
- [x] WAV 16/24/32-bit export
- [x] Sample rate conversion (48kHz → 44.1kHz)
- [x] TPDF dithering applied correctly
- [x] Mono mixdown works
- [x] Stem export creates separate files
- [x] ID3 metadata readable in players
- [x] Progress bar updates smoothly
- [x] Cancel stops export
- [x] Settings persist across sessions
- [x] Error messages displayed properly
- [x] Build succeeds (Rust + Flutter)

---

**Status:** COMPLETE

All export functionality implemented and tested. The export feature provides comprehensive audio export capabilities matching professional DAW standards.

---

**Completed by:** Claude
**Date:** December 26, 2025
