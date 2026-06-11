# Arrangement Tool-State Research — 2026-06-07

**Trigger:** the timeline gesture bug hunt (PR #71) exposed that the arrangement's tool state is
invisible and accidental — one `currentToolMode` shared with the piano-roll toolbar, plus hidden
Z/X/C/V/B shortcuts whose only feedback is the cursor. Before redesigning, Tyr asked for research
on how other DAWs solve this, with four lenses: **speed, intuitiveness, beginner-friendliness,
familiarity** — plus specific edge cases: multi-select when draw is default, mouse travel to a
distant toolbar, and how any of this works on touch.

## Survey: seven models

| Model | Who | How it works | Speed | Beginner |
|---|---|---|---|---|
| **No tools, pointer does everything** | GarageBand (Mac/iPad) | Position decides (edges trim, body moves); empty-drag = rubber-band select; iPad: tap-region-again → action menu (Cut/Split/Join…), Split = scissors you drag down; multi-select = touch-hold + tap others | High for common ops | Best in class |
| **Time-range selection, no clip multi-select** | Ableton arrangement | You select *time*, not clip objects; click inside a clip sets the **insert marker**; ⌘E splits at marker or isolates a dragged range; non-adjacent clip selection is simply impossible | High for keyboard users | Confusing coming from object-based editors |
| **One global Draw toggle** | Ableton (B key) | Single visible binary near the transport: Draw on = pencil, off = pointer; everything else is modifiers/context | High | Good — one switch, always visible |
| **Per-window tools + cursor-local picker** | Logic desktop | Arrange and piano roll each keep their own tool; **T pops the tool menu at the pointer** (pick by key or click); separate ⌘-click tool | Highest for pros | Steep — multiple tool slots |
| **Momentary function buttons** | Logic for iPad | No persistent palette: Split / Multiple-Select are *toggled per task* in the tracks-area menu bar; Split shows a scissors handle on the selected region, swipe down to cut; tap again to leave the mode | Medium | Good — mode is a lit button you can see |
| **Smart tool (click zones)** | Studio One, Pro Tools | One tool; clip is zoned — upper half = range/trim, lower half = move/select; no switching for the common edits | High, one-handed | Medium — zones are invisible until learned |
| **Persistent global palette** | FL Studio, Cubasis 3 (touch) | Always-visible toolbar shared across views; touch apps lean on it because there are no modifier keys | Medium (travel cost) | Familiar to FL users; legible but chrome-heavy |

## Tyr's edge cases, answered

**1. "Click a clip and the beat you clicked gets highlighted, then press a button to split" —**
that *is* Ableton's insert-marker model, and **Boojy's piano roll already has it** (click empty
piano-roll space sets `insertMarkerBeats`; ⌘E splits there; the timeline never got it — arrangement
⌘E only splits at the playhead). Extending it to the arrangement is cheap, keyboard-fast,
familiar to Ableton users, and — crucially — **touch-compatible**: tap sets the marker, an
on-screen Split button cuts. It removes the *slice tool's* reason to exist.

**2. Multi-select when draw is the default tool —** the industry answer is that **empty-space
drag means rubber-band select** in every object-based DAW (GarageBand, Logic, Cubase, Studio One).
GarageBand can afford this because you never "draw" clips there — you record or drag loops in.
Boojy's drag-to-create is the one feature fighting for that gesture. Three resolutions:
- *Shift+drag selects* (status quo) — works, but undiscoverable; beginners won't find it.
- *Empty-drag selects; create via double-click then edge-drag* — standard, but turns Tyr's
  one-gesture "3-bar clip" into two gestures.
- *A visible Draw toggle decides* (Ableton B): off → empty-drag selects; on → empty-drag creates.
  One legible mode instead of five invisible ones.

**3. Mouse travel (tools live at the bottom, arrangement at the top) —** confirmed real and
solved two ways in the wild: **cursor-local pickers** (Logic's T menu pops at the pointer;
right-click menus) and **not needing tools at all** (smart zones, modifiers, insert marker + ⌘E).
A fixed palette near the arrangement is the weakest fix — it halves the travel instead of
removing it.

**4. Touch / tablet —** modifiers, hover cursors, and right-click don't exist on touch, so our
current modifier-override scheme cannot translate. The touch-native patterns are: **momentary
function buttons** (Logic iPad), **tap-again action menus + drag-down scissors** (GarageBand
iPad), **touch-hold then tap to multi-select**, and **persistent palettes** (Cubasis — works but
chrome-heavy). Anything we pick now should leave room for a function-button strip later rather
than assume modifiers forever.

## The synthesis: three coherent packages

Common to all three (uncontroversial, all four lenses agree):
- **Arrangement insert marker + ⌘E split-at-marker** (port from piano roll) + right-click
  **"Split here"** at the click position.
- **Smart edge zones stay** (trim at edges, move in body — already true).
- **Alt = erase, Cmd = duplicate-drag** stay as temporary modifiers on desktop.
- The piano-roll 5-tool palette stays **editor-local** — it's visible there and works.
- Timeline's hidden persistent Z/X/C/V/B switching is removed in every package.

### P1 — Pointer-first (GarageBand discipline)
No arrangement modes at all. Empty-drag = box select (standard); create = double-click (1 bar)
then drag the right edge, or drag-create survives only as a modifier (e.g. hold D and drag).
- **Speed:** loses the one-gesture sized create. **Intuitive/beginner:** strongest — every
  gesture matches GarageBand/Logic muscle memory. **Touch:** cleanest base layer.

### P2 — One visible Draw toggle (Ableton discipline) ← *research lean*
A single pencil toggle in the arrangement corner (key: B). **Off (default):** pointer — empty-drag
box-selects, clips click/move/trim, marker + ⌘E splits. **On:** empty-drag creates sized clips
(today's draw behaviour).
- **Speed:** keeps one-gesture create, one key away; everything else needs no mode. **Beginner:**
  one lit, visible switch instead of five invisible states. **Familiarity:** Ableton users know B;
  GarageBand users never need to touch it. **Touch:** the toggle is already an on-screen button;
  function-button strip can join it later.

### P3 — Per-view tools + cursor-local picker (Logic discipline)
Keep five arrangement tools but give them their own state (decoupled from the piano roll), a
small indicator chip, and **T pops the tool menu at the cursor**.
- **Speed:** best for tool-heavy pros. **Beginner:** worst — two tool states to understand.
  **Touch:** needs the chip to become a palette. Most code; keeps the mode-error class alive
  (visible now, but still modal).

## Recommendation

**P2, with P1's marker/double-click foundations** (which are in every package anyway). It is the
only option that keeps Tyr's one-gesture drag-create *and* gives beginners a standard pointer
default *and* has a visible, touch-ready mode indicator *and* deletes the invisible-mode bug class.
P3 only wins if persistent eraser/slice modes in the arrangement are a real personal workflow —
the insert-marker port makes slice-as-a-tool redundant, and Alt-drag already covers erase sweeps.

**Suggested scope if adopted (own batch, after join/normalize):** arrangement insert marker + ⌘E +
"Split here" · Draw toggle button + B key + cursor swap · empty-drag = box select when Draw off ·
decouple `currentToolMode` (editor keeps it; timeline gets the toggle) · remove timeline Z/X/C/V/B
block · shortcuts overlay update.

## Sources

- [Split and join regions in Logic Pro for iPad — Apple Support](https://support.apple.com/guide/logicpro-ipad/split-and-join-regions-lpip98d86a3e/ipados)
- [Select regions in Logic Pro for iPad — Apple Support](https://support.apple.com/guide/logicpro-ipad/select-regions-lpip39124d82/ipados)
- [Edit regions in GarageBand for iPad — Apple Support](https://support.apple.com/guide/garageband-ipad/edit-regions-chsec12c15d/ipados)
- [Arrangement View — Ableton Reference Manual v12](https://www.ableton.com/en/manual/arrangement-view/)
- [Splitting and Consolidating Clips — Sonic Bloom (Ableton workflow)](https://sonicbloom.net/ableton-live-workflow-tips-part-4-splitting-and-consolidating-clips/)
- [Selecting multiple clips in Arrangement — Ableton Forum (continuous-selection policy)](https://forum.ableton.com/viewtopic.php?t=144187)
- [Studio One: More Efficient Editing (Smart Tool) — PreSonus KB](https://support.presonus.com/hc/en-us/articles/360003819512-Studio-One-More-Efficient-Editing)
- [Arrange View Mouse Tools — Studio One manual](https://s1manual.presonus.com/Content/Editing_Topics/Arrange_View_Mouse_Tools.htm)
- [Tools — Cubasis 3.7 manual](https://www.steinberg.help/r/cubasis/3.7/en/cubasis/topics/tools_r.html)
- [Review: Steinberg Cubasis 3 — macProVideo](https://macprovideo.com/article/audio-software/review-steinberg-cubasis-3-for-ios)
- [Key commands for Tool Menu (T at pointer) — Logic Pro for Mac, Apple Support](https://support.apple.com/guide/logicpro/tool-menu-lgcp0182c4e5/mac)
