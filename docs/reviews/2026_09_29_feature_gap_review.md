# Feature-gap review, 2026-09-29

*Scope: features that are missing. Bugs are covered by the correctness audit and visual polish by the UI/UX review, so neither appears here. Lens: a beginner with no plugins, no samples and no MIDI keyboard. Following the brief, the five-tool row (EDITING.md) and sound or effect quantity are not reported.*

## 1. Executive summary

**Can a beginner make a full song end to end today? Yes, but only a determined one, and it probably won't sound good.** Every step of the core loop exists in code: new project, record audio or MIDI with a count-in, play from the QWERTY keyboard, draw notes, program drums, arrange, mix, draw volume automation, undo, auto-save and export. Nothing needs new engine capability.

The gap is at the start and the end:

- **The start.** A new synth track plays a raw oscillator. The only instrument with good sounds out of the box is the drum kit (29 one-shots). The "Sounds" library row is empty. Nothing starts the tour. Row 10's "beat in 10 minutes" might just be possible with the drum kit. A song with a bassline and chords is not, unless you already know sound design.
- **The end.** MP3, the format a beginner shares, is greyed out on a stock Mac or Windows machine because it needs ffmpeg. Windows users are told to run `brew`.

In short, Boojy is capability-complete for a beginner but has no content or guidance. The four DAW teardowns and both internal surveys agree on this. It matches the parked "First Sound" theme almost item for item, which confirms that theme as the natural v0.8 feature work. The fix is mostly content and wiring, not engineering, so it is sized M–L, not XL.

**Corrections to the survey inputs.** Checked in code today, these change some classifications:
- Tap tempo exists (`tempo_controls.dart`). It is hidden at narrow widths, not missing.
- Clip reverse exists in the audio editor.
- An armed track shows its input level as a faded overlay on its mixer fader (`capsule_fader.dart:17`). The "no input level" gap is therefore "only visible when the mixer is open", not "absent".
- There are 29 bundled WAVs, not 30.
- A `normalizeTargetDb` field exists in the clip model, but BACKLOG still treats clip normalise as not done. I have not checked whether it is reachable in the UI.

**Rejected as gaps.** Several "blocking" inputs describe features Boojy already has: the virtual piano, the mixer, undo, save and auto-save, basic effects, and recording itself. Their problems are reliability, which is rows 1, 2, 3 and 9 and the correctness audit. They are not missing features.

## 2. v1.0-blocking gaps

A gap blocks only if a beginner cannot finish, or cannot get a decent-sounding result, without it. Ranked by beginner impact.

| # | Gap | Why a beginner is stuck | Evidence | Effort |
|---|---|---|---|---|
| B1 | **Named synth presets** (Piano, Keys, Bass, Pad, Lead, Pluck) with the preset browser re-enabled for built-ins | Adding a synth track gives a bare waveform. A beginner picks sounds by name and cannot build a bass from an oscillator, a filter and an ADSR, so every melodic part sounds unfinished. | `engine/src/synth.rs` (one oscillator, one-pole LP, ADSR, no presets); `editor_panel.dart` `_shouldShowPresetNav => false`, `_loadPresets` returns early for non-VST3 instruments; BACKLOG Parked "First Sound" | M |
| B2 | **At least one sampled melodic instrument**: a piano or keys multisample for the sampler, or a preset bank good enough to stand in | Even with synth presets, "Piano" from one oscillator will not pass "sounds good straight away" (row 5). PRODUCT.md's "finish a song with nothing installed" isn't reachable without a real keys sound. | `instrument_browser.dart` lists only Synthesizer, Sampler and Drum Kit; `ui/assets/samples` holds drums only | M (licensing: CC0 or in-house, per the sample-sourcing rule) |
| B3 | **The empty "Sounds" root: fill it or hide it** | A beginner clicks it, finds nothing and concludes the app is broken. It is a dead control under the "inert controls work or are hidden" decision and row 10's "no dead buttons". | `library_service.dart:321` "`empty - not yet implemented`"; `library_panel.dart:291` still lists it | S to hide, M to fill with B1/B2 content |
| B4 | **A first-run path to sound**: a starter or demo project or template, then a tour that auto-starts and teaches "make a beat", not just "where the panels are" | First launch is the start screen, then an empty arrangement. Nothing suggests adding a drum kit and pressing play. This is row 10's bar. | `daw_screen.dart:229` auto-start removed ("tour isn't good enough yet"); `hasCompletedTour` is only written, never read; start screen offers only New and Open | M (BACKLOG: content comes first, so after B1–B3) |
| B5 | **MP3 export with no ffmpeg install** (bundle an encoder, e.g. the planned `mp3lame-encoder`) | MP3 is what gets sent to friends. On a stock machine the option is disabled, and the Windows hint says `brew install ffmpeg`, which is a dead end. The README says "WAV or MP3" with no caveat. | `engine/src/export/mp3.rs` shells out to `ffmpeg`; `export_dialog.dart:466-470, 919-924` | M (cross-platform native build is the risk) |
| B6 | **Tour and Help reachable on Windows, and "Boojy Audio Help" working or hidden** | On Windows there is no route to any onboarding or help. On macOS, "Boojy Audio Help" does nothing. | `daw_menu_bar.dart:337-351` (PlatformMenuBar only; the Help handler is a comment); `app_menu_button.dart:62-70` offers only Settings, Shortcuts and Start Screen | S |
| B7 | **Scale highlight: a root and type picker, or hide the toggle** | Outside C major the "Scale" toggle highlights the wrong notes, so the helper actively teaches mistakes. | BACKLOG "Scale highlight is fixed to C major"; pickers deleted 2026-09-13 | S (the pickers existed before) |

**Affirmed for v1.0 by earlier decision, but not beginner-blocking.** Loop recording and take comping, clip normalise, pan automation end to end, the LUFS target in export, and localisation. From a beginner's point of view none of them stops a song being finished. Loop recording and comping (L–XL) is the one to challenge. Single takes plus undo get a beginner through a vocal. GarageBand does have cycle takes, so it is a real parity point, but it is the most expensive item on the v1.0 list and serves intermediate users. I recommend keeping it on the v1.0 list but doing it after B1–B7, and cutting it from v1.0 if schedule pressure comes. This is a high-stakes scope call, so it is Tyr's.

## 3. Nice-to-have backlog (ranked by beginner impact ÷ effort)

| Rank | Feature | Impact | Effort | Note |
|---|---|---|---|---|
| 1 | **Drum-kit starter patterns** (3–5 genre grooves) | High | S–M | Turns "blank grid" into "press play". Parked under First Sound. The fastest win for row 10. |
| 2 | **Named effect patches** (Vocal, Warm, Big Room, Echo) on the six stock effects | High | M | Beginners can't read EQ or compressor parameters. Parked under First Sound. Different from the excluded always-on "enhance" chain, because it is opt-in. |
| 3 | **Clip fade-in and fade-out handles** | Med–High | M | Trimmed vocals click, and the only workaround is volume automation, which beginners won't find. BandLab and Soundtrap both have handles. First check whether the engine already applies de-click edge fades; if it doesn't, that is a row-1 sound-quality item for the correctness audit. |
| 4 | **One-click "Export song"**: named after the project, opens the folder | Med | S | Makes the finishing moment easy. BACKLOG Projects candidate. |
| 5 | **Small starter loop set** (drums, bass, chords at a fixed key and tempo) plus tempo-synced preview | High | L | This is BandLab and Soundtrap's main beginner draw. It needs B3's library to be meaningful. |
| 6 | **Tap tempo always reachable**, not only at wide widths | Low–Med | S | It exists but drops out on narrow layouts. |
| 7 | **Auto-warp dropped audio to project tempo** (BPM detection on import) | Med | L | Only valuable once loops exist (rank 5). A grep found no detection. |
| 8 | **Tooltips on track-header Mute and Solo; remove UI Labs dev switchers** | Med | S | Row 10 learnability. Overlaps the UI/UX review, so it is listed here only for completeness. |
| 9 | **Auto-arm a new audio track when a mic is present; input level in the track header** | Med | M | The level already shows on the mixer fader, so this is about visibility, not new capability. |
| 10 | **Drum per-step velocity and pattern length** | Low–Med | M–L | Depth for users who stick with it. |
| 11 | **Arrangement markers and sections** | Low | M | Clips already act as visual markers. Fixing the stale "Split at Marker" label is a correctness-audit item. |
| 12 | **Undo-history panel** | Low | M | Cmd+Z already covers beginners. |
| 13 | **Tuner** | Low–Med | M | Useful for guitarists. Not in BACKLOG. Add as a candidate only if Tyr wants it. |
| 14 | **Windows native updater** | Med (trust) | L | Row 13 and platform work, not a music-making feature. Already in BACKLOG. |

## 4. Out of scope (don't re-raise)

These are deliberate. Most are already in BACKLOG's "Excluded" list or the platform plan.

- Drummer or Session Player virtual musicians, AI auto-mastering, and an always-on "enhance" chain (listen first).
- Cloud save, sharing, collaboration, share sheet and social upload.
- Browser, web or phone versions for v1.0. Web, iPad and phone are "later" per PLATFORMS.md.
- Read and write automation modes, automation shapes, and per-parameter automation lanes beyond the affirmed pan work.
- Complex groove pool, step-sequencer swing and a tagging system.
- Sidechain UI, groups, folders, pre-fader sends, plugin delay compensation and RMS/LUFS metering.
- Pattern-first or clip-launch workflows (linear arrangement is the model; Live Loops-style is out).
- Auto-Tune-style pitch correction. It conflicts with listen-first, and nobody has asked for it.
- CC lanes in the piano roll as a beginner feature (velocity covers it). The unreachable CC lane is a dead-code or correctness item.
- VST2. AU stays a candidate, not a plan.
- More effect types or more instruments for their own sake. Row 7 and row 5 score quality, not range.
- Punch in and out (removed 2026-09-13; re-adding it is a design decision).

## 5. Comparison on beginner essentials

| Essential | GarageBand | BandLab | Soundtrap | FL Studio | **Boojy** |
|---|---|---|---|---|---|
| Good sound the moment you add an instrument | Yes (huge preset library) | Yes | Yes | Yes (100+ presets) | **Drums only** (B1, B2) |
| Loops to drag in | Yes (Apple Loops) | Yes | Yes | Some | **None** |
| Play without MIDI hardware | Musical Typing | On-screen | QWERTY and on-screen | Typing keyboard | **Yes** (virtual piano) |
| One-click beat | Drummer, Beat Sequencer | Drum machine | Beatmaker | Channel Rack | **Yes** (starter kit, step grid; no patterns) |
| Record with count-in and hear yourself | Yes | Yes | Yes | Yes | **Yes** (reliability unproven, row 2) |
| Take comping | Yes | Limited | Limited | Yes | **No** (affirmed v1.0) |
| Effect presets | Yes | Yes | Yes | Yes | **No** |
| Clip fades | Automation | Handles | Handles | Yes | **No** (automation only) |
| Scale help | Yes | No | No | Yes | **C major only** (B7) |
| Templates and first-run guidance | Yes | Yes | Yes | Yes | **No** (tour exists, off) |
| Undo, auto-save, crash recovery | Yes | Cloud | Cloud | Undo | **Yes** |
| Export MP3 out of the box | Yes | Yes | Yes | Yes | **No** (needs ffmpeg) |
| Free, local, private, cross-platform desktop | macOS only | Web-first | Web-first | Paid | **Yes**: Boojy's real edge |

Boojy wins on fundamentals and positioning: free, local, desktop on macOS and Windows, command-pattern undo, and crash recovery. Every competitor wins on content and first ten minutes. Nothing in the loss column needs an engine rewrite.

## 6. Where each gap lands

v0.7 is reliability (rows 1, 2, 3 and 9 plus the editing model). Feature gaps belong there only when they are cheap and remove a false claim or dead control.

| Gap | Row | Recommended release | Alternative, and what it costs |
|---|---|---|---|
| B6 Windows Tour and Help; hide the inert "Help" item | 10, 13 | **v0.7** (fix before release, S) | Wait for v0.8: v0.7 ships with a dead menu item on macOS and zero help on Windows, against the "inert controls work or are hidden" decision. |
| B5 MP3 export: **README caveat plus Windows-correct message** | 9, 15 | **v0.7** (S) | Skip it: the public README keeps overclaiming, and Windows users are sent to `brew`. |
| B5 MP3: **bundled encoder** | 9 | **v0.8** | Do it in v0.7: a native cross-platform build risk lands inside a reliability release. |
| B3 "Sounds" root: **hide now** | 8, 10 | **v0.7** (S) | Leave it: a visible dead root row in the release. |
| B3 fill Sounds, B1 synth presets, B2 keys instrument | 5, 8 | **v0.8**: the First Sound theme's core | Pull into v0.7: splits attention from rows 1–3, the stated gate, and BACKLOG already sequences content after the release. |
| B4 first-run path (template or demo plus auto-tour) | 10 | **v0.8, after B1–B3** | Before the content: a tour that teaches with a raw oscillator, which is why auto-start was pulled. |
| B7 scale picker | 4 | **v0.8** (or hide the toggle in v0.7, S) | Leave it: the helper misleads in every key but C. |
| Drum patterns, effect patches, one-click export, tap tempo reachable | 5, 7, 9, 11 | **v0.8** | Later: row 10's 10-minute beat stays hard to hit. |
| Clip fades | 3 | **v0.8** (a check for de-click edge fades goes to the correctness audit now) | v0.7: expands row 3 while the editing model is already changing it. |
| Loop library, auto-warp on import | 8 | **Later / v1.0** | v0.8: an XL content job that would crowd out B1–B4, which do more per hour. |
| Loop recording and take comping, pan automation, LUFS target, clip normalise | 2, 6, 9 | **v1.0 (affirmed), after v0.8** | Earlier: the most expensive items serve intermediate users first. |
| Windows updater | 13 | **v0.8** (with Linux) | Earlier: platform work competes with reliability. |

**Recommended next feature theme (v0.8): "First Sound".** In order: B1, B2 and B3 content → drum patterns and effect patches → B4 first-run → B7 and one-click export → B5 encoder. It re-activates the parked theme almost unchanged, so no new planning doc is needed; promote it from Parked when v0.7 ships. For v0.7 itself, add only the three S items (B6, the B5 doc and message fix, hiding the Sounds root) to "Fix before release".
