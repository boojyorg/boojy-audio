# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **v0.6 — "Sound"** — spec: `docs/plans/v0.6-plan.md` (opened 2026-06-06 from the
triage). Work order: starter kit (drum-kit PR3) → sound quick wins (automation/reverse/monitoring)
→ join clips → UI ledger batches → cleanups. **Normalize moved to v1.0 (Tyr, 2026-06-08).**

**Status (2026-06-09):** everything through the playhead/orientation batch is **on master** —
drum-kit stack (#44/#65/#66), sound quick wins (#68), join MIDI (#70) + audio (#75, incl. the
recorded-audio save data-loss fix), gesture/tool fixes (#71/#72), batch-8 cleanups (#78: chord
palette removed, High Contrast hidden), and the playhead overhaul + transport-key fix (#79,
Tyr eyeballed and approved 2026-06-09). The **selection-token sweep** (deferred from #79) is the
current branch (`feat/v0.6-selection-token-sweep`). Remaining for v0.6: **UI batch 6 (top bar +
chrome)** → dogfood. §6.B strip mockup still parked pending a design conversation.

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
- [ ] **Selection-token sweep** (this branch): convert all remaining selected/active controls to
  the shared `selectionFill`/`selectionBorder` tokens — editor tabs + tools + collapsed tabs
  (via `resolveEditorButtonStyle`), transport split-button hover/divider, piano-roll Snap split,
  scale + audition toggles, audio/sampler controls-bar Loop/Warp/Reverse chips. Panel toggles
  stay quiet chrome — an active state was tried and Tyr rejected it (don't re-add).
- [ ] **UI batch 6 — top bar + chrome** (per plan §batch 6): overflow banner H1 · transport
  circles H2 · panel-toggle radius M25 · BPM compact M22 · RecoveryDialog logos H13 · dialog
  barrier/width M20.
- [ ] **Dogfood pass** → pick remaining ledger items / close v0.6.

**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
