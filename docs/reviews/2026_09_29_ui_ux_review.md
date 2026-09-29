# Boojy Audio: UI/UX Review and Design Direction

**Date:** 2026-09-29
**Build under review:** `master` at `8a04829`. The start screen and Settings show v0.6.0.
**Scope:** UI/UX only. That covers the visual language, interaction, consistency, readiness for every input method, and a comparison with GarageBand, Ableton Live, FL Studio and Logic Pro. **Out of scope:** how the audio engine sounds, and the five-tool row. Its problems are known and are being replaced by the B+ model in `docs/EDITING.md`, so they are not reported here.

**How this was produced:**
- Eight area readers went over the Flutter UI: theme, top bar, transport and time, piano roll, timeline, mixer, effects and devices, chrome and settings.
- Four DAW teardowns were written from working knowledge. Nothing was re-verified live.
- The synthesis read `docs/BACKLOG.md` and `docs/EDITING.md` first.

**Grounding:**
- All nine staged screenshots in `docs/reviews/_screenshots/` were read, across the readers and the synthesis. They were taken at UI Scale 110% ("Comfortable") and at about 2048pt wide. Nothing about narrow-window behaviour is grounded visually; that comes from code and computed thresholds.
- The synthesis checked five findings against the code: U1, U2, U3, U4 and U29, plus the tempo fallback. Those are marked **✓code**.
- Findings seen in a screenshot are marked **◎shot**.
- Everything else was read from code by a reader. Under BACKLOG process step 4 it stays a **candidate until a failing test reproduces it**.

---

## 1. Verdict

The screenshots show an app that is already calm at first glance: one dark Gunmetal ramp, one blue accent, Inter and JetBrains Mono, a restrained arrangement and a device chain with a sound skeleton. But it is not yet an instrument you can trust, and not one you could use without a mouse.

The gap to 8/10 is not visual polish. Three things hold it back:
- **Controls that don't do what they show.** The toolbar's Snap has no effect on the arrangement. The volume fader jumps when you grab it. A new project inherits the last project's 254 BPM. VST3 effects look to be silently dropped from the chain.
- **Actions that live only on hover, double-click, drag or right-click.**
- **Colour words that mean three things at once.** Amber is used for loop, warning and pan.

Most of the fixes are small and sit on a handful of shared primitives: a tap target, a readout popover, a `⋯` menu, a dialog shell and semantic colour tokens. That is why the scores below are low while the effort is moderate.

**Proposed starting scores.** 8 means good to great compared with other DAWs. No grades are carried over from earlier reviews. BACKLOG says scores are set by Tyr and Claude together from using the app, so treat these as the review's opening bid, to confirm in a walkthrough.

| # | Area | Score | Why, in one line |
| --- | --- | --- | --- |
| 3 | Arranging & clip editing | **5.0** | Clip overlap is fixed. But Snap doesn't reach the arrangement, audio trims don't snap, "1 bar" assumes 4/4, the drag-create ghost drifts when you scroll, and tempo edits flood the undo history. The five-tool row is known and not counted twice. |
| 4 | Piano roll & MIDI | **5.0** | Quantize, Legato and Velocity exist and edits undo cleanly. But labels are hard to read on the pale notes, there's no sense of where C is, Scale is C major only, zoom is hidden, and same-pitch notes can stack invisibly. |
| 6 | Mixing & automation | **4.5** | The fader jumps on grab. There's no unity mark, and clipping looks the same as loud. Sends, duplicate and delete are right-click only. "Change Color" on a return does nothing. The automation grid assumes 4/4. |
| 7 | Effects & plugins *(UI half only; sound not judged)* | **5.0** | VST3 effects look to be dropped by a parser mismatch. Duplicate loses its settings. The synth scrolls inside the chain. Controls come in three languages. |
| 9 | Projects & export *(UI half only)* | **5.5** | Auto-save and recovery exist. But Save As renames before you pick a folder, there's no unsaved-changes signal, and New Project keeps the old tempo. |
| 10 | First run & learnability | **4.5** | The empty project leads with a drag. The two main menus look like plain text. Readouts hide their gestures in tooltips. Settings hides four of its six sections. |
| 11 | Look & feel | **6.0** | Calm and coherent at a glance. Up close it's a collage: an amber loop band, traffic-light transport at rest, five dialog styles, three knob styles, and 185 hard-coded font sizes. |
| 12 | Input & accessibility | **3.5** | Hit areas are 12–24px throughout. Many actions are right-click or hover only. There's no keyboard focus in dropdowns. Muted text is at 2.7–3.5:1 contrast and there's 9px text. |

---

## 2. Core diagnosis: why it doesn't yet feel like a calm, precise instrument

Six root causes sit under almost all of the roughly 110 findings.

1. **Actions are hidden behind gestures.** Before EDITING.md there was no rule that every action needs a visible, plain-tap path. So the app grew these:
   - readouts that scrub, cycle or type depending on drag, click or double-click;
   - clip, strip, device and recent-project menus that open only on right-click;
   - trim handles you find only by the cursor changing;
   - two top-bar menus with no caret.

   This single cause drags down rows 10 and 12 together.
2. **The tap area is the drawn area.** No shared tap-target primitive exists. Every family (bar buttons, M/S/R, knobs, send ×, float icon, dropdown chips, note edges, clip handles) hand-sizes its own 12–24px target. EDITING.md rule 2 has nothing to build on yet.
3. **The tokens aren't the source of truth.**
   - Colour meanings overlap: amber is loop, warning and pan; there are six ambers and four reds; and hard-coded white is used for "active".
   - The type scale (9/11/13/15/20) doesn't match what the UI uses, which is 10 and 12, so 185 literals bypass it.
   - Three kinds of shared surface each exist in several versions: five dialog styles, three knob styles, two tooltip styles.

   That's what makes the top bar and chrome read as a collage up close.
4. **Controls that don't tell the truth.** These break the settled "inert controls work or are hidden" decision and cost more trust than any visual flaw:
   - Snap does nothing in the arrangement.
   - Return "Change Color" is a no-op.
   - No Input and No Output are never applied.
   - UI Scale promises "text and controls" but scales text only.
   - The Settings sidebar highlights a section you can't see.
   - "Unsaved changes will be lost" appears after a save.
   - Effect Duplicate doesn't copy the effect.
   - An empty tempo field becomes 120.
5. **Precision controls give no precise feedback.**
   - The fader maps the pointer, not the thumb.
   - Meter and fader use different scales.
   - There's no unity detent and no clip latch.
   - Envelope and delay-time controls are linear.
   - ArcKnob has no reset.
   - The tempo drag rounds 120.5 down to 120.

   A beginner can't hit "back to where it was", and that is exactly what "precise" means.
6. **Loud when healthy, silent when at risk.** This is the opposite of the product's rule.
   - Loud at rest: the transport shows green, orange and red rings; the loop band is permanently amber; every save pops "Project saved"; the device meter turns amber at −12 dB.
   - Silent at risk: there's no dirty indicator, and clipping looks the same as loud.

---

## 3. Bug and inconsistency ledger

The raw findings were deduplicated, with about 20 merged, and a few new ones added from the screenshots. IDs are U1 to U112. The row numbers refer to the BACKLOG scorecard.

### Quick wins (high or medium impact, effort ≤ S)

| ID | What | Rows |
| --- | --- | --- |
| U2 | New project keeps the previous tempo and time signature (254 BPM on "Untitled") | 9, 10 |
| U3 | Fader jumps when grabbed | 6 |
| U5 | Save As renames even when the folder picker is cancelled | 9 |
| U7 | Playing playhead and selected-strip border are hard-coded white and vanish in the Light theme | 11 |
| U8 | Loop region painted in the warning amber | 11 |
| U9 | Muted text fails contrast | 11, 12 |
| U10 | Drag-to-create ghost offset by the scroll amount | 3 |
| U12 | Note label and selection contrast | 4 |
| U15 | Carets on the wordmark and project-name menus | 10, 12 |
| U29 | Tempo dialog turns empty input into 120 | 3 |
| U30 | Tempo scroll and tap-tempo: one undo step per burst | 3 |
| U31 | Return to start (Home) | 10 |
| U35 | Snap button shows the actual grid size | 4 |
| U38 | Audio trim snaps like MIDI trim | 3 |
| U46 | Keep track colour when a track is selected | 6, 11 |
| U50 | M/S/R columns stop shifting when a track is armed | 6 |
| U51 | Hide the dead "Change Color" on returns | 6 |
| U59 | Effect Duplicate copies the settings | 7 |
| U66 | Apply No Input and No Output; hide the one-item driver dropdown | 2, 10 |
| U79 | Windows minimum window size | 13 |
| U111 | Drum-pad names truncated beside empty space | 10 |

Two items are worth an afternoon even though they are larger than S: **U1**, where hiding the Snap button is S and wiring it is M, and **U4**, writing the failing test for the VST3 parser.

<details>
<summary><b>Full ledger (112 items)</b>: id · effort · area · rows</summary>

**High severity**

- **U1** (M) [Arrangement, 3] **✓code** The transport Snap toggle and resolution ("Bar") don't affect arrangement snapping. `arrangementSnap*` is passed only to `TransportBar` (`daw_screen.dart:3047`). `TimelineState.getGridSnapResolution()` always derives the grid from zoom (`timeline_state.dart:395`). *Fix:* thread the Snap setting into `TimelineView`, where Auto uses the zoom grid, Off skips snapping, and fixed values are used as picked. Add a regression test for clip drag and trim. Until then, hide the button.
- **U2** (S) [Chrome/Transport, 9, 10] **✓code ◎shot** New Project keeps the previous tempo. Screenshots 01, 02 and 03 show a fresh "Untitled" at **254 BPM** while every recent project reads 120. `executeNewProject()` (`daw_project_mixin.dart:77-117`) clears tracks, undo, layout and automation, but never tempo, time signature or `projectMetadata`, and `ProjectManager.newProject()` only resets path and name. It's a candidate until a failing test confirms it. *Fix:* reset the engine tempo, time signature and metadata to defaults in the same function, and add a test.
- **U3** (S) [Mixer, 6] **✓code** The capsule fader sets volume from the absolute pointer position (`dx / maxWidth`, `capsule_fader.dart:50`) while the thumb is drawn at `r + v·(W−2r)`. Grabbing the thumb at unity jumps it about 1 dB, and a drag starting at the far right jumps to +6 dB. The device-strip fader has the same mismatch and also jumps on a tap (`device_strip.dart:198-217`). *Fix:* a relative drag with a grab offset, using the painter's own geometry. Test: press on the thumb, move 0px, and the value is unchanged.
- **U4** (M) [Devices, 7] **✓code** VST3 effects are likely dropped from the chain. The engine emits `type:vst3,bypassed:0,name:Foo,path:/x` (`effects.rs:208`), and `EffectData.fromInfo` calls `double.parse` on every other key, so `name:Foo` throws and the effect returns null and is skipped (`effect_data.dart:16-44`). The UI branches also test for `startsWith('vst3:')`, and Windows `C:` paths break the split. Not reproduced. *Fix:* write the failing test first, then parse name and path as strings and key the UI off `type == 'vst3'`.
- **U5** (S) [Chrome, 9] Save As applies the new name to the manager, title and metadata *before* the folder picker (`daw_project_mixin.dart:310`). Cancelling leaves the project renamed but unsaved. *Fix:* commit the name only after the save succeeds.
- **U6** (M) [Chrome, 9, 10] There's no dirty flag. `WindowTitleService.setUnsavedChanges` is dead code. New Project guesses using `currentPath != null || canUndo`, Close always warns (even straight after a save), and every save shows a "Project saved" SnackBar. *Fix:* a real dirty flag, a quiet dot beside the project name, confirm only when dirty with Save / Don't Save / Cancel, and toasts only on failure.
- **U7** (S) [Theme/Arrangement, 11] The playing playhead and the selected-strip border are `Colors.white` (`timeline_view.dart:1032`, `unified_nav_bar_painter.dart:325,377`, `track_mixer_strip.dart:1203,2192`, `piano_roll.dart:1207`), so they vanish on the Light theme. The `playhead` token (`app_colors.dart:201`) is unused. **◎shot** The Master strip shows selection in accent blue while tracks use white, so there are two selection colours. *Fix:* a theme-aware `playheadActive` token, one selection treatment, and a Light-theme golden test.
- **U8** (S) [Theme/Piano roll, 11] **◎shot** The loop range is `colors.warning` at 35% (`loop_bar_painter.dart:55`, `unified_nav_bar_painter.dart:97`). It shows as a muddy olive band and is the loudest colour in screenshots 03, 05 and 07. Amber also means pan-left (`pan_knob.dart:121`) and plugin error. *Fix:* a `loopRegion` token (a cool accent tint around 12–14% with a 2px underline), plus separate pan and warning tokens.
- **U9** (S) [Theme, 11, 12] **◎shot** Dark muted text `646880` is about 3.1:1 on `dark` and 2.7:1 on `elevated`; Light muted `707070` is 3.4–3.8:1. It carries the empty-state "or" and the 9px "Add an effect" hint. *Fix:* dark muted around `8A8FA3` and light around `5E5E5E`, verified at ≥4.5:1 on every surface. Reserve muted for decoration.
- **U10** (S) [Arrangement, 3] Both drag-to-create previews subtract `scrollOffset` (`clip_preview_builders.dart:833,878`), even though they are mounted in scrolling content space (the same bug was fixed in the box-select overlay). Past bar 1 the ghost sits left of the pointer while the clip lands in the right place. *Fix:* remove the subtraction and add a test with the view scrolled.
- **U11** (M) [Top bar/Transport, 10, 12] The three readouts have no plain-tap action:
  - Tempo types only on double-click.
  - Position cycles its format on click.
  - Signature has a resize cursor but a tap opens a menu.

  Scrub, nudge, fine-step and type are explained only in hover tooltips. Tap-tempo disappears below about 1010px, so at the 960px minimum it's unreachable. Hit areas are 22–24px. *Fix:* a tap on any readout opens a small popover with the field, ±, and Tap for tempo. Drag, scroll and Shift stay as accelerators, and the "BPM" caption stays at every width.
- **U12** (S) [Piano roll, 4] **◎shot** Note fill is forced to HSL lightness 0.45–0.72 while labels and the selection stroke are near-white, about 1.7:1 on pale green. In screenshot 05 you can barely tell the selected F4 apart. *Fix:* choose the ink colour from the fill's luminance, add a dark outer ring for selection, and skip labels on notes under about 12px tall.
- **U13** (M) [Piano roll, 4] The root band draws only when Scale is on, and Scale is locked to C major because the pickers were deleted on 2026-09-13 (already in BACKLOG). In any other key, Scale highlights the wrong home note. *Fix:* always draw a faint C-row tier, restore the root and Major/Minor pickers, and until then label the button "C major".
- **U14** (M) [Chrome, 10] **◎shot** Settings is one scroll view (`app_settings_dialog.dart:285-345`), and the sidebar only scrolls to a key when clicked. On open you see Appearance and half of Audio. The Buffer Size subtitle is cut off mid-sentence ("more load on") at the dialog's edge, and MIDI, Saving, Projects and Updates are unseen. *Fix:* real pages, one section at a time.
- **U15** (S) [Chrome/Top bar, 10, 12] The ▲udio wordmark (Settings, Shortcuts, Start screen) and "Untitled" (Save, Export, Rename, Project Settings, Close) are menus with no caret. On Windows the wordmark is the only way to reach Settings. *Fix:* a caret visible at rest on the project name, and a menu affordance on the wordmark.
- **U16** (M) [Devices, 5, 11] **◎shot** The synth panel scrolls inside the device chain, and ENVELOPE is cut off at the bottom in screenshot 08. That breaks the settled "no nested scrolling" rule. *Fix:* three columns (Osc | Filter | Env) or a compact knob grid, with the previews at about 48px.

**Medium severity**

*System and theme*
- **U17** (M) [11] Six near-identical ambers (`FFC107`, `EAB308`, `FACC15`, `FFA600`, `F59E0B`, `F97316`) and four reds. The transport shows saturated green, orange and red rings at rest, and in screenshot 08 Pause (amber) and Stop (orange) look almost the same. *Fix:* one amber, one red, one green; neutral Play and Stop at rest; Play green only while rolling; Record's red as the only warm accent.
- **U18** (S) [4, 11] Notes use a fixed mint colour computed in the model layer (`midi_note_data.dart:66`), and the CC lanes use Material 300 pastels outside the palette. *Fix:* `noteFill(velocity)` in the theme, derived from the track colour; CC lanes mapped onto `TrackColors.manualPalette`.
- **U19** (M) [11] The colour temperature drifts. Backgrounds are neutral, but text and shadows are left over from an indigo palette, so text looks lavender on grey. The Light theme's editor is blue-white on neutral grey. *Fix:* derive text and shadow from one hue, and add a palette test.
- **U20** (L) [11] 110 `Color(0x…)` literals and 37 `Colors.*` uses sit outside the palette. Dialog scrims use black at 0.4–0.5 alpha instead of `BT.dialogBarrierColor`. The piano-key colours ignore the existing `pianoWhiteKey` and `pianoBlackKey` tokens. *Fix:* route all of them through tokens, and add a grep check in CI.
- **U21** (M) [11, 12] UI Scale is a `textScaler` only. Icons, the 24px control heights and painter geometry stay fixed. The top bar's well widths were measured at 1.0, so at 1.2 the `ClipRect` silently trims controls, and the tempo number can overflow its fixed 34px box. *Fix:* either rename the setting "Text size" and exempt the fixed chrome, or scale control sizes from one `BT.scale`. Add density tests at 0.9 and 1.2.
- **U22** (L) [11] The type scale (9/11/13/15/20) has no 10 or 12 step. There are 185 `fontSize:` literals and about 390 raw `TextStyle(` calls against about 10 `BT.*` calls, and the doc example in `tokens.dart:11` is wrong. Font tokens are already in BACKLOG. *Fix:* rebase the scale to 10/12/13/15/20 with a 10px floor.
- **U23** (M) [12] No control anywhere has a tap area larger than what's drawn:
  - `BoojyButton` 22–24px
  - bar controls 24–30px
  - M/S/R and pan 14–22px
  - send × 12px
  - float icon 12px
  - dropdown chip about 26px, rows about 30px
  - clip handles 8px
  - note edges 9px

  *Fix:* one `TapTarget` primitive with an opaque hit box of at least 32px (44 on coarse pointers) that leaves the drawn control unchanged. Adopt it family by family.

*Top bar and transport*
- **U24** (M) [10, 11] The project name gets 56px below about a 1300px window (`transport_bar.dart:240-250`), so "My First Beat" becomes "My Fir…". *Fix:* let the transport drift up to about 60px off-centre before the name shrinks.
- **U25** (M) [11] Every control family has its own hover and press behaviour: scale 1.02 or 1.05 or none, three different fills, animated or not. Capture has no hover or press state at all. *Fix:* one `BarButtonSurface`; the scale value waits on Tyr's hover/motion sign-off.
- **U26** (S) [3, 10] The signature control:
  - It has a resize cursor, but a tap opens a stock `showMenu`.
  - The menu offers 2–7 while drag reaches 16, and Project Settings offers 1–12 over 2, 4, 8 and 16.
  - **◎shot** It's also settable in the piano-roll and audio-editor controls bars.

  That's four places with different ranges, and a saved 6/8 has no selectable entry in the transport. *Fix:* one range everywhere, `showBoojyMenu`, a click cursor, and "/4" dimmed. Check whether the editor-bar control is per-clip or the project value, and label it accordingly.
- **U27** (M) [11] The position readout resizes with its content. At bar 10 it grows by one character, time mode is wider, and "both" mode is two lines tall, so the tempo and signature boxes shift during playback. The density test covers bars mode only. *Fix:* a fixed width and height for the widest string in each mode, and tests for all three modes.
- **U28** (S) [10] Position editing:
  - Time mode shows `m:ss.mmm` but accepts only `[0-9.]` as raw seconds.
  - Bars mode rejects `3.2.1` silently.
  - The field cancels on blur, and the 80px edit box shifts its neighbours.

  *Fix:* parse the format that's displayed, commit on blur, Esc to cancel, show a visible error, and keep the box the same width.
- **U29** (S) [3] **✓code** The tempo dialog commits `double.tryParse(...) ?? 120.0` (`tempo_controls.dart:125,137`), so clearing the field and pressing OK sets 120 BPM. It's also a stock AlertDialog. *Fix:* keep the current tempo and show an inline error; fold it into the U11 popover.
- **U30** (S) [3] Each scroll notch and each tap-tempo tap is its own `SetTempoCommand` (`daw_screen.dart:808-825`), so 30 notches make 30 undo steps. *Fix:* treat a burst as one gesture (500ms of quiet, or the tap window).
- **U31** (S) [10] There's no return to start: no button, no Home key, no menu item (grep found none). *Fix:* Home and a menu item, plus a second press of Stop when already stopped.

*Piano roll*
- **U32** (S) [4] Black and white lanes differ by about 1.2:1 in the dark theme, and the hairlines match the lane colour. In the Light theme, the 35% black makes a heavy stripe. *Fix:* per-theme lane tokens at about 1.35:1, and a distinct tier for sub-lines.
- **U33** (S) [4] The edge-resize zone is a fixed 9px on each side, so a 1/16 note (20px) leaves about 2px to move it, and anything under 18px can't be moved at all. There's no visible handle. *Fix:* `min(9, width/3)`, and a grip drawn on selected notes.
- **U34** (M) [4, 12] Zoom:
  - Cmd+wheel scrolls in the piano roll but zooms in the arrangement.
  - There's no pinch, no +/−, and no fit.
  - Height zoom is a hidden horizontal drag in the key gutter.

  *Fix:* fold into the BACKLOG Zoom spec (one spec, one PR).
- **U35** (S) [4] In adaptive mode the Snap button reads just "Snap", so the grid can change size with zoom and nobody can tell. *Fix:* "Snap 1/16" as a quiet suffix; "Auto" goes in the dropdown.
- **U36** (M) [4] Moving or resizing a note onto another of the same pitch leaves both stacked, with one hidden and two note-ons played. This survives the editing-model change. *Fix:* trim or merge inside the same undo command, and add a regression test.
- **U37** (S) [4, 11] **◎shot** The key gutter is the brightest element on screen. It uses fixed greys that ignore the theme, labels every row at 8px, and ignores text scale. *Fix:* label C only (10–11px, with octave number) plus the hovered or selected row, tone the naturals down, and shorten the black keys.

*Arrangement*
- **U38** (S) [3] Audio trims clamp but never snap (`timeline_gesture_layer.dart:1111-1135, 1253-1274`), while MIDI trims do. *Fix:* snap the trimmed edge in beats, respecting Alt and U1.
- **U39** (M) [3, 6] "One bar" is hard-coded as 4 beats in several places:
  - drag labels (`clip_preview_builders.dart:838,894`)
  - the minimum drag length
  - the double-click clip length
  - bar snap
  - the automation lane (`timeline_track_list.dart:642`, `beatsPerBar: 4`)

  *Fix:* one `barLengthBeats` helper from the project signature, with tests.
- **U40** (M) [3, 12] Clip trim strips are 8px, opaque and invisible. On clips under 16px they cover the whole clip, so it can't be moved. *Fix:* `min(8, w/3)` drawn, a larger hit area, and a faint edge grip on the selected clip.
- **U41** (M) [3, 12] The clip menu (split, rename, colour, mute, loop, copy) is right-click only. *Fix:* long-press, and make sure the B+ action bar's `⋯` carries mute, loop, rename and colour.
- **U42** (S) [10] Empty lanes show no hint, and double-click on an audio lane does nothing. *Fix:* "Double-click to add a clip" and "Drop or record audio here", which the EDITING.md hints already plan.
- **U43** (S) [3, 11] **◎shot** Clip bodies are transparent, so the grid runs through notes and waveforms, and the audio clip in screenshot 08 reads as an outline. *Fix:* a body at 12–18% of the track colour.
- **U44** (S) [3, 11] **◎shot** Clip headers:
  - They use 10px white text on saturated headers.
  - Audio headers print raw file names ("Cymatics - Cobra Flute Loop 1 - 108 BPM D Min.wav").
  - MIDI headers repeat the track name.

  *Fix:* one header style at 11–12px, ink colour chosen by luminance, the file extension stripped, and the label skipped when it equals the track name.
- **U45** (S) [10] **◎shot** The empty project:
  - The prompt leads with "Drag an instrument…".
  - The buttons read "+ MIDI" and "+ Audio", which is jargon.
  - The "or" is almost invisible, and grid lines run through the text.
  - With **no tracks**, the bottom editor still shows an "Instrument" tab and an "Add an effect" tile for a track that doesn't exist.

  *Fix:* click-first wording, a soft card behind the prompt, and the editor collapsed or showing its own hint until something is selected.

*Mixer (track strips)*
- **U46** (S) [6, 11] **◎shot** Selecting a track swaps its colour border for white. Audio tracks default to slate grey, which reads as "unassigned". *Fix:* keep the colour and show selection as an inner ring plus a lift; give audio tracks a palette hue by default.
- **U47** (M) [6, 10] The "Mixer" panel is actually the only place track names, M/S/R and add-track live. Hide it and the lanes become anonymous (screenshot 03), and its visibility persists. *Fix:* rename it "Tracks", and add a slim name-and-colour label in each lane. This feeds the open mixer-header decision (brief §6).
- **U48** (M) [6, 12] Duplicate, Delete, Convert, Show Automation, "Send to…" and master rename are right-click only, and master uses a different callback. *Fix:* a `⋯` button on strips, long-press, and one gesture for master.
- **U49** (M) [6] The meter maps −60…0 dB across the whole capsule while the fader puts 0 dB at 70%. The thumb covers the meter tip, there's no unity mark or detent, and anything over 0 dBFS is clamped, so clipping looks like loud. *Fix:* a unity tick (parked in BACKLOG), a detent of about 1–2 dB, and a latched red end-cap that clears on click. That's a clip cue, not the rejected peak-hold.
- **U50** (S) [6] **◎shot** Arming an audio track adds a Monitor button, which slides M/S/R about 26px left (screenshot 08: track 3 against tracks 1–2). *Fix:* reserve the slot on every strip.
- **U51** (S) [6] The return strip shows "Change Color" but the choice is swallowed (`onColorChanged` is null). There's no FX button, and the identity is an 8px "RETURN" chip. *Fix:* hide or wire the colour option, add the FX button, and show the effect name.

*Devices*
- **U52** (L) [7, 11] There are three control languages: green Material sliders in the synth, ArcKnob, and MiniKnob. They differ in sensitivity (120 vs 150px), cursor, label placement and number format, and green competes with the blue accent. *Fix:* one ArcKnob everywhere, with sliders only where a long throw is genuinely better.
- **U53** (S) [5, 7] Attack, release, delay time and compressor timing are linear, so 5–50ms fits in about 2% of the travel. *Fix:* skew or log curves for time and frequency.
- **U54** (S) [7] ArcKnob has no reset even though each knob spec stores a default, and MiniKnob resets to the midpoint. *Fix:* double-tap resets to the stored default, and tapping the value lets you type (also the touch-safe path).
- **U55** (S) [7, 12] **◎shot** Knob labels, values and EQ axis labels are 9–10px in muted text. *Fix:* 11px labels and 12px values in `textSecondary`.
- **U56** (S) [7] A bypassed device is dimmed three times over (0.5 × 0.5 × 0.4), including the power dot needed to turn it back on, and its knobs can't be dragged. *Fix:* dim the body once, keep the header at full opacity, and keep knobs live.
- **U57** (M) [7, 12] The whole card is a 150ms `LongPressDraggable`, so a slow knob or EQ drag can pick up the device, and reorder has no handle. *Fix:* drag from the header or a grip only, plus Move left and Move right in the menu.
- **U58** (S) [7, 12] Remove, Duplicate and Reset are right-click or keyboard only. *Fix:* a `⋯` in the header and long-press.
- **U59** (S) [7] Duplicate calls `_addEffect(type)`, which creates a default effect at the end of the chain (`device_chain_view.dart:704-713`). *Fix:* copy the parameters and insert at index+1 as one undoable command.
- **U60** (M) [7] The "fixed MIX knob" (a settled decision) is just whichever knob happens to be last. EQ has "Out", and Limiter carries a rarely useful wet/dry. *Fix:* a pinned MIX slot in the device shell; the EQ uses the same slot labelled "Level".
- **U61** (M) [7] The compressor has no makeup gain (the engine exposes it) and no gain-reduction display, and shows 5 knobs in 190px. *Fix:* Amount + Makeup + pinned MIX, with attack and release under "More", plus a small GR bar.
- **U62** (M) [7, 11] The device meter turns amber at −12 dB, so a healthy mix sits in amber. Effect strips look like faders but are only meters. *Fix:* green to −6 dB, red above −1 dB or on clip; meter-only strips drawn flat.
- **U63** (M) [7] EQ:
  - "+ Add Band" lands on top of the existing 1 kHz band, so it can't be grabbed.
  - The hit radius is 12px and bands have no identity.
  - There are gridlines at 100, 1k and 10k only.
  - Focus is greyed ("Shelf") on the default band (screenshot 08).

  *Fix:* place new bands in the widest gap, prefer the selected band when hit-testing, number the bands, and hide Focus on shelves.

*Chrome and settings*
- **U64** (M) [11] There are five dialog styles plus about 15 stock `AlertDialog`s with Material 3 defaults (28px radius), and no `dialogTheme`. *Fix:* one `BoojyDialog` shell plus `dialogTheme` and `textButtonTheme`, then migrate.
- **U65** (S) [11] App Settings applies live and has an X; Project Settings uses Cancel and Save, where Save's contrast varies by theme. *Fix:* both live, with one "Done".
- **U66** (S) [2, 10] **◎shot**
  - On macOS the Audio Driver is a dropdown with one item, and an empty description still leaves a gap under it.
  - Choosing "No Input" or "No Output" is saved but never applied.
  - Input defaults to "No Input", which undercuts row 2 (recording) on first run.

  *Fix:* hide single-option rows, apply or remove the "No" choices, and default to the system input.
- **U67** (S) [10, 12] Remove and Reveal on a recent project are right-click only. *Fix:* a `⋯` on the card, long-press, and `showBoojyMenu`.
- **U68** (M) [12] `BoojyDropdown` is a bare `GestureDetector`: no focus, no semantics, no arrow keys, Enter or Esc, 11px text and 26–30px rows. It sits behind every setting. *Fix:* a focusable control with keyboard navigation, and larger rows on coarse pointers.
- **U69** (S) [11] Stock `showMenu` is used in **six** sites, not the two BACKLOG lists: `signature_dropdown.dart:86`, `project_card.dart:203`, `track_mixer_strip.dart:1391,2035`, `audio_editor_controls_bar.dart:316`, `piano_roll_clip_automation_lane.dart:342`. *Fix:* update the BACKLOG list and migrate.
- **U70** (M) [9] The project name is editable in Project Settings, Save As and Rename, and only Rename renames the folder, so the name and folder drift apart. *Fix:* one rename path.
- **U111** (S) [10] **◎shot** The drum-kit editor truncates pad names to 3–6 characters ("808 Ki…", "Electr…", "Close…") while about 300px sits empty to the right of the grid (screenshot 06). The per-pad slider and "0.0" have no label or unit. *Fix:* give the name column the spare width and label the slider "Vol" (dB).

**Low severity**

- **U71** (S) [11] UI Labs switchers still ship: the palette editor, canvas-bg variants, the playhead lab and four `TopBarVariant`s (already in BACKLOG; this is a reminder). *(Tyr picks.)*
- **U72** (S) [11] `ColorScheme.fromSeed` leaks M3 scrollbar, selection, focus and splash colours; popup and tooltip radii are off-token.
- **U73** (S) [11] `BoojyColors` is rebuilt on every `context.colors` access, so about 1,000 sites depend on the whole provider.
- **U74** (S) [10, 11] Capture MIDI: a 24px chip in the circle cluster, a "scan" glyph that reads as fullscreen, a pulse even when nothing was captured, and no hover state.
- **U75** (S) [11] Mixed icon families in one row: a raster PNG metronome (which reads as a tick), Material 14px and lucide 18px.
- **U76** (S) [11] Off-token literals in the left rail (14px name, radius 4, 10/6/2/6 gaps). Undo/redo and Library look like one group.
- **U77** (S) [10, 11] Play, Stop, Undo, Redo, the readouts and panel toggles use the plain Flutter tooltip; the rest use `BoojyTooltip`.
- **U78** (S) [10] A single click on the position readout silently cycles its format. A double-click flickers through the cycle and writes the setting twice.
- **U79** (S) [13] Windows has no minimum window size (macOS pins 960×600), and below about 740px the wells are clipped.
- **U80** (S) [3] The tempo drag rounds 120.5 to 120 on start; 0.5 BPM per pixel with no fine mode.
- **U81** (S) Pinned ruler readout: debug-only, a duplicate formatter that ignores the display mode, but its persisted variant is applied in release builds.
- **U82** (S) [10] "6.4.3" (bar.beat.sixteenth) isn't labelled. The ruler shows "6.4" and the piano roll shows "Length 4.0.0".
- **U83** (S) [3, 4] Add a note and drag it in one gesture, and it takes two undo steps, with `isSelected` stored in the snapshots. Candidate.
- **U84** (S) [4] Grid tiers are shown by weight (1, 1.5, 2.5px), and the hover-row accent wash stacks on the root band.
- **U85** (S) [4, 10] **◎shot** Controls-bar labels are dim, "Length 4.0.0" is jargon, and the signature box has a different weight from its neighbours.
- **U86** (S) [10] The empty piano roll has no hint. EDITING.md plans one; this is a reminder to build it with that work.
- **U87** (S) [3, 11] Ghost previews don't match real clips: an audio header of 20px against 18px, different padding and border, no notches, and success green for "creating".
- **U88** (S) [11] The timeline grid shows half-beats at about 12px spacing, and the painter draws the full content width.
- **U89** (S) [10, 11] **◎shot** When the master lane is hidden it still reserves an unlabelled band, which looks like a ghost track.
- **U90** (S) [3] A collapsed track (16px) is shorter than the clip header (18px), so the clip overflows.
- **U91** (S) [3] A drag-create shorter than a bar is silently discarded after a live "2.5 beats" preview.
- **U92** (S) [6] **◎shot** The pan ring and FX bolt nearly vanish at rest, and the bolt's "+" shows on hover only.
- **U93** (S) [6] M/S/R use icons at the standard height and letters when compact. The Solo headphones icon is also Master's identity icon.
- **U94** (S) [2, 6] **◎shot** The input chip always reads "In 1", and the short-name code is dead.
- **U95** (S) [6] Sends: a linear amplitude knob with a dB label, 9px muted value, and a 12px ×. There's no explicit way to add a return (parked).
- **U96** (S) [10] Four add-track entry points with jargon labels, three different audio glyphs, and a stale doc comment.
- **U97** (S) [6] A tap on the name, fader or pan may delay selection by the double-tap timeout. Candidate; needs a latency test.
- **U98** (M) [12] Strip reorder is a vertical drag inside a vertical scroll, and resize and collapse is a 6px strip that needs a double-click.
- **U99** (S) [6, 10] Delete Track and Delete Return ask "Are you sure?" even though both are undoable. *Fix:* delete, then show an Undo toast.
- **U100** (M) [7] **◎shot** Reverb, Delay, Chorus and Limiter have no visualiser. The Reverb card is about 435px tall with three 32px knobs.
- **U101** (S) [12] The float and embed icon is a 12px target (screenshot 09). Covered by U23.
- **U102** (S) [7] The EQ knob row uses a different label layout and case from ArcKnob, and Out sits apart from where MIX sits on other devices.
- **U103** (S) [7] Delay uses the metronome glyph, the Oscillator section reuses the EQ glyph, and Limiter uses a generic arrow.
- **U104** (M) [5] The sampler device card is a header and a strip with an empty body.
- **U105** (S) [9] The recovery dialog always says "Untitled", splits its sentence across two widgets, mixes case, and lives in `settings_dialog.dart`.
- **U106** (M) [10] **◎shot** Start screen: thumbnails are soft (captured at 0.25), times read "2w" and "3mo", the last row is clipped mid-card, non-`.audio` drops are ignored silently, and the track count is never saved.
- **U107** (S) [12] Start-screen actions aren't focusable and New Project isn't autofocused. Settings pops the launcher and then re-shows it.
- **U108** (M) [13] macOS chrome relies on hand-tuned insets measured at 1.0 while the default scale is 110%. Double-clicking the bar doesn't zoom the window.
- **U109** (S) [11] Leftover settings layouts: a 32px indent on Updates, a Bluetooth warning offset 100px, an inline auto-save sentence, and an ignored `fontSize` parameter.
- **U110** (S) [10] ⌘, opens Project Settings rather than app Settings. Menu shortcuts and ellipses are inconsistent.
- **U112** (S) [3, 10] **◎shot** The audio-editor controls bar shows dimmed "120 BPM" and "÷2 ×2" with no reason given (screenshot 07). *Fix:* explain why they're disabled, or hide them until they apply.

</details>

**Not reported, because they are known or decided:**
- the five-tool row and its cursors and keys;
- panel-toggle "no active state";
- peak-hold;
- the toolbar having no add-track or ? button;
- the hover-scale value (Tyr sign-off);
- the Zoom spec itself (U34 only feeds it);
- the top-bar overflow menu decision (U79 only notes the floor).

---

## 4. How Boojy compares to the four DAWs

The teardowns were written from memory of GarageBand 10.4+ and iPad, Live 11–12, FL 21–2024 and Logic 10.8–11, and aren't re-verified. Suggestions that clash with a settled decision have been dropped or reframed. Examples:
- Drummer and Session Player are excluded.
- A permanent info panel is excluded, so FL's hint line becomes consistent tooltips.
- The toolbar layout was settled on 2026-09-13, so "one merged LCD" becomes "make the three boxes behave as one".
- Vertical faders and effect collapse were already decided against.

### 4.1 Top bar and time readout

| DAW | Take from it | Avoid |
| --- | --- | --- |
| GarageBand | One place to look. Red means recording and nothing else. Bars by default, time one tap away. | Small, low-contrast LCD text; metronome state shown as a faint tint. |
| Ableton | BPM you can drag, double-click or tap; loop and metronome toggles with a clear filled-or-outline state. | 15–20 tiny unlabelled controls (Link, key/MIDI map, CPU). |
| FL Studio | Tempo and time as the two big, high-contrast numbers; the same gesture everywhere. | Hidden modes that change what Play does; "steps" as vocabulary. |
| Logic | Beats first, time second, never both at the same weight. | An LCD with many modes, and CPU in the bar. |

**For Boojy:**
- Keep the three readout boxes.
- Give each one the *same* tap behaviour: a tap opens a popover (U11).
- Show the default readout as bar.beat (U82).
- Make Record's red the only warm colour at rest (U17).
- Add Home (U31).

Boojy's labelled Count-in is already ahead of all four.

### 4.2 Piano roll

| DAW | Take from it | Avoid |
| --- | --- | --- |
| GarageBand | C-only labels, darker black-key rows, velocity shown as brightness. | A roll too small by default. |
| Ableton | "Scale awareness" as a visible default; always-on velocity lane; the snap grid visible on screen. | Hair-thin resize edges; 20+ cryptic clip controls (Legato, Inv, Rev). |
| FL Studio | Notes stay at the last-used length; audition on every placement; ghost notes (already "Later" in EDITING.md). | Tool sprawl; mixed snap vocabulary ("Line", "Cell"). |
| Logic | Audition on key click; a key picker that tints in-key rows. | Four MIDI editors, and a quantise parameter wall. |

**For Boojy:**
- C-only gutter labels and a faint C row (U37, U13).
- Restore the two scale pickers and name the feature plainly, for example "Stay in key".
- Show the snap size on screen (U35).
- Readable labels and selection (U12).
- Visible edge grips (U33).
- Pinch and ⌘-wheel zoom through the Zoom spec (U34).

Boojy already has what the teardowns praised: a docked editor, audition, one toolset in the B+ plan, and last-used note length.

### 4.3 Arrangement and clips

**Take:**
- Clips that read as objects: a coloured body, a header with a friendly name, and mini notes or a waveform inside (Logic, GarageBand).
- Dropping a sample onto empty space creates the right track (Ableton, FL).
- Split, Duplicate and Delete visible on the selection (GarageBand's gap; Boojy's B+ action bar already answers it).

**Avoid:**
- Functions reachable only by right-click or a modifier (all four).
- Ableton's Session/Arrangement split (Boojy's linear-first decision is right).

**For Boojy:** a Snap control that tells the truth (U1), clip bodies (U43), friendly header names (U44), a `⋯` on the selected clip that carries mute, loop, rename and colour (U41), and empty-lane hints (U42).

### 4.4 Mixer

**Take:**
- The track header as the beginner's mixer (GarageBand, and Logic's selected-track inspector). Boojy's strip-beside-lane layout already is this.
- The same order on every strip, with the track colour carried from lane to strip (all four).
- Double-click reset on every control (Logic).
- A visible master meter (the GarageBand lesson, taken in reverse).

**Avoid:**
- Routing vocabulary and dropdowns as default chrome (Ableton, Logic).
- FL's split between channels and inserts.
- Solo and Cue sharing one button.
- Tiny pan knobs (GarageBand).

**For Boojy:**
- Keep the compressed strip.
- Make it precise: a relative fader, a unity tick and detent, a clip latch (U3, U49).
- Keep the track colour when selected (U46).
- Add a `⋯` for strip actions (U48).
- Call the panel "Tracks" (U47).

Logic's selected-track inspector is an input to the still-open mixer-header decision (2026-09-13 brief §6), not a proposal here.

### 4.5 Effects and devices

**Take:**
- A few big, plainly named knobs in front of a full-parameter view: GarageBand's and Logic's Smart Controls, and Ableton's few up-front controls. This matches Boojy's settled "2–3 hero params".
- One MIX knob in a fixed place on every device (Ableton).
- Pictures that show what the effect does: a draggable EQ curve and a big gain-reduction meter (all four).
- One consistent header on every device: name, bypass, presets (Logic).

**Avoid:**
- Skeuomorphism (FL, Logic).
- Parameter walls, Racks and macro mapping (Ableton).
- Floating windows for built-in effects.
- Different visual languages across a vendor's own devices (Logic, FL). Boojy has three right now (U52).

**For Boojy:** one knob (U52), a pinned MIX slot (U60), Makeup plus gain reduction on the compressor (U61), a header `⋯` (U58), and never nested scrolling (U16).

Named presets, the EQ spectrum and the reverb quality pass stay in the parked "First Sound" theme.

### 4.6 Visual language and first run

**Take:**
- Neutral chrome with colour reserved for musical content and state (Logic, Ableton).
- One accent for selection, one colour for the playhead, one for record, never overlapping (the GarageBand lesson).
- Big targets and one task per screen (Logic and GarageBand on iPad). This backs B+ and the all-devices goal.
- Goal-based starts on the new-project chooser (GarageBand; this belongs with parked templates and onboarding).

**Avoid:**
- Icon-only panel toggles.
- The same pane showing different content by track type.
- Features hidden behind an "Advanced" switch (Logic).
- 9–11px low-contrast type (Ableton).
- Several elevation systems.

---

## 5. Design direction: a calm, precise instrument that works under a finger

Five principles. Each one ends the root cause of the same number in §2 (the sixth cause, precision, is carried by principle 4).

1. **Visible first, fast second.**
   - Every control has one obvious tap action.
   - Drag, scroll, double-click, right-click, modifiers and hover only speed up something already reachable. This is EDITING.md's touch-ready rules applied beyond editing.
   - **Rules:** readouts open a popover on tap; every object with more than one action gets a `⋯` that matches right-click and long-press; menus show a caret at rest.
2. **Tap area ≥ drawn area.** A `TapTarget` primitive with `BT.minHit`: 32px on fine pointers and 44px on coarse, opaque, with no visual change. Neighbouring targets split the gap and never overlap. It gets adopted by family: bar, strip, device header, dropdown, and editor edges.
3. **One colour, one meaning.** Colour tokens are named for their meaning, and nothing is painted with a literal. The proposed map:

   | Token | Meaning | Dark | Light |
   | --- | --- | --- | --- |
   | `accent` | selection, focus, primary action | existing blue | existing blue |
   | `record` | recording or armed, **only** | one red | same |
   | `danger` | destructive or error | shares `record` hue, used sparingly | same |
   | `warning` | a real warning, **only** | one amber | darker amber |
   | `success` / `level` | meter body, confirmations | one green | same |
   | `loopRegion` | loop range | accent at ~12%, plus a 2px accent underline | accent at ~10% |
   | `playheadActive` | playhead | near-white | near-black |
   | `textMuted` | decoration only, ≥ 4.5:1 | ~`8A8FA3` (verify) | ~`5E5E5E` (verify) |
   | `pan` | pan arc | `textSecondary` | `textSecondary` |

   The transport is neutral at rest. Play turns green only while rolling, Stop is a neutral square, and Pause gets the same treatment as Play.
4. **Controls tell the truth.**
   - Inert controls are hidden (Snap until wired, single-option dropdowns, dead "Change Color").
   - Every readout shows its unit.
   - Every knob and fader resets to its *stored* default, and meters say "too loud", not "loud".
   - Typed input never gets silently replaced.
5. **Quiet when healthy, clear at risk.**
   - A dirty dot instead of "Project saved" toasts.
   - A clip latch instead of amber at −12 dB.
   - A loop band that sits back from the notes.
   - Confirmations only for destructive actions that can't be undone.

**The shared surface kit (one of each, used everywhere):**
- `TapTarget`
- `BarButtonSurface`
- `BoojyDialog` with `dialogTheme`
- `showBoojyMenu` (migrate the six stock sites)
- `BoojyTooltip` (with the shortcut line)
- one `ArcKnob` (with default, reset and type-in)
- one readout popover
- the device shell with a pinned MIX

**Type scale:** 10 caption / 12 label / 13 body / 15 display / 20 heading, with a 10px floor after scaling. Migrate each file as it's opened; the BACKLOG font-token item covers this.

**UI Scale:** relabel it "Text size" and keep the fixed-size chrome out of text scaling. That's cheaper and honest. The alternative is to scale control sizes from one `BT.scale` (see decision D9).

---

## 6. Before and after mockups (ASCII)

> These show layout, not appearance. Colour, type and motion follow §5. The real check is `fvm flutter run -d macos`.

### 6.1 Top bar at rest (screenshots 03 and 08)

**Before.** Three saturated rings at rest, "Untitled" with no caret, unlabelled numbers, and tempo you can only type after a double-click:
```
▲udio Untitled      ↶ ↷ ⫼    [▦ Bar▾][↻][𝄐][Count-in]  (▶)(■)(●)[⛶]  [1.1.2][254 BPM][4/4]        ⫶
      ▲ menu? no cue          ▲ Snap: arrangement ignores it  ▲ green  ▲ tap does nothing / cycles / menu
                                                     orange red
```
**After.** A neutral transport, a caret and dirty dot, one tap behaviour for all readouts, and Home:
```
▲udio▾  Untitled ▾ •    ↶ ↷  │ ⫼   [▦ Bar▾][↻][𝄐][Count-in]  ⏮ (▶)(■)(●) ⟲   [ 1.1 ][ 120 BPM ][ 4/4 ]     ⫶
        ▲caret  ▲unsaved       ▲gap = two groups                 ▲neutral; ● is the only red
                                                                  tap any box → popover; drag/scroll still work
```
*Notes:*
- Readout boxes have a fixed width for the widest mode (U27).
- "BPM" stays at every width (U11).
- Each control gets a hit box of at least 32–44px with an unchanged look (U23).
- The Capture glyph changes to a clock-rewind dot (U74).

**Tempo popover (tap on the number; replaces the stock dialog):**
```
          ┌──────────────────────────────┐
          │  Tempo                        │
          │  [ − ]   [ 120.0 ]   [ + ]    │  typed value kept; bad input shows an error, never "120"
          │  [        Tap        ]        │  tap-tempo survives every window width
          │  Tip: drag or scroll the      │
          │  number in the bar to nudge.  │
          └──────────────────────────────┘
```
A burst of scrolls, taps or steps is one undo step (U30).

### 6.2 Empty project (screenshot 03)

**Before:**
```
┌ ruler ▇▇amber▇▇ 2    3    4  ───────────────────────────────────────┐
│ ║ ║ ║ ║ ║ ║ ║ ║   [piano icon]   ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║     │ grid runs through the text
│ ║ ║ ║   Drag an instrument from the library   ║ ║ ║ ║ ║ ║ ║ ║ ║     │ drag-first
│ ║ ║ ║        to start making music ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║     │
│ ║ ║ ║ ║ ║ ║ ║ ║ ║    or   ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║     │ "or" ≈ invisible
│ ║ ║ ║ ║ ║   [+ ▦ MIDI] [+ ≋ Audio]   ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║ ║     │ jargon
├──────────────────────────────────────────────────────────────────────┤
│ [Instrument] [MIDI]              (five tools)                        │ editor for a track
│ ┌───────────┐                                                        │ that doesn't exist
│ │ Add effect│                                                        │
└──────────────────────────────────────────────────────────────────────┘
```
**After:**
```
┌ ruler (loop = faint cool tint) ───────────────────────────────────────┐
│ · · · · · · · · · · ·  ┌────────────────────────────────┐ · · · · · · │ grid faded while empty
│ · · · · · · · · · · ·  │  Start with an instrument       │ · · · · · · │
│ · · · · · · · · · · ·  │  [ + Instrument track ]         │ · · · · · · │ click first
│ · · · · · · · · · · ·  │  [ + Record or import audio ]   │ · · · · · · │
│ · · · · · · · · · · ·  │  or drag a sound from Library   │ · · · · · · │ drag is the quiet line
│ · · · · · · · · · · ·  └────────────────────────────────┘ · · · · · · │
├───────────────────────────────────────────────────────────────────────┤
│  Select a track to see its instrument and effects here                │ editor hint, no fake tab
└───────────────────────────────────────────────────────────────────────┘
```
Tempo reads 120 on a new project (U2).

### 6.3 Mixer strip (screenshot 08)

**Before:**
```
┌───────────────────────────────────────────────┐ ← border turns white when selected
│ ▦ 1 Synthesizer              [🔇][Ω][●] ⚡ ◌  │ 14–22px targets, ◌ pan barely visible
│ 0.0 dB [█████████████████████████(●)────────] │ meter −60..0 fills; 0 dB fader at 70%; no tick
└───────────────────────────────────────────────┘
│ ♪ 3 Audio      In 1▾   [🔇][Ω][●][◉] ⚡ ◌      │ M/S/R pushed ~26px left by Monitor
```
**After:**
```
┌▌──────────────────────────────────────────────┐  ▌ track colour always shown
│▌ ▦ 1 Synthesizer        [M][S][R][ ]  ◐C   ⋯  │  fixed Monitor slot; pan shows value; ⋯ = strip menu
│▌ 0.0 dB  [████████████░░░░░░░|░░(●)──────] ▮   │  | unity tick + ~1.5 dB detent; ▮ clip latch
└▌──────────────────────────────────────────────┘  selected = inner ring + lift, colour kept
```
*Notes:*
- Relative fader drag with a grab offset (U3).
- Hit boxes ≥ 32px with M/S and R separated by ≥ 6px (U23).
- "In 1" becomes "Mic" or the device name (U94).
- The panel is renamed "Tracks" (U47).

### 6.4 Piano roll (screenshot 05)

**Before:**
```
[Loop] Start 1.1.1 Length 4.0.0 Signature 4/4 [▦ Snap▾][Quantize▾][Scale][Legato][Velocity]
┌────┬▇▇▇▇▇▇▇▇▇ amber loop ruler ▇▇▇▇▇▇▇▇▇┬───────────
│F#5 │                                    │  every row labelled at 8px, bright key slabs
│ C5 │  [C5▒▒]      [C5▒▒]      [C5▒▒]    │  white label on pale green ≈ 1.7:1
│ B4 │                                    │  lanes ≈ 1.2:1, no C row marked
│ G4 │[G4▒▒]      [G4▒▒]                  │
│ F4 │                          [F4▒]← selected? barely
```
**After:**
```
[Loop]  Clip ▾ (4 bars)   [▦ Snap 1/16 ▾][Quantize▾][C major ▾ Stay in key][Legato][Velocity]
┌─────┬────── quiet cool loop tint, 2px underline ──────┬───────────
│     │                                                 │  C-only labels (10–11px + octave)
│ C5 ─┼ ─ ─ ─ faint octave row ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
│     │  [C5▓▓]      [C5▓▓]      [C5▓▓]                 │  dark ink on light fills
│     │[G4▓▓]      [G4▓▓]                               │  lanes ≈ 1.35:1
│     │                          ┏F4▓┓▐ ← outer ring + grip on selection
│ C4 ─┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
```
The Start, Length and Signature boxes move into a "Clip" popover. The B+ Select/Draw toggle and hints arrive with EDITING.md and aren't drawn here.

### 6.5 Device card (screenshots 04 and 08)

**Before:**
```
┌ Reverb ─────────────── ● ┐▐   435px tall; three 32px knobs float in space
│                          │▐   9px labels in muted text
│      ◠     ◠     ◠       │▐   MIX is just "the last knob"
│    SIZE  DAMP   MIX      │▐   strip looks like a fader but is a meter
│    0.5   0.5    30%      │▐   delete/duplicate = right-click only
└──────────────────────────┘
```
**After:**
```
┌ ⟳ Reverb            ⏻  ⋯ ┐▮  header: glyph · name · power · ⋯ (Bypass/Duplicate/Reset/Delete/Move)
│  ╭─ decay tail ───────╮   │▮  small visual of what it does
│  ╰────────────────────╯   │▮
│    ◯ Size     ◯ Damp      │▮  hero knobs 44–48px, 11px labels, 12px values
│    1.2 s      40 %        │▮  double-tap resets to default; tap value to type
│ ─────────────────────────  │▮
│    ◯ Mix  30 %            │▮  pinned MIX slot, same place on every device
└───────────────────────────┘   ▮ flat meter, green to −6 dB, red only at clip
```

---

## 7. Proposed work, mapped to the scorecard and releases

### 7.1 Design decisions (each with the alternative's cost)

- **D1. Readouts open a popover on tap; gestures stay as accelerators.** *Alternative: keep double-click to type and add help text.* It costs nothing to build, but it still fails touch rule 1 and a beginner still sees three read-only numbers.
- **D2. One `TapTarget` primitive now, adopted family by family.** *Alternative: enlarge each control's drawn size.* That breaks the settled density ladder and the calm look. *Alternative: wait for the iPad port.* Every new widget then adds to the debt, against BACKLOG's "every UI change from now on" rule.
- **D3. Semantic colour tokens (one amber, one red, one green, plus `loopRegion` and `playheadActive`), with a neutral transport at rest.** *Alternative: just desaturate the literals.* It's cheaper, but amber would still mean three things and the next widget reintroduces a literal. *Cost:* Play and Stop lose their "always coloured" look, which some users read as familiarity.
- **D4. Hide the toolbar Snap until it is wired, then wire it before v0.7 ships.** *Alternative: wire it straight away (M).* That's the right end state but takes longer. *Alternative: leave it.* A visible control that lies breaks a settled decision and costs trust on row 3.
- **D5. Precise fader: relative drag, unity tick with detent, latched clip cap.** *Alternative: a numeric dB field only.* It's precise but not fast, and doesn't fit the compact strip. *Alternative: the "enhanced fader".* Already rejected.
- **D6. `⋯` on every object that has a right-click menu (clip, strip, device, recent project), plus long-press.** *Alternative: long-press only.* That's invisible on mouse and trackpad and fails "visible first". *Cost:* a small glyph on selected objects. It shows only on selection or at strip edges, so it stays quiet.
- **D7. Settings becomes pages.** *Alternative: scroll-spy on the current scroll.* It's cheaper, but still hides content under macOS overlay scrollbars and needs a tall dialog.
- **D8. Dirty dot beside the project name instead of save toasts.** *Alternative: toasts plus the macOS title asterisk.* The native title is hidden on macOS, so the risk stays silent.
- **D9. Relabel UI Scale to "Text size" and exempt the fixed chrome.** *Alternative: true control scaling from `BT.scale`.* That's the better end state, but it's L-sized and touches every painter. It's worth doing before the iPad port, not now.
- **D10. One `ArcKnob` and a pinned MIX slot across the synth and every effect.** *Alternative: keep the synth sliders (long throw).* It's familiar, but three languages in one chain is the clearest "unfinished" signal in screenshot 08.
- **D11. Rename the "Mixer" panel "Tracks" and add a slim lane label.** *Alternative: keep the name.* Hiding "Mixer" then removes track identity, a trap for beginners. *Cost:* it touches the open workspace-layout decision (brief §4 and §6). Tyr should confirm before the rename.

### 7.2 Mapping to releases

**v0.7.0: the core works every time (rows 1, 2, 3, 9, plus the B+ editing model)**

| Work | Findings | Rows | Size |
| --- | --- | --- | --- |
| Snap tells the truth (hide now, wire before release) | U1 | 3 | S → M |
| Arrangement bugs that survive B+ | U10, U38, U39, U40 (behaviour), U90, U91 | 3 | M |
| Undo hygiene | U30, U83 (confirm first), U29 | 3 | S |
| New project is really new | U2 | 9, 10 | S |
| Save and close you can trust | U5, U6 (dirty flag + dot), U70, U105 | 9 | M |
| Input actually applied, sensible default | U66 | 2 | S |
| Light theme regressions (a decision says they are bugs) | U7 | 11 | S |
| **Build B+ on the new primitives:** the action bar, `⋯`, empty-view hints and pinch are in EDITING.md's first version. Build `TapTarget` and the `⋯`/long-press pattern *as part of it*, so the arrangement and piano roll get U40, U41 and U42 for free. | U23 (editor half), U41, U42, U86 | 3, 12 | M (inside B+) |

Every v0.7 item follows the BACKLOG process: a failing test first, one PR each, and Tyr's walkthrough. U2, U4 and U10 are code-read candidates until then.

**v0.8.0: the rest of the scorecard**

| Theme | Findings | Rows |
| --- | --- | --- |
| **Visible and tappable** (principles 1 and 2) | U11, U15, U23 (rest), U31, U48, U57, U58, U67, U68, U77, U98, U107 | 10, 12 |
| **One colour, one meaning** (principles 3 and 5) | U8, U9, U17, U18, U19, U46, U62, U72, U92; then U20 and U22 as files are opened | 11 |
| **Precise mixer** | U3 (could move to v0.7 if Tyr hits it), U49, U50, U51, U93, U94, U95, U99, U47 (after D11 sign-off) | 6 |
| **Piano roll orientation** | U12, U13 (pickers), U32, U33, U35, U36, U37, U84, U85; U34 via the Zoom spec | 4 |
| **Device shell, finished** | U4 (move to v0.7 if a failing test shows effects vanishing, since that's a take-loss-class bug), U16, U52–U56, U59–U61, U63, U100, U102–U104 | 5, 7 |
| **Chrome consolidation** | U14, U21 (D9), U24, U25 (after the hover sign-off), U26, U27, U28, U64, U65, U69, U74–U76, U78, U82, U106, U109, U110, U111, U112 | 10, 11 |
| **Windows parity** | U79, U108 | 13 |

**Later** (the every-device goal, or waiting on another decision):
- true control scaling (D9's alternative);
- a narrow or phone layout beyond the density ladder;
- the top-bar overflow menu (BACKLOG item);
- the UI Labs switcher clean-up (U71, U81, Tyr picks);
- `BoojyColors` caching (U73) when a profiler shows it matters;
- CC-lane colours with the CC-lane decision;
- goal-based new-project starts and named effect presets (parked "First Sound").

### 7.3 In and out

- **In** (this review's recommendation): the v0.7 table above, then the six v0.8 themes. Each theme is roughly 2–5 focused days.
- **Out, and why:**
  - Other tool models: B+ is agreed.
  - A merged single LCD: the toolbar was settled on 2026-09-13; D1 gets the benefit without re-opening it.
  - Vertical faders and a full console mixer: they fight the compact-strip model and the open mixer-header decision.
  - Peak-hold: decided against.
  - A permanent hint line: decided against. Consistent `BoojyTooltip`s plus EDITING.md's empty-view hints do that job.

### 7.4 Verification for the v0.7 slice (`fvm flutter run -d macos`)

1. **New project tempo.** With a project at 150 BPM open, choose New Project. The bar reads **120 BPM, 4/4**.
2. **Snap.** Set Snap to "Bar", zoom in and drag a clip. It lands on bar lines. Turn Snap off and it moves freely. Trim an audio clip and its edge lands on the grid.
3. **Drag-create ghost.** Scroll to bar 20 and drag-create on an empty MIDI lane. The ghost sits under the pointer, and the clip lands where the ghost was.
4. **Tempo undo.** Scroll the tempo up ten notches, then press ⌘Z once. The tempo returns to where it started.
5. **Save As.** Choose Save As, type a name, cancel the folder picker. The project name is unchanged.
6. **Dirty dot.** Edit anything and a dot appears beside the name. Save and it disappears with no toast. Close straight after saving and there's no warning.
7. **Light theme.** Switch to the Light theme and press Play. The playhead is clearly visible in both the arrangement and the piano roll, and the selected track keeps its colour.
8. **Recording input.** In Settings → Audio, pick "No Input" and try to record. Nothing is captured. Pick the Mac mic and the level moves.
