/// Audio file loading and decoding
use anyhow::{Context, Result};
use rubato::{FftFixedInOut, Resampler};
use std::path::Path;
use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
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
    let file = std::fs::File::open(path_ref)
        .context(format!("Failed to open audio file: {:?}", path_ref))?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

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
            Err(err) => return Err(anyhow::anyhow!("Error reading packet: {}", err)),
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
            Err(Error::DecodeError(_)) => continue, // Skip decode errors
            Err(err) => return Err(anyhow::anyhow!("Decode error: {}", err)),
        }
    }

    // Resample if needed
    let final_samples = if source_sample_rate != TARGET_SAMPLE_RATE {
        resample_audio(
            &decoded_samples,
            source_sample_rate,
            TARGET_SAMPLE_RATE,
            channels,
        )?
    } else {
        decoded_samples
    };

    let frame_count = final_samples.len() / channels;
    let duration_seconds = frame_count as f64 / TARGET_SAMPLE_RATE as f64;

    Ok(AudioClip {
        samples: final_samples,
        channels,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds,
        file_path: path_ref.to_string_lossy().to_string(),
    })
}

/// Convert Symphonia AudioBufferRef to interleaved f32 samples
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
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| (s as f32 - 128.0) / 128.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| (s as f32 - 128.0) / 128.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U16(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| (s as f32 - 32768.0) / 32768.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| (s as f32 - 32768.0) / 32768.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U24(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s.inner() as f32 / 8388608.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s.inner() as f32 / 8388608.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::U32(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| (s as f32 - 2147483648.0) / 2147483648.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| (s as f32 - 2147483648.0) / 2147483648.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S8(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s as f32 / 128.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s as f32 / 128.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S16(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s as f32 / 32768.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s as f32 / 32768.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S24(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s.inner() as f32 / 8388608.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s.inner() as f32 / 8388608.0).collect();
            interleave_channels(&left, &right, buf.frames())
        }
        AudioBufferRef::S32(buf) => {
            let left: Vec<f32> = buf.chan(0).iter().map(|&s| s as f32 / 2147483648.0).collect();
            let right_src = if channels > 1 { buf.chan(1) } else { buf.chan(0) };
            let right: Vec<f32> = right_src.iter().map(|&s| s as f32 / 2147483648.0).collect();
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
        let ratio = target_rate as f64 / source_rate as f64;
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
        for ch in 0..channels {
            output.push(resampled_buffers[ch][frame_idx]);
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

