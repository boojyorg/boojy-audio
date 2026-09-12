# Boojy Audio — Feature-Gap Review

**Date:** 2026-06-01
**Version under review:** v0.4.0 (Visual & UX Polish — unreleased, not yet tagged)
**Scope:** feature-coverage audit only — *what a beginner expects from a GarageBand-class DAW that Boojy does not yet deliver.* This review deliberately does **not** cover correctness bugs (see `2026_06_01_codebase_review.md`) or visual/UX polish (see `2026_06_01_ui_ux_review.md`). A "gap" here is a missing or unreachable *capability*, not a defect in an existing one.
**Lens:** beginner-first throughout. Boojy targets beginners and hobbyists on the GarageBand model — "sit down with an idea, hear it in 30 seconds, finish a song without reading a manual." A missing *pro* feature is usually correctly out-of-scope, not a gap.
**Extends:** `docs/FEATURE_TRACKER.md` (the canonical feature checklist) and `docs/ROADMAP.md` (tiering). Where the tracker and the code disagree, the code wins and the tracker is flagged as drift.

**How this review was produced:** parallel agents surveyed `FEATURE_TRACKER.md`, `ROADMAP.md`, and the `docs/plans/` specs for *claimed-vs-actual* status, cross-checked every claim against the real Rust/Dart source, and ran four beginner-DAW teardowns (GarageBand, BandLab, Soundtrap, FL Studio) asking "what does a first-time user expect here that Boojy lacks?" Each candidate gap was then classified — **v1.0-blocking | nice-to-have | out-of-scope-for-beginners** — and the blockers ranked by *beginner-impact ÷ effort*. The recommended next theme is reconciled against the two sibling reviews' proposals at the end.

---

## 1. Executive summary — can a beginner make a full song end-to-end?

**Mostly yes for audio, no for "from-scratch" music — and the gap is one thing: sound.** A beginner who arrives with a microphone and a song idea can record audio with count-in, arrange it on a timeline, mix it through a real send/return system, add EQ/compression/reverb, and export a WAV or MP3. That loop is genuinely complete and is the surprising strength of a v0.4 product. The recording fundamentals, piano roll, mixer, effects chain, undo/redo, and export are at or near GarageBand parity.

**But the GarageBand model is "open the app and make music with nothing but the app," and Boojy fails that test at the first step.** A beginner who opens Boojy with no microphone, no MIDI controller, and no VST3 plugins — i.e. the *typical* first-time user — adds a MIDI track and **hears nothing**. There are no stock instruments (the engine has a working synth and sampler in Rust, but zero playable presets are exposed), no drum kit, no step sequencer, and an empty Sounds/Samples library. The one escape hatch — loading a VST3 instrument — is broken on project reload (every plugin reopens as a silent effect; codebase-review C32). So the most fundamental beginner workflow, *"make a beat, save it, come back tomorrow,"* does not survive a round trip.

Three other beginner-essential capabilities are **built but unreachable**: automation (fade-outs) is fully implemented but hidden behind a feature flag; swing has a slider that drives no engine; and ghost notes have a toggle that feeds on nothing. These are "broken promises" — a beginner sees the control, uses it, and nothing happens, which is worse for confidence than the feature simply being absent.

**Bottom line:** Boojy is roughly **two feature cycles** away from "a beginner can make a full song end-to-end from a blank project." The single highest-leverage cycle is *Sound* — ship stock instruments + a drum sequencer + a starter sample library and fix the VST3-reload identity bug. The other reviews are right that this should *not* be the very next cycle (see §6).

---

## 2. v1.0-BLOCKING gap list

Each gap below genuinely stops a beginner from finishing a song from a blank project. Effort is XL > L > M > S. Where the engine already has the capability and only the UI/plumbing is missing, that is called out — those are the cheap wins.

### B-1 · Stock instruments (synth presets, drum kit, sampler, preset player) — **XL**
**A beginner with no plugins hears silence on a new MIDI track.** This is the single most disqualifying gap versus every reference DAW. The Rust engine *has* a functional 1-oscillator, 8-voice ADSR synth (`engine/src/synth.rs`) and a pitch-shifting sampler (`engine/src/sampler.rs`), and the library lists "Piano / Synthesizer / Drums / Sampler" as draggable items — but dragging any of them yields an empty parameter panel, not a sound. All five Stock-Instrument rows in `FEATURE_TRACKER.md` (basic synth, Boojy Synth, Boojy Sampler, Boojy Drums, preset player) are unchecked, and no `boojy_synth`/`boojy_drums`/`preset_player` files exist. There are **no factory patches** — `instrument_data.dart` has no preset list, and the synth panel has no preset concept.
**Evidence:** `FEATURE_TRACKER.md` lines 221–226; `synth.rs`, `sampler.rs` present but preset-less; `library_service.dart` instrument entries resolve to bare engines.
**Note:** the *engine* exists, so this is "ship presets + drum kit content + a preset browser," not "build a synth from scratch." That is why it is XL, not unbounded.

### B-2 · VST3 instrument identity lost on project reload — **S**
**Save a project with a VST3 piano, reopen tomorrow, and it is silent.** `engine/vst3_host/vst3_host.cpp:645` hardcodes `info->is_effect = true; info->is_instrument = false;` with a TODO — every plugin loaded from a saved project path is treated as an effect, so MIDI routed to it produces nothing (codebase-review C32). This breaks the most basic creative workflow there is: *save and return.* It is also the only beginner escape hatch from B-1 until stock instruments land, so it is doubly load-bearing.
**Evidence:** `vst3_host.cpp:645`; codebase-review 2026-06-01 C32.
**Note:** small, surgical fix (persist/restore the instrument flag) — best done *with* the correctness cycle, since it is a lifecycle bug as much as a feature gap.

### B-3 · Automation lanes (volume/pan) hidden behind a feature flag — **M**
**A beginner cannot draw a fade-out — the most common "first mixing trick."** The backend is *complete*: `AutomationController`, volume/pan lanes, linear interpolation, painters, and full project serialization all exist and preserve data. But `ui/lib/constants/ui_constants.dart:14` sets `enableAutomation = false`, and every automation widget across the mixer strip, track list, and timeline is gated on that flag. GarageBand, BandLab, and Soundtrap all expose fade-out trivially on day one. With the flag off, Boojy presents as having no automation at all.
**Evidence:** `ui_constants.dart:14`; `FEATURE_TRACKER.md` lines 110–113 ("backend complete; UI hidden behind flag in v0.2.2, data preserved").
**Note:** effort is M not S because flipping the flag exposes UI that hasn't had a quality pass — draw/select/delete-in-lane needs verification and an integration smoke test before it ships to beginners.

### B-4 · No stock drum kit + step sequencer — **L**
**Making a beat is the canonical beginner entry point, and Boojy has no on-ramp for it.** The only path to drums today is clicking notes into the piano roll — intimidating and slow for a first-timer. GarageBand's Beat Sequencer and BandLab's Beat Maker exist precisely because a 16-step grid is how beginners make a drum pattern in 30 seconds. No `StepSequencer`/`DrumPad`/`step_seq` code exists anywhere; `ROADMAP.md` explicitly defers it.
**Evidence:** `FEATURE_TRACKER.md` lines 74–79 (all unchecked); zero grep hits; `ROADMAP.md` defer note.
**Note:** depends on B-1's drum content to be useful — sequence and ship them together.

### B-5 · Loop recording (multiple takes) + comping / take lanes — **L**
**A beginner recording vocals or guitar will not nail it in one pass.** Without loop recording they must stop, undo, and re-record repeatedly, which breaks creative flow. GarageBand's take lanes are a core beginner feature for exactly this. No take-lane/loop-record/comping logic exists in `engine/src/recorder.rs` or the UI; `ROADMAP.md` lists it as Tier 2 (pre-v1.0).
**Evidence:** `FEATURE_TRACKER.md` lines 47–49; empty greps; `ROADMAP.md` Tier 2.

### B-6 · Beginner-friendly effect presets (named patches per effect) — **M**
**The effects exist but are unusable to a beginner.** EQ, Compressor, Reverb, Delay, Chorus, and Limiter are all implemented with a working chain, bypass, and reorder — but they expose only raw parameter knobs (threshold? Q? room_size?). A beginner does not know what values to set. BandLab/GarageBand ship named patches ("Vocal Plate," "Radio EQ," "Punchy Snare") so effects are instantly useful. A modest 5–7 presets per effect plus a "Reset to Default" turns the existing chain from opaque to professional.
**Evidence:** effects all `[x]` in tracker but no factory presets; `effect_parameter_panel.dart` is bare knobs; `ROADMAP.md` "Not Including" excludes AI mastering but is silent on effect presets.

### B-7 · Light / High-Contrast themes are advertised but render broken — **XL**
**A low-vision user selects "High Contrast" in Settings and gets an unusable UI.** `app_colors.dart` defines all four `BoojyTheme` palettes (dark / highContrastDark / light / highContrastLight), and Settings lets you pick them — but painters hardcode dark-theme hexes (~390 colour tokens un-tokenised; ui-ux-review B-TH4), so a light theme renders dark rulers on a light shell with invisible labels, and `highContrastDark` reuses the normal accent with no contrast boost (B-TH6). Shipping a *broken* accessibility promise is worse than offering none.
**Evidence:** `app_colors.dart` lines 4, 270–313; `dreams.md` §1 line 42; ui-ux-review 2026-06-01 B-TH4/B-TH6.
**Note:** This is the exact work the **ui-ux-review's "Legibility & Trust"** cycle targets. It is XL because of the tokenisation sweep. It overlaps heavily with that review's recommendation — treat it as *theirs*, not a separate effort.

### B-8 · First-launch onboarding / guided tutorial — **M**
**A beginner facing a blank 5-panel DAW with no guidance churns within minutes.** This violates Boojy's own north star ("no manual-reading"). The tour *infrastructure* is built — `TourController`/`TourOverlay` exist and `daw_screen.dart:187` auto-fires a tour on first launch — but it is only a ~5-step tooltip spotlight; the promised "Quick Start + Full Course" content is unbuilt and the steps list is thin/empty depending on path.
**Evidence:** `FEATURE_TRACKER.md` lines 250–251 (both unchecked); `daw_screen.dart:187` auto-trigger present; tour scaffold real but content-light.
**Note:** infrastructure is ~85% there — this is mostly content/copy authoring, not new systems.

### B-9 · Tooltips on all controls — **M**
**A beginner cannot discover what mute/solo/record/FX/send buttons do without leaving the app to google.** 147 `Tooltip` usages already exist (transport, library preview, editor tabs), but coverage is incomplete — many mixer-strip MSR buttons, track-header buttons, send knobs, and piano-roll sidebar controls have none. FL Studio and GarageBand make hover hints load-bearing for discoverability. This is beginner-safety infrastructure, not polish, and it directly serves the "learn without docs" principle.
**Evidence:** `FEATURE_TRACKER.md` "Tooltips on all buttons" unchecked; 147 existing usages but gaps in mixer/track/piano-roll controls.

### B-10 · Export with platform-aware LUFS normalization in the UI — **M**
**A beginner uploading to Spotify/YouTube needs correct loudness, and the capability is built but unreachable.** The engine has `normalize.rs` (`calculate_lufs`, `normalize_lufs`) and `export/options.rs` defines `PlatformTarget` (Spotify −14 LUFS, Apple Music −16, etc.) — but `export_dialog.dart` exposes only a boolean "Normalize" toggle that applies a fixed −0.1 dBFS peak, with no platform selector. The primary "finish and upload a song" use case is blocked despite the engine being ready.
**Evidence:** `normalize.rs`, `export/options.rs` present; `export_dialog.dart` lines ~1272 boolean-only; `FEATURE_TRACKER.md` line 199 unchecked.
**Note:** This is a UI-surfacing job over an existing engine capability, hence M.

### B-11 · Clip-level Normalize (one-click level fix) — **S**
**Recorded clips arrive at wildly different levels, and the one-click fix is missing.** The model (`audio_clip_edit_data.dart:60` `normalizeTargetDb`), the waveform painter, and `parameter_operations.dart:166 setNormalize()` all exist — but `audio_editor_controls_bar.dart` has no Normalize button, and the FFI noted as "Future (v0.3.0)" was never added. A beginner must instead ride a gain knob by ear.
**Evidence:** model + painter + `setNormalize()` present; no button; `parameter_operations.dart:101` "Future: FFI for reverse and normalize."
**Note:** cheapest blocker on this list — mostly one FFI function + one button.

### B-12 · Swing actually changes playback — **L**
**The swing slider produces no audible groove, which confuses the hip-hop/lo-fi beginners who reach for it first.** `piano_roll_sidebar.dart` has a 0–100% slider and Apply button; `note_operations.dart:300 applySwing()` does pure Dart-side offset math on the *currently-open clip's* selected notes only. There is no `swing`/`set_swing` FFI, no global swing, and no live/playback swing. A beginner presses Apply, hears almost nothing, and assumes the feature (or they) are broken.
**Evidence:** sidebar slider + Apply present; `applySwing()` Dart-only; no swing FFI in `engine/src/ffi/`; `FEATURE_TRACKER.md` line 155 global-swing unchecked.

> **Windows platform support** (`FEATURE_TRACKER.md` line 257) is the one true blocker I am *not* numbering above, because it is a distribution decision, not a feature a beginner clicks. It is genuinely v1.0-relevant — the GarageBand-alternative audience is mostly on Windows — but it belongs in release planning, not a feature-gap cycle. Flagging it here so it is not forgotten: **effort M** (CI already runs Windows analyze/test/clippy; the gap is a VST3 build + packaging path).

### Blocker ranking (impact ÷ effort)

| Rank | Gap | Effort | Why it ranks here |
|---|---|---|---|
| 1 | B-2 VST3-reload identity | S | Tiny fix, unblocks save/return + the only escape from B-1 |
| 2 | B-11 Clip Normalize | S | One FFI + one button; daily beginner need |
| 3 | B-3 Automation flag-flip | M | Fully built; fade-out is table stakes |
| 4 | B-10 LUFS in export UI | M | Engine ready; unblocks "upload to Spotify" |
| 5 | B-9 Tooltips coverage | M | Discoverability infra; cheap, high reach |
| 6 | B-8 Onboarding content | M | 85% built; content authoring |
| 7 | B-6 Effect presets | M | Makes the existing chain usable |
| 8 | B-12 Swing→engine | L | Genre-defining for entry users |
| 9 | B-5 Loop recording | L | Core to vocal/guitar iteration |
| 10 | B-4 Drum step sequencer | L | Canonical beat-maker on-ramp |
| 11 | B-1 Stock instruments | XL | The biggest gap, but engine exists |
| 12 | B-7 Theme legibility | XL | Owned by the ui-ux review |

---

## 3. Nice-to-have backlog (ranked by beginner-impact ÷ effort)

These genuinely add value but do **not** stop a beginner from finishing a song. Ranked best-leverage first.

| Rank | Feature | Effort | Beginner value / why deferred |
|---|---|---|---|
| 1 | **Tracker accuracy sweep** (Duplicate clips, Reverse audio, Quantize, Search, Favorites, Tap tempo, auto-tour all marked `[ ]` but **shipped**) | S | Pure metadata drift — *no code needed*. Misleads every future planning pass. Fix `FEATURE_TRACKER.md` lines 70, 91, 104, 155, 176, 179–180 and the tour rows. Highest leverage on this list because it costs an hour and stops re-hunting built features. |
| 2 | **Project / track templates** ("Vocal," "Singer-Songwriter," "Beat") | M | Removes the blank-canvas freeze. Track templates (pre-wired FX) beat genre templates for beginners. Blank projects work today, so deferred. |
| 3 | **Ghost notes plumbing** | M | Toggle + painter exist; `daw_screen.dart` EditorPanel never passes a `ghostNotes:` list (defaults `const []`). Harmonic context across clips is a real beginner aid; beginners can still write by ear, so not a gate. |
| 4 | **File browser inside the library panel** | M | Add-Folder + Finder drag-drop already cover import; an in-app tree is friction relief, not new capability. |
| 5 | **Effects/device overhaul** (universal MIX/wet-dry knob, GR meter, EQ dot-curve) | L | Bypass + per-effect mix exist today; this raises confidence and approachability. Owned by the ui-ux review's later milestone, deliberately deferred post-v0.4. |
| 6 | **Markers / locators on timeline** | M | Helps long songs; a typical 8–16-bar beginner song finishes fine without them. |
| 7 | **Built-in royalty-free loop pack** | L–XL | Accelerates first-use *enormously* but needs curation + licensing + disk, and even 50 loops reads as thin vs GarageBand's thousands. Pairs naturally with B-1's content cycle. |
| 8 | **Plugin delay compensation (PDC)** | L | Beginners avoid heavy VST chains; correctness-critical once plugins are loaded, but the three plugin lifecycle bugs (codebase-review C30/C32/C34) must land first. |
| 9 | **MP3 ID3 metadata tagging** | S | Nice for "title/artist" on export; not blocking. |

---

## 4. Explicitly OUT-OF-SCOPE for v1.0 (do not re-raise)

These surface in DAW teardowns but are pro/platform features orthogonal to "a beginner finishes a song." Recording the rationale here so each is not re-litigated every planning cycle.

- **Social / cloud / one-tap sharing (SoundCloud, AirDrop, Messages, share-link).** This is BandLab's *moat* — community and engagement, not DAW depth. Beginners share via file export + manual upload. Requires auth, accounts, moderation; Tier 3 at the earliest. *Boojy's value is creativity, not a social network.*
- **Plugin delay compensation as a v1.0 gate.** Pro infrastructure; beginners rarely build latency-inducing chains. A warning or auto-compensation serves v1.0 better than the full DSP layer. (Listed as a *nice-to-have* above, but explicitly **not** a blocker.)
- **A large bundled loop library at GarageBand scale.** Only the beat-maker persona benefits directly; vocalists/bands don't need it; any set we ship reads as thin vs 10k+ loops. A *starter* pack pairs with the Sound cycle, but matching GarageBand's catalogue is not a v1.0 goal.
- **Tempo automation, automation shapes (sine/ramp/square), per-arbitrary-parameter automation.** Volume/pan fades cover the beginner need; curve editing is a pro escalation.
- **Search / Favorites as *features to build*.** Both are already implemented (tracker drift). They are also premature to *emphasise* until a stock library exists to organise.
- **Pattern-based workflow as the primary model.** Boojy is arrangement-first by design. A step sequencer is in-scope as a *drum entry tool* (B-4); a full FL-style pattern/playlist paradigm is not.
- **Chord detection, humanize, advanced MIDI transforms.** Piano-roll polish, not capability gates.
- **MIDI hardware as a requirement.** The virtual piano + ASDF keyboard mapping already cover the no-hardware path — this is *done*, not a gap.

---

## 5. How Boojy compares to GarageBand / BandLab / Soundtrap / FL Studio on beginner essentials

Legend: ✅ shipped & usable · 🟡 built but broken/unreachable/preset-less · ❌ absent

| Beginner essential | GarageBand | BandLab | Soundtrap | FL Studio | **Boojy v0.4** |
|---|---|---|---|---|---|
| Audio recording (arm, count-in, monitor, punch) | ✅ | ✅ | ✅ | ✅ | **✅** |
| Virtual piano + computer-keyboard input | ✅ | ✅ | ✅ | ✅ | **✅** |
| Piano roll: draw/edit, scale highlight, quantize | ✅ | ✅ | ✅ | ✅ | **✅** (tracker says ❌ — drift) |
| BPM + metronome + count-in | ✅ | ✅ | ✅ | ✅ | **✅** |
| Tap tempo | ✅ | ✅ | ✅ | ✅ | **✅** (tracker drift) |
| Mixer (vol/pan/mute/solo) + sends/returns | ✅ | ✅ | ✅ | ✅ | **✅** |
| Effects chain (EQ/comp/reverb/delay/chorus/limiter) | ✅ | ✅ | ✅ | ✅ | **✅** chain / 🟡 *no presets* (B-6) |
| Undo/redo | ✅ | ✅ | ✅ | ✅ | **✅** |
| Export WAV/MP3/stems | ✅ | ✅ | ✅ | ✅ | **✅** / 🟡 no LUFS target (B-10) |
| **Stock instruments (synth/piano/drums)** | ✅ | ✅ | ✅ | ✅ | **🟡 engine only, no presets (B-1)** |
| **Step sequencer / drum machine** | ✅ | ✅ | ✅ | ✅ | **❌ (B-4)** |
| **Bundled loops / sounds library** | ✅ | ✅ | ✅ | ✅ | **❌ empty Sounds/Samples** |
| **Basic automation (fade-out)** | ✅ | ✅ | ✅ | ✅ | **🟡 built, flag-hidden (B-3)** |
| **Loop recording / take comping** | ✅ | ✅ | ✅ | partial | **❌ (B-5)** |
| **Swing/groove** | ✅ | ✅ | ✅ | ✅ | **🟡 slider, no audio (B-12)** |
| **First-run onboarding** | ✅ | ✅ | ✅ | ✅ | **🟡 stub tour (B-8)** |
| Tooltips on all controls | ✅ | ✅ | ✅ | ✅ | **🟡 partial (B-9)** |
| VST3 hosting | (AU) | ❌ | ❌ | ✅ | **✅ live / 🟡 silent on reload (B-2)** |
| Social/cloud sharing | partial | ✅ | ✅ | ❌ | **❌ (out of scope)** |

**Read of the table:** Boojy's *editing-and-mixing spine* is at four-DAW parity — genuinely impressive for an alpha. Every red/yellow cell clusters in exactly two themes: **(a) sound to make music *with*** (instruments, drums, loops) and **(b) features that exist but don't reach the user** (automation, swing, themes, tooltips, ghost notes). The first is a content+UI cycle; the second is mostly unblocking work already paid for.

---

## 6. Recommended next theme (the version after v0.4.0) — and the alternative's cost

**The two sibling reviews both argue that correctness and legibility come before new features — and they are right.** This review's findings *strengthen* that conclusion rather than competing with it:

- The **codebase-review (2026-06-01)** proposes **v0.5 = "Trust under a real session"**: VST3 lifecycle protocol violations, DeleteTrack content-loss undo, recorder audio-thread blocking, a round-trip tempo bug, command/undo holes, and — critically — **fixing CI test-suite trustworthiness first** (integration tests skip when the dylib is absent; clippy is non-fatal).
- The **ui-ux-review (2026-06-01)** proposes **v0.5 = "Legibility & Trust"**: make theme tokens load-bearing, painters honour scaling/theming, raise piano-roll readability, add mixer fader affordances/peak-hold, plus effect bypass + MIX knob.

**My recommendation: do NOT make the next cycle a feature cycle. Adopt the correctness/legibility theme — and fold three of this review's items into it because they *are* trust work, not new features.** Specifically:

> **v0.5 — "Trust & Legibility" (correctness-first, with three feature-gap rescues):**
> 1. Everything in the codebase-review (lifecycle, DeleteTrack undo, recorder thread, tempo round-trip, CI gates) — *the foundation.*
> 2. Everything in the ui-ux-review's legibility pass — which **is B-7** (theme tokenisation) in this review. They are the same work; don't schedule it twice.
> 3. **Three cheap feature-gap rescues that are really trust fixes:** **B-2** (VST3-reload identity — a lifecycle bug the codebase-review already touches), **B-3** (flip the automation flag — shipping a built, data-preserving feature), and **B-11** (clip Normalize — one FFI). Plus the **tracker accuracy sweep** (§3 rank 1) so the next plan starts from an honest baseline.

Then make the cycle *after* that — call it **v0.6 "Sound"** — the dedicated feature cycle: **B-1 stock instruments + B-4 drum sequencer + a starter loop pack + B-6 effect presets + B-12 swing**, which together finally deliver "open a blank project and make a beat." That sequencing is deliberate: shipping stock instruments *on top of* the known VST3/recorder/undo defects would mean a beginner's very first from-scratch song lands on the app's shakiest code paths.

**Cost of the alternative (going feature-first now):** if v0.5 chased Sound (B-1/B-4) ahead of the hardening cycle, a beginner's first end-to-end song — the exact moment we are trying to win — would run straight into the silent-VST3-reload bug, the DeleteTrack content-loss undo, and recorder audio-thread blocking. We would be inviting new users onto the most fragile paths *and* validating the new instrument code against a CI suite the codebase-review showed cannot be trusted (skipped integration tests, non-fatal clippy). The likely outcome is a worse first impression than shipping nothing new — a beginner who loses their first beat on reload does not come back. **Hardening first is cheaper than the support/reputation cost of breaking the moment of capture.**

One honest tension to flag: the longer the *flagship* gap (no stock instruments) stays open, the longer Boojy can't demo its core pitch to a beginner from a blank project. That is a real cost of deferring B-1 by one cycle — but it is a *demo/marketing* cost, not a *user-harm* cost, and it is the right trade against shipping instruments onto unverified foundations.
