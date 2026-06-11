# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **v0.6 — "Sound"** — spec: `docs/plans/v0.6-plan.md` (opened 2026-06-06 from the
triage). Work order: starter kit (drum-kit PR3) → sound quick wins (automation/reverse/monitoring)
→ join clips → UI ledger batches → cleanups. **Normalize moved to v1.0 (Tyr, 2026-06-08).**

**Status (2026-06-11):** **All five bug-hunt fix batches MERGED** (reports =
`docs/reviews/bug_hunt_2026_06_10.md` + `design_recs_2026_06_10.md`, 96 findings): #84 sampler
rescue, #85 time-is-one-domain, #86 drum kit, #87 M/S/R tap lag, #88 right-click/favourites,
#89 undo-truth/persistence — details in the milestone list below. **Remaining before the tag
decision: low-sweep batch (scoped 2026-06-11, see milestone below), then dogfood round 2.**
§4 decisions SETTLED (Tyr, 2026-06-11): audio arming → **exclusive arm like MIDI** (engine
keeps multi-capture; deliberate multi-arm UI later) · mixer strip border → **unify to one
weight** (drop the 4px left accent) · count-in at bar 1 → **mute track playback during
count-in (metronome stays), riding the low sweep**. Wordmark baseline = Tyr's eyes at 1×/2×
during dogfood (verifiers split). §4.6 sampler Warp resolved — controls were cut by design in
the sampler rebuild, nothing to hide. §6.B strip mockup still parked pending a design
conversation.

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
- [x] **Batch 1 — sampler rescue (PR #84 MERGED 2026-06-10, Tyr-approved)**: silence fix on all
  instrument paths, drop zone (library + Finder drops), ▶ preview (strip rejected), ruler-only
  loop (on-waveform handles rejected), per-gesture undo incl. undoable load (new unload/get-path
  FFI). Deferred: Load copy-to-project, seconds-based sampler ruler, engine println flood.
- [x] **Batch 2 — "time is one domain"** (branch `fix/v0.6-batch2-time-domain`, PR opening):
  #3/#4 one real-seconds domain + tempo-change engine sync, #28 metronome phase, #19
  stopped-path lock (→ retest M/S/R lag), #10/#11/#18 time-sig honesty (denominator locked
  /4 — Tyr's call; piano-roll Signature now edits the project sig).
- [x] **Batch 3 — drum kit** (PR #86 MERGED 2026-06-10, squash `c30e609`, Tyr walkthrough-approved
  pre-PR per the new process): playhead clip-local formula, drag-to-paint (one stroke = one undo),
  pad fader/M/S undo, autoSelectClip on all creation paths (+ audio→sampler convert rebuilt — its
  clips were engine-only/invisible), waveform corner artifact. Follow-up flagged: delete dead
  mixin duplicates (`convertAudioTrackToSampler` etc.) in a consolidation pass.
- [x] **M/S/R tap lag — fixed (PR #87 MERGED 2026-06-10, `e470d75`, walkthrough passed)**:
  ancestor `onDoubleTap` on TrackHeader/TrackMixerStrip held the gesture arena ~300 ms per tap;
  now manual double-click detection + regression test `track_buttons_latency_test.dart` + rule
  in `.claude/rules/flutter-ui.md`. Closes the §4.4 bug-report decision.
- [x] **Batch 4 — right-click/favourites** (walkthrough PASSED 2026-06-10, PR opening):
  favourites for all sources (#9) + path-as-ID with legacy prune (#41) + star outline/filled
  pair, cross-platform `revealInFinder()` (#40), provider-listen sweep (track-header/CC/
  automation-lane menus) + **AST guard test** `ui/test/lint/provider_listen_guard_test.dart` +
  UndoRedoManager debug rethrow, phantom Effects tab via single `_tabs` source (#7, + collapsed
  Master), shared bottom buffer (#12), instrument-drop mixin consolidation (batch-3 debt).
- [x] **Batch 5 — undo-truth/persistence (PR #89 MERGED 2026-06-11, squash `7edc2f4`, CI
  green ×4, walkthrough passed)**: recording undo engine-resync (#15 trim trio re-push,
  #16 `replaceClipsOnTrack` engine sync + fresh-id redo), icon undo + persistence (#17/#47
  SetTrackIconCommand + ProjectPersistence + cross-project leak fix), auto-save live restart
  (#44), dead SettingsDialog + undo-limit UI DELETED per Tyr (#45), navBar dispose (#52),
  dead stubs gone. Walkthrough-found bonus: recording stop now selects the take (stale
  live-sentinel selection read as a blank clip). Ultracode workflow, batch-3 shape
  (36 agents, ~2.1M tokens; 16 raw → 6 confirmed findings, all fixed pre-walkthrough).
- [x] **Low-sweep batch** (branch `fix/v0.6-low-sweep`, built 2026-06-11, gates green ×5 —
  cargo test, clippy -D warnings, analyze --fatal-infos, format, widgets/lint/services/state
  tests — **awaiting Tyr walkthrough, no PR yet**). Shipped: corner artifacts ×3 (project
  card, Loop/Snap splits — metronome pattern), hover-divider crossfade exit, Open/Settings
  rest borders, piano-roll toolbar 4px radius + full-height dividers + control heights,
  EQ per-band ⏻ CUT (design-recs §4: delete+undo covers it), editor-tab hover +
  MIDI/Piano-Roll label unify, shortcuts-overlay ghosts + full piano-key map, `Icons.*`→BI
  (6 widgets, +radioUnchecked/upload/count* facade entries), vertical note zoom WIRED
  (8–40px, centre-anchored), `shouldRepaint` trackColor, drag-end double engine reschedule
  removed, automation Duplicate-at-click + resize-moved-into-pan-handlers (occlusion),
  dead `_loadTrackVolume` regex deleted, library left-column width persisted
  (`library_left_width` via ProjectPersistence), voice-steal quietest-tail. Decisions:
  exclusive arm ALL track types (+ disarm on every create path; dead
  `onTrackCreatedFromMixer` mixin duplicate deleted), mixer+Master border unified 2px,
  count-in mute (engine `count_in_in_place` flag → renderer mutes tracks during CountingIn,
  metronome stays). REFUTED on re-verify: stem-render limiter restore (never set — stems
  skip master bus). Deferred: automation box-select/Delete (future automation batch),
  playhead-grabber early-hide (marginal).
- [ ] **Dogfood round 2** (Tyr): includes wordmark-baseline look at 1×/2×, plus the still-owed
  macOS Sparkle spot-check.
- [ ] **Tag decision** → if go: v0.6.0 release flow (Version Sync checklist + Windows smoke
  test before publishing the draft).

**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
