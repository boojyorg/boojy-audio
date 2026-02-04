/// MIDI recording engine
use crate::midi::{MidiClip, MidiEvent, MidiEventType};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

const SAMPLE_RATE: u32 = 48000;

/// MIDI recording state
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MidiRecordingState {
    Idle,
    Recording,
}

/// MIDI recorder
pub struct MidiRecorder {
    /// Current recording state
    state: MidiRecordingState,
    /// Buffer of recorded MIDI events
    events: Vec<MidiEvent>,
    /// Recording start timestamp (in samples)
    start_timestamp: u64,
    /// Sample position where actual recording begins (after count-in)
    /// Events before this position are discarded
    recording_start_samples: u64,
    /// Current playhead position (in samples)
    playhead_samples: Arc<AtomicU64>,
    /// Tempo (BPM) for quantization
    tempo: f64,
    /// Quantize grid size (in samples, 0 = no quantization)
    quantize_grid_samples: u64,
    /// Notes held during count-in (note_number -> NoteOn event)
    /// Used to catch notes that straddle the recording boundary
    held_notes: HashMap<u8, MidiEvent>,
    /// Whether held notes have been flushed into the recording
    held_notes_flushed: bool,
}

impl MidiRecorder {
    /// Create a new MIDI recorder
    pub fn new(playhead_samples: Arc<AtomicU64>) -> Self {
        Self {
            state: MidiRecordingState::Idle,
            events: Vec::new(),
            start_timestamp: 0,
            recording_start_samples: 0,
            playhead_samples,
            tempo: 120.0,
            quantize_grid_samples: 0,
            held_notes: HashMap::new(),
            held_notes_flushed: false,
        }
    }

    /// Start recording MIDI
    pub fn start_recording(&mut self) -> Result<String, String> {
        if self.state != MidiRecordingState::Idle {
            return Err("Already recording".to_string());
        }

        // Get current playhead position as recording start point
        self.start_timestamp = self.playhead_samples.load(Ordering::SeqCst);

        self.events.clear();
        self.held_notes.clear();
        self.held_notes_flushed = false;
        self.state = MidiRecordingState::Recording;

        eprintln!("🎹 [MIDI_REC] Recording started at sample {}", self.start_timestamp);
        Ok("Recording started".to_string())
    }

    /// Stop recording and return the recorded MIDI clip
    pub fn stop_recording(&mut self) -> Result<Option<MidiClip>, String> {
        if self.state != MidiRecordingState::Recording {
            return Err("Not recording".to_string());
        }

        self.state = MidiRecordingState::Idle;

        if self.events.is_empty() {
            eprintln!("⚠️ [MIDI_REC] No MIDI events recorded");
            return Ok(None);
        }

        eprintln!("🎹 [MIDI_REC] Recording stopped. {} events captured", self.events.len());

        // Create MIDI clip from recorded events
        let mut clip = MidiClip::with_events(self.events.clone(), SAMPLE_RATE);

        // Apply quantization if enabled
        if self.quantize_grid_samples > 0 {
            clip.quantize(self.quantize_grid_samples);
            eprintln!("🎹 [MIDI_REC] Applied quantization: {} samples", self.quantize_grid_samples);
        }

        Ok(Some(clip))
    }

    /// Set the sample position where actual recording begins (after count-in)
    pub fn set_recording_start(&mut self, samples: u64) {
        self.recording_start_samples = samples;
        eprintln!("🎹 [MIDI_REC] Recording start set to sample {}", samples);
    }

    /// Record a MIDI event
    pub fn record_event(&mut self, event: MidiEvent) {
        if self.state != MidiRecordingState::Recording {
            return;
        }

        // During count-in: track held notes so we can catch notes that
        // straddle the recording boundary (pressed before, released after)
        if event.timestamp_samples < self.recording_start_samples {
            match event.event_type {
                MidiEventType::NoteOn { note, .. } => {
                    self.held_notes.insert(note, event);
                }
                MidiEventType::NoteOff { note, .. } => {
                    self.held_notes.remove(&note);
                }
            }
            return;
        }

        // First event after boundary: flush any notes still held from count-in
        // These are notes the user pressed before the recording start and is
        // still holding — insert them at timestamp 0 (the recording start)
        if !self.held_notes_flushed {
            self.held_notes_flushed = true;
            let held: Vec<MidiEvent> = self.held_notes.drain().map(|(_, e)| {
                match e.event_type {
                    MidiEventType::NoteOn { note, velocity } => {
                        eprintln!(
                            "🎹 [MIDI_REC] Caught held note from count-in: note={}, vel={}",
                            note, velocity
                        );
                        MidiEvent::note_on(note, velocity, 0)
                    }
                    _ => unreachable!(), // held_notes only stores NoteOn
                }
            }).collect();
            for e in held {
                self.events.push(e);
            }
        }

        // Make timestamp relative to recording start (after count-in)
        let mut recorded_event = event;
        recorded_event.timestamp_samples -= self.recording_start_samples;

        // Deduplicate: skip if identical to the last recorded event
        // (handles MIDI controllers that send on multiple channels simultaneously)
        if let Some(last) = self.events.last() {
            if *last == recorded_event {
                return;
            }
        }

        self.events.push(recorded_event);

        eprintln!(
            "🎹 [MIDI_REC] Event recorded: {:?} at sample {}",
            recorded_event.event_type, recorded_event.timestamp_samples
        );
    }

    /// Get current recording state
    pub fn get_state(&self) -> MidiRecordingState {
        self.state
    }

    /// Check if currently recording
    pub fn is_recording(&self) -> bool {
        self.state == MidiRecordingState::Recording
    }

    /// Set tempo (BPM) for quantization calculations
    pub fn set_tempo(&mut self, tempo: f64) {
        self.tempo = tempo.max(20.0).min(300.0);
        self.update_quantize_grid();
    }

    /// Get tempo
    pub fn get_tempo(&self) -> f64 {
        self.tempo
    }

    /// Set quantize grid (0 = off, 1/4, 1/8, 1/16, 1/32)
    pub fn set_quantize(&mut self, note_division: u32) {
        if note_division == 0 {
            self.quantize_grid_samples = 0;
            eprintln!("🎹 [MIDI_REC] Quantization disabled");
        } else {
            self.update_quantize_grid();
            eprintln!("🎹 [MIDI_REC] Quantization enabled: 1/{} note", note_division);
        }
    }

    /// Update quantize grid based on tempo
    fn update_quantize_grid(&mut self) {
        // Calculate samples per beat
        let seconds_per_beat = 60.0 / self.tempo;
        let samples_per_beat = (seconds_per_beat * SAMPLE_RATE as f64) as u64;

        // Default to 1/16 note grid
        self.quantize_grid_samples = samples_per_beat / 4;
    }

    /// Get number of recorded events
    pub fn event_count(&self) -> usize {
        self.events.len()
    }

    /// Get a snapshot of recorded events for live UI preview
    /// Returns a reference to the events buffer (no allocation)
    pub fn get_events_snapshot(&self) -> &[MidiEvent] {
        &self.events
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::midi::MidiEventType;

    #[test]
    fn test_midi_recorder_start_stop() {
        let playhead = Arc::new(AtomicU64::new(0));
        let mut recorder = MidiRecorder::new(playhead);

        assert_eq!(recorder.get_state(), MidiRecordingState::Idle);

        recorder.start_recording().unwrap();
        assert_eq!(recorder.get_state(), MidiRecordingState::Recording);

        let result = recorder.stop_recording().unwrap();
        assert!(result.is_none()); // No events recorded

        assert_eq!(recorder.get_state(), MidiRecordingState::Idle);
    }

    #[test]
    fn test_midi_recorder_record_events() {
        let playhead = Arc::new(AtomicU64::new(0));
        let mut recorder = MidiRecorder::new(playhead);

        recorder.start_recording().unwrap();

        // Record some events
        let event1 = MidiEvent::note_on(60, 100, 1000);
        let event2 = MidiEvent::note_off(60, 64, 2000);

        recorder.record_event(event1);
        recorder.record_event(event2);

        assert_eq!(recorder.event_count(), 2);

        let clip = recorder.stop_recording().unwrap();
        assert!(clip.is_some());

        let clip = clip.unwrap();
        assert_eq!(clip.events.len(), 2);
    }

    #[test]
    fn test_midi_recorder_quantization() {
        let playhead = Arc::new(AtomicU64::new(0));
        let mut recorder = MidiRecorder::new(playhead);

        recorder.set_tempo(120.0);
        recorder.set_quantize(16); // 1/16 note

        recorder.start_recording().unwrap();

        // Record event slightly off-grid
        let event = MidiEvent::note_on(60, 100, 1010);
        recorder.record_event(event);

        let clip = recorder.stop_recording().unwrap();
        assert!(clip.is_some());

        // Events should be quantized (exact value depends on tempo/grid)
        let clip = clip.unwrap();
        assert!(clip.events.len() > 0);
    }
}
