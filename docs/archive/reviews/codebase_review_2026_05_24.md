# Boojy Audio — Codebase Review (Delta)

**Date:** 2026-05-24
**Scope:** Delta since [codebase_review_2026_05_22.md](codebase_review_2026_05_22.md) (~v0.2.4). Covers what landed this cycle — v0.3.0 send/return, the reverb DSP fix, and the Flutter 3.44 / Dart 3.12 upgrade (PR #1, merged). Unchanged areas are not re-litigated.

---

## Executive Summary

Two days of work moved three things that the May-22 review was waiting on: **routing shipped** (minimal send/return aux buses, the #1 v1.0 blocker), an **`integration_test/` suite now exists and runs in CI** (the biggest May-22 testing gap), and the **toolchain is on Flutter 3.44 / Dart 3.12**, pinned via FVM. The headline caveat is a quality one: the stock **reverb was effectively silent** (mis-scaled Freeverb, ~0.1% energy at full wet) and shipped that way undetected — it was only caught because building send/return forced a 100%-wet use and we added the first test of stock-effect *output*. It's fixed, but it exposes that critical-path DSP had no coverage. Net: capability and test breadth both up; macOS CI fully green; **Windows is now confirmed broken** (VST3 linking + a unit test).

---

## Scorecard

| Area | May-22 | Now | Δ | Notes |
|------|--------|-----|---|-------|
| Architecture | B+ | B+ | – | Top "god file" (`timeline_view.dart` 4,900→1,252 + parts) decomposed; but complexity relocated to a 2,361-line gesture part, `daw_screen.dart` still 4,086, split-persistence model unchanged. |
| Engine (Rust) | A- | A- | – | Send/return DSP (realtime + offline) + deadlock pattern fixed/documented. Held back: a stock effect shipped broken; PDC still absent and now *acute* for returns. |
| UI (Flutter) | B | B | – | New ⚡ send picker + mixer send knobs; `onReorderItem` migration; Material-only icons. No regressions, no structural change. |
| Testing | B- | **B** | ▲ | `integration_test/` now real: 8 native golden paths incl. save/reload-with-sends and export energy. Still thin on FFI, the realtime renderer, and the new send knobs. |
| Docs / process | A | A | – | Added `FLUTTER_3.44_RULES.md` + a loaded CLAUDE.md conventions section; "revisit-when" deferral log. |
| Release / CI | B+ | **B** | ▼ | macOS matured (integration in CI, FVM pin). Windows now *confirmed* red: VST3 `LNK1120` (5 unresolved `vst3_*`) + 1 unit-test failure. A `*.xcworkspace` ignore also hid a file needed to build macOS from a clean checkout (fixed). |
| Product readiness | Alpha+ | Alpha+ | – | Routing started (minimal aux). Still gated on comping, stock instruments, Windows hardening. |

---

## Rust Audio Engine

### What improved

- **Send/return routing** — post-fader sends summed into per-return accumulators, processed through the return FX chain, mixed to master, in **both** the realtime (`audio_graph/renderer.rs`) and offline/export (`audio_graph/offline.rs`) paths. Shared returns dedupe by effect type (`api/sends.rs`).
- **Deadlock pattern fixed and documented** — the non-reentrant `parking_lot::Mutex` hazard (calling `TrackManager` while holding a `Track` lock) bit `get_track_sends`; fixed via the snapshot pattern, now codified in CLAUDE.md and used in `find_return_by_effect_type` / `get_track_sends`.
- **Project restore hardened** — two-pass restore with a save-id→new-id map remaps send targets and clip attachments (golden-path tested).

### Concerns

- **Stock DSP shipped broken.** The Freeverb fed `room_size` straight into comb feedback (~0.5, never resonates) and attenuated wet ~36 dB; at 100% wet it returned ~0.1% energy. Fixed (feedback 0.7–0.98 map, corrected gain) with a new `reverb_full_wet…energy` guard — but **no test covered stock-effect output before this**, so the other built-ins (EQ/Comp/Delay/Chorus/Limiter) are unverified for level/correctness.
- **Plugin delay compensation still absent.** The May-22 review flagged PDC as mattering "for send/return"; returns now exist with **zero latency compensation**, so any return-chain latency phase-smears against the dry. (Only MIDI-input monitoring latency comp exists, in `api/midi_input.rs`.)
- **`eprintln!` still in hot paths** — 16 in `renderer.rs`, 9 in `offline.rs`. Gate before v1.0.

---

## Architecture & UI

### What improved

- **Timeline decomposition landed** — `timeline_view.dart` 4,900 → 1,252 lines, with `timeline_gesture_layer.dart` and `timeline_track_list.dart` as `part` files sharing the private library.
- **v0.3.0 mixer UI** — ⚡ FX picker (`widgets/fx_chain/fx_chain_view.dart`) and per-strip send knobs; send operations go through the `Command` pattern (`services/commands/send_commands.dart`) for undo.

### Concerns

- **Complexity relocated, not removed.** The decomposition split the file but `timeline_gesture_layer.dart` is itself **2,361 lines**, `daw_screen.dart` is still **4,086**, and `track_mixer_strip.dart` grew to **2,346** with the send knobs. `api/remaining.rs` is still a 634-line catch-all.
- **Split persistence unchanged** — engine `project.json` + UI `ui_layout.json`; the v0.3.0 send state lives engine-side and round-trips, but the structural split that caused earlier data-loss bugs is the same.

---

## Testing & CI

### What improved

- **`integration_test/` exists and runs in CI** (macOS) — 8 native-engine golden paths: MIDI track/note save→reload, clip-move undo, WAV export smoke, **send→save→reload persistence**, shared-send dedup, `AddSharedSendCommand` undo, and **reverb-send tail energy**. This directly closes May-22's "No `integration_test/` folder yet" and "save/load roundtrip: partial."
- **DSP now has a (first) output test** — the reverb energy guard.

### Gaps (still open)

| Area | Coverage | Risk |
|------|----------|------|
| FFI string/memory boundary | None | Double-free / leak, untested |
| Realtime `renderer.rs` / `offline.rs` sample loop | Indirect only | DSP regressions slip through (cf. reverb) |
| Mixer send knobs / gesture layer | None | New surface, untested |
| Other stock effects' output | None | Could be mis-scaled like the reverb was |
| VST3 load/unload | None | Crash-prone |
| **Windows** | **Red** | VST3 `LNK1120` + 1 unit-test failure on `master` |

---

## May-22 "Focus Next" → status

- **v0.2.3** — persistence audit ✓, integration tests ✓ (suite added), timeline decomposition phase 1 ✓, Windows CI ✓ (added, though now red), undo audit / dead-code cleanup ~partial.
- **v0.3.0 — send/return routing** ✓ shipped (minimal aux bus, realtime + export, persisted, undoable).
- **v0.3.x — ghost notes, clip polish** ☐ open.

---

## Where to Focus Next

1. **Validate the other stock effects** (EQ/Comp/Delay/Chorus/Limiter) the way the reverb now is — output-level/energy tests. The reverb episode says this is the real gap.
2. **Plugin delay compensation** — now that returns exist, latency-align them; otherwise send/return phase-smears with VST3 in the chain.
3. **Windows parity** — the confirmed blocker: link the 5 `vst3_*` symbols (host lib export mismatch) and fix the 1 red Dart unit test, so `master` CI is green on both platforms.
4. **Cover the new/critical surfaces** — FFI boundary, mixer send knobs, a smoke test over the realtime renderer.
5. **Gate hot-path `eprintln!`** before v1.0.
6. **Reverb voicing pass** — the fix made it *present*; confirm the default decay/wetness is musically right (it was tuned to a sensible energy ratio, not by ear).
7. **Continue decomposition** — `daw_screen.dart` (4,086) and `timeline_gesture_layer.dart` (2,361) are the next god files.

---

## Review Index

| Date | Doc | Scope |
|------|-----|-------|
| 2026-03-26 | [ui_review_2026_03_26.md](ui_review_2026_03_26.md) | UI/UX vs competitors |
| 2026-03-29 | [ui_review_2026_03_29.md](ui_review_2026_03_29.md) | UI/UX follow-up |
| 2026-05-22 | [codebase_review_2026_05_22.md](codebase_review_2026_05_22.md) | Full codebase architecture & engineering |
| 2026-05-24 | This doc | Delta: v0.3.0 send/return, reverb fix, Flutter 3.44 |
