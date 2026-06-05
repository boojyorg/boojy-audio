//! Drum Kit instrument — a multi-slot one-shot sampler.
//!
//! A `DrumKit` is one instrument on one track. Each **pad** is a slot holding its own
//! [`Sampler`](crate::sampler::Sampler), pinned to a fixed MIDI note. An incoming `note_on`
//! is routed to the slot whose `pinned_note` matches — so a drum hit is just an ordinary MIDI
//! note at the pad's pitch. Pads are one-shot (the underlying sampler defaults to no-loop), and
//! each slot's `root_note` is set equal to its `pinned_note` so the sample plays at native pitch
//! (the per-pad Pitch control adds `transpose_semitones` on top).
//!
//! Per-pad **volume** reuses the sampler's `volume_db`; **pan**, **mute**, and **solo** are owned
//! by the kit (the sampler has no notion of them) and applied while summing the slots. The
//! `choke_group` field is reserved for a future feature (open-hat cut by closed-hat) and is unused
//! in v0.6.

use crate::audio_file::AudioClip;
use crate::sampler::{Sampler, SamplerData};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// A single drum pad: one sampler pinned to one MIDI note.
pub struct DrumSlot {
    /// Stable handle used by the UI/FFI to address this pad (independent of display order).
    pub pad_index: u8,
    /// The MIDI note this pad responds to. Also the slot sampler's root note (native pitch).
    pub pinned_note: u8,
    /// Per-pad pan, -1.0 (hard left) .. 1.0 (hard right). Applied by the kit when summing.
    pub pan: f32,
    /// Per-pad mute.
    pub muted: bool,
    /// Per-pad solo. If any slot is soloed, only soloed (and non-muted) slots sound.
    pub soloed: bool,
    /// Reserved for a future choke-group feature; unused in v0.6.
    pub choke_group: Option<u8>,
    /// The pad's sampler (one sample, one-shot playback, AR envelope).
    pub sampler: Sampler,
}

impl DrumSlot {
    fn new(pad_index: u8, pinned_note: u8, sample_rate: f32) -> Self {
        let mut sampler = Sampler::new(sample_rate);
        // Pin the sampler's root to the pad note so it plays at native pitch.
        sampler.root_note = pinned_note;
        Self {
            pad_index,
            pinned_note,
            pan: 0.0,
            muted: false,
            soloed: false,
            choke_group: None,
            sampler,
        }
    }
}

/// A multi-slot one-shot sampler. Holds N pads, routes notes by pinned MIDI note.
pub struct DrumKit {
    slots: Vec<DrumSlot>,
    sample_rate: f32,
    next_pad_index: u8,
}

impl DrumKit {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            slots: Vec::new(),
            sample_rate,
            next_pad_index: 0,
        }
    }

    /// Add an empty pad pinned to `pinned_note`. Rejects a duplicate pinned note (which would make
    /// two pads fire on the same MIDI note). Returns the new pad's stable index, or `None` if the
    /// note is already taken.
    pub fn add_pad(&mut self, pinned_note: u8) -> Option<u8> {
        if self.slots.iter().any(|s| s.pinned_note == pinned_note) {
            println!("⚠️ DrumKit: note {pinned_note} already has a pad; rejecting duplicate");
            return None;
        }
        let pad_index = self.next_pad_index;
        self.next_pad_index = self.next_pad_index.wrapping_add(1);
        self.slots
            .push(DrumSlot::new(pad_index, pinned_note, self.sample_rate));
        Some(pad_index)
    }

    /// Restore a pad with an explicit `pad_index` (used when loading a project so indices are
    /// preserved). Skips a duplicate pinned note.
    fn restore_pad(&mut self, pad_index: u8, pinned_note: u8) -> bool {
        if self.slots.iter().any(|s| s.pinned_note == pinned_note) {
            return false;
        }
        self.slots
            .push(DrumSlot::new(pad_index, pinned_note, self.sample_rate));
        self.next_pad_index = self.next_pad_index.max(pad_index.wrapping_add(1));
        true
    }

    /// Remove a pad by its index. Returns `true` if a pad was removed.
    pub fn remove_pad(&mut self, pad_index: u8) -> bool {
        let before = self.slots.len();
        self.slots.retain(|s| s.pad_index != pad_index);
        self.slots.len() != before
    }

    /// The lowest MIDI note not yet used by a pad, searching from `start` upward. Useful for the
    /// UI's "[+] adds the next free note" behaviour.
    pub fn next_free_note(&self, start: u8) -> Option<u8> {
        (start..=127).find(|n| self.slots.iter().all(|s| s.pinned_note != *n))
    }

    fn slot_mut(&mut self, pad_index: u8) -> Option<&mut DrumSlot> {
        self.slots.iter_mut().find(|s| s.pad_index == pad_index)
    }

    /// Load a sample into a pad. Sets the sampler's root note to the pad's pinned note so it plays
    /// at native pitch. Returns `true` if the pad exists.
    pub fn load_pad_sample(&mut self, pad_index: u8, clip: Arc<AudioClip>) -> bool {
        if let Some(slot) = self.slot_mut(pad_index) {
            let note = slot.pinned_note;
            slot.sampler.load_sample_with_root(clip, note);
            true
        } else {
            println!("⚠️ DrumKit: no pad with index {pad_index} to load sample into");
            false
        }
    }

    /// Set a per-pad parameter. Kit-owned keys (`pan`, `muted`, `soloed`, `choke_group`) are handled
    /// here; everything else is forwarded to the pad's sampler (`volume_db`, `attack`, `release`,
    /// `transpose_semitones`, `reversed`, …).
    pub fn set_pad_parameter(&mut self, pad_index: u8, key: &str, value: &str) {
        let Some(slot) = self.slot_mut(pad_index) else {
            println!("⚠️ DrumKit: no pad with index {pad_index} for parameter {key}");
            return;
        };
        match key {
            "pan" => {
                if let Ok(v) = value.parse::<f32>() {
                    slot.pan = v.clamp(-1.0, 1.0);
                }
            }
            "muted" => slot.muted = value == "1" || value == "true",
            "soloed" => slot.soloed = value == "1" || value == "true",
            "choke_group" => {
                slot.choke_group = value.parse::<u8>().ok();
            }
            _ => slot.sampler.set_parameter(key, value),
        }
    }

    /// Route a note to the matching pad. Notes with no matching pad are ignored.
    pub fn note_on(&mut self, note: u8, velocity: u8) {
        if let Some(slot) = self.slots.iter_mut().find(|s| s.pinned_note == note) {
            slot.sampler.note_on(note, velocity);
        }
    }

    pub fn note_off(&mut self, note: u8) {
        // One-shot pads ignore note-off, but route it anyway for slots in loop mode.
        if let Some(slot) = self.slots.iter_mut().find(|s| s.pinned_note == note) {
            slot.sampler.note_off(note);
        }
    }

    pub fn all_notes_off(&mut self) {
        for slot in &mut self.slots {
            slot.sampler.all_notes_off();
        }
    }

    /// Process one frame, summing all pads with per-pad pan, mute, and solo applied.
    pub fn process_sample(&mut self) -> (f32, f32) {
        let any_solo = self.slots.iter().any(|s| s.soloed);
        let mut left = 0.0;
        let mut right = 0.0;
        for slot in &mut self.slots {
            let audible = if any_solo { slot.soloed } else { !slot.muted };
            // Always advance the sampler so muted pads don't "resume" when unmuted mid-hit.
            let (l, r) = slot.sampler.process_sample();
            if !audible {
                continue;
            }
            // Constant-power pan: pan -1 -> hard left, +1 -> hard right.
            let angle = (slot.pan + 1.0) * std::f32::consts::FRAC_PI_4;
            left += l * angle.cos();
            right += r * angle.sin();
        }
        (left, right)
    }

    pub fn process_sample_mono(&mut self) -> f32 {
        let (l, r) = self.process_sample();
        (l + r) * 0.5
    }

    /// Number of pads.
    pub fn pad_count(&self) -> usize {
        self.slots.len()
    }

    /// Read-only view of the slots (for UI info / waveform peaks).
    pub fn slots(&self) -> &[DrumSlot] {
        &self.slots
    }

    /// Snapshot for serialization.
    pub fn get_parameters(&self) -> DrumKitData {
        DrumKitData {
            slots: self
                .slots
                .iter()
                .map(|slot| DrumSlotData {
                    pad_index: slot.pad_index,
                    pinned_note: slot.pinned_note,
                    pan: slot.pan,
                    muted: slot.muted,
                    soloed: slot.soloed,
                    choke_group: slot.choke_group,
                    sampler: slot.sampler.get_parameters(),
                })
                .collect(),
        }
    }
}

// ============================================================================
// SERIALIZATION
// ============================================================================

/// Persisted state for a whole drum kit.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DrumKitData {
    pub slots: Vec<DrumSlotData>,
}

/// Persisted state for one pad. `sampler` is `None` for an empty (sample-less) pad.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DrumSlotData {
    pub pad_index: u8,
    pub pinned_note: u8,
    #[serde(default)]
    pub pan: f32,
    #[serde(default)]
    pub muted: bool,
    #[serde(default)]
    pub soloed: bool,
    #[serde(default)]
    pub choke_group: Option<u8>,
    #[serde(default)]
    pub sampler: Option<SamplerData>,
}

impl DrumKit {
    /// Recreate a pad's metadata (pinned note, pan, mute, solo, choke group), preserving its saved
    /// index. The sample and sampler parameters are restored separately by the caller, in this
    /// order: `restore_pad_meta` → load the sample file → [`restore_pad_sampler`]. This mirrors the
    /// sampler restore flow (load the audio file first so loop points resolve against it). Returns
    /// `true` if the pad was added.
    pub fn restore_pad_meta(&mut self, data: &DrumSlotData) -> bool {
        if !self.restore_pad(data.pad_index, data.pinned_note) {
            return false;
        }
        if let Some(slot) = self.slot_mut(data.pad_index) {
            slot.pan = data.pan;
            slot.muted = data.muted;
            slot.soloed = data.soloed;
            slot.choke_group = data.choke_group;
        }
        true
    }

    /// Restore a pad's sampler parameters from saved data (call after the sample file is loaded).
    pub fn restore_pad_sampler(&mut self, pad_index: u8, sampler_data: &SamplerData) {
        if let Some(slot) = self.slot_mut(pad_index) {
            slot.sampler.restore_parameters(sampler_data);
            // Keep the slot's root pinned to its note regardless of the saved root.
            slot.sampler.root_note = slot.pinned_note;
        }
    }

    /// The saved sample path for a pad, if it had one (used by the project loader to load the file).
    pub fn slot_sample_path(data: &DrumSlotData) -> Option<&str> {
        data.sampler
            .as_ref()
            .map(|s| s.sample_path.as_str())
            .filter(|p| !p.is_empty())
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_pad_rejects_duplicate_note() {
        let mut kit = DrumKit::new(48000.0);
        let a = kit.add_pad(36);
        assert_eq!(a, Some(0));
        // Same note again -> rejected.
        assert_eq!(kit.add_pad(36), None);
        // Different note -> new pad with next index.
        assert_eq!(kit.add_pad(38), Some(1));
        assert_eq!(kit.pad_count(), 2);
    }

    #[test]
    fn test_next_free_note() {
        let mut kit = DrumKit::new(48000.0);
        kit.add_pad(36);
        kit.add_pad(37);
        assert_eq!(kit.next_free_note(36), Some(38));
        assert_eq!(kit.next_free_note(40), Some(40));
    }

    #[test]
    fn test_remove_pad() {
        let mut kit = DrumKit::new(48000.0);
        let a = kit.add_pad(36).unwrap();
        kit.add_pad(38);
        assert!(kit.remove_pad(a));
        assert!(!kit.remove_pad(a)); // already gone
        assert_eq!(kit.pad_count(), 1);
        // The freed note can be re-added.
        assert!(kit.add_pad(36).is_some());
    }

    #[test]
    fn test_note_on_routes_only_to_matching_pad() {
        // Build a kit with two pads, each loaded with a distinct test clip, and confirm a note
        // only triggers the pad whose pinned note matches.
        let mut kit = DrumKit::new(48000.0);
        let kick = kit.add_pad(36).unwrap();
        let snare = kit.add_pad(38).unwrap();
        kit.load_pad_sample(kick, Arc::new(test_clip(0.5)));
        kit.load_pad_sample(snare, Arc::new(test_clip(0.9)));

        // Hit the kick note: only the kick voice should be active.
        kit.note_on(36, 100);
        assert_eq!(active_voices(&kit, kick), 1);
        assert_eq!(active_voices(&kit, snare), 0);

        // A note with no pad does nothing.
        kit.note_on(100, 100);
        assert_eq!(active_voices(&kit, snare), 0);

        // Hit the snare note: now the snare voice is active too.
        kit.note_on(38, 100);
        assert_eq!(active_voices(&kit, snare), 1);
    }

    #[test]
    fn test_mute_silences_pad_but_solo_overrides() {
        let mut kit = DrumKit::new(48000.0);
        let kick = kit.add_pad(36).unwrap();
        kit.load_pad_sample(kick, Arc::new(test_clip(1.0)));
        kit.note_on(36, 127);
        // Audible by default.
        assert!(max_abs(&mut kit, 64) > 0.0);

        // Muted -> silent.
        kit.set_pad_parameter(kick, "muted", "true");
        kit.note_on(36, 127);
        assert!(max_abs(&mut kit, 64) <= f32::EPSILON);

        // Solo on a different (empty) pad would silence the kick; solo on the kick keeps it.
        kit.set_pad_parameter(kick, "muted", "false");
        kit.set_pad_parameter(kick, "soloed", "true");
        kit.note_on(36, 127);
        assert!(max_abs(&mut kit, 64) > 0.0);
    }

    #[test]
    fn test_serialization_roundtrip_preserves_pads() {
        let mut kit = DrumKit::new(48000.0);
        let kick = kit.add_pad(36).unwrap();
        kit.set_pad_parameter(kick, "pan", "-0.5");
        kit.set_pad_parameter(kick, "muted", "true");
        let data = kit.get_parameters();
        let json = serde_json::to_string(&data).unwrap();
        let back: DrumKitData = serde_json::from_str(&json).unwrap();
        assert_eq!(back.slots.len(), 1);
        assert_eq!(back.slots[0].pinned_note, 36);
        assert!((back.slots[0].pan - (-0.5)).abs() < 1e-6);
        assert!(back.slots[0].muted);
        // Empty pad serializes with no sampler.
        assert!(back.slots[0].sampler.is_none());
    }

    // --- test helpers ---

    /// A 1-channel constant-amplitude clip, long enough to sound for a while.
    fn test_clip(amplitude: f32) -> AudioClip {
        AudioClip {
            samples: vec![amplitude; 48000], // 1 second mono
            channels: 1,
            sample_rate: 48000,
            duration_seconds: 1.0,
            file_path: "test.wav".to_string(),
        }
    }

    fn active_voices(kit: &DrumKit, pad_index: u8) -> usize {
        kit.slots()
            .iter()
            .find(|s| s.pad_index == pad_index)
            .map_or(0, |s| s.sampler.active_voice_count())
    }

    /// Peak absolute mono output over `n` frames.
    fn max_abs(kit: &mut DrumKit, n: usize) -> f32 {
        let mut peak = 0.0_f32;
        for _ in 0..n {
            peak = peak.max(kit.process_sample_mono().abs());
        }
        peak
    }
}
