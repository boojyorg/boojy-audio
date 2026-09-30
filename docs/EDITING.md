# Editing model

How you create, select, move, split and delete things in Boojy: clips in the arrangement, notes in
the piano roll, points in automation lanes. One set of rules for every view and every device.

> **This is the plan, not the current app**, which still has the five-tool row (Draw, Select,
> Erase, Duplicate, Slice; keys Z X C V B). Reviewers and agents: the five tools' problems are
> known and being replaced by this design; don't report them or propose other tool models. Bugs
> that would survive the change (undo, clip overlap, snapping) are still worth reporting.

**Status:** agreed with Tyr 2026-09-29 ("B+"), scheduled for v0.7, not built. A throwaway Mac +
iPad prototype (no sound, default mode as a setting) comes first and must answer: does Select +
double-click feel fast enough for note entry, is Draw-tap-to-remove natural, does the action bar
get in the way, and should one-finger drag on touch scroll or select.

## What changes for the user

Today you pick one of five tools (Draw, Select, Erase, Duplicate, Slice) from a row in the
editor header, and the tool decides what a click does. Draw is the default, so clicking empty
space to deselect creates a note by accident, and a simple beat costs about eight trips to the
tool row. On a touchscreen, with no modifier keys, every change is a trip.

B+ turns this around: **pick a thing, then act on it.** Clicking selects by default.
Double-clicking empty space creates. The actions for whatever is selected appear next to it.
A single Draw toggle is there for painting lots of notes quickly. The same rules work in the
arrangement, the piano roll and automation, and with a keyboard and mouse, a mouse alone, a
trackpad or a finger.

```text
Today                                         B+
[✏] [↖] [⌫] [⧉] [✂]   ← mode first            [ ↖ Select | ✏ Draw  B ]   ← one toggle
click = whatever the tool says                click = select, double-click = create

                                               ┌─────────────────────┐
                                               │[■]   [■]   [■]   [■]│ ← selection
                                               └─────────────────────┘
                                                ⧉ Duplicate  ✂ Split  ⌫ Delete  ⋯
```

## The rules

### Same verbs in every view

| | Arrangement | Piano roll | Automation | Audio editor |
| --- | --- | --- | --- | --- |
| **The thing** | clip | note | point | *(later, see Open questions)* |
| Click | select | select | select | |
| Drag | move | move | move | |
| Drag an edge | resize | resize | — | |
| Double-click empty space | new clip (MIDI tracks; 1 bar, as today) | new note | new point | |
| Double-click a thing | nothing (see Deleting) | remove it | remove it | |
| Box select | drag on empty space | same | same | |
| **B** | Draw on/off | Draw on/off | Draw on/off | hidden |
| Delete / ⌫ | delete selection | same | same | |
| Cmd+D | duplicate selection | same | same | |
| Cmd+E | split selection | same | — | |
| Cmd+C / Cmd+V | copy / paste | same | same | |
| Right-click / long-press | the `⋯` menu | same | same | |
| Esc | clear selection, Draw off | same | same | |

**If a verb makes no sense in a view, it is hidden, not given a different meaning.** The Draw
toggle disappears where there is nothing to draw.

### Select is the default

Clicking empty space deselects. It never creates anything by accident. Dragging on empty space
draws a selection box. This matches the arrangement's main job (moving things around), every
other app people use, and touch, where a stray tap must not create notes.

Considered and rejected: Draw as the default (today's behaviour). It's faster for pure note entry,
but it creates notes and clips when you meant to deselect, makes group selection a modifier trip,
and on touch every stray tap creates something. The speed it offers is recovered by
double-click and by Draw mode itself.

### Draw mode

Draw is for painting many notes, clips or points quickly. While it's on:

- **Tap or click empty space** adds a note (at the last-used length, which already exists).
- **Tap or click a note** removes it. Draw works like a drum machine's step grid.
- **Drag a note** moves it; **drag an edge** resizes it.
- **Shift-drag** still draws a selection box.

Turning it on and off:

- **B** switches Draw on or off. **Hold B** draws only while the key is down; releasing it
  returns to Select, so there is no leftover mode to trip over.
- The **labelled toggle** `[ ↖ Select | ✏ Draw  B ]` shows the state in words and the shortcut.
- In Draw mode the cursor is a pencil.

### Deleting

| You want to… | Keyboard + mouse | Mouse only | iPad |
| --- | --- | --- | --- |
| Remove one note fast | double-click it | double-click it | double-tap it |
| Remove lots while making a beat | B, then click each | Draw on, click each | Draw on, tap each |
| Remove a group | box-select, then ⌫ | box-select, then 🗑 on the bar | box-select, then 🗑 |
| Undo a mistake | Cmd+Z | Edit menu or undo button | undo button |

**Clips are not deleted by double-click.** A clip can hold minutes of work and a note is one click
to redo, and people often double-click a clip expecting it to open. Clips are deleted from the
action bar, the Delete key or the menu.

Considered and rejected: **long-press to delete** (on touch, long-press has to open the menu,
since there is no right-click) and **right-click to delete** (right-click means "menu" everywhere,
and touch has no right-click).

### The action bar

It appears next to the selection only while something is selected. It holds three or four actions
plus `⋯`, which opens the same menu as right-click and long-press.

- Notes: `⧉ Duplicate   ✂ Split   ⌫ Delete   ♩ Quantize   ⋯`
- Clips: `⧉ Duplicate   ✂ Split   ⌫ Delete   ⋯` (rename and colour are in `⋯`)
- Points: `⌫ Delete   ⋯`

***Split** cuts where you last clicked on the selected clip or note (a faint line shows the spot;
with a mouse a hover line previews it). The cut snaps to the grid.

The bar sits above the selection and flips below it near the top edge. It is not a tool badge:
it shows actions for the selection, not the current mode.

### Modifier keys and shortcuts

Keys speed up actions that are already one click or tap away. They are never the only way.

| Key | Today | B+ |
| --- | --- | --- |
| Option/Alt (hold) | Erase tool | **Option-drag = copy** (Finder, Figma and most DAWs use this) |
| Cmd/Ctrl (hold) | Duplicate tool | **Cmd-drag = ignore the grid** while dragging |
| Shift (hold) | Select tool | Shift-click adds to the selection; Shift-drag box-selects in Draw mode |
| Z / X / C / V | Draw / Select / Erase / Duplicate tools | freed |
| B | Slice tool | **Draw on/off; hold for temporary Draw** |
| Cmd+E | split selected clip at the playhead | split selection (see Open questions) |
| Cmd+C / Cmd+V on clips | disabled menu items | copy / paste clips |

## Every input method

| | Keyboard + mouse | Mouse only | Trackpad | iPad / touch |
| --- | --- | --- | --- | --- |
| Select / move | click / drag | same | same | tap / drag |
| Create | double-click, or Draw + click | same | same | double-tap, or Draw + tap |
| Duplicate / split / delete | keys or bar | bar | bar | bar |
| Menu | right-click | right-click | two-finger click | long-press |
| Zoom | scroll or ruler drag | ruler drag | pinch | pinch |
| Scroll | wheel | wheel | two fingers | two fingers |
| Undo | Cmd+Z | menu / button | Cmd+Z | undo button |

Touch-readiness rules that follow from this, for all new UI from now on:

1. Every action works with a plain click or tap. Right-click, modifier keys, hover and shortcuts
   only speed up actions that are already reachable.
2. The tap area can be bigger than the drawn control; the look stays the same.
3. Nothing important appears only on hover (tooltips are fine).
4. Standard gestures: pinch to zoom, two-finger scroll, long-press for the menu.
5. Undo and redo have a visible button wherever there is no keyboard.

## Helping people find it

- **Empty views say what to do** ("Double-click to add a note, or press B to draw"); the hint
  goes away once you've done it.
- **A one-time tip** after a few double-click adds: "Adding lots of notes? Press B to draw."

The five-tool row, the Z / X / C / V keys, "Alt = Erase" and the borrowed cursors all go; every
capability survives through double-click, Draw, the keys and the action bar.

## Open questions

- **Where the toggle lives.** In each canvas header (arrangement and editor), both showing the
  same on/off state, or once in the top bar. Leaning towards the canvas headers; the top bar's
  layout was settled on 2026-09-13.
- **A faint tint on the grid while Draw is on.** It would make the mode obvious, but it sits
  close to the settled "no canvas tool badge" decision (BACKLOG, Decisions). Tyr's call.
- **Cmd+E: at the playhead (today) or at the clicked point (like the bar).** One meaning for
  both would be simpler; the playhead is what Cmd+E does now.
- **One-finger drag on touch** on empty space: scroll or box-select. The usual answer is
  two-finger scroll everywhere and one-finger box-select; to confirm in the prototype.
- **The audio editor's "thing":** the whole clip, or a time range within it. Out of the first
  version.
- **Shortcut clashes to resolve:** Cmd+B is bounce globally and duplicate in the piano roll; Z and X
  are also the virtual piano's octave keys.

## Scope

**In the first version (proposed for v0.7):** Select default; double-click create and remove;
the Draw toggle with tap-to-remove, B and hold-B; the action bar; the same verbs across the
arrangement, piano roll and automation; clip copy and paste; Option-drag copy and Cmd-drag
ignore-grid; removal of the five-tool row and its keys; empty-view hints; pinch-to-zoom on the
trackpad.

**Later:** paint by dragging in Draw mode; chord stamps; ghost notes (other tracks' notes shown
faintly); the audio editor's selection model; full touch sizing and the iPad port itself.
