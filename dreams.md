# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** v0.6 — **Sound**. Headline feature: the **Drum Kit** — a one-click multi-slot one-shot
sampler that lets a beginner make their first beat. A drum hit is an ordinary MIDI note routed to a
pinned pad, so the kit writes to a normal MIDI clip (arrangement/undo/save-load come free). Plan:
`~/.claude/plans/bright-soaring-fox.md` (settled Layout A + design — don't relitigate).

**Status (2026-06-05): PR2 (editor UI) in progress** on `feat/v0.6-drum-kit-engine`.
PR-stack: **PR1 engine** committed `7884fdb` (DrumKit struct + 9 extern-C FFI shims + save/load;
`cargo test` 146 green; **Dart bindings deferred to PR2; not pushed, no PR yet**) → **PR2 UI**
(current) → **PR3 bundled starter kit**.

### Milestones (v0.6 Drum Kit)
- [x] **PR1 engine** — `DrumKit`/`DrumSlot`, note routing by pinned note, per-pad pan/mute/solo,
  duplicate-note rejection, reserved `choke_group`, `DrumKitData` save/load, 9 extern-C FFI shims.
- [ ] **PR2 UI** — Dart FFI bindings (mirror sampler) · `DrumKitInfo` model parsing
  `get_drum_kit_info` JSON · `editor_panel.dart` `_isDrumKitTrack` branch (`[DrumKit, MIDI]` tabs) ·
  `DrumKitEditor` (Layout A: detail panel left, step grid right) · `DrumStepSequencer` rows
  (colour swatch + `CapsuleFader`/`VolumeReadoutBox` + round M/S) · Library "Drum Kit" create-path ·
  undo (step toggles reuse `AddMidiNoteCommand`/`DeleteMidiNotesCommand`).
- [ ] **PR3 content** — bundled CC0 starter kit (kick/snare/hat/clap) wired into the create-path
  (the one-click first beat); asset-copy-to-app-support mechanism.

### v0.6 FFI surface (PR1, ready to bind)
`create_drum_kit_for_track_ffi(u64)->i64` · `add_drum_pad_ffi(u64,u8 pinned_note)->i64 pad_index` ·
`remove_drum_pad_ffi(u64,u8)->*c_char` · `load_drum_pad_sample_ffi(u64,u8,*path)->i32` ·
`set_drum_pad_parameter_ffi(u64,u8,*name,*value)->*c_char` · `is_drum_kit_track_ffi(u64)->i32` ·
`drum_next_free_note_ffi(u64,u8 start)->i64` · `get_drum_kit_info_ffi(u64)->*c_char` (JSON
`DrumKitData{slots:[{pad_index,pinned_note,pan,muted,soloed,choke_group,sampler:SamplerData?}]}`) ·
`get_drum_pad_waveform_peaks_ffi(u64,u8,usize,*out_len)->*f32` (free via
`free_sampler_waveform_peaks_ffi`). Param names = sampler's: `pan/muted/soloed/volume_db/attack_ms/
release_ms/transpose_semitones/fine_cents`.

### Deferred → v0.5.1 "loop & device polish" (still owed, post-v0.6)
- **Metronome downbeat doubles at loop wrap (intermittent).** Loop-wrap is driven by a Dart 60fps
  timer that seeks the engine, racing the audio thread; the metronome click window
  (`position_in_beat < 4000`, `engine/src/recorder.rs`) has no "already-fired-this-beat" guard and
  `seek_metronome` sets zero cooldown. Real fix: a per-beat last-fired-index guard and/or move the
  loop-wrap into the audio thread.
- **MIDI keyboard hot-plug doesn't work.** Connect a keyboard mid-session → Settings detects it but
  no notes flow; midir's `MidiInput` is consumed on connect (`engine/src/midi_input.rs`), refresh
  re-enumerates but the input connection isn't re-established for the new device. Needs hardware
  testing.
- Carried from earlier: **C24** (VST3 block size hardcoded on reload), **C99** (device disconnect
  kills playback silently), **C104** (output device not persisted).

### Trap (still live)
`daw_screen.dart` wires PRIVATE `_` copies of its mixins — the mixins are dead/diverged, so edit the
wired private methods, *not* the mixins.

### How we work here
- Plan **one milestone at a time** — only one active `docs/plans/vX.Y-plan.md`.
- After each release: **dogfood** on a real project, then pick the next theme from friction.
  `docs/ROADMAP.md` + `docs/FEATURE_TRACKER.md` are the backlog, not a pre-scheduled ladder.
- **Design decisions (UI/UX)** before locking implementation: brainstorm tradeoffs (UX first) →
  ASCII mockups (3–4 variants when layout is ambiguous; Tyr picks before code) → defer on taste,
  push back on architecture.

<!-- §1 only by design. git log is the history; Claude Code auto memory holds incidental learnings.
     No incident log, no backlog, no session ledger. -->
