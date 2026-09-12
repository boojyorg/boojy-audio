# Boojy Audio v0.6 — Design Recommendations

Synthesized from four design tracks (start screen/empty state, top bar/toolbar, automation/effects, sampler), grounded in screenshots and code. Audience: designer-first; UX outcomes lead, file paths at the end of each section.

---

## Summary table

| # | Question | Recommendation | Effort |
|---|----------|----------------|--------|
| 1a | Start-screen buttons: outlined or borderless? | Keep borderless at rest (action role); unify hover on shared mixin + `divider` hairline | S |
| 1b | Empty arrangement prompt | Replace floating mid-canvas card with a **ghost track row** in the track-header column | M |
| 1c | Loop region on new project | Hide until Loop is toggled or first clip lands (then auto-fit); 1-bar fallback | S |
| 2a | +MIDI/+Audio vs Loop/Snap resting weight | One resting recipe for all bar controls: `textMuted` border + `surface` fill | S |
| 2b | Loop chevron only when active | Chevron always visible, constant width; menu can also enable loop | S |
| 2c | Wordmark→Settings vs name→file menu | **Swap**: wordmark = main menu (app-level), project name = project actions | M |
| 2d | Editor tab "MIDI" label | Rename to **Piano Roll** | S |
| 2e | M/S/R letters | Replace with icons (GarageBand-style), keep state colors + letter-shortcut tooltips | M |
| 2f | Piano-roll toolbar rounding | Unify on `BT.borderMd` (4px); tokenize the hardcoded 2px radii | S |
| 3a | Automation clutter | Keep lane-per-track; **silence empty lanes** (ghost line, no chrome until hover/point) | M |
| 3b | Editor tools in automation lanes | Already mostly wired — verify duplicate, make slice act as draw | S |
| 3c | Global vs per-channel automation toggle | Keep global button; fixing (3a) dissolves the complaint | S |
| 3d | Effects-chain [+] | One affordance: dashed "+ Add an effect" card, always visible, vertically centred | S |
| 3e | EQ improvements | 1) all bands default bell + labeled shape picker, 2) lean spectrum analyzer, 3) cut per-band power | M–L |
| 4 | Sampler unusable | Controls-bar diet (fixes overflow), drop-zone empty state, keyboard strip, on-waveform loop handles, undo plumbing | L |

---

## 1. Start screen & empty state

### a) Open / Settings / Check-for-updates buttons

**Keep them borderless at rest.** The role language says outline = toggle (a state container with an active fill to switch into). These three have no on-state; giving them the Loop/Snap resting outline would teach "outline = might be on," then break that lesson everywhere. The current treatment — filled-accent primary (New Project) + flat dark cards gaining a hairline `divider` border on hover — is the action role correctly scaled up for a modal menu surface.

Two consistency fixes worth doing instead:

- `_ActionButton` / `_UpdateButton` hand-roll duplicate hover state (`_isHovering` + post-frame callbacks ×2) — fold into the shared radius token + `button_hover_mixin.dart`. Hover border = `divider` hairline, never the accent-tinted toggle border.
- "Check for updates" has no icon while its siblings do — either give it one or accept it as a tertiary text action; pick one.

Cost of outlining them instead: visual weight rises and the toggle grammar dilutes app-wide. Not worth it for one screen.

### b) Empty arrangement

The current prompt floats in the *clip area* — dead-center of the space where music will live — so it reads as content, not chrome. It duplicates the header's `+ MIDI / + Audio` buttons and sits over the bar grid, making the canvas feel occupied rather than empty.

How the four DAWs handle it:

- **GarageBand** — never shows an empty arrangement: new-project flow forces a track-type chooser, so you always land with one track.
- **Logic** — same chooser, plus a faint "Drag Apple Loops here" watermark *in the track lane*, not floating mid-canvas.
- **Ableton** — ships with 2 MIDI + 2 audio tracks pre-created; "Drop Files and Devices Here" lives in the drop zone itself.
- **FL Studio** — arrangement empty state is just empty (least helpful model for beginners).

Shared lesson: **put the hint where tracks appear, don't float UI over the clip canvas.**

**Recommended — Option 1, ghost track row:** a single dimmed "phantom" row at the top of the track list: dashed track header with `+ Add a track` and the drag hint inline, clip lane left empty. Drag-over lights the whole row; clicks open the same MIDI/Audio choice.

```
┌──────────────┬────────────────────────────────────────────┐
│ ⋮ + Add a    │ 1    2    3    4    5    6    7    8       │
│ ┄┄┄┄┄┄┄┄┄┄┄┄ │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ ┊ 🎹 MIDI  ┊ │ ┊  drag an instrument or sample here    ┊  │
│ ┊ 〰 Audio ┊ │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ ┄┄┄┄┄┄┄┄┄┄┄┄ │                                            │
│              │            (clean empty grid)              │
└──────────────┴────────────────────────────────────────────┘
```

It previews exactly what will happen (a track appears *here*), lives in chrome territory, kills the duplicate buttons, and keeps the canvas silent. Reuse the existing drag-over accent-wash from `_buildEmptyTimelinePrompt`; delete `_EmptyPromptButton`.

Alternatives considered: **seed one MIDI track** (GarageBand-lite — strong second choice, but "delete the thing the app gave me" is a sour first interaction); **watermark hint only** (quietest/cheapest, but the click affordance is far from the hint).

### c) Loop region default

Current: `playback_controller.dart` defaults to a visible 1-bar yellow region on an empty project. Comparisons: Ableton shows a default brace (loop off); Logic, GarageBand, and FL show nothing until cycle/loop is enabled.

**Don't show a loop region until it means something.** Hide it until (a) the user toggles Loop, or (b) the first clip lands — then auto-fit to that clip's bar-rounded extent. Keep the 1-bar engine default as fallback so toggling Loop on an empty project never produces nothing. A permanently-lit yellow band on an empty project violates silence-when-healthy and trains beginners to ignore the loop indicator, making it *less* legible when actually in use.

**Files:** `ui/lib/widgets/start_screen/start_screen_modal.dart` (`_ActionButton` ~310, `_UpdateButton` ~400) · `ui/lib/widgets/timeline_view.dart` (`_buildEmptyTimelinePrompt` ~1229, `_EmptyPromptButton` ~1326) · `ui/lib/controllers/playback_controller.dart` (loop defaults, lines 40–41) · `ui/lib/widgets/shared/boojy_button.dart`, `button_hover_mixin.dart`

---

## 2. Top bar & toolbar language

### a) Resting weight: +MIDI/+Audio vs Loop/Snap

The mismatch is token drift, not role-driven: `AddTrackButton` rests transparent + `divider` border (near-invisible); the split buttons rest `surface` + `textMuted` border (deliberately heavier — a code comment notes divider read as invisible). GarageBand, Logic, and Ableton all give every top-bar control the same resting chrome; *state*, not role, changes appearance.

**One resting recipe for everything in the bar** — adopt the split buttons' (`textMuted` border, `surface` fill) and lift `AddTrackButton` + `BoojyButton`'s inactive state to match. Roles still diverge where the language says: toggles take `selectionFill` when on; actions never do, they press-flash. Quieting the split buttons down instead would re-introduce the documented invisible-outline problem.

### b) Loop chevron

Currently mounts only when loop is active → ~34px layout shift on toggle, and an inconsistent contract with Snap (whose chevron is always there). **Chevron always visible, constant width:**

```
off:   [ ⟳ Loop │ ▾ ]     chevron textMuted (Snap does exactly this)
on:    [ ⟳ Loop │ ▾ ]     accent fill left zone, accent chevron
punch: [ ⟳ Loop │ →| ]    status text replaces chevron (keep this)
```

Chevron with loop off opens the punch menu anyway; ticking a punch option also enables loop (one click instead of two). Cost: one muted glyph of resting chrome — fair price for a stable shape and a single split-button contract.

### c) Wordmark vs project name — swap

| App | Logo/brand click | Document name click |
|---|---|---|
| GarageBand/Logic | not clickable (native menu bar) | titlebar popover: rename/move/duplicate |
| Ableton | not clickable | not clickable (menus) |
| FL Studio | hamburger = **main menu** | — |
| Figma (closest analog: custom chrome) | logo = **main menu** (file ops, settings inside) | name chevron = **doc actions**: rename, duplicate, versions |

The convention is unambiguous: **brand mark = main menu, document name = document-scoped actions.** Nobody makes the logo open Settings. **Do the swap**, with one refinement: project name opens *project actions* (Rename in-place foregrounded, Save As, Save New Version, Export, Close), not a settings panel. App-level items (New, Open, Settings, About, Check for Updates) move under the wordmark; the engine-failed red triangle still works, its menu just opens with Settings highlighted. Cost: Settings becomes two clicks and one habit relearns — acceptable pre-1.0 for new users guessing right first time.

### d) Editor tab label

Rename hardcoded `'MIDI'` → **Piano Roll**. Competitors name the surface, not the data format (FL/Logic/GarageBand: "Piano Roll"; Ableton: "Clip view"); "MIDI" is pure protocol jargon, while everyone can see piano keys and infer the name. It also stays honest for sampler tracks and parallels "Audio Editor". Check `_buildCollapsedTabButton` at narrow widths (~35px wider); collapsed form can stay icon-only.

### e) M/S/R(/I) — icons

Logic and Ableton use letters (pro shorthand, dense mixers); **GarageBand uses icons** — and GarageBand is the stated model. Letters fail the "guessable without a manual" test (M = Mute? Mono? MIDI? Metronome?).

```
letters:  [M] [S] [R] [I]
icons:    [🔇] [🎧] [⏺] [〜]   mute=speaker-off · solo=headphones · arm=red dot · monitor=input wave
```

Keep existing state colors (yellow solo, red arm) — color carries state, icon carries meaning. Tooltips keep the letter shortcut ("Mute (M)"). The current bare `ElevatedButton`s in `track_header.dart` / `track_mixer_strip.dart` should migrate to proper toggle-role styling in the same pass. Honest cost: keep icons ≥ 14px (a 10px letter is crisper than a 12px glyph at the mixer's smallest widths), and pros scan letters marginally faster — right trade for this audience.

### f) Piano-roll toolbar rounding

`piano_roll_controls_bar.dart` hardcodes `Radius.circular(2)` and `BoojyButton` defaults to `BT.borderSm` (2px), while the top bar settled on `BT.borderMd` (4px). **Unify on `borderMd`**; reserve `borderSm` for tiny inner elements (badges, meter caps, swatches) and document the split in `tokens.dart`. Replace the hardcoded literals with tokens while in there. A two-tier "compact = 2 / standard = 4" rule is defensible but is exactly the rule-shape that produced this drift.

**Suggested batching:** (f) token sweep → (a) resting-weight unify → (b) loop chevron → (d) rename = one cohesive "toolbar consistency" PR. (c) and (e) are behavior changes worth their own PRs.

**Files:** `ui/lib/widgets/shared/boojy_button.dart`, `shared/add_track_button.dart`, `transport_bar/loop_split_button.dart`, `transport_bar/snap_split_button.dart`, `transport_bar.dart`, `editor_panel.dart` (`_buildTabButton(1, BI.piano, 'MIDI')` ~956), `track_header.dart`, `track_mixer_strip.dart`, `piano_roll/piano_roll_controls_bar.dart`

---

## 3. Automation

### a) Why it feels cluttered — silence the empty lanes

With the global `Automation` pill on, *every* track grows a lane, and each empty lane pays full chrome: `Volume ▾` dropdown, `0.0 dB` readout, an extra icon button, and a full beat grid — while the same `Volume ▾ 0.0 dB` row also renders on every mixer strip. In the screenshot, the identical control appears 8 times for one actual automation curve. (`timeline_track_list.dart` renders a lane for all tracks when `automationVisible`, synthesizing an empty Volume lane when none exists.)

References: GarageBand's empty lane is just a flat line — no grid, no value chrome until touched. Logic same, picker tucked into the track header. Ableton overlays automation on clips with opt-in extra lanes. FL uses automation clips (different model, not a beginner fit).

**Keep the lane-per-track model; make empty lanes quiet** (GarageBand's move):

- Empty lane = flat ghost line at current fader value — no grid, no readout, no extra icon. Chrome appears on hover/first point.
- Parameter picker becomes a quiet `Volume ▾` text label in the lane's left gutter, aligned under the track name.
- Value readout only while dragging (the `onPreviewValue` hook is already wired).
- Drop the duplicate `Volume ▾` rows from mixer strips while timeline lanes are visible — one home per control.

```
Before (per track, even empty):          After:
┌──────────────────────────────┐         ┌──────────────────────────────┐
│ Synthesizer        [clips]   │         │ Synthesizer        [clips]   │
├─Volume ▾  0.0 dB  ⟳──────────┤         ├──────────────────────────────┤
│ ┊grid┊grid┊grid┊grid┊  ●──●  │         │ Volume ▾            ●────●   │   ← has points: line + quiet label
└──────────────────────────────┘         └──────────────────────────────┘
┌─Volume ▾  0.0 dB  ⟳──────────┐         ┌──────────────────────────────┐
│ ┊grid┊grid┊grid┊grid┊ (empty)│         │ ······ ghost flat line ····· │   ← empty: nothing else
└──────────────────────────────┘         └──────────────────────────────┘
```

### b) The 5 editor tools inside lanes

**They already mostly work** — `TrackAutomationLaneWidget` switches on `toolMode` (draw/select/eraser/duplicate/slice, lines 256–347). This is a confirm-and-finish job: verify **duplicate** isn't a silent no-op, and make **slice** behave as draw inside lanes (no meaningful target on a point curve; a dead cursor reads as a bug). Matches Ableton/Logic and honours the settled one-global-toolset decision.

### c) Global vs per-channel toggle

**Keep the global button.** GarageBand and Logic both use one global switch revealing all tracks — it works because their empty lanes are quiet. The clutter Tyr felt was (a), not (c); fixing (a) dissolves it. If more control is still wanted afterwards, a hybrid: global button reveals lanes only on tracks *with* automation plus the selected track, with a small per-track chevron for the rest. Per-channel-only toggles cost: N hidden buttons, no all-at-once overview, and forgotten mystery lanes — it optimises for the pro case Boojy doesn't serve.

⚠ Pan/clip automation is deliberately hidden (no engine support) — don't let this work "fix" the dropdown into offering Pan.

**Files:** `ui/lib/widgets/timeline/track_automation_lane_widget.dart` (tool switch 256–347), `ui/lib/widgets/timeline/timeline_track_list.dart` (~74, 569–625), `ui/lib/controllers/automation_controller.dart`

---

## 4. Effects chain & EQ

### a) The [+] / "Add an effect" hint

There are currently *two* add affordances: empty chain → a top-aligned 150px hint card (misaligned against the chain-height-centred signal arrow); non-empty chain → a 40px-wide [+] strip stretched to full chain height, which reads as a weird tall slot, not a button.

**One affordance, always visible, vertically centred** — Ableton's perpetual "Drop Audio Effects Here" end-of-chain zone is one of its best beginner features:

- Delete the tall [+]. The trailing slot is always the dashed hint card (~150×96), wrapped in `SizedBox(height: chainHeight)` + `Center`.
- It's both the drop target and the click target (same add menu). With 10+ effects it scrolls at the end of the chain — fine; that's where the eye already is when adding.
- Copy: `+ Add an effect` / `drag from library`. Dashed border, `textMuted`, press-flash on click.

```
┌ Synthesizer ┐▐│→ ┌ EQ ───────┐▐│→ ┌ Reverb ──┐▐│→
│  oscillator │▐│  │  curve    │▐│  │ size 0.5 │▐│   ╭┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮
│  filter     │▐│  │  bands    │▐│  │ damp 0.5 │▐│   ┊ + Add an effect┊  ← centred on
│             │▐│  │           │▐│  │ mix  0.3 │▐│   ┊ drag from libr.┊    chain height
└─────────────┘▐│  └───────────┘▐│  └──────────┘▐│   ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯
```

### b) EQ for v0.6 — ordered by value

Engine defaults are Low shelf / Bell / High shelf, flat (`effects.rs:308–330`).

**1. Fix the edge-band surprise (highest value, cheapest).** "I moved the right dot and everything past it changed" is a real expectation bug. Logic and FL ship shelf edges; **Ableton's EQ Eight defaults all enabled bands to bell** — follow Ableton: default all three bands to bell, make shelf an explicit, *labeled* choice via a shape picker on the selected band:

```
selected band:   Freq      Gain      Shape: ( ∩ Bell )( ⌐ Shelf )( / Cut )
                 294 Hz   −2.1 dB           outline-fill selection role
```

Tooltip copy: Bell = "changes around the point", Shelf = "changes everything past the point". The dedicated Low Cut/High Cut buttons already cover the real edge use-case. "More bass" via shelf becomes one extra click — predictability is worth it. (The curve fill already shades the affected area and the surprise happened anyway — shading alone doesn't fix it.)

**2. Spectrum analyzer behind the curve (biggest learning value, medium-high cost) — yes, the lean version.** Ableton/FL/Logic all do it; for a beginner DAW it's arguably *more* pedagogically valuable. Scope ruthlessly: one post-EQ FFT tap, ~30–60 smoothed log-spaced bins over FFI, dim grey fill behind the curve, ~30fps, no peak-hold, no pre/post toggle, off when the panel is closed. Real engine + FFI work — if it threatens the cycle it degrades gracefully to v0.7 without blocking items 1 and 3.

**3. Per-band power icon (cheap polish).** A bare power glyph next to a trash can is ambiguous ("off vs delete"). A/B-ing a single band is a pro habit; delete + undo covers beginners. **Cut the per-band power for v0.6.** If band bypass must stay, replace the glyph with a labeled `On` outline-toggle chip and dim the band's handle + curve contribution when off, so state is visible in the graph.

**Order: 1 → 2 → 3** (3 rides along with 1).

**Files:** `ui/lib/widgets/device_chain/device_chain_view.dart` (`_buildEffectHintPlaceholder` ~1544, full-height `_buildAddButton` ~1600), `ui/lib/widgets/device_chain/eq/eq_curve_painter.dart` (`EqShape`), `engine/src/effects.rs` (~308)

---

## 5. Sampler

### Why it "can't be made to work" — concrete failures

1. **Load is literally unreachable.** The controls bar is a non-wrapping `Row` of ~12 groups; `Load` sits far right after a `Spacer` and is clipped off-screen at real panel widths (the screenshot shows the overflow stripes). This alone explains the experience.
2. **Default entry path creates a sampler with no sample and no prompt.** Picking "Sampler" lands you on a waveform view of nothing, with Warp/Sig/Pitch/Start/Length all live for a 0-second sample. The empty state says *"Select a Sampler track to view the sample"* — wrong message, no Load CTA.
3. **No way to hear the sample from the editor** — no audition button, no onboard keys.
4. **The bar is the Audio Editor bar wearing a sampler hat.** Start/Length/Sig/Warp/BPM/÷2/×2 are clip-warping concepts; a bars-beats `Start 1.1.1` as *loop start* is actively misleading for a pitched one-shot instrument.
5. No drag-and-drop onto the editor; none of the parameter edits go through Commands — nothing is undoable (violates the repo's own rule).

### Reference comparison

- **GarageBand Quick Sampler** — the model. Drop a file on the big waveform; draggable start/end/loop handles *on the waveform*; a handful of labelled controls; built-in keyboard strip to audition. One screen, zero day-one modes.
- **Logic Quick Sampler** — same plus Classic/One-Shot/Slice modes — the modes are where beginners get lost; evidence for *cutting* modes.
- **Ableton Simpler** — waveform front-and-centre, Warp folded behind a small toggle. Even Ableton keeps warp visually subordinate; Boojy gives it top billing.
- **FL Studio channel sampler** — knob soup across tabs; the confusing one. The current Boojy bar is closer to FL than GarageBand.

### (a) Minimal beginner flow — Load → see waveform → play on keys

1. Add Sampler track → editor shows a big drop zone: "Drop an audio file here, or **Browse…**" — the empty state *is* the load UI.
2. File loads → waveform fills the panel, auto-zoomed; a one-shot plays once as confirmation.
3. Slim keyboard strip at the bottom, root note highlighted; click a key or use musical typing to hear it pitched; drag the root marker to retune.
4. Loop is opt-in: toggle Loop → start/end handles appear **on the waveform**, not in bars-beats fields.

### (b) Redesigned layout

```
┌──────────────────────────────────────────────────────────────────────┐
│ [⟳ Loop]  Atk (▭▭──) 1ms   Rel (▭──) 50ms │ Root [C4 ▾] │ [Reverse]  │
│                                                  Vol −3.0dB  [Load ▾]│
├──────────────────────────────────────────────────────────────────────┤
│            ┃▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▙▖                              │
│            ┃▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▛▘   kick.wav · 0.8s           │
│            ┃          big waveform, drop target, loop handles        │
│            ┃◄ loop start            loop end ►                       │
├──────────────────────────────────────────────────────────────────────┤
│ ▁▁█▁█▁▁▁█▁█▁█▁▁  keyboard strip · root C4 marked · click to audition │
└──────────────────────────────────────────────────────────────────────┘
```

- **One row of controls, 6 items max**: Loop (toggle=outline), Atk/Rel capsules, Root dropdown, Reverse (toggle), Volume, Load (action role). Fits a normal panel width — the overflow bug dies by subtraction, not by adding a scroll.
- **Loop handles on the waveform** — the painter already draws loop markers; most of the existing nav-bar drag logic reuses directly.
- **Keyboard strip** is the one genuinely new piece — the GarageBand signature that makes the instrument feel alive. If note-preview FFI exists for musical typing it's mostly UI; if not, it's the only new FFI needed.

### (c) Cut for v0.6

- **Warp group entirely** (Warp/Stretch-vs-Re-Pitch, BPM, ÷2/×2) — wrong mental model for an instrument; #1 source of "what is all this."
- **Start/Length bars-beats fields + Sig dropdown** — replaced by on-waveform handles.
- **Pitch st/ct display** — Root covers the beginner case; fine-tune can return post-v0.6.
- **Keep**: Reverse, Volume. **Don't add**: slice mode, multi-zone mapping, filter/LFO, crossfade looping — Kontakt's slope, explicitly forbidden by the design philosophy.

Cost: power users lose warp from the sampler — acceptable; loop-warping belongs on an Audio track (that editor keeps everything), and the engine params remain saved/loadable, just unexposed.

Same-pass fixes: route sampler param changes through the Command pattern (currently raw `setSamplerParameter` calls, none undoable) and wire `desktop_drop` on the waveform (dependency already in the app).

**Files:** `ui/lib/widgets/sampler_editor/sampler_editor.dart` (empty state ~421, params ~227–231, gestures ~544+), `sampler_controls_bar.dart` (Load after Spacer, 199–200), `sampler_waveform_painter.dart`; entry paths `ui/lib/screens/daw/mixins/daw_track_mixin.dart:245–250`, `daw_library_mixin.dart:163–220`

---

## Suggested v0.6 design-work order

Given Tyr's stated priorities (sampler working, EQ improved), ordered by priority-fit then risk:

1. **Sampler rescue** (L) — controls-bar diet first (fixes overflow + unreachable Load by subtraction), then drop-zone empty state, keyboard strip, on-waveform loop handles, undo plumbing. This is the #1 stated priority and the only outright broken flow.
2. **EQ band defaults + shape picker** (S–M) — fixes a confusion users hit on first contact; cut/replace the per-band power glyph in the same pass.
3. **EQ spectrum analyzer, lean scope** (M–L) — the marquee improvement of the "Sound" cycle if budget allows; degrades gracefully to v0.7 without blocking anything.
4. **Toolbar consistency PR** (S) — token-radius sweep + resting-weight unify + always-on loop chevron + "Piano Roll" rename. Four small changes, one cohesive batch, near-zero risk.
5. **Automation quiet-lanes** (M) — biggest silence-when-healthy win outside the sampler; plus the small tool-verification pass (duplicate, slice-as-draw).
6. **Effects-chain add affordance** (S) — single centred dashed card; quick win, pairs naturally with the EQ work since you're in the device chain anyway.
7. **Empty-arrangement ghost row + loop-region hiding** (M + S) — first-run polish; valuable but not on the stated priority path.
8. **Wordmark/project-name swap** and **M/S/R icons** (M each) — own PRs, behavior changes; schedule after the above or defer to v0.7 if the cycle runs short.

Items 1–3 are the version's substance; 4–6 are low-risk consistency batches that can interleave; 7–8 are the first to defer.