# Feature-Gap Review — Boojy Audio (v0.6.0 → v1.0)

*Beginner-first lens. Complements the correctness audit and UI/UX review — this report covers only **missing features**, not bugs or visual polish.*

---

## 1. Executive Summary — Can a beginner make a full song end-to-end?

**Almost — the editing-and-mixing spine is real, but the "instant sound" surface is missing.** A beginner who arrives **with a microphone or a MIDI controller** can already record, arrange in the timeline, edit MIDI in a real piano roll (velocity, quantize, scale highlighting), program a beat on Boojy Drums, run a six-effect chain with send/return routing, undo deeply, and export to WAV/MP3/stems. That is a credible GarageBand-class spine, and v0.6.0 closed several formerly-broken promises (volume automation is live, reverse audio is wired, input monitoring has a UI toggle, Windows builds ship).

**But the core promise — "open a blank project and make a song from nothing" — still cannot be kept.** The moment a beginner adds a MIDI track, they hear a raw saw-wave oscillator with no named patch. The Sounds library is an explicit empty stub (`_buildSoundsCategory()` returns `items: []`). There is no piano, no strings, no pad — only three blank engines (Synthesizer, Sampler, Drum Kit). There is no guided first-launch flow (the tour auto-start was deliberately removed as "not good enough yet"). So the persona Boojy most wants — the absolute beginner with no gear and no theory — opens the app and faces silence.

**The honest verdict:** Boojy is roughly **one focused content-and-onboarding cycle** away from a credible beginner-first v1.0. The hard remaining work is not architecture (the engines exist) — it is **content**: factory presets, effect patches, and a guided "make your first song" flow. The spine is built; the welcome mat is not.

---

## 2. v1.0-Blocking Gaps

These are gaps that stop a beginner from completing their first song *or* break a visible promise badly enough to erode trust at launch. Ordered by severity.

### B1 — Stock instruments / named presets (Piano, Strings, Pads, Bass, Leads) — **Effort: L–XL**
**Why a beginner is stuck:** They add a MIDI track, press a key, and hear an unpatched oscillator. Beginners don't know synthesis — they expect to *choose a named sound* ("Grand Piano", "Warm Pad") and play immediately. Every reference DAW ships this. Without it, the "open the app and make music from nothing" promise is undeliverable.
**Evidence:** `library_service.dart:323–331` `_buildSoundsCategory()` returns `items:[]` ("empty - not yet implemented"); `instrument_browser.dart:22–43` lists only blank engines; `synthesizer_panel.dart` has zero preset concept; `EditorPanel` hard-codes `_shouldShowPresetNav => false` for the stock synth; FEATURE_TRACKER lines 230–235 all unchecked; v0.6-plan line 65 explicitly deferred (B-1).
**Note on effort:** XL if bundled sampled instruments (real piano/string multisamples) are in scope; **L if kept thin** — a handful of synth presets (Piano-ish, Strings, Bass, Pad, Lead) authored on the existing 1-osc engine + the already-built (but disabled) preset browser. Recommend shipping thin first.

### B2 — Effect presets (named patches: "Vocal Plate", "Punchy Snare") — **Effort: M**
**Why a beginner is stuck:** A beginner does not know what *threshold −24 dB* or *attack 10 ms* means. The six effects work but open to raw knobs, so the mixing phase goes untouched and the song sounds thin. Named patches are what make the effects chain *usable* for this audience — GarageBand/BandLab/Soundtrap all ship them.
**Evidence:** `effect_parameter_panel.dart` has 0 hits for "preset"; `preset_browser_dropdown.dart` is VST3-only; no `EffectPreset` class anywhere in `ui/lib/`; all six effects expose raw knobs only; v0.6-plan line 65 deferred (B-4).

### B3 — First-launch onboarding / guided "make your first song" flow — **Effort: M**
**Why a beginner is stuck:** GarageBand/BandLab/Soundtrap make the first song achievable in ~2 minutes via guidance. A blank 5-panel DAW with no onboarding causes immediate churn — beginners drop DAWs when they open a blank project and don't know where to click. This directly violates the "learn without docs" north star.
**Evidence:** `daw_screen.dart:228` "First-run tour auto-start removed for now (current tour isn't good enough yet)"; tour is Help-menu-only with 5 panel-name spotlight steps; no "add a drum beat / record your voice / export" flow; FEATURE_TRACKER lines 250–251 unchecked.
**Note:** Infra is ~85% done (`TourController`/`TourOverlay` are real). The gap is *content authoring + auto-start trigger*, and it is correctly **sequenced after B1** — onboarding that ends on a silent MIDI track teaches the wrong lesson.

### B4 — Capture MIDI (retroactive record) — backend built, reachable from no UI — **Effort: S**
**Why a beginner is stuck:** "You played it, it's saved" is the most beginner-natural feature — improvise without thinking about the record button. The entire backend (`midi_capture_buffer.dart`), dialog (`capture_midi_dialog.dart`), and mixin method (`daw_clip_mixin.dart:703 captureMidi()`) are production-ready, but **no button, menu item, or shortcut wires to it** (zero hits in `daw_screen.dart`/`transport_bar.dart`/`daw_menu_bar.dart`).
**Evidence:** as above; FEATURE_TRACKER line 65 unchecked.
**Note:** This is the highest-leverage item on the list — a near-finished flagship feature blocked by a ~5-minute wiring task. Do it regardless of theme.

### B5 — Loop recording / take comping — **Effort: L**
**Why a beginner is stuck:** A beginner recording vocals or guitar rarely nails a take in one pass. Without loop recording they must stop → undo → re-record repeatedly, breaking creative flow. GarageBand's take lanes are a core beginner feature for exactly this scenario (singers, home bands).
**Evidence:** FEATURE_TRACKER lines 47–49 unchecked; no `loop_record`/`take_lane`/comping logic in `recorder.rs` or any widget; ROADMAP Tier 2 (pre-v1.0).

### B6 — Audio clip duplicate via Cmd+D — MIDI-only, silently no-ops on audio — **Effort: S**
**Why a beginner is stuck:** Duplicating a drum loop across the timeline is the *first arrangement move* a beginner makes. Cmd+D works on MIDI but silently fails on audio — which reads as a glitch and erodes trust *more* than an absent feature would.
**Evidence:** `daw_screen.dart:2170–2177` `_duplicateSelectedClip()` only routes MIDI; `DuplicateAudioClipCommand` + `duplicate_audio_clip_ffi` already exist — only the selector needs to check audio-track selection. FEATURE_TRACKER line 100.

### B7 — Clip normalize — engine ready, no FFI setter, no button — **Effort: S**
**Why a beginner is stuck:** Recorded clips arrive at wildly inconsistent levels. Without one-click normalize, a beginner must ride the fader by ear — a skill they don't have. `normalize.rs` (`calculate_lufs` + `normalize_lufs`) and the Dart `setNormalize()` field both exist; only the FFI bridge + a button in the audio editor are missing.
**Evidence:** `parameter_operations.dart:108` "Future: FFI for normalize"; no `set_audio_clip_normalize_ffi` in `engine/src/ffi/`; no "Normalize" in `audio_editor_controls_bar.dart`; v0.6-plan deferred to v1.0 (Tyr, 2026-06-08); FEATURE_TRACKER line 115.

### B8 — Pan automation — engine-less, hidden from the parameter picker — **Effort: M**
**Why a beginner is stuck:** Beginner tutorials routinely show pan sweeps. Volume automation is live, but pan is *silently absent* from the picker — a visible inconsistency with the rest of the automation layer.
**Evidence:** `track_automation_data.dart:24` `engineBacked = [volume]` (pan explicitly excluded); `track_mixer_strip.dart:523` iterates `engineBacked` only, so Pan never appears; FEATURE_TRACKER line 119 (honest "partial").

### B9 — Swing — slider applies static note offsets, no playback groove — **Effort: L (wire) or S (remove)**
**Why a beginner is stuck:** Swing is *the* defining groove tool for hip-hop and lo-fi — the two biggest beginner entry points. Pressing Apply nudges static note positions, but the playback clock has no groove. A named control that changes nothing at playback is a confidence-eroding broken promise.
**Evidence:** `note_operations.dart:302–332` `applySwing()` is pure Dart-side offset math on selected notes; zero `swing`/`set_swing` in `engine/src/ffi/`; FEATURE_TRACKER line 165 (global swing) unchecked.
**Decision needed:** either wire the engine groove (L) or remove the UI until then (S). The current visible-but-inert state is the worst option.

### B10 — MIDI hot-plug — device selection by index goes stale — **Effort: M**
**Why a beginner is stuck:** A beginner who plugs in a MIDI keyboard mid-session finds it doesn't respond even after selecting it in Settings — with no error. `selectMidiInputDevice(int deviceIndex)` is index-based; the index goes stale across port-list rescans.
**Evidence:** `midi_input.rs:166` "Hot-plug: an active capture is bound to the OLD port list"; dogfood notes 2026-06-11 §A1/§F2 (refresh only on refocus/arm, not USB plug-in). Fix direction (poll names every ~2s, select by stable name/id) is documented but unbuilt.

### B11 — Windows in-app updater — silently dead — **Effort: M**
**Why a beginner is stuck:** The GarageBand-alternative audience skews majority-Windows. A Windows user who clicks "Check for Updates" gets a silent no-op (no MethodChannel implementation in `ui/windows/runner/`), leaving them on stale builds exactly when a newcomer is deciding whether Boojy is maintained.
**Evidence:** dogfood notes 2026-06-11 §A11/§F1; `ui/windows/runner/` has no updater files; macOS Sparkle flow is fully functional.

> **Two judgment calls flagged for Tyr:**
> - **B5 (loop recording) and B8/B9 (pan automation, swing groove)** are the only *true* engineering-heavy v1.0 blockers here. The rest of this list is small wiring (B4, B6, B7) or content (B1, B2, B3). If v1.0 must ship lean, B5 is the most defensible single deferral — beginners *can* layer punched-in passes as separate clips — but it's a real GarageBand-parity gap, so defer it only deliberately.
> - **Export LUFS platform selector** (engine-ready, UI exposes a boolean toggle only) was raised as v1.0-blocking by one survey and nice-to-have by another. I've placed it in the backlog (§3) — a beginner's first Spotify upload is *playable* without it (Spotify re-normalizes on playback), so it's mastering polish, not a song-completion gate. Pushing back on the "blocking" framing here.

---

## 3. Nice-to-Have Backlog (ranked by beginner-impact ÷ effort)

| # | Feature | Impact | Effort | Why it ranks here (not blocking) |
|---|---------|--------|--------|-----------------------------------|
| 1 | **CC automation lane** — widget built, expand toggle not wired | Med | S–M | Lane fully built; toggle never fires `setState`. Beginners finish via velocity (already wired). Cheap trust-fix. |
| 2 | **Light theme `cycleTheme()` footgun** — iterates all 4 themes incl. broken High-Contrast | Med | S | Settings picker is correct; only the cycle shortcut lands on broken variants. One-line fix (`selectable`, not `.values`). |
| 3 | **Ghost notes** — toggle + painter built, data list never populated | Med | M | Permanently inert toggle. Plumbing to collect sibling-clip notes → `EditorPanel`. Trust hit + harmonic-context aid. |
| 4 | **Export LUFS platform selector** (Spotify −14 / Apple −16 / YouTube) | Med | S–M | Engine ready; only a dropdown. Real value for first uploads, but Spotify re-normalizes anyway → mastering polish. |
| 5 | **Drum kit per-step velocity lane** | Med | M | Groove feel after tutorials; full song ships via piano-roll velocity. Data layer supports it; UI deferred. |
| 6 | **Tooltips on M/S/R/I, faders, FX headers** | Med | M | Beginners hover unlabeled icons. Table-stakes, but discoverable by click today. |
| 7 | **Project templates** ("Beat", "Song", "Podcast") | Med | M | Blank-canvas friction relief — but only *after* B1, else templates open onto silence. |
| 8 | **Built-in drum-machine preset patterns** | Med | M | Pre-loaded patterns build momentum; the manual step grid already closes the "make a beat" capability. |
| 9 | **Tempo-synced library preview** | Low–Med | M–L | Real value, but needs a populated library first (gated on B1/loops). |
| 10 | **Curated loop / Apple-Loops-style library** | High value, but content-only | L–XL | High *speed-of-capture* value; entirely licensing/curation, not code. Stock instruments (B1) unlock every genre first; a thin pack erodes credibility. |
| 11 | **Variable step resolution / choke groups (drums)** | Low | M | Intermediate groove tools; not capability-blocking. |
| 12 | **Plugin delay compensation (PDC)** | Low | L | Power-user, post-sound-creation. Return-chain phase-smear only matters after mastering VST3s. |
| 13 | **Crossfades between clips** | Low | L | v0.6 deliberately *prevents* overlaps; allowing crossfades is a design shift, not a missing primitive. |
| 14 | **Undo history panel** | Low | M | Undo/redo already unlimited + keyboard-mapped; scrollable panel is a power-user affordance (and absent from GarageBand). |

---

## 4. Out-of-Scope (deliberately NOT chasing — do not re-raise)

These are pro/engagement features outside the beginner-first, local-first north star. Several have been re-raised across multiple reviews; logging them here to stop the churn.

- **Social sharing / community / collaboration** — BandLab/Soundtrap's moat, not Boojy's. Tier 3+ deferred across the 2026-06-01 and 2026-06-05 reviews. Boojy's value is *creativity*, not a social graph.
- **Real-time collaboration / cloud project sync** — requires accounts, cloud infra, conflict resolution. Boojy's personas are single-user; v1.0 differentiator is local-first desktop simplicity.
- **One-click export to SoundCloud / share sheet / cloud upload** — local-file MP3/WAV export fully covers v1.0 sharing. Social upload is an engagement layer, not a creation blocker.
- **Automation shapes (sine/ramp/square) + per-parameter automation beyond volume/pan** — pro-editing convenience. Straight-line volume fades + arrangement layering cover the beginner's foundational need.
- **Swing/groove *on the step sequencer* specifically** — (distinct from the global swing engine in B9). Refinement, not a beat-making enabler.

**Already shipped — close as resolved, not as gaps** (these surfaced in teardowns as "missing" but are built):
- **Virtual on-screen MIDI keyboard** — fully shipped v0.6.0 (`VirtualPiano`, ASDF keys, Cmd+P, persisted). Done.
- **Drag-and-drop audio import** — works (`timeline_track_list.dart onDragDone`); the "File browser UI" tracker line is a separate folder-picker nice-to-have, not the drag gesture beginners use.
- **MP3/WAV/stem export + ID3 metadata** — shipped and reachable.
- **Unlimited undo/redo** — shipped (command pattern, 100 steps, keyboard-mapped).
- **Input monitoring, count-in, punch in/out** — shipped v0.6.

---

## 5. Boojy vs. GarageBand / BandLab / Soundtrap / FL Studio (beginner essentials)

| Beginner essential | Boojy v0.6.0 | GarageBand | BandLab | Soundtrap | FL Studio |
|---|---|---|---|---|---|
| Record mic/audio + input monitoring | ✅ (no loop/comping) | ✅ | ✅ | ✅ | ✅ |
| Piano roll (velocity, quantize) | ✅ strong | ✅ | ✅ | ✅ | ✅ |
| Virtual keyboard (no hardware) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Named playable instruments (piano/strings/pads)** | ❌ **blank engines only** | ✅ | ✅ | ✅ | ✅ (3xOSC presets) |
| Step sequencer / beat machine | ✅ Boojy Drums (1 kit, no patterns) | ✅ | ✅ (default surface) | ✅ | ✅ |
| **Curated loop / sound library** | ❌ **empty stub** | ✅ Apple Loops | ✅ huge cloud | ✅ | ✅ |
| Effects chain (EQ/comp/reverb/delay) | ✅ six effects | ✅ | ✅ | ✅ | ✅ |
| **Named effect presets** | ❌ raw knobs only | ✅ | ✅ | ✅ | ✅ |
| Volume automation | ✅ live (v0.6) | ✅ | ✅ | ✅ | ✅ |
| Pan automation | ❌ hidden/engine-less | ✅ | ✅ | ✅ | ✅ |
| Loop recording / takes | ❌ | ✅ | ✅ | ✅ | ✅ |
| Export MP3/WAV | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Guided first-launch onboarding** | ❌ stub, auto-start removed | ✅ | ✅ | ✅ strong | ✅ |
| Undo/redo | ✅ unlimited | ✅ | ✅ | ✅ | ✅ |
| Social/cloud sharing | ❌ (out of scope) | partial | ✅ moat | ✅ | partial |

**Read of the table:** Boojy's *mechanics* row (record, piano roll, effects, automation, export, undo) is at or near parity. Every ❌ that matters clusters in **two columns**: **ready-to-play sound** (instruments, presets, loops) and **guided first run**. That is the entire gap to GarageBand parity, and it is overwhelmingly *content + wiring*, not new architecture. Social/cloud (BandLab/Soundtrap's edge) is the one place Boojy is deliberately, correctly absent.

---

## 6. Recommended Next Theme (the version after v0.4.0)

> Note: the survey data describes a live **v0.6.0** build; the brief's "after v0.4.0" framing appears to predate it. The substantive recommendation — the *next* cycle — is the same either way, so I'm framing it as **v0.7**.

### Recommended: **v0.7 "First Sound" — stock instruments, effect presets, and a guided first song.**

**What ships:** the B1–B4 cluster as one coherent theme — author a thin set of synth presets (Piano/Strings/Bass/Pad/Lead) on the existing engine, re-enable the (already-built) preset browser, add named effect patches, wire **Capture MIDI** to a transport button (B4, ~5 min), and author the guided "add drums → record → export" onboarding flow on top of the 85%-built tour infra (B3, now unblocked because v0.6 drums give the flow something to teach).

**Why this is the right theme:** It is the *only* theme that closes the two columns where Boojy still fails the GarageBand promise — and it's mostly content authoring + wiring, so the risk profile is low. Every blocking gap in this theme has its engine or infra already built; the work is the welcome mat, not the house. Ship this and a beginner can open a blank project and make a song from nothing — the v1.0 bar.

**The alternative, and its cost — "Feel & Fidelity" (groove + recording flow):** wire the swing engine (B9-L), add loop recording / take comping (B5-L), per-step velocity (drums), pan automation (B8). This deepens the *spine* and is genuinely valuable for the singer/beat-maker who's past their first session.
**Cost of choosing it:** it leaves the **first-session wall intact**. A beginner still opens to a silent MIDI track and a blank canvas — so the headline v1.0 promise stays unmet, and the heaviest items (loop recording, swing groove) are pure engineering with no content lever to ship thin. Picking "Feel & Fidelity" first optimizes the experience of users Boojy is currently failing to *acquire*. It's the right *second* cycle, not the first.

**Recommendation:** v0.7 = "First Sound", then "Feel & Fidelity", then v1.0 release-hardening. Do **B4 (Capture MIDI wiring), B6 (audio Cmd+D), and the B-list one-liners (CC-lane toggle, theme-cycle footgun)** opportunistically inside whichever cycle touches that code — they're too cheap to schedule as their own line items.
