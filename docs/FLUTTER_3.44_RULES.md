# Flutter 3.44 / Dart 3.12 — what changed for Boojy

Boojy Audio is a **macOS/Windows desktop** app (Flutter + a Rust engine over FFI). This doc
records what the 3.44/3.12 upgrade actually meant for *this* project, and why we made the calls
we did. It is the "why"; the **enforced rules live in [`../CLAUDE.md`](../CLAUDE.md)** (that's the
file an AI session actually loads — this one is for humans).

> Heads-up: much of the public 3.44 advice targets mobile (iOS SwiftPM, Android Hybrid
> Composition). Most of it does not apply to a desktop DAW. Verify against this project before
> acting on a generic "3.44 best practices" list.

## Toolchain

- Pinned to **Flutter 3.44.0 / Dart 3.12** via **FVM** (`ui/.fvmrc`). Run `fvm flutter …` /
  `fvm dart …` from `ui/`. CI pins the same version through `FLUTTER_VERSION` in
  `.github/workflows/*.yml` — keep the two in sync.
- `build.sh` is unaffected (it only drives `cargo` for the Rust engine).

## Real breaking changes we hit (and fixed)

- **`IconData` is now `final`.** Packages that `extends`/`implements IconData` no longer compile.
  This broke `phosphor_flutter` (latest is `2.1.0`, ~2 years stale, no fix). Phosphor was already
  disabled at runtime (`usePhosphor = false`), so we **removed it** and made
  `ui/lib/theme/boojy_icons.dart` Material-only — zero visual change. Icons stay behind the `BI`
  facade. Don't add another `IconData`-subclassing icon package.
- **`onReorder` is deprecated** in favour of **`onReorderItem`**, which adjusts `newIndex` for the
  removed item itself. Migrated `ui/lib/widgets/fx_chain/fx_chain_view.dart` and dropped the manual
  `newIndex--` adjustment.
- **Dart 3.12 formatter** rewrote a handful of files (whitespace only) — expected; CI's
  `dart format --set-exit-if-changed` enforces it.

## Deliberately deferred — revisit when…

| Topic | Decision | Revisit when |
| --- | --- | --- |
| `material_ui` / `cupertino_ui` standalone packages | **Stay on `package:flutter/material.dart`.** The packages are preview (`material_ui` is `0.0.1`, "Coming soon") and the in-SDK imports are **not** deprecated in 3.44 — migrating now would bet ~170 files on a preview package. | `material_ui` ships a stable (≥1.0) release **and** the in-SDK imports start emitting deprecation warnings. |
| SwiftPM (default for new iOS/macOS projects in 3.44) | **Keep CocoaPods.** Do not run `flutter config --enable-swift-package-manager`. | `window_manager`, `desktop_drop`, and `screen_retriever_macos` all ship SwiftPM support (today `flutter pub get` warns they don't). |
| Dart 3.12 private named parameters | **Allowed, not mandated.** Fine for new constructors; no mass refactor. | n/a — use at your discretion. Primary constructors stay off (experimental). |

## Not applicable to this project

- **Android Hybrid Composition / SurfaceControl** — no Android target, no Maps/WebView platform
  views. (The macOS `VST3PlatformView` is unrelated.)
- **Impeller migration** — already the macOS default; nothing to do.
- **iOS / CocoaPods-vs-SwiftPM troubleshooting** — no iOS target ships.

## The auto-generated SwiftPM scaffolding

Building on 3.44 adds a `FlutterGeneratedPluginSwiftPackage` reference and a "Prepare Flutter
Framework" pre-action to `ui/macos/Runner.xcodeproj`. This is Flutter-generated and hybrid
(CocoaPods still resolves the plugins above). Leave it in place; don't hand-edit it.
