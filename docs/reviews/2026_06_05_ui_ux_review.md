# Boojy Audio — UI/UX Review & Design Direction

**Date:** 2026-06-05
**Version under review:** v0.5.1 (running build, `feat/ui-polish-topbar-master-library`)
**Scope:** UI/UX only — visual language, theme-token discipline, layout, responsiveness, beginner-legibility, and a competitive read against GarageBand, Ableton Live, FL Studio, and Logic Pro. Plus a proposed next milestone. **Out of scope:** the audio engine, the v0.6 drum-kit work, the sampler blank-panel fix (already on a branch), and any plugin/VST3 loading behaviour.
**How this was produced:** a multi-agent pass — 8 readers over the Flutter UI source (theme-tokens, top bar, transport/time, piano roll, timeline, mixer, effects/devices, chrome+settings), 4 competitive DAW teardowns, then synthesis into a bug ledger, design direction, ASCII mockups, and a milestone plan. **Grounded** against 10 owner screenshots in `docs/reviews/_screenshots/` dated 2026-06-05 — all read directly off disk, so the visual judgements below are real, not inferred.

---

## 1. Verdict — **B−**

The bones are now genuinely good and visibly better than the v0.3.2 review: the Gunmetal dark theme is coherent and calm, the LCD readout family reads as one instrument, the top-bar density ladder is thoughtful, the capsule fader is the right beginner instinct, and the empty-arrangement prompt is direct and welcoming. The "calm precise instrument" target is *within reach* — but the app is held back from B+ by two things the screenshots make undeniable: a **token-discipline backslide** (213 hard-coded colours outside the palette, with semantic tokens that exist but are silently ignored) and a **colour-language collision** where the one accent blue is being asked to mean five different things at once. The single most damaging artifact is in the narrow-window screenshot — a live red Flutter "RIGHT OVERFLOWED BY" debug banner printing straight over the arrangement, which a beginner reads as a crash. None of this is a redesign. It is, again, **commitment**: finish wiring the tokens you already defined, and give each meaning its own colour.

**The single highest-leverage change is giving the playhead, the loop region, and selection three distinct colours instead of one accent blue.** Right now the playhead is `colors.accent` (Boojy Blue) — and the dedicated `colors.playhead` token (warm red `#FF5252`) defined in `app_colors.dart` is *never referenced*. In the arrangement screenshot the playhead nearly disappears against the blue selection outline and the gold loop bar. Wire the token that already exists and the canvas instantly reads the way GarageBand and Logic do.

**What's wrong, in one breath:** one accent doing five jobs · 213 hard-coded colours bypassing live tokens (`FileDropZone` alone is 13 raw greys) · a live overflow banner at ~680–724 px window width · piano-roll root band is blue while notes are green · natural-key lane separators are invisible · no unity mark or peak-hold on any fader · M/S/R buttons with no tooltips · and a misleadingly named `opacityFull = 0.65`.

---

## 2. The core diagnosis — the few root causes under most symptoms

Five root causes sit under almost every symptom in the ledger. Fix these and ~30 line-items collapse.

1. **One accent, five meanings.** `colors.accent` (Boojy Blue) is simultaneously the playhead, the selection highlight, the loop region, hover borders, and the EQ curve. When everything important is the same blue, nothing reads as the *most* important. Ableton and Logic both enforce "colour = information, not decoration" — one hue per meaning. Boojy already defines the tokens to fix this (`playhead`, `success`, etc.); it just doesn't use them. → **Assign: playhead = warm red, loop = gold, selection = accent blue.**

2. **The token layer leaks — 213 hard-coded `Color(0x…)` outside the palette.** Six files carry the bulk: `file_drop_zone.dart` (13 greys, *zero* `context.colors`), `virtual_piano.dart` (14), `piano_roll.dart` (9), `piano_roll_controls_bar.dart` (8), `cc_lane.dart` (6), `transport_bar.dart` (4). The light/high-contrast themes silently *don't propagate* to these surfaces — the FileDropZone will render jet-black boxes on a white background. The "premium" feeling dies the first time a beginner imports a sample into an unstyled prototype-grey panel.

3. **A temperature fracture between the Gunmetal ramp and the painters.** The BG ramp has a faint cool undertone (r−b of −5 to −12). The grid painter defaults are far more indigo (r−b of −19 to −27), and the canvas-bg variants are *warmer* than the ramp. In the arrangement screenshot the grid feels "off" — like a different screen is painted underneath. A beginner can't name it; they just feel the app is unfinished.

4. **Shape and naming drift — no single system enforced.** Five border-radius values across one transport bar (2/4/6/8/token). Four dialog widths (400/480/520/680) with no shared constant. Three dialog barrier colours. `opacityFull` that means 0.65. Three live "greens" where the palette comment explicitly forbids a second. Each is small; together they read "hand-assembled," not "cast from one mould."

5. **Implemented-but-undiscoverable features — beginner trust leaks.** The CC lane works but has no button to open it. The dB readout types exact values but nothing says so. The EQ adds bands by undocumented double-tap. The position field accepts seconds with no unit hint. M/S/R have no tooltips. The features exist; the *affordances* don't. This is the exact failure mode the teardowns flagged in Ableton (hidden info view) and GarageBand (mode-implicit tools).

---

## 3. Full bug & inconsistency ledger

Deduped from the eight area reads (several findings reported the same overflow / same barrier-colour split from different angles — merged below). **Quick wins (high-impact, ≤S effort) are bolded** — most are an afternoon, several are visible trust signals.

> **Dead code, not live bugs** — confirmed unused, fold into one cleanup task rather than ranking as user-facing: `horizontal_level_meter.dart` (divergent linear fader curve), `EffectParameterPanel`/`effect_parameter_panel.dart` (legacy, divergent EQ param model, bypasses undo), `SplitButtonHoverMixin` (defined, never used), the unused `boojy_wordmark.dart` import in `transport_bar.dart`, and the legacy `SettingsDialog` (imported in two live paths but never shown as the entry point). The window-title em-dash "finding" is a **non-issue** on inspection — that's the correct macOS-native title; no action.

### High severity

| # | What | Root cause | Area | Fix | Eff |
|---|---|---|---|---|---|
| **H1** | **Live red "OVERFLOWED BY" banner over the arrangement at ~680–724 px** (confirmed in `top-bar-narrow`) | Density ladder `preferredWidth=724` + `FittedBox` scaleDown absorb only sub-pixel; the **modifier well has no FittedBox guard** the readout well has, so Loop+Snap+Metronome overflow before the `compressed` tier hits | top-bar / transport / chrome | Wrap the modifier well's inner Row in the same `FittedBox(scaleDown, centerRight)`; add a density tier that sheds the BPM/sig readout; `clipBehavior: Clip.hardEdge` on the centre `Expanded` so the stripe can never escape | M |
| H2 | Transport circles balloon to bar-height and overlap labels at narrow width (`top-bar-narrow`) | `_buildTransportWell` clamps size to `max(density.size, 32.0)` — the 32 px floor is never shed | top-bar | Drop the floor to `density.transportButtonSize` (or 24 px at `compressed`) so circles recede, not dominate | M |
| H3 | **Playhead is accent-blue, not the dedicated `playhead` token** — nearly invisible vs blue selection/loop (confirmed in `arrangement`) | `UnifiedNavBarPainter._drawPlayhead` + arrangement `Positioned` use `colors.accent`; `colors.playhead` (#FF5252) is **never referenced anywhere** | timeline | Replace `colors.accent` → `colors.playhead` in the painter (line, glow, hover) and the arrangement container | **S** |
| H4 | **Natural-key lane separators invisible** — C–D–E / F–G–A–B merge into one band (confirmed in `piano-roll`) | `separatorLine: colors.elevated` == `whiteKeyBackground: colors.elevated` (same colour) | piano-roll | `separatorLine: colors.surface` (one ramp step darker) or `colors.divider.withValues(alpha:0.6)` | **S** |
| **H5** | **`FileDropZone` is 13 raw greys, zero `context.colors`** — renders jet-black on light theme | Widget predates `BoojyColors`, never migrated | theme-tokens | Map every literal to a token (`standard`/`divider`/`success`/`surface`/`textMuted`); delete the duplicate mobile branch | **S** |
| H6 | **No unity-gain mark on any fader** (confirmed in `mixer-sidebar`) | `_drawVolumeHandle` draws only a thumb; 0 dB sits at slider 0.70 with no tick | mixer | Draw a 1 px accent tick at `_volumeDbToSlider(0.0)`; faint −12 dB "safe" tick — ~10 lines | **S** |
| H7 | No peak-hold / clip indicator — clipping invisible (20 dB/s decay) | `_updatePeakLevels` has no held peak or clip flag | mixer | Hold peak 2 s then decay; pass `clipFlag` → red band at far-right of capsule, clears on tap | M |
| H8 | **M / S / R buttons have no tooltips** (confirmed in `mixer-sidebar`) | `_buildControlButton` wraps `MouseRegion` only, no `Tooltip` | mixer | Wrap each in `Tooltip` ("Mute" / "Solo" / "Arm for Recording") | **S** |
| H9 | **On/off dot tap target 10×10 in a 22 px strip** — misses start a fader drag | GestureDetector wraps a bare 10 px Container | effects-devices | `SizedBox(22×24)` tap zone, 10 px dot centred inside | **S** |
| H10 | **Bypass context-menu icon identical whether on or off** | `effect.bypassed ? BI.lightning : BI.lightning` (same icon both branches) | effects-devices | `BI.lightningOff : BI.lightning`, or tint by state | **S** |
| H11 | Device-chain slider thumb 4 px — below grab threshold, inconsistent (4/6/7 px across panels) | `enabledThumbRadius:4` hard-coded; no shared `SliderThemeData` | effects-devices | Raise to 6/12; extract a shared `paramSlider` theme in `tokens.dart` | **S** |
| H12 | **EQ band shape (bell/shelf) has no UI** — always creates bells (confirmed: `master-effects` shows only Freq/Gain/Focus) | `_buildBandRow` has no shape selector; `AddEqBandCommand` defaults to `bell` | effects-devices | Add three pill chips (Bell / Low Shelf / High Shelf) after the knobs | M |
| H13 | **RecoveryDialog uses near-black PNG logos** — brand invisible on dark modal, on every crash-recovery path | `Image.asset('boojy-logo.png'/'boojy_audio_text.png')` — known-broken assets | chrome-settings | Reuse the code-drawn `_BoojyWordmarkLockup` / `BoojyWordmark` | **S** |

### Medium severity

| # | What | Area | Fix | Eff |
|---|---|---|---|---|
| M1 | Grid-painter colour mapping inverts the brightness ladder — `minorGrid`=`standard` is darker than `subBeat`=`surface`; finer lines read *heavier* | timeline | Swap the last two args so subdivisions are faintest | **S** |
| M2 | Grid defaults are indigo-tinted (+19..+27 r−b) vs the cool Gunmetal ramp (+5..+12) | theme-tokens | Re-derive the 4 defaults at ~−10 r−b to match the ramp | **S** |
| M3 | Root-band highlight is always accent-blue even when notes are green (confirmed in `piano-roll`) — misleading two-colour signal | piano-roll | Derive `rootBandColor`/`rootEdgeColor` from the resolved note colour | **S** |
| M4 | Black-key vs white-key lane contrast ~1.12:1 — too low to orient by colour | piano-roll | Raise the black tint overlay 0.20 → ~0.35 (~1.4:1) | **S** |
| M5 | Velocity-lightness ramp **inverts** above `baseLightness 0.54` — vel-127 darker than vel-100 for bright track colours | piano-roll | Clamp ceiling to `(baseLightness+0.12)` | **S** |
| M6 | Note-name fallback shows only the pitch letter — "A" for A4 / A#4 / Ab4 (ambiguous) | piano-roll | Strip only the octave digit, keep the accidental | **S** |
| M7 | **CC lane is unreachable** — props threaded but no button rendered; `ccLaneExpanded` never set true | piano-roll | Add a CC toggle to the controls bar, mirroring the velocity-lane pattern | M |
| M8 | Send amount shown as `%` not dB (confirmed: data is already dB internally) | mixer | Add `amountDbLabel` getter; swap the label | **S** |
| M9 | Add-track entry point disappears after the first track (only the small top-bar buttons remain) | mixer | Persistent `AddTrackButton` row below the last strip | M |
| M10 | dB readout click-to-type is undiscoverable | mixer | Tooltip "Drag to adjust · Click to type"; 1 px accent border on hover | **S** |
| M11 | Return tracks show Solo — soloing a reverb bus silences everything (GarageBand hides M/S on returns) | mixer | Hide Solo on returns; keep Mute only | **S** |
| M12 | Master strip has no persistent clip indicator (most important clip point) | mixer | Apply H7's peak-hold + a "CLIP" badge to master | M |
| M13 | **Double opacity on bypassed effects** — `DeviceBox` 0.5 × content 0.5 = 0.25 (near-invisible) | effects-devices | Remove the inner `Opacity` wrapper | **S** |
| M14 | Compressor has no makeup-gain slider in the device chain (present in legacy only) | effects-devices | Add `Makeup` slider before `Mix` | **S** |
| M15 | EQ add-band by double-tap is undiscoverable — no cursor change, no hint | effects-devices | `SystemMouseCursors.click` + a "Double-tap to add a band" tooltip/overlay | M |
| M16 | "Mix" (device chain) vs "Wet/Dry" (legacy) naming split | effects-devices | Standardise on "Mix" | **S** |
| M17 | EQ value readout 9 px in a 38 px box — illegible on a 1080p monitor (confirmed in `master-effects`) | effects-devices | Bump to `fontLabel` (11), widen to 42 | **S** |
| M18 | Empty-state prompt suppressed when only Return tracks exist — blank canvas, no guidance | timeline | Exclude `master` *and* `return` from the predicate | **S** |
| M19 | Ghost/drag-preview clip headers 20 px vs real clips 18 px — breaks the drop illusion | timeline | Use `UIConstants.clipHeaderHeight` everywhere | **S** |
| M20 | **Three dialog barrier colours + four dialog widths, no shared constant** | chrome-settings | `BT.dialogBarrierColor`, `BT.dialogWidthSm/Md/Lg` | **S** |
| M21 | Subdivision digit hard-coded to 4/beat everywhere — wrong in 3/4, 6/8 | transport-time | Thread `subsPerBeat` from the signature | M |
| M22 | BPM label not hidden in compact density (contrary to comments) — centre group wider than the density math expects | transport-time | `showLabel` flag on `TempoDisplay` from `density.showLabels` | **S** |
| M23 | Variant-D pinned readout is `IgnorePointer` — the hero position widget can't be clicked | transport-time | Replace with a real `PositionDisplay` | **S** |
| M24 | SignatureDropdown drag + tap compete — incidental trackpad drift changes the numerator on open | transport-time | Tap = menu; drag handle/long-press = numerator; or 4 px dead-zone | M |
| M25 | Shape language: 5 radius values across one bar; panel-toggle buttons have **no active state** (can't tell if Library/Mixer is open) | top-bar | One radius for chrome (4), one for overlays (8); render `isActive` (brighter icon + subtle fill) | **S** |
| M26 | Two code paths for the same 16-colour picker — divergent selection state | mixer | Extract a shared `_TrackColorGrid`; drop the standalone dialog | M |
| M27 | Recording note pills render orange-pink (lighter tint of `error`) instead of white | timeline | `noteColorOverride: textPrimary` while recording | **S** |
| M28 | Loop-region gold fill paints on bar 1 even with loop disabled (confirmed in `arrangement-empty`) | timeline | Guard the nav-bar fill behind `loopEnabled` | **S** |

### Low severity (token & polish)

`opacityFull = 0.65` misnamed → rename `opacityHigh` · `_chordsGreen #10B981` second green (B-TH1 violation) → `colors.success` · CC-lane + `midi_note_data` hardcode more greens/cyan → token list · virtual-piano `#38BDF8` ≈ accent but not equal → `colors.accent` · piano-key warm greys break light theme → use `pianoWhiteKey`/`pianoBlackKey` tokens · `NotePainter` default cyan `#00BCD4` → transparent or accent · dozens of bare `fontSize:` literals → `BT.font*` · `CanvasBgVariant` warm-shifted dev artifact → re-derive or delete · transport amber/orange literals → `transportPause`/`transportStop` tokens · record-menu raw `Icons.looks_*` and automation `Icons.timeline` → `BI` facade · metronome PNG → vector · "both"-mode secondary time 11 px low-contrast → 13 px · ruler 15 px playhead dead-zone blocks click-to-set · zoom shows raw "80px" → % or "N beats" · position-edit "time" mode has no unit hint · UI-scale dropdown shows "· 110%" jargon → "Small/Default/Large" · `ProjectSettingsDialog` Save is a `TextButton` with a bolted-on bg → `FilledButton` · add-effect button shrinks to 40×60 → ≥48 + "FX" label · start-screen Settings round-trips through the DAW screen (one-frame flash) · AppSettings ALL-CAPS vs SettingsDialog mixed-case headers.

---

## 4. How Boojy compares to the four DAWs

| Area | **Steal** | **Avoid** |
|---|---|---|
| **Top bar / transport** | GarageBand: transport as its own isolated zone (you're already doing this — keep action and state-display separate). Ableton/FL: the BPM number is the hero, the *whole field* is tap-to-increment + tap-drag-to-scrub. FL: tempo nudge arrows on hover telegraph editability. | FL: 30+ targets in one band — your bar is near the limit, **require a removal before any addition**. GarageBand: LED seven-segment styling reads "old software" to a 2026 beginner — your flat readout is better. Detachable/tearable toolbars (FL) — beginners can't recover them. |
| **Piano roll** | GarageBand/Ableton: velocity as note **brightness/fill-line**, no separate lane needed for casual reading (you have the ramp — fix the inversion M5). GarageBand: keyboard sidebar key = pitch-preview button. Logic: per-octave band tint (cheap orientation win). Logic: ellipsis fallback for narrow notes (don't show nothing — M6). | GarageBand: mode-implicit tool selection (pencil/select inferred from modifiers) — keep your tools *visible* above the roll. FL: 7-mode tool palette + lane-type dropdown — too many. Per-note colour as default (FL) — keep uniform note colour with a legibility floor. Logic: collapsed-sliver piano roll — open it to a generous height. |
| **Timeline / arrangement** | Ableton: per-track clip **colour** as identity (you're single-green today — auto-assign from a beginner-safe palette). Ableton: loop region as a thick gold brace with big handles. FL/Logic: active-clip brightness boost under the playhead. FL: clip mini-previews (you have these — keep locked). | Ableton: the **two-window Session/Arrangement model** — your biggest structural *win* is being arrangement-first; never add a clip launcher. Ableton: zebra striping you can't actually see — stripe only at a visible contrast. Uniform waveform colour (Ableton) — tint waveforms with the track colour. |
| **Mixer** | GarageBand: unity mark on every channel (H6). Logic: **peak-hold** line — "the single most beginner-useful metering feature" (H7). Logic/FL: track colour carried into the strip as a swatch. Logic: A/B compare on EQ. | GarageBand/Logic/FL: hidden mixer behind a separate view/window — your always-visible sidebar mixer is *better*, keep the scroll coupled to the track list. FL: fader + volume-knob duplication; stereo-separation knob; per-channel "send to master" toggle (silent-output footgun). |
| **Effects / devices** | Ableton/FL: horizontal **left-to-right device rack** read like a sentence (you have this). GarageBand: Smart Controls principle — lead with 2–3 key params, full detail behind disclosure. Ableton/FL: per-device collapse triangle. Logic: consistent bypass+name header strip with **unambiguous on/off** (H10). | GarageBand/Logic: **skeuomorphic rotary knobs** — "for people who already know what a threshold is," wrong message for beginners; prefer sliders / labelled pill-knobs with readouts. Every-plugin-floating-window (all four) — your inline card panel is strictly cleaner. Jargon param names (Color/Diffusion/Cross) — plain English. |
| **Library / sounds** | GarageBand: two-column browse (category → preset) with **live-preview on click** — kills the "load → hate → undo" loop. | "**Patch**" terminology (GarageBand) — use "Sound" or "Preset." Burying device/buffer/sample-rate behind Preferences only (Ableton) — keep a persistent top-bar settings affordance. |
| **Chrome / onboarding** | Your empty-arrangement prompt and start-screen Recent grid are already GarageBand-adjacent and good — preserve them. | Customisable toolbars (Logic/FL) — no upside for this audience, big support surface. Mixed icon families (Logic) — your `BI` facade is a uniformity asset; don't let `Icons.*` / PNG / SVG drift back in. |

**The competitive throughline:** every teardown independently flagged the same principle — *colour = information, not decoration*, and *legibility floors over density*. Boojy's two biggest divergences from that discipline are the one-accent-does-everything collision (§2.1) and the sub-10 px readouts (M17, EQ value 9 px). Both are squarely in scope for the next milestone.

---

## 5. Design direction

**Theme: "One colour, one meaning — and wire what you already drew."** This cycle is not new surfaces; it's *commitment to the system that already exists in the codebase but isn't switched on.* Three moves carry it:

1. **Split the accent into a semantic colour map.** Assign each meaning its own token and use it everywhere: **playhead → warm red (`colors.playhead`, already defined), loop region → gold, selection/hover → accent blue, active/armed → `success` green, danger → `error` red.** This single discipline fixes H3, M3, M28, the "armed track looks like an error" alarm, and the chords/second-green violations in one mental model.

2. **Close the token leaks, ramp-down from the worst offenders.** `FileDropZone` first (H5 — most visible to a first-time importer), then `virtual_piano`, `piano_roll`, the grid-painter defaults (M2/M1), then the long tail of `fontSize:`/colour literals. Add the missing semantic tokens (`transportPause`/`transportStop`, `ccLaneColors`, dialog barrier/width) so there's nowhere left to hard-code.

3. **Pay the beginner-legibility floor.** Unity mark + peak-hold on faders (H6/H7), tooltips on M/S/R and the dB readout (H8/M10), bigger device-chain thumbs and EQ readouts (H11/M17), and surface the hidden affordances (CC lane M7, EQ band-shape H12, EQ double-tap hint M15). These are the trust signals that separate "premium beginner DAW" from "functional prototype."

**Calibration / pushback:** Per-track clip colour (the Ableton steal) is genuinely high-leverage but touches the engine data model *and* the renderer — it's a two-PR change and shouldn't ride this cycle. The richer LCD multi-mode readout (Chord/Tuner) is a "display-mode" cycle of its own. Hold both for a later theme; this milestone is deliberately *finish-work*, not new capability — that's what moves the grade.

---

## 6. ASCII before → after — highest-leverage screens

### A. Narrow top bar (H1/H2/M25) — the most alarming artifact

```
BEFORE (top-bar-narrow-2026-06-05 — live red debug stripe)
┌──────────────────────────────────────────────────────────────────────┐
│ ▲udio  Untitled  ↶ ↷  ▢   [↻][⌄]  ‖OVERFLOWED BY‖ (◯)(◼)(●)  1.1.1 120 │
│                                     ^red banner    ^circles nearly      │
│                                      over canvas    as tall as the bar  │
└──────────────────────────────────────────────────────────────────────┘

AFTER (modifier well gains a FittedBox guard; circles shed the 32px floor)
┌──────────────────────────────────────────────────────────────────────┐
│ ▲udio  Untitled  ↶ ↷  ▢   [↻][⌄][◴]   ◯ ◼ ●    1.1.1 120     +M +A  ▢ ?│
│                            (gaps shrink) (smaller, recede)  (readout    │
│                            no banner, ever                   sheds last)│
└──────────────────────────────────────────────────────────────────────┘
```

### B. Mixer strip (H6/H7/H8/M8/M11) — the beginner's level instrument

```
BEFORE (mixer-sidebar — no unity mark, no peak-hold, no tooltips)
┌─────────────────────────────────────────┐
│ 🎹 1 Synthesizer    (M)(S)(R)  ⚡  ◯      │
│  -4.3 dB  [====green====○········]        │  no landmark — push right = clip
└─────────────────────────────────────────┘

AFTER (unity tick + safe tick + peak-hold + clip band; tooltips on hover)
┌─────────────────────────────────────────┐
│ 🎹 1 Synthesizer    (M)(S)(R)  ⚡  ◯      │   hover R → "Arm for Recording"
│  -4.3 dB  [===green==|=○····:·····|█]      │
│                      ^0dB  ^-12  ^peak ^CLIP (sticky red, tap to clear)
│  Send A   -6.0 dB    (was "75%")          │
└─────────────────────────────────────────┘
```

### C. Piano roll grid (H3/H4/M3/M4) — orientation the eye can trust

```
BEFORE (piano-roll — natural runs merge, root band is BLUE vs green notes)
 C6 │▓▓▓▓ blue root band ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│   ← blue, unrelated to green notes
 B5 │                                       │
 A5 │      (no visible line between A5/B5)   │   ← natural-key runs are one band
 G5 │   [F5 green]                           │
 ...│
 C5 │▓▓▓▓ blue root band ▓▓▓▓ [C5 green] ▓▓▓│

AFTER (root band tinted from note colour; visible hairline per lane)
 C6 │░░░ green-tinted root band ░░░░░░░░░░░░░│   ← matches the notes
 B5 │───────────────────────────────────────│   ← surface-step separator
 A5 │───────────────────────────────────────│
 G5 │   [F5 green]                           │
 ...│
 C5 │░░░ green-tinted root band ░░ [C5] ░░░░│
```

### D. Arrangement playhead (H3) — wire the token that exists

```
BEFORE: playhead drawn in colors.accent (blue) — lost against blue
        selection outline + gold loop bar.   │(blue)│  ← which line is "now"?

AFTER:  playhead drawn in colors.playhead (#FF5252 red) — reads instantly
        against green/grey clips and the blue selection.   ┃(red)┃
```

---

## 7. Proposed next milestone — **v0.5.2 "Calm & Legible"**

A finish-work cycle: wire the semantic colour map, close the worst token leaks, and pay the beginner-legibility floor. No new surfaces — this is the pass that moves the grade from B− toward B+. It also absorbs the v0.5.2 "loop & device polish" items already owed (metronome loop-wrap, the sampler blank-panel fix), which fit the device-polish half cleanly.

**In scope (this cycle):**

- **Semantic colour map** — playhead red (H3), root band from note colour (M3), loop-fill gating (M28), kill the second/third greens (`_chordsGreen`, CC-lane, virtual-piano near-accent), add `transportPause`/`transportStop` tokens.
- **Token-leak ramp-down** — `FileDropZone` (H5), grid-painter defaults (M1/M2), then the `virtual_piano`/`piano_roll`/`fontSize:` tail; add the missing dialog/barrier/width tokens (M20); rename `opacityFull → opacityHigh`.
- **Mixer legibility** — unity + safe + peak-hold marks (H6/H7), master clip badge (M12), M/S/R + dB-readout tooltips (H8/M10), sends in dB (M8), hide Solo on returns (M11).
- **Effects legibility** — bigger thumbs + shared slider theme (H11), double-opacity fix (M13), bypass-icon state (H10), bigger EQ readouts (M17), on/off-dot tap zone (H9), EQ band-shape selector (H12) and double-tap hint (M15), makeup gain (M14).
- **Piano-roll correctness** — separator hairline (H4), black/white contrast (M4), velocity-ramp inversion (M5), note-name fallback (M6), surface the CC-lane toggle (M7).
- **The two owed items** — metronome loop-wrap; sampler blank-panel fix (already branched).
- **Dead-code sweep** — delete the five confirmed-unused files/symbols in one PR.

**Out of scope (deferred, with the cost of including it):**

- **Per-track clip colours** — *highest-value steal, but two PRs (engine data model + renderer).* Including it would bloat a finish-work cycle into a feature cycle and blur the "did the polish land?" verification. → own theme.
- **LCD multi-mode readout (Chord/Tuner/Project)** — *delightful, but it's a new capability surface, not finish-work.* Including it competes for the same transport-bar attention this cycle is trying to *calm down.* → own "display-mode" cycle.
- **Full type-scale / 1440p scaling rework** — *the `fontSize:` substitution here is mechanical token hygiene, not a scaling-control-point.* A real `BT.scaled(context)` helper + accessibility scaling is an L-effort cross-cutting change. → fold into a later "responsiveness" pass; don't half-do it now.
- **Three-settings-dialog consolidation** — *we delete the dead `SettingsDialog` and unify barrier/width tokens this cycle, but fully merging `AppSettingsDialog`/`ProjectSettingsDialog` into one system is its own refactor.* Including it risks regressing the live settings flow mid-polish. → after the token map is in.

**Each design decision, paired with the alternative's cost:**

| Decision | Alternative & its cost |
|---|---|
| Wire `colors.playhead` (red) for the playhead | *Keep accent-blue:* the most important timing cue stays invisible against selection/loop — the #1 reason the canvas reads "generic," and the token already exists unused |
| Split accent into a semantic map now | *Token-leak cleanup first, colour map later:* you'd re-touch the same painters twice; the leak fixes and the colour assignments live in the same files |
| Peak-hold + unity mark on faders | *Ship without:* beginners can't tell if they clipped or what "normal" is — the single most-requested beginner metering affordance per the Logic teardown |
| Tooltips + visible affordances (M/S/R, CC lane, EQ shape) | *Leave discoverable-by-accident:* features that exist but can't be found erode trust faster than missing features; this is the exact Ableton hidden-info-view failure |
| Defer per-track clip colour | *Include it:* turns a 1-PR finish cycle into a 2-PR engine+renderer change and muddies verification of whether the polish landed |
| Defer the LCD multi-mode readout | *Include it:* adds transport-bar density the cycle is explicitly trying to reduce — directly contradicts the theme |

**Verification (manual, on `fvm flutter run -d macos`):**
1. Drag the window narrow past ~700 px — **no red overflow stripe ever appears**; transport circles shrink rather than balloon.
2. Hit play in the arrangement — the playhead is an **unmistakable red line**, distinct from the blue selection and gold loop bar.
3. Open the piano roll — you can **count individual white-key rows** (visible hairlines); the root band is the **same colour family as your notes**.
4. Open the mixer — every fader has a **visible "0 dB" tick**; push a track loud and look away — a **sticky clip mark** is still there when you look back; hover M/S/R and the **dB box** and read the tooltips.
5. Open an effect — the **slider thumb is easy to grab**, the EQ value is **readable from a normal distance**, and you can pick **Bell / Low Shelf / High Shelf** on a band.
6. Switch to the light theme (if exposed) and open the sample-import drop zone — it's **styled, not jet-black**.

---

*Grounding note: all visual claims above were checked against the 10 PNGs in `docs/reviews/_screenshots/` (2026-06-05). The most load-bearing — the live overflow banner, the blue playhead, the blue-root-band-vs-green-notes collision, the invisible natural-key separators, the unmarked horizontal faders, and the 9 px EQ readout — were each confirmed directly in the screenshots, not inferred from source.*
