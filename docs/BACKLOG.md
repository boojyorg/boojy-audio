# Boojy Audio Backlog

The one planning document. Four sections: **Now** (the single active priority), **Next** (what
could follow, verified against code), **Parked** (kept with the reason), **Decisions** (settled,
don't re-raise). Completed work goes to [CHANGELOG.md](../CHANGELOG.md); accepted behaviour goes
to engineering rules and specs. Nothing here is a release commitment.

Every item below was checked against the source tree on **2026-09-13** unless it says otherwise.
Items marked *(Tyr)* need a design call from Tyr before an agent should start.

## Now: documentation health

Tyr paused the v0.7 "Devices & Feel" feature theme on 2026-09-12. The three docs passes
(consolidate planning · one home per fact · rewrite this backlog against code) are complete
with this PR. **The next priority is Tyr's choice**; the recommended pick is the release below,
because three months of finished work is sitting unreleased and the update path has never been
exercised end to end.

## Next: candidates

### Release v0.7.0 (recommended)

Everything in the changelog's Unreleased section has been done since v0.6.0 on 2026-06-11,
including the v0.6.1 fixes that were never tagged. Release gate, on top of `RELEASING.md`:

- Confirm Sparkle actually offers the update: install v0.5.4 or v0.6.0 on a Mac, launch, expect
  the offer. The appcast now carries build number 10 for v0.6.0, so the fix is published but has
  never been observed working.
- Windows smoke checklist. Windows still has **no native updater**: the Dart service and the
  Settings toggle exist, but `ui/windows/runner/` implements no `boojy_audio/updater` channel.
  Either wire it before release or make sure the toggle is hidden on Windows.
- macOS "check for updates automatically" is persisted by Sparkle itself, not by app settings.
  Toggle it, relaunch, confirm it sticks.

### Small, certain fixes (each under a day; found in the code check)

- **Project sample-rate dropdown is cosmetic.** The engine always requests 48 kHz stereo and
  falls back to the device default only if that fails; the 44.1/48 picker in Project Settings
  changes metadata only. Per the "inert controls work or are hidden" decision: hide it, or make
  it real.
- **Menu-bar Zoom In / Zoom Out / Zoom to Fit are disabled placeholders.** Same rule. Zoom that
  does exist: Cmd-scroll, ruler drag, nav-bar buttons, middle-drag in the piano roll. No pinch.
- **Scale toggle has no scale picker.** The piano-roll Scale highlight works, but the root and
  type pickers are plumbed and never rendered, and Project Settings lost its key/scale fields in
  v0.7. Users can highlight a scale they cannot choose. Render the two pickers in the controls bar.
- **Ghost notes render but cannot be switched on.** The painter and state are wired; no visible
  toggle exists (a dead `piano_roll_scale_controls.dart` carries one and is imported nowhere).
  Add the toggle and delete the dead widget.
- **Swing is dead code.** The `applySwing` operation exists and nothing calls it; there is no
  control to hide. Delete it, or wire it as a one-shot action beside Quantize and Legato.
- **CC lane is unreachable.** Full editing code, but `ccLaneExpanded` is only ever set false; the
  clip-automation lane is behind a constant set to false. Decide: expose one lane toggle, or
  remove the code.
- **Start-screen thumbnails are read synchronously in `build()`** (`project_card.dart`). Move to
  a future/cached load.
- **Tooltip coverage is uneven.** `BoojyTooltip` covers transport buttons and mixer M/S/R;
  piano-roll Quantize/Legato/Snap use the plain Flutter tooltip; track-header Mute/Solo have none.
- **Residual pre-migration menu sites** (verified 2026-09-12): two `showMenu` calls in
  `track_mixer_strip.dart`, a `PopupMenuButton` in `file_menu_button.dart`, a local `_showMenu`
  in `view_menu_button.dart`. Migrate when those files are next open.
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
- **Top-bar overflow.** The bar shrinks through six density steps and drops labels; there is no
  overflow menu. If that ever fails at a real window size, the open question was trailing
  chevron vs right-click. Not needed until it fails.
- **Windows updater** native wiring (see release gate).
- **Font-size tokens.** 228 hardcoded `fontSize:` values remain across `ui/lib`. Migrate to a
  type scale when a theme pass is open; not worth a standalone PR.

## Parked

### "First Sound" theme (chosen June 2026 as the theme after Devices & Feel)

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

### Feature candidates by area

Ideas with no owner and no date. A candidate's presence here is not a decision.

| Area | Candidates |
| --- | --- |
| Recording | Pre/post-roll; auto-arm a new audio track when a mic is present and show its level; per-track-type effect presets. Already true and not work: loop on, snap to bar, metronome on while recording, input monitoring on for armed tracks. |
| MIDI | Chord tools, humanize; drum per-step velocity, pattern length, variable step resolution, choke groups; compound x/8 feel; an arpeggiator (compatible with linear arrangement). |
| Audio editing | Crossfades, transient detection, normalize; clarify "merge" against the existing join/consolidate. |
| Automation | Per-parameter lanes beyond volume. |
| Mixing | Sidechain UI, pre-fader sends, folders/linked tracks/groups, plugin delay compensation, RMS/LUFS metering; a unity tick on faders (not built); an explicit add-return control (returns are created implicitly by the FX picker's shared path). |
| Tracks | Freeze, bounce in place, templates, markers/locators, arranger sections. |
| Library | File browser, collections, tempo-synced preview. |
| Projects | Backup/version-history UX, templates, collect-all-and-save; one-click export that names the file after the project and opens the folder. |
| Export | FLAC. (MP3 ID3 metadata is shipped and reachable.) |
| Plugins | VST3 load/reopen lifecycle hardening, preset browsing reachability, a plugin manager, AU. |
| Instruments | Thin synth presets (First Sound); wavetable or advanced sampler modes need a fresh product decision. |
| Usability | High-contrast themes stay hidden until their tokens render correctly; secondary-monitor plugin windows; shortcut overlay and customisation; undo-history panel. |
| Platforms | Windows hardening; iPad was proposed but is untested in CI; Linux only if asked; Web is a strategic question, not a plan. |
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
