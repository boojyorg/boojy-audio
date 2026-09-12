# Dropdown / Menu Unification (B2) — Migration Plan

> Read-only audit (2026-06-16, 7-area workflow, 83 raw sites → ~60 distinct) to plan v0.7
> Slice 3 item **B2**: one shared "filled value chip + themed compact menu" system, built with
> two visual variants behind the `Cmd+Shift+D` dev switcher for a live A/C pick.

The sites collapse into four shapes: **value dropdowns** (pick one value from a list),
**split-buttons** (toggle/action on the left, value-menu on the right), **context menus**
(right-click icon·label·shortcut rows), and **settings controls** (knobs, segmented pills, color
grids — mostly *not* menu-shaped). The plan builds one shared `BoojyDropdown<T>` + one themed menu
surface, ships behind the `Cmd+Shift+D` A/C switcher on 2–3 showcase sites first, then batches the
rest.

---

## 1. Inventory by kind

### Value dropdowns (pick-a-value)

| Site | File:line | Visible | Mechanism |
|---|---|---|---|
| Sampler Root Note (88 notes) | `sampler_editor/sampler_controls_bar.dart:324` | contextual | custom overlay (scroll list — keep) |
| CC type selector | `piano_roll/piano_roll_cc_lane.dart:142` | contextual (lane open) | bespoke showMenu |
| Clip-automation parameter | `piano_roll/piano_roll_clip_automation_lane.dart:255` | unrendered (flag off) | bespoke showMenu |
| Audio Editor Signature | `audio_editor/audio_editor_controls_bar.dart:272` | contextual | bespoke showMenu |
| Device name-tap (Instrument) | `device_chain/device_chain_view.dart:458` | contextual | bespoke showMenu |
| Device name-tap (Effect) | `device_chain/device_chain_view.dart:482` | contextual | bespoke showMenu |
| Add Effect `[+]` menu | `device_chain/device_chain_view.dart:1624` | contextual | bespoke showMenu |
| Add Effect hint placeholder | `device_chain/device_chain_view.dart:1538` | contextual (empty state) | bespoke showMenu |
| Mixer Automation parameter | `track_mixer_strip.dart:505` | contextual (automation on) | Material DropdownButton |
| Mixer Audio Input chip | `track_mixer_strip.dart:1066/1067` | contextual (audio track) | **custom overlay (live meters — keep)** |
| Synth waveform type | `synthesizer_panel.dart:129` | contextual | Material DropdownButton |
| VST3 Preset name (PresetNav) | `preset_nav.dart:42` | unrendered (`_shouldShowPresetNav`=false) | custom overlay (animated browser — keep content) |
| Scale Root / Type (sidebar) | `piano_roll/piano_roll_scale_controls.dart:93/101` | **unrendered (dead — sidebar never mounted)** | CompactDropdown |
| **Time signature** (transport + PR bar) | `transport_bar/signature_dropdown.dart:45/46` | always | bespoke showMenu **+ drag-to-scrub** |
| App: Theme / UI Scale | `app_settings_dialog.dart:422/454` | contextual (dialog) | Material DropdownButton (`_appearanceRow`) |
| App: Audio Driver / Output / Input / Buffer / MIDI / Auto-save | `app_settings_dialog.dart:604/1097/829/986/907/1297` | contextual (dialog) | Material DropdownButton |
| Project: TimeSig N/D, Root, Scale, Sample Rate | `project_settings_dialog.dart:553/591/629/667/697` | contextual (dialog) | Material DropdownButton (`_buildDropdown`) |
| Export: MP3 Bitrate / WAV Depth / Sample Rate | `export_dialog.dart:952/966/980` | contextual (dialog) | Material DropdownButton (`_buildDropdownRow`) |
| Capture MIDI duration | `capture_midi_dialog.dart:109` | contextual (dialog) | Material DropdownButton |
| **CompactDropdown (shared)** | `shared/compact_dropdown.dart:19` | — | bespoke showMenu (**the migration seed**) |

### Split-buttons (toggle/action + value-menu)

| Site | File:line | Visible | Left zone semantics |
|---|---|---|---|
| Transport Snap | `transport_bar/snap_split_button.dart:92` | always | **toggle** (on/off) |
| Transport Metronome (count-in) | `transport_bar/metronome_split_button.dart:79` | always | **toggle** (PNG icon) |
| Transport Loop (punch) | `transport_bar/loop_split_button.dart:60` | always | **toggle** + conditionally-rendered right zone, multi-select overlay |
| PR Snap | `piano_roll/piano_roll_controls_bar.dart:428` | always | **toggle** (stateful overlay: radio+Triplet) |
| PR Quantize | `piano_roll/piano_roll_controls_bar.dart:610` | always | **action flash** (240ms, not persistent) |
| Audio Editor Warp Mode | `audio_editor/audio_editor_controls_bar.dart:492` | contextual | **toggle** (two-line menu items — keep overlay) |
| Tempo BPM zone (tap-tempo) | `transport_bar/tempo_controls.dart:273` | always | **not a menu** — exclude |
| KnobSplitButton (shared) | `shared/knob_split_button.dart:14` | contextual | right zone = **knob popover, not a list** — exclude |

### Context menus (right-click rows)

| Site | File:line | Mechanism |
|---|---|---|
| Note menu (`showNoteContextMenu`) | `context_menus/note_context_menu.dart:13` | **ContextMenuHelper + ContextMenuItem (ready)** |
| Clip menu (`showClipContextMenu`) | `context_menus/clip_context_menu.dart:15` | **ContextMenuHelper + ContextMenuItem (ready)** |
| TrackHeader | `track_header.dart:79` | bespoke showMenu (no shortcut col, error-color Delete) |
| TrackMixerStrip / Master | `track_mixer_strip.dart:1199/2002` | bespoke showMenu (+ Send-to-Return items @1366, color-picker substep) |
| Device instrument / effect | `device_chain/device_chain_view.dart:612/516` | bespoke showMenu (Float/Embed, Bypass) |
| Device dropdown helper | `device_chain/device_dropdown.dart:11` | bespoke showMenu (**needs section-header variant**) |
| Library item / VST3 / user folder | `library_panel.dart:1501/1609/790` | bespoke showMenu (folder one lacks `listen:false`) |
| Record count-in / new-track | `transport_bar/record_controls.dart:86`, `transport_bar.dart:317` | bespoke showMenu |
| Time ruler / empty track / drag-create-track | `timeline/timeline_context_menus.dart:119/228/338` | bespoke showMenu (inline rows, no shared helper) |

### Settings controls (NOT menu-shaped — mostly out of scope)

| Site | File:line | Verdict |
|---|---|---|
| Scale toggle (PR bar) | `piano_roll/piano_roll_controls_bar.dart:377` | pure on/off → filled-chip **toggle** only |
| Send amount knob | `track_mixer_strip.dart:645` | drag knob — exclude |
| Track icon+color picker popup | `track_mixer_strip.dart:933` | bespoke combined overlay — exclude |
| Track color picker dialog | `track_mixer_strip.dart:1435` / master `:2057` | modal grid (dup'd) — exclude, extract later |
| Version Type pill-selector | `project_settings_dialog.dart:225` | segmented control — **out of scope** |
| Buffer Size preset list | `dialogs/latency_settings_dialog.dart:36` | radio-list dialog — exclude, match item style only |
| Input selector overlay (live meters) | `input_selector_dropdown.dart:10` | stateful polling overlay — **trigger migrates, content stays bespoke** |
| PresetBrowserDropdown | `preset_browser_dropdown.dart:25` | search+tree panel — **content stays bespoke** |

---

## 2. Showcase sites for the live A/C comparison (build these FIRST)

Goal: **always-visible**, **single-tap → flat value list** (no drag, no live state, no toggle) so
`Cmd+Shift+D` shows Quiet-A vs Two-tone-C instantly. **Caveat: no always-on value dropdown is
clean** (the only always-visible one, time-sig, has a drag gesture). The picks below are all one
interaction away from view.

- **Pick 1 — Audio Editor Signature (`audio_editor_controls_bar.dart:272`)** — clean tap→showMenu,
  already reads colors `listen:false`, already draws a check on the selected item (Variant C
  half-built). Visible when an audio clip is open in the editor.
- **Pick 2 — CC type selector (`piano_roll_cc_lane.dart:142`)** — already the right shape (dark
  fill + caret + short label), flat enum list, `listen:false` guard in place, no bespoke gesture.
  Short label = obvious caret-well (C) vs muted-caret (A) read. Visible once a CC lane is toggled.
- **Pick 3 (anchor) — CompactDropdown itself (`shared/compact_dropdown.dart:19`)** — the seed
  widget. Reskinning it to support both variants is **zero production risk** (only consumers are
  the dead scale sidebar) and is the cleanest place to build the two skins.

**Bad showcases — do NOT lead with these:** Time signature (drag-to-scrub = highest risk);
Tempo/Send-knob/KnobSplitButton/Version-pill (not menus); Scale sidebar / Clip-automation /
PresetNav / Add-Effect placeholder (unrendered/gated); Audio Input chip (live meters — menu can't
be the shared surface).

---

## 3. Proposed shared-widget API

```dart
BoojyDropdown<T>({
  required T value,
  required List<BoojyMenuItem<T>> items,   // value + label + optional leading icon + enabled
  required ValueChanged<T> onChanged,
  String Function(T)? itemLabel,           // label transformer ('N Hz', 'N samples (Xms)', etc.)
  Widget Function(T)? triggerBuilder,      // override chip content (LCD mono, '★' prefix, badge)
  IconData? leadingIcon,                   // chip glyph; asset-icon caveat below
  String? caption,                         // 'Type' / 'Snap' style label
  double? width,                           // fixed-width sites (52px scale, 220px input)
  bool enabled = true,                     // recording-lock, single-item-degrade, empty-list
  BoojyChipState chipState = .neutral,     // neutral | active(toggle) | actionFlash — split-button reuse
});
```

- `BoojyMenuItem<T> { T value; String label; IconData? icon; String? shortcut; String? trailingHint; bool enabled; bool destructive; }`
  — `shortcut`/`trailingHint`/`destructive` cover context menus + Send-to-Return + error-color Delete.
- `BoojyMenuSection(label)` sentinel for the **Device dropdown BUILT-IN / PLUGINS headers** (the one
  structural gap in `ContextMenuItem` today).
- **Variant marking is internal to the menu surface**, not a per-item flag: Variant A draws a thin
  left accent bar on the current-value row; Variant C draws a trailing check. The chip's right side
  switches *muted caret* (A) vs *darker caret-well* (C). Callers never know which variant is live.

**Variant reaches deep call sites via an `InheritedWidget` scope (`BoojyMenuTheme`)**, not a
threaded param — mounted once near the app root, holding `variant: quietA | twoToneC`,
`Cmd+Shift+D` flips it (mirrors the `Cmd+Shift+L`/`Cmd+Shift+E` dev switchers). Threading a param
through ~60 sites (many 3–5 widgets deep behind callbacks) would be churn-heavy and miss sites.

**Context-menu reuse:** re-point `ContextMenuHelper.show` + `ContextMenuItem` at the **same
menu-surface** `BoojyDropdown` opens. Deltas to land: add `destructive`, add `BoojyMenuSection`
headers, migrate the bespoke-inline menus (timeline, track header, library, device) onto
`ContextMenuItem`. Context menus share the *surface*, not the *trigger*.

---

## 4. Migration batching

- **Batch 0 — Foundation + Showcase (behind `Cmd+Shift+D`).** Build `BoojyDropdown<T>` +
  `BoojyMenuTheme` scope + both variant skins + shared menu surface. Migrate **CompactDropdown
  (zero risk), Audio Editor Signature, CC type selector**. Stop for Tyr's walkthrough pick before
  going wide.
- **Batch 1 — Material→shared dropdowns (mechanical).** All `Material DropdownButton` via shared
  helpers (`_appearanceRow`, `_buildDropdown`, `_buildDropdownRow`), Capture MIDI, Synth waveform,
  Mixer Automation param. **Preserve load-bearing item text** (latency badges, 'N Hz', quality
  hints, Bluetooth warning, `__no_output__` sentinel, index-keyed MIDI devices).
- **Batch 2 — Device-chain + library menus.** Device name-tap (real chip trigger), Add-Effect `[+]`
  + placeholder (**keep the `RelativeRect.fromRect` A5-drift fix — don't revert to `fromLTRB`**),
  Device dropdown helper (needs `BoojyMenuSection` first), library context menus → `ContextMenuItem`
  (+ add the missing `listen:false` to the user-folder one).
- **Batch 3 — Timeline + track + record context menus.** Time ruler / empty-track / drag-create
  (keep the drag trigger, migrate only the menu; keep `colors.elevated` override), TrackHeader,
  TrackMixerStrip/Master (+ Send-to-Return dynamic items, color-picker substep), Record
  count-in/new-track. Note/Clip menus already on `ContextMenuHelper` — confirm surface match. Carry
  **error-color Delete** via `destructive`.
- **Batch 4 — Bespoke / care-required (last, partly deferred).** Split-button toggles (Snap,
  Metronome, Loop, PR Snap/Quantize, Warp) adopt the chip *skin* only — two-zone split, toggle/
  action-flash state, stay-open stateful overlays, and PNG icons stay bespoke (`chipState` covers
  colour only). Time-sig drag-to-scrub: migrate the tap-menu, keep the scrub gesture + undo
  coalescing. Live-meter/animated content (Audio Input, input selector, PresetBrowser, Sampler
  88-note): trigger chip migrates, menu content stays bespoke.

**Gated on Tyr homework — defer:** **B9 overflow** (don't finalise chip width/shed until the
responsive-shed spec lands) · **B7 hover** (chip hover-fill follows the hover spec, not invented
here) · **C1 zoom** (geometry assumptions wait). Unrendered/flag-gated (PresetNav, Clip-automation,
Scale sidebar) — migrate opportunistically only.

---

## 5. Risks & gotchas

- **Provider-listen-in-handler (recurring).** `context.colors` from an `onPressed`/`.then()`/menu
  callback throws "listen outside build" — debug-only assert, swallowed by `UndoRedoManager`, so
  the action *silently does nothing* (the v0.5.1 right-click-Delete bug). Resolve colors in
  `build()` or the menu's overlay build context, never in the value-changed handler. **Known
  offender to fix during migration: user-folder library menu (`library_panel.dart:790`).**
- **CompactDropdown's safe-by-accident path** reads colors in the *item builder* (overlay context),
  not the handler — safe today; lock it down when reskinning.
- **Track-lock deadlock (engine, indirect).** Send-to-Return / Delete / Duplicate / Convert paths
  must snapshot ids before re-entering `TrackManager` (`parking_lot::Mutex` non-reentrant, silent
  freeze). UI-only migration won't introduce it — don't restructure send-routing in passing.
- **Asset-icon vs `IconData`.** `metronome.png` / `magnet.png` are `Image.asset`-coloured; if
  `leadingIcon` only takes `IconData`, those split-buttons need the `triggerBuilder` escape hatch —
  no glyph swap without Tyr's sign-off.
- **Anchor-positioning.** Don't let a "unify position math" pass revert Add-Effect's
  `RelativeRect.fromRect` (the A5 fix); overlay sites using `CompositedTransformTarget/Follower`
  (Loop punch, PresetNav, ViewMenu) track on scroll — a naive `Positioned` swap loses that.
- **`destructive` / section-header gaps.** `ContextMenuItem` has neither today — build both into the
  item model in Batch 0 so later batches are pure data.
- **Dead/debug noise.** Clip-automation + CC-lane carry `Log.d` instrumentation; the Effect context
  menu has a likely copy-paste bug (same `BI.lightning` for Bypass + Enable, `device_chain_view.dart:~537`).
  Clean up when touching those files.
