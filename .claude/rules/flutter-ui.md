---
paths:
  - ui/lib/**
  - ui/macos/**
  - ui/pubspec.yaml
---

# Flutter 3.44 / Dart 3.12 conventions & UI changes

Flutter is pinned to **3.44.0 / Dart 3.12** via FVM (`ui/.fvmrc`). Full rationale and the
"revisit-when" log live in [docs/FLUTTER_3.44_RULES.md](../../docs/FLUTTER_3.44_RULES.md); the
load-bearing rules:

- **Keep `package:flutter/material.dart` imports.** Do **not** migrate to the standalone
  `material_ui` / `cupertino_ui` packages yet — they're preview (`0.0.1`) and the in-SDK imports are
  **not** deprecated in 3.44. Revisit only when those packages reach a stable release.
- **Icons are Material-only, via the `BI` facade** (`ui/lib/theme/boojy_icons.dart`). Prefer `BI.*`
  over importing `Icons.*` directly in widgets. `phosphor_flutter` was removed because it extends
  `IconData`, which became `final` in 3.44 — any icon package that extends/implements `IconData`
  will fail to compile, so don't add one.
- **Plugins use CocoaPods, not SwiftPM.** Do **not** run
  `flutter config --enable-swift-package-manager`: `window_manager`, `desktop_drop`, and
  `screen_retriever_macos` don't support SwiftPM yet. The `FlutterGeneratedPluginSwiftPackage`
  scaffolding in `ui/macos/Runner.xcodeproj` is Flutter-generated (hybrid) — leave it, don't
  hand-edit.
- **macOS title bar: native title is hidden, the transport bar is the only top chrome.** No native
  `NSToolbar` style gives "centred + compact" — `.expanded` centres the title but adds an empty,
  taller toolbar row; `.unifiedCompact` is compact but left-aligned. So we hide the native title via
  `window_manager` `TitleBarStyle.hidden` (keeping the traffic lights) and let the transport bar run
  edge-to-edge. A centred Flutter-drawn title exists but is **off by default** — it collides with the
  transport controls in single-row layouts. Don't re-enable the native title bar.
- **Reorderable lists use `onReorderItem`**, not the deprecated `onReorder`. `onReorderItem` already
  adjusts `newIndex` for the removed item — do **not** add a manual `if (newIndex > oldIndex)
  newIndex--`.
- **Dart 3.12 private named parameters** (`MyType({required this._field})`) are fine for new
  constructors, but not a required refactor of existing code. Primary constructors are still
  experimental — don't use them.
- **Toolchain sync:** changing the Flutter version means updating `ui/.fvmrc` **and**
  `FLUTTER_VERSION` in both `.github/workflows/*.yml` together.

## When modifying UI widgets

- **Check parent consumers** before changing a widget's API or layout — check all call sites.
- **Preserve existing behavior** — design changes shouldn't break other panels.
- **Test at different window sizes** — the DAW layout is responsive; verify small and large.
- **Painters are sensitive** — changes to `CustomPainter` classes affect rendering across the
  timeline.
- **Timeline layout:** `timeline_view.dart` uses `part` files for `timeline_gesture_layer.dart` and
  `timeline_track_list.dart` (private methods share one library). Import `timeline_view.dart` only,
  never the part files directly.
- **`daw_screen.dart` trap:** it wires **private `_` copies** of its mixins; the actual mixin files
  are **dead/diverged**. Edit the wired private methods in `daw_screen.dart`, *not* the mixins —
  editing the mixins changes nothing the app runs.
- **UI persistence:** new fields saved in `ui_layout.json` must go through
  `ProjectPersistence.collect()` / `applyUILayout()` — don't scatter field lists across project
  managers.
- **Use `Log.d()` / `Log.e()` / `Log.i()`** (from `utils/logger.dart`), not `print()`.
