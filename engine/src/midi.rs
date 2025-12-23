/// MIDI event and clip data structures
use std::cmp::Ordering;

/// MIDI note number (0-127)
pub type MidiNote = u8;

/// MIDI velocity (0-127)
pub type MidiVelocity = u8;

/// MIDI event types
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MidiEventType {
    NoteOn { note: MidiNote, velocity: MidiVelocity },
    NoteOff { note: MidiNote, velocity: MidiVelocity },
    // Future: CC, PitchBend, etc.
}

/// MIDI event with sample-accurate timestamp
#[derive(Debug, Clone, Copy)]
pub struct MidiEvent {
    /// Event type (NoteOn, NoteOff, etc.)
    pub event_type: MidiEventType,
    /// Timestamp in samples (relative to clip start)
    pub timestamp_samples: u64,
}

impl MidiEvent {
    pub fn new(event_type: MidiEventType, timestamp_samples: u64) -> Self {
        Self {
            event_type,
            timestamp_samples,
        }
    }

    /// Create a note-on event
    pub fn note_on(note: MidiNote, velocity: MidiVelocity, timestamp_samples: u64) -> Self {
        Self::new(
            MidiEventType::NoteOn { note, velocity },
            timestamp_samples,
        )
    }

    /// Create a note-off event
    pub fn note_off(note: MidiNote, velocity: MidiVelocity, timestamp_samples: u64) -> Self {
        Self::new(
            MidiEventType::NoteOff { note, velocity },
            timestamp_samples,
        )
    }
}

impl PartialEq for MidiEvent {
    fn eq(&self, other: &Self) -> bool {
        self.timestamp_samples == other.timestamp_samples
            && self.event_type == other.event_type
    }
}

impl Eq for MidiEvent {}

impl PartialOrd for MidiEvent {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for MidiEvent {
    fn cmp(&self, other: &Self) -> Ordering {
        self.timestamp_samples.cmp(&other.timestamp_samples)
    }
}

/// MIDI clip containing a sequence of MIDI events
#[derive(Debug, Clone)]
pub struct MidiClip {
    /// List of MIDI events (sorted by timestamp)
    pub events: Vec<MidiEvent>,
    /// Duration in samples
    pub duration_samples: u64,
    /// Sample rate (for converting to/from seconds)
    pub sample_rate: u32,
}

impl MidiClip {
    /// Snap duration to next bar boundary (at 120 BPM, 4/4 time)
    /// One bar = 4 beats = 2 seconds = 96000 samples at 48kHz
    /// Examples: 3.5 bars -> 4 bars, 3.1 bars -> 4 bars, 3.0 bars -> 3 bars
    pub fn snap_to_bar(samples: u64, sample_rate: u32) -> u64 {
        let samples_per_bar = (sample_rate as u64) * 2; // 2 seconds per bar at 120 BPM
        if samples == 0 {
            return samples_per_bar; // Minimum 1 bar
        }
        // If already on a bar boundary, keep it; otherwise round up
        if samples % samples_per_bar == 0 {
            samples
        } else {
            ((samples / samples_per_bar) + 1) * samples_per_bar
        }
    }

    /// Create a new empty MIDI clip
    pub fn new(sample_rate: u32) -> Self {
        Self {
            events: Vec::new(),
            duration_samples: 0,
            sample_rate,
        }
    }

    /// Create a MIDI clip with events
    pub fn with_events(mut events: Vec<MidiEvent>, sample_rate: u32) -> Self {
        // Sort events by timestamp
        events.sort();

        // Calculate duration snapped to bar boundary
        let last_event_samples = events
            .last()
            .map(|e| e.timestamp_samples)
            .unwrap_or(0);
        let duration_samples = Self::snap_to_bar(last_event_samples, sample_rate);

        Self {
            events,
            duration_samples,
            sample_rate,
        }
    }

    /// Add an event to the clip (maintains sorted order)
    pub fn add_event(&mut self, event: MidiEvent) {
        self.events.push(event);
        self.events.sort();

        // Update duration if event extends beyond current duration, snap to bar
        if event.timestamp_samples > self.duration_samples {
            self.duration_samples = Self::snap_to_bar(event.timestamp_samples, self.sample_rate);
        }
    }

    /// Remove an event at the given index
    pub fn remove_event(&mut self, index: usize) -> Option<MidiEvent> {
        if index < self.events.len() {
            Some(self.events.remove(index))
        } else {
            None
        }
    }

    /// Get all events within a time range (in samples)
    pub fn get_events_in_range(&self, start_samples: u64, end_samples: u64) -> Vec<MidiEvent> {
        self.events
            .iter()
            .filter(|e| e.timestamp_samples >= start_samples && e.timestamp_samples < end_samples)
            .copied()
            .collect()
    }

    /// Get duration in seconds
    pub fn duration_seconds(&self) -> f64 {
        self.duration_samples as f64 / self.sample_rate as f64
    }

    /// Quantize all events to the specified grid (in samples)
    pub fn quantize(&mut self, grid_samples: u64) {
        if grid_samples == 0 {
            return;
        }

        for event in &mut self.events {
            // Round to nearest grid position
            let remainder = event.timestamp_samples % grid_samples;
            if remainder < grid_samples / 2 {
                event.timestamp_samples -= remainder;
            } else {
                event.timestamp_samples += grid_samples - remainder;
            }
        }

        // Re-sort after quantization
        self.events.sort();
    }

    /// Clear all events
    pub fn clear(&mut self) {
        self.events.clear();
        self.duration_samples = 0;
    }
}

/// MIDI note representation for piano roll editing (not to be confused with MidiNote type)
#[derive(Debug, Clone, Copy)]
pub struct Note {
    /// MIDI note number (0-127)
    pub pitch: MidiNote,
    /// Velocity (0-127)
    pub velocity: MidiVelocity,
    /// Start time in samples
    pub start_samples: u64,
    /// Duration in samples
    pub duration_samples: u64,
}

impl Note {
    /// Convert note to NoteOn and NoteOff events
    pub fn to_events(&self) -> (MidiEvent, MidiEvent) {
        let note_on = MidiEvent::note_on(self.pitch, self.velocity, self.start_samples);
        let note_off = MidiEvent::note_off(
            self.pitch,
            64, // Standard release velocity
            self.start_samples + self.duration_samples,
        );
        (note_on, note_off)
    }

    /// Create a note from start/end events
    pub fn from_events(note_on_event: &MidiEvent, note_off_event: &MidiEvent) -> Option<Self> {
        match (note_on_event.event_type, note_off_event.event_type) {
            (
                MidiEventType::NoteOn { note, velocity },
                MidiEventType::NoteOff { note: note_off_pitch, .. },
            ) if note == note_off_pitch && note_off_event.timestamp_samples >= note_on_event.timestamp_samples => {
                Some(Self {
                    pitch: note,
                    velocity,
                    start_samples: note_on_event.timestamp_samples,
                    duration_samples: note_off_event.timestamp_samples - note_on_event.timestamp_samples,
                })
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_midi_event_ordering() {
        let e1 = MidiEvent::note_on(60, 100, 1000);
        let e2 = MidiEvent::note_on(62, 100, 2000);
        assert!(e1 < e2);
    }

    #[test]
    fn test_midi_clip_add_event() {
        let mut clip = MidiClip::new(48000);
        clip.add_event(MidiEvent::note_on(60, 100, 1000));
        clip.add_event(MidiEvent::note_off(60, 64, 2000));

        assert_eq!(clip.events.len(), 2);
        assert_eq!(clip.events[0].timestamp_samples, 1000);
        assert_eq!(clip.events[1].timestamp_samples, 2000);
    }

    #[test]
    fn test_midi_clip_quantize() {
        let mut clip = MidiClip::new(48000);
        clip.add_event(MidiEvent::note_on(60, 100, 1010));
        clip.add_event(MidiEvent::note_on(62, 100, 2980));

        // Quantize to 1000 sample grid
        clip.quantize(1000);

        assert_eq!(clip.events[0].timestamp_samples, 1000);
        assert_eq!(clip.events[1].timestamp_samples, 3000);
    }

    #[test]
    fn test_note_conversion() {
        let note = Note {
            pitch: 60,
            velocity: 100,
            start_samples: 1000,
            duration_samples: 1000,
        };

        let (note_on, note_off) = note.to_events();

        assert_eq!(note_on.timestamp_samples, 1000);
        assert_eq!(note_off.timestamp_samples, 2000);

        match note_on.event_type {
            MidiEventType::NoteOn { note, velocity } => {
                assert_eq!(note, 60);
                assert_eq!(velocity, 100);
            }
            _ => panic!("Expected NoteOn"),
        }
    }
}
