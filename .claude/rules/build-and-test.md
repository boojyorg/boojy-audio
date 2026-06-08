---
paths:
  - ui/test/native/**
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
- **Native-engine tests live in `ui/test/native/`** (moved out of `ui/integration_test/`). They load
  `libengine` over `dart:ffi` and pump no UI, so they run as **plain `flutter test`** — no device,
  no `-d macos`. Run `./build.sh` first so the dylib exists. As of the v0.5 C92 fix the suite never
  silently early-returns when the engine is absent: under `BOOJY_CI` (CI passes
  `--dart-define=BOOJY_CI=true`) it registers a **failing** test so a forgotten `./build.sh` can't
  produce a vacuous "N passed"; locally without the flag it reports **skipped**. The per-test
  `isNativeEngineAvailable` guards were removed — one top-of-`main()` guard handles it; don't re-add.
- **The macOS integration-test foreground hang is DESIGNED OUT** (not just retried). The flake came
  from `flutter test -d macos` launching the app via `open`, which couldn't foreground it on the
  headless runner and lost the handle to kill it → the process hung to the timeout. Moving these to
  plain `flutter test` removes the device/app entirely, so there's no app to foreground and no hang.
  The old mitigations (the `exit(0)`-on-teardown hack, the reporter-grep success check, and the
  `nick-fields/retry` 3x wrapper) are all **gone** — a red `Run unit tests` is now a REAL failure.
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
