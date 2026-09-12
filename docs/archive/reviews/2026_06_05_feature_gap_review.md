# Feature-Gap Review — Boojy Audio (toward v1.0)

**Date:** 2026-06-05 · **Baseline:** v0.5.1 (branch `feat/ui-polish-topbar-master-library`) · **Lens:** beginner-first (GarageBand model)
**Scope:** This review answers *"what features are MISSING."* It deliberately does **not** cover bugs (see the correctness audit) or visual polish (see the UI/UX review). Where a "feature" is silently broken because a layer is missing (e.g. a toggle with no engine FFI), it is treated as a *gap*, not a bug.

---

## 1. Executive summary — can a beginner make a full song end-to-end?

**Not yet — and the blocker is sound, not editing.**

Boojy has a genuinely strong DAW spine. The *audio-editing half* is functionally complete for a beginner: multi-track audio + MIDI recording, a linear timeline with snap/loop/zoom, a real piano roll with quantize and velocity, send/return routing, a six-effect chain (EQ, compressor, reverb, delay, chorus, limiter), command-pattern undo/redo, auto-save, and WAV/MP3/stem/MIDI export are all built **and reachable by a user**. VST3 support is unusually mature for a pre-1.0 beginner DAW. Against the reference DAWs, the plumbing is at or near GarageBand parity for *someone who arrives with audio to record*.

The *music-creation half* fails the most basic beginner test: **open the app, add a MIDI track, play the keyboard — and hear nothing.** There are no stock instruments, no factory presets, no bundled loops or samples (the Sounds/Samples library categories are explicit empty stubs), and no drum-pad/step-sequencer UI. The one escape hatch — a VST3 instrument — assumes the beginner already owns and can install plugins, which the target persona does not.

Compounding this, several features *look* finished but stop short of the layer that makes them work, which is worse than absence because it teaches a beginner the app is broken:

- **Automation** — full backend, painters, persistence, tests; hidden behind `enableAutomation = false` (verified in `ui_constants.dart:14`).
- **Reverse audio** — UI toggle present; **no `set_audio_clip_reverse_ffi` exists** (verified: only a read-back field in `synth.rs`, no setter). Playback is unaffected.
- **Clip normalize** — `setNormalize()` and model field exist Dart-side; no engine FFI, no button.
- **Swing** — slider + Apply move selected notes statically; no engine FFI, no playback groove (verified: zero swing hits in `engine/src/ffi/`).
- **Input monitoring** — FFI + Dart binding wired; **no UI control** (verified: no `monitoring` reference in track headers).

**Verdict:** roughly **one full cycle away.** A beginner who arrives with a microphone and patience can *technically* record, arrange, mix, and export a song today. A beginner who opens a blank project expecting to *make* music from nothing — the GarageBand promise — hits a wall in the first 30 seconds. The single highest-leverage move is the **v0.6 "Sound" cycle** (stock instruments + drum UI), with a handful of cheap "finish-the-last-mile" fixes (flag-flip automation, wire the three orphaned FFI/UI bridges) that recover real value for near-zero cost.

---

## 2. v1.0-BLOCKING gap list

Ranked by beginner impact. Effort: **S** ≈ hours · **M** ≈ days · **L** ≈ 1–2 weeks · **XL** ≈ a cycle.

### B-1 · Stock instruments — a new MIDI track is silent · **XL**
**Why a beginner is stuck:** They add a MIDI track, press a key, and hear nothing. Every reference DAW ships playable, named instruments out of the box. This is the single most disqualifying gap against the GarageBand model — without it the core promise ("open it, make a song from nothing") cannot be kept.
**Evidence:** `FEATURE_TRACKER.md` lines 221–226 (all 5 stock-instrument rows unchecked); `ROADMAP.md:22` confirms a new MIDI track is silent; `library_service.dart` lists Piano/Synthesizer/Drums/Sampler as draggable but with **no presets**; `instrument_data.dart` has no preset list; `synthesizer_panel.dart` has no preset concept. The synth (`synth.rs`, 8-voice + ADSR + filter) and sampler engines exist and are reachable, but ship as raw oscillators/empty slots.
**What's needed:** curated factory presets (piano, strings, pads, bass, leads), a preset browser, and bundled instrument content — not new engine work.

### B-2 · Drum kit UI + step sequencer — no way to make a beat without the piano roll · **L** (UI) atop B-1 content
**Why a beginner is stuck:** Tapping a 16-pad/16-step grid is the canonical first-time beat-making move (GarageBand Beat Sequencer, BandLab/Soundtrap Beat Maker). Boojy's only path to drums is the piano roll, which assumes music literacy the target user lacks. Beat-makers are a primary persona.
**Evidence:** **Verified — zero Dart calls to `add_drum_pad_ffi` / `load_drum_pad_sample_ffi` / `create_drum_kit_for_track_ffi`.** The full DrumKit engine (`drum_kit.rs`) and FFI (`engine/src/ffi/synth.rs:405–537`) are implemented; there is no `DrumPad`/`StepSeq` widget anywhere in `ui/lib/`. `FEATURE_TRACKER.md` lines 74–79 all unchecked. The hard part (engine + FFI) is done; only the Flutter grid + Dart bindings + kit content remain.
**Pairing:** ship with B-1 in the v0.6 Sound cycle — pads are worthless without kit samples.

### B-3 · Automation lanes (fade-out) — backend complete, hidden behind a flag · **S**
**Why a beginner is stuck:** Drawing a fade-out at the end of a track is the first "pro move" every beginner tries after recording. The entire backend — `AutomationController`, volume/pan lanes, interpolation, painters, serialization — is built and tested, but **invisible to every user**.
**Evidence:** **Verified** `ui_constants.dart:14` → `enableAutomation = false`; gating confirmed across `timeline_view.dart`, `track_mixer_strip.dart`, `piano_roll.dart`, `timeline_gesture_layer.dart`; `FEATURE_TRACKER.md` lines 110–113 document the flag. Flag unchanged since the 06-01 review.
**What's needed:** flip the flag + a quality pass on the draw/select/delete gestures. The cheapest high-value win in the entire backlog.

### B-4 · Effect presets — six working effects, no named patches · **M**
**Why a beginner is stuck:** A beginner does not know what "threshold −24 dB, ratio 4:1, attack 10 ms" means. The effects chain is built and correct but practically inaccessible — named patches ("Vocal Plate", "Punchy Snare", "Warm Master") are what make it usable for the target audience. Without them the song sounds thin because the effects go untouched.
**Evidence:** all six effects `[x]` in `FEATURE_TRACKER.md`; `effect_parameter_panel.dart` exposes only raw knobs; no preset list in any effect file; `preset_browser_dropdown.dart` exists for **VST3** preset nav only. `ROADMAP.md:22` schedules effect presets in v0.6.

### B-5 · Reverse audio — labelled toggle that does nothing · **S**
**Why a beginner is stuck:** They toggle Reverse, press play, the clip plays forward. A visible control that silently no-ops erodes trust faster than an absent feature.
**Evidence:** **Verified — no `set_audio_clip_reverse_ffi` setter exists** (only a read-back `out_reversed` in `synth.rs:259/305`). `audio_editor_controls_bar.dart:624–630` renders the toggle; `parameter_operations.dart:101` literally comments *"Future: FFI for reverse and normalize."* The engine *processes* `reversed: bool` correctly (`sampler.rs:262`) — only the one-way bridge to set it is missing.

### B-6 · Clip normalize — one-click level fix · **S–M**
**Why a beginner is stuck:** Recorded clips arrive at wildly inconsistent levels. Without one-click normalize, the beginner must ride the fader by ear — a skill they don't have. Dart side (`setNormalize()`, `normalizeTargetDb`) is done; engine FFI + a button are missing.
**Evidence:** `FEATURE_TRACKER.md` line 115 unchecked; `parameter_operations.dart:165` has `setNormalize()`; same `:101` "Future FFI" comment; no normalize FFI in `engine/src/ffi/clips.rs`; no Normalize button in `audio_editor_controls_bar.dart`.

### B-7 · Input monitoring — FFI wired, no UI toggle · **S**
**Why a beginner is stuck:** A singer/guitarist needs to hear themselves through headphones while tracking. With no control, monitoring is frozen at the engine default and the user concludes the mic is broken — a hard blocker on the very first recording session.
**Evidence:** **Verified — no `monitoring` reference in `track_header.dart`/`track_mixer_strip.dart`.** `set_track_input_monitoring_ffi` + Dart binding are wired (`audio_engine_base.dart:717`); `FEATURE_TRACKER.md` line 56 marks it `(partial: no UI control)`. One track-header toggle closes it.

### B-8 · Swing — slider produces no audible groove · **L** (to fix) / **S** (to remove)
**Why a beginner is stuck:** Swing is *the* groove tool for hip-hop and lo-fi — the biggest beat-making entry points. Pressing Apply shifts only static note offsets on selected notes in the current clip; there is no live playback swing. A broken-promise control on a genre-defining feature is worse than no control.
**Evidence:** **Verified — zero swing hits in `engine/src/ffi/`.** `piano_roll_sidebar.dart` has the slider; `note_operations.dart:303–332` does pure Dart-side offset math; `FEATURE_TRACKER.md` line 155 (global swing) unchecked.
**Decision required:** either *remove* the UI for v1.0 (S) or *properly wire* global swing through the engine playback clock (L). Shipping it as-is is the worst option.

### B-9 · Export with platform-aware LUFS normalization · **M**
**Why a beginner is stuck:** A beginner uploading their first song to Spotify needs correct loudness; the platform otherwise re-normalizes or flags it. The engine is fully ready — only the UI selector is missing — so this is a credibility-cheap win.
**Evidence:** `engine/src/export/normalize.rs` has `calculate_lufs` + `normalize_lufs`; `options.rs` defines `PlatformTarget` (Spotify −14, Apple −16, YouTube, Custom); `export_dialog.dart:1270–1273` exposes **only a boolean** "Normalize" toggle, no platform picker; `FEATURE_TRACKER.md` line 199 unchecked.
*(Borderline blocker — see §3; could ship a peak-normalize-only v1.0 and defer the LUFS dropdown to a v1.x mastering pass. Listed here because "share to Spotify" is the beginner's finish line.)*

### B-10 · First-launch onboarding — stub tour, no guided first-song flow · **M**
**Why a beginner is stuck:** A 6-step spotlight that names panels is not onboarding — it never teaches the blank-project workflow ("add a drum beat", "record your voice"). GarageBand/BandLab/Soundtrap make the first song achievable in ~2 minutes via guidance; without it beginners churn. The `?` shortcut promised in the tour's step 6 isn't even wired (no shortcuts overlay exists). Directly violates Boojy's "learn without docs" north star.
**Evidence:** `daw_screen.dart:3163–3204` `_startTour()` with 5–6 panel-name steps; `TourController`/`TourOverlay`/`TourScrimPainter`/`TourStep` exist; `FEATURE_TRACKER.md` lines 250–251 (tutorial + first-launch onboarding) both unchecked. Infrastructure ~85% done; this is content + flow authoring.
*(Note: meaningful onboarding is **gated on B-1** — there is no point teaching "make a beat" before drums exist.)*

### B-11 · Windows platform build · **M** (distribution gate, not a feature)
**Why a beginner is stuck:** The GarageBand-alternative audience is majority Windows. With no Windows build, most intended users can't run Boojy at all. CI already runs Windows analyze/test/clippy; the gap is the VST3 build + installer packaging path.
**Evidence:** `FEATURE_TRACKER.md` line 257 unchecked; `ROADMAP.md` Tier 3; CI has no Windows VST3 build or installer step.
*(This is a who-can-use-it gate, distinct from the feature gaps above. It must be resolved by v1.0 but belongs to a release/packaging cycle, not the Sound cycle.)*

---

## 3. Nice-to-have backlog (ranked by beginner-impact ÷ effort)

High ratio first. These are **not** v1.0 gates — a beginner can finish a song without them.

| # | Feature | Effort | Why it's nice, not blocking | Evidence |
|---|---------|--------|------------------------------|----------|
| 1 | **FEATURE_TRACKER accuracy sweep** — tick shipped items (duplicate clips, tap tempo, quantize, library search, favorites, ID3 metadata) | **S** | Costs nothing; every stale "unchecked" misdirects future planning into re-hunting done work and erodes roadmap trust. Pure metadata. | `2026_06_01_feature_gap_review.md §3`; `tempo_controls.dart:50`, `library_panel.dart:78/182`, `export_dialog.dart:277–304` + `metadata.rs` all shipped yet unchecked |
| 2 | **Duplicate clip (audio) — wire Cmd+D** | **S** | MIDI Cmd+D works; audio silently no-ops, reading as a glitch. Alt-drag/context-menu already duplicate audio, so it's a consistency refinement. ~5-min fix. | `daw_screen.dart:2256–2263` checks only `currentEditingClip`; `duplicate_audio_clip_ffi` exists (`audio_engine_base.dart:774`) but isn't called from the handler |
| 3 | **Tooltips on M/S/R + key controls** | **S** | Beginners can't discover Mute/Solo/Arm without leaving the app; standard discoverability affordance. Not a song-completion gate. | `track_mixer_strip.dart` `_buildControlButton` wraps `MouseRegion` only; `2026_06_05_ui_ux_review.md H8`; ~149 tooltips elsewhere so coverage is partial |
| 4 | **CC lane in piano roll — wire the toggle** | **M** | Widget fully built; no button ever sets `ccLaneExpanded = true`. Intermediate MIDI expression (pitch bend, mod) — beginners finish on velocity alone. Afternoon to mirror the velocity-lane button. | `piano_roll_state.dart:222`; zero `ccLaneExpanded = true` hits; `2026_06_05_ui_ux_review.md M7` |
| 5 | **Ghost notes — pass the data** | **M** | Painter + toggle + prop chain built (`note_painter.dart:63–99`, 30% opacity); `daw_screen.dart` never passes a non-empty `ghostNotes:` list. Harmonic context speeds writing but isn't required. Visible-but-inert toggle is a minor confidence hit. | `piano_roll_state.dart:356`; `ghostNotes:` only appears as passthrough; `daw_screen.dart:~4218` omits the arg |
| 6 | **Export LUFS platform dropdown** | **S** | If B-9 ships only peak-normalize, the platform selector becomes nice-to-have mastering polish. Engine-ready. | `options.rs:73 PlatformTarget`; `export_dialog.dart:1270–1273` boolean-only |
| 7 | **Loop recording + take comping** | **L** | Real value for vocal/guitar iteration, but a beginner can finish via stop-undo-rerecord. Comping UI can be a minimal retake modal for v1.0; full take lanes are post-1.0. | `FEATURE_TRACKER.md` 47–49 unchecked; no `loop_record`/`take_lane` in `recorder.rs`; `ROADMAP.md` Tier 2 |
| 8 | **Bundled loop/sample library** | **L** | Accelerates beat-maker first-use hugely, but stock instruments (B-1) already unlock any genre. A *thin* pack vs GarageBand's thousands erodes credibility more than shipping none. Content + licensing, not code. | `library_service.dart:265/276` empty stubs; no audio in `ui/assets/` (verified) |
| 9 | **Project templates / New-project wizard** | **M** | Reduces blank-canvas freeze, but blanks succeed today and real value comes *after* B-1. Pure UX friction relief. | `FEATURE_TRACKER.md` "Project templates" unchecked; `start_screen_modal.dart` creates an empty project |

---

## 4. OUT-OF-SCOPE for v1.0 (deliberately NOT chasing — do not re-raise)

These are pro/engagement features outside the beginner-first, GarageBand-model north star. They are intentional non-goals, not oversights.

- **Pattern-based (clip/loop) composition workflow (FL-style).** Boojy deliberately adopts GarageBand's *linear arranger* (documented in `ROADMAP` "Not Including"). Pattern-first is a pro beat-maker convention; copy/paste + multitrack recording cover v1.0 composition needs.
- **One-tap social/cloud share (link, SoundCloud, direct upload).** Export-to-file fully covers "finish and share a song." Social/cloud is BandLab's engagement moat, not a DAW capability — Boojy's north star is creativity, not a social graph. Tier 3.
- **Light / High-Contrast themes.** v1.0 is a dark-mode beginner DAW. Accessibility themes wait until the hardcoded-colour tokenisation sweep lands; shipping a *broken* theme signals "we don't test accessibility," which is worse than none.
- **Deep mixing/mastering suite (LUFS metering, multiband, mid/side, reference loudness analysis).** Beyond the single platform-target export (B-9). The beginner finish line is "a good-enough export," not a mastering chain.
- **Bundled sample/loop *library* as a v1.0 gate.** A beginner can make a full song via recorded audio, MIDI instruments, or imported samples. Loops are friction relief for beat-makers, correctly paired with the v0.6 Sound cycle — not a capability blocker.
- *(Already shipped, listed so they're not re-hunted as gaps: piano-roll quantize, deep undo/redo, save/load + auto-save, MP3/WAV/stem export. All `[x]` and user-reachable — the FEATURE_TRACKER drift in §3 is the only reason these read as "missing.")*

---

## 5. Beginner-essentials scorecard vs reference DAWs

✅ done & reachable · ◑ built but blocked/hidden/no-UI · ⚪ absent

| Beginner essential | GarageBand | BandLab | Soundtrap | FL (beginner) | **Boojy v0.5.1** |
|---|:--:|:--:|:--:|:--:|:--:|
| Multi-track audio + MIDI recording | ✅ | ✅ | ✅ | ✅ | **✅** |
| Piano roll (draw notes, quantize, velocity) | ✅ | ✅ | ✅ | ✅ | **✅** |
| **Playable stock instruments (no setup)** | ✅ | ✅ | ✅ | ✅ | **⚪ B-1** |
| **Drum pad / step sequencer** | ✅ | ✅ | ✅ | ✅ | **◑ B-2** (engine only) |
| **Bundled loops / samples** | ✅ | ✅ | ✅ | ✅ | **⚪** (empty stubs) |
| Built-in effects (EQ/comp/reverb/delay) | ✅ | ✅ | ✅ | ✅ | **✅** |
| **Effect presets (named patches)** | ✅ | ✅ | ✅ | ✅ | **⚪ B-4** (raw knobs) |
| **Volume/pan automation (fade-out)** | ✅ | ✅ | ✅ | ✅ | **◑ B-3** (flag off) |
| **Input monitoring (hear yourself)** | ✅ | ✅ | ✅ | ✅ | **◑ B-7** (no UI) |
| Loop recording / comping | ✅ | ⚪ | ✅ | ✅ | **⚪** (Tier 2) |
| Undo/redo (deep) | ✅ | ✅ | ✅ | ✅ | **✅** |
| Save/load + auto-save | ✅ | ✅ | ✅ | ✅ | **✅** |
| Export MP3/WAV | ✅ | ✅ | ✅ | ✅ | **✅** |
| **Export LUFS / platform target** | ✅ | ✅ | ✅ | ◑ | **◑ B-9** (engine only) |
| **Guided first-launch onboarding** | ✅ | ✅ | ✅ | ✅ | **◑ B-10** (stub tour) |
| Tooltips on controls | ✅ | ✅ | ✅ | ✅ | **◑** (partial) |
| VST3 plugin hosting | ✅ (AU) | ⚪ | ⚪ | ✅ | **✅** (mature) |
| One-tap social/cloud share | ✅ | ✅ | ✅ | ◑ | **⚪** (out of scope) |

**Read:** Boojy *meets or beats* the references on the editing/mixing/export spine — and exceeds the browser-based DAWs on VST3 hosting. It trails on the **"instant gratification" surface** every reference DAW uses to hook beginners: ready sounds, ready beats, ready loops, visible automation, and a real first-song tutorial. Every ⚪/◑ in the "make sound" rows is a v0.6-Sound-cycle item; the spine is already green.

---

## 6. Recommended next theme (the version after v0.4.0)

> **Note on baseline:** the brief frames this as "the version after v0.4.0," but the working tree is already at **v0.5.1** with v0.6 "Sound" scaffolded (DrumKit engine + FFI merged in PR #44). I'm reading the question as *"what theme should the next substantive cycle carry,"* and grounding the recommendation in the live state. If the intent was literally the slot after v0.4.0, that slot is the already-shipped v0.5 "Trust & Legibility" hardening — which was the correct call and is done.

### Recommended: **v0.6 "Sound" — make a new project make sound**

**The thesis:** Boojy's spine is done; its *voice* is missing. This cycle resolves the single most disqualifying gap (a silent MIDI track) and the cluster of broken-promise controls around it, in the order a beginner discovers them.

**Ships this cycle (In):**
- **B-1 stock instruments** + a preset browser (piano, strings, pads, bass, leads) — the headline.
- **B-2 drum kit UI + 16-step sequencer**, wiring the already-built DrumKit FFI, paired with bundled kit content.
- **B-3 automation** — flip `enableAutomation` + gesture QA (S-effort rescue, ride along).
- **B-4 effect presets** — named patches that unlock the existing FX chain.
- **The three orphaned bridges (B-5 reverse, B-6 normalize, B-7 input monitoring)** — cheap S-effort fixes that each turn a broken-looking control into a working one.
- **B-8 swing decision** — either wire it through the engine clock or pull the UI; do not ship it broken.

**Deferred (Out):** loop recording/comping (Tier 2 — beginners survive on stop-rerecord), bundled *loop* library (pairs with content licensing, ship a starter pack later), B-10 onboarding content (gated on B-1 existing first — teach "make a beat" only once beats exist), B-11 Windows build (a separate packaging cycle), B-9 LUFS dropdown (peak-normalize is enough for v1.0).

**Why this over the alternative:**

**The alternative — "Trust & Polish" / a second correctness pass first** (chase the broken-promise toggles, tooltips, tracker drift, and remaining bugs before adding any sound). Its cost: it's the *cheaper, safer* cycle — mostly S-effort, low risk — but it leaves the **defining beginner failure untouched.** A first-time user who opens Boojy still hits silence on a blank project regardless of how polished the editor is. You'd ship a beautifully-finished tool that beginners can't make music with, and you'd have spent a cycle treating symptoms (a reverse toggle that no-ops) while the disease (no sounds) remains. The correctness theme was the *right* call for v0.5 and is now banked — doing it again before adding sound optimises the half of the app that already works.

**The honest tension:** the Sound cycle is **XL+L heavy** (B-1 + B-2 are the bulk), the riskiest and longest of any theme on the table, and it lands new code on instrument-creation paths. The mitigation is that v0.5 already hardened the foundation those paths sit on (that was the whole point of sequencing hardening first), and the *cheap* B-3/B-5/B-6/B-7 fixes can be batched into the same cycle as low-risk confidence wins while the instrument work proceeds. **Net: Sound is the only theme that moves Boojy from "a DAW you can edit in" to "a DAW a beginner can make a song in" — which is the v1.0 bar. Take it.**

---

### Key files referenced (absolute paths)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/ui/lib/constants/ui_constants.dart` (line 14 — `enableAutomation = false`)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/engine/src/ffi/synth.rs` (lines 405–537 — drum FFI built; 259/305 — reverse read-back only, no setter)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/engine/src/drum_kit.rs` (engine done, zero Dart callers)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/ui/lib/services/library_service.dart` (lines 265/276 — empty Sounds/Samples)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/ui/lib/widgets/piano_roll/operations/note_operations.dart` (lines 303–332 — Dart-only swing)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/ui/lib/services/parameter_operations.dart` (line 101 — "Future: FFI for reverse and normalize")
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/engine/src/export/options.rs` (line 73 — `PlatformTarget`)
- `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/docs/FEATURE_TRACKER.md` (stock instruments 221–226; step seq 74–79; drift items per §3)

Suggested save location: `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio/docs/reviews/2026_06_05_feature_gap_review.md`