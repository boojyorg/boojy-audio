# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** v0.5.2 — **"Correct on real hardware, right after undo."** Correctness-only cycle set
by the 2026-06-05 review chain (`docs/reviews/triage_2026_06_05.md`); no features, no visible UI.
Spec: `docs/archive/plans/v0.5.2-plan.md` (each phase = one small PR, gates green between). Bug IDs (C…)
refer to `docs/reviews/codebase_review_2026_06_05.md`.

**Status (2026-06-06):** plan opened. v0.5.1 published; drum-kit PRs #44/#45 merged (v0.6 paused
behind this cycle).

### Milestones
- [x] **P1 — Criticals:** C32 stopped-path lock-order deadlock; C46/C63 clip-move undo never syncs
  engine start time; cherry-pick sampler blank-panel fix `6df5ac6`.
- [x] **P2 — Honest saves, faithful reloads:** C55 save reports success on `Error:`; C61
  save-as-copy path leak (real live instance was the auto-save backup repoint); C65 held notes
  dropped on save; C66 audio clips dropped on reload (root cause: clips_map keyed by saved ids vs
  fresh timeline ids — now re-keyed on load + honest save/load errors).
- [x] **P3 — No stuck notes, no clicks:** C38 PianoRoll dispose NoteOff; C41 chord-preview after
  dispose (fix = capture engine + track pending notes, flush on dispose — a bare `mounted` check
  would have made the leak worse); C7 synth release anchor (`release_start_level`, sampler
  pattern); C10 voice-steal ramp (stolen voice → 5ms fade-out tail, synth + sampler; steal
  prefers already-releasing voices).
- [x] **P4 — Export tells the truth:** C16 LUFS dead code (now applied pre-mixdown, supersedes
  peak-normalize); C18 export range ignored (sliced post-render so FX are warmed up; empty range =
  hard error); C68 stem gain-stage order ≠ mix (stems now fader/pan *after* FX, same as
  `render_offline`). Note: UI doesn't expose range/platform-target yet — engine-side truth only.
- [x] **P5 — FFI hardening:** C33 null-guard `CStr::from_ptr` (shared `cstr_arg` helper, all ~40
  sites across `ffi/`, not just the review's 5 — null-is-valid semantics preserved at 2 sites);
  C34 track-name comma injection (name percent-encoded at all 3 CSV emitters incl. sends/returns,
  decoded once in Dart via `decodeCsvField`).
- [x] **P6 — Gates + release hygiene:** C76/C77 hook = CI (`--all-targets -- -D warnings`,
  `--fatal-infos`); C78/C79 both lockfiles committed + .gitignore comments say WHY; appcast
  edSignature double-wrap fixed at the source (extract bare base64 from `sign_update` output,
  hard-fail if extraction comes up empty) — first correctly-signed feed = next tagged release.
- [x] **P7 — Engine test net, first slice (C69):** 12 tests in `engine/src/api/tests.rs` against
  the real global-singleton API: save/load round-trip (multi-clip C66, held notes C65, honest
  errors C55), clip-move execute→undo→redo (C46/C63), export smoke (range C18, LUFS C16,
  stem-vs-mix C68). Found+fixed a real bug: offline renders reused live FX state (compressor
  envelopes/delay/reverb tails bled into exports) — built-in FX now reset per offline render.
- [x] **P8 — Real hardware** *(code complete in 3 PRs: #56 DSP sweep, #57 VST3, #58 device
  robustness)*: sample-rate sweep C2/C9/C4/C6/C11/C22 (Delay/Chorus/Reverb working
  `set_sample_rate` + buffer resize; synth filter anchored at 48 kHz; recorder resamples takes to
  engine rate; monitoring ramp; offline renders pin built-in FX to 48 kHz + restore); C26 VST3
  reinit on rate change + C21/C62 block size honours buffer preset; metronome loop-wrap flam
  (refractory guard + monotonic click clock); MIDI hot-plug reconnect-by-name; C99 stream death →
  transport stops + banner (`get_audio_stream_error` FFI, take-semantics). C104 verified
  already-covered app-level (user_settings + startup apply) — project.json would be the wrong
  home. **Hardware pass (2026-06-06):** loop-wrap metronome, MIDI replug, interface yank —
  ✅ passed by Tyr. 44.1 kHz delay/recording + VST3 rate switch — **deferred to the v0.6
  dogfood** (no in-app rate switch; needs Audio MIDI Setup fiddling — engine-level tests cover
  the rate math). Sample-rate selector added to `docs/BACKLOG.md`.
- [ ] **Tag v0.5.2:** AFTER the hardware pass — version-sync (CHANGELOG, ROADMAP, README, **bump
  `ui/pubspec.yaml`**), archive the plan, tag.

**If-time (explicit call, don't pull in silently):** C45/C47/C48/C49/C52/C54 (adjacent undo
holes), C17 quantize, C40/C71 non-4/4, C81/C83/C87 release Lows. **Out:** UI ledger + mockups →
v0.6; C37/C50 → v0.6 Join rewrite; VST3 fidelity (C27–C30) → its own later cycle.

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
