---
paths:
  - ui/lib/**
  - ui/macos/**
  - ui/pubspec.yaml
---

# Flutter UI rules

Flutter is pinned in `ui/.fvmrc`. Much public Flutter advice targets mobile (SwiftPM, Android,
iOS); check it applies to this macOS/Windows desktop app before acting on it.

## Platform and packages

- **Keep `package:flutter/material.dart` imports.** Don't move to the preview `material_ui` /
  `cupertino_ui` packages until they're stable and the in-SDK imports are deprecated.
- **Icons are Material-only, via the `BI` facade** (`theme/boojy_icons.dart`). No icon packages:
  `IconData` is `final`, so packages that extend it don't compile.
- **Plugins use CocoaPods, not SwiftPM.** Don't enable SwiftPM until `window_manager`,
  `desktop_drop` and `screen_retriever_macos` support it. Leave the generated
  `FlutterGeneratedPluginSwiftPackage` scaffolding alone.
- **macOS: the transport bar is the only top chrome.** The native title is hidden
  (`TitleBarStyle.hidden`, traffic lights kept); the bar insets its left edge past the lights and
  drops the inset in full screen. Don't re-enable the native title bar or add a title strip.
- **Reorderable lists use `onReorderItem`** (it already adjusts `newIndex`; don't decrement it).
- Private named parameters are fine in new constructors; primary constructors stay off.

## Shared surfaces (one of each)

- **Menus:** every picker and context menu goes through `showBoojyMenu<T>()`
  (`widgets/shared/boojy_dropdown.dart`); `BoojyDropdown<T>` is the standard trigger;
  right-click goes through `ContextMenuHelper`. Never `showMenu` / `PopupMenuButton`. Pass
  `selectedValue: null` for context menus.
- **Notices:** `Notices.info(text)` for a hint after an action that did nothing (fades after
  3 s); `Notices.problem(text, {id, action, error})` for something that went wrong (stays until
  closed or `Notices.clear(id)`). Never `SnackBar`, no status line, **never post success**.
  Plain words on screen; pass the exception as `error:` so it goes to the log. Posting needs no
  `BuildContext`. The look is settled (neutral pill, amber ⚠ only).
- **File dialogs and reveal:** `utils/native_dialogs.dart` (`pickFolder`, `pickSaveFilePath`,
  `sanitizeFileName`, `revealInFinder`). Never inline `osascript` or `open -R`: they broke Save As,
  Open and Export on Windows.
- **Zoom:** `shared/editors/anchored_zoom.dart`'s `zoomAnchored`. Set zoom and scroll the grid and
  its ruler in the same call; never correct scroll in a post-frame callback (one-frame wobble).
- **Menu bar:** `StableMenuBar` (`widgets/shared/stable_menu_bar.dart`), never a bare
  `PlatformMenuBar`: the plain one resends every menu on every rebuild, which closes an open
  macOS menu. Also avoid `notifyListeners()` from pollers when nothing changed.
- **Logging:** `Log.d()` / `Log.e()` / `Log.i()`, never `print()`.
- **UI state:** `provider`, used lightly. Riverpod is a planned migration, not a casual swap.
- **`ui_layout.json`** fields go through `ProjectPersistence.collect()` / `applyUILayout()`.

## Gotchas that caused real bugs

- **Never read `context.colors` inside an event handler** (onTap, a menu `.then`, a dialog
  callback). It's a listening `Provider.of`: in debug the handler dies silently, so the action
  just doesn't happen. Use `context.themeProvider.colors` or capture colours in `build()`.
  `test/lint/provider_listen_guard_test.dart` guards it.
- **Never combine `Border.all` + `borderRadius` + `clipBehavior` on one Container**: the clip
  shaves the border at the corners. Use a bordered box with no clip and an inner `ClipRRect`.
  Moving Container → `DecoratedBox` loses the border inset, so child fills cover the stroke; use
  `DecoratedBox(position: DecorationPosition.foreground)` for bordered boxes with filled children.
- **Never put `onDoubleTap` on an ancestor of buttons.** The recogniser holds every tap ~300 ms
  (the old M/S/R lag). Detect double-click manually with a `_lastTapAt` timestamp (see
  `track_mixer_strip.dart`). `onDoubleTap` on a leaf widget is fine.
- **Timeline coordinates:** track rows and clips live inside the horizontal scroll view, so their
  `localPosition.dx` is already content space: never add the scroll offset. The ruler and
  `findRenderObject()` drag-ghost maths are outside it (viewport space), where `+ scrollOffset` is
  right. The ruler (`UnifiedNavBar`) is content-width inside its scroll view: never add the
  offset to its local x. Check which render box a position is relative to before adjusting.
- **`timeline_view.dart` uses part files** (`timeline_gesture_layer.dart`,
  `timeline_track_list.dart`): import `timeline_view.dart` only.
- **`daw_screen.dart` and its mixins: one copy per method.** `_DAWScreenState` mixes in
  `DAWClipMixin` etc. Logic goes in the mixin under a public name and the screen calls that; the
  screen keeps only what needs screen-only state (build, lifecycle, start screen, Close Project).
  Never add a private `_` copy of a mixin method: the copies drifted apart (54 were removed in October 2026).
- **Transport bar layout:** `_SingleRowLayout` (`transport_bar.dart`) sizes everything from the
  window width, never the project name, and the centre never scales. If a centre button's width
  changes, `test/widgets/transport_bar_density_test.dart` fails: re-measure `_kWellWidths` with
  real fonts, don't loosen the test.
- **One icon per track type** (`TrackIcons.forType`, `utils/track_icons.dart`): MIDI piano, Audio
  waveform, Master headphones. No per-track picker, no guessing from the name; old `track_icons`
  keys in `ui_layout.json` are ignored on load. No emoji in track chrome.
- **Bundled samples** (`ui/assets/samples/drums/`) are copied to app support on first use by
  `services/bundled_content_service.dart`; the engine loads them by path. Bump `contentRevision`
  when bundled content changes.

## When changing a widget

Check every call site before changing its API, keep other panels working, test at small and
large window sizes, and treat `CustomPainter` changes as timeline-wide. Render new UI to PNG
before handing it over (`test/helpers/render_preview.dart`).
