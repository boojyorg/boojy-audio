# Boojy Audio — UI/UX Review & Design Direction

**Date:** 2026-05-30
**Version under review:** v0.3.2 (the running build, though it mislabels itself v0.3.0 — see B1)
**Scope:** UI/UX only — visual language, layout, consistency, responsiveness, and a competitive read against GarageBand, Ableton, FL Studio, and Logic Pro. Plus a proposed next milestone. **Out of scope:** audio engine, the Serum/VST3 loading bug (flagged for its own session), and the effects-panel overhaul (its own milestone).
**How this was produced:** a multi-agent pass — 8 readers over the Flutter UI source (theme, top bar, transport/time, piano roll, timeline, mixer, effects, chrome+settings), 4 competitive DAW teardowns, then synthesis into a bug ledger, a design direction, ASCII mockups, and a milestone plan. Grounded against four owner screenshots (top bar wide, top bar narrow, blank project, settings). ~16 agents.

---

## 1. Verdict

Your C+ is fair, and it's the *right* C+ — the bones are genuinely good (a real token system, a sane component set, a coherent dark layout), but three or four foundational gaps make the whole thing read "generic dark app" instead of "premium instrument." The encouraging part: almost none of it is a redesign. It's **commitment** — finishing the design system you already started.

**The single highest-leverage change is committing to one colour temperature.** Today the chrome is warm charcoal (`#2C2C32`) sitting over cool blue-slate content (`#0E0F14` / `#272A38`). That mismatch is the #1 reason it reads *accidental* rather than *designed*. Fix that, ship a real typeface, lift the type off its 9px floor, and let "space" live only at the edges — and you jump a full grade without moving a single panel.

**What's actually wrong, in one breath:** mixed warm/cool palette · no bundled font (you're on system fallback) · type hard-coded in 323 places so nothing scales on a 1440p screen · the "space theme" is a code comment, not pixels · and a cluster of small, visible bugs (version label, title alignment, broken logo, top bar that overlaps when narrow).

---

## 2. The core diagnosis — why it doesn't "feel right"

Five root causes sit under almost every symptom you named:

1. **Mixed temperature.** Warm-charcoal chrome over cool content. This is the big one. Every other polish move sits on top of this, so partial polish would look like lipstick. → unify to one cool deep-space blue-black ramp; chrome *joins* the content hue.
2. **No typeface.** No `fonts:` in pubspec, no `fontFamily` in `ThemeData`, and `BT.fontFamilyMono` is the generic `'monospace'` alias (= Courier on stock macOS). Logic, GarageBand, Ableton all ship a distinctive face. This is the biggest cheap win available.
3. **No scaling control point.** 323+ raw `fontSize` literals bypass the `BT.font*` tokens, and chrome heights are fixed px. So your "too small on 1440p" complaint has no single knob to turn, and macOS accessibility scaling is ignored entirely.
4. **The token layer leaks.** ~392 hard-coded `Color(0x…)` calls live outside the palette (225+ in dialogs/widgets, 64+ in painters). The theme switch (dark → high-contrast → light) silently *doesn't propagate* to a large fraction of the UI. The "space theme" is literally a `// star field renders here` comment in `app_colors.dart` — there's no painter, no spatial identity beyond the brand blue.
5. **Three button shape-languages in one bar** (your "inconsistent top bar"): rounded-square blue toggle pills, circular traffic-light transport rings, and dark rectangular value pills — no shared height/radius rhythm, groups divided by whitespace only.

---

## 3. The bugs you spotted — confirmed, with root causes

All seven of your reported issues are real and root-caused. IDs map to the full ledger in §4.

| # | What you saw | Root cause | Fix | Effort |
|---|---|---|---|---|
| **B1** | App says **v0.3.0** | `pubspec.yaml:19` is `0.3.0+1`; read via `PackageInfo`. Shipped build is v0.3.2. (Known version-sync gap — pubspec isn't on the checklist.) | Bump pubspec; add it to the Version Sync checklist | S |
| **B2** | **Title left-aligned** ("Untitled - Boojy Audio") | `MainFlutterWindow.swift:27` sets `toolbarStyle = .unifiedCompact` — a comment *claims* it centers, but unified styles leading-align. | `.unifiedCompact` → `.expanded` (centers it, Logic-style) | S |
| **B3** | **Logo misaligned**, vanishes when narrow | `_buildLogo` composites a PNG + the literal word "Audi" (Poppins SVG) + a *detached* blue circle "o" via a `ClipRect`+`OverflowBox` float-math hack. The dot doesn't track the text width → misaligned; at narrow width the whole word snaps to 0. | Author **one** path-outlined `▲udio` SVG (triangle + "udi" + dot on a shared baseline) in a `Flexible`+clip; delete the hack | M |
| **B4** | **Text too small on 1440p** | Every `TextStyle` hard-codes px; no `MediaQuery` text-scaler hook; chrome heights fixed. Token scale exists but is bypassed 323× | Lift the scale + add a `BT.scaled(context, size)` helper (text-scaler + ≥1440 width bump, capped ~1.25) | L |
| **B5** | **Grey piano-roll keys** | Keyboard caps are three greys (`#808080`/`#555`/`#2A2A2A`); white-vs-black grid rows differ by only ~11 luminance points; root note never tinted | Bright off-white naturals / near-black sharps; single deep-indigo lane; **root-note band** | M |
| **B6** | **No seconds time** (`0:05.12`) | Position readout toggles bars↔time silently (no label), can't show both, and the arrangement has no pinned "where am I" readout once scrolled | Logic-style **dual "Beats & Time"** mode + a pinned BAR.BEAT overlay on the ruler; persist the mode | M |
| **B7 / B8 / B27** | **Top bar inconsistent + breaks when narrow** | The right group has *no* overflow handling (RenderFlex overflow risk); the centre cluster overflows rather than clips; button radii/fonts/hover differ per widget | Group-priority hiding + `ClipRect`; sub-minimum density tier; unify in-bar radius/font/hover | M+S |

**From your screenshots I'd add five things the code alone didn't show:**

- **The narrow bar doesn't just drop labels — it *overlaps*.** "120 BPM" clips and the "4/4" pill collides with a circular element. It's not degrading gracefully; widgets are overrunning each other.
- **The transport circles read slightly toy-like** — bright traffic-light green/orange/red. Desaturate a touch and tokenise them.
- **The mixer uses *horizontal* faders** — vertical is the premium DAW convention; worth revisiting.
- **The settings page isn't the odd one out — the main UI is.** More on this below; it changes the fix direction.
- **Your ▲udio idea is good** and on-theme — see §6.

### On the settings page (you were right to flag it — but the fix flips)

You said settings "feels different from the rest." It does — but **settings is closer to the target than the main app is.** It's airier, larger-type, cleaner. The main UI is the dense, small-text outlier. So the resolution isn't "cram settings down to match the cramped main UI" — it's:

- **Lift the main UI toward settings' breathing room and type size** (this also fixes your 1440p "too small" complaint), and
- **Make settings adopt the app's accent + space identity** and one consistent header/dropdown system.

There's a real consistency bug underneath too (**B12**): the *three* settings dialogs (`SettingsDialog`, `AppSettingsDialog`, `ProjectSettingsDialog`) each roll their own section headers, dropdown chrome, and barrier colour — they were written by "different people" stylistically. That consolidation is its own pass; the v0.4 milestone touches the type scale here but defers the full unify.

---

## 4. Full bug & inconsistency ledger (48 items)

11 **quick wins** (high-impact, ≤S effort): **B1, B2, B9, B10, B11, B14, B20, B25, B27, B35, B43.** Do these first — most are an afternoon and several are visible trust signals.

> **Correction worth knowing:** several "broken" findings are **dead code** that never reaches users — folded into **B23** rather than ranked as live bugs. Confirmed unused: `track_header.dart`, `bar_ruler_painter.dart` (so the "orange vs blue playhead conflict" is *not* actually visible), `effect_parameter_panel.dart` (the legacy effect UI — "two effect UIs side-by-side" doesn't reach users), `horizontal_level_meter.dart`, `SettingsDialog` (imported, never shown), and `bounceCurve`. The one real effect-chain regression that survives is **B13** (EQ band frequencies silently dropped from the live chain view).

<details>
<summary><b>Expand the full 48-item ledger</b> (id · severity · effort · area)</summary>

**High severity**

- **B1** (S) Version label shows v0.3.0 — `pubspec.yaml:19`. *[you reported]*
- **B2** (S) macOS title left-aligned — `MainFlutterWindow.swift:27`. *[you reported]*
- **B3** (M) Logo wordmark misaligned + fragile clip hack — `transport_bar.dart:555`. *[you reported]*
- **B4** (L) No text/display scaling; small on 1440p — `tokens.dart` + 323 literals. *[you reported]*
- **B5** (M) Piano-roll key lanes flat grey, no root highlight — `piano_roll.dart:1193`. *[you reported]*
- **B6** (M) No persistent/dual time readout — `timeline_view.dart`, `position_display.dart`. *[you reported]*
- **B7** (M) Top-bar right group has no overflow handling (RenderFlex risk) — `transport_bar.dart:798`. *[you reported]*
- **B8** (M) PositionDisplay overflows centre cluster at min density — `position_display.dart`. *[you reported]*
- **B9** (S) About box placeholder reads "Audio / Version M6.2" — `daw_menu_bar.dart:113`.
- **B10** (S) Start-screen "Settings" button is a silent no-op — `start_screen_modal.dart:211`.
- **B11** (S) Piano-roll zoom-out button shows the **X** (close) icon — `piano_roll_toolbar.dart:52`.
- **B12** (L) Three settings dialogs, three visual languages.
- **B13** (M) EQ centre-frequency controls silently inaccessible — `device_chain_view.dart:1316`. *(real functional regression)*
- **B15** (L) Painters bypass tokens (~64 inline colours) — theme switch doesn't propagate.
- **B16** (L) 225+ hard-coded colours in dialogs/widgets — won't adapt to theme.
- **B19** (M) Effect sliders: 2px track / 4px thumb / 9–10px labels — illegible & hard to hit.

**Medium severity**

- **B14** (S) Velocity bars hardcoded cyan, ignore track colour.
- **B17** (M) Emoji (🎹🥁🎤) used as track icons instead of the BI facade.
- **B18** (S) Mixer M/S/R buttons have no hover state.
- **B20** (S) Tempo scroll-wheel clamps to 999 BPM (dialog/drag clamp to 300). *[you reported: inconsistency family]*
- **B21** (S) Position edit-mode input format doesn't match the displayed format.
- **B22** (S) Bypass menu shows identical icon for Enable/Bypass; add-effect menu uses one generic icon.
- **B23** (M) Dead/orphaned widgets ship in the build (see correction above).
- **B24** (M) **No custom UI typeface** — system fallback. *(biggest "generic" lever; a feature add, not a defect)*
- **B25** (S) Play/stop + fader-meter colours hardcoded, diverge from declared meter tokens.
- **B26** (S) Pan knob (orange/red) & send knob (off-accent blue) use bespoke colours.
- **B27** (S) In-bar button radius/font/hover inconsistent across families. *[you reported]*
- **B28** (S) Piano-roll/transport sub-readouts hardcode 10px vs the 15px display tokens.
- **B29** (S) `TimeSignatureDisplay` leaks an undisposed `FocusNode` per edit.
- **B30** (S) Snap/quantize overlays use raw hex; can't dismiss with Escape.
- **B32** (S) `addPostFrameCallback` hover handlers cause 1-frame lag + stuck-hover race.
- **B33** (S) Nav-bar zoom buttons overlay ruler with no backing, obscure bar numbers.
- **B36** (M) Timeline grid painter colours + dimming are dark-theme-only hardcodes.
- **B37** (S) `ProjectSettingsDialog` dismisses on barrier tap, discarding unsaved edits.
- **B38** (S) Start-screen thumbnails read files synchronously in `build()` — open stutter.
- **B39** (M) Fader handle has no unity marker; meter has no peak-hold.
- **B40** (S) Mixer send rows over-compressed (22px, 9–10px text, tiny targets).
- **B43** (S) Clip colour picker uses raw Material colours, not the curated track palette.

**Low severity**

- **B31** Mixer drag placeholder hardcoded to width 380 (vs configured width).
- **B34** Clip ghost headers: mixed 10/11px font, 20px vs canonical 18px height.
- **B35** (S) Loop-bar hint text fails contrast (~2.5:1). *(quick win)*
- **B41** Knob/slider drag sensitivities inconsistent (send 120, mini 150, pan 200 px/range).
- **B42** Transport bar height 54px duplicated as a magic spacer.
- **B44** Direct `Icons.*` usage bypasses the BI facade in several widgets.
- **B45** (M) Piano-roll vertical zoom is a no-op; row height fixed at 16px.
- **B46** Piano-roll shows a meaningless "Npx" zoom readout.
- **B47** One-off accent colours (chord green, VST3 host error colours).
- **B48** Empty-timeline prompt split across two Text widgets; start-screen column fixed 200px.

</details>

---

## 5. How Boojy compares to the four DAWs

### 5.1 Top bar & time readout
- **GarageBand:** one big centred **LCD as the anchor** that bundles tempo/key/sig *inside* it; tap to toggle bars↔time; generous ~44pt targets, no density laddering. **Steal:** LCD-as-anchor; touch-sized floor.
- **Ableton:** segment-editable position fields (type into bar/beat/16th independently); **drops whole groups** at narrow width rather than shrinking. **Steal:** both. **Avoid:** Ableton has *no* in-bar seconds readout — that's exactly your gap; don't copy bars-only.
- **FL Studio:** explicit **labelled mode indicator** on the readout + right-click format menu. **Steal:** the label. **Avoid:** fully detachable/rearrangeable toolbars — that's why FL feels busy.
- **Logic:** the **"Beats & Time" dual mode** (bars *and* min:sec stacked), disclosure-triangle mode chooser, tabular figures, dim backlit panel. **Steal:** all of it — this is the premium readout you want.

**→ For Boojy:** centre the position readout as the bar's hero LCD (~20px tabular mono), demote tempo/sig to dim satellites inside the same panel, add a Bars → Time → **Both** cycle with a quiet `BARS/TIME/BOTH` tag, persist the mode, and replace per-element shrinking with group-priority dropping at narrow width (keep transport + LCD full-size to the end).

### 5.2 Piano roll (your favourite is FL)
- **FL (the target feel):** the lane is a **low-saturation coloured surface**, not grey; black-key rows are a *darker shade of the same hue*; 3-tier vertical grid; scale-highlight **lightens** in-scale rows; notes have a subtle bevel.
- **Ableton:** the **root note gets its own distinct band** — find "home" at a glance. Highest-leverage trick you're missing.
- **Logic:** velocity-as-colour stays legible across the whole range; keep note labels readable at any velocity.
- **GarageBand:** the floor — plain black/white rows, but a genuinely **high-contrast keyboard graphic** (which your flat greys fail at).

**→ For Boojy:** re-tint the lane to one deep-indigo hue (rows ~`#1B1E2E` / `#151728`); bright off-white naturals vs near-black sharps on the keyboard; add a faint accent **root-note band** (6–8% wash + 2px tick); switch scale-highlight to *lighten* in-scale; 3-tier grid; give the lane its own per-theme tokens. **Avoid:** vivid nebula backgrounds, different *hues* for black vs white rows, or dimming-only scale highlight (muddies the dark lane).

### 5.3 Effects / device UI (for the *later* milestone)
- **Ableton (your primary):** one **Dry/Wet MIX knob in a fixed corner of every device**; 100% = full, 0% = bypass-equivalent; EQ = draggable curve + selected-band dials; orange gain-reduction meter.
- **Logic (premium ref):** premium = **big legible knobs + one hero meter + breathing room**, not more controls; switchable meter (peak vs GR); tasteful per-device identity.
- **GarageBand (your audience):** 3 big draggable dots on an EQ curve; plain-language labels; named "Enhance" presets do the work.
- **FL:** confirms "curve is the primary control, knobs are the fine-tune."

**→ For Boojy:** one reusable device shell (header + visualizer + knob row + fixed MIX knob) for EQ/Comp/Reverb/Delay; universal 0–100% MIX knob; arc knobs (keep Attack/Release as faders); gain-reduction meter on the comp first; GarageBand-style dot-curve EQ with an "advanced" reveal; named presets. **Avoid:** Logic skeuomorphism, an 8-knob wall, FabFilter-level surface area in v1. *(All deferred — see §8.)*

### 5.4 Overall visual language
- **Logic:** premium through **restraint** — one neutral-cool base, colour as *data only*, depth from surface-lightening + soft shadow (not stroke boxes), total radius/divider/elevation consistency.
- **GarageBand:** friendly through **structure** — bigger targets, generous spacing, one clear action, progressive disclosure (not just rounder corners).
- **Ableton:** flat + consistent can read premium; **pick one temperature and commit** (their warm/cool tone control).
- **FL:** the **anti-model** — skeuomorphic gradients, saturated scheme, window soup. What to avoid wholesale.

---

## 6. Design direction — "a calm, precise instrument from deep space"

The north star: **Logic's discipline × GarageBand's friendliness**, with space living only at the edges. Premium through restraint, not decoration. Build the dense desktop tier now, but bake in a larger-radius/target tier + a text-scaler hook so the *same* language scales to tablet later without a redesign.

**Palette — commit to ONE cool temperature.** Re-derive the dark ramp as a single blue-leaning family (keep all 8 token names): `editor ~#0B0E18`, `darkest ~#0E1119`, `dark ~#1A1D2A` *(the big change — chrome joins the content hue)*, up through `hover ~#474D63`. Never pure `#000`. Keep one hero accent (nudge `#40B3E8` one step toward periwinkle/cyan); add at most **one** "starlight" secondary (pale gold/mint) for a single special state. **Accent signals meaning, never decorates.**

**Typography.** Ship **Inter** (UI sans) + **JetBrains/IBM Plex Mono** (all numeric readouts, tabular figures). Lift the scale off its 9px floor: caption 11 / label 12 / body 14 / display 16 mono / subhead 18 / heading 22; three weights only (400/500/600). Route sizing through **one** `BT.scaled(context, size)` helper (text-scaler + ≥1440 width bump, capped ~1.25) — migrate the worst offenders first, not all 323 at once.

**Elevation.** Add a 4-tier token set — base / raised / overlay / modal — with soft **blue-tinted** shadows; reserve 1px borders for focus/selection only. Depth from surface-lightening, not boxes (the Logic signal).

**Space accents — five restrained moves, each with a home:** (1) a **static**, barely-there starfield in the *empty* timeline/editor/start-screen only, fading out when content fills the area (finally making the `// star field renders here` comment real); (2) a soft accent **focus-glow halo** on the active element (extend the record-button pulse to the playing position readout); (3) faint **OLED-style radial gradient** on the readout LCDs; (4) the **piano-roll root band**; (5) **one** orbit/constellation line-art motif used *only* in onboarding/empty/About. Blue-tinted shadows app-wide tie it together.

> **Anti-gimmick guardrails:** no animated/twinkling/parallax starfields, no starfield behind working UI, no neon glow on text/borders, no saturated nebula panel backgrounds, no HUD reticles / hexagons / lens flares / chrome textures. These are what make space themes look cheap.

**Wordmark — yes to ▲udio.** It's the strongest single brand move: the play-triangle is the most universal DAW glyph, so baking it into the "A" makes the wordmark read as *play* and, subtly, a rocket nose — distinctive and on-theme without being a sci-fi cliché. Crucially it also fixes the bug: today `boojy_audio_audi.svg` is literally the word "Audi" in Poppins plus a *separate* floating circle, assembled by a fragile clip hack. Author **one** path-outlined SVG (▲ + "udi" + circle "o" on a shared baseline), triangle filled in accent blue, drop it in a `Flexible`+clip. Kills the misalignment, the clip hack, and the snap-to-zero in one pass. (Also: hover scale 1.05 → 1.02.)

---

## 7. ASCII mockups (before → after)

> Layout truth, aesthetic hint. ASCII can't show colour/type/glow — those are in the notes under each. The real verdict is seeing it on `fvm flutter run`.

### 7.1 Top bar — wide (1280px+)

**Before** — position/tempo/sig/Tap are four equal 15px pills, nothing reads as primary, centre never anchored; title left-aligned:
```
╓──── traffic lights ────────────────────────────────────────────────╖
║ ● ● ●   Untitled - Boojy Audio                                      ║  <- title LEFT (.unifiedCompact)
╠═════════════════════════════════════════════════════════════════════╣
║ ▲udi● Untitled ↶↷ [|]│ [↻Loop][▦Snap][⏱]  ◉ ◼ ●  1.1.1 Tap 120.0 4/4 │ [|'] ⊕ [✓ Ready] ?║
║       file menu undo       modifiers well   transport  └── 4 equal pills ──┘             ║
╚═════════════════════════════════════════════════════════════════════╝
```
**After** — position LCD is the centred hero; tempo/sig demoted to dim satellites inside it; title centred:
```
╓──────────────────────── window title (centred) ────────────────────╖
║ ● ● ●                Untitled — Boojy Audio                         ║  <- .expanded centres title
╠═════════════════════════════════════════════════════════════════════╣
║ ▲udio Untitled  ↶↷ [|]│ ◉ ◼ ●  ┌───────────────┐  [↻][▦][⏱]  [|'] ⊕ ✓║
║ ◄logo►◄project► ◄undo► transport│   12 . 3 . 1   │ ◄modifiers►  mixer+sts║
║                                 │ ─────────────── │                    ║
║                                 │ 120 BPM   4/4   │ <- dim satellites    ║
║                                 └───────────────┘                      ║
║                                 ▲ centred hero LCD (BARS·TIME, ~20px)   ║
╚═════════════════════════════════════════════════════════════════════╝
```
*Notes:* bar bg → cool `dark #1A1D2A`; height a named constant (54px <1440, 60px ≥1440); blue-tinted bottom shadow. LCD = `darkest #0E1119` + faint radial OLED vignette, 1px divider border. Position: JetBrains Mono tabular ~20px/600; satellites ~12px secondary. Playback → faint accent halo on the LCD. Transport circles ≥36px, tokenised colours. All toolbar buttons → `radiusSm 2px`. Wordmark = one ▲udio SVG.

### 7.2 Top bar — narrow (~960px) — **this is the broken state**

**Before** — everything micro-shrinks to 24px, labels gone, four pills still fighting, right group can overflow (this is the collision in your screenshot):
```
╔══════════════════════════════════════════════════════════════╗ (~960px)
║▲● Untit… ↶↷[|]│[↻][▦][⏱]◉◼●1.1.1 Tap120 4/4│[|']⊕[✓] ?║
║   everything shrunk: 24px btns, gaps→1px, labels gone,         ║
║   tempo/sig pills OVERLAP/clip, right group can ⚠ RenderFlex   ║
╚══════════════════════════════════════════════════════════════╝
```
**After** — transport + LCD stay full size; whole low-priority groups drop into a `⋯` overflow menu; nothing collides:
```
╔══════════════════════════════════════════════════════════════╗ (~960px)
║ ▲udio Untit… ↶↷ [|]│  ◉ ◼ ●  ┌───────────┐  [|'] ⊕ ✓     ⋯ ║
║ ◄logo►◄proj► ◄undo► transport│ 12 . 3 . 1 │ mixer+status   ▲ ║
║                              │120 BPM  4/4│                │ ║
║                              └───────────┘                │ ║
║  DROPPED (priority): Loop/Snap/Metro ─┐                   │ ║
║  reachable via the ⋯ priority-plus menu┴───────────────────┘ ║
╚══════════════════════════════════════════════════════════════╝
```
*Notes:* ~3 meaningful breakpoints (full → drop-modifiers → drop-satellites) instead of 6 micro-tiers. Right group wrapped in `LayoutBuilder` + `ClipRect` so overflow is impossible. 36px transport floor holds at every width; no label below 11px.

### 7.3 Transport time display — placement + format toggle

**Before** — one small pill, silent click-toggle, mode lost on reload, ambiguous (5.1.1 vs 5:01):
```
┌────────┐  click→  ┌──────────┐
│ 1.1.1  │ ──────── │ 0:00.000 │   15px mono, NO mode label, mode lost on reload
└────────┘          └──────────┘
```
**After** — (a) top-bar hero LCD and/or (b) a pinned readout on the arrangement ruler; three-state cycle with a quiet tag:
```
(a) TOP-BAR hero LCD          (b) ARRANGEMENT readout (pinned, non-scrolling)
┌──────────────────┐          ╔═══ nav/ruler row (32px) ═══════════════════╗
│ BARS·TIME      ▾ │          ║┌──────────────┐ |1   |5   |9   |13  |17    ║
│   12 . 3 . 1     │  ~20/14  ║│BARS·TIME   ▾ │  ruler bars scroll →        ║
│   0 : 24.13      │          ║│ 12.3.1       │  (LCD pinned left, fixed)   ║
│ 120 BPM    4/4   │          ║│ 0:24.13      │                            ║
└──────────────────┘          ╚════════════════════════════════════════════╝
  cycle:  [BARS] 12.3.1   →   [TIME] 0:24.13   →   [BARS·TIME] 12.3.1 / 0:24.13 (stacked)
```
*Notes:* quiet `BARS/TIME/BARS·TIME` tag in `textMuted` removes the ambiguity; `▾` opens a format menu; **persist the mode via `ProjectPersistence`** (not widget State); double-click pre-fills the *full* value; playing → accent halo; playhead unified to accent-blue `#3B82F6` (retires the clashing warm `#FF5252`).

<details>
<summary><b>7.4 Settings page</b> (before → after)</summary>

**Before** — three dialogs, three header styles, three dropdown chromes, three barrier colours, a unique left-border sidebar:
```
AppSettingsDialog (680×550)        ProjectSettingsDialog (different feel)
┌─────────────────────────────┐    ┌─────────────────────────────┐
│ Settings              [×]   │    │ Project Settings        [×] │ 20px, no icon
│ ┌──────┐ APPEARANCE ─────── │    │ NAME ───────  (letter 0.5)  │ caps 12px
│ │Appear│ Theme  [ Dark   ▾]│rad4│ [ My Song            ]      │ raw fields
│ │ ░░░░ │←left-border accent │    │ BPM  ───────                │
│ │Audio │ AUDIO ──────────── │    │ [ 120 ]  KEY [ C maj    ▾]  │ rad4/6 mix
│ └──────┘  ▲udi● v0.3.0      │    └─────────────────────────────┘
└─────────────────────────────┘    SettingsDialog (3rd, lighter bg) = outlier
```
**After** — one design system across all settings surfaces (and the main UI borrows this breathing room):
```
┌──────────────────────────────────────────────────────────────┐
│  Settings                                          [ × ]       │  one header: 22px, no icon
├────────────┬───────────────────────────────────────────────── │
│ ◉ Appearan │  APPEARANCE ───────────────────────────────────  │  one section header: caps/12/letter-1.5
│   Audio    │  Theme           [ Dark              ▾ ]          │  one SettingsDropdown<T>: standard bg,
│   MIDI     │  Display scale   [ Auto              ▾ ]          │  radiusMd 4, divider border, no underline
│   Saving   │  AUDIO ─────────────────────────────────────────  │
│   Projects │  Output device   [ Built-in Output   ▾ ]          │
│   Updates  │  Sample rate     [ 48 000 Hz         ▾ ]          │
│  ▲udio     │  PROJECT ───────────────────────────────────────  │  Project folded in (Logic model)
│  v0.3.2    │  Name [ My Song        ] BPM [120] Key [C ▾]      │
└────────────┴───────────────────────────────────────────────── ┘
```
*Notes:* one `SettingsSectionHeader` + one `SettingsDropdown<T>` + one container bg + one barrier colour; sidebar active = accent @12% fill (not the unique left-border); dialog on the `modal` elevation tier with `radiusXl 10–12px`; real version + "Boojy Audio" name.

</details>

<details>
<summary><b>7.5 Effect panel</b> — FUTURE reference, not this milestone</summary>

**Before** — every effect is a 24px-header box over full-width 2px sliders (EQ = 5 sliders, MIX is just another row, no knobs, no meter):
```
┌─ device box (172–192px) ───────────────┬─┐
│ ⚡ Compressor                          │●│  ● on/off dot (10px)
├────────────────────────────────────────┤▮│  ▮ tiny meter
│ Thresh ─────●──────────  -18.0dB        │ │  all params = 2px slider, 4px thumb
│ Ratio  ──●───────────────  4.0:1        │ │  labels 10px, vals 9px
│ Mix    ────────────●─────  0.5          │ │  MIX = just another slider row
└────────────────────────────────────────┴─┘
```
**After** — one reusable shell: header (bypass + preset) → visualizer → knob row → fixed MIX knob:
```
┌─ reusable DEVICE SHELL (~280px) ───────────────────────────┐
│ ◉ⓔ Compressor        ‹ Vocal Glue ›           ⌃⌄  ⋯ │  bypass LED + preset ‹prev/next›
├────────────────────────────────────────────────────────────┤
│   ┌──────────── visualizer ───────────┐                     │
│   │ GR ▮▮▮▮▮░░░ -4 dB   in ███ out██  │  hero meter / curve  │
│   └────────────────────────────────────┘                    │
├────────────────────────────────────────────────────────────┤
│    ◍       ◍        ⊟        ⊟         ◍                     │
│  THRESH  RATIO    ATTACK   RELEASE    MIX  ◄─ fixed corner    │
│  -18dB    4:1      10ms     240ms    50%      (every device)  │
└────────────────────────────────────────────────────────────┘
  EQ variant: 3-dot draggable curve; advanced reveal = Freq/Gain/Q for the SELECTED band only
```
*Notes:* one shell for EQ/Comp/Reverb/Delay (consistency = the premium signal); universal MIX knob 0–100% in a fixed corner (100% full / 0% bypass); GR meter on the comp first; per-type BI icon, no skeuomorphism.

</details>

---

## 8. Proposed next milestone — **v0.4 "Visual & UX Polish"**

This makes Boojy stop reading as "generic dark app" without touching how anything sounds. Fix the embarrassing chrome bugs, then land the restrained look-and-feel (one temperature, real font, type that survives 1440p), a proper time readout, and the piano-roll re-treat.

**Design decisions (each with the alternative's cost):**
- **One cool palette, chrome joins content** — highest leverage. *Alt (leave it mixed): cheaper, but every other polish move is lipstick on an incoherent base.*
- **Bundle Inter + JetBrains Mono** — biggest perceived-quality jump per unit effort. *Alt (system fallback): zero work, but it's the dominant "hobby project" tell.*
- **Lift the scale + one `BT.scaled()` helper, migrate visible surfaces only** — *Alt A (migrate all 327 literals): correct end-state but eats the whole milestone. Alt B (bump numbers, no helper): leaves 1440p users with no control point.*
- **Logic-style dual "Beats & Time" readout, persisted** — *Alt (keep the silent one-format toggle lost on reload): exactly your complaint.*
- **Indigo piano lane + root band + real black/white keys** — *Alt (just lighten the greys): keeps the flat-grey ladder; the win is committing to a hue.*
- **Group-priority hiding for the narrow bar** — *Alt (keep micro-shrinking to 24px): that's literally the breakage today.*
- **One ▲udio SVG** — *Alt (keep patching the runtime composite): no constant-tuning fixes a fundamentally fragile assembly. Cost: needs the SVG asset produced first (a design task).*

**In scope:** B1, B2, B9, B10, B11 (quick chrome bugs) · B3 (wordmark) · B7, B8 (narrow-bar resilience) · scoped B4 + B24 (type scale + helper + Inter/mono, visible surfaces) · palette unification (+ relevant B25) · B5 (piano lane) · B6 (dual readout + ruler overlay + persistence) · B42, B27, B20, B32 (cheap, on-path).

**Out of scope (with why):**
- **Effects/device overhaul** (the MIX-knob shell, GR meter, EQ dot-curve) — its own milestone *with engine work* (a GR-data FFI feed). B13's EQ-frequency fix belongs there so it lands in the redesigned panel.
- **Serum/VST3 bug** — a targeted engine investigation, unrelated to visual polish.
- **Full painter/dialog colour sweep (B15/B16)** — genuinely L-sized (392 literals); it's the dedicated "theme-switch correctness" pass that should *precede* any new theme work.
- **Bulk migration of all 327 font literals** — low-risk mechanical follow-up; doesn't need to gate the visible win.
- **Settings consolidation (B12), dead-code delete (B23), emoji→BI (B17)** — real but independent; an obvious next "cleanup" pass.
- **The richer space flourishes** (animated-free starfield, halos, nebula) — additive; earn the foundation first.

**Effort:** large, ~6–9 focused days. Quick chrome bugs are an afternoon; palette + font + scoped scale is the bulk (~3–4 days incl. eyeballing every surface); piano-roll (~1d), dual readout + persistence (~1–1.5d), narrow-bar (~1d).

**Verification (run on `fvm flutter run -d macos`):** About box + settings footer read "Boojy Audio / v0.3.2" · window title centred · ▲udio reads as one clean lockup and truncates gracefully when you drag narrow · drag toward 960px with sidebar + mixer open → no overflow stripe, peripheral controls drop cleanly while transport + LCD stay full-size · chrome and timeline are the same cool family, nothing pure black · small labels noticeably larger/crisper in Inter, readouts in tabular mono · click the readout → Bars → Time → Both, pick Both, save+reopen → still Both · scroll past bar 1 → pinned BAR.BEAT stays visible · piano roll reads as a real keyboard with an indigo lane + root band · tempo scroll stops at 300.

---

## 9. Extra ideas worth a look (beyond what you asked)

- **Empty-state as a brand moment.** Your blank-project timeline is a near-black void — that's prime real estate for the static starfield + the "add a track" prompt + one constellation motif. First-run impression for free.
- **A "Giant" readout** (Logic's tear-off) — a keyboard shortcut that blows the position up full-screen for across-the-room/recording use. Cheap, very pro-feeling.
- **Track icons → BI glyphs (B17)** — the emoji are the most "non-premium" pixels in the mixer; swapping to themeable icons is small and high-signal.
- **Vertical mixer faders** — the horizontal faders in your screenshot are unusual for a DAW; vertical is the muscle-memory convention and reads more premium. Worth a deliberate decision (could fold into the mixer's own pass).
- **Peak-hold + unity notch on faders (B39)** — two painter additions that instantly read "precision tool."

---

## 10. Appendix — sequencing note

The design-system debt cluster is **B16 → B15 → B24/B4** (tokenise dialogs → tokenise painters → font + scale). **Tokenise before attempting any light/high-contrast theme work** — the theme switch is currently broken for a large fraction of the UI, so a "light theme" today would render half-dark. v0.4 unifies the *dark* ramp + the piano lane; the broad painter/dialog sweep is the follow-on "theme-switch correctness" pass.
