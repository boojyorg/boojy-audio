# Boojy Audio Backlog

The one planning document. Four sections: **Now** (the single active priority), **Next** (what
could follow, verified against code), **Parked** (kept with the reason), **Decisions** (settled,
don't re-raise). Completed work goes to [CHANGELOG.md](../CHANGELOG.md); accepted behaviour goes
to engineering rules and specs. Nothing here is a release commitment.

Every item below was checked against the source tree on **2026-09-13** unless it says otherwise.
Items marked *(Tyr)* need a design call from Tyr before an agent should start.

## Now: every area to 8/10, core first (v0.7.0)

**Status 2026-09-29: back in development.** Work slowed after 2026-09-13 and resumes now; Audio
is not paused. v0.7.0 is the next release, with no date: it ships when its rows reach 8.

### The goal and the scorecard (agreed 2026-09-29)

Every area reaches a solid **8/10: good to great compared with other DAWs**, not "good for a solo
project". Tyr and Claude score together in half points, from using the app and from test
evidence, not from reading code. Grades in older reviews (letter grades, "7.5/10 for an alpha")
are not carried over; they were generous and used different bars. Sounds and effects are scored
on the quality of what exists, not on how many there are.

| # | Area | 8/10 means… | Score | Release |
| --- | --- | --- | --- | --- |
| 1 | Stability & performance | An hour of normal use with no crashes or crackles; CPU in line with other DAWs on the same project | 4 | v0.7 |
| 2 | Recording | Audio and MIDI record first time, you hear yourself without noticeable delay, no take is lost | 2 | v0.7 |
| 3 | Arranging & clip editing | Moving, trimming, splitting, duplicating and looping clips is quick; undo always works | 5 | v0.7 |
| 4 | Piano roll & MIDI | You can draw, edit and quantise notes without fighting the tools | 5 | v0.8 |
| 5 | Instruments | The built-in synth, sampler and drums sound good straight away | 3.5 | Later |
| 6 | Mixing & automation | Levels, pan, sends and automation are clear and dependable | 4.5 | v0.8 (UX) · Later (automation) |
| 7 | Effects & plugins | The built-in effects work and sound good; VST3s load without taking the app down (range not scored) | 5 | v0.8 (UX) · Later (sound) |
| 8 | Sound library | Browsing, previewing and dragging sounds in is quick (size not scored) | 3.5 | Later |
| 9 | Projects & export | Save, reopen, auto-save, crash recovery and export never lose work | 5 | v0.7 |
| 10 | First run & learnability | A beginner makes a beat in 10 minutes without a tutorial, with no dead buttons | 4 | v0.8 |
| 11 | Look & feel | Consistent and calm, fits a laptop screen, feels finished | 6 | v0.8 |
| 12 | Input & accessibility | Every task works with mouse only, trackpad only, keyboard and mouse, and touch; text is readable | 3.5 | v0.8 |
| 13 | Platforms | macOS, Windows and Linux feel the same, and install and update cleanly | 4 | Later |
| 14 | Repo, tests & CI | Bugs are caught before Tyr sees them | 4.5 | v0.7 → v0.8 |
| 15 | Public face | Site, README and release notes are honest and inviting | 4 | v0.8 release |

**First scores: 2026-09-29.** Tyr and Claude, from the two reviews of that date and Tyr's use
of the app. Rows 2 and 15 are Tyr's; the rest are the reviews' opening bids, accepted. Re-score
before each release.

### Releases

- **v0.7.0: the core works every time.** Rows 1, 2, 3 and 9 reach 8, with no known blocker.
  Row 14 gets the test net that makes that measurable. It includes the **editing model**
  ([EDITING.md](EDITING.md)), because the five-tool row is row 3's biggest problem: a
  throwaway Mac and iPad prototype comes first, only its "first version" list is in scope, and
  if the prototype says no or the work balloons, it moves to v0.8.
- **v0.8.0: the app feels right.** UI/UX and bugs, not new sounds (decided 2026-09-29). Rows 4,
  10, 11, 12 and 14, plus the UX half of rows 6 and 7: the precise mixer (fader, unity mark,
  clip warning) and the finished device shell. The 2026-09-29 UI/UX review's v0.8 themes are the
  starting list. The public face (row 15) is refreshed at release: the GitHub page and
  boojy.org/audio.
- **After v0.8: sounds, then Linux.** Once the engine and UX are at or near 8: instruments
  (row 5), the sound library (row 8), effect sound quality (row 7), automation depth (row 6), so
  the parked "First Sound" theme. Then Linux (row 13, see [PLATFORMS.md](PLATFORMS.md)).
  Reason: new sounds are judged through the app around them, so the base comes first.
- **Later: every device.** Boojy should work well, and look and behave the same, on a laptop,
  a desktop, a tablet and a phone. iPad and phone are not scheduled, but every UI change from now
  on follows the touch-ready rules in [EDITING.md](EDITING.md#every-input-method), so the port
  isn't a rewrite.

### Bugs: find them before Tyr does

Bugs are the biggest problem today; Tyr hits them several times a minute while using the app.
Most live where gestures, the UI and the engine meet, and the current tests (about 1,270 Dart,
190 Rust) mostly check logic in isolation: three test files drive the real screen over the real
engine, and nothing runs the live audio callback. The plan:

1. **Workflow tests** for each core task, headless over the real engine (the harness in
   `ui/test/native/clip_drag_overlap_test.dart` is the template): record, drag, trim, split, undo
   many times, save, reopen, compare. They describe outcomes ("the clip ends up trimmed"), not
   the exact clicks, so the editing-model change touches one helper, not every test.
2. **Random stress tests**: thousands of random edits, undos and save/reload cycles, checking
   rules that must always hold (undo restores the exact state, a reopened project matches the
   saved one, nothing crashes).
3. **Audio-safety checks**: tests fail if the audio thread allocates memory or waits on a lock
   (the crackle causes in the 2026-09-13 review), plus offline renders checked for silence,
   clicks and invalid samples.
4. **A failing test before every fix.** A bug found only by reading code is a candidate until
   it is reproduced.
5. **Builds reach Tyr after the suites pass**, so he is the second tester, not the first.
6. **A local log and an audio-dropout counter**, so "it crackled" comes with data.

First, confirm which engine build is being dogfooded: `./build.sh` with no argument installs a
debug engine, which can glitch under load in ways a release build would not.

The 2026-09-13 review's reliability findings (brief §2 and §3, C1–C17) are the starting list for
row 1: none is reproduced yet. Its workspace layout and mixer header options (brief §4 and §6)
are still open and are decided before anything is planned; its editing-tool question is now
answered by [EDITING.md](EDITING.md). The review's individual recommendations are candidates until
accepted here. The paused "Devices & Feel" theme (`docs/archive/plans/v0.7-plan.md`) stays
archived.

### Severity and process

**Severity rule.** *Blocks release*: known data loss, or a core workflow (record, arrange, edit,
mix, save and reopen, export) that does not complete. *Fix before release*: visible and cheap
enough to do now, but the release would ship without it. *After release*: improvements and
polish; they wait for a patch. An improvement does not become a blocker because it was noticed
during the gate.

**Process.**

1. Known bugs are recorded below, classified by the severity rule.
2. The test net above is built early; each fix is one PR: reproduce with a failing test, fix,
   CI green, Tyr's walkthrough, merge. Completed fixes go under Unreleased in the changelog.
3. Tyr dogfoods builds that have already passed the suites; new findings land below.
4. Re-score rows 1, 2, 3 and 9. Release when all four are at 8 and nothing blocks: the checks in
   `RELEASING.md`, the Windows smoke test and the release-day checks below.

**Release-day checks**, on top of `RELEASING.md`:

- Confirm Sparkle actually offers the update: install v0.5.4 or v0.6.0 on a Mac, launch, expect
  the offer. The appcast now carries build number 10 for v0.6.0, so the fix is published but has
  never been observed working.
- Windows smoke checklist. Windows still has **no native updater**: `ui/windows/runner/`
  implements no `boojy_audio/updater` channel, so since 2026-09-13 `UpdaterService.isSupported`
  is macOS-only and the Updates section is hidden on Windows. Confirm it stays hidden.
- macOS "check for updates automatically" is persisted by Sparkle itself, not by app settings.
  Toggle it, relaunch, confirm it sticks.

### Known bugs from dogfooding (2026-09-13)

Classified by the severity rule above. Add to this list as testing continues; the code-check
items under Next are secondary to it and are not release work unless promoted here.

**Blocks release**

- **Audio recording makes empty clips** (Tyr, 2026-09-29, `flutter run` after the Xcode 27
  build). An audio track records a clip with no waveform; macOS never asked for microphone
  permission; MIDI not tried. Found in code so far:
  - The Settings **Input** choice is never applied (review U66); the engine records from the
    macOS default input. Settings showed "No Input" with a Scarlett 2i2 as output.
  - If input capture fails to start, `api/recording.rs` prints a warning to the console and
    records anyway, so the failure is silent and still leaves a clip.
  - Under `flutter run`, macOS attributes microphone access to the terminal that launched the
    app, so a missing prompt can mean the terminal was denied earlier.

  Next: read the `🎙️`/`⚠️` lines in the `flutter run` console, check the terminal under Privacy
  & Security → Microphone, and check the macOS default input's level. Then a failing test. Two
  fixes whatever the cause: apply the Settings input, and tell the user when capture fails
  instead of making an empty clip.
- No other known blockers. (The clip-overlap deletion, transport shrink and ruler zoom fixes
  found on 2026-09-13 are under Unreleased in the changelog, with their regression tests.)

**Fix before release**

- **Cmd+E is bound twice** (review T7): Edit → "Split at Marker" and View → "Show Editor
  Panel" (`daw_menu_bar.dart`). The marker no longer exists (removed in PR #79); the split uses
  the playhead. Check which binding macOS dispatches, rename the item "Split at Playhead", and
  give one of them a different shortcut. The README lists neither until this is settled.
- **The appcast commit can't reach `master`.** `release.yml` ends with a direct
  `git push origin HEAD:master` of `appcast.xml`, and `master` has required a PR and green checks
  since 2026-09-13, so on the next tag the push is rejected and installed Macs are never offered
  the update (they read the feed from `master`, `RELEASING.md`). Options: have the job open a PR
  for the appcast instead, or serve the feed from somewhere unprotected (moving `SUFeedURL` needs
  one last appcast on `master` pointing old installs at the new place). Found in the docs pass of
  2026-09-29; not yet fixed.

**Candidates from the 2026-09-29 reviews** ([UI/UX](reviews/2026_09_29_ui_ux_review.md),
[feature gaps](reviews/2026_09_29_feature_gap_review.md)). Found by reading code and screenshots,
not by use: each needs a failing test before it counts as a bug here (process step 2). IDs point
into the reports.

- *Blocks release if reproduced:* **VST3 effects may drop out of the device chain** (U4). The
  engine reports `name:` and `path:` as text; the Dart parser reads every value as a number, so
  the effect is skipped. Windows `C:` paths break the split too.
- *Fix before release, if reproduced:*
  - **New Project keeps the previous tempo and time signature** (U2). The staged screenshots
    show "Untitled" at 254 BPM.
  - **The toolbar Snap doesn't reach the arrangement** (U1). The arrangement always snaps to the
    zoom grid. Hide the button now; wire it before release.
  - **The volume fader jumps when grabbed** (U3), on the mixer strip and the device strip.
  - **Save As renames before the folder is picked** (U5): cancel leaves the project renamed.
  - **No unsaved-changes signal** (U6). Close always warns, even straight after a save, and
    every save shows a toast. A quiet dot beside the name instead.
  - **The drag-to-create preview drifts when scrolled** (U10); the clip lands in the right place.
  - **Tempo edits flood undo** (U30): one step per scroll notch or tap. **An empty tempo field
    becomes 120** (U29).
  - **"No Input" and "No Output" are never applied** (U66).
  - **Playhead and selected strip vanish in the Light theme** (U7): hard-coded white.
  - **The empty "Sounds" library root** (B3): hide it until it has content.
  - **No Tour or Help on Windows; "Boojy Audio Help" does nothing on macOS** (B6).
  - **MP3 export is promised but needs ffmpeg** (B5): README caveat, and a Windows install line
    in place of `brew` (see the ffmpeg item under Next).

**After release**

- **Automation feels unfinished.** Volume automation works end to end (engine interpolates per
  frame, lane draws, edits undo), so it stays; pan and the clip lane are already hidden. Polish
  is a post-release theme. If a concrete misbehaviour turns up, move it up.

## Next: candidates

### Small, certain fixes (each under a day; found in the code check)

- **Scale highlight is fixed to C major.** The root and type pickers were deleted in the
  2026-09-13 dead-code pass (they were plumbed but never rendered). Bring them back as a small
  feature when the piano roll is next open: two dropdowns in the controls bar.
- **CC lane is unreachable.** Full editing code, but `ccLaneExpanded` is only ever set false; the
  clip-automation lane is behind a constant set to false. Decide: expose one lane toggle, or
  remove the code.
- **Start-screen thumbnails are read synchronously in `build()`** (`project_card.dart`). Move to
  a future/cached load.
- **Tooltip coverage is uneven.** `BoojyTooltip` covers transport buttons and mixer M/S/R;
  piano-roll Quantize/Legato/Snap use the plain Flutter tooltip; track-header Mute/Solo have none.
- **Residual pre-migration menu sites** (verified 2026-09-13): two `showMenu` calls in
  `track_mixer_strip.dart` (`file_menu_button.dart` already uses `showBoojyMenu`, corrected
  2026-09-29). Migrate when that file is next open.
- **UI Labs dev switchers are still in the build** (canvas background, editor-button style,
  playhead lab, palette editor, behind Cmd+Shift shortcuts). Pick winners, promote the tokens,
  delete the switchers. *(Tyr picks.)*
- **Missing-ffmpeg message has no Windows line** (`.claude/rules/audio-export.md`).

### Larger pieces (need Tyr's design input first)

- **Zoom spec** *(Tyr)*: anchor point, modifiers, pinch, ruler drag, zoom-to-fit, whether
  horizontal and vertical zoom are independent, and the note-height repro. One spec, then one PR.
- **Sampler workflow** *(Tyr research)*: the old Start/Length controls were cut by design in
  favour of loop handles on the waveform, and the waveform painter is origin-anchored. Research
  what the sampler should be before touching it again. Keep per-gesture undo and undoable sample
  loading (both exist as commands).
- **Hover/motion language** *(Tyr sign-off)*: candidate hover ~1.02 / press ~0.98 on navigation
  and creation surfaces only; nothing that adds latency on transport, tools, faders or M/S/R/I.
- **Top-bar overflow.** The bar sheds through six density steps and drops labels; there is no
  overflow menu. Since 2026-09-13 nothing shrinks or clips at supported window sizes (see the
  release gate above), so this is now only about the menu: trailing chevron vs right-click.
- **Windows updater** native wiring (see release gate).
- **Font-size tokens.** 185 hardcoded `fontSize:` literals remain across `ui/lib` (review count, 2026-09-13). Migrate to a
  type scale when a theme pass is open; not worth a standalone PR.

## Parked

### "First Sound" theme (chosen June 2026 as the theme after Devices & Feel)

Not part of v0.7.0; the next feature theme is chosen after the release, by review.

Thin presets on the existing synth (Piano/Strings/Bass/Pad/Lead, re-enable the built preset
browser), named effect patches, guided first-song onboarding (tour overlay infrastructure exists
and is wired from the DAW screen), Capture Audio (Capture MIDI shipped; prove the UX first),
EQ live spectrum and a reverb quality pass, project templates, drum-machine preset patterns,
tempo-synced library preview and a loop library. Content comes before content-dependent
onboarding and preview. Judge visual additions like the spectrum against PRODUCT's listen-first.

### Affirmed for v1.0, unscheduled

Clip normalize · pan automation end to end (the picker option stays hidden; the engine never
reads `pan_automation`) · engine swing groove · LUFS platform target in the export dialog (the
engine's `ExportOptions` already supports platform targets and ranges; the Dart dialog exposes
only peak normalize) · localisation · loop recording and take comping (not implemented; the one
engineering-heavy parity gap, scoped pre-1.0).

**Platform prep for v1.0** (decided 2026-09-13, details in [PLATFORMS.md](PLATFORMS.md)):

- **Web:** pure engine render path (no threads or clocks in the renderer) · a `dart:js_interop`
  binding beside `dart:ffi` · AudioWorklet host with a shared-memory ring for playhead and meters
  · origin-private filesystem storage · verify `signalsmith-stretch` builds for WASM. The
  render-path cleanup is worth doing first because it improves the desktop engine too.
- **iPad:** touch-first gesture pass · CoreMIDI channel in Swift · AUv3 is a separate decision.
- **Linux:** packaging decision (AppImage or Flatpak) · a CI job mirroring Windows.

### Feature candidates by area

Ideas with no owner and no date. A candidate's presence here is not a decision.

| Area | Candidates |
| --- | --- |
| Recording | Pre/post-roll; auto-arm a new audio track when a mic is present and show its level; per-track-type effect presets. Already true and not work: loop on, snap to bar, metronome on while recording, input monitoring on for armed tracks. |
| MIDI | Chord tools; note transforms removed as dead code on 2026-09-13 and worth rebuilding as one-shot buttons beside Quantize and Legato (humanize, reverse, stretch, swing); ghost notes from other tracks in the piano roll; drum per-step velocity, pattern length, variable step resolution, choke groups; compound x/8 feel; an arpeggiator (compatible with linear arrangement). |
| Audio editing | Crossfades, transient detection, normalize; clarify "merge" against the existing join/consolidate. |
| Automation | Per-parameter lanes beyond volume. |
| Mixing | Sidechain UI, pre-fader sends, folders/linked tracks/groups, plugin delay compensation, RMS/LUFS metering; a unity tick on faders (not built); an explicit add-return control (returns are created implicitly by the FX picker's shared path). |
| Tracks | Freeze, bounce in place, templates, markers/locators, arranger sections. |
| Library | File browser, collections, tempo-synced preview. |
| Projects | Version history (the half-built `VersionManager` and its dialog were deleted on 2026-09-13; start fresh from the product need, not the old code), templates, collect-all-and-save; one-click export that names the file after the project and opens the folder. |
| Export | FLAC. (MP3 ID3 metadata is shipped and reachable.) |
| Plugins | VST3 load/reopen lifecycle hardening, preset browsing reachability, a plugin manager, AU. |
| Instruments | Thin synth presets (First Sound); wavetable or advanced sampler modes need a fresh product decision. |
| Usability | High-contrast themes stay hidden until their tokens render correctly; secondary-monitor plugin windows; shortcut overlay and customisation; undo-history panel. |
| Platforms | Windows hardening for beta. Linux, web and iPad are v1.0 candidates; the plan and what each needs are in [PLATFORMS.md](PLATFORMS.md). |
| Hardware | Optional sample-rate selector driven by supported device rates (see the cosmetic dropdown above). ASIO deferred; WASAPI stays the default. |

### Engineering follow-ups

Guardrails verified present in CI (2026-09-13): `cargo fmt --check`, toolchain pin,
pubspec-vs-tag gate, Sparkle feed-URL assert, signing key in `$RUNNER_TEMP` with cleanup trap,
DMG-exists assert, no swallowed appcast errors, CompositeCommand round-trip test, transport tap
and latency tests, golden painter tests, sampler pitch tests. Branch protection on master is on
(2026-09-13): PR required, `flutter-checks` and `rust-checks` must pass, no force-push, no deletion.

Still open:

- **No audio-thread logging gate.** `audio_graph/` still contains `eprintln!` calls and nothing
  in CI catches new ones.
- **macOS CI links the committed VST3 `.a` libraries** rather than rebuilding them; Windows CI
  rebuilds with CMake. A C++ change can pass macOS CI without ever compiling.
- **Tests absent:** any test that loads a real VST3 (e.g. the SDK's adelay); sampler and drum-pad
  command tests; an engine automation-interpolation test; a tempo-change re-push test (the
  existing re-push test covers clip trim, not tempo); a dedicated FFI null-safety suite. Write
  each when its subsystem is next open.
- **Release-pipeline checks** carried since June: whether `docs/screenshots/social-preview.png`
  was uploaded in the repository settings. Reassess before acting.
- A backup mirror from the June history purge was retained on disk; deleting it is a separate
  deliberate decision.

### Technical debt

Verified against the tree on 2026-09-12 unless noted.

- **Large files.** Eleven Dart files exceed 50 KB. `daw_screen.dart` (144 KB / 3,972 lines) is
  much the largest, then `timeline/timeline_gesture_layer.dart`, `piano_roll.dart`,
  `track_mixer_strip.dart`, `timeline/timeline_track_list.dart`, `library_panel.dart`,
  `device_chain/device_chain_view.dart`, `track_mixer_panel.dart`, `editor_panel.dart`,
  `timeline_view.dart`, `transport_bar.dart`. The `timeline_view.dart` part-file split worked;
  `daw_screen.dart` is the obvious next candidate. No agreed size target and nothing enforces one.
- **`DraggableControlMixin` does not exist.** Proposed to share knob/slider drag boilerplate.
  Reasonable, unbuilt.
- **MP3 export shells out to `ffmpeg`.** Planned replacement: the `mp3lame-encoder` crate, so
  export has no external runtime dependency. WAV stays the dependency-free format.
- **Test coverage gaps.** Native-engine golden-path tests and Rust stock-effect guards exist.
  Absent: widget tests for critical components beyond the transport bar; visual goldens beyond
  the two painters.
- **Unaccepted proposals, for the record.** Virtualised lists for large clip/note counts; lazy
  library loading; painter-cache tuning; standardised error handling; model codegen; stricter
  lints; ADRs; accessibility (semantic labels, keyboard navigation, screen reader); a widget
  catalogue. None has a measured problem behind it. Require evidence before scheduling.

## Decisions: don't re-raise

- **Punch in/out is out of the UI (2026-09-13).** Removed with the toolbar pass: no menu, no
  I/O keys, no ruler colouring. The engine's punch code stays dormant (never enabled by the UI).
  Re-adding it is a design decision, not a toggle to flip back on.
- **Count-in is Off / 1 bar only, default on, and always clicks** (2026-09-13). The user
  preference is the single source of truth; the value in the project file is ignored on load.
- **The toolbar carries no add-track buttons and no ? button** (2026-09-13). Tracks are added
  from the mixer panel header, the empty-arrangement prompt, Record with nothing armed, or a
  library drag. The shortcuts sheet is under the Audio menu and on the ? key.

- **One shared dropdown and context-menu surface** (filled-chip triggers, `showBoojyMenu`).
- **Device editors share one shell** (header glyph, name, power dot, collapse; visualiser; 2–3
  hero params; fixed MIX knob). The old effect-parameter panel is deleted. Editor height adapts
  to a compact floor then clamps; no nested scrolling.
- **Inert controls work or are hidden.** Applied to high-contrast themes, the pan-automation
  picker option, and now the sample-rate dropdown and menu zoom items above.
- **Light theme must read correctly everywhere.** Shipped in v0.7 slice 1; regressions are bugs.
- **No extra piano-roll canvas tool badge**; toolbar selection and cursor convey the tool.
- **Quiet panel-toggle chrome**; no "active" state treatment.
- **The library browser is one full-width tree, not two columns** (2026-09-13). Root rows have
  icons and labels but no chevrons; subfolders use a chevron in place of a folder icon; several
  roots can be open at once; opening is not selecting. Don't re-add the left category column or
  its divider. Sticky section headers, shared-prefix folding of long sample names and search
  results shown in place in the tree are follow-up candidates, not part of the tree change.
- **No peak-hold marker on meters** (proposed June 2026, not adopted; meters use instant-attack,
  smooth-decay ballistics).
- **Beta ships on macOS and Windows; Linux, web and iPad are v1.0 candidates.** The stack stays
  Flutter + Rust; alternatives were assessed on 2026-09-13 and the stack question is not reopened
  before v1.0 ([PLATFORMS.md](PLATFORMS.md)).
- **Linear arrangement is the primary model.** No pattern-first or clip-launch workflow. Sequencing
  within a track (arpeggiator, drum step sequencer) is compatible ([PRODUCT.md](PRODUCT.md)).
- **Excluded:** tagging system, read/write automation modes, Drummer/Session Player, AI
  auto-mastering, complex groove pool, permanent info panel, preview key-sync commitment,
  general detachable app windows (floating plugin windows are a separate, existing capability),
  social/cloud/collaboration/share-sheet, automation shapes, step-sequencer swing, an always-on
  "enhance" effect chain (listen first: let the musician judge the raw recording).
- **No speculative infrastructure:** no tracing migration, no Windows smoke rig, no
  gesture-layer widget-test project, no realtime render-callback tests. The Windows machine is a
  release test rig, not a development machine.
- **VST2 was never accepted.** AU is a candidate, not a plan.

## History

Reviews and triages are dated evidence in [`docs/archive/reviews/`](archive/reviews/README.md),
including the June 2026 triage that carried the item IDs this backlog used until 2026-09-13.
The paused v0.7 plan is at [`docs/archive/plans/v0.7-plan.md`](archive/plans/v0.7-plan.md).
Never re-open an archived item without re-verifying it against today's code.
