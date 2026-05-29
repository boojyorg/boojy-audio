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
- **macOS integration tests can hang in CI** at app-foreground — verify locally instead (~2s); don't
  wait out a CI stall. (See auto memory: "macOS integration tests hang in CI".)
- The "app stuck on initializing = missing FFI symbol" gotcha lives in
  [`ffi.md`](ffi.md) since it's an FFI-boundary issue.
