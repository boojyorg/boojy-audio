# Boojy Audio — Backlog

The one planning document. Accepted behaviour belongs in focused specs and engineering rules;
completed changes belong in [CHANGELOG.md](../CHANGELOG.md). An idea here is not a release commitment.

## Active priority — documentation health

Tyr paused v0.7 “Devices & Feel” on 2026-09-12. No new feature work is scheduled.
Existing completed work remains unreleased; this pause does not revert it or publish a release.

1. Consolidate planning and correct conflicting status claims (this PR).
2. Verify behaviour contracts against code; simplify architecture and engineering guidance.
3. Extract useful decisions and unresolved findings from historical docs, then prune and polish.

Use a separate PR for each pass. Target roughly 3,500–5,000 tracked Markdown lines overall,
without discarding unique requirements, engineering safeguards, licences, or unresolved work.

## Product direction

A beginner-friendly DAW for quickly capturing ideas, recording, editing, mixing, and exporting.
Prefer simple defaults, forgiving edits, progressive disclosure, and a small polished toolset.
Keep the linear arrangement workflow. The existing synth is deliberately one oscillator,
a one-pole lowpass, ADSR, and eight voices; expanding it needs an explicit product decision.

The former “First Sound” direction remains parked: thin presets on existing instruments,
named effect patches, guided first song, Capture Audio, EQ spectrum and reverb quality,
project templates, drum patterns, tempo-synced preview and a loop library. Content comes before
content-dependent onboarding and preview. Old v0.8/v0.9 labels are historical sequencing,
not an active release schedule. v1.0 remains the broader goal; its final gate list needs triage.

## Paused work and decisions

- **Sampler fix package (A7/D6):** waveform origin and Start/Length controls; depends on Tyr's
  sampler research (C2). Preserve per-gesture undo and undoable sample loading. Sampler/drum
  command tests and sampler pitch tests (EH-8/EH-14) accompany this work when resumed.
- **Windows updater (A11/D7):** Dart service and automatic-check Settings checkbox exist;
  `ui/windows/runner/` has no `boojy_audio/updater` MethodChannel implementation. Native wiring
  and a Windows walkthrough remain outstanding. Do not treat the existing checkbox as proof
  of functioning Windows updates. Check macOS automatic-check persistence when revisiting.
- **Zoom (C1, A2/A3):** Tyr's spec must settle anchors, modifiers, pinch, ruler drag, zoom-to-fit,
  horizontal/vertical independence, and the note-height repro before implementation.
- **Hover/motion (B7/N5):** needs Tyr's visual sign-off. Consider hover ~1.02 / press ~0.98
  for navigation/creation surfaces only; avoid latency on transport, tools, faders and M/S/R/I.
- **Overflow affordance (B9):** prior choice was trailing chevron vs right-click; verify current
  behaviour before reopening. Recovery-file card styling was a flex item, not a release gate.
- **CC lane, swing, ghost notes:** verify live reachability and audible behaviour before claiming
  completion. CC editing code exists but the main controls expose velocity and clip automation,
  not a CC expand callback. Swing is a one-shot action if functional; otherwise hide it.
  Ghost notes follow the same keep-or-hide decision. Engine groove is separate deferred work.
- **Branch protection (EH-9):** owner action previously outstanding; verify hosted settings before
  marking done. The end-of-cycle codebase review is paused with the feature cycle; reviews
  remain human-triggered and must not automatically restart feature work.
- **Release verification:** v0.6.1 was skipped; its fixes remain part of Unreleased. The next
  release must verify the v0.6.0 update offer and pass the Windows smoke checklist in AGENTS.md.

### Reconciled status (source inspection, not a runtime certification)

The previous roadmap called entire slices “shipped”, while dreams still listed unfinished work.
Use the changelog for completed changes, and the individual open items above for remaining work.
Capture MIDI, audio duplicate, Legato, velocity toggle, menu consolidation, device/theme work,
MIDI hot-plug and guardrails are recorded in Unreleased; do not add them back as new features.
The former mixer-icon idea is covered by the implemented mixer treatment.

Sources: `ui/lib/services/updater_service.dart`, `ui/lib/widgets/app_settings_dialog.dart`,
`ui/windows/runner/`, `ui/lib/widgets/piano_roll.dart`, and the Unreleased changelog.
The old feature tracker was only partially audited; unchecked entries below are candidates or
verification tasks, not proof that code is absent. A full behaviour audit belongs to pass 2.

## Deferred requirements and candidates

**Previously affirmed for v1.0, now unscheduled:** clip normalize, pan automation (keep its
unsupported picker option hidden), engine swing groove, LUFS platform selector, and localization.
Loop recording / comping was explicitly deferred for later pre-1.0 scoping, not promised now.

| Area | Preserved open work / verification needed |
| --- | --- |
| Recording | Loop recording, comping/take lanes, pre/post-roll; verify recording defaults before promoting audience-doc suggestions into requirements. |
| MIDI | Ghost notes, chord tools, humanize; drum per-step velocity (previously hardcoded at 100), pattern length, variable resolution and choke groups; compound x/8 feel. |
| Audio editing | Clarify merge vs existing join/consolidate; crossfades, transient detection, normalize. |
| Automation | Pan end-to-end support; per-parameter lanes. Volume lanes and undoable point editing already recorded as implemented. |
| Mixing | Sidechain UI, pre-fader sends, folders/linked tracks/summing groups, plugin delay compensation, RMS/LUFS/platform metering; compressor gain-reduction meter and EQ curve—verify current devices first. |
| Tracks | Freeze, bounce in place, templates, markers/locators, arranger sections. |
| Library | File browser, collections, tempo-synced preview; existing search/favourites are not new work. |
| Projects | Backup/version-history UX, templates, collect-all-and-save; verify existing recovery and sample-copy paths before deciding gaps. |
| Export | LUFS platform picker (engine support previously recorded), MP3 ID3 metadata reachability, FLAC. |
| Plugins | Serum/VST3 load/reopen repro and lifecycle hardening, preset browsing reachability, plugin manager, AU; VST2 was a legacy idea, not an accepted requirement. |
| Instruments | Thin synth presets/preset player, sampler workflow research; existing basic synth must not be mistaken for missing functionality. Wavetable/advanced sampler modes need a fresh explicit decision. |
| Usability | High-contrast themes remain hidden pending correctness; secondary-monitor plugin windows, shortcut overlay/customization, undo-history panel, tooltip coverage, tutorial/onboarding. |
| Platforms | Windows hardening; iPad reintroduction was proposed but untested in CI, iPhone not targeted. Linux only if requested; Web remains a strategic question. |
| Hardware | Optional sample-rate selector using supported device rates; continue following device rate by default. ASIO deferred: WASAPI remains beginner default; revisit for demonstrated interface latency needs (SDK/licence/CI prerequisites). |

### Engineering and UI follow-ups

These are inherited candidates; inspect code and later changes before treating old review IDs as open bugs.

- UI: font-size token migration (T10), canvas-background resolution (T11), CC palette readability
  (T7), transport leftovers (X3/X5–X8), zoom-gutter discovery (P8), timeline smalls
  (L3/L5/L6/L8), add-return affordance (M7), start-screen batch (C9–C12, including synchronous
  thumbnail reads), and Master rename/colour reachability.
- Tests/build: adelay VST3 test (EH-13), macOS CMake rebuild in CI (EH-16); when those areas
  change, automation interpolation (EH-6), FFI null-safety (EH-7), tempo re-push (EH-10).
- Guardrails: reconcile EH-1–5/15/17 against merged CI changes before creating further tasks.
- Architecture improvement proposals and export's planned fix still need consolidation in pass 2;
  they are not a second active schedule. Provider remains current; Riverpod needs demonstrated pain.
- Historical EH-12 history purge is recorded complete. Its sibling backup mirror was retained;
  deleting that backup needs a separate deliberate decision, not this docs cleanup.
- Release pipeline (carried 2026-09-07, unverified since June): confirm against the published
  appcast whether Sparkle auto-update actually offered v0.6.0, and whether
  `docs/screenshots/social-preview.png` was uploaded in the repository settings. Reassess both
  before acting; listing them here does not authorise the work.

## Decisions to preserve

- One shared filled-chip dropdown/context-menu surface. Device editors share header/power/
  collapse chrome and MIX placement. Editor height adapts to a compact floor, then clamps;
  do not introduce nested scrolling as a substitute.
- Light-theme readability is required. Inert controls must work or be hidden. The proposed
  extra piano-roll canvas tool badge was rejected; toolbar selection and cursor convey the tool.
- Quiet panel-toggle chrome stands (N6 rejected). No pattern-first workflow, tagging system,
  read/write automation modes, Drummer/Session Player, AI auto-mastering, complex groove pool,
  permanent info panel, or preview key-sync commitment. General detachable app windows were
  excluded; already-supported floating plugin windows are a separate capability.
- Social/cloud/collaboration/share-sheet proposals, automation shapes and step-sequencer swing
  were excluded at June triage; older feature-list entries do not override that decision.
- No speculative tracing migration, Windows smoke rig, gesture-layer widget-test project or
  realtime render-callback tests from the June audit. Keep the actual per-release Windows smoke
  test; the Windows machine is a release test rig, not a development machine.

## Historical evidence

[June triage](reviews/2026_06_12_triage.md) preserves item IDs and product decisions;
[paused v0.7 plan](archive/plans/v0.7-plan.md) preserves detailed acceptance walkthroughs until
pass 2 extracts contracts. These are dated evidence, not current scheduling authority.
Older plans, reviews, and audience research will be assessed in pass 3. Preserve unique decisions
and unresolved findings here or in specs before removing them. Git retains retired planning docs.
