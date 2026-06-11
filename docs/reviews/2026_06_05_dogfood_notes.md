# Dogfood notes — Tyr, 2026-06-05 (v0.5.1 build)

Captured verbatim-in-spirit from a screenshot walkthrough the day v0.5.1 was tagged. These are
**ideas, not directives** — Tyr explicitly asked the review chain to do its own thorough analysis
too. Cross-reference against `2026_06_05_ui_ux_review.md` at triage; agreement = strong signal.
Screenshots referenced are the dated PNGs staged in `_screenshots/` for the review run.

## Start screen (`start-screen-2026-06-05.png`)

- Wordmark: "Boojy" and "Audio" are not the same size.
- The yellow O in "Boojy" should sit slightly lower.
- "Open" / "Settings" / "Check for Updates" boxes are **too mellow** — consider the grey
  inactive-button colour used elsewhere (e.g. Loop/Snap inactive state).
- Project-card image preview should be **full width** (see the "30th May 2026" card — the
  track preview stops short; make it continue longer).
- **Remove BPM** from the project card.
- Dates as relative — "6 days ago" / "1 week ago" — possibly on its own line below the name.

## Top bar (`top-bar-2026-06-05.png`, `top-bar-narrow-2026-06-05.png`)

- Overall: pretty happy.
- `[+ Audio]` button: the audio glyph could look better.
- **Narrow layout doesn't look good.** Idea: Loop/Snap/Play/Stop/transport/BPM scale down
  *together* as one group, instead of only transport/BPM shrinking.

## Arrangement (`arrangement-2026-06-05.png`, `arrangement-empty-2026-06-05.png`)

- Empty state ("Drag an instrument…" / MIDI Track / Audio Track) doesn't look good — wants
  design ideas for a nicer empty state.
- Populated view is decent, but **track/clip identity is unclear**: a clap or audio clip shows
  only a note icon, no name — what should show instead?

## Piano roll (`piano-roll-2026-06-05.png`)

- Overall: quite happy.
- Unsure the dark blue C-note lane colour looks good.
- Snap/quantize **divider stops a couple of pixels short** of full height — should span fully.
- Preview-note button is bright blue — should match the other buttons (blue border + dark
  blue fill).
- **Missing: vertical (y-axis) zoom** — can't stretch note rows thinner/thicker.

## Mixer sidebar (`mixer-sidebar-2026-06-05.png`)

- Mostly good.
- M/S/R letter buttons → **icons/symbols like GarageBand**? Wants suggestions for which glyphs.
- The `[ln1v]` (input selector) on Audio tracks looks bad — drop for now, or redesign?

## Effects / Master (`master-effects-2026-06-05.png`, applies to graphic EQ panel too)

- Enable/disable blue circle should be a bit **larger**.
- Each effect should get a **distinct icon/symbol** (currently uniform).
- **BUG:** dragging a sound onto the thin blue insert-line (rather than inside the `[+]` slot)
  does nothing — silent drop.
- `[+]`-add-effect pinned at top doesn't look good — consider **centring vertically**.

## Library (`library-2026-06-05.png`)

- Many **sound names get cut off** — unsolved; wants ideas.
- Search field: should be **full width of the panel and boxless** (or the box full-width) —
  cleaner, in line with the Loop bar in the arrangement section. (Rounded-corner inset box
  out.)
- **Hover state doesn't show** over a sound or folder.

## Settings (`settings-2026-06-05.png`)

- Expanding a section requires clicking the **triangle** — clicking the label ("Audio") should
  work too.
- Feels **cramped**; the theme dropdown (and similar option controls) are too chunky.
- Dislikes the thin strip left of the "Appearance" sidebar button.
- Make the settings popup ~**10% larger** to fit more per page.
