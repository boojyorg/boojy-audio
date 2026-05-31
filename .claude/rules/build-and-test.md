---
paths:
  - ui/integration_test/**
  - engine/build.rs
  - build.sh
---

# Build & test gotchas

- **Tests pass but the app crashes** → likely a dylib mismatch. Run `./build.sh` to rebuild the
  engine and refresh the symlinked `libengine.dylib`.
- **Integration tests fail or skip on macOS** → `libengine.dylib` is missing. Run `./build.sh`
  first, then `cd ui && fvm flutter test integration_test/ -d macos`.
- **macOS integration-test CI flake is FIXED** (PR #31, 2026-05-31). It used to hang/fail even though
  the tests passed — on the headless runner `flutter test -d macos` can't foreground the app
  (`open returned 1`) and returns a non-zero exit code regardless. CI now judges the suite by the
  streamed reporter (`"N tests passed."`) and ignores flutter's exit code; the suite also `exit(0)`s
  under `--dart-define=BOOJY_CI=true`. **So if `Run integration tests` is red now, it's a REAL
  failure — trust it**, don't `rerun`. Locally it still passes in ~2s. (See auto memory: "macOS
  integration tests hang in CI".)
- The "app stuck on initializing = missing FFI symbol" gotcha lives in
  [`ffi.md`](ffi.md) since it's an FFI-boundary issue.
