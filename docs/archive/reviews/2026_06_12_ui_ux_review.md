# Boojy Audio — UI/UX Review & Design Direction

**Date:** 2026-06-12
**Version under review:** v0.6.0 (the running build)
**Scope:** UI/UX only — visual language, token hygiene, layout, consistency, responsiveness, and a competitive read against GarageBand, Ableton Live, FL Studio, and Logic Pro. Plus a proposed next milestone. **Out of scope:** audio engine, the synth/drum sound design itself, and Sparkle/release plumbing.
**How this was produced:** a multi-agent pass — readers over the Flutter UI source by area (theme/tokens, top bar, transport/time, piano roll, timeline, mixer, effects/devices, chrome+settings), four competitive DAW teardowns, then synthesis into a bug ledger, a design direction, ASCII mockups, and a milestone plan. **Grounded against eight owner screenshots** staged in `docs/reviews/_screenshots/` (demo-project, piano-roll, mixer, effects-chain, eq-effects, sampler, drum-kit, settings, startup, new-project). The visual judgements below were checked against those real pixels.

---

## 1. Verdict

**Grade: B−.** The previous cycle's promise (one cool temperature, real type scale, a coherent dark shell) has largely landed — the "healthy" surfaces genuinely look like a premium instrument. The demo-project screenshot reads as a real DAW: dense well-coloured clips, a calm gunmetal shell, vivid-but-controlled emerald meters, a Boojy-blue EQ curve. Nothing here is a redesign.

What holds it at B− rather than B+ is **follow-through, not vision**: the token system is correct but *leaks* in exactly the pockets that haven't been touched recently — the file-drop zone, the virtual-piano resize handle, the snap/quantize popups, three settings dialogs — and several of those leaks render *broken on the Light theme* (hardcoded dark-on-dark or near-white borders). On top of that sit two classes of beginner-hostile rough edge: **interaction footguns** (a ~300 ms lag on every tempo/position tap from `onDoubleTap`-on-a-tap-leaf, a fader that teleports volume on a single misclick) and **missing legibility cues a beginner relies on** (no peak-hold, no unity tick, M/S/R with no tooltips, invisible white-key separators in the piano roll).

**The single highest-leverage change is finishing theme-token propagation so the Light theme actually works** — today it is half-broken, and several "selected"/"active" states are invisible on it. Right behind it: **kill the two `onDoubleTap` latency footguns** (they make the most-touched controls feel laggy), and **add the three GarageBand-grade legibility cues** (peak-hold, unity tick, icon+tooltip M/S/R) that every beginner DAW ships and Boojy doesn't.

**What's wrong in one breath:** a token layer that's right but unfinished (Light theme breaks in the un-migrated pockets) · ~300 ms input lag on tempo/position from a documented `onDoubleTap` footgun · a mixer that's opaque to beginners (no peak-hold, no unity mark, cryptic M/S/R/I, sends in % not dB) · a piano roll whose white-key lanes have *no visible separator* and whose scale-root band shows even when the toggle is off · and the usual long tail of raw-hex / raw-`fontSize` / `clipBehavior`+`Border.all` token-hygiene drift.

---

## 2. The core diagnosis — why it doesn't fully "feel right"

Five root causes sit under almost every symptom in the ledger:

1. **The token layer is correct but unfinished — and the gaps are Light-theme-shaped.** `BoojyColors` / `BT` is well-designed (one Boojy Blue, one emerald, a clean Gunmetal ramp, `MeterColorZones` as a single source of truth). But the components that pre-date the facade or were never revisited still hardcode hex: `FileDropZone` (11 warm-grey literals), `device_box.dart`'s `#E8EAF0` selected border, the snap/quantize popups (`#2A2A2A` + `Colors.white70`), the loop-dim overlay (`0x4D000000`), the grid-painter and note-painter defaults. On **Dark** they mostly look fine by luck; on **Light** they invert to dark-on-dark or blinding-white-on-white. The theme switch silently doesn't reach these pockets. → finish propagation; make painter/popup colour params `required` or theme-sourced.

2. **Colour-temperature split personality in the un-migrated pockets.** Every healthy surface is cool gunmetal (hue ~220°). But `FileDropZone` and the `VirtualPiano` resize handle use pure neutral grey (hue 0°, `#2B2B2B`/`#505050`) that reads warmer and dirtier than the shell around it. A beginner opening the Sampler for the first time lands on a generic-grey drop target floating inside a polished cool shell — it doesn't feel like one product.

3. **`onDoubleTap` on tap-interactive leaves = ~300 ms lag on the most-touched controls.** The position display (`onTap` cycles mode, `onDoubleTap` edits) and the tempo number zone (`onVerticalDragStart` scrub, `onDoubleTap` dialog) both hold the gesture arena for `kDoubleTapTimeout` after *every* tap before acting. CLAUDE.md already documents this exact footgun (the v0.6 M/S/R latency bug) and the `_lastTapAt` fix. It shipped anyway in two more places. → replace with manual last-tap comparison.

4. **The mixer is functional but opaque** — the opposite of the GarageBand "you get it at a glance" benchmark. The fader teleports on a single `onTapDown`; there's no peak-hold tick (transients vanish before the eye arrives); no 0 dB unity mark (so beginners push everything right and clip the master); M/S/R/I are bare letters with no tooltips ("I" = input-monitor is never explained); sends read "10%" while every other volume in the app reads dB. None of this is a bug per se — it's *absence of the cues a beginner navigates by*.

5. **Three-dialect chrome + token drift in the long tail.** The transport bar still reads as three control families (loud glow transport circles · muted outline split-buttons · LCD readout tiles) with five different hover-scale magnitudes across twelve items. Settings has three eras (polished two-pane `AppSettingsDialog` · plain-form `ProjectSettingsDialog` · raw `AlertDialog` `LatencySettingsDialog`) with different backgrounds, header letter-spacing, widths, and missing `barrierColor`. Plus ~30+ raw `fontSize:` literals between the named token sizes, and the misnamed `BT.opacityFull = 0.65` that has spawned a parallel ad-hoc alpha system. Individually minor; together they're the "rough/unfinished in spots" smell.

---

## 3. Quick-win shortlist (high-impact, ≤S effort)

Do these first — most are an afternoon, and several are visible trust/legibility signals or remove real input lag. IDs map to the full ledger in §4.

**16 quick wins (≤S):** **T1, T2, T3, T4, T6, T9** (theme-token leaks + transport-amber tokens) · **N1, N3, N4** (transport metronome PNG, project-name font, undo press-state) · **X1, X2** (the two `onDoubleTap` latency footguns) · **P1, P3, P5** (piano-roll separators, root-band guard, accidentals) · **L1, L2** (selected-clip border, return-only empty prompt) · **M1, M3, M5** (fader teleport, unity tick, send-in-dB) · **E2** (bypass context-menu icon ternary) · **C1, C2** (title em-dash, dialog barrier colour).

> The two **highest-leverage trust fixes** are **X1/X2** (kill the 300 ms lag — the bar *feels* slow until this lands) and **T2/T3 + the snap/quantize popup fix (P7)** (without these the Light theme is shipping broken — selected device borders and dropdowns invert).

---

## 4. Full bug & inconsistency ledger

> **Severity** = beginner impact. **Effort:** S ≈ an afternoon, M ≈ 1–2 days, L ≈ a milestone slice. Grounded items are flagged where a screenshot confirms them.

<details>
<summary><b>Expand the full ledger</b> (id · severity · effort · area)</summary>

### Theme & tokens

- **T1** (high · S) `FileDropZone` uses 11 hardcoded warm-grey `Color(0x…)` literals — breaks on Light theme, mismatches the cool shell. → `colors.dark/divider/textMuted/textSecondary/accent` + `BT.font*`; use a `BoojyButton` for Browse. *(Sampler drop screen.)*
- **T2** (high · S) `device_box.dart:112` selected border hardcodes `#E8EAF0` (the Dark `textPrimary`) — near-white border on Light, invisible-or-blinding. → `colors.accent` (matches the selection system everywhere else).
- **T3** (high · S) `ThemeProvider.cycleTheme()` iterates `BoojyTheme.values` (4) instead of `BoojyThemeExtension.selectable` (2) — the dev shortcut lands on the two High-Contrast variants explicitly marked "render broken surfaces." → cycle `selectable` only.
- **T4** (med · S) Transport pause/stop use unthemed amber `#F59E0B` / orange `#F97316` with no token. → add `colors.transportPause` / `colors.transportStop` (or reuse `warning` / `countInActive`).
- **T5** (med · S) `BT.opacityFull = 0.65` is misnamed (implies 1.0) — has spawned a parallel ad-hoc alpha system (`0.53/0.67/0.78/0.80/0.35` in nav-bar painter; `0.24/0.85` in editor button). → rename to `opacityBorder`; add a real `opacityFull = 1.0`; collapse the ad-hoc values onto existing constants.
- **T6** (med · S) `VirtualPiano` resize handle: idle `#505050` (warm grey, hue 0°) + active `#38BDF8` (sky-blue ≠ Boojy Blue). → `colors.divider` / `colors.accent` (the handle comment already says "matching ResizableDivider").
- **T7** (med · M) `piano_roll_cc_lane.dart` CC palette is 6 independent Material leftovers with no relation to the Boojy temperature system; pastels may be unreadable on Light. → derive from `accent/success/warning/error`.
- **T8** (med · S) `timeline_grid_painter.dart` defaults are indigo-tinted greys (hue ~231°) vs the gunmetal (hue ~220°) the live call site passes. → drop the defaults (make `required` or `transparent`).
- **T9** (low · S) `note_painter.dart` default `noteColor` is Material cyan `#00BCD4`, not Boojy Blue `#40B3E8`. → make `required` or default to Boojy Blue. *(Also tracked as P6.)*
- **T10** (low · M) ~30+ raw `fontSize:` literals (10/12/14/16/18) between the named token sizes (9/11/13/15/20) across clip previews, track header, library, export dialog. Most visible: the clip-name label (10 vs 11 for MIDI/audio makes identical chrome read as "two kinds of clip"). → migrate to `BT.font*`; consider adding `BT.fontSm = 12`.
- **T11** (low · M) `canvas_bg_variant.dart` still ships 4 candidate backgrounds as a permanent enum ("once a winner is chosen we hard-set it" — never happened). → promote one to `BG.editor`, delete the enum, keep `Cmd+Shift+B` as a palette-editor override.

### Top bar

- **N1** (med · S) Metronome is a blurry 14px PNG with no `filterQuality`; `BI.metronome` (`Icons.av_timer`, crisp vector) exists and is unused. → swap to `Icon(BI.metronome, …)`.
- **N2** (med · S) `_PunchOverlay` (loop split-button popup) combines `Border.all` + `borderRadius` with no clip — ragged corners per the flutter-ui rule. → `DecoratedBox(position: foreground)` for the border.
- **N3** (med · S) `FileMenuButton` project name is raw `fontSize: 14` — between body (13) and display (15), ~27% larger than its 11px neighbours, pulls the eye to the filename over the transport. → `BT.fontBody`.
- **N4** (low · S) `AddTrackButton` has no press-depth or scale animation — only a colour flip; reads laggy/broken next to every other bar button. → add `ButtonHoverMixin` + `AnimatedScale`.
- **N5** (low · M) Five different hover-scale magnitudes across the bar's twelve items (1.05 logo/transport/record · 1.02 undo/panel/help · none AddTrack · none split-buttons). → one "chrome" scale (1.02) + one "primary" scale (1.05), applied via the mixin.
- **N6** (low · M) `_PanelToggleButton` shows no active/inactive distinction at rest (deliberate "quiet chrome" — but a beginner can't tell if the sidebar is open without hovering). → subtle `colors.surface` fill when active (one step below the rejected accent treatment).
- **N7** (low · S) Tempo/signature/position readout boxes hardcode `BorderRadius.circular(4)` instead of `BT.borderMd`. → token. *(No visual change today; prevents drift.)*
- **N8** (low · M) At `minimum` density the `PositionDisplay` can be starved to a 0-width / sub-readable scrubber below ~440px window. → `minWidth: 0` guard + non-negative `FittedBox` constraint, or drop the readout entirely at `minimum` (matching the `showTempoSig` pattern).

### Transport & time

- **X1** (high · S) `PositionDisplay` has `onTap` (cycle) + `onDoubleTap` (edit) on one leaf → ~300 ms lag on *every* mode-cycle tap. CLAUDE.md documents the `_lastTapAt` fix. → remove `onDoubleTap`; manual last-tap compare.
- **X2** (high · S) Tempo number zone: `onDoubleTap` (dialog) alongside `onVerticalDragStart` → ~300 ms sticky lag before every scrub. → same `_lastTapAt` fix, or replace the dialog with inline edit (see X7).
- **X3** (med · S) `_formatBars` hardcodes `subdivisionsPerBeat = 4` (also `* 4` at `timeline_view.dart:1102`), ignoring beat unit — wrong sub range for 3/8, 6/8. → add a `subsPerBeat` param (default 4 until the engine has a beat-unit concept).
- **X4** (med · M) Pinned ruler readout duplicates all of `PositionDisplay`'s formatting (two `* 4` sites; ignores the saved `positionDisplayMode`). → replace `_buildPinnedReadout` with `PositionDisplay(chromeless: true, …)`.
- **X5** (med · S) Signature menu lists only 2–7; drag clamps 2–16 — drag to 9/4 and the menu can't restore a value or show a checkmark. → extend the menu to the full range (or clamp drag to match).
- **X6** (med · M) Signature drag (vertical) and tap (menu) conflict on trackpads — a 1px Y wobble swallows the intended tap. → split affordances: tap opens menu, a separate ▲▼ chevron handles drag.
- **X7** (med · S) Time-mode edit accepts raw seconds (no `M:SS`, empty pre-fill, no hint) — typing "1:30" fails silently. → pre-fill seconds + `hintText`, or parse `M:SS`.
- **X8** (low · M) Tempo edit is a heavy `AlertDialog` while the position display already has lightweight inline edit; the range label floats away on first keystroke. → mirror the inline pattern with a persistent `20–300` hint.
- **X9** (low · S) "Both" mode edit only supports bar entry; the time sub-line gives no edit affordance and no explanation. → drop into bars-edit only and update the tooltip to "Double-click to jump to bar."

### Piano roll *(grounded against piano-roll.png)*

- **P1** (high · S) White-key row separators are drawn in `colors.elevated` — the *same* colour as the white-key background, so they're invisible; you can't tell where D ends and E begins. *(Confirmed: the screenshot's lanes read flat.)* → `colors.surface` (or `divider`) for the separator only.
- **P2** (med · S) Black-key lanes are only ~0.20 alpha darker (~8 RGB units) — barely reads as a different zone at 16px rows; GarageBand targets ~35–40%. *(Confirmed: faint.)* → raise alpha to ~0.35.
- **P3** (med · S) Root-note band renders unconditionally (alpha 0.16) regardless of the Scale Highlight toggle — beginners see an unexplained cyan tint on every C. → gate on `scaleHighlightEnabled`.
- **P4** (med · M) Snap/Quantize popups hardcode `#2A2A2A` + `Colors.white70` — near-black popup on the near-white Light editor. *(= P7 in quick-wins.)* → `colors.elevated/divider/textPrimary`.
- **P5** (med · S) Single-letter note label takes `noteName[0]` — `C#5` shows "C", making chromatic runs look diatonic at intermediate zoom. → strip the octave digits, keep the accidental.
- **P6** (low · S) Default `noteColor` hardcoded `#00BCD4` (not the accent token). *(= T9.)* → `required` or Boojy Blue.
- **P7** (med · M) No persistent in-grid tool-mode badge — Draw vs Select is only the toolbar highlight + cursor; beginners get stuck in Select and can't place notes. → small fading "Draw/Select" pill bottom-right of the grid.
- **P8** (low · S) Vertical zoom (drag the key gutter horizontally) is undiscoverable — no tooltip, no cursor hint. → Tooltip + `resizeColumn` cursor on the gutter.
- **P9** (low · M) Scale controls (root/type/Highlight/Lock) appear to be missing from the live controls-bar build path (moved to a `PianoRollScaleControls` sidebar that may never be instantiated). → **audit first**; if absent, re-add a compact Scale group to the controls Wrap.

### Timeline *(grounded against demo-project.png)*

- **L1** (high · S) Selected-clip border uses `textPrimary` (near-white) on every track colour — invisible on yellow/lime/cyan clips. → luminance-aware white/black, or a dedicated `selectionBorder` token.
- **L2** (high · S) Empty-state prompt triggers when only Return tracks exist (`type != 'Master'`) — "Drag an instrument" floats over a populated arrangement. → also exclude `return`.
- **L3** (med · S) Audio ghost/copy-drag clips hardcode `headerHeight = 20.0`; real audio clips use `UIConstants.clipHeaderHeight` (18) — ghosts are 2px too tall on every Cmd-drag. → use the constant (4 sites).
- **L4** (med · S) Loop-region dim overlay hardcodes `0x4D000000` — invisible on Light theme. → add a theme-aware `loopDimColor` param.
- **L5** (med · M) Empty-area ghost clip subtracts `scrollOffset` while on-track ghosts don't — scrolled canvas places the ghost left of where it lands. → drop the subtraction (content-space `clipX` is already correct).
- **L6** (low · S) Drag-to-create preview is green (`success`) in the empty area but track-coloured on existing tracks. → use the next track colour so the preview foreshadows the result.
- **L7** (low · M) `timeline_grid_painter.dart` defaults are hardcoded hex (= T8) — wrong on Light if ever constructed without explicit colours. → make `required`/`transparent`.
- **L8** (low · S) `PlayheadLab.notifier` (dev-only `Cmd+Shift+H`) is wired as the production painter's `repaint` listener — release builds repaint on every lab toggle. → guard behind `kDebugMode`.

### Mixer *(grounded against mixer.png)*

- **M1** (high · S) `CapsuleFader.onTapDown` teleports volume on any single click on the body — the only recovery is double-tap-reset or undo. → remove `onTapDown`; keep drag; optionally require the tap to land near the thumb.
- **M2** (high · M) No peak-hold tick on the meters — only smooth decay, so transients vanish before the eye arrives (the primary clip-spotting cue in every beginner DAW). → held-peak value + ~1.5s hold + a 2px bright/red tick.
- **M3** (med · S) No unity-gain (0 dB) marker on the fader (unity sits silently at 0.70 of travel) — beginners push everything right and clip the master. → a 1–2px tick at the unity position.
- **M4** (med · S) M/S/R/I have no tooltips; "I" (input monitor) is never explained. → `Tooltip` on each with plain-language text.
- **M5** (med · S) Sends display as % (`10%`) while every other volume reads dB. *(Confirmed: "Reverb · 10%".)* → an `amountDbLabel` getter (default send → "−20 dB").
- **M6** (med · S) `TrackMixerStrip` + `MasterTrackMixerStrip` combine `clipBehavior: Clip.hardEdge` with `Border.all(width: 2)` — the selection ring renders at ~1px (flutter-ui rule). → drop `clipBehavior`; clip the child separately or paint the border foreground.
- **M7** (med · M) No visible "Add Return" entry point — returns are only creatable via a right-click submenu that appears only when returns already exist. → a "+ Reverb"/"+ Delay" affordance below the return strips.
- **M8** (low · S) `HorizontalLevelMeter` uses a linear dB↔slider curve vs `CapsuleFader`'s piecewise Boojy curve — same thumb position, different dB. Appears unused. → delete, or share the curve.
- **M9** (low · S) Return strips reuse the regular M/S buttons (no tooltips) and delete with no confirmation dialog — right-click "Delete Return" nukes a bus + all its sends silently. → reuse `_confirmDeleteTrack`; add tooltips.

### Effects & devices *(grounded against effects-chain.png, eq-effects.png)*

- **E1** (high · M) The on/off dot in the 22px `DeviceStrip` has a 10×10 hit target. → wrap in a 22×22 `SizedBox` with a centred 10px dot (≈5× the tap area at no visual cost).
- **E2** (high · S) Bypass/Enable context-menu icon ternary emits `BI.lightning` in *both* branches — no state feedback. → distinct icons (+ tint). *(Note: the card-header power dot at top-right does change colour — confirmed in the screenshot — this bug is the context-menu item only.)*
- **E3** (high · S) Effect slider labels print at 9–10px and values at 9px — at/below the legibility floor. → label `BT.fontCaption`, value ≥10px; narrow the label/value columns to reclaim width.
- **E4** (med · M) The Mix (wet/dry) slider is visually identical to every other parameter — the most important beginner knob is undifferentiated. → render Mix as a distinct circular knob bottom-right of each card (GarageBand pattern).
- **E5** (med · S) The EQ "Out" knob is the same size/style/position as the per-band Freq/Gain/Focus knobs — reads as another band parameter. *(Confirmed: identical knobs in the utility row.)* → separate it (move to graph corner, or a divider + "Output Gain / master" sub-label).
- **E6** (med · S) `HorizontalLevelMeter` (linear) vs `DeviceStrip` (piecewise) curve mismatch — same finding as M8; shared util or delete.
- **E7** (med · S) `EffectParameterPanel` is dead but compiles with a *different* visual language (green accent, 6px thumb, wider sliders, `ElevatedButton` menus, a fixed-band EQ) — a regression landmine. → delete; `flutter analyze` to confirm no live refs.
- **E8** (med · M) EQ card has no min-height guard — at the default ~170px editor height the graph compresses to ~80px and band/utility rows nearly touch. *(Confirmed in demo-project.png.)* → `minHeight` constraint or a "resize to see the graph" placeholder.
- **E9** (low · S) Add-effect menu items all share `BI.lightning` (`_getEffectIcon` returns it for everything). → distinct per-type icons (`BI.equalizer`, `BI.compress`, …).
- **E10** (low · S) Effect slider thumb radius 4px (chain) vs 6px (dead panel) — extract one shared `SliderThemeData`.

### Chrome & settings *(grounded against settings.png, startup-screen.png)*

- **C1** (low · S) Window title uses a plain hyphen (`name - app`) while the macOS strip uses an em-dash (`name — Boojy Audio`) — Mission Control / Window menu show different punctuation. → align on the em-dash.
- **C2** (med · S) `ProjectSettingsDialog` and its nested NewVersion dialog both omit `barrierColor: BT.dialogBarrierColor` — a lighter scrim than every other dialog. → add it.
- **C3** (med · M) `LatencySettingsDialog` is a bare `AlertDialog` (`colors.dark`, squared, no barrier) vs the unified `Dialog()` chrome everywhere else. → rewrite to match.
- **C4** (low · S) `ProjectSettingsDialog` hardcodes widths 520/400 vs `BT.dialogWidthMd` (480) / `dialogWidthSm` (420). → tokens.
- **C5** (low · S) Section-header letter-spacing is 1.5 in `AppSettingsDialog` but 0.5 in `ProjectSettingsDialog`. → one `BT.letterSpacingCaps` token / shared helper.
- **C6** (low · S) `AppSettingsDialog` section divider uses `accent @ 40%` — a teal cast bleeds onto every section rule (visible in settings.png), pulling the eye to dividers not content. → `colors.divider`.
- **C7** (low · S) Bluetooth latency warning is `fontSize: 10` (below the 11 floor) at exactly the moment a beginner needs to read hardware advice. → `BT.fontLabel`.
- **C8** (low · S) That warning uses a hardcoded `left: 100` indent that breaks at non-default UI Scale. → match the control's `Expanded(1:2)` Row.
- **C9** (low · S) Start-screen action buttons + project cards defer hover `setState` through `addPostFrameCallback` — a one-frame flicker (the callback is unnecessary; `MouseRegion` fires outside build). → direct `if (mounted) setState`.
- **C10** (med · M) `ProjectCard` reads its thumbnail with `readAsBytesSync()` *inside build* — 9–12 synchronous disk reads on every start-screen rebuild → jank on slow volumes. → `FutureBuilder` / async load.
- **C11** (low · S) Start-screen "Recent Projects" heading is raw `fontSize: 20`, not `BT.fontHeading`. → token.
- **C12** (low · S) `splashRadius: 16` on the start-screen close `IconButton` is deprecated (ignored in M3). → remove; use `constraints` + `padding`.

</details>

---

## 5. How Boojy compares to the four DAWs

### 5.1 Top bar & time readout
- **GarageBand — take inspiration:** the isolated, protected transport zone (Boojy already does this — *protect* it); the time readout treated as a first-class instrument display, not a label. **Avoid:** seven-segment LCD skeuomorphism — Boojy's flat readout is already right.
- **Ableton — take inspiration:** the minimal slim strip; segment-editable position fields; dropping whole *groups* at narrow width rather than micro-shrinking (fixes N8). **Avoid:** the Session/Arrangement two-view split entirely — Boojy's arrangement-only model is a beginner advantage.
- **FL Studio — take inspiration:** the labelled mode indicator on the readout; the dual bars+clock readout. **Avoid:** the toolbar cemetery (30+ ungrouped icons) and detachable/floating windows — Boojy's single-panel layout is strictly better; require a *removal* before any toolbar addition.
- **Logic — take inspiration:** the "Beats & Time" dual mode and click-to-toggle; the dark inset LCD frame that reads as a measurement device; scrub-to-adjust tempo (already half-there). **Avoid:** customisable toolbars; overflow-by-cramming (shed a label, then a control — never overlap).

**→ For Boojy:** the readout family is already a coherent LCD trio — the work is (a) fixing the lag (X1/X2) so it *feels* like a precise instrument, (b) the dual-mode persistence and a quiet `BARS/TIME/BOTH` tag (X4, X9), and (c) group-priority dropping at narrow width (N8) instead of starving the readout.

### 5.2 Piano roll
- **FL — take inspiration:** explicit tool modes — resize only on the right edge with a wide move deadzone (directly fixes the resize-vs-move ambiguity); value-on-hover instead of always-on labels. **Avoid:** maximal density and detached piano-roll windows.
- **Ableton — take inspiration:** the **root note gets its own distinct band** for at-a-glance "home." **Avoid:** clip envelopes drawn inside clip bodies by default — show automation only where it exists.
- **GarageBand — take inspiration:** clickable keyboard sidebar that auditions the note on the current instrument; the always-visible tool strip; velocity-as-note-brightness (Boojy has the ramp). **Avoid:** mode-implicit tool selection ("I deleted a note and don't know why") and collapsed-sliver default heights.
- **Logic — take inspiration:** subtle per-octave background tint for orientation; ellipsis truncation (`C…`) so a note never reads empty.

**→ For Boojy:** the lane *structure* is the gap, not the colour. Make the white-key separators visible (P1), deepen the black-key contrast (P2), gate the root band on its toggle (P3), keep the accidental (P5), and add a persistent tool badge (P7). That's GarageBand-grade legibility for ≤S–M effort each.

### 5.3 Mixer
- **GarageBand / Logic — take inspiration:** the **unity-gain tick** (the single cheapest metering win — M3); **peak-hold** line (M2); **M/S/R as icons** with state colours (speaker-off / headphones / record-dot — fixes the "M = Mute/Mono/MIDI?" guessing, M4); track colour carried into the strip as a swatch (Boojy's headers already do this — keep it). **Avoid:** hiding the mixer behind a separate window/view — Boojy's always-visible coupled-scroll sidebar is *better than all four DAWs*; never add a "show/hide mixer" toggle that defaults hidden.
- **FL — take inspiration:** strict uniform strip geometry (don't let name length reflow). **Avoid:** fader + volume-knob duplication — one volume control per channel.

**→ For Boojy:** the mixer is the area with the biggest beginner-payoff per unit effort — M1/M2/M3/M4/M5 are all S–M and each removes a "why doesn't this make sense?" moment.

### 5.4 Effects / devices
- **Logic / GarageBand — take inspiration:** Smart Controls — lead with 2–3 key parameters, full detail behind a disclosure; one consistent device header (name + power dot + collapse triangle); a per-device collapse to header strip (fixes the EQ-squeeze E8 without a hard min-height). **Avoid:** skeuomorphic rotary knobs as the default; floating plugin windows — Boojy's inline cards are the cleaner model.
- **Ableton — take inspiration:** identical device shell across every built-in; the fold triangle; EQ curve-over-spectrum (the best "*why* am I cutting" teaching tool); a universal Dry/Wet **MIX knob in a fixed corner**. **Avoid:** dense 40–60-param grids (Operator) and mod matrices — keep the synth at one oscillator + ADSR.
- **FL — take inspiration:** numbered insert slots; consistent power-LED chrome. **Avoid:** value-readouts that are illegibly small (E3 is exactly this today).

**→ For Boojy:** the device chrome is the headline v0.7 opportunity (see §7) — one shared shell (header glyph + name + power dot + collapse + visualizer + 2–3 hero params + fixed MIX knob) unifies Synth / Drum Kit / Sampler / EQ / Reverb and fixes E1–E9 structurally rather than one card at a time.

---

## 6. Design direction — "a calm, precise instrument" (finish the system, then unify the devices)

The north star is unchanged: **Logic's discipline × GarageBand's friendliness**, premium through restraint. The previous cycle built the foundation; this one is about **closing the gaps that make a beginner feel friction**, and then **unifying the device surfaces** into one shell.

**Finish the token layer (correctness, not aesthetics).** The Light theme is currently shipping broken in the un-migrated pockets. Make every painter/popup colour parameter either `required` or theme-sourced, route the snap/quantize popups and `FileDropZone` and `device_box` through `context.colors`, and add the two missing semantic tokens (`transportPause`/`transportStop`). Rename `opacityFull` to tell the truth and collapse the parallel alpha system. *This is the "theme-switch correctness" pass §10 of the last review flagged — it has to precede any further Light-theme polish.*

**Remove the interaction footguns (trust).** Two `onDoubleTap`-on-tap-leaf instances cost ~300 ms on the most-touched controls; the fader teleports on a misclick. These three fixes (X1, X2, M1) do more for the "precise instrument" feel than any visual change, because the instrument currently *feels* laggy and twitchy in the hand.

**Add the GarageBand-grade legibility cues (friendliness).** Peak-hold, unity tick, icon+tooltip M/S/R, sends-in-dB, visible piano-roll separators, a persistent tool badge. None of these are redesigns; each is a cue a beginner navigates by that the app currently withholds.

**Unify the device chrome (the premium signal).** All four DAW teardowns and the dogfood notes (§B10) converge on the same answer: one device shell for every built-in. The consistency *is* the premium signal. Lead with 2–3 hero params, put a universal MIX knob in a fixed corner, add a collapse triangle, and reserve the full param set behind a disclosure. This fixes the "half-finished pro tool" gestalt (mixed sliders/knobs/fader-strips) at the root.

> **Guardrails (unchanged):** accent signals meaning, never decorates · no skeuomorphism · one icon family through `BI`, no escape hatch to `Icons.*` · shed a label before shrinking a hit target, shed a control before overlapping · keep the synth at one oscillator + ADSR — no mod matrix · never add a clip-launcher, a second side panel, or a floating-window model.

---

## 7. ASCII mockups (before → after)

> Layout truth, aesthetic hint. ASCII can't show colour/type/glow — those are in the notes. The real verdict is seeing it on `fvm flutter run -d macos`.

### 7.1 Mixer strip — the highest beginner-payoff surface

**Before** — fader teleports on click, no peak-hold, no unity mark, bare M/S/R/I, send in %:
```
┌─ 2 Synthesizer ─────────────────────────── M  S  R  ⚡ ◯ ┐   M/S/R = bare letters, no tooltip
│ ┌────────┐  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  ◖thumb◗     │   ← single click ANYWHERE = teleport
│ │ 0.0 dB │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░             │   ← meter: smooth decay, NO peak-hold
│ └────────┘                              ▲ no 0 dB mark   │
│ Reverb ◔ 10%                                    ×        │   ← send in % (every other vol = dB)
└──────────────────────────────────────────────────────────┘
```
**After** — grab-the-thumb, peak-hold tick, unity notch, icon+tooltip M/S/R, send in dB:
```
┌─ 2 Synthesizer ──────────────────── 🔇  🎧  ⏺  ⚡ ◯ ┐   icons + tooltips (Mute/Solo/Arm/Monitor)
│ ┌────────┐  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│▓▓▓▓░░░┊░░░  ◖═◗      │   │ = unity tick   ┊ = peak-hold (1.5s)
│ │ 0.0 dB │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│▓▓░░░░░┊░░░          │   ← drag scrubs; click near thumb only
│ └────────┘                     ▲0dB        ▲held peak │
│ Reverb ◔ −20 dB                                 ×    │   ← send in dB (matches every fader)
└────────────────────────────────────────────────────────┘
```
*Notes:* unity tick = `textMuted @ 0.5`, 1–2px, at slider-pos 0.70; peak-hold = 2px white, red above 0.95; M1 removes `onTapDown`; M/S/R icons keep their state colours (yellow solo, red arm).

### 7.2 Piano-roll lane — make it read like a keyboard

**Before** — white-key separators invisible (drawn in the row bg colour), black-keys barely darker, root band always on:
```
 G5 ┃ F#5 ▭▭▭▭                                    ← no visible line between G5 and F5 (same colour)
 F5 ┃     ▭▭▭                                      ← black-key rows only ~8 RGB units darker
 E5 ┃                                              ← C row tinted cyan even with Scale Highlight OFF
 D5 ┃                                              
 C5 ┃░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ← unexplained root band, always rendering
```
**After** — visible separators, deeper black-keys, root band gated on the toggle:
```
 G5 ┃ F#5 ▭▭▭▭                                    
────┃──────────────────────────────────────────  ← separator = colors.surface (visible, calm)
 F#5┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ← black-key ~0.35 alpha (clearly a darker zone)
────┃──────────────────────────────────────────  
 F5 ┃     ▭▭▭                                      
 C5 ┃     (root band ONLY when Scale Highlight is on; label keeps accidental: "C#5" not "C")
```
*Notes:* P1 (separator colour), P2 (0.35 alpha), P3 (gate on `scaleHighlightEnabled`), P5 (keep `#`). Optional: clickable key gutter auditions the note (inspired by GarageBand).

### 7.3 Device shell — one chrome for every built-in (the v0.7 headline)

**Before** — three metaphors in one chain (EQ knobs · Reverb sliders · vertical fader strips), Mix = a plain slider, Out = another band knob, no collapse:
```
┌─ Reverb ───────────────────⚡●┐ │ ┌─ EQ ───────────────────────⚡●┐
│ Size ──●──── 0.5             │ │ │   [ curve over grid ]          │
│ Damp ──●──── 0.5             │ │ │ ◔Freq ◔Gain ◔Focus   ◔Out  🗑  │ ← "Out" == band knobs
│ Mix  ─●───── 0.3   ← plain   │ │ │ +Add Band  Low Cut  High Cut   │
└──────────────────────────────┘ │ └────────────────────────────────┘
```
**After** — one shell: header (glyph + name + power dot + collapse) → visualizer → 2–3 hero params → fixed MIX knob:
```
┌─ ◆ Reverb ───────────────── ◉  ⌄ ┐   ◉ power dot (clear on/off)   ⌄ collapse to header
│   [ subtle decay visualizer ]      │
│   ◍ SIZE    ◍ DAMP        ◍ MIX ◄──┤   MIX = circular knob, FIXED bottom-right, EVERY device
│    0.5       0.5            30%    │
│            ‹ advanced ▾ ›          │   full param set behind disclosure
└────────────────────────────────────┘
  EQ variant: curve hero + Add Band; "Output Gain" separated from band knobs (label "master")
```
*Notes:* fixes E1 (dot in a 22px tap zone via the shell), E2/E9 (per-type icons), E3 (params ≥10px), E4 (MIX knob), E5 (Out separated), E8 (collapse instead of squeeze). Synth / Drum Kit / Sampler adopt the same header so the chain reads as one instrument family.

<details>
<summary><b>7.4 Settings — one design system across the three dialogs</b></summary>

**Before** — three eras: polished two-pane `AppSettingsDialog` · plain-form `ProjectSettingsDialog` (no barrier, width 520, header letter-spacing 0.5, accent-tinted dividers) · raw `AlertDialog` `LatencySettingsDialog`:
```
AppSettings (two-pane, accent dividers)   ProjectSettings (plain form, no barrier)
┌────────────┬───────────────────┐        ┌─────────────────────────┐
│ ◉ Appear   │ APPEARANCE ─────── │ ←1.5   │ NAME ──────── ←0.5      │ different letter-spacing
│   Audio    │ Theme   [ Dark ▾] │        │ [ My Song          ]    │ width 520 (not token)
│   MIDI     │ (divider = accent@40%)     │ BPM ────────            │ no barrierColor
└────────────┴───────────────────┘        └─────────────────────────┘
LatencySettings = bare AlertDialog, colors.dark, squared corners, no barrier = the outlier
```
**After** — one header / one section-header / one dropdown / one barrier across all three:
```
┌──────────────────────────────────────────────────────────────┐
│  Settings                                          [ × ]       │  one header style
├────────────┬───────────────────────────────────────────────── │
│ ◉ Appearan │  APPEARANCE ──────────────────────────────────   │  caps/12/letter-1.5, divider neutral
│   Audio    │  Theme           [ Dark              ▾ ]          │  one dropdown chrome
│   MIDI     │  AUDIO ────────────────────────────────────────  │
│   Latency  │  Output device   [ Built-in Output   ▾ ]          │  Latency folded in, same chrome
│   Project  │  PROJECT ──────────────────────────────────────  │
└────────────┴───────────────────────────────────────────────── ┘  BT.dialogBarrierColor everywhere
```
*Notes:* C2 (barrier), C3 (Latency → unified Dialog), C4 (token widths), C5 (one letter-spacing), C6 (neutral dividers). Independent cleanup pass — folded into v0.7's chrome slice, not its headline.

</details>

---

## 8. Proposed next milestone — **v0.7 "Devices & Feel"**

Two threads, sequenced: first **close the trust + legibility gaps** that make a beginner feel friction (theme correctness, the lag footguns, the mixer cues), then land the **unified device chrome** the teardowns and dogfood notes all point to. Nothing here changes how anything sounds.

**Design decisions (each with the alternative's cost):**

- **Finish theme-token propagation (Light theme works everywhere).** *Alt (leave the pockets hardcoded): cheaper now, but the Light theme is shipping visibly broken — selected device borders and snap/quantize popups invert — and every further Light polish is built on sand.*
- **Kill both `onDoubleTap` footguns + the fader teleport (X1/X2/M1).** *Alt (leave them): the most-touched controls keep their ~300 ms lag and the fader keeps eating volume on misclicks — the single biggest "feels unfinished" signal, and CLAUDE.md already documented the fix.*
- **Mixer legibility cues: peak-hold, unity tick, icon+tooltip M/S/R, sends-in-dB (M2–M5).** *Alt (defer): the mixer stays opaque to exactly the audience the product targets; these are the cues every beginner DAW ships.*
- **Piano-roll lane re-treat: visible separators, deeper black-keys, gated root band, kept accidentals (P1–P3, P5).** *Alt (just lighten greys): keeps the flat, hard-to-read keyboard; the win is committing to a visible lane structure.*
- **One device shell with a fixed MIX knob + collapse + 2–3 hero params (E1–E5, E8).** *Alt A (patch each card): fixes the symptoms one at a time and the "three metaphors" gestalt survives. Alt B (defer to v0.8): leaves the most-requested premium signal on the table while the chain still reads half-finished. Cost of doing it: needs the shell designed first (a real design task) and is the milestone's bulk.*
- **Group-priority narrow-bar dropping (N8) over micro-shrinking.** *Alt (keep starving the readout below ~440px): the position display goes sub-readable — Logic's "shed a label, not a hit target" is the right model.*

**In scope:** T1–T8 (theme correctness + transport tokens) · X1, X2, X4, X9 (transport lag + dual-mode reuse) · M1–M6 (mixer feel + legibility) · P1–P3, P5, P7 (piano-roll re-treat + tool badge) · L1, L2, L4 (selection border, return-only prompt, loop-dim) · E1–E5, E8, E9 (the device shell + its structural fixes) · N1, N2, N3 (metronome PNG, punch-overlay clip, project-name font) · C2–C6 (settings unify, folded in) · E7 (delete the dead panel).

**Out of scope (with why):**
- **The synth/instrument visual overhaul beyond the shared shell** — the shell header lands here; a full Synth/Sampler face redesign is its own pass once the shell exists.
- **Full `fontSize`-literal migration (T10) + `canvas_bg_variant` resolution (T11)** — low-risk mechanical follow-ups; don't gate the visible wins.
- **The CC-lane palette (T7) and grid-painter `required`-param tightening (T8/L7)** beyond the Light-theme-critical ones — finish the user-visible Light breaks first; the painter-default hardening is a regression-prevention follow-on.
- **EQ spectrum-over-curve (inspired by Ableton) + clickable piano-roll key audition (inspired by GarageBand)** — both excellent, both additive; earn the shell + the lane re-treat first.
- **`HorizontalLevelMeter` / `EffectParameterPanel` audit beyond deletion (M8/E6/E7/E10)** — confirm-and-delete is in; any salvage is a separate call.

**Effort:** large, ~6–9 focused days. Theme correctness + the three footgun fixes are ~1.5 days (high trust-per-hour). Mixer cues ~1.5 days. Piano-roll re-treat ~1 day. The device shell is the bulk (~3–4 days incl. wiring every built-in through it). Settings unify ~0.5 day.

**Verification (run on `fvm flutter run -d macos`):** switch to the **Light theme** → file-drop zone, selected device border, and snap/quantize popups all read correctly (no dark-on-dark, no white-on-white) · tap the position/tempo readout → it responds *instantly* (no ~300 ms pause) · single-click anywhere on a fader → volume does **not** jump · play a loud clip → a peak-hold tick freezes ~1.5s at the transient; a unity tick is visible at 0 dB · hover M/S/R/I → tooltips explain each; the send reads "−20 dB" not "10%" · open the piano roll → white-key lanes have visible separators, black-key rows clearly darker, "C#5" keeps its sharp, the root band only appears when Scale Highlight is on · open three different effects → identical header chrome, a circular MIX knob bottom-right of each, a collapse triangle that shrinks to the header · drag the window toward ~440px → the readout drops cleanly into overflow rather than going sub-readable.

---

## 9. Grounding note

All visual judgements in §1–§5 were checked against the eight owner screenshots staged in `docs/reviews/_screenshots/` (demo-project, piano-roll, mixer, effects-chain, eq-effects, sampler, drum-kit, settings, startup, new-project) — they are present and current for v0.6.0, so the read is grounded, not speculative. The strongest confirmations: the piano-roll's flat lanes (P1/P2), the mixer's `10%` send + missing unity/peak-hold (M2/M3/M5), the EQ's identical "Out" knob (E5) and ~80px squeezed graph (E8), and the effects chain's three-metaphor split (E4). If a future reader finds the `_screenshots/` folder empty, re-verify these on `fvm flutter run -d macos` before acting.
