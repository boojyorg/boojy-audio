# Boojy Audio Backlog

The one planning document: **Now**, **Known bugs**, **Test plan**, **Next**, **Later**,
**Decisions**. Finished work goes to [CHANGELOG.md](../CHANGELOG.md); how releases are gated and
shipped is in [RELEASING.md](RELEASING.md). Nothing here is a release commitment. Items marked
*(Tyr)* need Tyr's design call before an agent starts.

## Now: every area to 8/10, core first (v0.7.0)

Every area reaches a solid **8/10: good to great compared with other DAWs**. Tyr and Claude
score together in half points, from using the app and test evidence, not from reading code.
Sounds and effects are scored on the quality of what exists, not how many there are. First
scores 2026-09-29; re-score before each release.

| # | Area | 8/10 means… | Score | Release |
| --- | --- | --- | --- | --- |
| 1 | Stability & performance | An hour of normal use with no crashes or crackles; CPU in line with other DAWs | 4 | v0.7 |
| 2 | Recording | Audio and MIDI record first time, you hear yourself without noticeable delay, no take is lost | 2 | v0.7 |
| 3 | Arranging & clip editing | Moving, trimming, splitting, duplicating and looping clips is quick; undo always works | 5 | v0.7 |
| 4 | Piano roll & MIDI | You can draw, edit and quantise notes without fighting the tools | 5 | v0.8 |
| 5 | Instruments | The built-in synth, sampler and drums sound good straight away | 3.5 | Later |
| 6 | Mixing & automation | Levels, pan, sends and automation are clear and dependable | 4.5 | v0.8 (UX) · Later |
| 7 | Effects & plugins | Built-in effects work and sound good; VST3s load without taking the app down | 5 | v0.8 (UX) · Later |
| 8 | Sound library | Browsing, previewing and dragging sounds in is quick (size not scored) | 3.5 | Later |
| 9 | Projects & export | Save, reopen, auto-save, crash recovery and export never lose work | 5 | v0.7 |
| 10 | First run & learnability | A beginner makes a beat in 10 minutes without a tutorial, no dead buttons | 4 | v0.8 |
| 11 | Look & feel | Consistent and calm, fits a laptop screen, feels finished | 6 | v0.8 |
| 12 | Input & accessibility | Mouse only, trackpad only, keyboard and mouse, and touch all work; text is readable | 3.5 | v0.8 |
| 13 | Platforms | macOS, Windows and Linux feel the same, install and update cleanly | 4 | Later |
| 14 | Repo, tests & CI | Bugs are caught before Tyr sees them | 4.5 | v0.7 → v0.8 |
| 15 | Public face | Site, README and release notes are honest and inviting | 4 | v0.8 release |

- **v0.7.0: the core works every time.** Rows 1, 2, 3 and 9 reach 8 with no known blocker;
  row 14 gets the test net that proves it. Includes the editing model ([EDITING.md](EDITING.md))
  after a throwaway Mac + iPad prototype; if the prototype says no or the work balloons, it moves
  to v0.8.
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

- **No live waveform while recording audio.** `LiveRecordingNotifier` draws MIDI only; needs a
  live peak feed from the engine (new FFI) and a painter. Row 2.
- **Recording with loop on shows a negative playhead** (−0.9s, −1.9s after the loop wraps).
  *(Tyr)* decide what loop-on recording does (stop at loop end, or ignore the loop) first.
- **The appcast commit can't reach `master`** (branch protection). Details and options in
  [RELEASING.md](RELEASING.md#what-the-release-workflow-does).
- **Export showed an error pop-up** (Tyr, 2026-09-30; format and message not captured). Maybe
  the ffmpeg lookup: it's installed in `/opt/homebrew/bin`, which apps opened from Finder
  don't get in their PATH.
- *If reproduced:*
  - New Project keeps the previous tempo and time signature (U2).
  - The volume fader jumps when grabbed (U3).
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
tests don't cover.

1. **Workflow tests** per core task, headless over the real engine (template:
   `ui/test/native/clip_drag_overlap_test.dart`). Describe outcomes, not exact clicks.
2. **Random stress tests**: thousands of random edits, undos and save/reload cycles against
   invariants (undo restores exactly, a reopened project matches, nothing crashes).
3. **Audio-safety checks**: fail if the audio thread allocates or waits on a lock; offline
   renders checked for silence, clicks and invalid samples.
4. **A failing test before every fix.** A bug found only by reading code is a candidate.
5. **Builds reach Tyr after the suites pass**, and new UI is rendered and checked first.
6. **A local log and an audio-dropout counter**, so "it crackled" comes with data.

Dogfood a release engine (`./build.sh release`); the debug engine glitches under load. The
[2026-09-13 review](reviews/2026_09_13_product_review.md) reliability findings (C1–C17) are row
1's starting list; none is reproduced yet.

## Next

- **Scale highlight** (hidden while fixed to C major): bring it back with root and type pickers
  in the piano-roll controls bar.
- **Tooltip coverage is uneven**: piano-roll Quantize/Legato/Snap use the plain tooltip;
  track-header Mute/Solo have none.
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
