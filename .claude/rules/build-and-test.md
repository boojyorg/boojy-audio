---
paths:
  - ui/integration_test/**
  - ui/test/goldens/**
  - engine/build.rs
  - build.sh
---

# Build & test gotchas

- **Rust changes must be built in release mode.** `ui/macos/Runner/libengine.dylib` is a **symlink**
  to `engine/target/release/libengine.dylib`, so a plain `cargo build` (debug → `target/debug/`)
  won't be picked up. Use `./build.sh release` (or `cd engine && cargo build --release`). **Don't run
  `flutter build`** — the Xcode run script builds the engine on `flutter run`.
- **Tests pass but the app crashes** → likely a dylib mismatch. Run `./build.sh` to rebuild the
  engine and refresh the symlinked `libengine.dylib`.
- **Integration tests fail or skip on macOS** → `libengine.dylib` is missing. Run `./build.sh`
  first, then `cd ui && fvm flutter test integration_test/ -d macos`. As of the v0.5 C92 fix the
  suite no longer silently early-returns when the engine is absent: under `BOOJY_CI` it registers a
  **failing** test (so a forgotten `./build.sh` in CI can't produce a vacuous "N passed"), and
  locally it reports as **skipped** rather than passed. The per-test `isNativeEngineAvailable`
  guards were removed — a single top-of-`main()` guard handles it, so don't re-add them.
- **macOS integration-test CI flake is FIXED** (PR #31, 2026-05-31). It used to hang/fail even though
  the tests passed — on the headless runner `flutter test -d macos` can't foreground the app
  (`open returned 1`) and returns a non-zero exit code regardless. CI now judges the suite by the
  streamed reporter (`"N tests passed."`) and ignores flutter's exit code; the suite also `exit(0)`s
  under `--dart-define=BOOJY_CI=true`. **So if `Run integration tests` is red now, it's a REAL
  failure — trust it**, don't `rerun`. Locally it still passes in ~2s. (See auto memory: "macOS
  integration tests hang in CI".)
- The "app stuck on initializing = missing FFI symbol" gotcha lives in
  [`ffi.md`](ffi.md) since it's an FFI-boundary issue.

## Golden (screenshot) tests — `ui/test/goldens/`

- These render `CustomPainter`s (piano-roll lanes, timeline grid) straight to PNG under plain
  `fvm flutter test` — **no device, no engine**. They run inside the normal `flutter test` gate and
  exist as a visual safety net for the legibility work.
- **After an intentional visual change**, refresh the baselines:
  `cd ui && fvm flutter test --update-goldens test/goldens/`, then eyeball the PNGs before
  committing. A pixel diff writes images to `test/goldens/failures/` (gitignored).
- **macOS is the reference platform.** The tests `skip` off macOS (Windows CI also runs
  `flutter test`, and per-platform rasterization wouldn't byte-match). Generate/refresh on macOS.
