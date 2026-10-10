# Boojy Audio Backlog

The one planning document: **Now**, **Known bugs**, **Test plan**, **Next**, **Later**,
**Decisions**. Finished work goes to [CHANGELOG.md](../CHANGELOG.md); how releases are gated and
shipped is in [RELEASING.md](RELEASING.md). Nothing here is a release commitment. Items marked
*(Tyr)* need Tyr's design call before an agent starts.

## Now: every area to 8/10, core first (v0.7.0)

Every area reaches a solid **8/10: good to great compared with other DAWs**. Tyr and Claude
score together in half points, from using the app and test evidence, not from reading code.
Sounds and effects are scored on the quality of what exists, not how many there are. First
scores 2026-09-29, re-scored 2026-10-01 (after #151–#175) and 2026-10-04 (after #177–#185);
re-score before each release and at each state-of-play review ([RELEASING.md](RELEASING.md#milestone-reviews)).

| # | Area | 8/10 means… | Score | Release |
| --- | --- | --- | --- | --- |
| 1 | Stability & performance | An hour of normal use with no crashes or crackles; CPU in line with other DAWs | 4.5 | v0.7 |
| 2 | Recording | Audio and MIDI record first time, you hear yourself without noticeable delay, no take is lost | 5.5 | v0.7 |
| 3 | Arranging & clip editing | Moving, trimming, splitting, duplicating and looping clips is quick; undo always works | 6.5 | v0.7 |
| 4 | Piano roll & MIDI | You can draw, edit and quantise notes without fighting the tools | 5 | v0.8 |
| 5 | Instruments | The built-in synth, sampler and drums sound good straight away | 3.5 | Later |
| 6 | Mixing & automation | Levels, pan, sends and automation are clear and dependable | 5.5 | v0.8 (UX) · Later |
| 7 | Effects & plugins | Built-in effects work and sound good; VST3s load without taking the app down | 5 | v0.8 (UX) · Later |
| 8 | Sound library | Browsing, previewing and dragging sounds in is quick (size not scored) | 3.5 | Later |
| 9 | Projects & export | Save, reopen, auto-save, crash recovery and export never lose work | 6 | v0.7 |
| 10 | First run & learnability | A beginner makes a beat in 10 minutes without a tutorial, no dead buttons | 5 | v0.8 |
| 11 | Look & feel | Consistent and calm, fits a laptop screen, feels finished | 6.5 | v0.8 |
| 12 | Input & accessibility | Mouse only, trackpad only, keyboard and mouse, and touch all work; text is readable | 4 | v0.8 |
| 13 | Platforms | macOS, Windows and Linux feel the same, install and update cleanly | 4 | Later |
| 14 | Repo, tests & CI | Bugs are caught before Tyr sees them | 5.5 | v0.7 → v0.8 |
| 15 | Public face | Site, README and release notes are honest and inviting | 4 | v0.8 release |

- **v0.7.0: the core works every time.** Rows 1, 2, 3 and 9 reach 8 with no known blocker;
  row 14 gets the test net that proves it. Includes the editing model ([EDITING.md](EDITING.md))
  after a throwaway Mac + iPad prototype; if the prototype says no or the work balloons, it moves
  to v0.8.
  **Order (2026-10-04):** the test net first, because Tyr still found three bugs by hand in
  the last walkthrough (Test plan below): screen-and-engine check → CI builds the apps →
  workflow tests through the DAW screen (spike first) → random stress tests. Then dropout
  counter and log (row 1) → the loop in the engine, with loop-on recording decided → multi-track
  takes → projects (Save As, unsaved dot, export error) → editing model prototype.
- **v0.8.0: the app feels right.** UI/UX and bugs, not new sounds: rows 4, 10, 11, 12, 14 and
  the UX half of 6 and 7. Starting list: the [2026-09-29 UI/UX review](reviews/2026_09_29_ui_ux_review.md).
  Public face (row 15) refreshed at release.
- **After v0.8: sounds, then Linux.** Instruments, library, effect sound, automation depth
  ("First Sound", below), then Linux ([PLATFORMS.md](PLATFORMS.md)).
- **Every device, later.** New UI follows the touch-ready rules in
  [EDITING.md](EDITING.md#every-input-method) so an iPad or phone port isn't a rewrite.

## Known bugs

Classified by the severity rule in [RELEASING.md](RELEASING.md#severity-rule). Review findings
(IDs U*, B* point into the [UI/UX](reviews/2026_09_29_ui_ux_review.md) and
[feature-gap](reviews/2026_09_29_feature_gap_review.md) reports) count once a failing test
reproduces them.

**Blocks release**

- *If reproduced:* **VST3 effects may drop out of the device chain** (U4). The engine reports
  `name:` and `path:` as text; the Dart parser reads every value as a number. Windows `C:` paths
  break the split too.

**Fix before release**

- **Piano Roll loop changes aren't undoable.** Its loop Start, Length and loop-ruler drags change
  the clip but add no undo step, so ⌘Z undoes the edit before them instead (the Audio Editor's
  were fixed by making each edit an `EditAudioClipCommand`).
- **Recording onto two armed audio tracks shows only the first take.** The engine records a
  clip on every armed audio track, but the UI adds (and undoes) only the first, so the others
  exist in the engine unseen. `RecordingCompleteCommand` needs to cover several tracks.
- **Recording with loop on shows a negative playhead** (−0.9s, −1.9s after the loop wraps).
  Decided (2026-10-10): recording ignores the loop and carries straight on until Stop, so no
  part of a take is lost.
- **`appcast.xml` still says `minimumSystemVersion` 11.0, but the app now needs macOS 12**
  (CHANGELOG). `release.yml` generates the file (hard-coded in its "Generate appcast.xml" step),
  so fix it there, or Sparkle offers the update to Macs that can't run it.
- **The appcast commit can't reach `master`** (branch protection). Details and options in
  [RELEASING.md](RELEASING.md#what-the-release-workflow-does).
- **Export freezes the window, and its progress bar never moves.** The export runs on the UI
  thread (a blocking FFI call), so the progress polling can't run until it's done; a 20 s song
  freezes Boojy for 20 s. Run it off the UI thread (an isolate) so the bar and Cancel work.
- **MP3 export may not find ffmpeg when Boojy is opened from Finder** (unverified): apps opened
  there don't get `/opt/homebrew/bin` in their PATH (`Command::new("ffmpeg")` in `mp3.rs`).
- *If reproduced:*
  - New Project keeps the previous tempo and time signature (U2).
  - The volume fader jumps when grabbed (U3).
  - The loop's jump back is timed by the UI's 60 fps timer, not the engine, so it can land a
    frame or more late (a stutter at the loop point). The engine should own the loop.
  - **Boojy can't start on a machine with no audio output** (no default output device): the
    audio graph opens the output stream when it starts. Starting without one and saying so in a
    notice would also let `test/native` run on Windows CI, whose machines have no sound card.
  - Undoing a recording doesn't bring back the clips it recorded over: the overlap trims run
    outside `RecordingCompleteCommand` (`_applyAudioOverlap`, `_applyMidiOverlap`).
  - Trimming a MIDI clip's left edge drops the notes before it (`adjustNotesForTrim`), so
    dragging the edge back out shows an empty start; audio clips now keep theirs.
  - "Mute Clip" on a MIDI clip may not silence it: the menu sets a flag that nothing in the
    engine reads.
  - Save As renames before the folder is picked; cancel leaves it renamed (U5).
  - No unsaved-changes signal (U6): a quiet dot beside the name; close warns only when dirty.
  - The drag-to-create preview drifts when scrolled (U10).
  - Tempo edits flood undo (U30); an empty tempo field becomes 120 (U29).
  - "No Output" in Settings may never be applied (U66; the input half was fixed in #153).
  - Playhead and selected strip vanish in the Light theme (U7).
  - No Tour on Windows (B6).
  - MP3 export needs ffmpeg (B5): README caveat plus a Windows install line.

**After release**

- **Automation feels unfinished.** Volume automation works end to end and stays; pan and the
  clip lane are hidden. Polish later unless a concrete misbehaviour turns up.

## Test plan: find bugs before Tyr does

Tyr hits bugs several times a minute; most live where gestures, UI and engine meet, which unit
tests don't cover. The ones that got through (2026-10-04 review) were the screen and engine
disagreeing, untested wiring in the DAW screen, and a test that pinned the wrong behaviour.

1. **Screen and engine agree** (`ui/lib/services/state_consistency.dart`): what the engine
   plays (clips, IDs, positions, trims, warp, pitch, tempo) must match what the screen shows.
   Tests call it after every step; debug builds run it after every undoable action and project
   load, and show a notice on any mismatch.
2. **Workflow tests** per core task through the real DAW screen, headless over the real engine
   (`ui/test/native/support/daw_harness.dart`; examples in `daw_workflow_test.dart`: tempo and
   warp, loop toggle, Duplicate Track, save and reopen). Describe outcomes, not clicks; check (1)
   after every step. Recording workflows need a real input, so they aren't covered yet.
3. **Random stress tests** (`ui/test/native/daw_stress_test.dart`): seeded runs of random edits,
   undos and redos, checked with (1) after each; then undo everything back to an empty project,
   redo it all, and save and reopen, each of which must match. CI runs seeds 1–5;
   `STRESS_SEEDS`/`STRESS_STEPS` run more (1–40 pass).
4. **CI builds the apps**: macOS and Windows debug builds on every PR, so native code can't
   reach a release uncompiled. `test/native` can't run on Windows CI yet: the engine won't start
   without an output device (see Known bugs).
5. **Audio-safety checks**: fail if the audio thread allocates or waits on a lock. Offline
   renders are checked sample by sample (order, clip edges, levels, clicks, export files:
   `engine/src/audio_checks.rs`); the live mix and loop wrap need a sound card, so aren't.
6. **A failing test before every fix**, named for what Tyr expects, not what the code does. A
   bug found only by reading code is a candidate.
7. **Builds reach Tyr after the suites pass**, and new UI is rendered and checked first.
8. **A local log and an audio-dropout counter**, so "it crackled" comes with data.

Dogfood a release engine (`./build.sh release`); the debug engine glitches under load. The
[2026-09-13 review](reviews/2026_09_13_product_review.md) reliability findings (C1–C17) are row
1's starting list; none is reproduced yet.

## Next

- **Scale highlight** (hidden while fixed to C major): bring it back with root and type pickers
  in the piano-roll controls bar.
- **Tooltip coverage is uneven**: piano-roll Quantize/Legato/Snap use the plain tooltip;
  track-header Mute/Solo have none.
- **Move the Audio Editor's loop region in one go:** grab its middle on the ruler and drag
  (`LoopMarkerDrag.middle` exists, unwired). Start now keeps the region's end (2026-10-10), so
  moving a 1-bar loop to bar 3 takes Start then Length. The Piano Roll's Start box still slides
  its region with Length kept; settle one rule when its loop undo is fixed.
- **Two `showMenu` calls remain** in `track_mixer_strip.dart`; migrate to `showBoojyMenu`.
- **MP3 export shells out to `ffmpeg`.** Replace with the `mp3lame-encoder` crate.
- **Zoom spec** *(Tyr)*: anchor, modifiers, pinch, ruler drag, zoom-to-fit, independent axes.
- **Sampler workflow** *(Tyr)*: research what it should be before touching it again.
- **Windows updater**: no native `boojy_audio/updater` channel; the Updates section is hidden on
  Windows until it exists.
- **Engineering gaps**: `eprintln!` in `audio_graph/` with no CI gate; macOS CI links the
  committed VST3 `.a` instead of rebuilding it; no test loads a real VST3; `daw_screen.dart`
  (~2,300 lines, no more mixin duplicates) is the next file to split.

## Later

- **"First Sound" theme (after v0.8):** thin synth presets, named effect patches, guided
  first-song onboarding (tour overlay exists), Capture Audio, EQ spectrum and reverb quality,
  project templates, drum presets, tempo-synced library preview and a loop library. Content
  before content-dependent onboarding.
- **v1.0, unscheduled:** clip normalize; pan automation end to end; swing; LUFS platform targets
  in the export dialog (the engine supports them); localisation; loop recording and take
  comping. Platform prep for web, iPad and Linux is in [PLATFORMS.md](PLATFORMS.md).
- **Input sample-rate conversion.** The input now opens at the engine's rate (48 kHz), which
  most devices offer; one that can't would still crackle. The first open may switch the device's
  rate (a Scarlett left at 44.1 kHz), a short hiccup once.
- **Takes grow a list on the audio thread** (recorder pushes into a `Vec` under a lock). Measured
  on macOS: worst buffer 0.23 ms of 10.7 ms even on a 5-minute take, so not a crackle cause
  today. Revisit with a writer thread if Windows or long takes show otherwise.
- **Real preview for Finder drags:** files dragged from Finder show a one-bar placeholder, not
  their length or notes, because `desktop_drop` only hands over the file on drop. Needs the
  plugin patched (macOS + Windows) or a different package.

## Decisions: don't re-raise

- **Punch in/out is out of the UI** (2026-09-13). The engine code stays dormant; re-adding it is a
  design decision.
- **Count-in is Off / 1 bar, default on, always clicks.** The user preference wins over the
  project file.
- **No add-track or ? buttons in the toolbar.** Tracks come from the mixer header, the empty
  arrangement prompt, Record with nothing armed, or a library drag.
- **One shared dropdown and context-menu surface** (`showBoojyMenu`).
- **One notice system** (`Notices`): hints fade, problems stay, no success messages; neutral
  pill, amber ⚠ only (2026-09-30).
- **Device editors share one shell**; no nested scrolling.
- **Inert controls work or are hidden.**
- **Light theme must read correctly everywhere**; regressions are bugs.
- **No piano-roll tool badge; quiet panel-toggle chrome; no peak-hold marker on meters.**
- **The library is one full-width tree**, not two columns.
- **Beta ships on macOS and Windows**; the stack stays Flutter + Rust until v1.0
  ([PLATFORMS.md](PLATFORMS.md)).
- **Linear arrangement is the primary model**; no pattern-first or clip-launch workflow.
- **Excluded:** tagging, read/write automation modes, Drummer/Session Player, AI mastering,
  complex groove pool, permanent info panel, general detachable windows, social/cloud/share,
  automation shapes, step-sequencer swing, an always-on "enhance" chain.
- **No speculative infrastructure** (tracing migration, Windows smoke rig, realtime callback
  tests). The Windows machine is a release test rig, not a development machine.
- **VST2 was never accepted.** AU is a candidate, not a plan.

Older reviews and plans are in git history (tag `docs-archive-final`); re-verify anything from
them against today's code before reopening it.
