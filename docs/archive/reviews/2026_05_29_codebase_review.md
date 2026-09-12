# Boojy Audio — State-of-the-App Review

**Date:** 2026-05-29
**Version under review:** v0.3.0 (released 2026-05-25), dogfood phase, no active plan doc
**Scope:** whole-app audit — repo/process/CI, Rust engine, Flutter UI, testing, bug hunt, placeholder inventory, and a ranked improvement backlog. Improve the app, *not* add features.
**Extends:** `docs/archive/reviews/2026_05_24_codebase_review.md` (does not repeat it). Architecture is in `docs/ARCHITECTURE.md`; feature status in `docs/FEATURE_TRACKER.md`.

**How this review was produced:** a deep read of every subsystem by parallel agents, a multi-lens bug hunt, then **adversarial verification** — every candidate defect was re-checked by independent skeptics trying to refute it. 31 of 57 candidates survived; 21 were refuted and dropped; 5 are "disputed" (split verdict, flagged below). The three highest-impact bugs were additionally **verified by hand against the source** for this report. A full build + all test suites were run for the baseline.

**Baseline — everything green:**

| Check | Result |
|---|---|
| Engine build (`./build.sh`) | ✅ OK — `libengine.dylib` installed (engine crate `v0.1.6`) |
| Rust tests (`cargo test`) | ✅ 111 passed, 0 failed (incl. VST3 host loading real Serum/Serum2) |
| Flutter analyze (`--fatal-infos`) | ✅ No issues found |
| Flutter unit tests | ✅ 1254 passed |
| Integration tests (macOS goldens) | ✅ 9 passed (MIDI save/reload, clip-move undo, WAV export, sends/returns) |

> **Read this first:** the suite is fully green, so this review is *not* about failing tests — it is about **latent correctness bugs the green suite never exercises**. The happy path the dev tests on is solid; the app is fragile under non-default audio devices, real plugin load, untrusted project files, and the undo/redo paths a dogfooding musician hits constantly.

---

## 1. Executive summary + scorecard

Boojy Audio is a capable alpha DAW with **genuinely strong architecture and FFI discipline**, but this deeper audit surfaced a cluster of latent defects the prior shallow delta never reached. The standouts:

- **VST3 plugins are processed one sample at a time on the audio thread** (a `parking_lot` lock + two heap allocations + a full `process()` call *per sample* = ~48k calls and ~96k allocs/sec/plugin). This is the single critical realtime violation — the moment a dogfooder loads their favourite plugin is the moment the app audibly falls over.
- **Offline export folds every bounce to dual-mono** via a wrong pan matrix, so exports do not match what you hear during playback.
- **A systemic "stale-id on redo" pattern** silently breaks Undo→Redo across *every* Remove-style command (effects, returns, audio clips): after Undo→Redo the thing you thought was removed is still processing audio while the UI shows it gone.
- **Two core musical properties are silently dropped on save** — project time signature (hardcoded 4/4) and recorded MIDI CC — and **MIDI clips lose name/color/offset/loop/automation on reload** because they round-trip through the engine instead of `ui_layout.json`.

The most insidious theme is **a large body of dead, diverged duplicate code**: the entire DAW mixin layer is shadowed by private re-implementations in `daw_screen.dart` that have drifted, and that drift is the *direct root cause* of three live bugs (drag-created clips skip overlap resolution, deleted tracks orphan floating VST3 windows, floating windows don't hide on track switch). It also actively misleads any future edit into touching code with zero runtime effect.

The bright spots are real: the **FFI boundary (A-)** is exemplary, audio-clip persistence is clean, and the test suite is healthier than feared. But the engine `api/`/`ffi/` layers and every large screen/painter have **zero coverage**, and CI's Rust clippy gate is **non-fatal** despite `CLAUDE.md` claiming otherwise.

### Scorecard

| Area | Grade | Δ vs 05-24 | Note |
|---|---|---|---|
| Engine — Rust DSP + realtime | **C+** | ▼ from A- | Prior A- was a shallow delta. Deeper audit finds the realtime path assumes 48 kHz/stereo, offline export folds to mono, no NaN/Inf guard, synth release clicks, per-callback heap alloc. |
| Engine — FFI boundary + locks | **A-** | – | Exemplary. All 15 FFI files panic-guarded, matching free fns, documented non-reentrant `Mutex` deadlock respected at all ~40 call sites. Residual issues are dead scaffolding only. |
| VST3 hosting | **C-** | n/a | Feature-complete end-to-end and defensively coded at the boundary, but per-sample processing dominates, plus a main/audio-thread editor-attach race and `setParamNormalized` from the audio thread. |
| UI — screens + editors + mixer | **C+** | ▼ from B | The whole mixin layer is dead/diverged from wired private copies — root cause of 3 live bugs. Plus multi-clip move = N undo entries, overlap-move destroys clips un-undoably, VST3 effects vanish from the chain. |
| Services / Dart FFI / undo-redo | **B-** | n/a | Binding layer solid. Weak spot is the command layer: systemic stale-id-on-redo, `RemoveEffectCommand` ignores `effectIndex`, VST3 plugins not rebuilt on load, `send_commands.dart` untested. |
| Persistence / round-trip fidelity | **C+** | n/a | Audio-clip persistence is clean, but time signature, recorded MIDI CC, and MIDI-clip metadata are silently lost. Dual source of truth (engine `project.json` + `ui_layout.json`) is fragile. |
| Testing | **B** | – | Healthier than feared (47 Dart files, 9 native goldens), but zero tests on engine `api`/`ffi`, no save/reload fidelity test, no recording golden, no `send_commands` test, ~22 painters untested. |
| Release / CI | **B-** | ▼ from B | CI runs `cargo clippy --all-targets` with no `-D warnings`, so pedantic regressions exit 0 despite `CLAUDE.md` claiming "CI rejects warnings." The Rust lint gate is effectively advisory. |
| Repo hygiene | **B** | n/a | `.claude/scheduled_tasks.lock` (live pid) and `docs/archive/vault-snapshots/` are untracked-but-not-ignored; `vst3sdk` nested submodule shows perpetually-dirty content. |
| Docs / process | **A-** | ▼ slightly | Largely accurate and in sync. Knocked off the top by two doc/reality mismatches: CLAUDE.md's clippy claim, and `ffi/mod.rs` documenting a `parseEngineResult()` that was never written. |
| Product readiness | **Alpha+** | – | Demos well on the happy path; dogfood-blocking friction is concrete: mono exports, non-4/4 loss, MIDI-clip loss on reload, redo corruption, and several advertised actions that are reachable no-ops. |

---

## 2. Repo / process / CI

**Docs are in good shape.** `CHANGELOG.md` / `docs/ROADMAP.md` / `README.md` / `docs/FEATURE_TRACKER.md` / `dreams.md` all agree on v0.3.0 / v0.3.x. Two mismatches knock docs off the top half-grade:

- **CI does *not* reject Rust warnings**, contradicting `CLAUDE.md`. `.github/workflows/ci.yml` (lines ~105, 130) runs `cargo clippy --all-targets` with no `-D warnings` / `RUSTFLAGS=-Dwarnings`, and `lib.rs:2` uses `#![warn(...)]` (not `deny`). Clippy violations print but exit 0 — pedantic regressions can merge silently. The Dart side is fine (`analyze --fatal-infos` is fatal). → *backlog #18*
- **`ffi/mod.rs:44-115` documents a `parseEngineResult()` Dart helper that does not exist.** `FfiErrorCode`/`ffi_ok`/`ffi_err`/`ffi_result` are all `#[allow(dead_code)]` with zero call sites; the real contract is the legacy `"Error: ..."` prefix the Dart side checks with `result.startsWith('Error')`. Misleads anyone following the documented error contract. → *backlog #18*

**Repo hygiene** (low severity, but standing footguns → *backlog #22*):
- `.claude/scheduled_tasks.lock` (a live pid/sessionId) and `docs/archive/vault-snapshots/` are untracked-but-not-gitignored — the lock especially risks an accidental `git add -A`. Add `.claude/*.lock` to `.gitignore`.
- `engine/vst3sdk` shows "modified content" — it's the SDK's own nested `cmake` submodule. Recursive checkout works in CI, so it doesn't break builds, but a perpetually-dirty submodule trains the dev to ignore `git status`.

**Engine crate version is `v0.1.6`** while the app is v0.3.0 — not wrong, but the Cargo version isn't part of the version-sync checklist and drifts. Minor.

---

## 3. Rust engine

### Realtime audio path — **C+**
The render callback is built on the right idea (snapshot track state under lock, then process lock-free), and the *playing* path was hardened with `try_lock` + contention counters. But several real defects remain:

- **Device sample rate & channel count are not forced** (`renderer.rs:316`, verified by hand). Only `config.buffer_size` is overridden; `sample_rate`/`channels` inherit the device default while all time math hard-codes `TARGET_SAMPLE_RATE = 48000` and the callback hard-codes `frames = data.len()/2` (stereo). On a 44.1 kHz default device, playback runs ~8.8% fast and pitched up; on mono/multichannel devices the output is scrambled. *Device-dependent — won't show on the built-in stereo output the dev tests on.* → *bugs C-2, H-1; backlog #11*
- **Offline export folds to mono** (`offline.rs:381-384`, verified by hand) — a wrong pan matrix sums both channels into each output. Every bounce is dual-mono and ~3 dB hot. → *bug H-2; backlog #2*
- **Stopped/idle callback uses blocking locks** (`renderer.rs:369, 388-392`) — and this is the *dominant* state while editing (the stream runs continuously for MIDI preview). UI-thread mutations stall the audio callback → dropouts during live preview. The playing path was hardened; this one wasn't. *(disputed — one skeptic argued contention windows are short; worth a 5-min confirm.)*
- **No NaN/Inf guard before device write** (`renderer.rs:832-858`) — the limiter passes NaN through (`NaN > threshold` is false → gain 1.0). One bad plugin/denormal → full-scale noise or a wedged output device. → *bug M-1; backlog #10*
- **Per-callback heap allocation** (snapshot clones, `get_all_tracks`, `return_index` rebuild, O(n²) peak-writeback) — the documented snapshot tradeoff, but a genuine realtime hazard under load. → *backlog (smell, ties to #1)*

### DSP correctness — **C+**
- **Synth release always fades from sustain, not current level** (`synth.rs:214-218`) — releasing during attack/decay jumps to sustain (0.7) then fades → audible click, and staccato notes get *louder* on release. The sampler does this right (`sampler.rs:83`). The synth is the *default* instrument, so every melody hits this. → *bug H-3; backlog #12*
- **Voice stealing always culls slot 0 with a hard reset** (`synth.rs:267-271, 372-381`; same in `sampler.rs:563-572`) — clicks + repeatedly drops ringing notes in dense chords. → *bug M-2; backlog #12*
- **No denormal flush in reverb/delay feedback** (`effects.rs:600-625, 498-499`) — on x86 (Windows/Intel Mac) denormal arithmetic is 10-100× slower, spiking CPU on quiet tails. Apple Silicon flushes by default, hiding it on the dev machine. → *bug M; backlog #14*
- Quality smells (low): synth "cutoff" is a sample-rate-dependent mix coefficient not a frequency; naive saw/square alias (no band-limiting); the "RMS" compressor detector is actually instantaneous peak.

### Export, recording, persistence — **C+**
- **Time signature hardcoded 4/4 on save, never restored** (`project.rs:285-286, 339-355`) — 3/4 or 6/8 projects reopen in 4/4. → *bug H-5; backlog #4*
- **Recorded MIDI CC dropped on save** (`project.rs:805-845`) — the `ControlChange` arm is a no-op; sustain/mod-wheel/expression is discarded silently. → *bug M-4; backlog #4*
- **Engine `ClipData` omits gain/warp/transpose/automation** (smell) — survives today only because the UI shadow-saves it in `ui_layout.json`, creating two divergent persistence paths.
- **Export rejects projects < ~1 s** (`api/project.rs`) with a misleading "No audio content" — conflates "empty" with "short". (low)

### VST3 hosting — **C-**
Feature-complete and defensively coded at the boundary, but:
- **Per-sample processing on the audio thread** (`vst3_host.rs:863-888`) — the critical bug. → *bug C-1; backlog #1*
- **`setParamNormalized` called from the audio thread** for MIDI CC (`vst3_host.cpp:875-897`) — the edit controller is a main-thread object; the param-change queue is the correct mechanism. → *bug H; backlog #20*
- **Editor attach drops all locks** then calls `createView`/`attached` into the same controller/component the audio thread is mutating (`api/vst3.rs:250-300`) — a genuine data race that can crash on editor-open during playback. → *bug H; backlog #20*
- **`set_state` size validation can integer-overflow** on untrusted project blobs (`vst3_host.cpp:1162-1199`) — a malformed/edited `.boojy` can crash/OOM the engine. → *bug M; backlog #15*
- Param/program names truncated to ASCII (`vst3_host.cpp:946-949`) — a proper UTF-8 helper already exists at line 1408 but isn't used. (low)

### FFI boundary + lock safety — **A- (the bright spot)**
All 15 `ffi/*.rs` files wrap every `extern "C"` function in `ffi_catch`; `Box`/`CString` allocations have matching free functions; and the non-reentrant `parking_lot::Mutex` deadlock hazard from `CLAUDE.md` is respected at all ~40 call sites of `get_track`/`get_master_track`/`remove_track`. Residual issues are latent hygiene only (dead error scaffolding, the `parseEngineResult` doc mismatch above). Keep this discipline — it's what makes the rest safe to fix.

---

## 4. Flutter UI

### The dominant theme: dead, diverged mixin layer — **(high-severity smell)**
`DAWScreen` mixes in `DAWPlaybackMixin`, `DAWClipMixin`, `DAWUIMixin`, `DAWVst3Mixin`, `DAWBuildMixin`, `DAWTrackMixin`, `DAWProjectMixin` — then **re-implements almost all of their public methods as private `_` copies inside `_DAWScreenState` and wires only the private ones**. The mixins compile (private names are library-scoped) but are unreferenced and have drifted from the live copies. This is the **root cause of three live bugs** and a standing trap. → *backlog #7, #8*

The three user-facing payloads of the divergence:
1. **Drag-created MIDI clips skip overlap resolution** (`daw_screen.dart:1239-1269`) — the wired `_createMidiClipWithParams` doesn't call `ClipOverlapHandler`; the mixin twin does, but is never invoked. Dragging a clip onto an occupied spot leaves overlapping, double-triggering clips. → *bug H-8*
2. **Deleted tracks orphan floating VST3 windows** (`daw_screen.dart:857-866`) — the wired `_onTrackDeleted` doesn't close floated plugin windows; the mixin twin does. Native-window resource leak. → *bug H-9*
3. **Floating plugin windows don't hide on track switch** (`daw_screen.dart:741-779`) — the per-track show/hide feature exists in the dead mixin and never runs. → *bug M-3*

Additional dead/diverged code (clean up alongside): `DAWBuildMixin` status bar (never in the build tree — the CPU/latency/sample-rate bar isn't shown anywhere); three copies of clip-gesture math (`audio_clip_gestures.dart`, `midi_clip_gestures.dart`, `models/timeline_item.dart` — all unused, already drifted from the live inline math); `NoteGestureHandlerMixin` (~300 lines of dead, divergent gesture logic); `FxChainView` + `EffectCard` (entire files unused, carrying a latent VST3 + undo bug if revived).

### Editors (piano roll, timeline, painters) — **C+**
- **Multi-clip move creates N undo entries** (`timeline_gesture_layer.dart:797-858, 871-906`) — `execute()` is called per clip, so one Ctrl+Z reverts only one. `CompositeCommand` exists for exactly this. → *bug H-10; backlog #9*
- **Clip-move overlap destroys clips un-undoably** (`timeline_gesture_layer.dart:819-849`) — `ClipOverlapHandler` deletes/trims the overlapped neighbour, but `MoveAudioClipCommand.undo()` only restores the moved clip's position → the overwritten clip is permanently gone. Silent data loss. → *bug H-11; backlog #9*
- **64-beat clamp blocks editing in clips > 16 bars** (`piano_roll.dart:2242, 2306-2309`) — clips can reach 256 beats, but notes snap back at bar 17. → *bug M-6; backlog #17*
- **Grid painter vs snap resolution disagree in non-4/4 at low zoom** (`timeline_grid_painter.dart:28-34` vs `grid_utils.dart:57`) — clips snap off the drawn bar lines. → *bug M-7; backlog #17*
- **Piano-roll hit-testing may not be fold-aware** (`piano_roll.dart:312-329` …) — *disputed*; if real, all editing in fold view targets the wrong row. Confirm before bundling. → *backlog #17*
- Painter smells (low): `NotePainter.shouldRepaint` omits `noteColor`/`maxMidiNote` (stale colour); triplet grid float drift drops bar highlighting.

### Mixer & devices — **C**
- **VST3 effects silently vanish from the device chain** (`effect_parameter_panel.dart:38`, verified by hand) — `double.parse('<PluginName>')` on the `name:` field throws and nulls the whole effect. A VST3 effect added to a track is invisible/unmanageable in the UI while it processes audio. → *bug H-12; backlog #6*
- **Instrument enable/bypass toggle: no undo + engine desync** (`device_chain_view.dart:275-289, 121`) — purely local UI state reset on track switch; no `getSynthBypass` getter, so bypass→switch→back shows enabled while the engine is silent. → *bug M-8; backlog #13*
- **Effect "Duplicate" loses parameters** (`device_chain_view.dart:725-735`) — adds a stock effect, not a copy. (low) → *backlog #13*
- Undo gaps cluster (`CLAUDE.md` command-pattern violations): the entire **Sampler editor** writes straight to the engine (nothing undoable); instrument-strip volume thumb has no `SetVolumeCommand`; effect **Reset to Default** wipes tweaks with no undo. → *backlog #13*

### Services / Dart FFI / undo-redo — **B-**
The binding layer is solid (typedefs match the ABI, strings freed). The command layer is the weak spot:
- **Stale-id-on-redo across all Remove commands** (`effect_commands.dart:87-104`, `send_commands.dart:173-204`, `clip_commands.dart:467-495`) — undo recreates with a new engine id but keeps the old id in the command; redo then targets the stale id and no-ops. After Undo→Redo the effect/return/clip is still audible while the UI shows it gone. Tests never re-execute, masking it. → *bugs H-13, M-9, M-10; backlog #3*
- **`RemoveEffectCommand` ignores `effectIndex`** (`effect_commands.dart:65, 94-104`) — undo re-inserts the effect at the *end* of the chain, silently changing signal-chain order (and the sound). Every test uses index 0. → *bug H-14; backlog #3*
- **VST3 plugins not restored into `Vst3PluginManager` on load** (`daw_project_mixin.dart:186-227`) — the engine plays them but the mixer shows zero plugins; the user can't see/edit/remove them. → *bug M-11; backlog #16*
- **MIDI clip metadata lost on reload** (`midi_playback_manager.dart:538-617`) — rebuilt from the engine, which stores none of the UI fields, so name reverts to "MIDI Clip", colour/offset/loop/mute/automation are lost and linked clips unlink. Audio clips avoid this via `ui_layout.json`; there's no MIDI equivalent. → *bug H-15; backlog #5*
- Library preview can poll forever if the Rust decode silently fails (no timeout); native UTF8 args leak if an FFI call throws (frees outside `finally`). (low)

---

## 5. Testing

**The existing suite is solid and fully green** (111 Rust + 1254 Dart unit + 9 native goldens; analyze clean). The problem is **coverage breadth — the bugs above live exactly in the untested layers:**

| Gap | Severity | Why it matters |
|---|---|---|
| Engine `api/` + `ffi/` have **zero** `#[cfg(test)]` | high | The layer most prone to the silent-deadlock class the codebase was already bitten by (v0.3.0 "shared reverb deadlock"). |
| No save/reload **fidelity** test | medium | Would have caught time-sig loss, MIDI CC drop, and MIDI-clip-metadata loss (bugs H-5, M-4, H-15). |
| No `send_commands_test.dart` | medium | Every other command family has one; would have caught the stale-id redo (bug M-9). |
| No native **recording** golden path | medium | Recording is a first-class flow (622-LOC mixin) with zero end-to-end coverage. |
| No VST3 state round-trip / editor lifecycle test | high | The only VST3 tests no-op when Serum is absent and `println!` without asserting. |
| No widget/screen tests for `daw_screen`, mixins, `piano_roll`, mixer strips | medium | The heaviest, most regression-prone logic ships untested by the fast suite. |
| ~22 `CustomPainter`s untested | low | Pure coordinate math, cheap to test; a regression misdraws with no failing test. |
| No deadlock-guard regression test | low | The documented silent-hang hazard has only indirect coverage. |

→ *backlog #19* bundles the high-leverage tests with the fixes they protect.

---

## 6. Confirmed bugs (severity-ranked)

31 adversarially-confirmed defects. **Confidence key:** ✔︎hand = verified against source for this report; ✔︎adv = survived two independent refutation lenses; ⚠︎disp = disputed (split verdict, listed separately). All are **code-confirmed**; interactive GUI repro was not run (no headless click-through), so runtime-repro steps are noted where cheap. The green test suite does not cover any of these paths.

### Critical
- **C-1** ✔︎adv — **VST3 plugins processed one sample at a time on the audio thread** — `vst3_host.rs:863-888`. Lock + 2 allocs + full `process(numSamples=1)` per sample → ~48k calls/sec/plugin; dropouts/underruns with any non-trivial plugin. *Repro: load any real VST3 instrument, play a few notes → glitches/underruns.*

### High
- **H-1** ✔︎hand — **Output channel count not forced to stereo** — `renderer.rs:353-358, 493-494`. `frames = data.len()/2` assumes interleaved stereo; mono/multichannel default devices scramble output.
- **H-2** ✔︎hand — **Offline export folds stereo to mono** — `offline.rs:380-386`. Wrong pan matrix; every bounce is dual-mono and ~3 dB hot. *Repro: pan two tracks hard L/R, export WAV → both channels identical.*
- **H-3** ✔︎adv — **Synth release fades from sustain not current level** — `synth.rs:214-218`. Click on staccato/early release; notes get louder at note-off.
- **H-5** ✔︎adv — **Project time signature hardcoded 4/4 on save** — `project.rs:285-286, 339-355`. 3/4 or 6/8 projects reopen in 4/4.
- **H-8** ✔︎adv — **Drag-created MIDI clips skip overlap resolution** — `daw_screen.dart:1239-1269`. Overlapping double-triggering clips, unlike record/copy paths.
- **H-9** ✔︎adv — **Deleted tracks orphan floating VST3 windows** — `daw_screen.dart:857-866`. Native-window leak + dangling editor id.
- **H-10** ✔︎adv — **Multi-clip move = N undo entries** — `timeline_gesture_layer.dart:797-858, 871-906`. One Ctrl+Z reverts only one clip.
- **H-11** ✔︎adv — **Clip-move overlap destroys clips un-undoably** — `timeline_gesture_layer.dart:819-849`. The overwritten neighbour is permanently gone on undo. Silent data loss.
- **H-12** ✔︎hand — **VST3 effects vanish from the device chain** — `effect_parameter_panel.dart:38`. `double.parse('<PluginName>')` throws → whole effect nulled; invisible/unmanageable while processing audio.
- **H-13** ✔︎adv — **Redo of effect removal uses a stale id** — `effect_commands.dart:87-104`. After Undo→Redo the re-added effect keeps processing while the UI shows it removed.
- **H-14** ✔︎adv — **`RemoveEffectCommand` ignores `effectIndex`** — `effect_commands.dart:65, 94-104`. Undo re-inserts at chain end, changing signal order and the sound.
- **H-15** ✔︎adv — **MIDI clip metadata lost on reload** — `midi_playback_manager.dart:538-617`. Name/colour/offset/loop/mute/automation lost; linked clips unlink.
- **H (VST3)** ✔︎adv — **MIDI CC `setParamNormalized` from the audio thread** — `vst3_host.cpp:875-897`.
- **H (VST3)** ✔︎adv — **Editor attach drops all locks, races the audio thread** — `api/vst3.rs:250-300`. Can crash on editor-open during playback.

### Medium
- **M-1** ✔︎adv — **No NaN/Inf guard before device write** — `renderer.rs:832-858`. One bad value → full-scale noise / wedged device.
- **M-2** ✔︎adv — **Voice stealing always culls slot 0, hard reset** — `synth.rs:267-271, 372-381`; `sampler.rs:563-572`.
- **M-3** ✔︎adv — **Floating windows don't hide on track switch** — `daw_screen.dart:741-779`.
- **M-4** ✔︎adv — **Recorded MIDI CC dropped on save** — `project.rs:805-845`.
- **M-5** ✔︎adv — **Add Audio Track bypasses undo + force-unwraps engine** — `daw_screen.dart:3305-3308, 3562-3565`. Not undoable; throws if clicked before engine init.
- **M-6** ✔︎adv — **64-beat clamp blocks editing in clips > 16 bars** — `piano_roll.dart:2242, 2306-2309`.
- **M-7** ✔︎adv — **Grid painter vs snap disagree in non-4/4 at low zoom** — `timeline_grid_painter.dart:28-34` vs `grid_utils.dart:57`.
- **M-8** ✔︎adv — **Instrument bypass: no undo + engine desync on track switch** — `device_chain_view.dart:275-289, 121`.
- **M-9** ✔︎adv — **Redo of return deletion uses stale return id** — `send_commands.dart:173-204`. Orphaned return keeps routing audio.
- **M-10** ✔︎adv — **Redo of audio-clip deletion uses stale clip id** — `clip_commands.dart:467-495`. Restored clip keeps playing.
- **M-11** ✔︎adv — **VST3 plugins not restored into `Vst3PluginManager` on load** — `daw_project_mixin.dart:186-227`.
- **M (VST3)** ✔︎adv — **`set_state` size validation can integer-overflow** on untrusted project data — `vst3_host.cpp:1162-1199`.

### Low
- **L-1** ✔︎adv — **VST3 param/program names truncated to ASCII** — `vst3_host.cpp:946-949` (proper helper exists at 1408).
- **L-2** ✔︎adv — **Effect "Duplicate" loses parameters** — `device_chain_view.dart:725-735`.
- **L-3** ✔︎adv — **Library preview polls forever if decode silently fails** — `library_preview_service.dart:188-216`.

### Disputed — needs a manual confirm (⚠︎disp)
Split verdicts; not counted in the 31. Each is plausible and cheap to check:
- ⚠︎ **Device sample rate not forced to 48 kHz** — `renderer.rs:290-319`. *(I verified the code does not force `sample_rate`; the dispute was over real-world device defaults. Treat as real — confirm on a 44.1 kHz device.)*
- ⚠︎ **Stopped/idle callback uses blocking locks** — `renderer.rs:369, 388-392`.
- ⚠︎ **`quantize_midi_clip` hardcodes 120 BPM** — `api/midi_clips.rs:493-498`. Quantize misaligns at any other tempo.
- ⚠︎ **Piano-roll hit-testing not fold-aware** — `piano_roll.dart:312-329, 1426-1478, 2166-2171`. If real, editing is broken in fold view.
- ⚠︎ **MIDI scheduling drops notes on seek-into-active-note** — `renderer.rs:649-654`.

> 21 further candidates were **refuted and dropped** by the adversarial pass (e.g. supposed FFI panic-guard gaps, supposed deadlocks) — consistent with the FFI layer's A- grade. Not re-raising them here (mirrors the `v0.3-audit-deferred-and-false-positives` memory).

---

## 7. Placeholders & stubs

Distinguishing **deliberate placeholders** (honestly labelled) from **unfinished features that read as shipped** (the real problem — they silently do nothing). → *backlog #21*

**Reachable no-ops that look active (fix or disable):**
- **Instrument Delete** (`device_chain_view.dart:683-687`) — the called-out TODO. Right-click instrument → Delete does *nothing*; no instrument-removal Command exists anywhere. The menu item looks active.
- **Instrument dropdown Swap & Delete** (`device_chain_view.dart:451-460`) — both no-ops; only Reset is wired.
- **Sampler warp** (`sampler.rs:264-265, 409-444`) — `warp_enabled`/`warp_mode`/`original_bpm` round-trip through the UI but `process()` never reads them. Toggling Warp does nothing audible.
- **Piano-roll CC lane** (`piano_roll_state.dart:224`) — edited by the user but never persisted or sent to the engine for playback. Looks like a working feature; isn't.
- **LUFS / platform-target normalization** (`export/normalize.rs:61-207`) — entire `PlatformTarget` enum + LUFS code is dead (no callers, no UI control). The K-weighting is a "simplified approximation," not BS.1770.
- **Loop-region range export** (`api/project.rs:384, 486, 196`) — `start_time`/`end_time` exposed but never read; no UI control.
- **`restartComponent` ignores VST3 restart flags** (`vst3_host.cpp:82-87`) — `kIoChanged`/`kReloadComponent`/`kLatencyChanged` logged and ignored; host keeps stale bus/param setup after a preset change.

**Honestly-labelled "coming soon" (deliberate, but live UI surface):**
- **File > Export MIDI** (`daw_screen.dart:2671-2696`, wired to menu + `PlatformMenuBar`) — "coming soon" dialog, even though a real per-clip exporter (`MidiFileService.encode`) exists and could be reused.
- **Edit > Bounce MIDI to Audio / Cmd+B** (`daw_screen.dart:2184-2220`) — "coming soon" dialog.

**Dead stub beside the real thing:** `DeleteMidiClipCommand` (`clip_commands.dart:83-102`) is an empty command; the working one is `DeleteMidiClipFromArrangementCommand`. Remove it.

---

## 8. Prioritized improvement backlog

Ranked by severity × impact ÷ effort. **No new features** — fixes, hardening, tests, UX polish, refactors. Effort: S/M/L/XL.

| # | Item | Sev | Effort | Files |
|---|---|---|---|---|
| 1 | **VST3: process per-buffer, not per-sample** | critical | L | `vst3_host.rs:863-888`, `renderer.rs:186/631-706`, `offline.rs:298/349/396` |
| 2 | **Fix offline-export pan matrix (mono fold)** | high | S | `offline.rs:380-386` |
| 3 | **Fix stale-id-on-redo across all Remove commands** | high | M | `effect_commands.dart:87-104`, `send_commands.dart:173-204`, `clip_commands.dart:467-495` |
| 4 | **Persist time signature + recorded MIDI CC** | high | M | `project.rs:285-286/339-355/805-845`, `recorder.rs:296` |
| 5 | **Persist MIDI clip metadata (via `ui_layout.json`)** | high | M | `midi_playback_manager.dart:538-617`, `daw_project_mixin.dart:194/823/854`, `project_persistence.dart:54` |
| 6 | **Fix VST3 effects vanishing (`fromInfo` name parse)** | high | S | `effect_parameter_panel.dart:38`, `api/effects.rs:140` |
| 7 | **Delete the dead/diverged DAW mixin layer** | high | L | `screens/daw/mixins/*.dart`, `daw_screen.dart` private twins |
| 8 | **Restore overlap-resolution + window cleanup on live handlers** | high | M | `daw_screen.dart:1239-1269/857-866/741-779` |
| 9 | **Group multi-clip moves + make overlap-move undoable** | high | M | `timeline_gesture_layer.dart:797-906`, `clip_commands.dart:52-80` |
| 10 | **NaN/Inf sanitize before device write** | medium | S | `renderer.rs:832-858`, `effects.rs:778-794` |
| 11 | **Force/validate stereo output (+ confirm sample-rate)** | high | M | `renderer.rs:290-319/353-358` |
| 12 | **Fix synth envelope release + voice-steal clicks** | high | M | `synth.rs:214-218/267-271/372-381` |
| 13 | **Close undo gaps on instrument/sampler/audio-track controls** | medium | L | `device_chain_view.dart`, `daw_screen.dart:3305/3562`, sampler editor |
| 14 | **Denormal flush in reverb/delay feedback** | medium | S | `effects.rs:600-625/498-499` |
| 15 | **Harden VST3 `set_state` vs untrusted data + round-trip test** | medium | M | `vst3_host.cpp:1162-1199`, `ffi/vst3.rs:254-265` |
| 16 | **Restore VST3 plugins into `Vst3PluginManager` on load** | medium | M | `daw_project_mixin.dart:186-227`, `vst3_plugin_manager.dart:199-235` |
| 17 | **Fix piano-roll long-clip clamp (+ confirm fold-awareness)** | medium | M | `piano_roll.dart:2242/2306-2309/312-329` |
| 18 | **Make CI clippy fatal + fix doc/reality mismatches** | medium | S | `ci.yml`, `ffi/mod.rs:46-51`, `vst3_host.rs:884` |
| 19 | **Close highest-value test gaps (fidelity, recording, sends, deadlock)** | medium | L | `ui/test/services/commands/`, `integration_test/`, engine `api`/`ffi` |
| 20 | **Defer MIDI-CC + editor-attach off the audio thread** | high | M | `vst3_host.cpp:875-897`, `api/vst3.rs:250-300` |
| 21 | **Remove/disable placeholder features that read as shipped** | low | M | `daw_screen.dart:2671/2184`, `sampler.rs:264-265`, `normalize.rs` |
| 22 | **Repo hygiene: gitignore lock, settle snapshots, document submodule** | low | S | `.gitignore`, `.gitmodules`, `engine/vst3sdk` |

### Recommended v0.3.x theme

Frame v0.3.x as a **trust/correctness hardening** release, not feature work.

- **Primary — "Don't lose my work, don't corrupt my edits"** (#2, #3, #4, #5, #9, with the test gap #19). Every item is *silent* data loss or state corruption on paths a user hits every session: exports come out mono, redo undoes the wrong thing, non-4/4 projects reopen in 4/4, MIDI clips lose their metadata, grouped moves can't be undone. None throw errors — they quietly betray the user, the fastest way to lose trust in a DAW. They cluster in `project.rs`, the command layer, and the timeline gesture path; mostly S/M effort; a single save/reload fidelity test + an execute→undo→execute command test cover #3/#4/#5 at once. **Highest signal-to-effort, directly resumes the dogfood beat.**
- **Secondary — "Plugins and the audio thread"** (#1, #10, #11, #20). #1 is the single critical defect and the moment a dogfooder loads a plugin is the moment the app falls over — but it's an L-effort engine refactor that drags the data races (#20) along. Heavier and riskier.

**Recommendation:** lead with the data-loss/undo cluster (fast wins, restores trust), then slot the VST3 per-buffer refactor as the centerpiece of the *following* cycle once round-trip tests exist to catch regressions. Do the data-loss cluster either way **before any new feature work** — shipping features on top of silent corruption just buries it deeper.

---

*Generated 2026-05-29 from a multi-agent deep read + adversarial verification (126 agents) plus a full local build/test pass (all green). Bug confidence is code-level; interactive GUI reproduction was not performed. Disputed items are flagged for manual confirmation.*
