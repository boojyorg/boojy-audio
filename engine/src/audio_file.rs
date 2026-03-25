/// Audio file loading and decoding
use anyhow::{Context, Result};
use rubato::{FftFixedInOut, Resampler};
use std::io::{Read as _, Seek as _, SeekFrom};
use std::path::Path;
use std::sync::Arc;
use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Target sample rate for all audio in the engine
pub const TARGET_SAMPLE_RATE: u32 = 48000;

/// Represents a loaded audio clip with decoded samples
#[derive(Clone, Debug)]
pub struct AudioClip {
    /// Decoded audio samples (interleaved stereo, f32 format)
    pub samples: Vec<f32>,
    /// Number of channels (1 = mono, 2 = stereo)
    pub channels: usize,
    /// Sample rate (always 48000 after loading)
    pub sample_rate: u32,
    /// Duration in seconds
    pub duration_seconds: f64,
    /// Original file path
    pub file_path: String,
}

impl AudioClip {
    /// Get the number of frames (samples per channel)
    pub fn frame_count(&self) -> usize {
        self.samples.len() / self.channels
    }

    /// Get sample at specific frame and channel
    pub fn get_sample(&self, frame: usize, channel: usize) -> Option<f32> {
        if channel >= self.channels || frame >= self.frame_count() {
            return None;
        }
        Some(self.samples[frame * self.channels + channel])
    }
}

/// Load an audio file and decode it to interleaved f32 samples at 48kHz
pub fn load_audio_file<P: AsRef<Path>>(path: P) -> Result<AudioClip> {
    let path_ref = path.as_ref();

    // Fast path for WAV files — direct PCM read, no Symphonia overhead
    if let Some(ext) = path_ref.extension().and_then(|e| e.to_str()) {
        if ext.eq_ignore_ascii_case("wav") || ext.eq_ignore_ascii_case("wave") {
            let t0 = std::time::Instant::now();
            match load_wav_fast(path_ref) {
                Ok(clip) => {
                    eprintln!("[PREVIEW] fast WAV loaded in {:?} ({} frames)", t0.elapsed(), clip.frame_count());
                    return Ok(clip);
                }
                Err(e) => {
                    eprintln!("[PREVIEW] fast WAV failed: {e}, falling back to Symphonia");
                }
            }
        }
    }

    load_audio_file_symphonia(path_ref)
}

/// Raw preview clip — stores raw bytes, converts samples on-the-fly during playback.
/// This avoids the expensive upfront f32 conversion for large files.
pub struct RawPreviewClip {
    pub raw_data: Vec<u8>,
    pub channels: usize,
    pub sample_rate: u32,
    pub bits_per_sample: u16,
    pub audio_format: u16, // 1=PCM, 3=IEEE float
    pub frame_count: usize,
    pub duration_seconds: f64,
    pub file_path: String,
}

impl RawPreviewClip {
    /// Get a sample at (frame, channel), converting from raw bytes on the fly
    #[inline]
    pub fn get_sample(&self, frame: usize, channel: usize) -> f32 {
        if frame >= self.frame_count || channel >= self.channels {
            return 0.0;
        }
        let bps = (self.bits_per_sample / 8) as usize;
        let offset = (frame * self.channels + channel) * bps;

        match (self.audio_format, self.bits_per_sample) {
            (1, 16) => {
                let s = i16::from_le_bytes([self.raw_data[offset], self.raw_data[offset + 1]]);
                f32::from(s) / 32768.0
            }
            (1, 24) => {
                let s = i32::from_le_bytes([0, self.raw_data[offset], self.raw_data[offset + 1], self.raw_data[offset + 2]]) >> 8;
                s as f32 / 8_388_608.0
            }
            (3, 32) => {
                f32::from_le_bytes([self.raw_data[offset], self.raw_data[offset + 1], self.raw_data[offset + 2], self.raw_data[offset + 3]])
            }
            (1, 32) => {
                let s = i32::from_le_bytes([self.raw_data[offset], self.raw_data[offset + 1], self.raw_data[offset + 2], self.raw_data[offset + 3]]);
                s as f32 / 2_147_483_648.0
            }
            _ => 0.0,
        }
    }
}

/// Load a WAV file for preview — stores raw bytes, no f32 conversion, no resampling.
/// Returns nearly instantly for any size WAV.
pub fn load_wav_for_preview<P: AsRef<Path>>(path: P) -> Result<RawPreviewClip> {
    let path_ref = path.as_ref();
    let mut file = std::fs::File::open(path_ref)
        .context("Failed to open WAV file")?;

    // Read RIFF header
    let mut riff_header = [0u8; 12];
    file.read_exact(&mut riff_header)?;
    if &riff_header[0..4] != b"RIFF" || &riff_header[8..12] != b"WAVE" {
        anyhow::bail!("Not a valid WAV file");
    }

    let mut sample_rate: u32 = 0;
    let mut channels: u16 = 0;
    let mut bits_per_sample: u16 = 0;
    let mut audio_format: u16 = 0;
    let mut data_offset: u64 = 0;
    let mut data_size: u32 = 0;

    loop {
        let mut chunk_header = [0u8; 8];
        if file.read_exact(&mut chunk_header).is_err() { break; }
        let chunk_id = &chunk_header[0..4];
        let chunk_size = u32::from_le_bytes([chunk_header[4], chunk_header[5], chunk_header[6], chunk_header[7]]);

        if chunk_id == b"fmt " {
            let mut fmt_data = vec![0u8; chunk_size as usize];
            file.read_exact(&mut fmt_data)?;
            audio_format = u16::from_le_bytes([fmt_data[0], fmt_data[1]]);
            channels = u16::from_le_bytes([fmt_data[2], fmt_data[3]]);
            sample_rate = u32::from_le_bytes([fmt_data[4], fmt_data[5], fmt_data[6], fmt_data[7]]);
            bits_per_sample = u16::from_le_bytes([fmt_data[14], fmt_data[15]]);
        } else if chunk_id == b"data" {
            data_offset = file.stream_position()?;
            data_size = chunk_size;
            break;
        } else {
            let skip = (chunk_size + 1) & !1;
            file.seek(SeekFrom::Current(i64::from(skip)))?;
        }
    }

    if data_offset == 0 || data_size == 0 { anyhow::bail!("WAV missing data chunk"); }
    if audio_format != 1 && audio_format != 3 { anyhow::bail!("Unsupported format: {audio_format}"); }
    let ch = channels as usize;
    if ch == 0 || ch > 2 { anyhow::bail!("Unsupported channels: {ch}"); }
    if !matches!((audio_format, bits_per_sample), (1, 16) | (1, 24) | (3, 32) | (1, 32)) {
        anyhow::bail!("Unsupported bit depth: {bits_per_sample}");
    }

    // Just read raw bytes — no conversion
    file.seek(SeekFrom::Start(data_offset))?;
    let mut raw_data = vec![0u8; data_size as usize];
    file.read_exact(&mut raw_data)?;

    let bps = (bits_per_sample / 8) as usize;
    let total_samples = raw_data.len() / bps;
    let frame_count = total_samples / ch;
    let duration_seconds = frame_count as f64 / f64::from(sample_rate);

    Ok(RawPreviewClip {
        raw_data,
        channels: ch,
        sample_rate,
        bits_per_sample,
        audio_format,
        frame_count,
        duration_seconds,
        file_path: path_ref.to_string_lossy().to_string(),
    })
}

/// Fast WAV loader — reads raw PCM directly from the RIFF structure.
/// Supports 16-bit, 24-bit, and 32-bit float PCM.
fn load_wav_fast(path: &Path) -> Result<AudioClip> {
    let mut file = std::fs::File::open(path)
        .context("Failed to open WAV file")?;

    // Read RIFF header (12 bytes)
    let mut riff_header = [0u8; 12];
    file.read_exact(&mut riff_header)?;

    if &riff_header[0..4] != b"RIFF" || &riff_header[8..12] != b"WAVE" {
        anyhow::bail!("Not a valid WAV file");
    }

    // Find fmt and data chunks
    let mut sample_rate: u32 = 0;
    let mut channels: u16 = 0;
    let mut bits_per_sample: u16 = 0;
    let mut audio_format: u16 = 0;
    let mut data_offset: u64 = 0;
    let mut data_size: u32 = 0;

    loop {
        let mut chunk_header = [0u8; 8];
        if file.read_exact(&mut chunk_header).is_err() {
            break;
        }

        let chunk_id = &chunk_header[0..4];
        let chunk_size = u32::from_le_bytes([chunk_header[4], chunk_header[5], chunk_header[6], chunk_header[7]]);

        if chunk_id == b"fmt " {
            let mut fmt_data = vec![0u8; chunk_size as usize];
            file.read_exact(&mut fmt_data)?;

            audio_format = u16::from_le_bytes([fmt_data[0], fmt_data[1]]);
            channels = u16::from_le_bytes([fmt_data[2], fmt_data[3]]);
            sample_rate = u32::from_le_bytes([fmt_data[4], fmt_data[5], fmt_data[6], fmt_data[7]]);
            bits_per_sample = u16::from_le_bytes([fmt_data[14], fmt_data[15]]);
        } else if chunk_id == b"data" {
            data_offset = file.stream_position()?;
            data_size = chunk_size;
            break;
        } else {
            // Skip unknown chunk (pad to even boundary)
            let skip = (chunk_size + 1) & !1;
            file.seek(SeekFrom::Current(i64::from(skip)))?;
        }
    }

    if data_offset == 0 || data_size == 0 {
        anyhow::bail!("WAV file missing data chunk");
    }

    // Only support PCM (1) and IEEE float (3)
    if audio_format != 1 && audio_format != 3 {
        anyhow::bail!("Unsupported WAV format: {audio_format} (only PCM and IEEE float supported)");
    }

    let ch = channels as usize;
    if ch == 0 || ch > 2 {
        anyhow::bail!("Unsupported channel count: {ch}");
    }

    // Read raw data
    file.seek(SeekFrom::Start(data_offset))?;
    let mut raw_data = vec![0u8; data_size as usize];
    file.read_exact(&mut raw_data)?;

    // Convert to f32 based on bit depth
    let bytes_per_sample = (bits_per_sample / 8) as usize;
    let total_samples = raw_data.len() / bytes_per_sample;
    let mut samples = Vec::with_capacity(total_samples);

    match (audio_format, bits_per_sample) {
        (1, 16) => {
            // PCM 16-bit signed
            for chunk in raw_data.chunks_exact(2) {
                let s = i16::from_le_bytes([chunk[0], chunk[1]]);
                samples.push(f32::from(s) / 32768.0);
            }
        }
        (1, 24) => {
            // PCM 24-bit signed
            for chunk in raw_data.chunks_exact(3) {
                let s = i32::from_le_bytes([0, chunk[0], chunk[1], chunk[2]]) >> 8;
                samples.push(s as f32 / 8_388_608.0);
            }
        }
        (3, 32) => {
            // IEEE float 32-bit
            for chunk in raw_data.chunks_exact(4) {
                let s = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                samples.push(s);
            }
        }
        (1, 32) => {
            // PCM 32-bit signed
            for chunk in raw_data.chunks_exact(4) {
                let s = i32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                samples.push(s as f32 / 2_147_483_648.0);
            }
        }
        _ => anyhow::bail!("Unsupported WAV bit depth: {bits_per_sample}"),
    }

    // Resample if needed
    let final_samples = if sample_rate == TARGET_SAMPLE_RATE {
        samples
    } else {
        resample_audio(&samples, sample_rate, TARGET_SAMPLE_RATE, ch)?
    };

    let frame_count = final_samples.len() / ch;
    let duration_seconds = frame_count as f64 / f64::from(TARGET_SAMPLE_RATE);

    Ok(AudioClip {
        samples: final_samples,
        channels: ch,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds,
        file_path: path.to_string_lossy().to_string(),
    })
}

/// Streaming preview clip — samples grow as decode progresses.
/// Audio callback reads via RwLock, decode thread appends.
pub struct StreamingPreviewClip {
    pub samples: Arc<parking_lot::RwLock<Vec<f32>>>,
    pub decoded_frames: Arc<std::sync::atomic::AtomicUsize>,
    pub fully_decoded: Arc<std::sync::atomic::AtomicBool>,
    pub channels: usize,
    pub sample_rate: u32,
    pub file_path: String,
}

impl StreamingPreviewClip {
    #[inline]
    pub fn get_sample(&self, frame: usize, channel: usize) -> f32 {
        if frame >= self.decoded_frames.load(std::sync::atomic::Ordering::Relaxed) || channel >= self.channels {
            return 0.0;
        }
        let guard = self.samples.read();
        let idx = frame * self.channels + channel;
        if idx < guard.len() { guard[idx] } else { 0.0 }
    }

    pub fn frame_count(&self) -> usize {
        self.decoded_frames.load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn duration_seconds(&self) -> f64 {
        self.frame_count() as f64 / f64::from(self.sample_rate)
    }

    pub fn is_fully_decoded(&self) -> bool {
        self.fully_decoded.load(std::sync::atomic::Ordering::Relaxed)
    }
}

/// Start a streaming decode of a compressed audio file.
/// Returns a `StreamingPreviewClip` that grows as packets are decoded.
/// The caller should wait until `decoded_frames > 0` before starting playback.
pub fn start_streaming_decode<P: AsRef<Path>>(path: P) -> Result<StreamingPreviewClip> {
    let path_ref = path.as_ref();
    let file = std::fs::File::open(path_ref)
        .context(format!("Failed to open: {}", path_ref.display()))?;

    let mss = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());

    let mut hint = Hint::new();
    if let Some(ext) = path_ref.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .context("Failed to probe audio file format")?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .context("No valid audio track found")?;

    let track_id = track.id;
    let codec_params = track.codec_params.clone();

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .context("Failed to create decoder")?;

    let source_sample_rate = codec_params
        .sample_rate
        .context("Sample rate not specified")?;

    let channels = codec_params
        .channels
        .context("Channel count not specified")?
        .count();

    let samples = Arc::new(parking_lot::RwLock::new(Vec::with_capacity(source_sample_rate as usize * channels * 10)));
    let decoded_frames = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let fully_decoded = Arc::new(std::sync::atomic::AtomicBool::new(false));

    let clip = StreamingPreviewClip {
        samples: Arc::clone(&samples),
        decoded_frames: Arc::clone(&decoded_frames),
        fully_decoded: Arc::clone(&fully_decoded),
        channels,
        sample_rate: source_sample_rate,
        file_path: path_ref.to_string_lossy().to_string(),
    };

    // Spawn decode thread
    std::thread::spawn(move || {
        loop {
            let packet = match format.next_packet() {
                Ok(packet) => packet,
                Err(Error::IoError(_)) => break,
                Err(Error::ResetRequired) => { decoder.reset(); continue; }
                Err(_) => break,
            };

            if packet.track_id() != track_id { continue; }

            match decoder.decode(&packet) {
                Ok(audio_buf) => {
                    let new_samples = convert_audio_buffer_to_f32(&audio_buf, channels);
                    let new_frames = new_samples.len() / channels;
                    {
                        let mut guard = samples.write();
                        guard.extend_from_slice(&new_samples);
                    }
                    decoded_frames.fetch_add(new_frames, std::sync::atomic::Ordering::Release);
                }
                Err(Error::DecodeError(_)) => {}
                Err(_) => break,
            }
        }
        fully_decoded.store(true, std::sync::atomic::Ordering::Release);
    });

    Ok(clip)
}

/// Load only the first `max_seconds` of a compressed audio file.
/// Returns the partial clip at native sample rate (no resampling for speed).
pub fn load_audio_file_partial<P: AsRef<Path>>(path: P, max_seconds: f64) -> Result<AudioClip> {
    let path_ref = path.as_ref();
    let file = std::fs::File::open(path_ref)
        .context(format!("Failed to open audio file: {}", path_ref.display()))?;

    let mss = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());

    let mut hint = Hint::new();
    if let Some(ext) = path_ref.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .context("Failed to probe audio file format")?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .context("No valid audio track found")?;

    let track_id = track.id;
    let codec_params = track.codec_params.clone();

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .context("Failed to create audio decoder")?;

    let source_sample_rate = codec_params
        .sample_rate
        .context("Sample rate not specified")?;

    let channels = codec_params
        .channels
        .context("Channel count not specified")?
        .count();

    let max_frames = (max_seconds * f64::from(source_sample_rate)) as usize;
    let max_samples = max_frames * channels;
    let mut decoded_samples: Vec<f32> = Vec::with_capacity(max_samples);

    loop {
        if decoded_samples.len() >= max_samples {
            break; // Enough decoded for preview
        }

        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(_)) => break,
            Err(Error::ResetRequired) => { decoder.reset(); continue; }
            Err(err) => return Err(anyhow::anyhow!("Error reading packet: {err}")),
        };

        if packet.track_id() != track_id { continue; }

        match decoder.decode(&packet) {
            Ok(audio_buf) => {
                let samples = convert_audio_buffer_to_f32(&audio_buf, channels);
                decoded_samples.extend_from_slice(&samples);
            }
            Err(Error::DecodeError(_)) => {}
            Err(err) => return Err(anyhow::anyhow!("Decode error: {err}")),
        }
    }

    // Truncate to exact max if we overshot
    if decoded_samples.len() > max_samples {
        decoded_samples.truncate(max_samples);
    }

    let frame_count = decoded_samples.len() / channels;
    let duration_seconds = frame_count as f64 / f64::from(source_sample_rate);

    // Return at native rate — no resampling for preview speed
    Ok(AudioClip {
        samples: decoded_samples,
        channels,
        sample_rate: source_sample_rate,
        duration_seconds,
        file_path: path_ref.to_string_lossy().to_string(),
    })
}

/// Load an audio file using Symphonia (for MP3, FLAC, OGG, etc.)
fn load_audio_file_symphonia(path_ref: &Path) -> Result<AudioClip> {
    let file = std::fs::File::open(path_ref)
        .context(format!("Failed to open audio file: {}", path_ref.display()))?;

    let mss = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());

    // Create hint based on file extension
    let mut hint = Hint::new();
    if let Some(ext) = path_ref.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    // Probe the media source
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .context("Failed to probe audio file format")?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .context("No valid audio track found")?;

    let track_id = track.id;
    let codec_params = track.codec_params.clone();

    // Create decoder
    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .context("Failed to create audio decoder")?;

    let source_sample_rate = codec_params
        .sample_rate
        .context("Sample rate not specified in audio file")?;
    
    let channels = codec_params
        .channels
        .context("Channel count not specified in audio file")?
        .count();

    // Decode all packets into a flat buffer
    let mut decoded_samples: Vec<f32> = Vec::new();
    
    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(_)) => break, // End of stream
            Err(Error::ResetRequired) => {
                // The decoder must be reset
                decoder.reset();
                continue;
            }
            Err(err) => return Err(anyhow::anyhow!("Error reading packet: {err}")),
        };

        // Skip packets not for this track
        if packet.track_id() != track_id {
            continue;
        }

        // Decode the packet
        match decoder.decode(&packet) {
            Ok(audio_buf) => {
                // Convert the decoded audio buffer to f32 samples
                let samples = convert_audio_buffer_to_f32(&audio_buf, channels);
                decoded_samples.extend_from_slice(&samples);
            }
            Err(Error::DecodeError(_)) => {} // Skip decode errors
            Err(err) => return Err(anyhow::anyhow!("Decode error: {err}")),
        }
    }

    // Resample if needed
    let final_samples = if source_sample_rate == TARGET_SAMPLE_RATE {
        decoded_samples
    } else {
        resample_audio(
            &decoded_samples,
            source_sample_rate,
            TARGET_SAMPLE_RATE,
            channels,
        )?
    };

    let frame_count = final_samples.len() / channels;
    let duration_seconds = frame_count as f64 / f64::from(TARGET_SAMPLE_RATE);

    Ok(AudioClip {
        samples: final_samples,
        channels,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds,
        file_path: path_ref.to_string_lossy().to_string(),
    })
}

/// Convert Symphonia `AudioBufferRef` to interleaved f32 samples
fn convert_audio_buffer_to_f32(audio_buf: &AudioBufferRef<'_>, channels: usize) -> Vec<f32> {
    match audio_buf {
        AudioBufferRef::F32(buf) => {
            let left = buf.chan(0);
            let right = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            interleave_channels(left, right, buf.frames())
        }
        AudioBufferRef::F64(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s as f32).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s as f32).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U8(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| (f32::from(s) - 128.0) / 128.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| (f32::from(s) - 128.0) / 128.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U16(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| (f32::from(s) - 32768.0) / 32768.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| (f32::from(s) - 32768.0) / 32768.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U24(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s.inner() as f32 / 8_388_608.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s.inner() as f32 / 8_388_608.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U32(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| (s as f32 - 2_147_483_648.0) / 2_147_483_648.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| (s as f32 - 2_147_483_648.0) / 2_147_483_648.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S8(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| f32::from(s) / 128.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| f32::from(s) / 128.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S16(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| f32::from(s) / 32768.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| f32::from(s) / 32768.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S24(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s.inner() as f32 / 8_388_608.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s.inner() as f32 / 8_388_608.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S32(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s as f32 / 2_147_483_648.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s as f32 / 2_147_483_648.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
    }
}

/// Interleave left and right channels into a single buffer
fn interleave_channels(left: &[f32], right: &[f32], frames: usize) -> Vec<f32> {
    let mut output = Vec::with_capacity(frames * 2);
    for i in 0..frames {
        output.push(left[i]);
        output.push(right[i]);
    }
    output
}

/// Resample audio from source sample rate to target sample rate using FFT-based resampling
fn resample_audio(
    input: &[f32],
    source_rate: u32,
    target_rate: u32,
    channels: usize,
) -> Result<Vec<f32>> {
    if source_rate == target_rate {
        return Ok(input.to_vec());
    }

    // Deinterleave channels for resampling
    let frames = input.len() / channels;
    let mut channel_buffers: Vec<Vec<f32>> = vec![Vec::with_capacity(frames); channels];

    for frame_idx in 0..frames {
        for ch in 0..channels {
            channel_buffers[ch].push(input[frame_idx * channels + ch]);
        }
    }

    // Use FFT-based resampler for offline processing (handles buffering correctly)
    let mut resampler = FftFixedInOut::<f32>::new(
        source_rate as usize,
        target_rate as usize,
        1024, // chunk size
        channels,
    )?;

    let mut resampled_buffers: Vec<Vec<f32>> = vec![Vec::new(); channels];
    let chunk_size = resampler.input_frames_next();
    let mut position = 0;

    // Process full chunks
    while position + chunk_size <= frames {
        let chunk: Vec<Vec<f32>> = channel_buffers
            .iter()
            .map(|ch| ch[position..position + chunk_size].to_vec())
            .collect();

        let resampled = resampler.process(&chunk, None)?;
        for (ch_idx, ch_data) in resampled.iter().enumerate() {
            resampled_buffers[ch_idx].extend_from_slice(ch_data);
        }
        position += chunk_size;
    }

    // Handle remaining samples with padding
    if position < frames {
        let remaining = frames - position;
        let padded_chunk: Vec<Vec<f32>> = channel_buffers
            .iter()
            .map(|ch| {
                let mut chunk = ch[position..].to_vec();
                chunk.resize(chunk_size, 0.0);
                chunk
            })
            .collect();

        let resampled = resampler.process(&padded_chunk, None)?;

        // Calculate how many output frames correspond to actual input
        let ratio = f64::from(target_rate) / f64::from(source_rate);
        let output_for_remaining = (remaining as f64 * ratio).ceil() as usize;

        for (ch_idx, ch_data) in resampled.iter().enumerate() {
            let take_count = output_for_remaining.min(ch_data.len());
            resampled_buffers[ch_idx].extend_from_slice(&ch_data[..take_count]);
        }
    }

    // Interleave resampled channels
    let output_frames = resampled_buffers[0].len();
    let mut output = Vec::with_capacity(output_frames * channels);

    for frame_idx in 0..output_frames {
        for buf in &resampled_buffers {
            output.push(buf[frame_idx]);
        }
    }

    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_interleave_channels() {
        let left = vec![1.0, 2.0, 3.0];
        let right = vec![4.0, 5.0, 6.0];
        let interleaved = interleave_channels(&left, &right, 3);
        assert_eq!(interleaved, vec![1.0, 4.0, 2.0, 5.0, 3.0, 6.0]);
    }

    #[test]
    fn test_audio_clip_properties() {
        let clip = AudioClip {
            samples: vec![0.0, 0.1, 0.2, 0.3, 0.4, 0.5], // 3 frames, stereo
            channels: 2,
            sample_rate: 48000,
            duration_seconds: 3.0 / 48000.0,
            file_path: "test.wav".to_string(),
        };

        assert_eq!(clip.frame_count(), 3);
        assert_eq!(clip.get_sample(0, 0), Some(0.0));
        assert_eq!(clip.get_sample(0, 1), Some(0.1));
        assert_eq!(clip.get_sample(1, 0), Some(0.2));
        assert_eq!(clip.get_sample(1, 1), Some(0.3));
        assert_eq!(clip.get_sample(3, 0), None); // Out of bounds
    }

    #[test]
    fn test_no_resample_when_rates_match() {
        let input = vec![1.0, 2.0, 3.0, 4.0];
        let result = resample_audio(&input, 48000, 48000, 2).unwrap();
        assert_eq!(result, input);
    }
}

