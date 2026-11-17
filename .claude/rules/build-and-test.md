---
paths:
  - ui/test/native/**
  - ui/test/goldens/**
  - engine/build.rs
  - build.sh
---

# Build & test gotchas

- **Toolchains:** Rust is pinned in `engine/rust-toolchain.toml`, Flutter in `ui/.fvmrc`. Keep the
  versions in `.github/workflows/*.yml` in sync, and upgrade deliberately (strict Clippy after a
  Rust bump). Windows CI uses `windows-2022` to match the `Visual Studio 17 2022` CMake generator:
  upgrade them together and invalidate the VST3 library cache when the C++ toolchain changes.
- **`./build.sh` picks the engine the app runs:** no argument = debug, `release` = release. It
  repoints `ui/macos/Runner/libengine.dylib` and copies the dylib into the app; a plain
  `cargo build` changes nothing the app loads. **Dogfood and judge audio on `./build.sh release`**
  (the debug engine crackles on its own). Don't run `flutter build` locally; `flutter run` builds
  the engine via the Xcode run script. CI builds both apps (debug, unsigned) on every PR
  (`app-build-macos`, `app-build-windows`).
- **Tests pass but the app crashes** → a stale dylib. Run `./build.sh release`.
- **`ui/test/native/`** loads `libengine` over `dart:ffi` as plain `flutter test` (no device, never
  launches the app). Run `./build.sh` first. Under `--dart-define=BOOJY_CI=true` a missing engine
  is a failing test, locally a skip; one guard at the top of `main()` handles it, don't add
  per-test guards.
- **Keep engine-backed test files small.** `flutter test` runs files side by side but the tests
  inside one file one after another, and each workflow test takes seconds. One 46-test file
  was once the whole CI wait (8 to 9 minutes); it is now split by topic
  (`daw_*_workflow_test.dart`, `daw_*_undo_test.dart`). Add a new file for a new topic, with
  shared steps in `support/workflow_helpers.dart`.
- **Goldens (`ui/test/goldens/`)** render painters to PNG under plain `flutter test`. After an
  intentional visual change: `fvm flutter test --update-goldens test/goldens/`, then look at the
  PNGs. They skip off macOS; refresh only on macOS.
- **Previewing new UI without launching the app:** `test/helpers/render_preview.dart` renders a
  widget to PNG with real fonts and icons (use from a throwaway, uncommitted test).
