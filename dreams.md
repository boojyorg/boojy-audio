# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **v0.6 — "Sound"** — spec: `docs/plans/v0.6-plan.md` (opened 2026-06-06 from the
triage). Work order: starter kit (drum-kit PR3) → sound quick wins (automation/reverse/monitoring)
→ join clips → UI ledger batches → cleanups. **Normalize moved to v1.0 (Tyr, 2026-06-08).**

**Status (2026-06-10):** #83 (dogfood batch 1) MERGED. **Bug-hunt + design reviews ran
2026-06-10** (96 confirmed findings; reports = `docs/reviews/bug_hunt_2026_06_10.md` +
`design_recs_2026_06_10.md`) → verdict: don't tag v0.6 until the headline sound features work.
**Fix Batch 1 ("the sampler makes sound") = PR #84 open, CI watching**: silence-bug fix (default
clip never engine-registered — covered ALL instrument paths incl. a daw_screen private duplicate),
full sampler rescue (drop-zone, keyboard strip, on-waveform loop handles, slim 6-control bar,
per-gesture undo). Diff adversarially reviewed (2 blockers found+fixed pre-PR). Remaining
batches 2–5 in the bug-hunt report: time-domain/tempo (#3/#4 worst bug in app), drum kit,
right-click+favourites sweep, undo-truth+persistence; then visual sweep. §6.B strip mockup
still parked pending a design conversation.

### Milestones

- [x] **Publish v0.5.4 draft release** — verified 2026-06-07: `gh release list` shows v0.5.4 as
  Latest.
- [x] **Windows smoke test, round 2** (Tyr, parallel to dev): 5 CLAUDE.md steps + Save As
  (native dialog → `Documents\Boojy\Audio\Projects`), Open round-trip, Export WAV. Failures →
  small v0.5.5 before any v0.6 tag; suspects = Rust `save_project` / `project_manager_native`
  path handling.
- [ ] **macOS regression spot-check** (Tyr, 2 min): dialogs unchanged; Sparkle offers the update
  (live appcast-signature test).
- [x] **PR3 — starter kit** (#66 merged): 23 CC0/in-house WAVs bundled + first-use copy-out +
  8 pads pre-loaded on create (GM notes 36/38/42/46/39/41/47/49) + Samples category wired
  (+ fixed: top-level category items never rendered; + Windows `p.basename` fix in scanFolder).
- [x] **Sound quick wins** (PR #68 MERGED 2026-06-07, Tyr-approved): automation flag-flip
  (volume-only — pan + clip-lane hidden behind honest flags, lane gestures + clear-lane undoable;
  global Automation toggle in mixer header, strip controls pinned with [Volume ▾]/readout/reset in
  the lane-aligned space) · reverse-audio FFI + engine DSP (+ load-time re-push of all clip edit
  params — was silently lost on reopen) · input monitoring "I" toggle, armed-only (+ C9 even/odd
  channel fix).
- [x] **Join clips PR A — MIDI** (#70 MERGED 2026-06-07, Tyr-tested; fixes C37/C50): settled
  design = GarageBand interaction / Ableton outcome; Join naming; refuse mixed-type + cross-track.
  Live mixin `joinSelectedClips` Command-wrapped, loops unrolled via new
  `MidiClipData.unrolledNotes()` (shared with playback scheduling), automation merged via
  `ClipAutomation.joined()`, dead `_consolidateSelectedClips` deleted, right-click + ⌘J + menu
  renamed Join.
- [x] **Timeline gesture fixes** (#71 MERGED 2026-06-07): drag-create/box-select when scrolled
  (content-vs-viewport coordinate double-count — rule now in `.claude/rules/flutter-ui.md`),
  shift-click multi-select snapshot/repair, stale tool-mode cache at drag start. Plus **tool
  buttons match tab height** (#72 MERGED): 28→30px, icon 16→18; tool-state research report →
  `docs/reviews/tool_state_research_2026_06_07.md` (direction SETTLED: one global toolset, chip,
  marker+⌘E port — future batch).
- [x] **Join clips PR B — audio** (`feat/v0.6-join-audio-clips`, in flight — gates green, not yet
  merged/Tyr-tested): render-only engine `render_audio_clips_to_wav` (reuses
  `render_audio_clip_sample` so the bake is sample-identical to playback; gaps = silence; no track
  FX/fader/pan) + `join_audio_clips` API/FFI + Dart `JoinAudioClipsCommand` (undo restores originals
  via `addExistingClipToTrack` + re-applied edit params, never `loadAudioFileToTrack`). Wired into
  the existing `joinSelectedClips` so ⌘J / menu / right-click all cover audio.
- [x] **Data-loss fix folded into PR B**: saving a project with recorded (in-memory) audio clips
  failed — `save_project` `fs::copy`-ed a synthetic path that never existed, aborting the save. Save
  now writes in-memory clip samples out as a WAV (`project::write_audio_clip_to_project`) when the
  source path is absent.
- [x] **Playhead/orientation batch** (#79 merged, Tyr approved in-app 2026-06-09): playhead
  redesign (grey grabber, line white-on-play, decluttered ruler), Piano Roll live playhead +
  ruler-seek + paste-at-playhead, Space/L/M/I/O moved to HardwareKeyboard (focus-proof), partial
  selection-token unification. #78 cleanups also merged.
- [x] **Selection-token sweep** (#80 MERGED 2026-06-09): all remaining selected/active controls
  on the shared `selectionFill`/`selectionBorder` tokens — editor tabs + tools + collapsed tabs,
  transport split-button hover/divider, piano-roll Snap split, scale + audition toggles,
  audio/sampler Loop/Warp/Reverse chips. Panel toggles stay quiet chrome — an active state was
  tried and Tyr rejected it (don't re-add).
- [x] **UI batch 6 — top bar + chrome** (#81 MERGED 2026-06-09): overflow banner H1 · transport
  circles H2 · radius unification M25 · BPM suffix sheds M22 · RecoveryDialog lockup H13 ·
  dialog barrier + width tokens M20. (#82 dead-code deletion also merged.)
- [x] **Dogfood session 1** (2026-06-09) → **PR #83 open** (batch 1: editor⇄mixer fader sync —
  mixer→editor had never worked; synth card meter via track output; corner-artifact fix +
  flutter-ui.md rule; mixer narrow-width shedding; zoom-button backing; EQ auto-select band 1;
  emoji→BI track icons with key-based persistence; whole-wordmark Settings; 24px header
  unification; square full-bleed search field; solid 3px dividers; + Audio = Samples glyph).
- [x] **Merge #83** (merged 2026-06-10, CI green).
- [x] **Bug-hunt + design-recs reviews** (2026-06-10, ultracode): 96 confirmed findings → 5 fix
  batches; sampler + tempo time-domain block the tag. Reports in `docs/reviews/`.
- [ ] **Batch 1 — sampler rescue (PR #84)**: CI green → Tyr in-app walkthrough (drop zone, strip,
  loop handles, undo) → merge.
- [ ] **Batch 2 — "time is one domain"** (audio-clip tempo ratio #3/#4, metronome phase #28,
  time-sig decision #10/#18): the quietly-worst bug in the app.
- [ ] **Batches 3–5** (drum kit · right-click/favourites sweep · undo-truth/persistence), then the
  low-sweep visual batch; §4-of-bug-report decisions need Tyr (multi-arm, mixer border, M/S/R-lag
  retest after batch 2).
- [ ] **Tag decision** after batches land + dogfood round 2.

**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
