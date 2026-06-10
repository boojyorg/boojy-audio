---
paths:
  - ui/lib/**
  - ui/macos/**
  - ui/pubspec.yaml
---

# Flutter 3.44 / Dart 3.12 conventions & UI changes

Flutter is pinned to **3.44.0 / Dart 3.12** via FVM (`ui/.fvmrc`).

> Heads-up: much of the public 3.44 advice targets **mobile** (iOS SwiftPM, Android Hybrid
> Composition) and does **not** apply to this macOS/Windows desktop DAW — verify against this
> project before acting on a generic "3.44 best practices" list.

The load-bearing rules:

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

## Deferred 3.44 decisions — revisit when…

| Topic | Decision | Revisit when |
| --- | --- | --- |
| `material_ui` / `cupertino_ui` standalone packages | **Stay on `package:flutter/material.dart`.** Preview (`material_ui` is `0.0.1`, "Coming soon"); the in-SDK imports are **not** deprecated in 3.44 — migrating now bets ~170 files on a preview package. | `material_ui` ships a stable (≥1.0) release **and** the in-SDK imports start emitting deprecation warnings. |
| SwiftPM (3.44 default for new iOS/macOS projects) | **Keep CocoaPods.** Don't run `flutter config --enable-swift-package-manager`. | `window_manager`, `desktop_drop`, and `screen_retriever_macos` all ship SwiftPM support (today `flutter pub get` warns they don't). |
| Dart 3.12 private named parameters | **Allowed, not mandated** — fine for new constructors, no mass refactor. | n/a — use at discretion. Primary constructors stay off (experimental). |

**Not applicable here** (don't burn time on generic 3.44 advice): Android Hybrid Composition /
SurfaceControl (no Android target); Impeller migration (already the macOS default); iOS
CocoaPods-vs-SwiftPM troubleshooting (no iOS target ships).

## When modifying UI widgets

- **Check parent consumers** before changing a widget's API or layout — check all call sites.
- **Preserve existing behavior** — design changes shouldn't break other panels.
- **Test at different window sizes** — the DAW layout is responsive; verify small and large.
- **Painters are sensitive** — changes to `CustomPainter` classes affect rendering across the
  timeline.
- **Never combine `Border.all` + `borderRadius` + `clipBehavior` on one Container** — the clip
  shaves the outer half of the border stroke at the corner arcs (ragged-corner artifact; was
  visible on the metronome button and every device card). Instead: bordered container with NO
  clip, and either round the inner fills to `radius - borderWidth` (metronome pattern) or wrap
  the child in `ClipRRect` at the inner radius (DeviceBox pattern).
- **Track icons are BI icons keyed by string** (`utils/track_icons.dart`): `customIcon` persists
  a key like `'mic'`; legacy emoji strings from old projects map through the legacy-emoji table.
  Don't reintroduce emoji glyphs in track chrome.
- **Timeline layout:** `timeline_view.dart` uses `part` files for `timeline_gesture_layer.dart` and
  `timeline_track_list.dart` (private methods share one library). Import `timeline_view.dart` only,
  never the part files directly.
- **Timeline coordinate spaces (gesture math):** track rows and clips live INSIDE the horizontal
  scroll view at full content width, so their `details.localPosition.dx` is already **content
  space** — never add `scrollController.offset` to it (`calculateBeatPosition` once did; every
  beat computed from a row gesture drifted right by the scrolled amount — broken drag-to-create /
  double-click-create / empty-click deselect whenever scrolled past bar 1). The **ruler** and the
  `context.findRenderObject()`-based drag-ghost math are OUTSIDE that scroll → viewport space →
  there `+ scrollOffset` is correct. Box-selection state: X content space, Y visible space (the
  overlay Stack is the content-space one the playhead mounts in). When in doubt, check which
  render box the position is relative to before adding/subtracting scroll offsets.
- **`daw_screen.dart` / mixin trap:** `_DAWScreenState` **does** mix in `DAWClipMixin` etc., and
  many mixin methods are live — the instrument-drop/sampler/drum-kit constellation
  (`onInstrumentSelected`, `onInstrumentDropped(OnEmpty)`, `createDrumKitTrack`,
  `createSamplerTrackWithSample`, `convertAudioTrackToSampler`, `showSnackBar`) is consolidated
  onto the mixins, as are `splitSelectedClipAtPlayhead` / `joinSelectedClips`. But other methods
  have **private `_` duplicates in `daw_screen.dart` that the call sites actually use** (e.g.
  `_bounceMidiToAudio`; the library double-click trio `_handleLibraryItemDoubleClick` /
  `_handleVst3DoubleClick` / `_handleOpenInSampler` — the dead mixin copies were deleted in v0.6
  batch 4 after they silently diverged). Before editing either copy, check which one the
  Cmd-shortcuts/menus/callbacks reference; edit that one and delete the other when possible (the
  v0.6 join work removed the dead `_consolidateSelectedClips` this way).
- **UI persistence:** new fields saved in `ui_layout.json` must go through
  `ProjectPersistence.collect()` / `applyUILayout()` — don't scatter field lists across project
  managers.
- **Never read `context.colors` inside an event handler** (onTap/onPressed, a `showMenu().then`,
  a dialog callback). It's a listening `Provider.of`, which asserts "listen outside build" in
  DEBUG builds only — release looks fine, but in debug the handler dies silently and the
  menu/dialog/action just doesn't happen (v0.5.1 right-click Delete; v0.6 found five dead
  context/signature menus this way). In handlers use `context.themeProvider.colors`
  (listen:false), or capture the colors in `build()` / inside the menu's item builder.
  Regression guard = `ui/test/lint/provider_listen_guard_test.dart` (AST scan of `lib/**`, runs
  under plain `flutter test`) — it also catches reads inside methods *invoked from* handlers
  (`onTap: _showMenu` tearoffs and `onTap: () => _showMenu()`), the shape that shipped the
  sampler Root Note bug (#23). Note `UndoRedoManager` now rethrows command errors in debug
  (`kDebugMode`), so swallowed handler asserts surface instead of dying silently.
- **Use `Log.d()` / `Log.e()` / `Log.i()`** (from `utils/logger.dart`), not `print()`.
- **File/folder dialogs go through `ui/lib/utils/native_dialogs.dart`**
  (`pickFolder` / `pickSaveFilePath` / `sanitizeFileName`) — never call `osascript` inline.
  AppleScript dialogs throw a `ProcessException` on Windows; that's exactly how Save As / Open /
  Export shipped broken there through v0.5.3. The helper keeps AppleScript on macOS and uses
  `file_picker` everywhere else. Same rule for revealing files: use `revealInFinder(path)` +
  `revealInFinderLabel` from that file, never an inline `Process.run('open', ['-R', …])` —
  Windows needs `explorer /select,` with backslashes (and `explorer` exits nonzero even on
  success, so don't treat its exit code as failure).
- **Never put `onDoubleTap` on an ancestor of interactive controls.** A real
  `DoubleTapGestureRecognizer` HOLDS the gesture arena for `kDoubleTapTimeout` (~300 ms) after
  every tap-up, so every button inside the detector fires that late — this was the v0.6 M/S/R
  "100–400 ms lag" on track headers and mixer strips (misdiagnosed twice before; the engine lock
  fix in #85 was a real but separate lag). Detect double-click manually instead: keep a
  `DateTime? _lastTapAt` and compare in `onTap` against `kDoubleTapTimeout` (see
  `track_header.dart` / `track_mixer_strip.dart`; regression test =
  `test/widgets/track_buttons_latency_test.dart`). Bonus: the first click of a double-click then
  fires `onTap` immediately instead of being swallowed. `onDoubleTap` on a *leaf* widget with no
  interactive children (fader reset, name-rename) is fine.
