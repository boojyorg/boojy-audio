# Product review 2026-09-13 — supporting evidence

Companion to [`2026_09_13_product_review.md`](2026_09_13_product_review.md) (the decision brief).
This file is the raw material: the four readers' reports verbatim, the verifier's verdicts, and
the competitor facts verified during synthesis. Master at `988a068`, read-only.

**How to read it.** Finding IDs (T = tools, P = panels/mixer, C = correctness, R = repo health)
are used by the brief. Every T/P/C item tiered DEMONSTRATED or high severity, and every R item
recommending a deletion, was independently re-checked by the verifier (§5). Tiers: REPRODUCED
(observed running; none in this review), DEMONSTRATED (complete code path shown), SUSPECTED
(plausible, not closed).

**Known discrepancies, resolved in synthesis:**

- Reader 4's R10 concluded the `daw_screen.dart` / mixin twins were already deleted; it checked
  only the three names the rules file mentions. Reader 3's full sweep found 69 pairs, ~44 dead
  copies and two verified divergences; the verifier's independent regex also landed on 69. The
  brief uses 69.
- Reader 2's dialog inventory row #33 (`file_menu_button.dart` → `PopupMenuButton`) repeats a
  stale BACKLOG claim; the verifier refuted it (the file uses `showBoojyMenu`). No P-finding is
  affected.
- Reader 2's line numbers for P17/P18 are off by one (`track_icons.dart:23/25/69/81`).
- The empty-project screenshot is a 2048×1152 logical window (4096×2304 @2x), matching neither
  the laptop at 1710×1112 nor a maximised 30-inch; most likely the monitor, windowed. All laptop
  budgets in reader 2 are computed from code at 1710×1112, so this affects only how the
  screenshot itself is read (reader 2 notes the mixer in it is at ~210 px, near its 200 px floor).
- Reader 4's R17 says the `eprintln!` calls under `engine/src/audio_graph/` are not on the
  per-buffer path; reader 3's C11 finds one that is, in `engine/src/vst3_host.rs:864` (outside
  that directory). Both are correct.

Gates run by reader 3: `cargo test --release` 194 passed; `./build.sh release`; `fvm flutter
test --dart-define=BOOJY_CI=true` 1,282 passed, native tests included.

---

# §0 Competitor facts verified during synthesis


## Ableton Live 12
- Arrangement View is selection-based: click a clip selects it; click the background sets a flashing insert marker; drag selects a time span; Shift extends. Split = click inside a clip then Cmd+E (or context menu "Split") at that position. Cut/Copy/Paste/Duplicate act on the selection. There is NO draw tool for arrangement clips, no erase tool, no slice tool. (https://www.ableton.com/en/manual/arrangement-view/)
- MIDI Note Editor: Draw Mode toggled by the Control Bar button or key B. With Draw Mode ON: click-drag adds notes, clicking an existing note deletes it. With Draw Mode OFF (default pointer): double-click empty space adds a note, double-click a note deletes it. Duplicate (Cmd+D) is a command on the selection, distinct from Copy/Paste. No separate erase/slice tools. (https://www.ableton.com/en/live-manual/12/editing-midi/)
- Correction to the June 2026 research: the B toggle is a MIDI-editor/automation mode, not an arrangement-clip mode. Ableton never "draws" arrangement clips.

## Logic Pro (Mac)
- 14 tools: Pointer, Pencil, Eraser, Text, Scissors, Glue, Solo, Mute, Zoom, Fade, Automation Select, Automation Curve, Marquee, Flex. Chosen via Tool menu, T opens the menu at the pointer, Command-click tool as a second slot, Esc. The Pointer alone moves, resizes and loops regions by dragging edges/corners. (https://support.apple.com/guide/logicpro/tools-overview-lgcp84d2c7d8/mac)

## GarageBand (background, June 2026 research, not re-verified)
- No tool palette; position on the region decides (edges trim, body moves), empty-drag rubber-bands, split via Cmd+T at playhead / marker.

---

# §1 Reader 1 — Interaction model and the five editor tools


Read-only review. Repo at `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio`, branch `master`
at `988a068`. All paths below are relative to that root unless stated. No files in the repo were
modified.

---

## 0. Headline

The five tools are not five tools. They are **one tool (Draw) plus four narrow special cases**,
three of which are already reachable without leaving Draw (Alt = erase, Cmd = duplicate-drag,
Delete key = delete), and one of which (Slice) is the only genuinely unreachable one — and it is
the one with no modifier at all. Meanwhile the two names Tyr asked about are the two whose
**glyphs are literally the system Copy and Cut icons** (`Icons.content_copy`,
`Icons.content_cut` — `ui/lib/theme/boojy_icons.dart:101-102`), and Erase's glyph is a
**backspace key** (`Icons.backspace_outlined`, `boojy_icons.dart:109`). A beginner reading the
row left-to-right sees: pencil, crop-frame, backspace, copy, cut. Three of those five glyphs
promise clipboard/keyboard semantics the tools do not have.

The research doc's central assumption is now **factually stale**: the piano-roll insert marker it
proposed porting to the arrangement **no longer exists**. `insertMarkerBeats`
(`ui/lib/widgets/timeline/timeline_state.dart:347`) is a dead field — declared, never written,
never read anywhere in `lib/` or `test/`. It was removed from the piano roll by PR #79
(`905dd9d`, 2026-06-08) — **one day after the research doc was written** (2026-06-07). The
Edit menu still advertises "Split at Marker ⌘E" (`ui/lib/screens/daw/daw_menu_bar.dart:260-263`)
pointing at `splitSelectedClipAtPlayhead` (`ui/lib/screens/daw/mixins/daw_clip_mixin.dart:212`).
So the research's cheap "port the marker" move is now a from-scratch build in two views, and its
conclusion that "the insert-marker port makes slice-as-a-tool redundant" costs real work today
rather than being nearly free.

---

## 1. Behaviour matrix

Legend: **—** = the tool does nothing distinguishable from Draw in that view. **✗** = the tool is
inert (the view does not read `toolMode` at all). Line numbers are the handler that decides.

Entry points per view:
- Arrangement empty canvas: `ui/lib/widgets/timeline/timeline_track_list.dart:919` (tap),
  `:967` (double-tap), `:993` (drag start).
- Arrangement audio clip: `ui/lib/widgets/timeline/timeline_gesture_layer.dart:510` (tap),
  `:612` (drag start), `:936` (hover/cursor).
- Arrangement MIDI clip: `timeline_gesture_layer.dart:1486` (pointer down), `:1615` (drag start),
  `:1967` (hover/cursor + slice preview).
- Whole-canvas eraser sweep: `ui/lib/widgets/timeline_view.dart:890-935`.
- Piano-roll notes: `ui/lib/widgets/piano_roll.dart:1654` (tap), `:1898` (pan start),
  `:700-790` (pointer-level eraser sweep), `:1553` (hover cursor).
- Audio editor: `ui/lib/widgets/audio_editor/audio_editor.dart:33,53`.
- Track automation lane: `ui/lib/widgets/timeline/track_automation_lane_widget.dart:272` (tap),
  `:367` (pan start).
- Clip automation lane (piano roll): `ui/lib/widgets/piano_roll/piano_roll_clip_automation_lane.dart:400` (tap),
  `:473` (pan start).

### 1a. Arrangement — clips

| | click empty | drag empty | double-click empty | click clip | drag clip | drag clip edge |
|---|---|---|---|---|---|---|
| **Draw** (default) | deselect all `track_list:944-958` | MIDI track: drag-create sized clip `track_list:1089-1100`. **Audio track: nothing** | MIDI track: create 1-bar clip `track_list:967-991` | select `gesture_layer:552-600` / `:1537-1607` | move `gesture_layer:612-670` / `:1615-1680` | trim/resize `gesture_layer:2104,2228` |
| **Select** | deselect all (same) | box-select `track_list:1013-1086` | **still creates a 1-bar clip** `track_list:967` (not tool-gated) | select — | move — | trim/resize — |
| **Erase** | deselect all; sweep starts `timeline_view:896-910` | drag-erase clips under pointer `timeline_view:911-933` | **still creates a 1-bar clip** | delete `gesture_layer:521-531` / `:1502-1515` | blocked `:622,1628` | **still trims** (handle not tool-gated, `:2104,2228`) |
| **Duplicate** | deselect all — | nothing (create is gated `tool == draw`, `track_list:1089`) | **still creates a 1-bar clip** | **select only, no copy** `gesture_layer:551` | copy-drag `gesture_layer:630-634` / `:1636-1640` | trim/resize — |
| **Slice** | deselect all — | nothing | **still creates a 1-bar clip** | split at click `gesture_layer:533-549` / `:1517-1531` | blocked `:625,1631` | trim/resize — |
| **hover preview** | — | — | — | — | — | MIDI clip only: split line on hover `gesture_layer:1974-1982`. **Audio clip: none** `:941-948` |

Modifier overrides resolve identically in every cell via
`ui/lib/services/tool_mode_resolver.dart:36-41`: Alt→Erase, Cmd→Duplicate, Shift→Select, in that
priority. So Alt/Cmd/Shift temporarily replace whatever tool is active, in every view.

### 1b. Piano roll — notes

| | click empty | drag empty | click note | drag note body | drag note edge |
|---|---|---|---|---|---|
| **Draw** | create note of `lastNoteDuration` `piano_roll.dart:1829-1863` | **nothing** (`:2266` "no longer need to handle drawing here") | select `:1781-1820` | move `:2222-2262` | resize `:2204-2221` |
| **Select** | deselect all `:1758` | box-select `:1928-1937` | select / shift-toggle `:1712-1755` | move `:1985-2010` | resize `:1945-1983` |
| **Erase** | nothing; sweep starts `:735-737` | drag-erase notes `:750-761` | delete `:1667-1681` | blocked `:1923-1925` | blocked (same) |
| **Duplicate** | nothing | nothing | **duplicate in place, exactly stacked** `:1693-1709` | duplicate-and-move `:2015-2064` | duplicate-and-move (same branch) |
| **Slice** | nothing | nothing | split note at click X `:1684-1690` | blocked `:2067-2069` | blocked (same) |

Differences vs the arrangement, same tool:
- **Duplicate + click**: arrangement = select only; piano roll = immediate stacked duplicate.
- **Draw + empty-drag**: arrangement = create a sized clip; piano roll = nothing.
- **Select + note/clip edge**: piano roll explicitly keeps resize under Select (`:1945-1950`,
  with a comment saying so); the arrangement never gated edges by tool, so it matches by accident.

### 1c. Audio editor (waveform tab)

| all five tools | ✗ inert |
|---|---|
| `toolMode` is a declared parameter (`audio_editor.dart:33`, default `:53`) and **is never read anywhere in the file or its state/controls-bar** (verified: `grep -n toolMode ui/lib/widgets/audio_editor/*.dart` returns only those two lines). The five buttons render above it regardless (`ui/lib/widgets/editor_panel.dart:589` is in the shared 40px header, outside the `TabBarView`), so an Audio track shows a live-looking tool row that controls nothing in the visible tab. Same for the Master track, whose only tab is Effects (`editor_panel.dart:271-280`). |

### 1d. Automation lanes — and they disagree with each other

| | Track lane (arrangement) | Clip lane (piano roll) |
|---|---|---|
| **Draw** | click empty = add point; click point = drag `track_automation_lane_widget.dart:277-298` | same `piano_roll_clip_automation_lane.dart:405-413` |
| **Select** | select / shift-toggle; box-select on drag `:302-324`, `:410-420` | same `:416-437`, `:490-499` |
| **Erase** | delete point; drag-sweep `:326-335`, `:376-392` | delete point; **no drag-sweep** `:442-455` |
| **Duplicate** | copy point, nudged one snap step right so it is visible `:337-341`, `:357-367` | same `:459-463`, `:611-633` |
| **Slice** | **adds a point on the curve — anywhere, even empty space** `:343-355` | adds a point **only if you clicked an existing point** `:465-469`, `:635-647` |

Slice in an automation lane does not slice anything. It inserts a breakpoint. That is a useful
operation, but it is the wrong verb under the scissors icon, and the two lanes implement it
differently (one works on empty space, the other requires hitting a point).

---

## 2. Modifier and shortcut inventory

### Modifiers (identical in every view that reads `toolMode`)
`tool_mode_resolver.dart:36-41`, priority Alt > Cmd/Ctrl > Shift:

| held | becomes | arrangement | piano roll | automation lanes | audio editor |
|---|---|---|---|---|---|
| **Alt** | Erase | click/sweep deletes clips | click/sweep deletes notes | deletes points | ✗ |
| **Cmd/Ctrl** | Duplicate | drag = copy-drag; **click does nothing** | click on note = stacked duplicate; drag = duplicate-move | copies a point | ✗ |
| **Shift** | Select | empty-drag = box select; on a clip, Shift is additive-select (read separately at `gesture_layer:585-600`, re-read at tap-up `:1600` to survive missed reads) | empty-drag = box select; additive on notes | additive; `clip_automation_lane:479-486` box-selects on Shift regardless of tool | ✗ |
| **Shift during a clip drag** | — | bypasses snap `gesture_layer:1690-1696` — a *fourth* meaning for Shift | — | — | — |

### Sticky tool keys — Z X C V B
Bound twice, once per view, with identical semantics: `ui/lib/widgets/timeline_view.dart:667-700`
and `ui/lib/widgets/piano_roll.dart:2610-2641`. Z=Draw, X=Select, C=Erase, V=Duplicate, B=Slice,
each guarded on "no Cmd/Ctrl held".

They only fire when the timeline or piano roll holds keyboard focus. Neither is registered
app-wide (`daw_screen.dart:611` handles only Space/L/M globally; `:644` handles only Q and
Delete/Backspace). The piano roll guards against text fields (`piano_roll.dart:319-331`); the
timeline's handler (`timeline_view.dart:612`) has no such guard, though I found no `TextField`
inside the timeline's focus subtree, so I did not confirm a live keystroke leak.

### Command shortcuts

| combo | arrangement | piano roll | notes |
|---|---|---|---|
| **⌘C / ⌘V / ⌘X** | **nothing.** Edit-menu items exist but are `onSelected: null` — "Disabled - future feature" `daw_menu_bar.dart:234-248` | copy / paste / cut notes `piano_roll.dart:2561-2572`, `:2601-2606`; impl in `piano_roll/operations/clipboard_operations.dart:10,19,58` | Clip-level clipboard does not exist. The shortcuts sheet advertises ⌘C/⌘V as global Edit commands anyway (`keyboard_shortcuts_overlay.dart:96-97`) |
| **⌘D** | duplicate **one** clip, placed immediately after itself `daw_screen.dart:2174-2193`; timeline has its own MIDI-only copy at `timeline_view.dart:669-681` | duplicate selected notes `piano_roll.dart:2578-2582` | Does not act on a multi-selection in the arrangement — it reads `currentEditingClip` / `selectedAudioClip`, both singular |
| **⌘E** | split selected clip **at the playhead** `daw_screen.dart:3579-3580` → `daw_clip_mixin.dart:212-243` | — | Menu calls it "Split at Marker" (`daw_menu_bar.dart:260`) and **the same combo is also bound to View ▸ Show Editor Panel** (`daw_menu_bar.dart:308-311`). See T7 |
| **⌘B** | bounce MIDI to audio `daw_screen.dart:3590-3591` and `daw_menu_bar.dart:275-278` | duplicate selected notes `piano_roll.dart:2585-2589` | Same combo, two meanings. See T8 |
| **⌘A** | select all clips `timeline_view.dart:645-650` | select all notes `piano_roll.dart:2592-2596` | Edit-menu "Select All" is disabled (`daw_menu_bar.dart:279-283`) while both views implement it |
| **⌘J** | join clips `daw_screen.dart:3587` | — | |
| **Delete / Backspace** | delete selected clips `timeline_view.dart:613-619`, app-wide fallback `daw_screen.dart:669-676` | delete selected notes `piano_roll.dart:2538-2544` | Works everywhere without any tool |
| **Q** | quantize clip | quantize notes | |
| **Esc** | deselect | deselect | |

### Is any tool reachable without selecting it?

| tool | reachable without the toolbar? |
|---|---|
| Draw | it is the default (`daw_screen_state.dart:104`) — always reachable |
| Select | **yes** — Shift held, or Shift+drag for box select, everywhere |
| Erase | **yes** — Alt held, or the Delete key on a selection |
| Duplicate | **partly** — Cmd+drag copies (both views); Cmd+click duplicates a *note* but does nothing to a *clip*; ⌘D duplicates one clip |
| **Slice** | **no.** Cmd is taken by Duplicate, so there is no slice modifier. ⌘E splits at the *playhead*, not at the pointer, so it requires moving the playhead first. Right-click menus exist (`timeline_context_menus.dart`) but contain no "Split here". The Slice tooltip claims "Cmd+Click" (`editor_panel.dart:675`) — that is wrong in both views (see T4) |

So four of the five tool buttons are redundant with a modifier or a key, and the fifth — the one
that actually needs a mode — is the one whose advertised modifier does not work.

---

## 3. Selection-state rendering

**Which tool is active** is shown in exactly two places:

1. **The toolbar button fill** — `editor_panel.dart:1269-1345`. Active tool gets the accent fill;
   a held modifier gets the same fill at 50% alpha (`:1287-1289`) so you can see Alt/Cmd
   temporarily borrowing the mode. This part is well done and is the only honest signal.
2. **The mouse cursor** — `tool_mode_resolver.dart:62-70`, duplicated in
   `timeline_view.dart:300-312` and `timeline_gesture_layer.dart:68-80`.

The cursor mapping is the weak point:

| tool | cursor | what a beginner reads |
|---|---|---|
| Draw | `precise` (crosshair) | fine |
| **Select** | `basic` (the ordinary arrow) | **nothing.** Select mode looks exactly like every other app. There is no way to tell Select from "not in a mode" |
| **Erase** | `forbidden` (🚫) | **"this is not allowed"** — the OS no-drop cursor. A beginner in Erase mode sees the app telling them they can't do anything, and concludes the clip is locked |
| Duplicate | `copy` (arrow + green plus) | fine, matches macOS drag-copy |
| **Slice** | `verticalText` (text I-beam) | **"type here"**, not "cut here" |

There is **no canvas-side indicator** of the active tool — that is the settled decision
"No extra piano-roll canvas tool badge" (`docs/BACKLOG.md:240`). The consequence, given the
screenshot: the toolbar sits in the **header of the lower editor panel**
(`editor_panel.dart:589`, `Positioned.fill(child: Center(child: _buildToolRow()))`). In
`docs/reviews/_screenshots/01-empty-project.png` (1710×1112 maximised) it renders at roughly
y=665 of 1112 — **the vertical middle of the screen**, ~600px below the arrangement's first track
row. In `docs/screenshots/screenshot_v0.6.0.png` it sits between a populated arrangement (top
clip at ~y=140) and a populated piano roll (notes down to ~y=1150). So the only tool indicator is
~600px from whichever canvas you are editing in, in both directions.

**Answer to "can a beginner tell which mode they're in from the canvas alone": no.** Erase and
Slice announce themselves with cursors that say "forbidden" and "text insertion"; Select announces
nothing at all; and the only correct indicator is a small accent fill in a bar in the middle of
the screen that is visually attached to the piano roll, not to the arrangement.

**Selection of objects** (as opposed to tools) is rendered separately and is fine: selected
arrangement clips get a highlight border (`timeline_gesture_layer.dart:494`,
`isSelected: selectedAudioClipIds.contains(...)`; visible as the white outline on the green
Synthesizer clip in `screenshot_v0.6.0.png`), selected notes carry `isSelected` through
`MidiNoteData`, and box selection draws a live overlay
(`timeline_track_list.dart:1013-1086`, `piano_roll.dart:2270+`).

---

## 4. Naming analysis — Erase and Duplicate

### Erase

| | |
|---|---|
| **Name promises** | a rubber that rubs out, i.e. partial/sweeping removal, reversible-feeling, paint-like |
| **Glyph promises** | `Icons.backspace_outlined` (`boojy_icons.dart:109`) — **the backspace key**. That promises "the Delete key, as a button" |
| **Cursor promises** | `forbidden` 🚫 — "action not permitted" |
| **What it does** | Whole-object deletion. Click removes an entire clip or an entire note; drag removes every clip/note the pointer passes over (`timeline_view.dart:911-933`, `piano_roll.dart:750-761`). Never partial. Batched into a single undo step (`piano_roll.dart:2742-2752` commits "Delete N notes") |

**"Delete" is more accurate than "Erase", and the glyph already agrees with "Delete".** The one
thing "Erase" captures that "Delete" doesn't is the *sweep* — you can drag across eight notes and
remove them in one gesture, which the Delete key can't do without selecting first. But that is an
argument for keeping the sweep, not for keeping the word: Logic calls the same tool "Eraser" and
GarageBand doesn't have one at all; Ableton's equivalent is just the Delete key plus box-select.

Sharper point: **the sweep is the only thing this tool adds over `select + Delete`, and
`Alt+drag` already gives you the sweep with no mode switch.** If the tool is renamed Delete, its
reason to be a *button* gets thinner, not thicker.

### Duplicate

| | |
|---|---|
| **Name promises** | make a copy, now, next to the original |
| **Glyph promises** | `Icons.content_copy` (`boojy_icons.dart:102`) — **the universal clipboard Copy icon**, two stacked pages. Sitting immediately left of `Icons.content_cut` (scissors), the pair reads as "Copy" and "Cut" |
| **What it does — arrangement** | Click = **selects, copies nothing** (`gesture_layer:551`, comment: "Duplicate only creates copy on drag-end, not click"). Drag = copy-drag: the original stays, a copy follows the pointer (`:630-634`) |
| **What it does — piano roll** | Click = duplicate **in place**, pitch/start/duration identical, stacked exactly on the original (`piano_roll.dart:1693-1709`; `addNote` at `ui/lib/models/midi_note_data.dart:240-250` appends with no dedupe). Drag = duplicate-and-move (`:2015-2064`) |
| **⌘D for comparison** | Duplicates **one** clip and places it immediately after itself (`daw_screen.dart:2174-2193`), or all selected notes in the piano roll (`:2578`). That is the real "duplicate" semantic, and it needs no tool |
| **⌘C/⌘V for comparison** | Notes only (`piano_roll.dart:2561-2572`). For clips the menu items are disabled stubs (`daw_menu_bar.dart:234-248`) |

**Should Duplicate be distinguished from Copy? It already is — but the wrong way round.** The
tool is a *duplicate* (immediate, no clipboard) wearing the *copy* glyph, while the actual
clipboard Copy doesn't exist for clips at all. Renaming the tool to "Copy" would make that worse:
users would press it expecting ⌘V to work afterwards.

The honest fixes, in order of cheapness:
1. Change the glyph. `content_copy` must not sit on a non-clipboard action. Something like a
   "duplicate/stack-right" or `Icons.library_add` / a plus-on-object mark.
2. Keep the word "Duplicate" (it is accurate) and drop the tool: ⌘D + Cmd-drag already cover it,
   and the arrangement click case does nothing anyway.
3. If clip-level ⌘C/⌘V ever ship, they must not reuse these glyphs.

### The whole row, read as a beginner reads it

```
 [✏]   [⛶]   [⌫]   [⧉]   [✂]
Draw  Select Erase  Dup  Slice
 edit  crop  back-  copy  cut
       free  space
```
Three of five glyphs are borrowed from a different vocabulary (backspace key, clipboard copy,
clipboard cut) and one (`crop_free`) is the standard "fullscreen / expand" mark — it appears twice
in the same screenshot, once as a tool and once as the transport's fullscreen button
(`01-empty-project.png`, x≈1055 in the transport, x≈966 in the tool row, near-identical marks
meaning different things).

---

## 5. Mode-switching cost

Scenario: draw a 4-bar drum pattern → fix a wrong note → copy the pattern to bars 5-8 → slice a
bar off → delete a couple of stray notes.

### Path A — beginner, toolbar only (no modifiers known)

| step | tool needed | switches |
|---|---|---|
| Drag-create a 4-bar MIDI clip | Draw (default) | 0 |
| Open the piano roll, click in the drum notes | Draw | 0 |
| Drag a wrong note to the right pitch | Draw (`piano_roll.dart:2222`) | 0 |
| Delete a wrong note | **Erase** → then back to **Draw** | **2** |
| Copy the clip to bars 5-8 | **Duplicate** → drag → back to **Draw** | **2** |
| Slice the last bar off | **Slice** → click → back to **Draw** | **2** |
| Delete two stray notes | **Erase** → sweep → back to **Draw** | **2** |
| **Total** | | **8 switches** |

Each switch is a round trip from the canvas to the middle of the screen and back — ~1200px of
mouse travel per switch on the 1710px-tall laptop screen in the screenshot, so roughly **10,000px
of pure tool-fetching** across one 8-bar loop. And after every switch the user is left in a
non-default mode; the classic failure is forgetting, then clicking to add a note and deleting one
instead. Nothing on the canvas tells them.

### Path B — same user, once they know the modifiers

| step | how | switches |
|---|---|---|
| Drag-create the clip | default | 0 |
| Draw / move notes | default | 0 |
| Delete a note | Alt+click, or select + Delete | 0 |
| Copy to bars 5-8 | Cmd+drag, or ⌘D | 0 |
| **Slice the last bar off** | **no modifier exists.** ⌘E splits at the playhead → must first click the ruler to park the playhead on the bar line, select the clip, then ⌘E. Otherwise: switch to Slice and back | **0 (+2 extra steps and a moved playhead)** or **2** |
| Delete strays | Alt+drag sweep | 0 |
| **Total** | | **0-2** |

### Path C — a pointer-first model with modifiers (what B would become)

Pointer default; Draw is a visible toggle; Alt = delete; Cmd = duplicate-drag; slice via either a
dedicated modifier or a pointer-position split command. **0 tool switches for the whole loop, and
the one mode that remains (Draw) is a single visible binary you can see from the canvas.**

The gap is 8 versus 0. Every one of those 8 is paid by exactly the user Boojy targets — the one
who hasn't learned the modifiers yet.

---

## 6. Options

### Option A — keep five tools, fix the surface only

```
┌──────────────────────────────────────────────┐
│ [Synth][MIDI]     ✏  ↖  🗑  ⧉+  ✂       ⌄ │
│                  Draw Sel Del Dup Slice      │
└──────────────────────────────────────────────┘
```
Rename Erase → **Delete**. Replace `backspace_outlined` with a bin/eraser mark, `crop_free` with
a real pointer (`Icons.near_me` / `BI.cursor`, which already exists unused at
`boojy_icons.dart:110`), `content_copy` with a duplicate-specific mark, and keep scissors for
Slice. Replace the `forbidden` cursor with something that reads as delete, and `verticalText`
with a scissors/split cursor. Fix the wrong tooltips (T4) and the audio-editor inertness (T2).

- **For:** cheapest by far; zero behaviour change; no settled decision touched.
- **Against:** does nothing about the 8 switches, nothing about mode-blindness on the canvas, and
  nothing about the four tools that duplicate modifiers. It makes a confusing model legible
  rather than making it simpler. For a beginner-first product that is the wrong end of the lever.
- **Conflicts with a settled decision:** **N.**

### Option B — three tools: Pointer / Draw / Slice (this is the research's P2, plus a Slice button)

```
┌──────────────────────────────────────────────┐
│ [Synth][MIDI]      ↖  ✏  ✂            ⌄ │
│                  Point Draw Slice            │
└──────────────────────────────────────────────┘
```
- **Pointer** (default, X): click selects, empty-drag box-selects, drag moves, edges trim. This is
  today's Select tool promoted to default.
- **Draw** (Z): today's Draw — empty-drag creates a sized clip, click creates a note. Keeps Tyr's
  one-gesture sized create, which P1 in the research would have cost him.
- **Slice** (B): unchanged; it is the one operation with no modifier and a real position argument.
- **Erase is deleted as a tool.** Delete key on a selection + Alt-drag sweep already do everything
  it does, and Alt keeps the drag-erase sweep the key can't give you.
- **Duplicate is deleted as a tool.** ⌘D + Cmd-drag already do everything it does, and its click
  behaviour in the arrangement does nothing at all today.
- Both removals are branch deletions in code that already exists (`ToolMode.eraser` /
  `ToolMode.duplicate` cases stay reachable via `ToolModeResolver`; only the *sticky* entry points
  and two buttons go).

- **For:** cuts the beginner path from 8 switches to 2 (Slice out and back) and the expert path to
  0-2; removes both mis-glyphed tools instead of re-dressing them; keeps every capability;
  keeps one shared toolset across both views, so Tyr's "one global toolset" decision survives.
- **Against:** Pointer-as-default is a change in muscle memory for Tyr, who currently gets
  drag-create for free. C and V stop switching tools (they become free for clip ⌘C/⌘V later).
  Doesn't fix mode-blindness for Slice — you can still be stuck in it.
- **Conflicts with a settled decision:** **N** for "one global toolset" (still one, still shared).
  **N** for "no canvas tool badge" as written. It *does* reverse the default tool, which is not a
  recorded decision but is a real change to Tyr's workflow.

### Option C — one Draw toggle, no tool row (the research's P2 in its pure form)

```
┌──────────────────────────────────────────────┐
│ [Synth][MIDI]           ✏ Draw          ⌄ │
└──────────────────────────────────────────────┘
   (off = pointer · on = draw · key: B or Z)
```
Everything else becomes direct interaction: Alt = delete, Cmd = duplicate-drag, Shift = additive,
Delete key = delete, and **slice becomes an insert marker + ⌘E + a right-click "Split here"** at
the pointer position — which is what the research recommended.

- **For:** the simplest model, one visible binary, zero mode-blindness, touch-ready, and it is
  what the seven-DAW survey landed on. Split-at-pointer via right-click is more precise than the
  Slice tool is today (no hover preview on audio clips at all — T5).
- **Against:** **the insert marker no longer exists** (`insertMarkerBeats` is dead,
  `timeline_state.dart:347`; removed by PR #79, a day after the research was written). So the
  piece the research called "cheap, already built in the piano roll" is now a build in two views
  plus a new ⌘E target plus a new context-menu item plus the ⌘E collision (T7) to untangle first.
  This is the most work of the four by a wide margin, and it lands in the middle of a release
  gate.
- **Conflicts with a settled decision:** **Y, mildly** — "one global toolset shared across
  arrangement + piano roll" becomes "one global toggle", which is arguably still that, but Tyr
  has reopened it so it should be an explicit re-decision either way.

### Option D — smart tool / click zones, no toolbar at all

Clip upper half = range/trim, lower half = move/select, pointer position decides; slice via
right-click. Studio One / Pro Tools discipline.

- **For:** zero chrome, zero travel, zero mode.
- **Against:** the zones are invisible until learned, which is exactly the failure mode Boojy's
  calm-interface principle is trying to avoid; it is the least beginner-legible of the four
  despite being the most efficient; and it deletes the toolbar outright.
- **Conflicts with a settled decision:** **Y** — removes the shared toolset entirely.

### Recommendation: **Option B**, with Option A's glyph/cursor fixes folded into it.

Reasoning, honestly stated:

- **B gets ~90% of C's benefit for ~20% of the work,** and that ratio has changed *since* the
  research doc, because the marker C depends on was deleted the day after it was written. C was
  the right call in June; it is a more expensive call today, and v0.7.0 is a bounded release
  gate (`docs/BACKLOG.md`, "Now"), not the place for a two-view insert-marker build.
- **B removes the two tools Tyr asked about rather than renaming them,** which answers the naming
  question more durably than A does. "Should Erase be called Delete?" — yes, and then it should
  be a key, not a button. "Should Duplicate be distinguished from Copy?" — yes, and the cleanest
  distinction is that Duplicate is ⌘D and Cmd-drag, and Copy is a clipboard command that doesn't
  exist yet and shouldn't be confused with a tool.
- **B keeps Tyr's drag-create.** The research explicitly flagged that P1 costs it. Making Draw a
  named, visible, one-key tool rather than the silent default preserves it while giving beginners
  a standard pointer to land on.
- **The honest weakness of B:** Slice stays modal, so the "I'm stuck in a mode and don't know it"
  failure still exists in one place. Mitigate with the cursor fix (a real scissors cursor rather
  than a text I-beam) and by extending the MIDI hover split-preview to audio clips (T5), so Slice
  mode is at least visible on the canvas at the point of use. If that still isn't enough after
  dogfooding, C becomes the follow-up and B's work is not wasted — B is a strict subset of the
  road to C.

I'd push back on A as the answer even though it is tempting during a release gate: it spends
effort making five confusing things legible, and leaves the mode-switch cost — the thing that
actually hurts the target user — completely untouched.

---

## 7. Bugs and inconsistencies found

### T1 — Duplicate tool on a note creates an invisible, exactly-stacked duplicate
- **Tier:** DEMONSTRATED · **Severity:** med · **Confidence:** high
- **Evidence:** `ui/lib/widgets/piano_roll.dart:1693-1709` builds
  `clickedNote.copyWith(id: <new>, isSelected: false)` — pitch, `startTime`, `duration` and
  `velocity` all unchanged — then `ui/lib/models/midi_note_data.dart:240-250` appends it with no
  dedupe or offset. The dead duplicate of this code at
  `ui/lib/widgets/piano_roll/gestures/note_gesture_handler.dart:147-163` has the same defect.
- **What a user experiences:** in Duplicate mode, clicking a note appears to do nothing. The note
  is now doubled — louder, and on a sampler, phase-cancelling or flamming. Undo says "Duplicate
  note" so the user can back out *if* they notice. Compare the automation lane, which explicitly
  nudges a duplicate one snap step right precisely so it doesn't stack
  (`track_automation_lane_widget.dart:357-367`, comment: "if that rounds onto the original, nudge
  one snap step right so the two points don't stack"). The piano roll never got that guard.
- **Conflicts-with-decision:** N

### T2 — The tool row renders over the audio editor and the Master track, where it does nothing
- **Tier:** DEMONSTRATED · **Severity:** low · **Confidence:** high
- **Evidence:** `ui/lib/widgets/audio_editor/audio_editor.dart:33` declares `final ToolMode
  toolMode;`, `:53` defaults it — and it is read nowhere (`grep -n toolMode
  ui/lib/widgets/audio_editor/*.dart` returns only those two lines). The tool row is built in the
  shared 40px header at `ui/lib/widgets/editor_panel.dart:589`, outside the `TabBarView` at
  `:637-642`, so it renders for every tab including Audio and the Master track's Effects-only tab
  (`:271-280`).
- **What a user experiences:** on an audio track they see five lit, hoverable tool buttons above
  a waveform and none of them changes anything in that view. Clicking them silently changes what
  will happen when they go back up to the arrangement.
- **Conflicts-with-decision:** partially — **"Inert controls work or are hidden"**
  (`docs/BACKLOG.md:238`) is a settled decision and this violates its spirit. Flagging as
  **Y (inert-controls decision)**, in the sense that fixing it is *supported* by an existing
  decision, not blocked by one.

### T3 — Double-click creates a clip in every tool mode, including Erase and Slice
- **Tier:** DEMONSTRATED · **Severity:** low · **Confidence:** high
- **Evidence:** `ui/lib/widgets/timeline/timeline_track_list.dart:967-991` —
  `onDoubleTapDown: isMidiTrack ? (details) { ... onCreateClipOnTrack(...) } : null`. The handler
  reads `isMidiTrack` and `_isPositionOnClip`, never `widget.toolMode` or `ModifierKeyState`.
  Compare the drag-create path 100 lines below at `:1089`, which *is* gated
  (`if (tool == ToolMode.draw && !isOnClip && isMidiTrack)`).
- **What a user experiences:** in Erase mode, an over-eager double-click on empty track space
  *creates* a 1-bar clip. The `forbidden` cursor is showing at the time.
- **Conflicts-with-decision:** N

### T4 — Two of the five tooltips document modifiers that don't exist
- **Tier:** DEMONSTRATED · **Severity:** med · **Confidence:** high
- **Evidence:** `ui/lib/widgets/editor_panel.dart:675` — `'Slice (B) • Cmd+Click'`. But
  `ui/lib/services/tool_mode_resolver.dart:38` maps Cmd/Ctrl to `ToolMode.duplicate`, not slice,
  in every view. Two consequences:
  - **Arrangement:** Cmd+click on a clip hits the Duplicate branch, which by design does nothing
    on click (`timeline_gesture_layer.dart:551`). Cmd+click never slices anything.
  - **Piano roll:** the "Cmd+click on empty space slices the note under the cursor" branch at
    `ui/lib/widgets/piano_roll.dart:1767-1779` is **unreachable**. Holding Cmd sets
    `tempModeOverride = ToolMode.duplicate` (`:1541-1548`, driven by `_onHardwareKey` at `:210`),
    so `effectiveToolMode` is `duplicate` at `:1659`, and the duplicate branch at `:1693` matches
    and `return`s at `:1708` before line 1767 is ever reached. With `clickedNote == null` it
    returns having done nothing at all.
  - The same false claim is in the shortcuts sheet: `ui/lib/widgets/keyboard_shortcuts_overlay.dart:123`
    — `⌘ + Click → 'Slice at Cursor'`.
- **What a user experiences:** they read the tooltip, hold Cmd, click a clip or empty piano-roll
  space, and nothing happens. The advertised way to slice without switching tools does not work,
  which is exactly the escape hatch that would have made the Slice tool optional.
- **Caveat I did not close:** if `tempModeOverride` fails to update (modifier pressed while the
  window isn't key — a failure mode the codebase explicitly guards against elsewhere, see
  `timeline_track_list.dart:993-997`), line 1767 could fire. That makes the branch not just dead
  but *intermittently* alive, which is worse.
- **Conflicts-with-decision:** N

### T5 — Slice shows a split preview on MIDI clips and none on audio clips
- **Tier:** DEMONSTRATED · **Severity:** med · **Confidence:** high
- **Evidence:** MIDI clip hover calls `_updateMidiClipSplitPreview` when the tool is slice —
  `ui/lib/widgets/timeline/timeline_gesture_layer.dart:1974-1982`. The audio clip's `MouseRegion`
  `onHover` at `:941-945` only calls `updateTempToolMode()` and never touches
  `splitPreviewAudioClipId`; that field is set only inside the tap handler at `:542`, i.e. at the
  instant of the cut. `_clearSplitPreview` is wired on exit for both (`:946-948`, `:1984-1988`).
- **What a user experiences:** slicing a MIDI clip shows a line telling you where the cut lands;
  slicing an audio clip is blind. Recorded vocals and samples are exactly where you most want to
  see the cut point before committing.
- **Conflicts-with-decision:** N

### T6 — Slice in an automation lane inserts a point, and the two lanes disagree about how
- **Tier:** DEMONSTRATED · **Severity:** low · **Confidence:** high
- **Evidence:** `ui/lib/widgets/timeline/track_automation_lane_widget.dart:343-355` — the slice
  case computes `widget.lane.getValueAtTime(time)` and calls `onPointAdded`, on empty space or on
  a point alike. `ui/lib/widgets/piano_roll/piano_roll_clip_automation_lane.dart:465-469` only
  calls `_sliceAtPoint` (`:635-647`, same "add a point on the curve" body) **when
  `clickedPoint != null`**, so on empty space it does nothing.
- **What a user experiences:** the scissors tool adds breakpoints rather than cutting anything,
  and it works on empty space in the arrangement's automation lane but not in the piano roll's.
- **Conflicts-with-decision:** N

### T7 — ⌘E is bound to two different commands in the macOS menu bar
- **Tier:** DEMONSTRATED · **Severity:** med · **Confidence:** med (on which one wins)
- **Evidence:** `ui/lib/screens/daw/daw_menu_bar.dart:259-263` — Edit ▸ "Split at Marker",
  `SingleActivator(keyE, meta: true)` → `onSplitAtMarker`. And `:305-311` — View ▸ "Show Editor
  Panel", `SingleActivator(keyE, meta: true)` → `onToggleEditor`. Both are live `PlatformMenuItem`s
  in the same `PlatformMenuBar`. A third binding for the same combo exists in Flutter's own
  shortcut layer at `ui/lib/screens/daw_screen.dart:3578-3580` → `splitSelectedClipAtPlayhead`.
  The shortcuts sheet documents only the View meaning
  (`ui/lib/widgets/keyboard_shortcuts_overlay.dart:106`).
- **What a user experiences:** ⌘E does one of two very different things and the menus disagree
  about which. Both menu items render the same key equivalent, so one of them is visibly lying.
- **Secondary:** the Edit item is called "Split at **Marker**" but calls
  `splitSelectedClipAtPlayhead` (`ui/lib/screens/daw/mixins/daw_clip_mixin.dart:212-243`), which
  splits at the *playhead*. The marker it names does not exist anywhere in the app —
  `insertMarkerBeats` (`ui/lib/widgets/timeline/timeline_state.dart:347`) is declared and never
  written or read (verified across `lib/` and `test/`); the piano-roll implementation was removed
  by PR #79 (`905dd9d`, 2026-06-08).
- **I did not confirm** which binding macOS actually dispatches to. Menu order suggests Edit wins
  (it precedes View), which would make View ▸ Show Editor Panel's advertised shortcut dead — but
  that needs a launch to verify, which is out of scope for this read.
- **Conflicts-with-decision:** N

### T8 — ⌘B means "bounce MIDI to audio" globally and "duplicate notes" in the piano roll
- **Tier:** DEMONSTRATED · **Severity:** low · **Confidence:** med
- **Evidence:** `ui/lib/screens/daw_screen.dart:3590-3591` and
  `ui/lib/screens/daw/daw_menu_bar.dart:274-278` bind ⌘B to `_bounceMidiToAudio`.
  `ui/lib/widgets/piano_roll.dart:2584-2589` binds ⌘B to `duplicateSelectedNotes()` with the
  comment "(FL Studio style)". The piano roll consumes all keys it doesn't ignore
  (`:319-332` returns `KeyEventResult.handled` unconditionally), but a native menu key equivalent
  is normally dispatched before the Flutter focus tree sees it — which would make the piano-roll
  binding dead and ⌘B in the piano roll bounce the track instead of duplicating notes.
- **What a user experiences:** an FL-Studio user presses ⌘B expecting a note duplicate and gets a
  render-to-audio, or nothing. Not verifiable without launching.
- **Conflicts-with-decision:** N

### T9 — Erase/Slice mode still trims and resizes clips at the edges
- **Tier:** SUSPECTED · **Severity:** low · **Confidence:** med
- **Evidence:** the left-trim and right-resize handles are `GestureDetector`s with
  `behavior: HitTestBehavior.opaque` at `ui/lib/widgets/timeline/timeline_gesture_layer.dart:2104-2118`
  and `:2228-2246`, and neither consults `toolMode` or `ModifierKeyState`. The tool-aware blocks
  (`:622-625`, `:673`, `:1628-1631`, `:1681`) live on the *clip body's* drag handlers, not on the
  edge handles. Meanwhile the clip-wide `MouseRegion` paints the `forbidden` cursor over the whole
  clip including the edges (`:936-940`).
- **What a user experiences:** in Erase mode, hovering a clip edge shows 🚫 but dragging trims the
  clip. I have not closed which recogniser wins the gesture arena against the ancestor
  tap/pointer eraser for audio clips (`:510`) versus MIDI clips (`:1486`, a `Listener`, which sees
  the pointer regardless), so the exact outcome may differ between the two clip types — which
  would itself be the bug.
- **Conflicts-with-decision:** N

### T10 — `NoteGestureHandlerMixin` is a second, divergent copy of the live piano-roll gesture code
- **Tier:** DEMONSTRATED · **Severity:** low (maintenance) · **Confidence:** high
- **Evidence:** `ui/lib/widgets/piano_roll/gestures/note_gesture_handler.dart` defines
  `handleTapDown` (`:109`), `findNoteAtPosition` (`:28`), `getEdgeAtPosition` (`:42`),
  `startErasing` (`:261`), `eraseNotesAt` (`:270`), `stopErasing` (`:277`). Grep across `lib/`
  shows **none of those six is called anywhere**; the live implementations are the private copies
  in `ui/lib/widgets/piano_roll.dart` (`_onTapDown:1654`, `_findNoteAtPosition:1478`,
  `_getEdgeAtPosition:1492`, `_startErasing:2718`, `_eraseNotesAt:2727`, `_stopErasing:2742`).
  Only `findNoteAtVelocityPosition` (`:68`) is still used, by `velocity_lane_mixin.dart:30,48,83`.
  The two copies have already diverged — the live `_onTapDown` has a `justCreatedNoteId` reset
  branch (`piano_roll.dart:1785-1787`) the dead one lacks.
- **What a user experiences:** nothing directly. But any tool-behaviour fix applied to the
  obvious-looking file (`gestures/note_gesture_handler.dart`) will silently have no effect, which
  is a trap for exactly the work options A-D above imply. The dead-code pass (PR #138) missed it.
- **Conflicts-with-decision:** N

### T11 — ⌘D duplicates one clip even when several are selected
- **Tier:** DEMONSTRATED · **Severity:** low · **Confidence:** med-high
- **Evidence:** `ui/lib/screens/daw_screen.dart:2174-2193` reads
  `midiPlaybackManager?.currentEditingClip` then falls back to
  `timelineKey.currentState?.selectedAudioClip` — both singular. The multi-selection sets
  `selectedMidiClipIds` / `selectedAudioClipIds` (`timeline_gesture_layer.dart`, used throughout)
  are never consulted. Delete, by contrast, handles the full multi-selection
  (`ui/lib/widgets/timeline_view.dart:573-611`), and so does the Duplicate tool's copy-drag
  (`timeline_gesture_layer.dart:640-654`).
- **What a user experiences:** box-select four clips, press ⌘D, get one copy. The Duplicate *tool*
  drag copies all four. Same word, two scopes.
- **Conflicts-with-decision:** N

### T12 — Debug logging left in the clip automation lane's eraser path
- **Tier:** DEMONSTRATED · **Severity:** low · **Confidence:** high
- **Evidence:** `ui/lib/widgets/piano_roll/piano_roll_clip_automation_lane.dart:442-453` — three
  `Log.d('[AutomationLane] ERASER: ...')` calls including one on the miss path, firing on every
  eraser click and every eraser click that hits nothing.
- **What a user experiences:** nothing visible; log noise that violates the "quiet when healthy"
  principle in `docs/PRODUCT.md`.
- **Conflicts-with-decision:** N

### T13 — The shortcuts sheet documents the tools as "Piano Roll Tools" and advertises clip ⌘C/⌘V that don't exist
- **Tier:** DEMONSTRATED · **Severity:** med · **Confidence:** high
- **Evidence:** `ui/lib/widgets/keyboard_shortcuts_overlay.dart:110-117` — section header
  `'Piano Roll Tools'` listing Z/X/C/V/B, and `:119-126` `'Piano Roll Modifiers'` listing
  Alt+click / ⌘+drag / ⌘+click. All of those work in the **arrangement** too
  (`ui/lib/widgets/timeline_view.dart:667-700` binds the identical keys). Separately, `:96-97`
  lists `⌘C 'Copy'` and `⌘V 'Paste'` under a general **Edit** heading, but the Edit-menu items
  are disabled stubs (`ui/lib/screens/daw/daw_menu_bar.dart:234-248`, "Disabled - future
  feature") and the only implementations are note-level
  (`ui/lib/widgets/piano_roll.dart:2561-2572`).
- **What a user experiences:** the only written documentation of the tool model tells them the
  tools are piano-roll-only (they aren't) and that they can copy and paste clips (they can't).
  This is the single cheapest fix on the list and it is upstream of every naming decision.
- **Conflicts-with-decision:** N

---

## 8. What has changed since the 2026-06-07 research doc

| research claim | status today |
|---|---|
| "Boojy's piano roll already has [the insert marker]; ⌘E splits there" | **False now.** `insertMarkerBeats` is dead (`timeline_state.dart:347`), removed by PR #79 on 2026-06-08 — the day after. ⌘E splits at the playhead (`daw_clip_mixin.dart:212`) and the menu label still says "at Marker" |
| "the timeline never got it — arrangement ⌘E only splits at the playhead" | Still true, and now true of the piano roll as well |
| "Timeline's hidden persistent Z/X/C/V/B switching is removed in every package" | **Not done.** Still present at `timeline_view.dart:667-700` and mirrored at `piano_roll.dart:2610-2641` |
| "Alt = erase, Cmd = duplicate-drag stay as temporary modifiers" | Still true (`tool_mode_resolver.dart:36-41`) — and Shift = select was added as a third |
| "the piano-roll 5-tool palette stays editor-local — it's visible there and works" | The palette is still in the editor-panel header, but it drives the arrangement too and is documented as piano-roll-only (T13). It is not editor-local in behaviour, only in position |
| "Shift+drag selects (status quo) — works, but undiscoverable" | Still true, and the Select tool is the only discoverable route to box-select |
| "mouse travel … confirmed real" | Still real, and unchanged: the toolbar renders at the vertical mid-screen (`editor_panel.dart:589`; see `01-empty-project.png` at y≈665/1112) |
| P2 recommended because the marker port was "cheap" | The cost basis has changed. P2/Option C is now the most expensive of the four options, not the near-free one |

**The arguments that still hold:** five invisible modes is the wrong default for beginners; empty-drag
means box-select in every object-based DAW; the toolbar is far from both canvases; touch can't use
modifiers so the mode indicator should be an on-screen control. **The argument that no longer
holds:** that replacing Slice is nearly free.

---

## 9. Screenshot grounding

- `docs/reviews/_screenshots/01-empty-project.png` (current build) grounds: the tool row's
  position at mid-screen (§3, §5); the five glyphs as rendered — pencil, crop-frame, backspace,
  copy, scissors (§4); the tool row being present with **no track selected and an empty
  arrangement**, i.e. five lit tools with nothing to act on (`editor_panel.dart:680-710` builds
  the same row in the no-selection state); and the `crop_free` collision with the transport's
  fullscreen button (§4).
- `docs/screenshots/screenshot_v0.6.0.png` (older, populated) grounds: the toolbar's distance from
  a real arrangement (top clip ~y=140) and a real piano roll (notes to ~y=1150) — the ~600px
  round trip per tool switch in §5; and the clip-selection rendering in §3 (white outline on the
  selected green Synthesizer clip). It also shows the toolbar unchanged between v0.6.0 and today,
  so none of the intervening PRs (#140-#145) touched this surface.

---

# §2 Reader 2 — Panels, space, dialogs, mixer clarity


Read-only review of Boojy Audio at `/Users/tyrbujac/Documents/Projects/boojy/boojy-audio`,
2026-09-13, master @ 988a068. No files in the repo were modified; no app was launched.

Screenshots used, and what each grounds:

- `docs/reviews/_screenshots/01-empty-project.png` — grounds P1, P2, P3, P9, P18, P29, P33.
  Note: this capture is 4096×2304 physical = **2048×1152 logical**, not 1710×1112. The
  library reads ~345 px and the mixer ~210 px, i.e. Tyr has already dragged the mixer to
  within 10 px of its 200 px floor. That matters: at 210 px the audio-track input chip is
  suppressed (P26).
- `docs/reviews/_screenshots/02-mixer-strips.png` — grounds P17, P19, P20, P21, P22, P24, P28.
- `docs/screenshots/screenshot_v0.6.0.png` — the "before" for P17/P19: the same strips with
  **M S R** letters, and the arrangement/piano-roll/device-chain proportions.

---

## 1. PANEL MAP

### 1a. The tree as built

```
Scaffold.body = Stack
├── Column                                       ← the actual layout
│   ├── SizedBox(height: 54)                     transport reserve (inline variant)
│   └── Expanded → Column
│       ├── Expanded → Row                       ← "top section"
│       │   ├── LIBRARY      AnimatedContainer(w = libraryPanelWidth + 4)
│       │   │                └ Row[ SizedBox(libraryPanelWidth) , ResizableDivider(3) ]
│       │   ├── ARRANGEMENT  Expanded → TimelineView
│       │   │                ├ nav/ruler bar 24
│       │   │                ├ scrollable track column (+100 bottom buffer)
│       │   │                ├ per return: 2 px divider + 100 px band  (always reserved)
│       │   │                └ 2 px divider + 60 px master band        (always reserved)
│       │   └── MIXER        AnimatedContainer(w = mixerPanelWidth + 4)
│       │                    └ Row[ ResizableDivider(3) , SizedBox(mixerPanelWidth) ]
│       │                      ├ header 24 (+ MIDI / + Audio)
│       │                      ├ scrollable strips  (heights synced to arrangement)
│       │                      ├ return strips (pinned)
│       │                      └ master strip (pinned, 60)
│       ├── ResizableDivider(3)  — only when the editor is expanded
│       ├── EDITOR  AnimatedContainer(height = editorPanelHeight, else 40)
│       │           ├ 40 px tab/tool bar   [tabs | 5 tools | preset nav · chevron]
│       │           └ tab content
│       └── VIRTUAL PIANO  (independent, below the editor, off by default)
└── Positioned(top:0) → TransportBar (painted over the 54 px reserve)
    + PaletteEditor / UiLabsSwitcher / PlayheadLab / EditorButtonSwitcher (dev, Cmd+Shift)
```

`daw_screen.dart:3634-3860` · library `:3116-3186` · mixer `:3312-3470` · editor `:3702-3820`.

### 1b. Sizes, per region

| Region | Default | Min | Max | Collapsed | Persisted |
| --- | --- | --- | --- | --- | --- |
| Library | `clamp(0.15·W, 160, 600)`; internally 60 (frozen left) + 8 + right | 160 (right col 92) | `min(0.30·W, 600)` | 0 px, fully gone | **Twice**: `UserSettings` (global, SharedPreferences) *and* `ui_layout.json` per project |
| Arrangement | fills | 200 (guard only) | — | n/a | zoom/scroll in `view_state` |
| Mixer | `clamp(0.28·W, 200, 500)` | 200 | `min(0.35·W, 500)` | 0 px | Twice, as above |
| Editor | `clamp(0.32·H, 150, 800)` | 150 | `min(0.65·H, 800)` | **40 px bar, never 0** | Height: twice. **Visibility: global only — the per-project value is written and never read (P6)** |
| Track row | 100 | 16 | 400 | 1-row < 50, dots < 24 | per project (`clipHeights`) |
| Master row | 60 | 16 | 400 | — | per project |
| Virtual piano | fixed | — | — | hidden | global |

Constants: `state/ui_layout_state.dart:66-173`, `constants/ui_constants.dart:27-94`,
`widgets/resizable_divider.dart:43`, `widgets/transport_bar/transport_bar_models.dart:28-39`.

### 1c. Pixel budget — laptop 1710 × 1112

Vertical budget after the transport reserve: **1058 px**.
Defaults at this window: library 256.5 (+4), mixer 478.8 (+4), editor 355.8.

| | (a) library + editor | (b) library + mixer + editor | (c) arrangement only |
| --- | --- | --- | --- |
| Editor block | 355.8 + 3 divider | 355.8 + 3 | 40 (collapsed bar) |
| Top section height | 699.2 | 699.2 | 1018 |
| − ruler 24, − master band 62 | **613.2** scrollable | **613.2** | **932** |
| Tracks visible @100 px | **6** (6.13) | **6** | **9** (9.32) |
| Tracks @76 px ("standard") | 8 | 8 | 12 |
| Tracks @50 px (1-row strips) | 12 | 12 | 18 |
| Tracks @16 px (dots) | 38 | 38 | 58 |
| Mixer strips visible | — | **6** (viewport 615.2 = 699.2 − 24 header − 60 master) | — |
| Arrangement width | 1449.5 | **966.7** | 1710 |
| Mixer strip width | — | 478.8 | — |

Reading of (b): at Tyr's reference 4–14 tracks, **the 6-track ceiling is the binding
constraint on the laptop**, and it is set by the editor taking a third of the height, not by
the panel widths. A 10-track beat means scrolling the arrangement *and* the mixer (they are
scroll-synced) from the first bar onward.

Of the 613 px of arrangement, **62 px is a permanently blank master band** (P2) and another
100 px per return is blank the moment a reverb send exists — one send takes the visible
track count at 100 px from 6 to 5.

Editor internals at 355.8 px: 40 (tab bar) + ~40 (piano-roll controls bar) + 24 (nav bar)
leaves **~252 px of note grid at 16 px/semitone = 15.7 semitones**, i.e. **1.3 octaves**.
Open the velocity lane (80 + 6) and it is **10 semitones — under an octave**
(`widgets/piano_roll/piano_roll_state.dart:22,202-206`; `widgets/piano_roll.dart:370-410`).

### 1d. Pixel budget — 2560 × 1440 maximised

Two cases, and they differ, which is itself the finding (P4).

**New project created while maximised** (`resetSizesToDefaults` runs):
library 384 (+4) · mixer **500, hard-capped** (+4) · editor 460.8.
Vertical: 1386 − 460.8 − 3 = 922.2 top; − 24 − 62 = **836 → 8 tracks**.
Arrangement width 2560 − 388 − 504 = **1668**.

**Existing project carried over from the laptop** (the normal case): panel sizes come from
`ui_layout.json` / `UserSettings`, so library stays ~256, mixer ~479, **editor stays 355.8 on
a 1440 px screen**. Arrangement width 1825, arrangement height 1058 − 359 = 699 − 86 = 613 →
still **6 tracks**. Nothing recomputes on resize (`daw_screen.dart:3474-3491`).

What genuinely gains from the 30-inch:
- Arrangement width (+219 to +375 px ≈ 3-4 more bars at default zoom). Real.
- Device chain: boxes are fixed-width (322 built-in / 622 VST3 / 150 add-slot) laid out in a
  row, so more width = more devices visible without scrolling (`device_chain_view.dart:1190,
  1207-1225, 1758`). This is the one panel that scales well.
- +2 track rows, but only on a project created at that size.

What is wasted:
- **Height.** Nothing re-proportions, so the editor is the same 356 px it was on the laptop —
  the piano roll still shows ~1.3 octaves on a 1440 px display.
- **Mixer width above 500 px.** The cap is hard (`ui_layout_state.dart:121`) and the strip
  layout does not change with width beyond a longer fader — no sends column, no second info
  row, no bigger meters. Extra width past ~500 buys nothing in the mixer.
- **Editor width.** It spans the whole window (it sits below the Row, not inside it), so the
  piano roll at 2560 is a ~2560 × 250 note grid: a 10:1 letterbox. Width in a piano roll buys
  bars; the scarce axis is pitch, and that is the axis nothing ever grows.

---

## 2. DIALOG & FLOATING INVENTORY

Surface types: **modal** = `showDialog` with the dim barrier · **anchored** = `showBoojyMenu`
or `OverlayEntry` positioned at a trigger · **material** = raw `showMenu`/`PopupMenuButton`
(the two pre-migration sites the backlog already tracks).

| # | Trigger | What opens | Kind | Verdict |
| --- | --- | --- | --- | --- |
| 1 | App launch, File → Start Screen | Start-screen project chooser, `start_screen_modal.dart:43` | modal, dismissible | Acceptable |
| 2 | File → Export Audio | Export dialog + progress + result, `export_dialog.dart:370,547,762` | modal (progress not dismissible) | Acceptable |
| 3 | Audio → Settings | App settings, `app_settings_dialog.dart:40` | modal, two-pane 680 | Acceptable |
| 4 | First-run / audio-device setup | `settings_dialog.dart:28` | modal, non-dismissible | Acceptable |
| 5 | File → Project Settings | `project_settings_dialog.dart:20` | modal 420 | Acceptable |
| 6 | `?` key / Audio menu | Keyboard shortcuts, `keyboard_shortcuts_overlay.dart:11` | modal 680 | Acceptable |
| 7 | Device chain → Float (VST3) | Native floating plugin window, `daw_vst3_mixin.dart:111-140` | native window | Acceptable (explicitly in scope) |
| 8 | Capture MIDI button | `capture_midi_dialog.dart:26` | modal 500 | Acceptable |
| 9 | Audio → About | `AlertDialog`, `daw_menu_bar.dart:110` | modal, **raw Material** | Acceptable content, wrong chrome (P11) |
| 10 | File → New / Close Project | Unsaved-changes confirms, `daw_project_mixin.dart:53`, `daw_screen.dart:2861` | modal, raw Material | Acceptable content, wrong chrome (P11) |
| 11 | File → Save As / Rename | Name entry, `daw_project_mixin.dart:283,477`, `daw_screen.dart:2638` | modal, raw Material | Should be inline — the project name is already an editable field in the top bar (P11) |
| 12 | Engine init failure | `daw_screen.dart:532` | modal, raw Material | Acceptable |
| 13 | **Cmd+B / Edit → Bounce MIDI to Audio** | "Coming soon in a future update." | modal, raw Material | **Should not exist** (P12) |
| 14 | *(unreachable)* | VST3 plugin list "Plugins - Track 3" → parameter editor with an "Open GUI" button that fires a snackbar reading "🎛️ Native editor support coming soon!" | modal, raw Material | **Should not exist** — dead code (P13) |
| 15 | Mixer strip ⚡ | FX picker (insert vs shared send), `fx_picker_dialog.dart:39` | modal 320 | **Should be a panel/anchored menu** (P14) |
| 16 | Device-chain name tap | Instrument browser, `instrument_browser.dart:48` | modal 500 | **Should be a panel** — duplicates the library's Instruments branch (P16) |
| 17 | Device-chain "Add an effect" | Anchored add-effect menu, `device_chain_view.dart:1850-1888` | anchored | Fine, but a third path with different powers (P14) |
| 18 | Mixer strip right-click | Track context menu | **material `showMenu`**, `track_mixer_strip.dart:1391` | Should be `showBoojyMenu` (already in backlog) |
| 19 | Master strip right-click | Rename / colour | **material `showMenu`**, `track_mixer_strip.dart:2035` | Same |
| 20 | Context menu → Change Color | Swatch grid, `track_mixer_strip.dart:1433` **and** a second copy at `:2055` | modal `Dialog` | Should be inline in the menu (P15) |
| 21 | Strip icon tap | Icon picker, `track_mixer_strip.dart:1717` | modal with transparent barrier | Should be an anchored menu (P15) |
| 22 | Clip right-click → Color / Rename | `timeline_context_menus.dart:406,451` | modal, raw Material, **third colour palette** | Should be inline (P15) |
| 23 | Transport BPM double-tap | "Project Tempo" number entry, `tempo_controls.dart:115` | modal, raw Material | Should be inline — the mixer's dB box already types in place (P27) |
| 24 | Audio-editor BPM | "Original BPM", `shared/editors/bpm_display.dart:41` | modal | Same |
| 25 | Track delete / Return delete | Confirms, `track_mixer_panel.dart:614,661` | modal | Acceptable |
| 26 | Wordmark / File / Snap / Signature / Loop | `showBoojyMenu`, `transport_bar/*.dart` | anchored | Correct |
| 27 | Library right-click (folder / item / VST3) | `library_panel.dart:1013,1431,1507` | anchored | Correct |
| 28 | Piano-roll Quantize / Snap | `piano_roll_controls_bar.dart:599,820` | anchored | Correct |
| 29 | Audio-editor warp mode, sampler root note, virtual-piano velocity, knob split buttons | `OverlayEntry` popovers | anchored | Correct |
| 30 | Mixer input chip | `input_selector_dropdown.dart:19` | anchored | Correct |
| 31 | Help → Take a Tour | Tour overlay, `daw_screen.dart:2817-2832` | full-screen overlay | Acceptable (opt-in) |
| 32 | Cmd+Shift+P/L/E/B/H | Palette editor, UI Labs, editor-button and playhead switchers | in-`Stack` overlays | Ship-blocking clutter, already `(Tyr picks)` in the backlog |
| 33 | `file_menu_button.dart:156` | `PopupMenuButton` | material | Backlog-known |

**Score:** 33 surfaces. 12 acceptable, 2 should not exist, 3 should be panels, 7 should be
inline, 9 correct anchored menus. The house style is already good (`showBoojyMenu` is used in
9 places and looks right); the problem is the ~12 raw Material `AlertDialog`s that never got
migrated, and the two dead ones.

---

## 3. MIXER CLARITY

### 3a. Every control on a regular strip (≥ 50 px track height)

Row 1, left to right (`track_mixer_strip.dart:396-432`):

| Control | What it does | Label | Chrome |
| --- | --- | --- | --- |
| Track icon | Opens the icon picker (modal) | none | 14 px glyph, track colour. **Audio default = `BI.speakerHigh`** |
| Number | Mixer position, not the engine id | none | 12 px semibold; hidden < 56 px of info width |
| Name | Double-click to rename | the name itself | 12 px, ellipsised |
| Input chip `In 1 ▾` | Picks the capture input | "In 1" | filled chip + caret. **Audio only, and only when the strip is wide enough** |
| Mute | Silences the track | none | 22 px circle, `BI.speakerSlash`, fill `#FACC15` when on |
| Solo | Solo | none | 22 px circle, `BI.headphones`, fill `#3B82F6` |
| Arm | Record-arm; Shift-click multi-arms | none | 22 px circle, `BI.record`, fill `#EF4444` |
| Monitor | Hear live input | none | 22 px circle, `BI.speakerHigh`, fill `#22C55E`. **Only on armed audio tracks** |
| FX ⚡ | Opens the modal FX picker | none | **bare 17 px glyph, no well, no tooltip**, "+" on hover only |
| Pan | Pan, vertical drag; double-tap centres | none | 22 px ring, **blank at centre**, no tooltip |

Row 2: dB readout box (drag to scrub, click to type — inline) + `CapsuleFader`, a **horizontal**
capsule with the L/R meter painted inside it and a large circular thumb.
Row 3+ (only with sends): per-send label · 16 px knob · dB · ✕.
When automation is open: a `[Volume ▾]` dropdown + value + reset, in the lane-aligned space.

### 3b. Master strip (`track_mixer_strip.dart:2223-2340`)

`BI.headphones` icon · editable name · FX ⚡ (16 px, a different size from the strips' 22 px) ·
pan knob · dB box · fader. **No mute, no solo, no arm** — correct, but it means the master is
the one strip whose control row does not line up with any other, and it still carries a pan
knob that a beginner will never touch on a stereo master.

### 3c. Where the same concept wears different chrome

| Concept | Mixer strip | Elsewhere |
| --- | --- | --- |
| Volume | horizontal capsule fader + inline dB box | device chain: a **22 px vertical thumb strip** on the right edge of the instrument box, same value (`device_chain_view.dart:1152-1158`) |
| Mute | circle + `speakerSlash` ≥50 px | **letter "M" chip** 24-50 px; **6 px dot, not clickable** < 24 px (`:786-855`) |
| Solo | circle + `headphones` | letter "S" chip; 6 px dot |
| Arm | circle + `record` | letter "R" chip; **absent entirely** < 24 px, and transport Record is a separate red ring button |
| Monitor | circle + `speakerHigh`, green | nowhere else |
| Pan | thin ring, blank when centred | nowhere else |
| Automation | context-menu item + `[Volume ▾]` row | arrangement lane opens per track (PR #144) |
| Sends | row under the strip, dB + knob + ✕ | created only through the **modal** FX picker's "Shared (send)" mode |
| Add effect | ⚡ → modal picker (can make a send) | device chain "Add an effect" → anchored menu (insert only); library drag (insert only) |
| Typing a number | dB box: inline | BPM: **modal dialog** |
| Toggle button | filled circle | editor tools: 30 px rounded square, accent fill; transport: circle with a coloured *ring* |

### 3d. My read of `02-mixer-strips.png`

Tyr's "this changed a bit and I don't really like it" has a precise cause: **PR #111
(`1fea655`, v0.7 Slice 2) replaced the M / S / R letters with glyphs** — the v0.6.0 screenshot
still shows `M S R ⚡ ○`. Five things went wrong with that swap, and they compound:

1. **The glyph set collides with itself.** An audio track's default icon is `'volume'` →
   `BI.speakerHigh` (`track_icons.dart:22,82`), which is *exactly* the input-monitor glyph
   (`track_mixer_strip.dart:1591`), and mute is `BI.speakerSlash` (`:1557`). In the top row of
   the screenshot there are **three speaker glyphs meaning three unrelated things** — "this is
   an audio track", "silence the output", "hear the input" — at a 12 px glyph size. Letters
   never had this problem. Separately, `BI.headphones` is Solo *and* the Master's identity
   icon (`track_icons.dart:24,70`; master at `:2254`), which is why the Master row in
   screenshot 01 looks like it is permanently soloed.
2. **The cluster is not aligned between rows.** The monitor button is inserted *inside* the
   right-aligned cluster, between Arm and FX, and only on armed audio tracks
   (`:1583-1599`). In the screenshot the audio row's mute/solo/arm sit ~26 px left of the MIDI
   row's. Down a column of 8 strips this reads as sloppiness, not as information.
3. **The empty circle is the pan knob.** `PanKnob` draws a 270° ring and paints its label
   only when `|pan| > 0.02` (`pan_knob.dart:119-164`), so at centre it is a blank ring with no
   tooltip and no hit affordance, sitting at the end of a row of circular buttons. It reads
   as a sixth toggle that is switched off.
4. **The lightning is the only naked glyph.** Every other control in the row has a filled
   circular well; ⚡ has none, and no `BoojyTooltip` (`:585-621`) while M/S/R all have one. It
   reads as decoration or as a disabled state, not as the button that adds effects and sends.
5. **The colours shout, and they collide with track colours.** On a "calm, quiet when
   healthy" interface the loudest pixels in the window are a saturated red circle and a
   saturated green circle sitting side by side in a *track header*, on a track that is armed
   simply because it was just created. Worse, the palettes overlap: monitor green `#22C55E`
   vs the synth track colour `#69DB7C`; arm red `#EF4444` vs the drums track colour `#F03E3E`;
   mute yellow `#FACC15` vs Sunflower `#FFD43B`; stop orange vs Tangerine
   (`app_colors.dart:152,174,177,180` vs `track_colors.dart:25-32`). On a drum track you
   cannot tell at a glance whether the red means "drums" or "armed". The 2 px full-perimeter
   border in the track colour (`:1197-1208`) makes this worse: in the screenshot the MIDI strip
   reads as *selected* because of its bright green outline, when green is just its identity
   and selection is actually signalled by a **white** border.

The honest summary: the letters carried three unambiguous meanings in 8 px of type. The
glyphs carry the same three meanings in 12 px of picture, using a vocabulary that already
means something else twice over, in colours that already mean something else three times over,
in a row whose x-positions move between strips. Every individual decision in #111 is
defensible; the stack of them is what reads badly.

---

## 4. CONTROL CONSISTENCY

The memory's rule is **toggle = outline · selection = outline-fill · action = glyph +
press-flash**. Measured against the four surfaces:

| Surface | Toggle | Selection | Action |
| --- | --- | --- | --- |
| Transport | `CircularToggleButton`: circle, 2 px coloured ring, 20 % tint fill, hover glow + scale | Snap/Loop split buttons: filled chip | Play/Stop/Record: the *same* circle-with-ring shape as the toggles |
| Editor toolbar | 30 px rounded square (r4), surface fill + divider border | same square, accent fill | same square |
| Mixer strip | 22 px **solid-filled circle**, no border, no hover, no scale | white 2 px strip border | ⚡: bare glyph, no well at all |
| Device chain | `DeviceBox` header: power dot + name + collapse | accent 2 px border on the box | anchored menu from the name |

**Three conflicts:**

- **The circle means three different things.** Transport = action (ring + tint).
  Mixer = toggle state (solid fill). Pan = a continuous *value* (thin ring, no fill). Nothing
  in the shape tells you which. `shared/circular_toggle_button.dart:94-112` vs
  `track_mixer_strip.dart:1604-1640` vs `pan_knob.dart:90-140`.
- **Same role, two shapes.** The editor's tool buttons and the mixer's M/S/R are both
  "selected / not selected" and are a square and a circle respectively.
- **Feedback is uneven.** Transport buttons scale on hover and press and glow when active;
  mixer buttons do nothing on hover at all (no `MouseRegion` state, no `AnimatedContainer`).
  The mixer is the surface you click most.

Tooltips are a fourth axis: `BoojyTooltip` on M/S/R/monitor, plain Flutter `Tooltip` on the
editor tools (`editor_panel.dart:1301`), and **none** on ⚡, the pan knob, or the clickable
track icon.

---

## 5. COMPLEXITY-REMOVAL CANDIDATES

Ordered by (value removed) ÷ (cost of removing).

| Candidate | Evidence | Cost of removal |
| --- | --- | --- |
| **Bounce-MIDI-to-Audio dialog** — a modal that says the feature does not exist, on Cmd+B and in the Edit menu | `daw_screen.dart:2236-2271`, menu wiring `:3548-3551,3592` | Delete the method + two menu entries. **Violates the settled "inert controls work or are hidden" decision**, so removing it is enforcement, not a new decision |
| **VST3 plugin-list + parameter-editor dialogs** — unreachable: `onEditPluginsPressed` is declared on the strip and never rendered | declared `track_mixer_strip.dart:93,179`, never read; bodies `daw_screen.dart:1899-2019`; a byte-identical second copy in `daw_vst3_mixin.dart:144-230` | ~200 lines, zero UI change. Same settled-decision backing |
| **`DAWUIMixin` panel toggles** — `toggleLibraryPanel/toggleMixer/toggleEditor/resetPanelLayout` are never called; `daw_screen.dart` has private copies | `daw_ui_mixin.dart:23-80` vs `daw_screen.dart:980-996, 2070-2110` | ~60 lines, no behaviour change |
| **Instrument-browser modal** — the library panel already lists Instruments and loads on double-click | `instrument_browser.dart:48-120`; library `library_panel.dart` Instruments root | Route the device-chain name tap to focus the library's Instruments branch instead |
| **FX-picker modal** — third path to the same act, and the only one that can create a send | `fx_picker_dialog.dart:39-110` vs `device_chain_view.dart:1850` vs library drag | Real: the insert-vs-send choice must move somewhere. Recommend the anchored add-effect menu gains a "Shared (send)" section, then the modal goes |
| **Two duplicate colour pickers + a third clip palette** | `track_mixer_strip.dart:1433` and `:2055` (identical), `timeline_context_menus.dart:406` | Collapse to one anchored swatch row inside `showBoojyMenu` |
| **Pan knob on the Master strip** | `track_mixer_strip.dart:2296-2302` | None. A beginner never pans a stereo master; the control is one blank ring of pure ambiguity |
| **Track number column** | `track_mixer_strip.dart:933-944` | Low. The number is mixer position, appears nowhere else, and already sheds below 56 px — it is buying 20 px that the name wants |
| **"Convert to Sampler" in the strip context menu** | `track_mixer_strip.dart:1345-1358` | Keep for now — the backlog has an open sampler-workflow question |
| **UI Labs dev switchers** (4 of them, in the shipping build) | `daw_screen.dart:3846-3859` + Cmd+Shift bindings `:3598-3620` | Already `(Tyr picks)` in the backlog. They are in the release build |

Not a removal candidate, but worth stating: the **five-tool toolbar renders with no track
selected** and does nothing (`editor_panel.dart:684-700` keeps `_buildToolRow()` in the
no-selection state). The comment says the tools "aren't track-bound" — that is true of the
*mode*, but on an empty project there is nothing any of the five can act on. Screenshot 01
shows five live-looking buttons above the words "No track selected".

---

## 6. WORKSPACE OPTIONS (laptop 1710 × 1112)

The diagnosis is narrow: **the editor is a permanent third of the height, and the mixer is a
permanent fifth of the width, whether or not either is being used.** Three ways out.

### Option A — Editor and mixer share the bottom region as tabs

```
┌──────────────────────────────────────────────────────────────────────┐ 54
│ ⌂ Untitled   ↶ ↷ ▤        ▶ ■ ● │ 1.1.1 120 BPM 4/4        ▦ mixer  │
├────────────┬─────────────────────────────────────────────────────────┤
│            │ ruler                                                24 │
│  LIBRARY   │ ┌───────────────────────────────────────────────────┐   │
│    256     │ │  1 Drums                                          │   │ 856
│            │ │  2 Bass                                           │   │
│            │ │  3 Keys        … 8 tracks at 100 px               │   │
│            │ └───────────────────────────────────────────────────┘   │
│            │ master                                               60 │
├────────────┴─────────────────────────────────────────────────────────┤
│ [Instrument] [MIDI] [Mixer] │ ✏ ⛶ ⌫ ⧉ ✂ │              presets  ⌄  │ 40
│                                                                      │ 300
│   the selected tab's content, full window width                      │
└──────────────────────────────────────────────────────────────────────┘
```

- **Gains:** 8 tracks instead of 6; the arrangement is 1449 px wide at all times; the mixer
  gets the full 1710 px when it is the active tab, which is where a *horizontal* fader
  actually makes sense.
- **Costs:** you cannot watch a fader while dragging a clip. For a 4-14-track hip-hop project
  that is a real loss during a mix pass — you want meters visible while the arrangement plays.
  Mitigation: keep the compact 1-row strips in the right column as today *and* allow the full
  mixer as a bottom tab, i.e. the right column becomes track headers, the tab becomes the
  mixer. That is close to what the code already is (the right panel *is* the track list —
  `track_mixer_panel.dart:798-800`).
- **Conflicts with a decision:** N.

### Option B — Library as an overlay, mixer stays, editor stays

```
┌──────────────────────────────────────────────────────────────────────┐ 54
├──────────────────────────────────────────────────────┬───────────────┤
│░░░░░░░░░░░░│ ruler                                24 │ + MIDI +Audio │ 24
│░ LIBRARY  ░│                                         │ ▤1 Drums  ●●○ │
│░ overlay  ░│   arrangement, 1710 wide when the       │ ▤2 Bass   ●●○ │ 613
│░ (slides  ░│   library is dismissed                  │ ▤3 Keys   ●●○ │
│░  over)   ░│                                         │               │
│░░░░░░░░░░░░│ master                               60 │ Master        │
├────────────┴─────────────────────────────────────────┴───────────────┤
│ editor, 356                                                          │
└──────────────────────────────────────────────────────────────────────┘
```

- **Gains:** the arrangement gets 256 px back for the 95 % of the time the library is not in
  use; browsing is a deliberate, momentary act (press a key, drag, it dismisses). Cheapest
  option to build — the panel already animates its width.
- **Costs:** drag-and-drop from an overlay onto an arrangement the overlay is covering is
  awkward; the library is the primary way tracks get created in this app
  ("Drag an instrument from the library to start making music" is the empty state). An
  auto-hide that fights the main creation gesture is a bad trade.
- **Conflicts with a decision:** N (the settled decision is about the tree's internal shape,
  not where it lives).

### Option C — Reclaim the structural waste, keep the three-panel shape ← **recommended**

No new layout mode. Four changes, each independently shippable:

```
┌──────────────────────────────────────────────────────────────────────┐ 54
├────────────┬─────────────────────────────────────────┬───────────────┤
│            │ ruler                                24 │ + MIDI +Audio │ 24
│  LIBRARY   │  1 Drums                                │ ▤1 Drums      │
│    256     │  2 Bass                                 │ ▤2 Bass       │ 675
│            │  3 Keys      7 tracks at 100 px         │ ▤3 Keys       │   ← +62
│            │  …                                      │               │
│            │ ── master (only when shown) ──          │ Master     60 │
├────────────┴─────────────────────────────────────────┴───────────────┤
│ ▸ Instrument · MIDI                                          ⌃      │ 40  ← collapsed
└──────────────────────────────────────────────────────────────────────┘     by default
```

1. **Stop reserving the master/return bands when the row is hidden** (P2). +62 px, +100 px per
   return. One `if`.
2. **Start the editor collapsed on an empty project, and auto-expand it on first track
   selection** — which the mixer double-click path already does
   (`daw_screen.dart:3401-3407`). Removes the screenshot-01 state where 44 % of the window
   says "No track selected". Restores 356 px until it is earned.
3. **Re-proportion panels on a display change**, not just on first launch (P4). One call to
   `resetSizesToDefaults` behind a "the window changed size class" guard, or simply clamp the
   editor to `0.32·H` when the window height changes by more than ~20 %.
4. **Raise the mixer's hard max and let the strip earn the width** — at ≥ 420 px show the
   sends inline rather than as extra rows; above 500 px there is currently nothing to gain.

- **Gains:** 7 tracks with the editor open, 11 with it closed, on the laptop; nothing new to
  learn; every change is reversible.
- **Costs:** does not solve the piano roll's pitch-axis squeeze. That needs either Option A's
  full-height editor or a vertical-zoom control, and it is the one thing I would take Option A
  for if the piano roll turns out to be where Tyr spends his time.
- **Conflicts with a decision:** N.

**Recommendation: C now, A's "mixer as a bottom tab" as a follow-up experiment.** C is four
small, independently verifiable changes that buy back 62-160 px of arrangement and remove the
worst first-impression state, without asking anyone to relearn the window. A is the right
answer if dogfooding shows the piano roll is the bottleneck — but it is a workspace-model
change and should not ride along with a release-gate bug fix.

---

## 7. BUGS AND INCONSISTENCIES

Tier key: **DEMONSTRATED** = complete code path read, file:line given · **SUSPECTED** = strong
signal, not fully traced. Nothing here was reproduced in a running app (read-only review).

**P1 · Editor panel holds a third of the window to say "No track selected"**
DEMONSTRATED · sev **med** · `state/ui_layout_state.dart:87` (visible by default),
`screens/daw_screen.dart:3708-3716` (height = `editorPanelHeight`),
`widgets/editor_panel.dart:684-742` (empty state) · User: opens the app, 44 % of the window in
screenshot 01 is an empty panel with five tool buttons that cannot act on anything ·
Conflicts: **N** · Confidence high.

**P2 · The arrangement permanently reserves a master band and a full 100 px band per return, even when the rows are hidden**
DEMONSTRATED · sev **med** · `widgets/timeline_view.dart:988-1004` (master: `if
(masterTimelineVisible) … else SizedBox(height: masterTrackHeight)`), `:965-987` (returns) ·
User: 62 px of the arrangement is always blank; adding one reverb send silently costs another
102 px, taking the laptop from 6 visible tracks to 5 · Conflicts: **N** · Confidence high.

**P3 · The editor spans the full window width, so extra monitor width goes to bars, never to pitch**
DEMONSTRATED · sev **med** · `screens/daw_screen.dart:3648-3700` (the editor sits in the outer
`Column`, below the `Row`); `widgets/piano_roll/piano_roll_state.dart:22`
(`pixelsPerNote = 16`) · User: at 2560 wide the piano roll is a ~2560 × 250 letterbox showing
~1.3 octaves; at 1440 tall it shows the same 1.3 octaves it showed on the laptop ·
Conflicts: **N** · Confidence high.

**P4 · Panel sizes are computed once and never re-proportioned when the window or display changes**
DEMONSTRATED · sev **med** · `screens/daw_screen.dart:3474-3491` (guarded by
`hasInitializedPanelSizes` **and** `!hasSavedPanelSettings`) · User: moving a project from the
15-inch to the 30-inch keeps the laptop's 356 px editor and 479 px mixer; all 850 extra pixels
of height go nowhere · Conflicts: **N** · Confidence high.

**P5 · View → Reset Panel Layout gives different sizes than a first launch**
DEMONSTRATED · sev **low** · `state/ui_layout_state.dart:530-539` (fixed 380 / 250) vs
`:180-191` (proportional) · User: "reset" on a 1710 × 1112 window yields a 250 px editor where
a fresh install would have given 356 · Conflicts: **N** · Confidence high.

**P6 · `ui_layout.json` writes `panel_collapsed.bottom` and never reads it back**
DEMONSTRATED · sev **low** · written `state/ui_layout_state.dart:580`, and `applyLayout`
(`:542-569`) assigns library and mixer visibility but never `_isEditorPanelVisible` — the
comment at `:567` says this is deliberate · User: per-project editor visibility silently does
not round-trip; it always comes from the global preference
(`screens/daw_screen.dart:211`) · Conflicts: **N** · Confidence high.

**P7 · Library and mixer toggles silently do nothing when there is no room**
DEMONSTRATED · sev **low** · `screens/daw_screen.dart:985-990` and `:2070-2077`
(`return; // Not enough room - do nothing`) · User: on a window narrower than
~(library + mixer + 200), clicking the mixer icon in the top bar is a dead click with no
message and no state change. Bites below ~940 px with defaults, up to ~1300 px if both panels
have been dragged wide · Conflicts: **N** · Confidence high.

**P8 · Four dead duplicate panel-toggle methods**
DEMONSTRATED · sev **low** · `screens/daw/mixins/daw_ui_mixin.dart:23-80`
(`toggleLibraryPanel`, `toggleMixer`, `toggleEditor`, `resetPanelLayout`) — no call site; the
wired copies are the `_`-prefixed ones in `daw_screen.dart:980-996, 2070-2110` ·
Conflicts: **N** · Confidence high.

**P9 · Mixer width is hard-capped at 500 px and the strip layout does not change with width**
DEMONSTRATED · sev **low** · `state/ui_layout_state.dart:121,148-150`;
`widgets/track_mixer_strip.dart:379-395` (only the input chip is width-conditional) ·
User: on a 2560 monitor the extra mixer width buys a longer fader and nothing else ·
Conflicts: **N** · Confidence high.

**P10 · Panel containers are 1 px wider than their contents, and the arrangement-width guard ignores 8 px of chrome**
SUSPECTED (cosmetic) · sev **low** · `screens/daw_screen.dart:3122,3129` and `:3313,3321`
(`+ 4` container vs a 3 px `ResizableDivider`), `state/ui_layout_state.dart:202-208`
(`getArrangementWidth` subtracts the panel widths but not the `+4`s) · User: the auto-collapse
guard fires 8 px later than it thinks · Conflicts: **N** · Confidence med.

**P11 · ~12 raw Material `AlertDialog`s outside the Boojy dialog chrome**
DEMONSTRATED · sev **med** · `daw_menu_bar.dart:110`, `daw_project_mixin.dart:53,283,477`,
`daw_screen.dart:532,2246,2638,2861`, `timeline_context_menus.dart:406,451`,
`tempo_controls.dart:115`, `shared/editors/bpm_display.dart:41` — none passes
`BT.dialogBarrierColor` or `BT.dialogWidth*`, unlike the migrated dialogs
(`export_dialog.dart:372`, `app_settings_dialog.dart:42`, `settings_dialog.dart:31`,
`project_settings_dialog.dart:22`, `keyboard_shortcuts_overlay.dart:13`) · User: "Save As" and
"Project Tempo" open Material-blue dialogs with a different barrier dim than "Export" ·
Conflicts: **N** · Confidence high.

**P12 · Cmd+B / Edit → Bounce MIDI to Audio opens a modal that says the feature does not exist**
DEMONSTRATED · sev **med** · `screens/daw_screen.dart:2236-2271` ("Coming soon in a future
update."), wired at `:3548-3551` (menu) and `:3592` (Cmd+B). A second copy lives in
`daw_clip_mixin.dart:298-340` · User: selects a clip, presses Cmd+B, gets a dead-end dialog ·
Conflicts: **Y — "Inert controls work or are hidden"** (BACKLOG, Decisions). Removing it
enforces that decision · Confidence high.

**P13 · The VST3 plugin-list and parameter-editor dialogs are unreachable**
DEMONSTRATED · sev **low** · `onEditPluginsPressed` is declared
(`widgets/track_mixer_strip.dart:93,179`) and passed down
(`widgets/track_mixer_panel.dart:1407-1410`) but **never read in the strip's build** — no
render site exists. So `_showVst3PluginEditor` (`daw_screen.dart:1899-1937`, title
"Plugins - Track 3" with the raw engine id) and `_showPluginParameterEditor`
(`:1941-2019`, with an "Open GUI" button that fires a snackbar reading "🎛️ Native editor
support coming soon!") cannot be opened. Duplicated again in `daw_vst3_mixin.dart:144-230` ·
Conflicts: **Y — same "inert controls" decision** · Confidence high.

**P14 · Three ways to add an effect, with different powers and different chrome**
DEMONSTRATED · sev **med** · mixer ⚡ → modal `fx_picker_dialog.dart:39-110` (**the only path
that can create a send**); device chain "Add an effect" → anchored menu
`device_chain_view.dart:1850-1888` (inserts only); library drag/double-click (inserts only) ·
User: wants a shared reverb, finds "Add an effect" in the device chain, and the option is not
there — it is behind an unlabelled lightning glyph in the mixer · Conflicts: **N** ·
Confidence high.

**P15 · Two colour pickers and two menu systems inside one file**
DEMONSTRATED · sev **low** · identical `_showColorPicker` at
`widgets/track_mixer_strip.dart:1433` and `:2055`; raw `showMenu` at `:1391` and `:2035`; a
third clip palette at `timeline_context_menus.dart:406` · Conflicts: **N** (the `showMenu`
sites are already listed in BACKLOG → Next) · Confidence high.

**P16 · The instrument browser modal duplicates the library's Instruments branch**
DEMONSTRATED · sev **low** · `widgets/instrument_browser.dart:48-120`, opened from the device
box's name tap (`device_chain_view.dart:1166`) · User: two different-looking lists of the same
six instruments · Conflicts: **N** · Confidence high.

**P17 · `BI.speakerHigh` is both the default audio-track icon and the input-monitor button; `BI.speakerSlash` is mute**
DEMONSTRATED · sev **high** · `utils/track_icons.dart:22` (`'volume': BI.speakerHigh`) and
`:82` (`if (lowerType == 'audio') return 'volume';`); monitor
`widgets/track_mixer_strip.dart:1591`; mute `:1557` · User: three speaker glyphs at 12 px in
one row, meaning "audio track", "silenced", "monitoring" · Conflicts: **N** · Confidence high.
Grounded in `02-mixer-strips.png`.

**P18 · `BI.headphones` is Solo and also the Master's identity icon**
DEMONSTRATED · sev **med** · `utils/track_icons.dart:24,70`; solo
`widgets/track_mixer_strip.dart:1568`; master `:2254` · User: the Master strip in screenshot 01
looks permanently soloed · Conflicts: **N** · Confidence high.

**P19 · The monitor button shifts M/S/R left by 26 px, breaking column alignment between strips**
DEMONSTRATED · sev **med** · `widgets/track_mixer_strip.dart:1583-1599` — the monitor button is
appended inside `_buildControlButtons`, whose `Row` is right-aligned after an `Expanded` name,
so its presence pushes mute/solo/arm left by `buttonSize + spacing` = 26 px at full scale,
**only on armed audio tracks** · User: visible in `02-mixer-strips.png` as the two rows'
buttons not lining up · Conflicts: **N** · Confidence high.

**P20 · The pan knob is an unlabelled empty ring at centre, with no tooltip and drag-only interaction**
DEMONSTRATED · sev **med** · `widgets/pan_knob.dart:119` and `:143` (arc and label both gated
on `pan.abs() > 0.02`), `:33-50` (only `onVerticalDrag*` and `onDoubleTap` — a plain click does
nothing), no `BoojyTooltip` anywhere in the file; placed last in the button row at
`widgets/track_mixer_strip.dart:425-431` · User: "what is the empty circle?" · Conflicts: **N**
· Confidence high.

**P21 · The FX ⚡ button has no well and no tooltip, unlike every neighbour**
DEMONSTRATED · sev **med** · `widgets/track_mixer_strip.dart:585-621` — bare `Icon`, no
`Container` decoration, no `BoojyTooltip`; the "+" only appears on hover (`:605-616`). Every
adjacent button is a filled circle with a tooltip (`:1604-1640`) · User: the control that adds
effects and sends reads as disabled decoration · Conflicts: **N** · Confidence high.

**P22 · State colours and track-identity colours occupy the same hues**
DEMONSTRATED · sev **med** · `theme/app_colors.dart:152` (success `#22C55E`), `:174`
(solo `#3B82F6`), `:177` (mute `#FACC15`), `:180` (arm `#EF4444`) vs
`utils/track_colors.dart:25-32` (drums `#F03E3E`, bass `#FF922B`, synth `#69DB7C`) and
`:52-54` · User: a red border on a drum strip and a red circle on an armed strip are the same
red; a green MIDI strip and a green monitor-on button are near-identical greens ·
Conflicts: **N** · Confidence high.

**P23 · Mute/Solo/Arm have three different renderings by track height, and become non-interactive below 24 px**
DEMONSTRATED · sev **med** · `widgets/track_mixer_strip.dart:329-330` (route to 1-row below
50 px), `:786-819` (below 24 px: two 6 px `Container` dots with **no `GestureDetector`** —
display only, and Arm is absent entirely), `:822-855` (24-50 px: letter chips, `BT.borderSm`
rounded squares), `:1546-1602` (≥50 px: circles with glyphs) · User: shrinks tracks to fit a
14-track project, and mute/solo stop responding to clicks · Conflicts: **N** · Confidence high.

**P24 · Track colour and selection both render as a 2 px full border**
DEMONSTRATED · sev **med** · `widgets/track_mixer_strip.dart:1197-1208` — border is white at
90 % when selected, else the track colour · User: in `02-mixer-strips.png` the bright-green
MIDI strip reads as "active" when green is only its identity; the actual selected state (white)
is quieter than several track colours · Conflicts: **N** (the uniform 2 px border is a settled
2026-06-11 call; the *selection* signal competing with it is the issue, not the border) ·
Confidence med.

**P25 · Track volume has two different controls in two panels**
DEMONSTRATED · sev **low** · mixer: `CapsuleFader` + inline dB box
(`widgets/track_mixer_strip.dart:441-466`); device chain: a 22 px vertical thumb strip on the
instrument box writing the same `setTrackVolume` (`device_chain_view.dart:1152-1158`,
mirrored back into the strip at `daw_screen.dart:3759-3772`) · Conflicts: **N** ·
Confidence high.

**P26 · A track's input can only be chosen from a chip that disappears at narrow mixer widths, with no fallback**
DEMONSTRATED · sev **med** · `widgets/track_mixer_strip.dart:388-394` — the chip needs
`stripWidth − 12 − 132 − 52 ≥ 96`, i.e. **≈ 292 px of mixer width**; the mixer's floor is 200
and screenshot 01 shows it at ~210. The strip context menu (`:1290-1387`) has no input entry,
and `showInputSelectorDropdown` has one call site (`:1112`) · User: narrows the mixer, then
cannot choose which mic an audio track records from · Conflicts: **N** · Confidence high.

**P27 · The same "type a number" affordance is inline in the mixer and modal in the transport**
DEMONSTRATED · sev **low** · dB box edits in place (`VolumeReadoutBox`, used at
`widgets/track_mixer_strip.dart:443-451`); BPM double-tap opens an `AlertDialog`
(`widgets/transport_bar/tempo_controls.dart:64-70,115`) · Conflicts: **N** · Confidence high.

**P28 · The fader is horizontal, carries the meter inside it, and its thumb is a third circular shape in a row of circles**
DEMONSTRATED · sev **low** · `widgets/capsule_fader.dart`; row-2 layout
`widgets/track_mixer_strip.dart:437-468` · User: three circle idioms per strip (state toggle,
pan ring, fader thumb). Note this is a consequence of the row-per-track mixer, which is
deliberate — the mixer *is* the track-header column
(`widgets/track_mixer_panel.dart:798-800`) · Conflicts: **N** · Confidence med.

**P29 · The Master strip's ⚡ is 16 px while every other strip's scales to 22 px**
DEMONSTRATED · sev **low** · `widgets/track_mixer_strip.dart:2289-2294` (hard-coded 16) vs
`:354` / `:585` (`_lerp(14, 22, scale)`) · Conflicts: **N** · Confidence high.

**P30 · The circle shape carries three unrelated meanings across the app**
DEMONSTRATED · sev **med** · action: `widgets/shared/circular_toggle_button.dart:94-112`
(2 px coloured ring + 20 % tint); toggle state:
`widgets/track_mixer_strip.dart:1604-1640` (solid fill, no border, no hover);
continuous value: `widgets/pan_knob.dart:90-140` (thin ring) · Conflicts: **N** (does not touch
the settled "quiet panel-toggle chrome" call) · Confidence high.

**P31 · The same "selected" role is a square in the editor and a circle in the mixer**
DEMONSTRATED · sev **low** · `widgets/editor_panel.dart:1322-1333` (30 px, r4, accent fill) vs
`widgets/track_mixer_strip.dart:1618-1622` (circle, solid fill) · Conflicts: **N** ·
Confidence high.

**P32 · Tooltip coverage is uneven inside a single row**
DEMONSTRATED · sev **low** · `BoojyTooltip` on mute/solo/arm/monitor
(`widgets/track_mixer_strip.dart:1546-1602`); plain Flutter `Tooltip` on editor tools
(`widgets/editor_panel.dart:1301`); **none** on ⚡ (`:585`), the pan knob
(`widgets/pan_knob.dart`), or the clickable track icon (`:913-932`) · Conflicts: **N**
(already partly in BACKLOG → Next) · Confidence high.

**P33 · The five-tool toolbar renders live with nothing to act on**
DEMONSTRATED · sev **low** · `widgets/editor_panel.dart:684-700` keeps `_buildToolRow()` in the
no-selection state; the comment at `:676-678` justifies it as "the tools aren't track-bound" ·
User: screenshot 01 — five enabled-looking buttons directly above "No track selected" ·
Conflicts: **N** · Confidence high.

**P34 · The top-bar library toggle bypasses the collapse/expand size memory the divider uses**
SUSPECTED · sev **low** · button path sets `uiLayout.isLibraryPanelCollapsed` directly
(`screens/daw_screen.dart:2079-2082`), divider double-click calls
`uiLayout.toggleLibraryPanel()` → `collapseLibrary()/expandLibrary()`
(`state/ui_layout_state.dart:326-359`, which snapshot and restore
`_libraryLastLeft/RightColumnWidth`) · User: no visible difference today because the widths are
not cleared on collapse — but the two paths will diverge the first time either changes ·
Conflicts: **N** · Confidence med.

---

### One-line severity roll-up

High: P17. Med: P1, P2, P3, P4, P11, P12, P14, P18, P19, P20, P21, P22, P23, P24, P26, P30.
Low: P5, P6, P7, P8, P9, P10, P13, P15, P16, P25, P27, P28, P29, P31, P32, P33, P34.

---

# §3 Reader 3 — Correctness and architecture


Read-only pass. Nothing in the repo was modified. Scope: VST3 host lifecycle, the real-time
render path, lifecycle (device/recording/persistence/export/undo), architecture health, test
usefulness.

**Gates run (all green):**

| Suite | Command | Result | Duration |
| --- | --- | --- | --- |
| Rust | `cargo test --release` (engine/) | **194 passed, 0 failed** | 34 s wall |
| Engine build | `./build.sh release` | exit 0 | ~3 min |
| Dart | `fvm flutter test --dart-define=BOOJY_CI=true` (ui/) | **1282 passed, 0 failed** | 22 s wall |

`test/native/` did run (30 log lines; `clip_drag_overlap_test.dart`, `ruler_zoom_anchor_test.dart`,
`project_golden_paths_test.dart`). So no existing test reproduces anything below — every finding
here is DEMONSTRATED-by-code-path or SUSPECTED, none REPRODUCED. That is itself a finding (§D).

---

## A. Crash / crackle hypotheses, ranked

### C1 — Stopped transport drives every VST3 plugin **one sample at a time**, with two heap allocations per sample

- **Tier:** DEMONSTRATED
- **Severity:** HIGH — this is my primary crackle hypothesis and a credible crash source
- **Confidence:** high

**Path, every step:**

1. `engine/src/audio_graph/renderer.rs:601` — device callback: `if !is_playing { … }` takes the
   *stopped* branch.
2. `renderer.rs:670` — `for frame_idx in 0..frames` — a **per-sample** loop.
3. `renderer.rs:728` (muted/non-solo) and `renderer.rs:740` (audible) — call
   `process_effect_chain(&snap.fx_chain, …)` **inside that per-sample loop**.
4. `renderer.rs:287` — `process_effect_chain` does `effect.process_frame(out_l, out_r)` for each
   effect id.
5. `engine/src/effects.rs:1230` — `EffectType::process_frame` dispatches
   `EffectType::VST3(fx) => fx.process_frame(left, right)`.
6. `engine/src/vst3_host.rs:843-849` — `VST3Effect::process_frame` wraps the single sample and
   calls `self.process_block(&mut l, &mut r)`.
7. `engine/src/vst3_host.rs:852` — `let plugin = self.plugin.lock();` → **one mutex acquisition
   per sample**.
8. `engine/src/vst3_host.rs:855-856` — `let mut out_left = vec![0.0f32; len]; let mut out_right =
   vec![0.0f32; len];` → **two heap allocations per sample**.
9. `engine/src/vst3_host.rs:858` → `vst3_process_audio(..., num_frames = 1)` →
   `engine/vst3_host/vst3_host.cpp:914` `instance->processor->process(data)` with
   `data.numSamples = 1`.

**Numbers at 48 kHz:** 48,000 `IAudioProcessor::process()` calls/second per plugin with
`numSamples = 1`, 96,000 `malloc`/`free` pairs/second, 48,000 mutex acquisitions/second — all
inside the CoreAudio render callback.

The *playing* path is correct: `renderer.rs:1130 / 1190 / 1237` use
`process_effect_chain_block`, which calls `process_block` once per 512-frame sub-block
(`vst3_host.rs:851`, the documented "the real win"). Only the stopped path was left on the
per-sample path — the comment block at `renderer.rs:604-616` shows the stopped path was hardened
for *locking* (C1/C32) but the per-sample FX dispatch was never converted.

**User-visible effect:** Load a VST3 instrument (Boojy puts instruments in `fx_chain`), then sit
with the transport stopped — programming MIDI, tweaking the plugin GUI, using the virtual piano.
CPU spikes, the metronome/monitoring/virtual-piano audio crackles, and a plugin that does not
tolerate repeated `numSamples = 1` calls (many allocate or assert) can fault. This matches the
reported "crackles, and then it might crash afterwards" precisely, and explains why it feels
random: it depends on being stopped with a plugin loaded, not on any explicit action.

**Minimal manual repro for Tyr:** open a project, add one VST3 (Serum is installed — the test log
shows 2397 params), press **Stop**, do nothing. Watch Activity Monitor's CPU for the Boojy
process. Expect a large idle CPU load that scales with plugin count. Remove the plugin → load
drops. Then compare against the same project **playing** — CPU should be *lower* while playing,
which is the tell.

**How to close it:** convert the stopped branch to the same sub-block shape as the playing branch
(accumulate `sb_len` frames into scratch, one `process_effect_chain_block` per sub-block).
Independently, `VST3Effect::process_block` must not allocate — hoist `out_left`/`out_right` into
the struct, sized at `block_size` in `initialize()`.

---

### C2 — Recording appends to an un-reserved `Vec` under a blocking lock, on the audio thread

- **Tier:** DEMONSTRATED
- **Severity:** HIGH
- **Confidence:** high

**Path:**

1. `engine/src/audio_graph/renderer.rs:677` (stopped) and `:1271` (playing) —
   `recorder_refs.process_frame(...)` is called **per frame** from the device callback.
2. `engine/src/recorder.rs:639` — `RecordingState::Recording` arm.
3. `engine/src/recorder.rs:655` — `let mut samples = self.recorded_samples.lock();` — a **blocking**
   `parking_lot::Mutex` lock, not the `try_lock`-then-count pattern used for `state`/`tempo`/
   `time_signature` at `recorder.rs:482-513`.
4. `engine/src/recorder.rs:656-657` — `samples.push(input_left); samples.push(input_right);` with
   **no `reserve`** anywhere (`grep 'with_capacity\|reserve' engine/src/recorder.rs` → only the
   unrelated peaks buffer at `:328`). `start_recording` at `recorder.rs:167-169` only `clear()`s.

**Two failure modes:**

- *Amortised realloc.* `Vec` doubles. At 48 kHz stereo, 10 minutes of recording is 57.6 M f32
  ≈ 230 MB. Each doubling is an allocation + `memcpy` of up to 230 MB **inside the render
  callback** — tens to hundreds of milliseconds. Guaranteed dropout, and it gets worse the longer
  you record. On a first take the Vec has no capacity, so the early doublings are frequent.
- *Lock contention.* `get_recording_peaks` (`recorder.rs:321`) and `get_recorded_sample_count`
  (`recorder.rs:307`) take the same mutex from the UI thread. Any live waveform/level poll during
  recording stalls the audio thread on a blocking lock.

**User-visible effect:** crackling that gets worse as a take gets longer; worst on long takes.
A long enough stall can make CoreAudio tear down the stream, and a failed 200 MB allocation
aborts the process (Rust allocation failure is an abort, not a panic — `catch_unwind` at
`engine/src/ffi/mod.rs:36` cannot catch it, and it happens on the audio thread anyway).

**Minimal repro:** arm an audio track, record for 10+ minutes with the metronome on, listen for
periodic dropouts that grow in spacing (they should occur at ~each doubling: ~5 s, ~10 s, ~21 s,
~42 s, ~85 s, ~170 s, ~340 s of take time).

**How to close it:** reserve capacity for a generous take length on `start_recording`, and/or move
the write to a lock-free SPSC ring (`ringbuf` is already a dependency) drained by a writer thread.

---

### C3 — Loading a VST3 holds the `effect_manager` lock across the entire plugin load

- **Tier:** DEMONSTRATED
- **Severity:** HIGH
- **Confidence:** high

**Path:**

1. `engine/src/api/vst3.rs:20-22` — `add_vst3_effect_to_track` takes `graph.lock()`,
   `track_manager.lock()`, and **`let mut effect_manager = graph.effect_manager.lock();`**.
2. `engine/src/api/vst3.rs:34` — *still holding those locks* — `VST3Effect::new(plugin_path, …)`,
   which is `vst3_host.rs:684` → `VST3Plugin::load` → `vst3_load_plugin`
   (`vst3_host.cpp:505`) → `VST3::Hosting::Module::create` (**dlopen from disk**) +
   `component->initialize()` + controller creation + `IConnectionPoint` wiring.
3. `engine/src/api/vst3.rs:38-40` — still holding the locks — `vst3_effect.initialize()` →
   `setupProcessing` + `activateBus` + `setActive(true)` + `setProcessing(true)`.
4. Meanwhile the audio thread at `renderer.rs:662-667` (stopped) / `renderer.rs:892-897` (playing)
   does `effect_manager.try_lock()`, fails, increments `EFFECT_LOCK_CONTENTION`, then falls back
   to a **blocking** `effect_manager.lock()`.

**User-visible effect:** the audio callback is blocked for the whole plugin load — for a large
instrument that is seconds, not milliseconds. Guaranteed hard dropout / glitch burst at the moment
you add a plugin.

Note the *restore* path is already correct: `engine/src/audio_graph/project.rs:674` /`:714` use
scoped `self.effect_manager.lock().create_effect(effect)` after the load completes. The live
add path was not given the same treatment.

**How to close it:** mirror the restore path — load and initialise the plugin with no manager
locks held, then take `effect_manager` only for `create_effect` and `track.fx_chain.push`.

The same shape applies to **removal**: `engine/src/api/effects.rs:113` holds `effect_manager`, and
`effects.rs:1391` `self.effects.remove(&id)` drops the last `Arc`, running
`VST3Plugin::drop` → `vst3_unload_plugin` (`vst3_host.cpp:606`) → close editor + `setProcessing(false)`
+ `terminate()` + module unload — all under the lock the audio thread needs.

---

### C4 — VST3 editor and controller calls run on the Flutter UI thread, not the macOS main thread

- **Tier:** SUSPECTED (strong circumstantial evidence in the code itself)
- **Severity:** HIGH — my primary *crash* hypothesis
- **Confidence:** medium-high

**Path:**

Every editor operation is a direct `dart:ffi` call from the Dart isolate:

- `ui/lib/services/vst3_editor_service_native.dart:145` `vst3OpenEditor`
- `:151` `vst3GetEditorSize`
- `:191`, `:282` `vst3AttachEditor`
- `:118`, `:176`, `:184`, `:194`, `:214`, `:284`, `:312`, `:380` `vst3CloseEditor`
- `:247/:249` `setVst3EditorMaxSize`

These land in `engine/src/api/vst3.rs:183 / 206 / 229 / 263 / 557` and then
`vst3_host.cpp:1339 vst3_open_editor` (`controller->createView`), `:1378 vst3_close_editor`
(`editor_view->removed()`, releasing the plugin's NSView), and `:1416 vst3_attach_editor`
(`view->attached(parent, kPlatformTypeNSView)`).

On macOS, a Flutter app's Dart/UI task runner is **not** the platform (NSApplication main) thread.
VST3 requires `IPlugView`/`IEditController` on the host's UI thread; Cocoa requires view creation
and teardown on the main thread.

**The code itself is the evidence.** `engine/vst3_host/vst3_host_mac.mm:20-27`:

```objc
if (![NSThread isMainThread]) {
    fprintf(stderr, "📐 [ObjC] vst3_resize_nsview: dispatching to main thread\n");
    dispatch_async(dispatch_get_main_queue(), ^{ vst3_resize_nsview(nsview, width, height); });
    return;
}
```

That guard exists on the *only* two Cocoa entry points. It is reached from
`PlugFrame::resizeView` (`vst3_host.cpp:299`), which plugins call synchronously from inside
`view->attached()` — i.e. from inside `vst3_attach_editor`. Someone added a main-thread bounce
because attach was observed off the main thread. Everything *else* on that same call stack —
`createView`, `attached`, `removed`, `setFrame`, `setParamNormalized` — has **no** such guard.
`vst3_host.cpp:13` even carries the comment `// macOS specific includes for main thread check`
above `#include <pthread.h>`, but `pthread_main_np` is never called anywhere in the file.

**User-visible effect:** opening, closing, re-docking, or floating a plugin GUI occasionally
crashes, with no consistent trigger — the classic signature of off-main-thread AppKit work.
Sensitive to which plugin (plugins with heavier view setup fault more often).

**How to close it (cheap, decisive):** add `fprintf(stderr, "attach on main=%d\n", pthread_main_np())`
at the top of `vst3_attach_editor` / `vst3_open_editor` / `vst3_close_editor`, rebuild, open a
plugin GUI, read the log. If it prints 0, the hypothesis is confirmed and the fix is to marshal
all `IPlugView`/`IEditController` calls through the Swift side (`VST3PlatformChannel`) onto the
main queue, rather than calling FFI from Dart.

---

### C5 — `dispatch_async` in `vst3_resize_nsview` captures an unretained, possibly-dead NSView

- **Tier:** DEMONSTRATED (code path); the *timing* that triggers it is SUSPECTED
- **Severity:** HIGH
- **Confidence:** medium

**Path:**

1. `ui/macos/Runner/VST3PlatformView.swift:137` — `Unmanaged.passUnretained(hostView).toOpaque()`;
   the raw NSView pointer is handed to Dart (`:139`) → `vst3AttachEditor`.
2. `vst3_host.cpp:1497` — `instance->parent_window = parent;` — C++ stores that **unretained**
   pointer indefinitely.
3. `vst3_host.cpp:299` — `PlugFrame::resizeView` calls
   `vst3_resize_nsview(instance_->parent_window, width, height)`.
4. `vst3_host_mac.mm:23-25` — off the main thread, it `dispatch_async`es a block that captures the
   raw `void* nsview` and later does `(__bridge NSView*)nsview`, `[view window]`, `[view setFrame:]`.

Between the dispatch and the block running, Flutter can dispose the platform view (track switch,
panel collapse, dock→float transition) and `VST3PlatformView.swift:442`
`editorView?.removeFromSuperview()` / `:468 deinit` can free it. The block then messages freed
memory on the main thread.

`closeEditorOnDispose` (`vst3_editor_service_native.dart:305`) is the mitigation, and it is
explicitly documented as such at `:302-304` — but it clears `parent_window` in C++ (`vst3_host.cpp:1385`),
which does **not** cancel an already-queued `dispatch_async` block that captured the pointer by value.

**User-visible effect:** crash when a plugin asks to resize around the moment its editor is being
torn down or re-docked — e.g. switching tracks while a plugin GUI is open.

**How to close it:** retain the NSView for the life of the attachment (pass `passRetained`, release
on `vst3_close_editor`), or re-read `instance->parent_window` inside the dispatched block rather
than capturing it.

---

### C6 — Project save serialises every VST3's state while holding `effect_manager`; auto-save does it on a timer

- **Tier:** DEMONSTRATED
- **Severity:** MED-HIGH
- **Confidence:** high

**Path:**

1. `engine/src/api/project.rs:33` — `save_project` takes the graph lock, then `:36`
   `graph.export_to_project_data(...)`.
2. `engine/src/audio_graph/project.rs:31-33` — takes `track_synth_manager`, `track_manager` **and
   `effect_manager`** and holds all three for the whole traversal.
3. `engine/src/audio_graph/project.rs:203` — inside that hold:
   `let state_data = vst3.get_state().unwrap_or_default();` → `vst3_host.rs:462-469` →
   `vst3_get_state_size` + `vst3_get_state` (`vst3_host.cpp:1185`, `:1224`), each of which calls
   `component->getState()` and `controller->getState()` — for a large synth, megabytes of
   serialisation.
4. `:205` — plus a base64 encode of the whole blob, still under the lock.
5. Audio thread blocks at `renderer.rs:666` / `:897`.

`ui/lib/services/auto_save_service.dart:63` is a `Timer.periodic(Duration(minutes: …))`, so this
stall recurs unprompted.

**User-visible effect:** an audio glitch every time you save, and a *periodic* glitch on the
auto-save interval with no user action — which reads as "random crackling".

**Also demonstrated in the same code:** `vst3_get_state_size` and `vst3_get_state` each call
`getState()` independently (`vst3_host.cpp:1195` and `:1233`). If the plugin's state grows between
the two calls, `totalSize > max_size` (`:1247`) returns −1 → `vst3_host.rs:475` returns `Err` →
`project.rs:203` `.unwrap_or_default()` → **an empty state blob is saved and the plugin's settings
are silently lost on reload.** Severity med, confidence medium (needs a plugin whose state size
changes between calls).

**How to close it:** snapshot `(effect_id, Arc<Mutex<EffectType>>)` pairs under a brief
`effect_manager` lock, drop it, then call `get_state()` on the clones. And make `vst3_get_state`
a single `getState()` into a stream the caller sizes from.

---

### C7 — Export runs the offline renderer over the *live* effect instances, with the stream still running

- **Tier:** DEMONSTRATED
- **Severity:** MED-HIGH
- **Confidence:** high

`ui/lib/widgets/export_dialog.dart:641` calls `exportWavWithOptions` with **no prior transport
stop** (`grep 'stop' ui/lib/widgets/export_dialog.dart` → no hits). The engine side does not stop
it either (`engine/src/api/project.rs:218-237` `export_to_wav`, `:360` `export_wav_with_options`).
`AudioGraph::render_offline` then:

- takes `effect_manager.lock()` repeatedly through the render —
  `engine/src/audio_graph/offline.rs:181, 454, 519, 564, 774, 966` — contending with the audio
  callback's blocking fallback;
- processes through the **same** `Arc<Mutex<EffectType>>` instances the live callback is using, so
  reverb tails, delay lines and LFO phase interleave between the export and live playback;
- at `offline.rs:192-196` calls `effect_mgr.set_builtin_sample_rate(TARGET_SAMPLE_RATE)` and
  `master_limiter.set_sample_rate(...)` **globally**, retuning the *live* stream's built-in effect
  coefficients for the duration of the export and restoring them after.

**User-visible effect:** exporting while the transport is running produces audible glitching *and*
a non-deterministic exported file. The bug hides because most people press Stop first.

**How to close it:** refuse to export (or stop the transport) while playing, or give the offline
render its own cloned effect chain.

---

### C8 — `vst3_set_parameter_value` never reaches the audio processor

- **Tier:** DEMONSTRATED
- **Severity:** MED (functional, not a crash)
- **Confidence:** high

`vst3_host.cpp:1073-1080`:

```cpp
bool vst3_set_parameter_value(VST3PluginHandle handle, uint32_t param_id, double value) {
    …
    return instance->controller->setParamNormalized(param_id, value) == kResultOk;
}
```

That writes the **edit controller** only. `ProcessData::inputParameterChanges`
(`vst3_host.cpp:904`) is fed exclusively from `instance->param_changes`, which is only ever
populated by the MIDI-CC path (`:987-993`) and the program-change path (`:1633-1638`). Both of
those carry an explicit comment saying the controller-only write was the old bug (C34).
`set_vst3_parameter_value` was never given the same fix.

Reached from `engine/src/api/vst3.rs:145` ← `ui/lib/screens/daw_screen.dart:1895`
`_onVst3ParameterChanged` → `vst3PluginManager.updateParameter`.

**User-visible effect:** moving a plugin parameter from *Boojy's own* parameter sliders changes the
plugin's GUI but not the sound. (Moving it inside the plugin's own GUI works, because that path
goes through the plugin's internal controller→processor link.)

**How to close it:** mirror the program-change fix — `param_changes.addParameterData(param_id, …)`
+ `queue->addPoint(0, value, …)` alongside the controller write.

---

### C9 — FX chain order is not preserved across save/reload when VST3 and built-in effects are mixed

- **Tier:** DEMONSTRATED
- **Severity:** MED
- **Confidence:** high

`engine/src/audio_graph/project.rs:543` — on restore, the `fx_chain` loop **skips** VST3 entries
("they are restored from `vst3_plugins`"); `:651-724` then appends every VST3 plugin to
`track.fx_chain` *after* all built-in effects have been pushed. `Vst3PluginData.effect_id`
(`engine/src/project.rs:212`) is saved but never used to restore position — `create_effect`
(`effects.rs:1365`) hands out fresh sequential ids.

**User-visible effect:** a chain of `[VST3 saturator, built-in EQ]` reloads as
`[built-in EQ, VST3 saturator]`. The project sounds different after reopening.

**How to close it:** persist the chain order explicitly (index alongside each entry) and rebuild
`fx_chain` in the saved order.

---

### C10 — Device loss is detected only while playing, and the stream is never rebuilt

- **Tier:** DEMONSTRATED
- **Severity:** MED
- **Confidence:** high

`engine/src/audio_graph/renderer.rs:1349-1353` — the cpal error callback stores the error string
and `eprintln!`s. The only consumer is `ui/lib/controllers/playback_controller.dart:354`, inside
the **playhead timer**, i.e. only while the transport is running. `restart_audio_stream`
(`engine/src/audio_graph/device.rs:212`) is called only from `set_buffer_size` (`:30`) and
`set_output_device` (`:344`) — never from error recovery.

**User-visible effect:** unplug an interface while stopped (or while only monitoring/previewing)
and everything goes silent with no message and no recovery until you manually change the output
device in settings. Hot-plugging a new device is never picked up.

---

## B. Other defects

### C11 — `eprintln!` remains on realtime-reachable paths

- **Tier:** DEMONSTRATED · **Severity:** LOW-MED · **Confidence:** high

`engine/src/vst3_host.rs:864` — `eprintln!("VST3 processing error: {e}")` inside
`VST3Effect::process_block`, which is called from the render callback. A plugin that returns
non-`kResultOk` (e.g. `vst3_host.cpp:920` "Plugin not active", which happens during the
deactivate/reactivate window of `reset()` and `set_sample_rate`) makes the audio thread do
blocking stderr I/O **every block** — exactly the failure mode the renderer's contention counters
(`renderer.rs:12-18`) were introduced to eliminate. The BACKLOG already notes "No audio-thread
logging gate" under *Engineering follow-ups*; this is a live instance of it, not a hypothetical.

Similarly `vst3_host.rs:895/900/906` (`set_sample_rate`) — reached from
`EffectManager::set_sample_rate` (`effects.rs:1332-1337`), which is currently only called outside
the callback (`renderer.rs:532`), so lower risk.

### C12 — `VST3Effect::reset()` tears the plugin down and back up, from wherever it is called

- **Tier:** SUSPECTED · **Severity:** MED · **Confidence:** medium

`vst3_host.rs:870-876` — `reset()` does `deactivate()` → `initialize()` → `activate()`. That is a
full `setProcessing(false)` / `setActive(false)` / `setupProcessing` / `setActive(true)` /
`setProcessing(true)` cycle (`vst3_host.cpp:832`, `:783`, `:726`), which allocates inside the
plugin. `Effect::reset` is part of the shared trait, so any caller that assumes "reset is cheap,
just clear the buffers" (true for every built-in effect) gets a heavyweight teardown for VST3.
**To close:** grep every `reset()` call site for one on the audio thread; if none, downgrade to
low. `offline.rs:49 reset_builtin_fx_offline` deliberately skips VST3, which suggests the risk was
understood in one place but not enforced in the trait.

### C13 — `vst3_scan_directory` dlopens every plugin in-process

- **Tier:** SUSPECTED · **Severity:** MED · **Confidence:** medium

`vst3_host.cpp:361` — `VST3::Hosting::Module::create(plugin_path, error)` for every `.vst3` bundle
found by `fs::recursive_directory_iterator`, inside the host process, with no sandbox and no
crash isolation. One badly-behaved or ABI-mismatched plugin takes the whole app down at scan time.
Scanning is also the one VST3 API path that does **not** take the global graph mutex
(`api/vst3.rs:303`, `:320` — no `get_audio_graph()`), so it can run concurrently with anything.
**To close:** ask Tyr whether crashes correlate with app launch / opening the plugin browser. The
standard fix (out-of-process scan worker + a cached plugin database) is a real piece of work;
a cheap interim is a "last plugin attempted" marker file so a crash on next launch skips it.

### C14 — `processContext` is always null

- **Tier:** DEMONSTRATED · **Severity:** LOW · **Confidence:** high

`vst3_host.cpp:911` — `data.processContext = nullptr;`. Plugins never learn tempo, time signature,
playhead position, or play state. Tempo-synced delays/LFOs/arpeggiators in hosted plugins will not
follow the project tempo. Spec-legal, but a visible feature gap; a minority of plugins also
dereference it without a null check.

### C15 — `vst3_close_editor` can release an attached view without calling `removed()`

- **Tier:** DEMONSTRATED · **Severity:** LOW-MED · **Confidence:** medium

`vst3_host.cpp:1378-1392` — `removed()` is called **only if `instance->parent_window`** is set. If
attach partially succeeded (e.g. `view->attached()` returned non-ok at `:1489`, so
`parent_window` was never assigned at `:1497`, but the plugin had already created its view),
the `IPtr` release at `:1387` destroys an attached view without the spec-mandated `removed()`.
Plugin-dependent leak or fault.

### C16 — `PlugFrame::resizeRecursionGuard_` is a plain `bool`

- **Tier:** DEMONSTRATED · **Severity:** LOW · **Confidence:** medium

`vst3_host.cpp:180` declares `bool resizeRecursionGuard_;` while `refCount_` beside it is
`std::atomic<uint32>`. `resizeView` can be entered from more than one thread (plugin UI timer
thread vs. the FFI thread during `attached()`), and the guard is read/written non-atomically at
`:283-286` and `:311`. Data race; worst case a recursive resize gets through.

### C17 — Per-callback deep clone of every track's clip and automation vectors

- **Tier:** DEMONSTRATED · **Severity:** MED · **Confidence:** high

`engine/src/audio_graph/renderer.rs:841-854`, inside the device callback, per track, per callback:
`track.audio_clips.clone()`, `track.midi_clips.clone()`, `track.fx_chain.clone()`,
`track.volume_automation.clone()`, `track.sends.iter().map(...).collect()`.

`TimelineClip` (`engine/src/track.rs:21-58`) itself owns two `Vec<ClipAutomationPoint>`
(`:54`, `:57`), and `TimelineMidiClip` (`:240-253`) owns two more. So the clone of one track's
`audio_clips` is `1 + 2×(clip count)` heap allocations, repeated for `midi_clips`, every callback.

A 20-track project with 10 clips per track is roughly 500+ allocations per callback ≈ 47,000
allocations/second at 512 frames / 48 kHz, and it scales with project size. The comment at
`renderer.rs:550-566` shows the scratch *audio* buffers were deliberately hoisted to avoid exactly
this; the snapshot vectors were not given the same treatment (`snapshot_buf` is reused, but its
*contents* are freshly allocated each time).

**User-visible effect:** crackling that gets worse as a project grows — consistent with "sometimes
crackles" on a real project but never on a test project.

**How to close it:** store clips behind `Arc` in `Track` so the snapshot clones a pointer, or
maintain a double-buffered snapshot published by the API thread and read lock-free by the callback.

---

## C. Architecture assessment

### What holds

- **The three-layer FFI holds.** `engine/src/ffi/*` are thin `extern "C"` shims; `engine/src/api/*`
  is pure Rust returning `Result`. Exactly **one** leak in the whole tree: `api/vst3.rs:265`
  (`parent_ptr: *mut std::os::raw::c_void`) and its iOS stub at `:649`. The rule file says api/
  has "no raw pointers". It is a single, documented, well-commented exception (`api/vst3.rs:251-262`
  explains the lock discipline around it) — not a pattern breaking down.
- **Lock-order discipline is real and documented.** `.claude/rules/ffi.md`'s synth→track→effect
  rule is upheld at `audio_graph/project.rs:24-33`, `api/sends.rs`'s snapshot pattern, and the
  stopped path's explicit track→effect ordering note (`renderer.rs:617-620`). The FFI/lock audit
  of 2026-05-29 held up — I found no new deadlock, only lock *duration* problems (C3, C6, C7).
- **Beats-vs-seconds discipline holds.** `grep -rn 'setTempo' ui/lib` routes through
  `_onTempoChanged`; the renderer (`renderer.rs:810-817`) carries the seconds-only contract with
  the reason the legacy `tempo/120` scaling was removed. No violation found.
- **Realtime hardening is genuinely in place on the *playing* path** — hoisted scratch buffers,
  `try_lock`-then-count, denormal flush (`renderer.rs:580-586`), `sanitize_sample` at the device
  boundary (`renderer.rs:45`), sub-blocking for VST3. The gaps (C1, C2, C17) are the *stopped*
  path and the *snapshot* step that the hardening pass did not reach.

### What leaks

**`daw_screen.dart` ↔ `screens/daw/mixins/` — a duplicated, partly-diverged method layer.**

This is the evidence the brief asked for, so here it is in full.

- **69 twin pairs** exist: a private `_foo` in `screens/daw_screen.dart` and a public `foo` in one
  of `screens/daw/mixins/*.dart`.
- **~10 are genuine thin delegates** (`void _newProject() => newProject();` at
  `daw_screen.dart:2421`; also `_openProject`, `_openRecentProject`, `_applyUILayout`,
  `_onTrackDeleted`, `_onTrackSelected`, `_onCreateClipOnTrack`, `_onCreateTrackWithClip`,
  `_play`, `_pause`, `_stopPlayback`). Here the mixin copy is the wired one.
- **44 mixin copies have zero call sites anywhere in `ui/lib`.** The wired implementation is
  `daw_screen.dart`'s `_foo`; the mixin's `foo` is dead.

**Two pairs verified diverged** (this is the load-bearing evidence):

1. `saveNewVersion` — wired copy `daw_screen.dart:2527` (referenced at `:2931` and `:3516`);
   dead copy `daw/mixins/daw_project_mixin.dart:403`. The wired one creates the version directory,
   copies `project.json` and `ui_layout.json`, symlinks the `Samples` folder, sets `isLoading`, and
   calls `userSettings.addRecentProject`. The dead one does **none** of that — it only calls
   `saveProjectToPath` and renames. Different status text too ("Created new version: X" vs
   "Saved as X"). If anyone ever routes a call at the mixin copy, "Save New Version" silently
   stops copying the project files.
2. `onMidiFileDroppedOnEmpty` — wired copy `daw_screen.dart:1416` takes **two** parameters
   (`filePath`, position; called at `:1571` and `:3243`); dead copy
   `daw/mixins/daw_library_mixin.dart:389` takes **one**. The signatures have diverged, so they
   are not even interchangeable.

Several more pairs differ substantially in size and are near-certainly diverged the same way —
`_renameProject` (99 lines) vs `renameProject` (78), `_onAudioFileDroppedOnEmpty` (68) vs 58,
`_duplicateSelectedClip` (20) vs 8, `_handleSingleKeyShortcut` (37) vs 28,
`_deleteAudioClipsBatch` (33) vs 29, `_isEmptyAudioTrack` (16) vs 11.

There is also a **live cross-wiring hazard** in the small set that *is* reachable: the mixins call
each other's public copies (`daw_ui_mixin.dart:116 togglePlayPause()`, `:125 toggleMetronome()`,
`:111 isTextFieldFocused()`, `daw_track_mixin.dart:151 updateArrangementLoopToContent()`,
`daw_library_mixin.dart:263 isMidiTrack()`), while the widget tree calls `daw_screen.dart`'s `_foo`
versions of the same names. Mixins cannot see `_`-private members of `daw_screen.dart` (separate
libraries), so the two worlds genuinely cannot converge on their own. Any behaviour fix applied to
one copy leaves the other stale.

**Recommendation (evidence-gated):** consolidate the twins — not because `daw_screen.dart` is
3,915 lines, but because *two verified pairs have already diverged in behaviour and one has
diverged in signature*, and 44 dead copies sit there waiting to be wired back by accident. The
measured problem is silent behavioural drift between two live definitions of the same user action.
Concretely: delete the 44 uncalled mixin copies (a mechanical, `flutter analyze`-verified change),
then for the ~10 real delegates keep the mixin as the single home. That is a small, safe PR that
removes ~1,500 lines and closes the drift hazard, and it does *not* require the full
`daw_screen.dart` split the BACKLOG contemplates.

**I am not recommending** a general `daw_screen.dart` refactor. "144 KB / 3,972 lines" is not a
measured problem and the BACKLOG is right to leave it unscheduled.

### Layering note on VST3

`vst3_host.rs` currently serves three masters: raw `extern "C"` declarations (`:75-185`), a safe
wrapper (`:321-656`), and the `Effect` trait impl (`:842-917`). The `Effect` impl is where the RT
violations live (C1, C11). That is a thin-slice fix, not a restructure.

---

## D. Test usefulness

### Assertion density

Rust: 194 tests. Dart: 1282 tests across 61 files.

| Category | Files | Verdict |
| --- | --- | --- |
| **Models / serialization** (`test/models/*`, 11 files, ~1,100 expects) | high | Real behaviour: round-trips, defaults, edge cases. `serialization_roundtrip_test.dart` (157 expects) is the best file in the suite. |
| **Controllers** (`test/controllers/*`, 4 files, 404 expects) | high | Real behaviour against `MockAudioEngine`. `automation_controller_test.dart` (156 expects) and `track_controller_test.dart` (143) are substantive. |
| **Commands / undo** (`test/services/commands/*`, 7 files, 304 expects) | high | Execute/undo round-trips per command family. Genuinely protective. |
| **Native golden paths** (`test/native/*`, 3 files, 128 expects) | high, narrow | `project_golden_paths_test.dart` covers save→reload for MIDI tracks, notes, sends/returns, undo of a clip move, and one export-energy assertion. `clip_drag_overlap_test.dart` drives a real drag over the real engine. These are the most valuable tests in the repo — and there are only three of them. |
| **UI state / theme** (`state/`, `theme/`) | medium-high | Real assertions, low risk area. |
| **Widgets** (`test/widgets/*`, 10 files, ~105 expects) | mixed | `transport_bar_density_test.dart` (21 expects, sweeps widths) and `anchored_zoom_test.dart` are real. `capsule_fader_test.dart` (3 expects / 3 tests), `editor_panel_test.dart` (3/3), `mini_knob_test.dart` (7/7) are smoke tests — they prove the widget builds, not that it behaves. |
| **Goldens** (`goldens/painters_golden_test.dart`) | low-medium | 2 tests, **0 `expect(` calls** — it relies on `matchesGoldenFile` inside `expectLater`. Fine, but it covers two painters out of the whole `widgets/painters/` directory. |
| **Rust engine** | mixed | `effects.rs` (23), `recorder.rs` (17), `sampler.rs` (16), export modules — real DSP assertions. But `vst3_host.rs`'s 6 tests are largely `println!`-and-shrug: `test_vst3_load_serum`, `test_vst3_effect_wrapper`, `test_vst3_audio_processing` all take an `if let Ok(...) { … } else { println!("this is OK if not installed") }` shape (`vst3_host.rs:983`, `:1023`, `:1067`) and assert essentially nothing about output. `test_vst3_scan_with_wrapper` (`:946`) only asserts the scan doesn't error. |

### Would any of this catch the crackle/crash class? No.

- `AudioGraph::new()` is headless under `cfg(test)`, so **no test ever runs the device callback**.
  C1, C2, C17 (the three RT-violation findings) are structurally untestable by the current suite.
- The BACKLOG's *Decisions* section records "no realtime render-callback tests" as settled. That
  decision is why C1 has survived. It does not need to be reopened as "build a realtime test rig" —
  a plain unit test that calls `process_effect_chain` in a loop and counts allocations (or just
  asserts the stopped path uses the `_block` variant) would have caught C1 for near-zero cost.
- No test loads a real VST3 through the graph. The BACKLOG already lists this under *Tests absent*.
  Given that VST3 is the reported crash area, this is the single highest-value gap.

### Core workflows with NO protecting test

| Workflow | Coverage |
| --- | --- |
| Record (arm → record → stop → clip appears) | **none** end-to-end. `recorder.rs` unit tests cover count-in and metronome maths only. |
| Arrange / edit clips | partial — `clip_drag_overlap_test.dart` covers drag-overlap + undo/redo only. |
| Mix (fader/pan/send → audible change) | `mixer_commands_test.dart` + `send_commands_test.dart` cover the *commands*; `project_golden_paths_test.dart:202` covers send persistence. No test that a fader change changes the rendered signal. |
| Save → reopen a **populated** project | partial — `project_golden_paths_test.dart` covers MIDI tracks, notes, and sends. **Nothing** covers audio clips, effects, or VST3 across a save/reload — which is exactly where C9 lives. |
| Export | one assertion (`project_golden_paths_test.dart:376`, "reverb send has more energy than dry"). No LUFS/normalise/range test at the graph level (the `export/` unit tests cover the primitives in isolation). |
| Undo across engine resync | `undo_redo_manager_test.dart` + per-command tests, plus one native undo case. Adequate. |
| VST3 add / remove / reopen / editor lifecycle | **none.** |
| Tempo change re-push | **none** (BACKLOG already notes this). |
| Device change / stream restart | **none.** |

### Cheapest high-value additions

1. A Rust test asserting the stopped render branch calls `process_effect_chain_block`, not
   `process_effect_chain` — closes C1 permanently.
2. A `recorder.rs` test asserting `recorded_samples` capacity is pre-reserved after
   `start_recording` — closes C2.
3. Extend `project_golden_paths_test.dart` with: audio clip → save → reload; built-in effect +
   second effect → save → reload → **assert chain order** — closes C9.
4. A CI grep gate for `eprintln!`/`println!` under `engine/src/audio_graph/` *and*
   `vst3_host.rs`'s `Effect` impl — the BACKLOG already wants this; C11 shows why.

---

## E. Doc-vs-code contradictions

| # | Doc | Claim | Code | Verdict |
| --- | --- | --- | --- | --- |
| E1 | `.claude/rules/ffi.md` §1 | "`engine/src/api/` … No `extern "C"`, no raw pointers here." | `engine/src/api/vst3.rs:265` `parent_ptr: *mut std::os::raw::c_void`; iOS stub `:649`. | **Contradiction.** One deliberate, well-commented exception. Either document it in the rule as the single sanctioned exception, or move the pointer handling into `ffi/vst3.rs` and have `api/` take an opaque newtype. |
| E2 | `.claude/rules/ffi.md` Gotchas + `docs/ARCHITECTURE.md:44` | "**Every FFI call serialises on one global graph mutex**; the realtime audio callback is the only concurrent thread." | `engine/src/api/vst3.rs:303` `scan_vst3_plugins` and `:320` `scan_vst3_plugins_standard` never call `get_audio_graph()`. `api/preview.rs:122` uses a separate `lazy_static` player mutex, not the graph mutex. | **Contradiction**, and it matters: the plugin scan (which dlopens arbitrary third-party code, C13) can run concurrently with any other API call and with the callback. Either take the graph mutex in the scan paths or amend the rule to name the exceptions. |
| E3 | `.claude/rules/build-and-test.md` | "`ui/macos/Runner/libengine.dylib` is a **symlink** to `engine/target/release/libengine.dylib`, so a plain `cargo build` (debug) won't be picked up." | `build.sh:33` — `ln -sf "../../../engine/$SRC" ../ui/macos/Runner/libengine.dylib` **repoints** the symlink to debug or release depending on `$1`; `:36-37` also `cp`s the chosen build over `ui/macos/libengine.dylib` and `ui/macos/Frameworks/libengine.dylib`. | **Stale.** The literal statement is wrong for `./build.sh` (only for a bare `cargo build`). The consequence is worth flagging for this investigation: **`./build.sh` with no argument installs a debug engine into the app bundle**, and the engine's own code is `opt-level = 0` in debug (`Cargo.toml` only raises deps to 2). A debug engine will crackle regardless of C1/C2/C17. Worth confirming which build Tyr has been dogfooding before attributing all crackle to the findings above. |
| E4 | `docs/ARCHITECTURE.md:51` | "The realtime callback (`audio_graph/renderer.rs`) and offline export (`audio_graph/offline.rs`) **run the same signal chain**, so a bounced file matches what you hear." | The stopped realtime path runs VST3 per-sample (C1) while offline runs 512-frame blocks; `offline.rs:192` retunes built-in effect sample rates for the export only; and the two can run **concurrently over the same effect instances** (C7). | **Partial contradiction.** True for the playing path, false for the stopped path and false whenever export overlaps playback. Worth a sentence once C7 is fixed. |
| E5 | `vst3_host.cpp:13` | `// macOS specific includes for main thread check` above `#include <pthread.h>` | `pthread_main_np` is never called in the file (`grep pthread_main_np engine/vst3_host/` → no hits). | **Dead comment describing a check that does not exist.** Directly relevant to C4 — the check it promises is the one that would settle the crash hypothesis. |

---

## Summary: what I'd point Tyr at first

If the crackle and the crashes have one root, my ranked bet is:

1. **C1** (stopped-path per-sample VST3 + per-sample malloc) — explains crackle whenever a plugin
   is loaded and the transport is stopped, which is most of the time.
2. **C4** (editor calls off the macOS main thread) — explains "random, mostly VST3-related"
   crashes, and is cheap to confirm with one `pthread_main_np()` log line.
3. **C2** (unbounded `Vec::push` in the record callback) — explains crackle that worsens with
   take length.
4. **C3 / C6 / C7** (locks held across plugin load, project save, and export) — explain glitches
   tied to specific actions and to the auto-save timer.

C4 and C5 are the two that can actually *crash*. C1, C2, C3, C6, C7, C17 are the ones that
crackle — and a long enough stall from any of them can make CoreAudio tear down the stream, which
is how "crackles, then it might crash afterwards" becomes one story rather than two.

---

# §4 Reader 4 — Repo health, dependencies, platforms, docs


Reviewed against master @ 2026-09-13 (HEAD 988a068, dirty: `ui/macos/Podfile.lock` +2 staged
review screenshots). Read-only: no files edited, no app launched, no destructive git ops.

---

## 1. Dormant platform inventory

| Item | State | Cost of removal | Cost of keeping | Recommendation | Confidence |
|---|---|---|---|---|---|
| `ui/ios/` | 35 tracked files, **176 KB** tracked (the on-disk checkout with Pods/ephemeral is 3.2 MB but only ~176 KB is git-tracked scaffold). Not referenced by any CI workflow (`grep -rn ios .github/workflows/*.yml` → 0 hits) or `pubspec.yaml` platform config. It is default `flutter create` scaffolding, not hand-built. | Trivial: `flutter create --platforms ios .` regenerates it verbatim in seconds. | Near zero — untouched, doesn't run in CI, doesn't slow builds. | **Keep, cheap insurance** — PLATFORMS.md names iPad a v1.0 candidate; deleting saves nothing (it's not maintained anyway) and regenerating costs nothing either. Low priority either way. | high |
| `ui/android/`, `ui/linux/`, `ui/web/` | **Do not exist.** Confirmed by directory check. | n/a | n/a | Nothing to do — already gone. | high |
| Engine `cfg(target_os = "ios")` | 15 sites, all in `engine/src/midi_input.rs` (2), `engine/src/audio_graph/project.rs` (1), `engine/src/api/vst3.rs` (12, VST3-unavailable-on-iOS stubs). `engine/Cargo.toml` gates `midir` out for iOS (`[target.'cfg(not(target_os = "ios"))'.dependencies]`) since midir doesn't build there — matches PLATFORMS.md's "midir does not build for iOS" claim exactly. `cfg(target_os = "macos")` (1 site, `coreaudio-rs` latency query) is load-bearing for macOS today, not dormant. | Deleting the iOS cfg arms would not shrink the shipped binary (cfg-gated code is already compiled out on macOS/Windows) — it would only remove documentation-by-code of what an iPad port needs to handle (VST3 absence, MIDI replacement). | Near zero to keep — it's dead-weight only in the sense that no iOS target builds today; it costs nothing at compile time on macOS/Windows. | **Keep** — this is exactly the "prep, not built" pattern PLATFORMS.md describes for iPad; deleting forecloses documented v1.0 groundwork for no build-time or maintenance gain. | high |
| `engine/Cargo.toml` `mobile` feature (`mobile = ["native-audio"]`) and `asio` feature | Neither is ever built by `build.sh` or any CI workflow (`grep -rn "features\|mobile\b" build.sh .github/workflows/*.yml` → 0 hits). Untested, effectively unverified config strings. | Trivial to delete; nothing currently exercises them so nothing breaks. | Low — a few lines in `[features]`; risk is that they silently rot (already have, likely) and someone trusts a feature flag that's never been compiled. | **Low-priority cleanup candidate** — not urgent, but unlike the iOS cfg arms this one isn't "documented port prep," it's an unbuilt/unverified flag. Flag to Tyr, don't remove unilaterally (ASIO is an explicit "deferred, not cancelled" decision per BACKLOG). | med |
| Web/WASM engine target, `audio_engine_web.dart`, `dart:js_interop`/`dart.library.html` conditional imports | **None exist.** Verified: no `*_web.dart` file in `ui/lib`, no `dart.library.html`/`dart.library.js`/`dart:js` reference anywhere in `ui/lib`, no `wasm` string anywhere in `engine/`. `ui/lib/audio_engine.dart`'s conditional export is `stub.dart` if not `dart.library.ffi` → `native.dart` — there is no web branch at all. | n/a — nothing to remove. | n/a | The CHANGELOG's "Dead-code pass... removed the Dart-side fake web target and the engine's WASM modules" claim is **verified true**, and ffi.md's "No web binding exists" claim is **verified true**. This confirms PLATFORMS.md's "current web target is not [a real WASM path]... it will be deleted rather than extended" already happened. Nothing to do. | high |
| `Platform.isIOS`/`isAndroid` checks in shipping code | 5 real usages outside the io-utility file itself: `library_service.dart` (×3, iOS content-path branching), `platform_drop_target_native.dart` (×1, disables desktop_drop on mobile), `audio_engine_base.dart` (×1, buffer-size default branch). All are cheap `if` branches, not scaffolding files. | Trivial to strip if iPad is cancelled. | Near zero — a handful of one-line branches. | **Keep** — directly serves the affirmed-for-v1.0 iPad candidate; removing buys nothing since the branches are inert on macOS/Windows anyway. | high |
| `project_manager.dart` / `platform_drop_target.dart` / `vst3_editor_service.dart` conditional-export selectors | Each still branches on `dart.library.io`/`dart.library.ffi` for a native-vs-stub split, with doc comments claiming a "Web: IndexedDB storage" / "Web: desktop_drop web support" branch that **does not exist** — there is no third branch, just native-or-stub with stale comments describing a web path that was deleted. | Trivial — collapsing to a single native import would work today (macOS/Windows only ship). | Low — keeps the door open for a future non-FFI web target integration without redesigning the selector pattern; but the comments actively mislead (see Docs Health, R11). | **Keep the conditional-export mechanism** (real architectural value for the web-prep BACKLOG item), **fix the stale comments** (cheap, high value — a reader currently sees "Web: Uses IndexedDB storage" for a branch that doesn't exist). | med |
| CI matrix | 4 jobs: `flutter-checks` (macOS), `flutter-checks-windows`, `rust-checks` (macOS), `rust-checks-windows`. No Linux or iOS/Android job anywhere. Matches PLATFORMS.md ("no test rigs or infrastructure are built ahead of a platform being scheduled") — consistent, not a gap. | n/a | n/a | Correct as-is; don't add a Linux CI job until Linux is actually scheduled (per BACKLOG's "No speculative infrastructure" decision). | high |

**Summary for item 1:** the platform story is unusually clean. The one deliberately-dead thing
(web/WASM) is verified fully removed already. What remains (`ui/ios/` scaffold, iOS cfg arms,
Platform.isIOS branches) is all inexpensive, documented v1.0-candidate prep, not confusion —
except the three conditional-export files whose doc comments describe a web branch that no
longer exists (see R11 below).

---

## 2. Dead and abandoned code

### R1 — Four orphaned `api/` functions: zero FFI export, zero internal caller
**Category:** dead. **Confidence:** high.

Verified by diffing all `pub extern "C" fn ..._ffi` symbols in `engine/src/ffi/` (203 total)
against every `'symbol'` string literal referenced anywhere in `ui/lib` — **zero** FFI exports
lack a Dart lookup (the v0.7 dead-code pass's "two engine functions no UI called" claim already
got cleaned up; today's export surface is fully consumed). Then checked all 211 `pub fn` in
`engine/src/api/*.rs` for callers anywhere in `engine/src` (not just outside `api/`, to avoid
false positives from legitimate cross-file api-internal calls like `linear_to_db`, which **is**
called internally and is not dead).

Four functions have **no FFI shim and no internal caller** — referenced only by the `pub use`
re-export list in `api/mod.rs`, never called:

- `get_midi_clip_events` — `engine/src/api/midi_clips.rs:387-414` (28 lines). Returns all MIDI
  events for a clip as `(event_type, note, velocity, timestamp_seconds)` tuples.
- `remove_midi_event` — `engine/src/api/midi_clips.rs:421-439` (19 lines). Removes one MIDI event
  by index.
- `start_audio_input` — `engine/src/api/recording.rs:128-138` (11 lines). Starts a 10-second
  input-capture buffer independent of `start_recording`.
- `stop_audio_input` — `engine/src/api/recording.rs:143-150` (8 lines). Stops that capture.

**What they protect today:** nothing reachable — no UI path calls them, directly or via FFI.
**Cost of removal:** none functionally; ~66 lines deleted, `api/mod.rs`'s re-export list shrinks
by 4 names. If a future feature needs raw MIDI-event access (e.g. a "ghost notes" or event-level
undo redesign) or input-level metering independent of arm/record, this is the starting point —
but nothing in BACKLOG references either by name, so there's no known plan these serve.
**Cost of keeping:** low but nonzero — they're exactly the kind of orphan the 2026-09-13
dead-code pass was built to catch, and each one that survives makes the next `grep`-based sweep
noisier.
**Recommendation:** low-priority removal candidate; flag to Tyr rather than delete unilaterally,
since `get_midi_clip_events`/`remove_midi_event` look like they could support a future granular
MIDI-editing feature (BACKLOG's "note transforms... worth rebuilding" item lives nearby
conceptually). Not urgent.

### R2 — UI Labs dev switchers: already a tracked BACKLOG item, verified still present and correctly scoped
**Category:** dead (partially — reachable only via a debug key combo). **Confidence:** high.

`ui/lib/widgets/dev_tools/` = 4 files, 991 lines total (`palette_editor.dart` 456,
`playhead_lab.dart` 239, `editor_button_switcher.dart` 160, `ui_labs_switcher.dart` 136), plus
state/plumbing in `daw_screen.dart` (~8 bool fields + toggle methods + Cmd+Shift bindings around
lines 97-149 and 3598-3906) and supporting enums `editor_button_variant.dart`,
`canvas_bg_variant.dart`, and `TopBarVariant` in `transport_bar/transport_bar_models.dart`.
Verified live: `TopBarVariant.lcd`/`.twoRow`/`.arrangementPinned` still have real rendering
branches in `transport_bar.dart` (lines 554, 1078-1112) reachable only by picking them in the
hidden `UiLabsSwitcher` overlay (Cmd+Shift+L) — the shipped toolbar (post-#145 simplification)
always renders `.inline`, so B/C/D are unreached in normal use but not inert code (they're
maintained variant branches with no user path to them).

This exactly matches BACKLOG's own "Next: candidates" entry ("UI Labs dev switchers are still in
the build... Pick winners, promote the tokens, delete the switchers. *(Tyr picks.)*") — already
correctly identified and already deferred pending Tyr's choice. **Not a new finding**; I'm
recording it here only to confirm the backlog's claim is accurate and quantify it (991 lines in
`dev_tools/` + 3 files of variant enums + the transport-bar branches they gate).
**Recommendation:** no independent action — this is already the right call in BACKLOG (design
decision, not evidence-only cleanup). Confidence the backlog entry is accurate: high.

### R3 — CC/clip-automation lane: verified exactly as BACKLOG describes
**Category:** dead (flag-gated). **Confidence:** high.

`ui/lib/constants/ui_constants.dart:16-19`: `enableClipAutomation` is `const bool = false`, with
an accurate in-code comment ("the engine never reads clip-level automation... the lane would be
purely cosmetic"). Full editing UI exists behind it (`piano_roll_clip_automation_lane.dart`,
`clip_automation_data.dart`'s `ClipAutomationLane`/`ClipAutomationTrack` model with slice/shift/
copy support). Verified the engine claim: `pan_automation`/clip-level automation has zero hits
in `ui/lib` outside the model/painter/lane files themselves, and grep of `engine/src` for any
consumption of per-clip automation data (distinct from track-level volume automation, which is
wired end-to-end and stays) found none. **Not a new finding** — BACKLOG's "CC lane is
unreachable... Decide: expose one lane toggle, or remove the code" is accurate and already the
right framing. Confidence: high.

### R4 — Pan automation: engine writes it, nothing reads it (confirmed exactly as BACKLOG states)
**Category:** dead (flag-gated, affirmed-for-v1.0). **Confidence:** high.

`AutomationParameter.pan` exists in `ui/lib/models/track_automation_data.dart:7` (full min/max/
default), and the picker enumerates `AutomationParameter.values` (`automation_controller.dart:66`)
so pan *would* appear in the parameter picker — except BACKLOG's Decisions section says "the
picker option stays hidden." `pan_automation` on the Rust side exists only in `track.rs`,
`audio_graph/project.rs`, and `audio_graph/mod.rs` — a data field with **zero** consuming reads
in the render path (verified: no hit outside those 3 files, i.e. it's stored/persisted but never
applied to the pan DSP). This is explicitly "Affirmed for v1.0, unscheduled" in BACKLOG, not an
undiscovered gap. Confidence: high, no action needed beyond what's already planned.

### R5 — `split_button.dart` and `piano_roll_toolbar.dart`: false leads, already deleted
**Category:** dead-code-candidate that turned out to be already resolved.

Neither file exists. `git log --diff-filter=D` shows both were deleted in **PR #82**
("chore(ui): delete dead SplitButton/ToolbarButton and piano_roll_toolbar"), well before this
review. What exists today under similar names — `ui/lib/widgets/shared/knob_split_button.dart`
(353 lines, a knob-with-popup control) and `ui/lib/widgets/transport_bar/snap_split_button.dart`
(210 lines, the Snap grid-resolution picker) — are distinct, purpose-built widgets, not
duplicates or renamed survivors of the deleted files. **No action** — flagging only so a future
reviewer doesn't re-chase this lead; the task brief's candidate list appears to be generic/stale
relative to today's tree.

### R6 — `UserSettings.undoLimit`: fully wired, not dead
**Category:** checked, not dead. **Confidence:** high.

`undoLimit` has a getter/setter, persistence (`_keyUndoLimit` load/save), a default-reset path,
and is read live by `UndoRedoManager.maxHistorySize` (`undo_redo_manager.dart:22`). This is a
real, consumed setting — BACKLOG's "Unaccepted proposals" section separately floats an
"undo-history panel" and "undo-limit UI" as *not built* (no UI to change the limit exists), but
the underlying setting itself is not dead code. No removal warranted.

### R7 — Tour overlay, high-contrast theme, `VersionManager`: verified per BACKLOG's own record
- **Tour overlay**: `ui/lib/widgets/tour/tour_overlay.dart` exists and is wired from
  `daw_screen.dart` — matches BACKLOG's "tour overlay infrastructure exists and is wired from the
  DAW screen," parked under the "First Sound" theme, not orphaned. No action.
- **High-contrast theme**: tokens exist in `theme_provider.dart`/`app_colors.dart`/
  `user_settings.dart`, matching the settled decision "High-contrast themes stay hidden until
  their tokens render correctly." Present-but-hidden by design, not abandoned. No action.
- **`VersionManager`**: **zero hits** anywhere in `ui/lib`. Fully deleted, matching CHANGELOG's
  dead-code-pass entry and BACKLOG's Projects-candidates note ("the half-built `VersionManager`
  and its dialog were deleted on 2026-09-13"). Verified true. No action.

### R8 — `#[allow(dead_code)]` / `// ignore:` audit: small and each one justified
**Category:** hygiene, low severity. **Confidence:** high.

Rust: 7 total `#[allow(dead_code)]` sites. 4 are in `engine/src/ffi/mod.rs:72,102,112,125`, each
commented "Incrementally adopted — not all FFI functions use this yet" (a shared helper being
rolled out gradually — legitimate, self-documenting, not hiding genuine dead code). The other 3
(`preview.rs:388`, `recorder.rs:19`, `audio_graph/renderer.rs:31`) were not individually
line-read in this pass; volume is low enough not to warrant it — flag as a spot-check gap if a
future reviewer wants full coverage.

Dart: 6 total `// ignore:` comments. 2 are `non_constant_identifier_names` in the `BI` icon
facade (cosmetic naming convention, expected). 1 is `unused_import` in `daw_library_mixin.dart:7`
(worth a quick look — an unused import is literally free to remove, low-effort cleanup). 3 are
`unused_element`: `_importMidiNotesToTrack` and `truncateName` in `daw_library_mixin.dart` are
**both actually called** within the same file (verified: `_importMidiNotesToTrack` called at
lines 404 and 427; `truncateName` called at lines 50 and 84) — the `ignore:` looks like a stale
analyzer-appeasement left over from when these were mixin-private members the analyzer couldn't
resolve across the `on DAWTrackMixin` composition; today it's very likely a no-op suppression
(low-value cleanup: try removing the ignore comment and see if analyze still passes clean). The
third, `editor_panel.dart:1343` (`_buildPianoToggle`), is genuinely unused and has an explicit
rationale in its doc comment ("kept so it can be dropped back in without rebuilding it") — a
deliberate keeper, not an oversight.
**Recommendation:** trivial cleanup (remove 2 stale `unused_element` ignores + the 1
`unused_import`), not worth a standalone PR on its own; bundle with the next touch of that file.
Confidence: med (didn't run `flutter analyze` myself to confirm the ignores are truly
redundant — the task brief says this isn't needed since the hook already runs it, but that means
I haven't verified analyze stays green without them).

---

## 3. Duplicate paths

### R9 — Residual pre-migration menu sites: exactly as BACKLOG states, no more, no less
**Category:** duplicate (migration incomplete). **Confidence:** high.

`showMenu(` used at `track_mixer_strip.dart:1391` and `:2035` (2 call sites, both in the same
file). `PopupMenuButton` — **zero** hits (BACKLOG says "a `PopupMenuButton` in
`file_menu_button.dart`," but that's stale: `file_menu_button.dart` today uses a private
`_showMenu` helper calling into `showBoojyMenu`-style overlay, not `PopupMenuButton` directly —
verified no `PopupMenuButton(` construct exists anywhere in `ui/lib`). So the true residual count
is **2 sites in 1 file**, not the 2 files BACKLOG implies. Minor doc drift (see R12), trivial
scope either way. Recommendation: migrate `track_mixer_strip.dart`'s two `showMenu` calls next
time that file is open, per the existing rule; no urgency.

### R10 — Track-creation and clip-split: single implementation, multiple entry points (verified clean)
**Category:** checked, not duplicate. **Confidence:** high.

All track-creation call sites (`daw_library_mixin.dart:54,115`, `daw_track_mixin.dart:284,337`)
funnel through one engine call, `audioEngine!.createTrack(type, name)` — multiple UI entry
points (library drop, sampler-from-sample, drum-kit button, mixer-header buttons) but one
underlying path, not divergent logic. Likewise clip splitting has exactly one implementation,
`splitSelectedClipAtPlayhead` in `daw_clip_mixin.dart:212`, called from two `daw_screen.dart`
sites (menu + shortcut) — not two split implementations. The `flutter-ui.md` rule's warning
about `daw_screen.dart` private duplicates vs mixin methods (`_bounceMidiToAudio`, the library
double-click trio) was checked directly: the "duplicate" mentions in `daw_library_mixin.dart`
(lines 36-37, 428-429) are **comments referencing the names**, not live duplicate method bodies
— the actual dead mixin copies were already deleted (per the rule's own note, "v0.6 batch 4").
No new duplication found.

---

## 4. Dependencies

### R11 — `cupertino_icons`: zero call sites
**Category:** dependency. **Confidence:** high.

`ui/pubspec.yaml` declares `cupertino_icons: ^1.0.8` (default `flutter create` template
dependency). Verified: **zero** references to `CupertinoIcons` or `package:cupertino_icons`
anywhere in `ui/lib`. The app uses the `BI` Material-icon facade exclusively per
`flutter-ui.md`'s own rule. This is unused weight, not "iPad prep" — iOS-styled icons aren't part
of any stated design direction (PLATFORMS.md's iPad section talks about touch gestures and
CoreMIDI, not Cupertino visual styling).
**Cost of removal:** trivial — delete one pubspec line, re-run `pub get`.
**Cost of keeping:** negligible build-size/dependency-tree cost, but it's zero-evidence weight
sitting in the manifest.
**Recommendation:** remove. Confidence: high (true zero call sites, unlike the platform-prep
items above which have real, if small, live code).

### Other pubspec dependencies — import-site counts (all justified, no other zero-use candidates)
`ffi` (1 file, but foundational — the whole native binding layer), `desktop_drop` (3),
`cross_file` (1, paired with desktop_drop's `XFile` drop payload), `file_picker` (5),
`shared_preferences` (5), `path_provider` (2), `uuid` (4), `path` (2), `provider` (8, matches
flutter-ui.md's own "~9 files" note), `window_manager` (2), `package_info_plus` (3),
`flutter_svg` (1 — `transport_bar.dart` only, for the wordmark SVG). None of these is heavy-for-
one-thing in a way that's worth flagging; `flutter_svg` is a full SVG-rendering library for a
single wordmark image, which is a legitimate flag for "heavy dep, one small use" but replacing an
SVG asset with a raster PNG to drop the dependency is a design tradeoff (crisp scaling at
arbitrary window sizes vs. dependency weight) that belongs to Tyr, not an automatic removal.
Noting it, not recommending action.

### R12 — `mp3lame-encoder` not yet adopted; ffmpeg runtime dependency confirmed live
**Category:** dependency. **Confidence:** high.

`engine/Cargo.toml` has no `mp3lame-encoder` entry — the planned in-process MP3 replacement
(per `.claude/rules/audio-export.md` and BACKLOG's "Technical debt") has not landed. MP3 export
still shells out to the `ffmpeg` CLI (`engine/src/export/mp3.rs`), confirmed as a genuine runtime
(not build-time) dependency: the crate comment says "MP3 encoding uses ffmpeg via command line."
This matches every doc that mentions it consistently (ARCHITECTURE.md, audio-export.md,
BACKLOG.md all agree) — one home for this fact, no drift. No action needed beyond the already-
planned crate swap.

### R13 — VST3 SDK submodule and committed prebuilt libraries
**Category:** dependency/hygiene. **Confidence:** high.

`engine/vst3sdk` is a git submodule (486 MB checked out, mostly its own `.git` and `doc/`
directories — not part of the parent repo's history, just local disk). Six prebuilt static
libraries are **tracked directly in git** (not gitignored): `engine/lib/{libbase,libsdk,
libsdk_common,libsdk_hosting,libpluginterfaces,libvst3_host}.a` (macOS, largest is
`libsdk.a` at 431 KB) plus five Windows `.lib` counterparts (largest `sdk.lib` at 4.6 MB).
This is the exact situation `vst3-cpp-lib-rebuild` memory and BACKLOG's "macOS CI links the
committed VST3 `.a` libraries rather than rebuilding them" describe — **confirmed accurate**:
macOS CI (`ci.yml`'s `rust-checks`/`flutter-checks` jobs) never runs CMake, so a C++ change to
`vst3_host.cpp` can pass macOS CI while macOS still links the stale committed `.a`. Windows CI
(`rust-checks-windows`) does rebuild via CMake with a cache keyed on the VST3 SDK commit +
`vst3_host` sources. This is a real, already-documented asymmetry, not a new finding — repeating
it here only to confirm it's still true today and quantify the tracked binary sizes.
**Recommendation:** no independent action (BACKLOG already tracks this); the fix (macOS CMake
rebuild in CI) is known and simply not done yet — a scheduling decision, not a discovery.

---

## 5. Documentation health

| Doc | Claim | Reality | Location | Severity |
|---|---|---|---|---|
| README.md | "Record. Capture vocals and instruments with input monitoring, a count-in and **punch in/out**." | Punch in/out was removed from the UI entirely in the work now sitting under CHANGELOG's `## Unreleased` ("Punch in/out is removed for now. The Loop dropdown, the I and O keys and the red punch colouring on the ruler are gone") and BACKLOG's Decisions section confirms it's a deliberate removal, not a bug. The engine's punch code is dormant, never enabled by the UI. | README.md:28 vs CHANGELOG.md:50 and BACKLOG.md:225 | **Real, will ship wrong** — README describes the v0.6.0 tagged release (accurate for that tag) but reads as the *current* feature list; once v0.7.0 tags, this line must be cut or it actively misleads a downloading user into expecting a feature that's gone. Flag as a **must-fix-before-v0.7.0-release** doc task, not urgent today. |
| BACKLOG.md (Technical debt) | "228 hardcoded `fontSize:` values remain across `ui/lib`." | Measured: 370 total `fontSize:` usages; of those, 185 are `fontSize:` followed directly by a numeric literal (the rest already reference tokens — `BT.fontLabel` ×61+5, `BT.fontBody` ×31+8, `BT.fontCaption` ×14+12+7, `BT.fontHeading` ×6, or a local `fontSize` parameter). | `ui/lib/**/*.dart`, counted via grep | **Moderate drift** — the true hardcoded-literal count (185) is noticeably lower than claimed (228), and a real type-scale (`BT.*`) already covers a large share of usages that the claim's phrasing ("228 hardcoded... remain") implies don't exist yet. Doesn't change the recommendation (still worth a themed pass), but the number should be corrected next time this doc is touched — otherwise it undersells how much tokenisation is already done. |
| BACKLOG.md (Technical debt) | "Eleven Dart files exceed 50 KB." Lists 11 named files. | **Verified accurate** — all 11 named files exceed 50,000 bytes (`transport_bar.dart` at 51,161 bytes is the tightest case; using a strict 1024-byte "50 KiB" threshold instead of decimal 50 KB, only 10 clear it, which is why a naive `find -size +50k` check under-counts by one — a units artifact, not a doc error). | Verified via `wc -c`/`find` on `ui/lib` | **No drift** — false alarm on first pass, worth recording so a future reviewer doesn't re-flag it. |
| PLATFORMS.md | "The engine is roughly 30k lines of Rust... The UI is roughly 98k lines of Dart with 33 custom painters." | Measured: engine `.rs` = 29,799 lines (matches "roughly 30k" closely). UI `.dart` = 88,936 lines (not 98k — off by ~9%, i.e. "roughly 98k" overstates today's actual count by about 9,000 lines). Custom painters: 32 classes extend `CustomPainter` (claim says 33 — off by one, negligible). | `engine/src/**/*.rs`, `ui/lib/**/*.dart` | **Minor drift, low severity** — the Rust figure is solid; the Dart figure is a real but modest overstatement (could be legitimate if the doc was written before a chunk of dead-code-pass deletions reduced the line count, which is plausible given the doc's 2026-09-13 date lines up with the same-day dead-code pass — likely just needs a re-measure, not urgent). |
| ffi.md | "No web binding exists (see `docs/PLATFORMS.md`)." | **Verified true** — confirmed no `dart.library.html`/js conditional anywhere in `ui/lib`. | n/a | Accurate, no drift. |
| `project_manager.dart`, `platform_drop_target.dart`, `vst3_editor_service.dart` (in-code doc comments, not a `docs/*.md` file, but user-facing to any developer reading the source) | Each header comment describes a three-way split: "Native... / Web: Uses IndexedDB storage" (or "desktop_drop web support," or "VST3 not supported on web"). | There is **no web branch** in the actual conditional export (`export 'x_stub.dart' if (dart.library.io) 'x_native.dart';` — only two branches, native and stub-for-analysis). The web branch described in the comment doesn't exist in the code. | `ui/lib/services/project_manager.dart:1-9`, `ui/lib/widgets/platform_drop_target.dart:1-8`, `ui/lib/services/vst3_editor_service.dart:1-8` | **Real, mildly misleading** — a developer reading these three files (not the markdown docs) would believe web builds today. Low severity (in-code comments, not a doc a user reads), but easy to fix: rewrite the comments to say "native vs. stub (used for static analysis only); no web build exists yet — see PLATFORMS.md" next time any of the three is touched. |

**Facts with one home vs. drifted:** mostly one home. `AGENTS.md`/README/BACKLOG/ARCHITECTURE/
PLATFORMS don't restate the same fact in ways that visibly disagree with each other (checked
cross-references for punch, web, line counts, file-size claims — the punch and fontSize/line-
count items above are the only real drifts found). `docs/dogfood/` (2 files, last touched
2026-05-25 and 2026-05-31 — roughly 3.5 months stale relative to today) and `docs/private/
COMPETITIVE_ANALYSIS.md` exist on disk, are gitignored, and are **not referenced by any tracked
doc** (AGENTS.md's "Where things are" table omits both entirely, even though the suite-root
AGENTS.md's memory model explicitly names `private/` and implicitly a dogfood-notes pattern as
expected optional dirs). Not a repo-health defect since they're intentionally untracked, but
worth a note: if `docs/dogfood/` is meant to be a living log, it's stale; if it's superseded by
BACKLOG's "Known bugs from dogfooding" section (which is the actual live mechanism today), the
old per-session dogfood files are orphaned notes nobody will re-read.

---

## 6. Repo hygiene

### R14 — `ui/macos/Podfile.lock` working-tree modification: cosmetic CocoaPods version bump
**Category:** hygiene. **Confidence:** high.

The only line changed is `COCOAPODS: 1.16.2` → `1.17.0` — a local CocoaPods CLI version stamp
that `pod install` rewrites whenever the installed CocoaPods gem differs from what's recorded,
regardless of whether any pod dependency actually changed. This is classic environment drift
(the machine's global CocoaPods gem was upgraded at some point) rather than an intentional
dependency change. **Recommendation:** either commit it (if the team standard is "whatever
CocoaPods produces locally") or revert it and pin CI/dev CocoaPods versions to stop the churn —
Tyr's call, not a defect either way, but leaving it uncommitted means every future `pod install`
on this machine will keep flagging the same one-line diff.

### R15 — Untracked staged screenshots are legitimate staging input, not stray artifacts
`docs/reviews/_screenshots/01-empty-project.png` and `02-mixer-strips.png` are exactly the
intended use of that folder per its own README ("Drop current-build screenshots here before
running the `ui-ux-review` workflow... delete the PNGs after"). Not a hygiene issue — correctly
staged, not yet cleaned up because the review that would consume them (this one) is still running.

### R16 — CI coverage gap: Windows `flutter-checks-windows` never builds the engine or sets `BOOJY_CI`
**Category:** hygiene/CI. **Confidence:** high.

`.github/workflows/ci.yml`'s `flutter-checks-windows` job (lines 74-91) has no `needs:` on
`rust-checks-windows`, never runs `cargo build`/`./build.sh`, and runs plain `flutter test`
**without** `--dart-define=BOOJY_CI=true`. Contrast with `flutter-checks` (macOS): it explicitly
builds the engine (`cd engine && cargo build`) *before* `flutter test --dart-define=BOOJY_CI=true`,
specifically so the native-engine tests in `ui/test/native/` fail loudly instead of silently
skipping when the dylib is missing (the whole point of the C92 fix `build-and-test.md`
describes). On Windows, the dylib never exists in that job and `BOOJY_CI` is never set, so every
`test/native/` FFI test **silently reports "skipped," every single Windows CI run**, with no
signal that this is happening. This means the FFI boundary — the single riskiest part of this
architecture per `ffi.md`'s own lock-order/deadlock warnings — is exercised by native tests on
macOS CI only; a Windows-specific FFI regression (e.g. a symbol name mismatch that happens to
still resolve on macOS but not the `.dll`) would not be caught by `flutter-checks-windows` at all.
**Cost of fixing:** moderate — would need `flutter-checks-windows` to depend on
`rust-checks-windows`'s build output (or build its own release engine first), adding real time to
that job (the VST3 CMake rebuild alone is "several minutes" per the workflow's own comment).
**Cost of leaving as-is:** a real, silent, per-PR coverage gap on the platform BACKLOG explicitly
calls out as needing "hardening for beta" and having "fewer testers."
**Recommendation:** worth a scoped follow-up (build the engine in `flutter-checks-windows` too,
gate `test/native/` under `BOOJY_CI=true` there as well) — flag to Tyr as a genuine gap, not
BACKLOG's already-known "no audio-thread logging gate" item (this is a different, previously
unrecorded gap).

### R17 — Audio-thread logging: current `eprintln!`s are not actually in the hot per-buffer path (nuance on a known BACKLOG item)
**Category:** hygiene. **Confidence:** high.

BACKLOG already records "No audio-thread logging gate... nothing in CI catches new [eprintln!]
ones," and 66 `eprintln!` calls do exist under `engine/src/audio_graph/`. Traced where they
actually run: the majority are in `device.rs` (device enumeration/latency-query setup, not the
realtime callback) and `project.rs` (project load/save, not realtime), and `renderer.rs`'s own
top-of-file comment explains that the callback's *former* blocking `eprintln!`s were already
replaced with atomic lock-contention counters (`SYNTH_LOCK_CONTENTION`/`EFFECT_LOCK_CONTENTION`,
`renderer.rs:11-17`) specifically to get stderr I/O off the realtime thread. The one `eprintln!`
that does still run inside a callback closure (`renderer.rs:1351`) is inside the **cpal stream
*error* callback** (fires only on device disconnect/stream failure, not per-buffer) — a rare-path
cost, not a steady-state audio-thread risk. **This confirms the BACKLOG item's severity is
correctly calibrated as a process gap (nothing stops a *future* regression) rather than an
active bug today** — worth noting so it isn't escalated past what BACKLOG already says.

### R18 — Large tracked binaries: VST3 libs are the only outliers; no stray root-level build products
Checked `git ls-tree -r -l HEAD` for the largest tracked blobs: the top entries are the VST3
`.lib`/`.a` files (already covered in R13) and expected assets (bundled fonts, release
screenshots in `docs/screenshots/`). No stray build output, no accidentally-committed `.dylib`/
`.dll`/database dumps found at the repo root or elsewhere. `.gitignore` coverage looks correct —
`git status --ignored` shows the expected `target/`, `build/`, `.dart_tool/`, `Pods/`, `.fvm/`,
IDE folders, and (correctly) `docs/dogfood/`/`docs/private/` as ignored, not tracked-then-
ignored-accidentally. No hygiene defect here.

---

## Headline summary (for the synthesis pass)

1. Platform story is clean: web/WASM dead code is verified fully gone; iOS/Linux/Android leftovers
   are cheap, documented v1.0-candidate prep, not confusion — except stale "Web: IndexedDB" style
   comments in 3 conditional-export files that describe a branch that no longer exists.
2. Only 4 truly orphaned Rust `api/` functions found (zero FFI export, zero caller): `get_midi_clip_events`,
   `remove_midi_event`, `start_audio_input`, `stop_audio_input` (~66 lines total) — everything else
   flagged in BACKLOG as a dead-code candidate (split_button, piano_roll_toolbar, VersionManager,
   UI Labs switchers, CC lane, pan automation) is either already deleted or already correctly tracked.
3. `cupertino_icons` pubspec dependency has zero call sites — safe, trivial removal.
4. README.md still advertises "punch in/out" as a current feature; it was removed in the
   Unreleased work already in CHANGELOG.md/BACKLOG.md — must be cut before v0.7.0 ships.
5. Genuine, previously unrecorded CI gap: `flutter-checks-windows` never builds the engine or sets
   `BOOJY_CI=true`, so every native FFI test silently skips on every Windows CI run — the FFI
   boundary is only really tested on macOS.
6. BACKLOG's "228 hardcoded fontSize:" figure overstates the gap (measured 185 literal values;
   370 total usages, a large share already tokenised via `BT.*`) — correct the number, don't
   change the recommendation.
7. VST3 committed binaries + macOS-links-not-rebuilds asymmetry (R13) and the audio-thread
   eprintln! item (R17) are both already correctly recorded in BACKLOG; verified accurate and
   confirmed the eprintln!s aren't in the actual per-buffer hot path today.
8. `ui/macos/Podfile.lock`'s working-tree diff is just a local CocoaPods version stamp (1.16.2 →
   1.17.0), not a real dependency change — commit or pin, either resolves the recurring diff.

---

# §5 Verifier — adversarial verdicts


Read-only. Traced call chains for every C1-C17 (file 3), spot-verified every T1-T13 (file 1)
and P1-P33 (file 2) against cited file:line, re-measured every quoted count, and checked file 4's
delete/keep recommendations. `cargo test`/`flutter test` not re-run (gates already green per file 3;
no finding here depends on a test result changing). Scope per brief: every DEMONSTRATED/REPRODUCED
finding, every HIGH-severity finding regardless of tier, every file-4 deletion claim. SUSPECTED+low
items (T9, P10, P34, C12, C13) excluded per brief.

## Summary

62 items verified. **61 CONFIRM, 1 REFUTE** (a stale sub-item inside file 2's dialog-inventory
table, not one of its numbered P-findings), **0 DOWNGRADE**, **0 items upgraded** (upgrades are not
permitted and none were warranted). Independent re-measurement matched the report's own numbers in
every case checked: 69 twin pairs (exact match via independent regex), 4 orphaned api functions
(exact), cupertino_icons 0 call sites (exact), fontSize 185 literal / 370 total (exact), 6 tracks /
1.3 octaves on the laptop (order-of-magnitude match). No finding was downgraded — everything I could
independently trace held up exactly as described, including the five crash/crackle hypotheses
(C1-C5) I was told to be especially careful with.

## Table

| ID | Orig. tier | Orig. severity | Verdict | New tier/sev |
|---|---|---|---|---|
| T1 | DEMONSTRATED | med | CONFIRM | — |
| T2 | DEMONSTRATED | low | CONFIRM | — |
| T3 | DEMONSTRATED | low | CONFIRM | — |
| T4 | DEMONSTRATED | med | CONFIRM | — |
| T5 | DEMONSTRATED | med | CONFIRM | — |
| T6 | DEMONSTRATED | low | CONFIRM | — |
| T7 | DEMONSTRATED | med | CONFIRM | — |
| T8 | DEMONSTRATED | low | CONFIRM | — |
| T10 | DEMONSTRATED | low | CONFIRM | — |
| T11 | DEMONSTRATED | low | CONFIRM | — |
| T12 | DEMONSTRATED | low | CONFIRM | — |
| T13 | DEMONSTRATED | med | CONFIRM | — |
| P1 | DEMONSTRATED | med | CONFIRM | — |
| P2 | DEMONSTRATED | med | CONFIRM | — |
| P3 | DEMONSTRATED | med | CONFIRM | — |
| P4 | DEMONSTRATED | med | CONFIRM | — |
| P5 | DEMONSTRATED | low | CONFIRM | — |
| P6 | DEMONSTRATED | low | CONFIRM | — |
| P7 | DEMONSTRATED | low | CONFIRM | — |
| P8 | DEMONSTRATED | low | CONFIRM | — |
| P9 | DEMONSTRATED | low | CONFIRM | — |
| P11 | DEMONSTRATED | med | CONFIRM | — |
| P12 | DEMONSTRATED | med | CONFIRM | — |
| P13 | DEMONSTRATED | low | CONFIRM | — |
| P14 | DEMONSTRATED | med | CONFIRM | — |
| P15 | DEMONSTRATED | low | CONFIRM | — |
| P16 | DEMONSTRATED | low | CONFIRM | — |
| P17 | DEMONSTRATED | **high** | CONFIRM | — (off-by-one line cite, see notes) |
| P18 | DEMONSTRATED | med | CONFIRM | — (off-by-one line cite, see notes) |
| P19 | DEMONSTRATED | med | CONFIRM | — |
| P20 | DEMONSTRATED | med | CONFIRM | — |
| P21 | DEMONSTRATED | med | CONFIRM | — |
| P22 | DEMONSTRATED | med | CONFIRM | — |
| P23 | DEMONSTRATED | med | CONFIRM | — |
| P24 | DEMONSTRATED | med | CONFIRM | — |
| P25 | DEMONSTRATED | low | CONFIRM | — |
| P26 | DEMONSTRATED | med | CONFIRM | — |
| P27 | DEMONSTRATED | low | CONFIRM | — |
| P28 | DEMONSTRATED | low | CONFIRM | — |
| P29 | DEMONSTRATED | low | CONFIRM | — |
| P30 | DEMONSTRATED | med | CONFIRM | — |
| P31 | DEMONSTRATED | low | CONFIRM | — |
| P32 | DEMONSTRATED | low | CONFIRM | — |
| P33 | DEMONSTRATED | low | CONFIRM | — |
| Dialog table #33 (file_menu_button PopupMenuButton) | (table entry, not a P-finding) | — | **REFUTE** | n/a |
| C1 | DEMONSTRATED | **high** | CONFIRM | — |
| C2 | DEMONSTRATED | **high** | CONFIRM | — |
| C3 | DEMONSTRATED | **high** | CONFIRM | — |
| C4 | SUSPECTED | **high** | CONFIRM | — |
| C5 | DEMONSTRATED(code)/SUSPECTED(timing) | **high** | CONFIRM | — |
| C6 | DEMONSTRATED | med-high | CONFIRM | — |
| C7 | DEMONSTRATED | med-high | CONFIRM | — |
| C8 | DEMONSTRATED | med | CONFIRM | — |
| C9 | DEMONSTRATED | med | CONFIRM | — |
| C10 | DEMONSTRATED | med | CONFIRM | — |
| C11 | DEMONSTRATED | low-med | CONFIRM | — |
| C14 | DEMONSTRATED | low | CONFIRM | — |
| C15 | DEMONSTRATED | low-med | CONFIRM | — |
| C16 | DEMONSTRATED | low | CONFIRM | — |
| C17 | DEMONSTRATED | med | CONFIRM | — |
| R1 (4 orphaned api fns) | dead/flag-only | n/a | CONFIRM | — |
| R11 (cupertino_icons removal) | dead/recommend-remove | n/a | CONFIRM | — |

## Per-item reasoning

### File 1 — Tools

**T1–T13** (T9 excluded, SUSPECTED+low): all CONFIRMED by direct read of the cited code.
Highlights: T1's `piano_roll.dart:1693-1709` duplicate branch does append an identical `copyWith`
with a fresh id and no offset — confirmed by reading the exact block. T4's claim that Cmd/Ctrl maps
to Duplicate everywhere (not Slice) is confirmed at `tool_mode_resolver.dart:34-40`
(`getOverrideToolMode`), and the tooltip text `'Slice (B) • Cmd+Click'` is exactly as quoted at
`editor_panel.dart:675`. T7's two `SingleActivator(keyE, meta: true)` bindings are both present,
verbatim, in `daw_menu_bar.dart`. T8's ⌘B collision is real: `daw_screen.dart:3591` binds keyB to
`_bounceMidiToAudio`, and `piano_roll.dart` binds the identical combo (comment: "FL Studio style")
to `duplicateSelectedNotes()`. T10 is fully confirmed and is one of the cleaner findings in the
whole set: I grepped all six named `NoteGestureHandlerMixin` functions
(`handleTapDown`, `findNoteAtPosition`, `getEdgeAtPosition`, `startErasing`, `eraseNotesAt`,
`stopErasing`) across `ui/lib` and found zero callers anywhere outside their own declaration file —
genuinely dead, exactly as described. T11's `_duplicateSelectedClip` reads only
`currentEditingClip`/`selectedAudioClip` (both singular), confirmed. T12's three `Log.d('[AutomationLane] ERASER: ...')` calls are present at the cited lines, including the miss-path one.
Residual uncertainty: none material. The "caveat I did not close" that T4 itself flags
(`tempModeOverride` staleness making the dead Cmd+click-slice branch "intermittently alive") is a
real open question the original reader already surfaced honestly; I did not resolve it either
(requires a live app), so it stays as noted, not escalated.

### File 2 — Panels

**P1–P33** (P10, P34 excluded, SUSPECTED+low): all CONFIRMED. I read the master/return band
reservation code directly (`timeline_view.dart` ~965-1005) and confirmed the `else SizedBox(height:
...)` fallback that keeps a blank band when a section is hidden (P2). I read
`ui_layout_state.dart:115-150` and confirmed `mixerHardMax = 500.0` (P9) and `resetLayout()`'s fixed
`380.0`/`250.0` values vs. the percentage-based first-launch path (P5). I confirmed the
`hasInitializedPanelSizes` guard in `daw_screen.dart` never re-fires after first launch (P4). I
independently recomputed the laptop pixel budget from first principles (transport reserve, editor
default-height formula, ruler/master-band subtraction) and landed on ~6.3 visible tracks at 100px —
consistent with the report's 6.13/6, and `pixelsPerNote = 16.0` at `piano_roll_state.dart:22`
confirms the 1.3-octave arithmetic (252px / 16 ≈ 15.75 semitones ≈ 1.3 octaves) (P3). I confirmed
P7's exact "Not enough room - do nothing" comment text at two sites, P8's dead-mixin-toggle claim by
distinguishing qualified (`uiLayout.toggleMixer()`, a different class, genuinely called) from bare
(`toggleMixer()`, the mixin's version, never called anywhere) — this distinction matters and the
report got it right. P12's bounce dialog text ("Coming soon in a future update") is verbatim. P13's
"never rendered" claim survived a deeper check than the original: `onEditPluginsPressed` IS
threaded through `track_mixer_panel.dart:1407` into `TrackMixerStrip`'s constructor, but
`TrackMixerStrip`'s own `build()` never reads `widget.onEditPluginsPressed` (zero hits) — so the
callback genuinely has no UI trigger, confirming "unreachable" rather than refuting it. P17/P18
(icon collisions) confirmed exactly in substance — `'volume': BI.speakerHigh`,
`if (lowerType == 'audio') return 'volume'`, `if (lowerType == 'master') return 'headphones'`, and
`BI.headphones` used for both Solo and Master are all real — but the cited line numbers are
consistently off by one (report says `:22/:24/:70/:82`; actual is `:23/:25/:69/:81`), likely a
different snapshot of the file at read time. Doesn't change the verdict; noting per the brief's
"wrong file:line" check. P20's pan-knob claim (arc/label gated on `pan.abs() > 0.02`, only
`onVerticalDrag*`/`onDoubleTap`, no `onTap`, no `Tooltip`) is confirmed in full — I read the whole
gesture-handler block and found no tap handler at all. P21's FX button is confirmed bare (`Icon`
inside a `Stack`, no `Container`/decoration, no tooltip, "+" only rendered `if (_fxHovered)`). P23's
collapsed mute/solo dots are confirmed non-interactive (plain `Container`s, no `GestureDetector`)
and Arm is confirmed absent from that variant. P26's chip-suppression mechanism (fixedWidth +
inputChipWidth + minInfoWidth gate) is confirmed structurally present, though I did not re-derive
the exact "≈292px" arithmetic to the pixel — the mechanism and conclusion (chip disappears at
narrow widths, no fallback) are real. R16-adjacent P-items and the remaining P-series items (P11,
P14-P16, P19, P22, P24, P25, P27-P33) I spot-checked at a lighter grep-and-read level; each cited
file:line contained the described code with no discrepancy.

**One REFUTE**, not against a numbered P-finding but against a row in file 2's Dialog & Floating
Inventory table (§2, item #33): `file_menu_button.dart:156 → PopupMenuButton → material →
Backlog-known`. I verified there are **zero** `PopupMenuButton(` constructs anywhere in `ui/lib`
(matches file 4's own R9, which flags this same staleness independently). `file_menu_button.dart:156`
actually calls a private `_showMenu(context)` (line 49), which itself calls `showBoojyMenu<String>`
(line 64) — the correct, migrated pattern, not a raw Material popup. This is Reader 2 repeating a
stale BACKLOG claim without re-verifying it, one table row out of 33; it does not affect the report's
"12 acceptable / 2 should-not-exist / 3 should-be-panels / 7 should-be-inline / 9 correct-anchored"
tally in any severity-relevant way (it just moves one row from "material" to "correct anchored"),
and Reader 2's own qualitative note ("showBoojyMenu is used in 9 places") is itself an undercount —
I found `showBoojyMenu<...>(` at 18+ call sites across 11 files — but this is a rough prose aside,
not a numbered finding, so I flag it here rather than in the table.

### File 3 — Correctness (the crash/crackle hypotheses)

**C1** — CONFIRM, HIGH, DEMONSTRATED. I read the full stopped-path branch in `renderer.rs` (lines
~601-780). It has genuinely been hardened for **lock acquisition** (synth/effect managers are
locked once per buffer via try-lock-then-count, exactly matching the in-code comment that
explicitly says "(C1)" — that comment refers to a *previously fixed* lock-per-sample bug, a
different defect that happens to share the label). But the per-sample loop (`for frame_idx in
0..frames`) still calls `process_effect_chain` (not `process_effect_chain_block`) once per sample
per track — I read both functions side by side. `process_effect_chain` calls
`effect.process_frame()`, which for VST3 (`vst3_host.rs:850-867`) allocates two `Vec<f32>` and does
`vst3_process_audio` with `numSamples=1`, per sample. The playing path (verified at
`renderer.rs:~1130-1240`) uses `process_effect_chain_block` exclusively. The asymmetry is real and
exactly as described.

**C2** — CONFIRM, HIGH, DEMONSTRATED. `recorder.rs:655-657`'s `recorded_samples.push()` uses a
**blocking** `self.recorded_samples.lock()`, not the try-lock pattern used for `state`/`tempo`/
`time_signature` in the same file (I read `process_frame`, lines 476-514, and confirmed the
try-lock-then-count pattern is used there but not for the sample push). `grep -n
'with_capacity|reserve' engine/src/recorder.rs` finds nothing for `recorded_samples` — confirmed
no capacity reservation exists anywhere.

**C3** — CONFIRM, HIGH, DEMONSTRATED. `api/vst3.rs:20-22` takes `graph`, `track_manager`, and
`effect_manager` locks, then (still holding all three, per the code I read) calls
`VST3Effect::new(...)` and `.initialize()` — both of which do disk I/O and plugin activation. I
compared this against the restore path (`audio_graph/project.rs`, ~lines 674-712), which loads and
initializes the plugin *before* taking `effect_manager` only briefly for `create_effect` — confirming
the asymmetry the finding describes.

**C4** — CONFIRM (kept SUSPECTED, HIGH). This is architectural and can't be fully closed without
launching, but the evidence is stronger than the original report even states. I confirmed: (1) the
Dart-side calls (`vst3OpenEditor`, `vst3AttachEditor`, `vst3CloseEditor` etc. in
`vst3_editor_service_native.dart`) are direct synchronous `dart:ffi` calls, not routed through a
`MethodChannel` (which *would* hop to the platform/main thread) — only the higher-level
`openFloatingWindow` uses a channel. (2) Flutter's engine architecture runs the Dart "UI" task
runner (where all Dart code, including FFI calls, executes) on a thread separate from the
"Platform" task runner (the actual AppKit main thread) by default on desktop, with no thread-merging
config present in this app's `AppDelegate`/`MainFlutterWindow` (grepped, found none). (3) I read
`vst3_open_editor`, `vst3_close_editor`, and `vst3_attach_editor` in full in `vst3_host.cpp` and
confirmed **none** of them contains any `NSThread`/`pthread_main_np` check — only
`vst3_resize_nsview` and `vst3_set_nsview_bounds` in the separate `.mm` file are guarded (and I
confirmed those are the *only two* Cocoa entry points in that file, so the report's "only two"
claim is accurate, not an undercount). This is exactly the asymmetry the finding describes, and the
architecture strongly supports the hypothesis being correct rather than a false alarm.

**C5** — CONFIRM (kept DEMONSTRATED-code/SUSPECTED-timing, HIGH). Confirmed `Unmanaged.passUnretained(hostView).toOpaque()` at `VST3PlatformView.swift:137`, confirmed `instance->parent_window = parent` stores the raw pointer indefinitely in `vst3_host.cpp`, confirmed `PlugFrame::resizeView`
calls `vst3_resize_nsview` with that stored pointer, and confirmed the Swift view can be torn down
via `detachEditor()`/`deinit` while a queued `dispatch_async` block still holds the raw pointer by
value. The mechanism is real; whether it fires in practice depends on timing I can't reproduce
read-only, matching the original tier split exactly.

**C6** — CONFIRM, MED-HIGH, DEMONSTRATED. Read `project.rs:24-33`: synth, track, *and* effect
managers are all locked for the entire save traversal, and `vst3.get_state()` (which calls into
`getState()` on both component and controller, doing real serialization work) runs at line ~203
while still holding `effect_manager`. Confirmed the auto-save timer (`auto_save_service.dart:63`,
`Timer.periodic`) makes this recur unprompted.

**C7** — CONFIRM, MED-HIGH, DEMONSTRATED. Confirmed no transport-stop call exists in
`export_to_wav` or `export_wav_with_options` (`api/project.rs:218,360`) — the only `graph.stop()` in
that file is inside the unrelated `load_project` function (line 101). Confirmed `render_offline`
(`offline.rs`) and the live renderer share the *same* `self.effect_manager: Arc<Mutex<EffectManager>>`
field on `AudioGraph` (verified in `audio_graph/mod.rs:177`), so export and live playback do run
through the same effect instances. Confirmed the global `set_builtin_sample_rate` retune at
`offline.rs:192-196`.

**C8** — CONFIRM. `vst3_set_parameter_value` (`vst3_host.cpp:1073-1080`) calls only
`controller->setParamNormalized`. Grepped every write to `instance->param_changes` (the queue that
actually feeds `ProcessData::inputParameterChanges`) and found exactly the two sites the report
names (MIDI-CC path, program-change path) — `vst3_set_parameter_value` is not one of them.

**C9** — CONFIRM. Confirmed the restore loop in `project.rs` skips `effect_type == "vst3"` entries
and VST3 plugins are appended afterward from a separate list, with no persisted-order mechanism.

**C10** — CONFIRM. Confirmed `restart_audio_stream` has exactly the two call sites named
(`set_buffer_size`, `set_output_device`) and the cpal error callback (`renderer.rs:~1349`) only
stores a string and `eprintln!`s — no automatic recovery path.

**C11** — CONFIRM. Confirmed `eprintln!("VST3 processing error: {e}")` at
`vst3_host.rs:864`, inside `process_block`, which is on the render-callback call path.

**C14** — CONFIRM. `processContext` is assigned exactly once in the whole file, to `nullptr`.

**C15** — CONFIRM. Read `vst3_close_editor` in full: `removed()` is called only inside the
`if (instance->parent_window)` branch; the `editor_view = nullptr` release happens unconditionally,
confirming the partial-attach gap.

**C16** — CONFIRM. Confirmed `refCount_` is `std::atomic<uint32>` while the adjacent
`resizeRecursionGuard_` is a plain `bool`, in the same class.

**C17** — CONFIRM. Read the per-callback snapshot-construction loop directly: `audio_clips.clone()`
and `midi_clips.clone()` happen inside the per-track, per-callback loop, with no `Arc` wrapping.

**Architecture note (69 twin pairs / 44 dead mixin copies)** — CONFIRM, independently re-derived.
I wrote a regex-based extractor over `daw_screen.dart` (private `_foo` method signatures) and every
file in `daw/mixins/*.dart` (public `foo` signatures) and computed the name-intersection
independently of the report: **69 exact matches**, matching the report's count to the digit. I then
spot-verified the two "diverged" flagship examples by hand: `saveNewVersion()` (mixin,
`daw_project_mixin.dart:403`) has zero callers anywhere in `ui/lib` outside its own file — confirmed
via grep — while `_saveNewVersion()` (`daw_screen.dart:2527`) is wired at two call sites, and the two
bodies do materially different things (mixin version skips the version-directory/Samples-symlink
work). `onMidiFileDroppedOnEmpty`'s signature divergence (1 param in the mixin vs. 2 in
`daw_screen.dart`) is also confirmed by direct read. For the "44 dead" sub-count I sampled 10 of the
69 twin names by hand (distinguishing qualified calls like `uiLayout.toggleMixer()` — a different
class — from bare calls to the mixin method) and found 7/10 genuinely dead, 3/10 live via the
`_foo() => foo();` delegate pattern the report describes — consistent with, though not an exact
digit-for-digit reproduction of, the reported 44/69 (≈64%) split.

### File 4 — Repo health, delete/keep recommendations

**R11 (cupertino_icons removal)** — CONFIRM. `grep -rn "CupertinoIcons\|cupertino_icons"
ui/lib` returns zero hits. Safe, trivial removal exactly as stated.

**R1 (4 orphaned api functions, flagged not deleted)** — CONFIRM. Verified each of
`get_midi_clip_events`, `remove_midi_event`, `start_audio_input`, `stop_audio_input` has exactly one
hit in `engine/src` (the `pub use` re-export in `api/mod.rs`) and zero hits in `engine/src/ffi/` or
anywhere in `ui/lib`. The report correctly declines to recommend unilateral deletion; I have nothing
to add against that judgment call.

**Other file-4 counts re-measured**: fontSize — 370 total `fontSize:` usages, 185 followed directly
by a numeric literal, 148 by a `BT.*` token (185+148=333; the remaining 37 are local variables/
widget parameters) — matches the report's "185 literal / 370 total" claim exactly, confirming its
correction of BACKLOG's stale "228" figure. `VersionManager` — zero hits in `ui/lib`, confirmed
fully deleted. `split_button.dart`/`piano_roll_toolbar.dart` — confirmed absent at the cited paths.
R16 (Windows CI gap) — read the full `flutter-checks-windows` job in `.github/workflows/ci.yml`:
confirmed no `needs:` dependency, no engine build step, and `flutter test` with no
`--dart-define=BOOJY_CI=true`, exactly as described, in contrast to the macOS job which does both.

## Residual uncertainty, overall

The two things that can't be closed without launching the app (as both original readers already
say): (1) whether ⌘E actually dispatches to Edit-menu "Split at Marker" or View-menu "Show Editor
Panel" on macOS when both share the same `SingleActivator` (T7); (2) whether VST3 editor/controller
calls are actually observed off the main thread at runtime (C4) — the architecture and code-level
asymmetry strongly support it, but Reader 3's own suggested one-line `pthread_main_np()` instrumentation
is the fastest way to convert this from SUSPECTED to REPRODUCED. Neither of these should be
downgraded on the strength of that gap; both tiers were already conservatively set by the original
readers.
