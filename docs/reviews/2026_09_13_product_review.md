# Product, UI/UX and repo-health review — 2026-09-13

**Decision brief.** Evidence, file:line citations, the full tool behaviour matrix, the dialog
inventory and the verifier's verdicts are in
[`2026_09_13_product_review_evidence.md`](2026_09_13_product_review_evidence.md). Read-only
review of master at `988a068`; nothing in the repo was changed except these two files.

Method: four readers (tools and interaction model; panels, layout and mixer; correctness and
architecture; repo health, dependencies, platforms and docs), one adversarial verifier over
every demonstrated or high-severity finding, synthesis here. Grounding: two current screenshots
(empty project, 2048×1152 window; a mixer-strip crop) plus the v0.6.0 screenshot. Laptop budgets
are computed from code at 1710×1112. Both gates were run and are green: 194 Rust tests, 1,282
Dart tests including the native ones.

Bug tiers, used throughout: **reproduced** (observed running), **demonstrated** (complete code
path, input to wrong outcome), **suspected** (plausible, not closed). Nothing in this review is
reproduced; the gates pass and no existing test exercises the paths below. The verifier
confirmed 61 of 62 items and refuted one stale table row. It cannot promote a tier.

---

## 1. Verdict

The bones support the potential. A linear arrangement in one window, one engine with genuine
real-time hardening on the playing path, a command layer that makes every edit undoable, and a
model/command test base that actually asserts behaviour. None of that needs rethinking.

What stops it feeling close is not polish. Four structural things, in order of how much they
cost you today:

1. **The real-time path breaks its own rules off the playing branch.** With the transport
   stopped, every VST3 is processed one sample at a time with two heap allocations per sample.
   Recording grows an unreserved buffer under a blocking lock inside the audio callback. Adding
   a plugin, saving (including the auto-save timer) and exporting all hold the effect lock the
   callback needs. These are demonstrated, coherent, and explain "crackles, then maybe crashes"
   without needing VST3 to be at fault. VST3 stays a hypothesis for the crashes: the one path
   that could crash is plugin editor windows being driven off the macOS main thread, and that
   is suspected, not shown.
2. **The five tools are one tool plus four special cases, and a beginner cannot read the mode
   from the canvas.** Four of five are already reachable by a modifier or key. Three glyphs are
   borrowed from copy, cut and backspace. The Erase cursor is the OS "forbidden" symbol. The
   beat-making loop you described costs eight tool switches by toolbar, zero to two by modifier.
3. **The workspace spends its scarcest resource, laptop height, on nothing.** A third of the
   window is an empty editor on a new project; 62 px of the arrangement is a permanently blank
   master band; six tracks fit at default height with everything open. On the 30-inch the
   editor stays 356 px because panel sizes are computed once and never re-proportioned.
4. **The mixer header's glyph swap collided with the icon set and the colour set.** Three
   speaker glyphs in one row mean "audio track", "muted" and "monitoring". Headphones mean both
   Solo and Master. Arm red and monitor green are the same hues as the drum and synth track
   colours. Your dislike of it has a precise cause; it is not taste.

Everything in this brief is fixable without a rewrite, and none of it requires breaking
projects. The two decisions that shape the rest are the tool model (§5.1) and whether the
engine cluster goes first (§6, D1).

---

## 2. Confirmed bugs (demonstrated from code, verifier-confirmed)

Ranked by user impact. IDs refer to the evidence file. None is reproduced.

| # | What a user experiences | Where | Sev |
| --- | --- | --- | --- |
| C1 | Idle CPU load and crackle whenever a VST3 is loaded and the transport is stopped. 48k plugin calls and 96k mallocs per second per plugin inside the render callback. Playing path is correct. | `renderer.rs:670-740` → `vst3_host.rs:852-858` | high |
| C2 | Crackle that worsens as a take gets longer; each buffer doubling copies up to 230 MB inside the audio callback; UI level polling stalls the audio thread on a blocking lock. | `recorder.rs:655-657` | high |
| C3 | A hard dropout the moment you add a VST3: the plugin loads from disk while holding the lock the audio thread blocks on. Same shape on removal. The project-restore path already does it right. | `api/vst3.rs:20-40` | high |
| C6 | An audio glitch on every save, and on every auto-save tick, because VST3 state is serialised under the effect lock. Also: state is fetched twice, so a plugin whose state size changes between calls is saved empty. | `audio_graph/project.rs:31-205` | med-high |
| C7 | Exporting while playing glitches and produces a non-deterministic file: the offline render uses the live effect instances and retunes their sample rate globally. | `export_dialog.dart:641`, `offline.rs:181-196` | med-high |
| C17 | Crackle that scales with project size: every callback deep-clones every track's clip and automation vectors. | `renderer.rs:841-854` | med |
| C8 | Boojy's own VST3 parameter sliders change the plugin GUI but not the sound. | `vst3_host.cpp:1073-1080` | med |
| C9 | A chain of [VST3, built-in EQ] reloads as [EQ, VST3]. Projects sound different after reopening. | `audio_graph/project.rs:543-724` | med |
| C10 | Unplugging the interface while stopped goes silent with no message and no recovery; stream is never rebuilt. | `renderer.rs:1349`, `device.rs:212` | med |
| T1 | Duplicate tool click on a note makes an invisible stacked copy: doubled velocity, flam on samplers. The automation lane guards against exactly this; the piano roll doesn't. | `piano_roll.dart:1693-1709` | med |
| T4 | The Slice tooltip and shortcuts sheet advertise Cmd+click, which is Duplicate everywhere; the piano-roll Cmd+click-slice branch is unreachable. | `editor_panel.dart:675`, `piano_roll.dart:1767` | med |
| T7 | Cmd+E is bound to both "Split at Marker" and "Show Editor Panel"; the marker it names no longer exists (removed in PR #79). | `daw_menu_bar.dart:260,309` | med |
| T5 | Slice shows a cut preview on MIDI clips and none on audio clips. | `timeline_gesture_layer.dart:941-948` | med |
| P26 | Below ~292 px of mixer width the input chip disappears and there is no other way to choose which mic a track records from. Your mixer is at ~210 px in the screenshot. | `track_mixer_strip.dart:388-394` | med |
| P23 | Below 24 px track height, mute and solo become non-clickable dots and Arm vanishes. | `track_mixer_strip.dart:786-819` | med |
| P12 | Cmd+B opens a dialog saying "Coming soon". Conflicts with the settled "inert controls work or are hidden" decision. | `daw_screen.dart:2236-2271` | med |
| C11 | A plugin returning an error makes the audio thread write to stderr every block. | `vst3_host.rs:864` | low-med |

Lower-severity demonstrated items (T2, T3, T6, T8, T10–T13, P5–P9, P11, P13–P16, P25, P27–P33,
C14–C16) are in the evidence file. The verifier confirmed all of them.

## 3. Unverified concerns (suspected)

- **C4, high: plugin editor calls run off the macOS main thread.** Every open, attach and close
  editor call is a direct `dart:ffi` call from the Dart isolate. The C++ has a main-thread bounce
  on exactly two Cocoa entry points and a dead comment promising a main-thread check that was
  never written. That asymmetry is strong evidence someone saw it happen. **The uncertainty:**
  recent Flutter releases merged the Dart UI thread onto the platform thread on Apple platforms;
  if that applies to Flutter 3.44 on macOS, this is refuted. One `pthread_main_np()` log line in
  `vst3_attach_editor` settles it either way. This is the only candidate in the review that
  explains a *crash* rather than a glitch, together with C5 (an unretained NSView pointer
  captured by a queued block, freed by Flutter before the block runs).
- **Which engine build have you been dogfooding?** `./build.sh` with no argument installs a
  debug engine at opt-level 0 into the app bundle (the rules file describes an older symlink
  behaviour). A debug engine crackles regardless of anything above. Worth confirming before
  attributing all crackle to C1/C2/C17.
- **C13:** plugin scanning dlopens every `.vst3` in-process, unsandboxed, and is the one API path
  that skips the global graph mutex. If crashes cluster around launch or opening the plugin
  browser, this is the cause.
- **C12:** `reset()` on a VST3 is a full deactivate/reinitialise/activate cycle; harmless if
  never called from the audio thread, which was not fully traced.
- **T9:** in Erase or Slice mode, clip edges still trim (the handles ignore the tool) while the
  cursor says "forbidden". Which recogniser wins differs between audio and MIDI clips.
- **T7/T8 runtime:** which of the two Cmd+E bindings macOS dispatches, and whether the piano
  roll's Cmd+B (duplicate notes) ever fires given the global Cmd+B (bounce). Needs a launch.

## 4. UX findings

### 4.1 The five tools

**What they actually do** (full matrix in the evidence file):

| Tool | Arrangement | Piano roll | Audio editor | Automation lanes |
| --- | --- | --- | --- | --- |
| Draw (default) | drag empty = sized clip (MIDI tracks only); click clip = select; edges trim | click empty = note; drag note = move; edges resize | inert | click = add point |
| Select | drag empty = box select; otherwise same as Draw | same, plus box select | inert | box select |
| Erase | click/sweep deletes whole clips; edges still trim; double-click still creates a clip | click/sweep deletes whole notes | inert | delete point (sweep only in the track lane) |
| Duplicate | click = **select only**; drag = copy-drag | click = **stacked invisible copy** (T1); drag = copy-move | inert | copy point, nudged right |
| Slice | click = split at pointer; MIDI-only hover preview | click = split note | inert | **adds a breakpoint**, and the two lanes disagree on where |

Modifiers already cover four of the five in every view: Alt = Erase, Cmd = Duplicate, Shift =
Select, Delete key = delete selection. Slice is the only tool with no modifier, and it is the
one whose tooltip claims one. The tool row also renders, live-looking, over the audio editor and
on an empty project with nothing to act on.

**Selection state.** The active tool shows in two places: the toolbar button fill (well done,
including a half-fill for a held modifier) and the cursor. The cursor is the problem: Select is
the plain arrow (indistinguishable from no mode), Erase is the OS "forbidden" symbol, Slice is
the text I-beam. The toolbar sits in the editor header at mid-screen, about 600 px from either
canvas. A beginner cannot tell which mode they are in from the canvas alone.

**Names, answered by behaviour.**

- *Erase → Delete?* Yes. It deletes whole objects, never partially; its glyph is already the
  backspace key; Ableton has no such tool and Logic calls the same thing Eraser. The one thing
  "Erase" adds is the sweep, and Alt-drag already gives the sweep with no mode. Renaming it
  makes its case for being a button weaker, not stronger.
- *Duplicate vs Copy?* They are already distinct, the wrong way round: the tool is an immediate
  duplicate wearing the clipboard-copy glyph, while clipboard copy for clips does not exist
  (the Edit menu items are disabled stubs). Do not rename it Copy. Change the glyph, or remove
  the tool: Cmd+D and Cmd-drag already do everything it does, and its click in the arrangement
  does nothing.

**Mode-switching cost.** Draw a 4-bar pattern, fix a note, copy to bars 5–8, slice a bar off,
delete strays: eight switches by toolbar, roughly 10,000 px of mouse travel on the laptop; zero
to two once the modifiers are known. The user paying the eight is exactly the one Boojy targets.

**Options** (mockups and full tradeoffs in the evidence file):

| | Toolbar | For | Against | Conflicts |
| --- | --- | --- | --- | --- |
| A. Keep five, fix the surface | `✏ ↖ 🗑 ⧉+ ✂` Draw · Select · Delete · Dup · Slice | Cheapest; zero behaviour change | Leaves the eight switches and mode-blindness untouched | none |
| **B. Three tools** (recommended) | `↖ ✏ ✂` Pointer · Draw · Slice | Beginner path 8 → 2 switches; removes both mis-glyphed tools; keeps your one-gesture drag-create as a named tool; keeps one shared toolset | Pointer becomes the default, a change to your muscle memory; Slice stays modal | reverses the default tool (not a recorded decision); "one global toolset" survives |
| C. One Draw toggle, no row | `✏ Draw` (B key) | Simplest, one visible binary, touch-ready; what the June research chose | The insert marker it relies on was deleted the day after that research; now the most work by far | mildly reopens "one global toolset" |
| D. Smart tool, click zones | none | Zero chrome and travel | Zones are invisible until learned; least beginner-legible | removes the shared toolset |

Recommendation: **B, with A's glyph and cursor fixes folded in.** It answers both naming
questions by removal rather than relabelling, keeps every capability, and is a strict subset of
the road to C if dogfooding later wants it. The June research still holds on every argument
except cost: it assumed the piano-roll insert marker existed, and PR #79 removed it. Also fix
the shortcuts sheet, which documents the tools as piano-roll-only and advertises clip copy/paste
that does not exist (T13). The two settled decisions this touches ("one global toolset", "no
canvas tool badge") both survive B as written.

### 4.2 Workspace and use of space

The main window is the right model: arrangement, editor, library and mixer all live in it, and
of 33 popup surfaces only two should not exist, three should be panels and seven should be
inline. Export, settings and floating plugins are the acceptable ones, as you wanted.

The problem is where the height goes. At 1710×1112, defaults, everything open:

| | Value |
| --- | --- |
| Tracks visible at default 100 px | 6 |
| Of which lost to the blank master band | 62 px (one return adds 102 px more) |
| Piano roll pitch range | 1.3 octaves (under one with the velocity lane) |
| Editor on an empty project | 356 px, 44 % of the window, showing "No track selected" |

On the 30-inch nothing re-proportions: the editor stays 356 px on a 1440 px screen, the mixer
is hard-capped at 500 px and its layout does not change with width, and the editor spans the
full window so the piano roll becomes a 10:1 letterbox. Only the arrangement width and the
device chain gain anything from the monitor.

**Options.** (A) editor and mixer share the bottom region as tabs: 8 tracks, full-width mixer,
but you cannot watch a fader while dragging a clip. (B) library as an overlay: cheap, but it
fights the primary track-creation gesture. **(C, recommended)** reclaim the structural waste and
keep the three-panel shape: stop reserving hidden master/return bands, start the editor
collapsed on an empty project and auto-expand on first selection (the mixer double-click path
already does this), re-proportion on display change, and let the strip earn width above 420 px.
Four independent changes, 7 tracks with the editor open and 11 with it closed, nothing to
relearn. C does not fix the pitch-axis squeeze; if the piano roll proves to be where you spend
your time, A's "mixer as a bottom tab" is the follow-up.

### 4.3 Mixer clarity

PR #111 replaced the M S R letters with glyphs. Every individual choice is defensible; the
stack is what reads badly:

- Audio track default icon = monitor button glyph = the speaker family used for mute. Three
  speakers in one row at 12 px (P17, the review's one high-severity UX finding).
- Headphones = Solo and = Master identity, so the Master looks permanently soloed (P18).
- The monitor button is inserted inside the right-aligned cluster only on armed audio tracks,
  so those rows' M/S/R sit 26 px left of everyone else's (P19). This is the misalignment in
  your screenshot.
- The empty circle is the pan knob: blank at centre, no tooltip, drag-only (P20). The lightning
  is the only glyph with no well and no tooltip, so the button that adds effects and sends reads
  as decoration (P21).
- Arm red, monitor green and mute yellow sit on the same hues as the drums, synth and sunflower
  track colours; the 2 px track-colour border makes a green MIDI strip read as selected (P22,
  P24).

Beyond the header: three ways to add an effect with different powers, and only the modal FX
picker can create a send (P14); two colour pickers plus a third clip palette (P15); the circle
shape means action in the transport, toggle in the mixer and a value on the pan knob (P30); an
instrument-browser modal duplicates the library's Instruments branch (P16); tempo is typed in a
modal while dB is typed inline (P27).

**Options for the header.** (a) Keep glyphs, break the collisions: a waveform default icon for
audio tracks, a distinct Master icon, wells and tooltips on FX and pan, monitor moved out of
the M/S/R cluster so columns align, state colours shifted off the track palette. (b) Return to
letters (M S R, plus I for input monitoring), which carried three unambiguous meanings in 8 px
of type and never collided. Recommendation: (a) first, since the glyph decision came from the
June review's M4 finding and the collision is with the *icon set*, not the idea; fall back to
(b) if it still reads badly after the fixes. Either way, the master strip's pan knob has no
beginner use and can go.

### 4.4 Consistency and discoverability

Button roles are inconsistent across the four surfaces: transport toggles are rings with tint
and hover motion, mixer toggles are solid circles with no hover, editor tools are rounded
squares, device chain uses a header dot. Tooltips are `BoojyTooltip` on M/S/R, plain Flutter on
the tools, and absent on FX, pan and the track icon. About twelve raw Material dialogs skip the
Boojy dialog chrome (P11). None of this is a single fix; it is a pass with one rule per role.

## 5. Competitor comparison (workflow, not features)

Verified against current manuals where it mattered; the rest is background from the June
reviews.

- **Ableton Live 12** has *no* draw tool in the arrangement: click selects a clip, click the
  background sets an insert marker, Cmd+E splits there, Cmd+D duplicates the selection. Draw
  Mode (B) exists only in the MIDI editor and automation; with it off, double-click adds or
  deletes a note. The June research treated B as an arrangement model, which it is not. Boojy's
  Option B (pointer default, Draw as a named tool, Delete key) is closer to Ableton's actual
  arrangement than today's five tools are.
- **Logic Pro** ships fourteen tools but the Pointer alone moves, resizes and loops; T opens the
  tool menu *at the pointer*, so travel is never the cost. If Boojy keeps a modal Slice, a
  pointer-local picker or right-click "Split here" is the standard mitigation for a toolbar 600
  px away.
- **GarageBand** has no tool palette at all; position on the region decides. That is the ceiling
  for beginner legibility and the floor for one-gesture create, which is why B keeps a Draw tool.
- **FL Studio** is the one DAW with a persistent global palette, and it is the one the June
  review told Boojy not to copy. The five-tool row is closest to FL today.
- **Mixer:** Boojy's always-visible, scroll-coupled strip column is better than all four for a
  4–14-track project. Nothing here argues for a separate mixer window. The horizontal fader with
  the meter inside is a consequence of that choice and is fine; the header row is not.

## 6. Product decisions to make

Each with the benefit, the risk and what is uncertain. Items marked ⚑ conflict with a settled
BACKLOG decision.

- **D1. Engine cluster first, regardless of UX direction.** C1, C2, C3, C6, C7 and C17 are
  engine-only, need no UX change, and are the difference between a demo and a daily tool.
  Benefit: removes the demonstrated causes of crackle. Risk: low, each is a thin-slice change
  mirroring a pattern the code already uses elsewhere (block processing, the restore path's lock
  discipline). Uncertainty: none of them is reproduced; write the three cheap tests (§7) so they
  become so. Do C4's one-line thread check at the same time to settle the crash hypothesis.
- **D2. Tool model: Option B.** Benefit and risk in §4.1. Uncertainty: whether Pointer-as-default
  suits your own hands; try it for a week before committing. ⚑ Reverses the default tool; the
  two recorded decisions survive.
- **D3. Workspace: Option C now, A as a follow-up experiment.** Benefit: +62 to +160 px on the
  laptop, no relearning, the empty-project first impression stops being half a window of
  nothing. Risk: low. Uncertainty: whether the pitch squeeze is the real bottleneck, which only
  dogfooding on the piano roll answers.
- **D4. Mixer header: fix the collisions (a), letters (b) as fallback.** Benefit: your stated
  dislike has a mechanical cause; fixing it is cheap. Risk: the June review's icon rationale
  gets partly reversed if (b). Uncertainty: taste, which is yours to call.
- **D5. Enforce "inert controls work or are hidden".** Remove the Bounce dialog, the unreachable
  VST3 parameter dialogs, the tool row over the audio editor and on an empty project, and the
  "Split at Marker" label. Benefit: fewer dead ends. Risk: none. This is enforcement of an
  existing decision, not a new one.
- **D6. Pre-beta compatibility: no breaks proposed.** C9's fix adds a chain-order index to the
  project format, which is additive; old projects load with the current behaviour. Tool and
  workspace changes touch `ui_layout.json` only, which already tolerates unknown keys. If the
  format is ever going to change, the window is now, before beta, and nothing above needs it.
- **D7. Platforms: keep the dormant code; nothing worth removing.** The web fake is verified
  gone. What remains is the untouched iOS runner scaffold (176 KB tracked, regenerable in
  seconds), 15 iOS build gates in Rust that compile out on macOS and Windows and document what
  an iPad port needs, and five one-line `Platform.is*` branches. Removing any of it saves no
  build time and forecloses documented v1.0 candidates for nothing. Two exceptions worth a
  decision: the `mobile` and `asio` Cargo features are never built by anything and have likely
  rotted (ASIO is deferred, not cancelled, so ask, don't delete); and the three conditional-export
  files carry comments describing a web branch that no longer exists. No Linux code exists to
  remove. The stack question stays closed, as PLATFORMS says.
- **D8. Consolidate the `daw_screen` twins, on evidence.** 69 private/mixin method pairs; two
  verified diverged in behaviour (`saveNewVersion`: the dead copy skips copying project files)
  and one in signature; roughly 44 mixin copies have no caller (verifier sampled 7 of 10 dead).
  The repo-health reader initially concluded the twins were already gone because it checked only
  the three names the rules file mentions; the full sweep and the verifier's independent regex
  both land on 69. Benefit: closes a silent-drift hazard. Risk: low, mechanical, analyzer-checked.
  This is *not* a case for splitting the 4k-line file; that remains unjustified by evidence.

## 7. Maintainability recommendations (evidence-gated)

- **Three tests that would have caught the top bugs**, each under an hour: assert the stopped
  render branch uses the block variant (C1); assert `recorded_samples` is reserved after
  `start_recording` (C2); extend the native golden path with audio clip and two-effect chain
  order across save/reload (C9). Plus a CI grep gate for `eprintln!` in the render-reachable
  files, which the backlog already wants and C11 shows the need for.
- **Windows CI never runs the native FFI tests.** The Windows Flutter job builds no engine and
  sets no `BOOJY_CI`, so every native test silently skips on every Windows run. The FFI
  boundary is only tested on macOS. Previously unrecorded.
- **Remove:** `cupertino_icons` (zero call sites); the dead `NoteGestureHandlerMixin` copy of
  the piano-roll gesture code, which has already diverged from the live one (T10) and is a trap
  for any tool work; four dead mixin panel toggles (P8); the duplicate colour picker (P15).
  Flag, don't delete: four orphaned engine API functions with no FFI export and no caller (raw
  MIDI event access and a standalone input capture) in case a future feature wants them.
- **Test usefulness.** Models, commands and controllers assert real behaviour. The three
  native golden-path files are the most valuable tests in the repo and there are only three.
  Widget tests beyond the transport bar are smoke tests. The six VST3 Rust tests print and
  shrug; none asserts output. Core workflows with no protecting test: record end to end, audio
  clips and effects across save/reload, VST3 lifecycle, tempo re-push, device change.
- **Keep `daw_screen.dart` as one file** until a measured problem appears; the twins are the
  problem, not the size.

## 8. Documentation health

Facts mostly have one home. Drift found:

| Doc | Claim | Reality |
| --- | --- | --- |
| README | "punch in/out" | Removed in Unreleased. Must be cut before v0.7.0 tags. |
| BACKLOG | "228 hardcoded `fontSize:`" | 185 literals of 370 uses; 148 already tokenised. |
| BACKLOG | a `PopupMenuButton` in `file_menu_button.dart` | None exists; that file uses `showBoojyMenu`. Residual is two `showMenu` sites in one file. |
| PLATFORMS | "98k lines of Dart, 33 painters" | 89k lines, 32 painters. |
| `.claude/rules/ffi.md` | "no raw pointers in `api/`" | One deliberate, commented exception in `api/vst3.rs:265`. Document it or move it. |
| `.claude/rules/ffi.md`, ARCHITECTURE | "every FFI call serialises on one graph mutex" | Plugin scan and preview don't. The scan is the one that dlopens third-party code. |
| `.claude/rules/build-and-test.md` | symlink text | `build.sh` repoints the symlink and copies the chosen build; no-arg installs debug. |
| ARCHITECTURE | "realtime and offline run the same chain" | Not on the stopped path, and they can run concurrently (C7). |
| Edit menu | "Split at Marker" | Splits at the playhead; the marker was removed in PR #79. |
| Three service files | comments describing a web branch | No web branch exists. |
| `vst3_host.cpp:13` | "includes for main thread check" | No check exists. Directly relevant to C4. |

`docs/dogfood/` is three months stale and unreferenced; the backlog's known-bugs section is the
live mechanism. The `Podfile.lock` diff in the working tree is a CocoaPods version stamp
(1.16.2 → 1.17.0), not a dependency change; commit or pin.

## 9. What this review did not do

No app launch, so nothing is reproduced. No screenshots of the piano roll, audio editor,
recording setup or the busy laptop/monitor comparison; those were assessed from code and pixel
budgets, and anything that turned on a screenshot was filed as suspected. Competitor behaviour
was verified for Ableton and Logic only. The review stops here; direction is yours to choose.
