# Boojy Audio Backlog

The one planning document. Four sections: **Now** (the single active priority), **Next** (what
could follow, verified against code), **Parked** (kept with the reason), **Decisions** (settled,
don't re-raise). Completed work goes to [CHANGELOG.md](../CHANGELOG.md); accepted behaviour goes
to engineering rules and specs. Nothing here is a release commitment.

Every item below was checked against the source tree on **2026-09-13** unless it says otherwise.
Items marked *(Tyr)* need a design call from Tyr before an agent should start.

## Now: ship v0.7.0 as a bounded release

Docs health closed on 2026-09-13 (PRs #130 to #138). **v0.7.0 is a release of the work already
completed since v0.6.0 plus the fixes that genuinely block it.** It does not revive the paused
"Devices & Feel" feature theme (archived at `docs/archive/plans/v0.7-plan.md`); nothing from
that plan is added to the release because it was once scheduled.

**Severity rule.** *Blocks release*: known data loss, or a core workflow (record, arrange, edit,
mix, save and reopen, export) that does not complete. *Fix before release*: visible and cheap
enough to do now, but the release would ship without it. *After release*: improvements and
polish; they wait for a patch. An improvement does not become a blocker because it was noticed
during the gate.

**Process, in order.**

1. This backlog records the known bugs and which ones block (below).
2. Fix the known bugs, one PR per coherent fix, zoom separate: reproduce, fix, relevant tests,
   CI green, Tyr's walkthrough, merge. Completed fixes go under Unreleased in the changelog.
3. Tyr dogfoods the combined build; new findings land here, classified by the severity rule.
4. One scoped bug hunt once the known blockers are fixed, covering clip editing and undo, zoom,
   transport, recording, saving and reopening a populated project, and export. Findings are
   verified before they are reported as confirmed bugs. Confirmed blockers are fixed in separate
   PRs. The hunt is timeboxed; a known blocker is never shipped because the timebox expired.
5. Verify and release: the checks in `RELEASING.md`, the Windows smoke test, and the
   release-day checks below.
6. A broader audit afterwards is a separate task to inform future work, not an extension of
   this release.

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

- None open. The clip-overlap deletion found on 2026-09-13 is fixed (a partial overlap left a
  neighbour shorter than 0.25 s, which the resolver deleted instead of trimming; see Unreleased
  in the changelog). Regression coverage: `ui/test/native/clip_drag_overlap_test.dart` drives
  the real drag over the native engine, including undo and redo.

**Fix before release** (would not block on their own; Tyr wants both in this release)

- **Transport centre cluster shrinks its glyphs at narrow widths.** Fixed 2026-09-13 (see
  Unreleased in the changelog): the wells no longer scale, the density ladder measures the
  even-split slots the transport's centre pin creates, and below ~1110 px windows the side rails
  yield (Add-track labels drop, project name truncates) rather than the centre. Regression
  coverage: `ui/test/widgets/transport_bar_density_test.dart` sweeps every width from 960 to
  1600 px. The overflow *menu* (trailing chevron vs right-click) is still the open "top-bar
  overflow" question below; nothing overflows at the supported window sizes now.
- **Ruler drag zoom in the arrangement doesn't feel right** (target: Ableton's beat-time
  ruler). Three concrete gaps in `unified_nav_bar.dart` and `timeline_view.dart`:
  the timeline's zoom handler receives an anchor beat and ignores it, so the zoom pivots on the
  left edge of the view and the bar under the pointer slides away; the factor is linear per
  event with a 2 px dead zone, so the motion is lumpy and asymmetric; vertical and horizontal
  drag are handled as separate steps rather than one continuous gesture. The piano roll has a
  second copy of the same maths (`piano_roll/zoom_mixin.dart`, plus a third in
  `shared/editors/zoomable_editor_mixin.dart`) with a from-start linear factor that saturates
  at 200 px and a scroll correction one frame late, which wobbles. Fix: one shared
  implementation, exponential factor (equal drag = equal ratio both ways), anchor beat captured
  at drag start and held under the pointer with the scroll correction applied in the same
  frame, both axes live throughout. Check the drag direction against Ableton (down = in there;
  Boojy is up = in). The wider zoom spec (pinch, modifiers, zoom-to-fit) stays a separate item.

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
  `track_mixer_strip.dart` and a `PopupMenuButton` in `file_menu_button.dart`. Migrate when
  those files are next open.
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
- **Font-size tokens.** 228 hardcoded `fontSize:` values remain across `ui/lib`. Migrate to a
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

- **One shared dropdown and context-menu surface** (filled-chip triggers, `showBoojyMenu`).
- **Device editors share one shell** (header glyph, name, power dot, collapse; visualiser; 2–3
  hero params; fixed MIX knob). The old effect-parameter panel is deleted. Editor height adapts
  to a compact floor then clamps; no nested scrolling.
- **Inert controls work or are hidden.** Applied to high-contrast themes, the pan-automation
  picker option, and now the sample-rate dropdown and menu zoom items above.
- **Light theme must read correctly everywhere.** Shipped in v0.7 slice 1; regressions are bugs.
- **No extra piano-roll canvas tool badge**; toolbar selection and cursor convey the tool.
- **Quiet panel-toggle chrome**; no "active" state treatment.
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
