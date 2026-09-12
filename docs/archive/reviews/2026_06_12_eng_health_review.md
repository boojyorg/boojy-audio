# Engineering Health Review — 2026-06-12

> **Editor's note (same day):** EH-1 was diagnosed independently — and fixed — the same morning
> this review ran, via the live Sparkle spot-check (PR #98). One correction to its mechanism:
> the `tsbujacncl` feed URL **did** resolve (GitHub's rename redirect serves it; verified live
> with the installed 0.5.4, which fetched the feed and saw 0.6.0). Auto-update was dead for a
> different reason the review missed: `release.yml` wrote the **semver** into `sparkle:version`,
> but Sparkle compares it against the app's **CFBundleVersion** (the pubspec build number) — so
> 0.5.4 compared `9` vs `0.6.0`, decided 9 > 0, and reported "up to date." PR #98 fixes both
> (build number in `sparkle:version`, feed URL → `boojyorg`, enclosure pinned per-tag, plus a
> hot-fix of the published v0.6.0 appcast entry). EH-1's recommended CI grep on the plist URL is
> still open.

## Verdict

Boojy Audio's engineering setup is **solidly healthy for a solo-maintainer early-access DAW — grade B**. The CI skeleton, test suites, and release automation are all materially above what a one-person desktop project usually carries, and the two hardest historical release bugs (missing `engine.dll`, double-wrapped Sparkle signature) are fixed at the automation level rather than papered over with notes. The story holding it back from a higher grade is a single **critical, user-facing defect: every shipped macOS build points its auto-updater at a GitHub org that does not exist** (`tsbujacncl` instead of `boojyorg`), so auto-update has silently been dead for every release. Around that one critical, the open work is a cluster of cheap, high-leverage fixes — no rustfmt gate, no version-sync gate, no required CI check, and a handful of untested correctness-critical code paths (FFI shims, automation interpolation, CompositeCommand undo).

## Scorecard

| Area | Grade | One-line why |
|---|---|---|
| CI Pipelines | B | Well-structured 4-job parallel matrix; release fires on any tag with no CI gate, appcast push silenced with `\|\| echo`. |
| Rust Engine Test Quality | B | 192 real-assertion tests; FFI shim layer and per-frame automation interpolation are the untested silent-corruption risks. |
| Flutter UI Test Quality | B− | ~1,300 tests, but two command files untested, CompositeCommand has no round-trip test, widget tests are pump-and-no-crash. |
| Build & Release Automation | C+ | Hardest historical bugs fixed at automation level — but a **critical** wrong-org SUFeedURL has killed auto-update on every build. |
| Repo Hygiene & Docs | B | Docs unusually accurate; ~68 MB of committed build artifacts (iOS libs, Windows CMake tree) will bite at clone time before v1.0. |
| Dev Experience & Guardrails | B | Strong hook + analysis stack; no Rust toolchain pin (clippy-lag will recur), no rustfmt gate, 430+ bare `println!`. |

*Build & Release is capped at C+ because it carries a confirmed critical finding.*

## Ranked backlog

Ordered by impact-per-effort. The first item is the only critical and is genuinely user-facing.

**EH-1 — Fix the Sparkle auto-update feed URL (wrong GitHub org).** *Severity: critical · Effort: hours.* `ui/macos/Runner/Info.plist:37` points `SUFeedURL` at `raw.githubusercontent.com/tsbujacncl/boojy-audio/...`, but the appcast is pushed to `boojyorg/boojy-audio` and the `tsbujacncl` account does not exist. **Do:** change the URL to the `boojyorg` path; add a pre-tag/CI grep that asserts the plist URL contains `github.repository`. **Why it matters:** auto-update has been dead for every released macOS build — users never get offered new versions. This is the single highest-value fix in the report and it is a one-line change. *(See editor's note: mechanism corrected; fixed in PR #98 except the CI grep.)*

**EH-2 — Add a CI grep gate for `println!`/`eprintln!` in audio-thread paths (and remove the `|| echo` on the appcast push).** *Severity: medium · Effort: hours.* Two cheap loudness wins. (a) `release.yml:395-396` silences a failed appcast push with `|| echo`, so a push failure ships a stale update feed while the job goes green — remove the `|| echo` so it fails loudly. (b) 432 `println!`/329 `eprintln!` calls (`engine/src/`, e.g. `audio_graph/renderer.rs:1333`, `device.rs`) ship to release with no log-level control. **Do:** a grep gate failing on bare prints in `audio_graph/`, `synth.rs`, `sampler.rs` — *not* the full tracing/log crate. **Why it matters:** the appcast fix protects the EH-1 feed once it works; the print gate keeps the real-time path quiet without heavyweight logging infra.

**EH-3 — Add `cargo fmt --check` + a `rust-toolchain.toml` pin.** *Severity: medium (toolchain pin: high) · Effort: hours.* CI enforces Dart formatting (`ci.yml:49-50`) but has no `cargo fmt --check`; `cargo fmt --check` currently finds 19 drifted files. Separately, there is no `rust-toolchain.toml`, so CI's `dtolnay/rust-toolchain@stable` floats and the clippy-lag that sank PR #37 (CI 1.96 vs local 1.90) will recur the next time stable advances — it's closed today only by coincidence. **Do:** add `engine/rust-toolchain.toml` (`channel = "stable"`) and one `cargo fmt --check` step. **Why it matters:** closes the documented-but-unenforced formatting gap and makes the clippy-lag failure structural rather than a coin-flip.

**EH-4 — Add a version-sync gate (pubspec vs git tag).** *Severity: high · Effort: hours.* `release.yml:330-334` reads the version from the git tag and never compares it to `ui/pubspec.yaml`; v0.3.2 shipped with pubspec at `0.3.0+1`. **Do:** ~20 lines at the top of `build-macos` extracting the pubspec semver and failing if it ≠ the tag. **Why it matters:** prevents shipping a build whose in-app version label lies — a documented process that has already proven fallible.

**EH-5 — Test CompositeCommand execute/undo round-trip.** *Severity: high · Effort: hours.* `command.dart:20-38` iterates forward on execute, reversed on undo; the only test (`undo_redo_manager_test.dart:256-279`) checks description/length/timestamp and never calls `execute()`/`undo()`. It backs 7+ production paths (multi-clip move, join, EQ band ops, delete-cascade). **Do:** one ~10-line test with 3 ordered MockCommands asserting forward-then-reverse order. **Why it matters:** a reversed-undo ordering bug here would silently corrupt state across several of the app's most-used operations.

**EH-6 — Test automation gain interpolation.** *Severity: high · Effort: hours.* `interpolate_automation_gain()` (`audio_graph/mod.rs:97-150`) runs per-frame in both renderers (`renderer.rs:1135,1190`; `offline.rs:486,533,997`) and powers a live v0.6.0 feature, with zero boundary tests. **Do:** 4–5 unit tests — before-first anchor, after-last, midpoint, −96 dB → exactly 0.0, monotonic ramp. **Why it matters:** a wrong gain at a breakpoint would corrupt every exported file with nothing asserting against it.

**EH-7 — Add null-pointer-safety tests to the FFI shim layer.** *Severity: high · Effort: day.* 14 FFI files, 2 tests total (`ffi/tracks.rs:286-300`); API-layer tests call Rust directly and never cross the extern-C boundary. **Do:** mirror the `ffi/tracks.rs` null-guard pattern, prioritizing `clips.rs`, `export.rs`, `project.rs`. **Why it matters:** a mismatched type or leaked CString here is a UAF/leak invisible to every existing test — the most plausible silent-memory-corruption source.

**EH-8 — Test sampler and drum-pad commands.** *Severity: high (proportionate: medium) · Effort: hours.* `sampler_commands.dart` and `drum_pad_commands.dart` (v0.6.0's newest surfaces) have zero tests; 9 of 11 command modules are covered. **Do:** ~15 tests asserting execute sends `newValue`, undo sends `oldValue` via the existing MockAudioEngine. **Why it matters:** the drum-kit editor is the freshest shipped feature and its undo contract is entirely unverified — best done after v0.7 scoping settles.

**EH-9 — Enable branch protection / required CI checks on master.** *Severity: medium · Effort: hours (a settings click).* No branch ruleset exists; CI is not a required check, so a merge can land before the build turns red (documented in CLAUDE.md and memory). **Do:** require `flutter-checks` + `rust-checks`. **Why it matters:** converts the "watch CI go green" social rule into a hard gate — cheap insurance against the one mistake hardest to undo (a merged regression needing a patch release). Note this is a *known, consciously accepted* tradeoff, not a blind spot.

**EH-10 — Test tempo-change MIDI clip re-push.** *Severity: medium · Effort: day.* CLAUDE.md's load-bearing time-domain rule ("every tempo change must re-push engine positions via `_onTempoChanged`") has no native test; `rescheduleAllClips` (`midi_playback_manager.dart:295`) is never exercised across a tempo change. **Do:** native test asserting a beat-4 clip's engine start time halves when tempo doubles — may need extracting the arithmetic into a testable helper. **Why it matters:** this is the app's own documented silent-corruption risk; effort is higher only because the logic lives in a 3,000-line screen method.

**EH-11 — Test TransportBar interaction callbacks.** *Severity: medium · Effort: hours.* `transport_bar_test.dart:19-148` pumps and asserts `findsOneWidget`; zero `tester.tap()`. **Do:** tap play/stop/record and assert the callbacks fire. **Why it matters:** the most user-visible widget's primary contract (buttons firing callbacks) is untested.

**EH-12 — Remove committed build artifacts (iOS libs ~44 MB, Windows CMake tree 599 files).** *Severity: high (hygiene) · Effort: hours.* `ui/ios/Frameworks/*.a` (23.2 MB each, the two largest blobs in history) and `engine/vst3_host/build_win/` (599 tracked files, gitignored-but-tracked) are dead weight CI rebuilds anyway. **Do:** `git rm --cached`, add gitignore entries, and purge with git-filter-repo *before v1.0 goes wide-public*. **Why it matters:** clone time and repo size balloon for every future contributor; cheapest to fix now while the audience is small.

**EH-13 — Replace Serum-dependent VST3 tests with the bundled `adelay.vst3`.** *Severity: medium · Effort: hours.* `vst3_host.rs:978-1061` hard-codes a Serum path and passes gracefully when absent, so `cargo test` green never means the VST3 load+process cycle ran. **Do:** load the SDK's `adelay.vst3` relative to `CARGO_MANIFEST_DIR`, process an impulse, assert output ≠ input; `#[ignore]` if the artifact isn't reliably built in CI. **Why it matters:** the entire VST3 path is currently unexercised in CI.

**EH-14 — Test sampler playback pitch.** *Severity: medium · Effort: hours.* `calculate_playback_rate` is tested but the voice consuming it isn't (`sampler.rs`); no test verifies a loaded sample plays at the expected pitch. **Do:** synthesize an in-memory 440 Hz sine (root 69), play notes 69 and 81, count zero-crossings for ~440/~880 Hz. **Why it matters:** pitch corruption would be inaudible to the current suite.

**EH-15 — Harden Sparkle key handling + DMG-existence assertion in release.yml.** *Severity: medium/low · Effort: hours.* `release.yml:160` writes the Sparkle private key plaintext into the checkout root with cleanup only at line 180 (a mid-step failure leaves it on disk); separately, `create-dmg || true` (`:119-125`) plus an `hdiutil` fallback means notarize/sign operate on whichever DMG landed unverified. **Do:** write the key to `$RUNNER_TEMP` with a `trap … EXIT` cleanup; add `test -f "...mac.dmg"` before notarize. **Why it matters:** defense-in-depth on the signing path; ephemeral runners make the key risk low but the intra-job window is real.

**EH-16 — Add a macOS CMake rebuild of the VST3 `.a` libs in CI.** *Severity: medium · Effort: day.* macOS `rust-checks` links whatever committed `engine/lib/*.a` exists (months stale — some from Oct 30); Windows rebuilds from source, so a C++ host regression passes macOS and only fails Windows. **Do:** mirror the well-designed Windows `vst3-libs-cache` rebuild on the macOS job. **Why it matters:** removes a real divergent-linking blind spot — though Windows CI catches it as a backstop, so it's contained.

**EH-17 — Documentation + small-hygiene cleanup pass.** *Severity: low · Effort: hours (batch).* A cluster of one-line fixes: rename ROADMAP.md's stale `## What's Next (v0.4.0)` heading; add `engine/src/ffi/` to ARCHITECTURE.md's tree; fix the "60+ rules" lint claim (44 explicit, ~143 effective); add `ignore = dirty` to `.gitmodules` for `vst3sdk` (moving that fact out of volatile auto-memory); gitignore `docs/screenshots/social-preview.png`; reconcile `dart format` vs `fvm dart format` wording; remove the inert `cp …/libengine.dylib ../ui/assets/` (`release.yml:43`); add a macOS-only guard to `build.sh`; add the Windows `dart format` note. **Why it matters:** individually trivial, but together they keep the docs trustworthy for the contributor who reads them at v1.0.

## What NOT to do

Drawn directly from the findings — these would be over-engineering for a one-person project:

- **Don't adopt the `tracing`/`log` crate ecosystem** to fix the bare `println!` problem. A CI grep gate on the audio-thread files is the proportionate fix; a full structured-logging migration is solving a problem this project doesn't have yet.
- **Don't build a full automated Windows smoke-test rig.** The `CMakeLists.txt` `FATAL_ERROR` guard already kills the original `engine.dll` class of bug at build time; an EXE `--version` exit-0 check is the most you'd want. Audio/MIDI/save-load smoke stays a manual checklist.
- **Don't reintroduce CI workflow machinery for the release gate when docs suffice.** The wrong-org URL (EH-1) and version-sync (EH-4) deserve real gates; the "tag only on green CI" rule is fine as a documented checklist step rather than a reusable-workflow gate.
- **Don't write full piano-roll/timeline gesture-layer widget tests** (days of mock-tree setup). Extract the snap arithmetic (`grid_utils.dart`, `timeline_coordinates.dart`, `piano_roll_coordinates.dart`) into pure functions and unit-test *those*; leave the gesture wiring until that layer is next substantially changed.
- **Don't chase realtime render-callback unit tests.** The offline path is a deterministic, fully-tested proxy; virtual-audio-device testing isn't worth it for a solo project. Add a targeted test only if a `try_lock`/sub-block regression actually surfaces.

## Theme recommendation

**Engineering hardening should be a background track, not the v0.7 headline theme.** The findings argue against making it the marquee: with one exception, every confirmed item is a *hours*-effort fix, and the suite is already healthy (B across the board) — there isn't a v0.7-sized body of hardening work here, and a maintainer-facing "hardening release" would deliver nothing a user can see.

But that one exception, **EH-1, must be pulled out and shipped immediately — it doesn't wait for any theme.** Auto-update is dead for every user right now; that's a hotfix, not a roadmap item, and it pairs naturally with the still-owed Sparkle end-to-end spot-check already on `dreams.md §1`.

The proportionate plan: ship **EH-1 as a standalone hotfix this week**, fold the cheap structural gates (**EH-2 through EH-5, EH-9**) into v0.7 as a half-day "guardrails" sub-task riding alongside a user-facing theme (the "Devices & Feel" candidate), and schedule the **artifact purge (EH-12)** deliberately before v1.0 goes wide-public. The remaining test-coverage items (EH-6 through EH-8, EH-10/11) are best slotted opportunistically when their subsystems are next touched. That keeps engineering health improving continuously without spending a whole user-visible release on plumbing the audience won't notice.

## Appendix: refuted claims

- **Sparkle tool downloaded unpinned at release time** — version *is* pinned (2.6.0), Sparkle publishes no checksums, and the DMG is already Developer-ID-signed + notarized (the load-bearing protection).
- **Send/return routing has no output-correctness test** — `project_golden_paths_test.dart:376-438` exports dry vs −6 dB wet and asserts the wet tail is 2× hotter, validating send level + dB conversion.
- **Mixer command tests verify call-but-not-value** — technically true but mitigated: undo methods correctly use `oldValue`, args are captured selectively elsewhere, no mixer-undo bugs in history; lower priority than engine-layer gaps.
- **Post-edit hook runs full `flutter analyze` per edit (10–25s)** — intentional and well-documented; real latency is 3–6s for a 276-file codebase, the deliberate parity gate (scoping would miss cross-file type errors).
- **`clippy::not_unsafe_ptr_arg_deref` globally suppressed hides unsafe FFI bugs** — justified: FFI functions use the `cstr_arg()` validating helper; only `vst3_host.rs` warrants a targeted (not global) tightening.
