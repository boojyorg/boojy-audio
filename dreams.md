# Boojy Audio — Dreams

## §1 Active Engineering Target

**Target:** v0.5.0 — **Trust & Legibility**. Correctness/hardening for the moments a session leaves
the happy path, plus legibility (tokenised colours, themed/scaled painters). Theme set by the
2026-06-01 review chain (`docs/reviews/v0.4.0_pre_release_triage_2026_06_01.md`).

**Status (2026-06-04): in CI, dogfooding before tag.** The whole v0.5 branch is up as **PR #43**
(`feat/v0.5-mixer-fader-affordances` → master) — the first time it has hit CI. Decision: **skip the
unpublished v0.4.0 draft release**, next published tag is **v0.5.0**.

### Milestones
- [x] CI/test trust (C92/C95) + FEATURE_TRACKER sweep + headless goldens.
- [x] Correctness cluster: VST3 lifecycle (C30/34/35), DeleteTrack content-loss undo
  (C62/68/76/97) incl. VST3 instrument restore, recorder audio-thread blocking (C1–C3),
  round-trip tempo (C72), undo-integrity (C66/86), loadProject gate (C73/77), split-clip
  undo (C52/63/64).
- [x] Offline export fixes: synth+FX silence (C6), true mono WAV (C22), MIDI CC on bounce (C23).
- [x] FFI lock-safety (C44/46/47) — deadlock on audio-file drag.
- [x] Project-layout robustness (C74/C80).
- [x] Graphic EQ (variable bands, drag-the-dot graph) + sample-rate fix (C12) — PR #40.
- [x] Legibility pass (#10): one green, MeterColorZones, painters threaded with colours + textScale,
  piano-roll lane legibility.
- [x] Mixer affordances (#11): editable dB readout (drag to scrub / click to type, one undo step).
- [x] Arrangement-view polish pass + lighter canvas (`#1C1D21`).
- [x] UX/dogfood fixes: consistent panel sizes on new project; single-box 24px library search;
  piano-roll resize no-residual-bar; loop-end playback sync (dogfood bug B).
- [ ] **Before tag:** PR #43 CI all-green → finish dogfood → merge → version-sync (CHANGELOG →
  v0.5.0, ROADMAP, README, FEATURE_TRACKER, **bump `ui/pubspec.yaml`**, archive the plan doc) →
  tag `v0.5.0`.

### Deferred → v0.5.1 "loop & device polish"
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
