# Dogfood notes — 2026-06-11 (testing released v0.6.0, scoping v0.7)

Tyr's friction list from a hands-on session with v0.6.0, organised for the v0.7 review chain.
Cross-reference at triage with the upcoming ui-ux + feature-gap reviews; agreement = strong signal.
Code-level facts in §F were verified 2026-06-11.

---

## A. Bugs / broken behaviour

1. **MIDI hot-plug** — connecting a MIDI device mid-session doesn't auto-connect (works if
   plugged before launch); even after selecting it in Settings it "doesn't always work".
   See §F2 — rescan only fires on app-refocus/arm (plugging in USB doesn't unfocus the app, so
   it effectively never fires), and device selection is **by index**, which goes stale when the
   port list changes. v0.7 fix direction: poll port names every ~2 s + select by stable name/id.
2. **Zoom (arrangement + piano roll)** feels buggy. ⚠ Deliberate process: do NOT just fix —
   Tyr wants a joint DAW-comparison session to spec the target behaviour first (see §C1).
3. **Piano roll: making notes taller is buggy** (note-height / vertical zoom resize).
4. **Piano roll: resize-vs-move conflict** — cursor shows the `<|>` resize state but the drag
   moves the note instead. "Really frustrating" — hit-zone/priority bug, high annoyance.
5. **Add-effect [+] popup appears far to the right** of the button (screenshot on file).
   §F5: the chain's add-UI isn't a `showMenu` — repro + locate the actual widget first.
6. **Editor at reduced height overflows** ("BOTTOM OVERFLOWED BY 18 PIXELS" on synth + EQ).
   Direction chosen at triage — see brainstorm §C3.
7. **Sampler: loaded sample's waveform doesn't start at the very left** of the editor.
8. **Default track colors are off-palette** — confirmed §F3: defaults come from a separate
   9-entry `categoryColors` map (+ a legacy 8-color list), while the picker offers the 16-color
   `manualPalette`. Rule Tyr wants: defaults may ONLY be colors from the 16 selectable.
9. **Wordmark "▲udio" click opens Settings** (transport_bar.dart:727) — wrong, raised before.
   Decide: logo → Start screen (home); project name → inline rename; Settings via gear only.
   Keep the red-triangle engine-health indicator behaviour when redesigning.
10. **Library**: no pointer cursor over clickable folders; "+ Add Folder" has no hover/press
    animation.
11. **Windows in-app updater is unwired** (§F1) — `isSupported` claims Windows but there is no
    Windows MethodChannel implementation. "Check for Updates" on Windows likely no-ops.

## B. Design changes wanted (direction known, needs design pass)

1. **Recover-backup dialog**: the project box looks like a button but isn't — restyle as a flat
   "file card" (icon, name, relative time, maybe track count); Recover Backup = filled accent
   with hover brighten + slight grow; Discard = quiet text button. Tablet-ready: ≥44 px targets,
   press = scale 0.97.
2. **Dropdowns app-wide** (Settings Theme/UI Scale are "really chunky"; dropdowns generally not
   nice). Direction: unify on **black-filled value chips** (same family as the transport time
   readout) + one shared compact menu panel (26 px rows, checkmark on current). Mockups shown
   to Tyr 2026-06-11 — awaiting pick (quiet-text vs outline-pill vs filled-chip).
3. **Quantize is a one-shot but dressed as a toggle** — restyle to the existing *action* button
   role (glyph + press-flash, no persistent outline), keep the `▾` split for options. Notes
   visibly snapping is the real feedback.
4. **Right-click menus** (clips, mixer) feel large/clunky — tighten to 24 px rows, leading
   icons, hairline separators, ~180 px wide; same panel chrome as the new dropdown menu (one
   popup system everywhere). Alternative considered: icon-strip header + short list.
5. **Bar-ruler [-][+]**: remove the grey background; ghost glyph buttons at full height of the
   bar-number/loop row, hover fill.
6. **Piano-roll toolbar value chips**: Start / Length / Signature should all be black-filled
   value chips (like transport time), same height — Signature currently taller/larger than the
   others. (Same visual system as B2.)
7. **Hover/motion language app-wide** ("make the app feel more alive", slight space feel):
   spec proposed to Tyr — hover +5% lightness 120 ms + pointer cursor; press scale 0.97;
   one-shots flash accent 150 ms; grow-on-hover only for discrete buttons (≤1.02), never list
   rows; tablet = press states carry it. ⚠ Tyr wants visual suggestions run by him first.
8. **Tooltips, Affinity-style, consistent throughout** — title + one-line explanation +
   shortcut in a themed dark panel (a `BoojyTooltip` wrapper). Priority: Quantize, Legato,
   Snap, M/S/R, transport. (Feature-gap review already flagged M/S/R.)
9. **Top-bar overflow**: when narrow, metronome loses its "1 bar" companion — add access to the
   hidden control (Tyr's idea: right-click → dropdown; counter-proposal: trailing `»` overflow
   chevron, which is discoverable and tablet-friendly; right-click as bonus).
10. **Synthesizer visual overhaul** — restyle in the EQ's image: visual area on top (live
    waveform), labelled knob row beneath (same metrics as EQ's Freq/Gain/Focus), waveform type
    as 4 segmented icons instead of a chunky dropdown. Goal: a shared **"Boojy device chrome"**
    (header glyph+name+power dot / visual / knob row) that Synth, Drum Kit, Sampler, EQ all
    follow, giving Boojy instruments a distinct consistent look.
11. **Settings page** generally less clean than the rest of the UI — small tweaks only:
    new dropdown style, consistent row heights/section headers, match panel chrome.

## C. Open brainstorms (decide at triage)

1. **Zoom spec session** — Tyr compares DAWs directly and fills a behaviour checklist; then we
   spec Boojy's zoom and implement to spec. Checklist to cover, per DAW (Ableton / FL / Logic /
   GarageBand): scroll-wheel zoom anchor (under cursor vs playhead vs left edge), modifier keys
   (Cmd/Alt+scroll), pinch behaviour, drag-on-ruler zoom, zoom-to-fit shortcut, H/V zoom
   independence, smoothness/step size. Output: "Boojy zoom spec" → one PR.
2. **Sampler research** — Tyr tries other DAW samplers (likes/dislikes) before the v0.7 sampler
   fix. Already agreed in: waveform-at-left bug (A7), Start/Length chips like piano roll.
3. **Editor min-height** — options: (a) hard min-height clamp only; (b) internal scroll;
   (c) devices adapt to a compact floor (graph collapses first — EQ partially does this), THEN
   hard min stops further shrink. Recommendation: (c); avoid scroll-in-scroll (bad on tablets).

## D. v0.7 candidate features (Tyr's asks)

1. **Capture MIDI** (Ableton-style retrospective record) — rolling engine-side MIDI buffer,
   button materialises the last phrase into a clip. Beginner-perfect ("you played it, it's
   saved"). Strong v0.7 candidate, cheap memory cost.
2. **Capture Audio** — same idea for audio input (Cubase has "audio pre-record"; rare feature,
   genuine differentiator). ~23 MB/min stereo buffer is fine; needs care on expectations
   (armed/monitored tracks only + clear indicator). Recommend: prove Capture MIDI UX in v0.7,
   audio version v0.8.
3. **Legato** — piano-roll one-shot button next to Quantize, same action style (extend each
   selected note to the next note's start). Small.
4. **EQ: live spectrum behind the curve** — engine FFT tap → FFI ring buffer → ~30 fps paint.
   Medium. Part of "get EQ really good".
5. **Reverb quality pass** — after EQ; v0.7 device-theme fit.
6. **Sampler fix package** (A7 + Start/Length + findings from C2).
7. **Auto update check** — §F1: macOS Sparkle auto-check is effectively already on (default);
   surface a Settings toggle ("Check automatically") + "every X days" if wanted; wire Windows
   (currently dead).
8. **Virtual piano** — ALREADY SHIPPED (§F6): View menu toggle + transport piano button,
   computer-keyboard musical typing, octave shift Z/X, sustain Shift. If Tyr couldn't find it,
   that's a discoverability issue, not a missing feature.

## E. Strategy calls

- **Languages/i18n → v1.0**, not v0.7 (Tyr's call, agreed: features-complete + low bugs first).
- **Linux** — moderate port (midir/cpal/Flutter all support it) but real cost is a third
  release/smoke matrix while the Windows updater isn't even wired. Recommend NOT v0.7; revisit
  at v0.8 if users ask.
- **Web** — effectively a different product (engine→WASM, AudioWorklet, no VST3, file-system
  story). v0.9+ strategic question, not a milestone item.
- Emerging v0.7 theme candidate (pre-review): **"Devices & Feel"** — sampler/synth/EQ/reverb
  quality + capture MIDI + interaction polish (hover language, dropdowns, tooltips, menus).
  Let the ui-ux + feature-gap reviews confirm or challenge.

## F. Verified facts (code-checked 2026-06-11)

1. **Updates**: UI = start-screen bottom bar, Settings "Updates" tab, menu bar — all call
   `UpdaterService.checkForUpdates()` (`ui/lib/services/updater_service.dart`, MethodChannel).
   macOS = Sparkle via hand-written Swift wrapper (`ui/macos/Runner/SparkleUpdater.swift`,
   `SPUStandardUpdaterController(startingUpdater: true)`) → Sparkle's own background check on
   launch is ON by default; `setAutoCheck/getAutoCheck` already exposed. Download+install is
   the full native Sparkle flow, not a link. **Windows: declared supported but no Windows-side
   MethodChannel implementation exists** (`ui/windows/runner/` has no updater code).
2. **MIDI**: engine uses midir (`engine/src/midi_input.rs`); no OS hot-plug callback — explicit
   `refresh_devices()` reconnects when the port list changed (lines 170-186). Flutter triggers:
   app-refocus (`daw_screen.dart:380`), track-arm (`daw_screen.dart:3632`), Settings rescan
   button (`app_settings_dialog.dart:977`). Selection = `selectMidiInputDevice(index)` —
   **index-based, goes stale across rescans** (likely the "linked but doesn't work" cause).
3. **Track colors**: picker = `TrackColors.manualPalette` (16, `ui/lib/utils/track_colors.dart:34`);
   new-track default = `TrackColors.categoryColors` (9 semantic colors) via `detectCategory()`
   (`ui/lib/controllers/track_controller.dart:138`); legacy 8-color `palette` also live. Lists
   don't match → A8.
4. **Wordmark**: `transport_bar.dart:727` `onTap: onAppSettings` (tooltip 'Settings'); triangle
   doubles as engine-health indicator (red on engineFailed).
5. **Add-effect [+]**: no `showMenu`/RelativeRect in the chain code — inline
   `_buildAddEffectMenu` column (`effect_parameter_panel.dart:601`) or `showFxPickerDialog()`
   (AlertDialog). The far-right popup in the screenshot needs a repro to locate the widget.
6. **Virtual piano**: fully present + active (`ui/lib/widgets/virtual_piano.dart`; rendered when
   `uiLayout.isVirtualPianoEnabled`, toggled via View menu / transport `_toggleVirtualPiano`).

## G. Process notes

- Staged `_screenshots/` PNGs were captured 2026-06-10 morning — **before** the final bug-hunt
  fixes merged and the v0.6.0 tag. Retake on the installed v0.6.0 build before running the
  ui-ux review (same 13 filenames). The only certain-v0.6.0 capture is
  `docs/screenshots/screenshot_v0.6.0.png`.
- Sequence: Tyr confirms/extends these notes → retake screenshots → ui-ux review → feature-gap
  review (pass priorThemes) → triage together → `docs/plans/v0.7-plan.md`.
