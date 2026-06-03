# Changelog

All notable changes to Boojy Audio will be documented in this file.

## Unreleased

### Bug Fixes

- **Splitting a clip and undoing no longer destroys part of it (C52/C63/C64).** This was data loss:
  undoing a MIDI clip split left only the left half on the track and **permanently discarded the
  right region of the original**, and a split audio clip kept playing its right half and its
  full-length left half after undo. The split commands were piggy-backing on the
  copy/delete actions, which quietly re-numbered clips and ran overlap-trimming — so undo could never
  line things back up. Split is now one clean, fully reversible step: both halves are removed and the
  **complete** original clip is restored, in the timeline *and* the audio engine.
- **All three ways to split a clip now behave the same.** The slice tool, the right-click menu, and
  the Cmd+E shortcut were three separate implementations with different bugs — the right-click and
  Cmd+E splits couldn't be undone at all, and Cmd+E on an audio clip didn't even reach the audio
  engine until the next save/reload. They now share one undoable, engine-synced split.
- **Undo no longer silently swallows an action that fails (C66/C86).** If a command's undo or redo
  threw, the manager used to discard it entirely — the entry vanished from the history with no
  trace, and the stacks were left corrupt. It now keeps the command on its stack when the operation
  fails, so the history stays intact and the action can be retried.
- **Opening a broken project no longer pretends it worked (C73/C77).** A failed engine load (corrupt
  `project.json`, missing referenced files) was treated as success: the app rendered an empty/half-
  loaded state, adopted the bad folder as the current project, and a later auto-save could overwrite
  it on disk. A failed load now surfaces the error and leaves your current project — and its path —
  untouched.
- **Projects saved at a non-default tempo reopen on the grid (C72).** MIDI notes were restored using
  the stale default tempo (120) before the engine's real tempo synced, so a project saved at e.g.
  140 BPM reopened with every note shifted off the beat. Tempo is now synced before notes are
  restored, on both normal open and crash recovery.
- **Consolidate is now undoable (C53).** Consolidating several MIDI clips into one bypassed the undo
  system, so pressing Cmd+Z afterwards undid some unrelated earlier action instead. It's now a single
  undo step that restores the original clips.
- **Deleting notes in the piano roll is now undoable (C54).** Deleting a multi-note selection ran
  without recording an undo entry, so Cmd+Z did nothing and the notes were gone for good. The delete
  is now captured in history.
- **Undoing a track deletion brings the track's content back (C62/C68/C76/C97).** Deleting a track
  and pressing Cmd+Z used to recreate an empty shell — your MIDI clips, audio clips, effects, and
  sends were gone, and a redo left a ghost track behind. Undo now restores the track's clips (MIDI
  and audio), its full effect chain in order — **built-in effects *and* VST3 plugins/instruments
  (e.g. Serum), with their exact state** — sends, and mixer state, and redo cleanly removes the
  recreated track. *Known limits, surfaced when they apply:* tweaked built-in-synth parameters
  aren't recovered (a fresh default synth comes back with the track), a VST3 plugin that's been
  moved or uninstalled since the delete can't be reloaded (you're told which), and the track may
  reappear at the end of the list rather than its original position.
- **VST3 plugins follow the activation protocol (C30).** The host never called the mandated
  `IComponent::setActive()` before processing (and never deactivated on teardown), so strictly
  compliant plugins — including Steinberg's own — could output silence or crash. The host now
  activates and deactivates each plugin in the correct order.
- **VST3 preset/program changes are now heard, not just shown (C34).** Selecting a factory preset
  updated the plugin's editor but never reached the audio processor, so the name changed and the
  sound didn't. The change is now delivered to the processor.
- **VST3 restart requests are no longer silently dropped (C35).** The host acknowledged every plugin
  `restartComponent` request without inspecting it. It now decodes the flags and logs them;
  on-the-fly bus/processing reconfiguration (a rare path) remains deferred.

### Features

- **The built-in EQ is now a graph you draw on.** The old EQ was five flat sliders (four band gains
  + a Mix slider) with no sense of what they did. It's been rebuilt as a **Graphic EQ**: a
  frequency-response graph with draggable dots. A new EQ starts with three sensible Low / Mid / High
  bands (all flat, so it does nothing until you touch it); drag a dot left/right to choose the pitch
  range and up/down to boost or cut. Click a dot to edit it with **Freq / Gain / Focus** knobs (Focus
  sets how wide or narrow the band is), double-click a dot to remove it or the empty graph to add
  one, and use **+ Add Band** for up to eight bands. There are fixed **Low Cut** / **High Cut**
  switches to remove rumble and harsh highs, and an **Output** trim. Every action — drag, add,
  remove, cut, output — is a single undo step, and the whole EQ saves and reloads with your project.
  Existing projects' EQs load flat (no data loss). *Out of scope by design (reach for a VST3 plugin):*
  no Mix knob on the EQ, no spectrum analyser, no adjustable filter slopes.

### Improvements

- **The arrangement canvas is a refined dark grey instead of near-black.** The timeline background
  was an almost-black `#0C0E11`; it's now a slightly lifted `#1C1D21` for a more polished look, with
  the bar/beat grid lines nudged a touch brighter so they stay visible against it. Coloured clips
  (green MIDI, grey waveforms) still pop.
- **Arrangement-view polish pass — consistency and unfinished edges.** A round of small visual fixes
  so repeated elements get one treatment everywhere: the top-bar Loop / Grid / Metronome buttons now
  share a single height (Grid no longer sits taller); the sidebar-toggle icons match the help `?`
  glyph's lighter grey instead of reading darker; the editor tool buttons (draw/select/erase/…) now
  show the same hover feedback as the top bar; the library search field is squared off and slimmed to
  match the `+ MIDI/Audio Track` buttons and no longer clips its placeholder to `Searc…`; the
  favourite star is a quiet grey rather than a loud gold; and the editor's collapse chevron is a bare
  glyph instead of a boxed button.
- **The dB readout beside each mixer fader is now editable.** It used to be a dead label. Now you
  can **drag it up/down** to nudge the volume precisely (a finer touch than the fader), or **click
  it and type an exact value** (e.g. `-6`) — Enter or clicking away applies it, Esc cancels. Works
  on track strips and the master, and every change is a single undo step.
- **EQ / Compressor / Limiter now compute their filters at the real device sample rate (C12).** These
  effects baked in 48 kHz; they now take the actual stream rate, so their coefficients are correct on
  the rare device that can't open at 48 kHz. (The wider engine still targets 48 kHz — a full
  variable-rate engine remains future work.)
- **The UI Scale setting now scales the whole app — including the rulers and lanes (B-TH3).**
  Custom-drawn surfaces (the timeline ruler, piano-roll note labels, sampler ruler, knob readouts)
  used to ignore the Appearance → UI Scale setting: their text stayed frozen while everything else
  grew. They now scale with it, so "Large" actually enlarges every label.
- **Themed surfaces no longer paint dark bands on a light shell (B-TH4).** Every custom-drawn
  surface now follows the active theme instead of hardcoding dark-theme colours — the piano-roll
  lanes, timeline grid, velocity lane, note labels, meters, knobs, and automation lanes. This is the
  groundwork that lets the Light and High-Contrast themes render correctly rather than as dark
  patches with invisible text.
- **The piano roll is easier to read at a glance.** The key gutter now has bright off-white naturals
  and near-black sharps (so it reads as a keyboard), C is marked as a distinct shade for finding
  octaves, the root-note row gets a visible accent band plus a left tick, and note labels fall back
  to a single pitch letter when a note is too narrow for the full name instead of disappearing.
- **High-Contrast Dark now actually boosts contrast (B-TH6).** It used to reuse the normal dark
  theme's accent, so picking it changed nothing about the accent; it now uses a brighter, more
  saturated blue.
- **One green, one set of colours across the app (B-TH1).** The app had two different greens
  fighting on adjacent meters and signal indicators; they're now a single cool emerald defined once
  in the theme. The snapshot, version, and capture dialogs — which used to hardcode their own warm
  grey palette that clashed with the cool app — now follow the active theme, as do dozens of stray
  `red`/`amber`/`white` colours that were typed in by hand. Every level meter (fader, device strip,
  level bar) now reads its green/yellow/red zones from one shared definition, so they can't drift
  apart. Groundwork for the Light and High-Contrast themes to actually look right.

- **Recording stays off the audio thread's danger paths (C1/C2/C3).** Three realtime-safety holes
  the playing path had already been hardened against, fixed on the recording and stopped paths: the
  not-playing render callback re-locked the effect and track managers *per sample* (now locked once
  per buffer with the same try-lock + contention-counter treatment); the recorder read its state,
  tempo, and time-signature with blocking locks *per sample* (now try-locked); and the recorder
  emitted `eprintln!` console I/O on the audio thread during count-in, punch, and every second of
  recording (removed). Net effect: fewer dropouts/xruns when you tweak tempo or add an effect while
  recording or while live-monitoring stopped.

- **The test suite can no longer lie (C92).** The native-engine integration tests used to
  silently early-return when the engine library was missing — so a CI run that forgot to build the
  engine would still print "9 tests passed" while testing nothing. They now fail loudly under CI
  when the engine is absent, and report as *skipped* (not passed) locally. Internal only — no
  user-facing change, but it means every other fix this cycle is actually being measured.
- **CI now rejects Rust warnings for real (C95).** `cargo clippy` in CI was non-fatal despite the
  docs claiming it gated warnings; it now runs with `-D warnings`, and the 13 warnings that had
  quietly accumulated behind the non-fatal gate were cleaned up.

### Internal

- **Headless golden-screenshot tests** for the piano-roll lane painter and the timeline grid
  painter (`ui/test/goldens/`). They render the painters to PNG under plain `flutter test` (no
  device) so visual regressions in the upcoming legibility work fail the suite instead of slipping
  through; refresh with `fvm flutter test --update-goldens test/goldens/`. Compared on macOS only.
- **`ui-ux-review` screenshot grounding fixed.** The review workflow now grounds its subagents on a
  committed staging folder (`docs/reviews/_screenshots/`) instead of the ephemeral pasted-image
  cache, so future UI reviews actually see the app.
- **Feature-tracker accuracy sweep:** re-marked input monitoring and the two automation items
  `(partial)` — engine support exists but no user-reachable UI.

## v0.4.0 — 2026-06-01

> **"Visual & UX polish."** A real bundled typeface (Inter + JetBrains Mono), a unified cool
> "gunmetal" palette, a persisted UI Scale control, edge-to-edge macOS chrome, a restyled piano
> roll and centred transport, and a dogfood polish batch — plus two pre-tag fixes (VST3 instruments
> reopen with sound; the top bar no longer overflows in a narrow window). Folds in the earlier
> quick-win bug batch (no separate v0.3.3 release).

### Features

- **MIDI keyboards now "just work."** Boojy listens to your keyboard automatically, picks one up
  even when you **plug it in after launch** (it re-checks whenever you return to the app or arm an
  instrument track, with a brief "🎹 *name* connected" confirmation), and **remembers your choice**
  between sessions. Settings → MIDI now has a real device picker (with a rescan button) for when you
  have more than one keyboard — replacing the old placeholder. Under the hood, switching devices now
  actually re-routes the live notes (previously the picker would have had no effect).
- **UI Scale setting (Settings → Appearance).** Choose Compact / Default / Comfortable / Large to
  scale the whole interface at once — for high-DPI displays where the UI felt too small. Persists
  across launches.

### Improvements

- **Removed Sentry crash reporting (for now).** It was unblocking nothing pre-beta — you're the only
  user, and the local error handlers still print crashes to the console during dev. Removing it also
  fixed a macOS build failure: `sentry_flutter` 9.x ships a Swift Package Manager layout that
  doesn't resolve under this project's CocoaPods build. We'll re-add telemetry deliberately at beta,
  when external testers' crashes actually matter. The first-launch crash-reporting opt-in dialog is
  gone with it.
- **Recording resumes on the beat, with a visible count-in.** Continuing a paused take now snaps the
  resume point to the nearest beat so the count-in lands cleanly on "1, 2, 3, 4", and the playhead
  **sweeps through the count-in pre-roll** toward the record point instead of sitting frozen until
  recording begins (a first take at bar 1 stays put, since there's no room before it). Applies to
  both MIDI and audio takes — it's part of the shared transport flow.
- **Editor toolbar buttons match the rest of the app.** The Instrument/MIDI tabs and the piano-roll
  tool palette (draw / select / erase / duplicate / slice) now show the selected one with an
  accent **outline + soft tint** — the same "engaged" look as the top bar's Loop / Snap buttons —
  instead of a heavier solid-blue fill, so the whole interface reads as one design language.
- **Quantize now looks like an action, not a toggle.** It previously wore the same outlined pill as
  the Snap/Loop toggles beside it, so it looked like an on/off switch that was off. It now carries
  an accent magnet glyph and briefly **flashes when pressed** (then settles back), making it clear
  it *applies* quantization rather than turning something on. Establishes a consistent rule:
  outline = toggle, fill = selection, glyph + press-flash = action. The left chrome (▲udio wordmark, undo/redo,
  Library toggle) now sits on a fixed rail, so it no longer shrinks or shifts — and the wordmark no
  longer clips — when you collapse the Library. Both side rails share one width, which keeps the
  play / stop / record cluster locked to the centre of the window even when the Library and Mixer
  are different widths. The redundant **(+)** add-track button has left the top bar (use the
  type-coloured add buttons in the mixer header and track list), and the Mixer toggle now sits next
  to **Help** at the far right.
- **New ▲udio wordmark.** The top-left logo is now a clean **▲udio** lockup — a filled triangle as
  the "A" (which still opens Settings, as the old dot did) followed by "udio" — replacing the
  previous "Audi" + floating-dot composition. It scales and themes cleanly and truncates gracefully
  when the window narrows.
- **Track FX buttons use the themed effects icon.** The effects-chain button on each track and the
  Master strip showed a stray yellow emoji (⚡); it now uses the same lightning icon as the Library's
  **Effects** browser, in a muted theme colour (brightening to accent on hover) instead of system
  yellow.
- **Piano-roll lanes read like a keyboard (phase 2).** The grid's white- vs black-key rows were
  nearly the same grey; black-key rows are now noticeably darker for a clear keyboard read. The root
  note (the tonic — C by default, or whatever the scale picker is set to) gets a faint accent-blue
  **root band** so "home" is glanceable, and the pitch row under your cursor lights up as an
  **active lane** with an accent edge — so the piano roll now shows which note you're about to draw.
  The accent stays low-opacity so the notes keep their contrast on top.
- **Transport readout remembers Bars / Time / Both (phase 2).** Clicking the position readout now
  cycles through three modes — bars (`1.1.1`), time (`0:00.000`), and a stacked **Both** (bars over a
  smaller min:sec line, Logic-style) — instead of silently toggling bars↔time. The choice persists
  across launches.
- **Pinned "you are here" bar on the arrangement ruler (phase 2).** Scroll the timeline away from
  the start and a small chip pins to the left of the ruler showing the bar at the left edge, so you
  always know where in the song you're looking. It stays hidden until you've scrolled past bar 1.
- **macOS window chrome is now edge-to-edge (phase 3).** The redundant native title strip that sat
  above the transport bar is gone — the app's own top bar runs to the very top of the window, with
  the traffic-light buttons sitting cleanly within it. This reclaims vertical space and removes the
  left-aligned duplicate window title. *(Internally this also lands a debug-only "UI Labs" switcher,
  Cmd+Shift+L, now offering all four candidate top-bar layouts live — A inline, B LCD panel,
  C two-row (with a centred project title), and D compact-bar + a position/time readout pinned to
  the arrangement ruler — for choosing the final look. It is not part of release builds.)*
- **macOS title strip with a centred project title (phase 3 cont.).** A thin strip now sits above
  the transport bar holding the traffic lights and a window-centred `Untitled — Boojy Audio`
  title — in the native macOS system font, styled to read as one seamless piece of chrome with the
  bar below it. Because the strip spans the whole window, the title is *genuinely* centred (the
  earlier in-bar attempt was wedged between unequal sidebar/mixer widths, so it always drifted).
  With the lights moved up into the strip, the transport bar drops its ~78px traffic-light inset and
  the ▲udio wordmark sits at the true left edge.
- **Cleaner transport tool buttons (phase 3 cont.).** The Loop button is now a single plain pill
  when looping is off (the stray `|` next to it is gone); turning Loop on reveals the punch-in/out
  zone, opened via an accent chevron. When **any** of Loop / Snap / Metronome is engaged it now wears
  a soft accent-blue outline with a full-height accent divider between its two halves, so "this tool
  is on" reads at a glance — and a 1px grey sliver that used to peek through the rounded corners is
  gone. The ▲udio wordmark also nudges up ~2px to sit in line with its neighbours.
- **Record is always live (phase 3 cont.).** The record button is no longer dimmed when nothing is
  armed — pressing it with no armed track now drops a small **New MIDI Track / New Audio Track**
  menu, then creates that track (undoable), arms it, and starts recording (with count-in). One press
  to capture an idea on a blank project. Audio-track creation also now goes through the same
  undoable command as MIDI (previously it bypassed undo).
- **Tidier transport readouts + tap-tempo folded into the BPM box (phase 3 cont.).** The
  `1.1.1` / tempo / `4/4` readouts now share one height and padding so the cluster reads as an even
  row. The standalone **Tap** pill is gone — tap-tempo now lives *inside* the tempo box as a split
  button: `[ 120 │ BPM ]`. The number half drags / scrolls / double-clicks to type as before; the
  **BPM** half is the tap target (tap it in time and it pulses accent to set the tempo). The box
  keeps a fixed width so it doesn't jitter as the tempo changes digits. The off-state outline of
  the Loop / Snap / Metronome buttons is also lifted to a clearer grey, so a disabled tool's outline
  reads with the same weight as an engaged (blue) one.
- **The ▲ logo is now the engine-health light; the "Ready" badge is gone (phase 3 cont.).** The
  top-right "✓ Ready" badge restated what you already knew, so it's removed. Instead, if the audio
  engine fails to start, the ▲ in the **▲udio** wordmark turns **red** — a quiet, always-visible cue
  that something's wrong — and clicking it (it already opens **Settings**) is where you fix the audio
  device. When everything's fine the corner stays clean and the logo keeps its brand blue.
- **Cleaner top bar + Add Track in the mixer (phase 3 cont.).** Four small refinements to the
  workspace chrome:
  - **The top bar reads as one clean band.** The two faint vertical lines that boxed in the
    transport controls are gone; the sidebar and mixer can still be resized by dragging their
    boundary just below the bar.
  - **Add a track from the mixer.** The mixer's (previously empty) header now has explicit
    **+ MIDI Track** and **+ Audio Track** buttons — the mixer is where your tracks live, so it's
    where you add them. The labels shorten to **+ MIDI** / **+ Audio** when the mixer is narrow.
    The top-right **(+)** and dragging an instrument onto the timeline still work when the mixer is
    closed.
  - **Friendlier empty project.** The blank arrangement now shows an instrument icon, and the whole
    prompt lights up — *"Drop it here to add your new track"* — when you drag a sound over it.
  - **Tidier library search.** The search field is slimmer, giving the row back to your Favorites
    and categories (search is a quick filter here, not the main way around a small library).
- **Bundled typefaces.** The UI now ships **Inter** (interface) and **JetBrains Mono** (numeric
  readouts — transport, tempo, position, time) instead of falling back to system fonts, for a
  consistent, more premium look across platforms.
- **Unified dark palette.** The top bar and sidebar were a warm charcoal sitting on a cool
  blue-black content area; the whole dark theme is retuned to one near-neutral **"gunmetal"**
  dark-grey ramp (a faint cool undertone) so chrome and content belong together. The accent blue is
  unchanged. (Graphite / Slate / Indigo ramps are available to A/B live via the Cmd+Shift+P palette
  dev tool.)
- **Deeper, cooler shadows** on menus, tooltips and floating surfaces (new elevation tokens).
- **Start screen & settings now show the live ▲udio wordmark.** The launcher's "Boojy Audio" logo
  was a near-black raster that vanished on the dark panel; it's rebuilt in code as white "Boojy"
  (with the amber dot) over the same **▲udio** lockup as the top bar. The settings footer's stale
  "Audi●" art is replaced by the same shared wordmark, so the three can no longer drift.
- **Transport is centred in the top bar.** Play/stop/record now pin to the centre, with the
  modifier and readout clusters flanking them, instead of drifting with the side-panel widths.
- **Piano-roll Loop/Snap match the transport bar.** They now use the same outlined chip with a soft
  accent tint when engaged (Quantize keeps the shared shape as a momentary action), instead of a
  solid blue block.
- **Add-Track buttons gained type icons and colour.** "+ MIDI" / "+ Audio" (mixer header and the
  empty-arrangement prompt) now carry a piano / waveform icon and hover in their track-type colour
  (green for MIDI, grey for Audio).
- **Larger, re-centred macOS window title.** The "Untitled — Boojy Audio" strip text is ~10% larger
  and nudged to sit vertically centred against the traffic lights.

### Bug Fixes

- **VST3 instruments load with sound again after reopening a project.** A plugin loaded from a saved
  project was always treated as an *effect*, so MIDI routed to a VST3 *instrument* (synth/sampler)
  produced silence until you reloaded it by hand. Boojy now reads the plugin's real type when it
  loads — the same detection used when scanning your plugins — so "save a song with a soft-synth,
  reopen it tomorrow" just works. (Also fixes the type for instruments on first load, and the
  rebuilt host library is now a universal arm64 + Intel binary.)
- **Top bar no longer overflows in a narrow window.** Shrinking the window past a certain width made
  the transport bar paint a debug "overflow" stripe; its left/right sections now shrink together so
  the transport stays centred and the stripe is gone.
- **Pausing a recording started at bar 1, then resuming, no longer skips a bar.** When a take began at
  (or near) bar 1, the 1-bar count-in had nowhere to pre-roll, so it played "in place" and left the
  transport one bar ahead of the recorded music. Stopping hid this (it returns to the record start),
  but pausing kept the offset — so the continued take started a bar late, leaving a gap between
  clips. Pausing now pulls the playhead back to the true musical end, so resume continues seamlessly
  (and its own count-in pre-rolls correctly). Mid-timeline takes were unaffected and stay that way.
- **Play button now turns into Pause while recording.** When a take rolled (count-in or recording),
  the transport button kept its green "play" look even though clicking it paused the take. It now
  shows the amber pause affordance throughout playback, count-in, and recording — matching what the
  button actually does. Recording state lives separately from playback state, so the icon was only
  tracking plain playback and missed the recording-rolling case.
- **Pause/Play no longer gets stuck on the pause icon.** After pausing, the play/pause button stayed
  showing "pause" and wouldn't resume from the current position (only Stop unstuck it). The transport
  bar was only rebuilding off the 60fps playhead notifier, which `pause()` silences — so it never
  re-rendered to the paused state. It now also rebuilds on the playback controller's discrete
  play/pause/stop changes. (Also hardened the engine side: play/pause/stop now apply in the exact
  order pressed, instead of a deferred-on-contention path that could let a queued pause land after a
  later play.)
- **Pause button is now amber, not orange.** While playing, the pause affordance read as the *same*
  orange as the Stop button sitting right beside it; it's now amber so "hold" stays visually
  distinct from "stop".
- **The signature box no longer paints a 1px overflow stripe.** At certain window widths the
  position / tempo / signature readout cluster sat a sub-pixel past its slot (the two equal-width
  centre slots can't both fit the wider readout side); it now scales that fraction away invisibly.
- **Notes can now be resized in Select mode.** Dragging a note's edge in the piano roll's Select
  tool resizes it (with a resize cursor on hover), matching the Draw tool — previously edge-drags
  in Select mode only moved the note.
- **Delete sometimes did nothing on a selected clip.** Selecting a clip now pulls keyboard focus to
  the timeline, so Delete/Backspace reliably deletes it instead of leaking to whatever panel was
  last focused; a root-level fallback covers the edge cases.
- **Piano-roll notes stay legible on dark track colours.** Note brightness is now floored (and
  capped) so a very dark or near-white track colour no longer renders near-invisible or washed-out
  notes; velocity shading is preserved.
- **Track dB readout no longer wraps to a second line** at −10 dB and below — tightened the
  readout's side padding (track and master strips).

- **The app reported the wrong version (v0.3.0).** `pubspec.yaml` had drifted behind the shipped
  release and the in-app version label (About box, start screen, settings footer) reads it via
  `PackageInfo`. Bumped (now v0.4.0) and added `ui/pubspec.yaml` to the Version Sync checklist so it
  stops drifting.
- **The "About" box was a placeholder** ("Audio / Version M6.2"). It now shows "Boojy Audio" and the
  real bundle version; the app-menu About/Quit items are named "Boojy Audio" too.
- **The start screen's "Settings" button did nothing** — it closed the launcher and opened nothing.
  It now opens settings and returns to the launcher afterwards.
- **The piano-roll zoom-out button showed an "X" (close) icon** instead of a minus.
- **Tempo could be scrolled or dragged up to 999 BPM** while the type-in dialog and tooltip capped
  it at 300. All tempo inputs now clamp to 20–300 BPM consistently.
- **Velocity-lane bars were always cyan**, ignoring the track colour. They now take the track/clip
  colour (brightening with velocity), matching the notes in the roll.
- **The MIDI clip colour picker used raw Material swatches** unrelated to the app's palette. It now
  uses the curated Boojy track colours.
- **The "Drag to create loop" hint was nearly invisible** (~2.5:1 contrast); raised to a readable
  muted tone.

## v0.3.2 — 2026-05-30

> **v0.3.2 — "plugins & the audio thread."** The realtime cluster from the 2026-05-29 review:
> VST3 plugins are now processed a whole buffer at a time instead of one sample at a time (the
> single critical glitch), landed on top of a hardening safety net (NaN guard, denormal flush,
> stereo/sample-rate validation, plugin-thread fixes) plus a set of live plugin/clip UI fixes.

### Performance

- **VST3 plugins glitched and underran the moment they did real work.** The engine drove the
  whole effects path one sample at a time — for every plugin, on every sample, a separate
  Rust↔C++ `process()` call that allocated buffers and took a lock (~48,000×/second per plugin).
  The render loop (`renderer.rs` for playback, `offline.rs` for export) now processes each track
  in sub-blocks: it fills a per-track scratch buffer, then runs the FX chain once per block via
  `process_block`, so a plugin processes a whole buffer per call with sample-accurate MIDI
  offsets. Built-in effects are unaffected (their per-buffer path is a `process_frame` loop, so
  output is bit-identical — pinned by new equivalence tests); VST3 instruments (e.g. Serum) and
  VST3 effects get the real win. Sub-blocks are capped at 512 frames to respect the plugin's
  initialised max block size. (The transport-stopped monitoring path still processes per-sample;
  that's a separate follow-up.)

### Bug Fixes

- **A misbehaving plugin or denormal blow-up could blast full-scale noise.** Nothing sanitized
  the mixed output before it reached the audio device — the master limiter even passes NaN
  straight through (`NaN > threshold` is false, so its gain stays 1.0). Every output sample is
  now clamped to `[-1, 1]` and non-finite values are replaced with silence at the device
  boundary (`renderer.rs`).
- **Reverb/delay tails spiked CPU on Intel/Windows.** Denormalised floats in the feedback paths
  are 10–100× slower to process on x86. The audio callback now flushes denormals to zero
  (FTZ/DAZ) for its duration on x86_64 (Apple Silicon already flushes by default).
- **Playback could be pitched-up or channel-scrambled on non-48 kHz / non-stereo devices.** The
  engine inherited the device's default format while all time-math assumes 48 kHz stereo. It now
  explicitly requests a stereo 48 kHz stream when the device supports it (the common fix for
  devices that *default* to 44.1 kHz), lays out frames by the stream's real channel count instead
  of assuming stereo, and logs a clear warning when a device can't provide stereo 48 kHz. (True
  sample-rate conversion for 48k-incapable devices is still to come.)
- **Opening a plugin editor during playback could crash.** Editor attach extracted a raw plugin
  handle and attached *without* the per-plugin lock, racing the audio thread's `process()` on the
  same instance. Attach now goes through the locked path (the same mutex `process_block` holds),
  while still dropping the graph/effect-manager locks so plugin callbacks can't deadlock
  (`api/vst3.rs`, `vst3_host.rs`).
- **Incoming MIDI CC poked a main-thread plugin object from the audio thread.** The CC handler
  called `setParamNormalized` on the edit controller (a UI-thread object) from `process()`. That
  call is removed; the CC still reaches the processor via the thread-safe parameter-change queue
  (`vst3_host.cpp`).
- **Dragging a MIDI clip onto an occupied spot left overlapping, double-triggering clips
  (H-8).** The drag-create path skipped overlap resolution that the record/copy paths run.
  It now resolves overlaps at the new position like every other clip-creation path.
- **Deleting a track leaked its floating plugin windows (H-9).** Track deletion didn't close
  the track's floated VST3 editor windows — a native-window resource leak plus a dangling
  editor id. Deletion now closes them.
- **Floating plugin windows didn't hide when switching tracks (M-3).** The per-track
  show/hide of floating editor windows only ran on some selection paths. It now runs on every
  track selection, so only the selected track's plugin windows are visible.
- **Dragging a clip over a neighbour destroyed it un-undoably, and undo didn't move audio
  clips back (H-11).** Two entangled bugs: the audio move command updated the engine but not
  the on-screen clip list, so Ctrl+Z left the clip stuck at the moved spot; and the overlap
  resolution that trims/removes/splits the overwritten neighbour was applied outside the undo
  system entirely. Both audio and MIDI clip moves now compose the overlap destruction into the
  same undo step as the move, so a single Ctrl+Z restores **both** the moved clip and the
  overwritten neighbour (and redo re-applies it). Audio clip deletion also now restores the
  engine's offset/duration on undo, so re-overlapping an already-trimmed clip round-trips
  exactly.

### Improvements

- **Removed dead code (#7).** Deleted never-referenced leftovers verified to have zero live
  callers: the entire `DAWBuildMixin` (an unused status-bar / collapsed-mixer-bar / latency
  builder), the `FxChainView` + `EffectCard` widgets, `models/timeline_item.dart`, the unused
  `audio_clip_gestures.dart` + its barrel, and the dead state classes / calculators in
  `midi_clip_gestures.dart` (kept only `adjustNotesForTrim`, which the overlap handler uses). No
  behaviour change — `flutter analyze --fatal-infos` and the full test suite stay green.

## v0.3.1 — 2026-05-30

> **v0.3.1 — trust/correctness hardening ("don't lose my work").** A cluster of *silent*
> data-loss and undo-corruption bugs found in the 2026-05-29 whole-app review. None threw an
> error — they quietly betrayed edits on paths a dogfooding musician hits every session.

### Bug Fixes

- **Exports were mono.** The offline-export master-pan stage used a wrong matrix that summed
  both channels into each output (`temp_l = L*pan_left + R*pan_left`), so every bounce came out
  dual-mono and ~3 dB hot — what you heard during playback didn't match the WAV. Replaced with
  independent per-channel gain, matching the realtime renderer (`offline.rs`).
- **Redo undid the wrong thing (effects / returns / audio clips).** Removing an effect, return,
  or audio clip then Undo→Redo left the item *still processing audio* while the UI showed it
  gone: undo recreated the engine object with a **new** id but each Remove command kept the
  **old** id, so the reused execute()-on-redo path no-op'd against a stale id. Each command now
  tracks its current live id and updates it on undo (`effect_commands.dart`, `send_commands.dart`,
  `clip_commands.dart`). Covered by new execute→undo→redo regression tests.
- **Undoing an effect removal silently re-ordered the signal chain.** `RemoveEffectCommand`
  ignored `effectIndex` and re-inserted the effect at the *end* of the chain on undo, changing
  the sound. It now restores the effect to its original position via the sibling chain order.
- **Non-4/4 projects reopened in 4/4.** The engine hardcoded the time-signature numerator to 4
  on save and never restored it. It now persists/restores the real numerator (`project.rs`); the
  display denominator round-trips via `ui_layout.json` and is re-applied (numerator re-pushed to
  the engine) on load.
- **Recorded MIDI CC was dropped on save.** The `ControlChange` serialization arm was a no-op,
  so sustain / mod-wheel / expression you recorded vanished on reload. CC events now serialize to
  a new per-clip `midi_cc` field (back-compat via `#[serde(default)]`) and are restored alongside
  the notes.
- **MIDI clips lost their metadata on reload.** Clips were rebuilt purely from the engine (which
  stores no UI fields), so name reverted to "MIDI Clip" and colour / content offset / loop / mute
  / pattern link / clip automation were lost. UI metadata now persists via `ui_layout.json`
  (mirroring audio clips) and is merged back onto the engine-rebuilt clips by `(trackId,
  startTime)` — notes stay single-sourced in the engine.
- **A multi-clip drag took one undo step per clip.** Dragging several selected clips created N
  separate undo entries, so one Ctrl+Z reverted only one clip. The per-clip move commands are now
  wrapped in a single `CompositeCommand` (both the audio and MIDI drag handlers). *(Making the
  destructive overlap-resolution on a move undoable followed in v0.3.2 — see H-11 above.)*

### Improvements

- **Tests for the data-loss cluster**: new `send_commands_test.dart` (the only command family
  with none) plus execute→undo→redo regression tests for effect/return/audio-clip removal; a
  `ui_layout.json` round-trip test for MIDI-clip metadata + time signature; and engine tests for
  time-signature persistence and recorded-CC serialize/restore (incl. an old-project
  back-compat load).

## v0.3.0 — 2026-05-25

### Bug Fixes

- **Reverb was effectively silent (sends inaudible)**: the Freeverb was mis-scaled — `room_size` fed the comb feedback directly (≈0.5, far too low to resonate) and the wet output was attenuated ~36 dB, so a 100%-wet reverb returned only ~0.1% of its input energy. Used as an insert at 30% wet this read as "subtle"; used as a 100%-wet send return it was silent. Mapped `room_size`→feedback (0.7–0.98) and `damping`→0.4 range and corrected the wet gain, so the reverb now produces a present tail (and existing inserts sound fuller/longer). Covered by a new `reverb_full_wet_produces_comparable_output_energy` engine test and the export golden-path test.
- **Sends lost after save → quit → reopen**: `restore_from_project_data` recreated each track via `TrackManager::create_track`, which assigned fresh sequential IDs. Sends were restored with the *saved* `target_track_id`, so when the new return came in at a different new id, every send pointed to a phantom id and the renderer dropped the signal. Now the restore runs in two passes: first creates all tracks while building a save-id → new-id map, then applies sends using the remapped target IDs.
- **Audio clips silently dropped on project reload**: the API `load_project` attached restored audio clips to `track_data.id` (the saved track id) instead of the fresh id assigned by `create_track`. With the new IDs no longer matching the saved IDs, every WAV/MP3 clip went to a phantom track and disappeared. The id_map produced by `restore_from_project_data` is now returned and reused to remap clip attachments. (MIDI clips were unaffected because they're restored inside the per-track loop where the new id is in scope.)
- **Save dialog produced double-slash paths**: macOS `osascript` returns folder paths with a trailing `/`, and the Save flow joined it with `/$projectName.audio`, producing `…/Projects//Name.audio`. The Load flow already stripped the trailing slash — the Save flow was missed. Mirrored the strip so saved paths are clean.
- **Mixer fader unresponsive on regular tracks**: track-reorder wrapper used `onPan*` (any direction) for its drag gestures, which won the gesture arena over the fader's `onHorizontalDrag*` — even purely horizontal drags routed to reorder, so the slider never moved. Switched the wrapper to `onVerticalDrag*` (reordering is vertical-only), letting the fader's horizontal gesture win. Master/return strips were unaffected because they aren't wrapped in the reorder gesture detector.
- **Shared reverb deadlock**: ⚡ → Shared → Reverb no longer freezes the window. `get_track_sends` was holding the source-track lock while walking `TrackManager::get_track`, which re-locks every track to compare its id — `parking_lot::Mutex` is not re-entrant, so the moment a source track gained its first send the iterator hit the held lock and the engine froze. Snapshot the sends list and drop the source lock before resolving return names.
- **Audio renderer allocated memory every sample once a send existed**: the per-frame return-bus accumulator was a fresh `vec!` inside the sample loop, so the audio thread heap-allocated thousands of times per second whenever a return track was present — a realtime-safety violation that risks clicks/dropouts under load. Hoisted it to a reused buffer (`clear()` + `resize()`) alongside the renderer's other pre-allocated scratch buffers, restoring the "no allocations in the hot path" discipline.

### Features

- **Send/return buses (v0.3)**: ⚡ FX picker on mixer strips — insert effect on track or shared send to built-in return bus (Reverb, Delay, EQ, etc.); send rows with amount knob; return section pinned before Master; undo for send amount, add/remove send, delete return
- **Edit return effects**: clicking a return strip now selects it and opens the Editor Panel with the return's effect chain — same interaction as regular tracks. Lets you tweak the shared reverb's room size, decay, damping, etc.
- **Hidden master timeline row**: Master arrangement row hidden by default; show via View → Show Master Row or when master automation exists; persisted per project

### Improvements

- **Flutter 3.44 / Dart 3.12 toolchain**: upgraded from 3.35 (local) / 3.38 (CI); pinned via FVM (`ui/.fvmrc`) and matched in `.github/workflows/*.yml`. Migrated the FX-chain reorder to the new `onReorderItem` callback (replaces deprecated `onReorder`; framework now handles the index adjustment). Material/Cupertino package decoupling deferred — `material_ui` is still preview (0.0.1) and in-SDK imports are not yet deprecated in 3.44.
- **Stock-effect output guards**: added energy/finite sanity tests for EQ, Compressor, Delay, Limiter, and Chorus (mirroring the existing reverb guard) so a mis-scaled built-in effect can no longer ship silent or blow up undetected — the coverage gap that let the reverb regression through.
- **Realtime logging hygiene**: the per-buffer lock-contention warnings in the audio render callback no longer do blocking stderr I/O — they increment atomic counters instead. Informational engine chatter (device selection, render progress) now goes through a debug-only `dlog!` macro, so release builds stay quiet; genuine errors still print.
- **DSP divide-by-zero guards**: clamped the EQ filter Q, the compressor attack/release times, and the compressor ratio at their division points, so a pathological parameter value can no longer produce a NaN/Inf that poisons the master bus. (The energy tests catch a dead output, but not a transient NaN — these guards close that gap.)
- **Undo for time signature & track colour**: changing the time signature (from the menu or the drag) and recolouring a track now go through the command stack, so **Cmd+Z** reverts them like every other edit. A time-signature drag coalesces into a single undo step (matching the send-knob / position-scrubber pattern), and undoing a colour change on a track that had no override restores the auto colour. Covered by new `SetTimeSignatureCommand` / `SetTrackColorCommand` unit tests.
- **Engine test coverage**: added an offline-render round-trip test (multi-track + send/return bounced to a buffer, asserted finite and non-silent) — the export/bounce renderer previously had no coverage at all — plus a multi-track, multiple-sends-to-one-return save→reload integration test.
- **Smoother audio-file drag from the Library**: dragging a sound onto the arrangement no longer stutters, the ghost clip shows its waveform *while you drag*, and dropping is no longer followed by a blank-then-pop delay. Causes fixed: (1) the preview waveform used to decode the *whole* file synchronously on the first hover, freezing the UI for the length of the decode (a multi-minute MP3 could stall for seconds) — it now decodes on the engine's background thread (new `preview_is_fully_decoded` signal) and the ghost waveform appears as soon as the file is available and fills in as it decodes (the engine recomputes streaming peaks until decode completes, instead of caching a half-decoded preview); (2) the drag handlers rebuilt the entire timeline on every mouse-move frame (~60 Hz) — they now skip the rebuild unless the ghost clip's snapped position or track actually changed; (3) on drop, the clip now appears immediately with a quick low-res waveform and sharpens to full resolution one frame later, so the heavy peak computation (up to 240k points) no longer blocks the clip's first paint.

## v0.2.4 — 2026-05-22

### Improvements

- **Windows CI**: `windows-latest` jobs run `flutter analyze`, `flutter test`, and `cargo clippy` on every PR (no VST3 build)
- **Timeline decomposition (phase 1)**: Extracted `timeline_gesture_layer.dart` and `timeline_track_list.dart` from `timeline_view.dart` (~3800 lines moved via `part` files; zero behavior change)
- **Undo gaps closed**: VST3 plugin parameter drags go through `SetEffectParameterCommand`; clip-move undo covered by integration test
- **MIDI clip move sync**: `set_clip_start_time` now updates global MIDI clip storage; engine queries prefer track placement for authoritative start times

## v0.2.3 — 2026-05-22

### Improvements

- **Project persistence centralized**: UI layout save/load now goes through `ProjectPersistence.collect()` — single checklist for panel layout, loop region, track colors, view state, automation, and timeline clips in `ui_layout.json`
- **Integration tests (golden paths)**: Native engine smoke tests for MIDI track save/reload, MIDI note persistence, and WAV export under `ui/integration_test/` (skipped when `libengine` is not built)
- **Undo audit (partial)**: MIDI clip move/trim, mixer fader/pan/mute/solo, and device-chain effect parameter drags now go through `UndoRedoManager` / `Command`

## v0.2.2 — 2026-05-22

### Improvements

- **Arrangement background**: Warm charcoal background (#0E0F14) replaces deep blue-black, more professional studio aesthetic
- **Remove star field**: Animated star background removed from arrangement view
- **Piano roll controls simplified**: Controls bar trimmed to CLIP + GRID groups only; Scale, Transform, Lanes accessible via sidebar
- **Piano keyboard redesign**: Black keys visually shorter (~80% width) like a real keyboard; every key labeled with note name, C notes bolder as octave markers
- **MIDI notes use track color**: Notes in piano roll now inherit their track's assigned color instead of hardcoded cyan
- **Piano roll row contrast**: Black key rows darker (#1E2030) for clearer visual distinction from white key rows
- **Tool buttons stand out**: Draw/Select/Slice/etc buttons now have surface background + border when inactive (was flat dark, blended with toolbar)
- **Tab buttons visible when unselected**: [Synth] [MIDI] [Effects] tabs now show subtle surface background + border when not selected (was invisible/transparent)
- **Collapse chevron styled**: Expand/collapse chevron matches tab button styling
- **Automation deferred**: Automation UI hidden behind feature flag (data preserved in saved projects); will return in a future version

## v0.2.1 — 2026-04-07

### Improvements

- **Real project screenshots**: Project thumbnails on start screen now show actual DAW arrangement screenshots instead of generated clip rectangles
- **Record button always red**: Record button shows subtle muted red when no track is armed (was grey), brighter red when armed, solid red when recording
- **Piano Roll toolbar darkened**: Toolbar background behind Loop, Start, Automation buttons changed to darkest (#13151C) for better contrast
- **Empty mixer messaging**: Mixer sidebar now shows sliders icon and "Mixer" heading instead of generic "No tracks yet"
- **Toolbar centering**: Editor panel tools (Draw, Select, Erase, Duplicate, Slice) now truly centered across full toolbar width

### Bug Fixes

- **Track colors now persist**: Track color overrides saved to `ui_layout.json` and restored on project load
- **Loop region now persists**: Loop start/end/enabled state saved and restored (no longer resets to 1 bar on load)
- **Regular track mixer overflow**: Fixed 0.617px bottom overflow on regular track mixer strips
- **Duplicate save paths consolidated**: Cmd+S now uses the correct save path (was missing BPM in recent projects)
- **Screenshot freeze**: Thumbnail capture uses lower resolution + 3s timeout to prevent UI freeze on complex projects
- **New Project dialog on fresh load**: No longer shows "unsaved changes" confirmation when clicking New Project from start screen
- **Master mixer overflow**: Fixed 0.358px bottom overflow on master track strip at certain heights
- **"New Project Created" toast removed**: Redundant SnackBar removed (status bar already shows the message)

### Removals

- **MIDI Capture button**: Removed from transport bar (backend logic retained for future use)
- **Virtual Piano button**: Removed from editor toolbar (still accessible via P key and View menu)

## v0.2.0 — 2026-04-02

### Features

- **Sustain pedal (CC64) support**: MIDI Control Change messages parsed and routed to both built-in synth and VST3 plugins. Built-in synth holds voices past note-off when pedal held; VST3 CC delivered via IMidiMapping + IParameterChanges
- **Instrument on/off toggle**: Bypass button works for both VST3 instruments (via effect bypass) and built-in synth (new `set_synth_bypass` FFI)
- **MIDI track creation with default clip**: (+) button and instrument drag both create a 1-bar empty MIDI clip, highlighted in arrangement. Editor defaults to Instrument/Effects tab
- **Audio editor tab for audio tracks**: Audio tracks now show 2 tabs — [Audio] for waveform editing and [Effects] for the device chain
- **Add track button in top bar**: Accent (+) button between mixer toggle and Ready pill with MIDI/Audio dropdown
- **Serum v1 editor support**: Combined-mode VST3 controller fallback for plugins that implement IEditController on the component itself

### Improvements

- **UI polish**: Removed transport bar cluster borders (spacing only), star field brightness tiers, brighter grid lines, logo dot refined
- **Drag preview**: Instrument drag onto empty arrangement shows full-width track strip instead of floating card
- **Empty arrangement prompt**: Text renders on top of grid lines, restyled with instrument icons on buttons
- **Zoom out icon**: Changed from X/close to minus icon
- **Editor panel chevron**: Moved to right side, enlarged to 20px
- **Track naming**: Consistent "MIDI 1" across all creation methods. Clips named after instrument ("Synthesizer", "Serum 2")
- **Plugin-as-Instrument redesign (#11)**: Native VST3 plugin GUIs embedded directly in the editor panel
- **Plugin preset navigation**: Preset browser with folder structure and "Reset to Default"
- **Plugin float/embed toggle**: Float/Embed for third-party VST3 instruments
- **First-run tooltip tour (#10)**: 6-step guided tour with spotlight cutouts
- **Crash logging**: Rust panic hook with backtrace, Flutter error handlers (widget + platform), lock contention detection
- **Effect Reset to Default**: Reset individual effects to their default parameter values
- **Effect naming**: Renamed "Comp" to "Compressor" for clarity

### Bug Fixes

- **Renderer: built-in synth silenced by effects**: `has_vst3` incorrectly checked `fx_chain.is_empty()` instead of actual VST3 effects. Adding EQ to a synth track no longer kills audio
- **VST3 combined-mode crash**: Safe unload for plugins with combined component/controller (no double-terminate, skip self-disconnect)
- **File menu Provider crash**: Captured colors before popup overlay's `itemBuilder` context
- **MIDI input deadlock**: Removed `effect_manager.lock()` from has_vst3 check in live MIDI callback. Routes to both synth and VST3 without contention
- **Editor panel dead code**: Removed unused `_buildFloatToggle`, `_buildSamplerEditorTab`, `_buildFXChainTab`, `_isCurrentPluginVst3`
- **Effect slider jumping**: Fixed slider values snapping to wrong position on drag start

## v0.2.1 — 2026-04-07

### Improvements

- **Real project screenshots**: Project thumbnails on start screen now show actual DAW window screenshots instead of generated clip rectangles
- **Record button always red**: Record button shows subtle muted red when no track is armed (was grey), brighter red when armed, solid red when recording
- **Piano Roll toolbar darkened**: Toolbar background behind Loop, Start, Automation buttons changed to darkest (#13151C) for better contrast
- **Empty mixer messaging**: Mixer sidebar now shows sliders icon and "Mixer" heading instead of generic "No tracks yet"
- **Toolbar centering**: Editor panel tools (Draw, Select, Erase, Duplicate, Slice) now truly centered across full toolbar width

### Bug Fixes

- **Track colors now persist**: Track color overrides saved to `ui_layout.json` and restored on project load
- **Loop region now persists**: Loop start/end/enabled state saved and restored (no longer resets to 1 bar on load)
- **Regular track mixer overflow**: Fixed 0.617px bottom overflow on regular track mixer strips
- **Duplicate save paths consolidated**: Cmd+S now uses the correct save path (was missing BPM in recent projects)
- **Screenshot freeze**: Thumbnail capture uses lower resolution + 3s timeout to prevent UI freeze on complex projects
- **New Project dialog on fresh load**: No longer shows "unsaved changes" confirmation when clicking New Project from start screen
- **Master mixer overflow**: Fixed 0.358px bottom overflow on master track strip at certain heights
- **"New Project Created" toast removed**: Redundant SnackBar removed (status bar already shows the message)

### Removals

- **MIDI Capture button**: Removed from transport bar (backend logic retained for future use)
- **Virtual Piano button**: Removed from editor toolbar (still accessible via P key and View menu)

## v0.1.7 — 2026-03-27

### Improvements

- **Phosphor icon set**: Replaced 120 Material Icons with Phosphor Icons for consistent 1.5px stroke weight. Centralized via `BoojyIcons` (`BI`) class. Standardized to 3 sizes: 12/14/18px via `BT.iconSm`/`BT.iconMd`/`BT.iconLg`
- **Typography system**: 4 TextStyle factory methods (`BT.caption`/`BT.label`/`BT.body`/`BT.display`). Tabular figures added to all 18 numeric displays. All font sizes and weights now reference design tokens
- **Animation constants enforcement**: Replaced 28+ hardcoded animation durations with `AnimationConstants` references. Added `quickDuration` (100ms) and `mediumDuration` (300ms)
- **Fader glow micro-interaction**: Accent-colored glow on the capsule fader thumb during drag
- **Button press depth**: 1px downward shift on BoojyButton press for tactile feedback
- **Playhead glow**: Subtle blue glow on the playhead line during playback
- **Icon A/B toggle**: Cmd+Shift+K toggles between Phosphor and Material icon sets at runtime (Material default)
- **Empty timeline prompt**: Centered "Drag an instrument" message with + MIDI Track / + Audio Track buttons when project has no user tracks
- **Start screen — first-time welcome**: "Welcome to Boojy Audio" message when no recent projects exist
- **Start screen — accent New Project button**: Primary action button uses accent colour
- **Project card colour bars**: Each recent project card has a unique colour bar derived from project name hash, plus track count and BPM metadata
- **Editor panel empty states**: Simplified to text-only "Select a track to start editing" (no large icons)
- **Library favourites hint**: Empty favourites shows "Right-click any item to add it here"

### Features

- **Top bar redesign**: Restructured transport bar into 4-cluster centre layout (Modifiers, Transport, Position, Tempo & Time) with consistent spacing and visual hierarchy
- **Loop split button**: Consolidated Loop toggle + Punch In/Out into a single split button with dropdown — removes 3 standalone buttons
- **MIDI Capture button**: New corner-bracket icon button next to Record for retroactive MIDI capture from the capture buffer
- **Position display**: Click to toggle between bars (1.1.1) and time (0:00.000) modes; double-click to type a bar number and jump playhead
- **Status pill**: Replaced simple status dot with `[checkmark Ready]` / `[hourglass Init...]` pill in the right group
- **Tempo scroll wheel**: Scroll wheel on BPM display adjusts +/-1 BPM (Shift+scroll for +/-0.1 fine mode)
- **Expanded snap menu**: Grouped dropdown with Auto, standard grid sizes, and triplet values (1/8T, 1/16T)
- **Expanded time signature menu**: Grouped dropdown with Simple (2/4, 3/4, 4/4), Compound (6/8, 9/8, 12/8), and Odd (5/4, 7/8, 7/4) categories
- **Responsive density system**: 6-level overflow-based compression (comfortable through minimum) — nothing disappears at any window size
- **Value-text split buttons**: Split buttons show current setting value on right side instead of chevron (e.g., `[Loop | →|→]`, `[Snap | Beat]`, `[metronome | 1 Bar]`)
- **Punch overlay**: Loop punch dropdown stays open for multi-select — toggle both Punch In and Punch Out without re-opening
- **Cluster dividers**: 1px vertical dividers between Modifiers, Transport, and Readout clusters

### Improvements

- **Transport bar height**: Increased from 48px to 54px for more breathing room
- **Split button styling**: All modifier split buttons (Loop, Snap, Metronome) now use accent-at-30% background when active instead of solid accent fill
- **LCD readout style**: Position, tempo, and time signature displays use consistent darkest-background + divider-border + monospace 14px styling
- **Left group spacing**: Updated to match Boojy design system (16px left pad, 12px gaps, 4px undo/redo pair)
- **Transport button sizing**: Play, Stop, Record all same size (28px) — consistent visual weight
- **Tap button reduced**: Smaller font/padding than LCD displays to visually subordinate it
- **Status pill**: Color-coded green background when ready, hover tooltip shows engine stats (sample rate, latency, audio output)
- **Snap label**: Always shows "Snap" on left side, current value on right side — no more confusing label swap
- **Removed MIDI device selector** from metronome dropdown (moved to settings)

## 0.1.6 — 2026-03-25

### Bug Fixes

- **Sampler editor crash**: Fixed `.single` on FilePicker result that would crash if no file was selected. Now uses safe `.first` access with `.isNotEmpty` guard.
- **Sampler waveform division by zero**: Fixed `_pixelsPerBeat` calculation that produced NaN/Infinity when `originalBpm` was 0. Now returns fallback value.
- **Clip overlap handler**: Fixed loop iterating all clips instead of pre-filtered track clips, causing unnecessary iteration and misleading debug logs.
- **Recording negative duration**: Fixed count-in duration going negative when playhead seeked backward during recording. Now clamped to non-negative.
- **FFI heap corruption**: Fixed `Vec::from_raw_parts` capacity mismatch in waveform peak free functions — used `Box<[f32]>` via `into_boxed_slice()` to guarantee capacity == length.
- **Recorder timestamp panic**: Replaced `.unwrap()` with `.unwrap_or_default()` on `SystemTime::duration_since(UNIX_EPOCH)` to prevent panic if system clock is invalid.
- **Recording listener leak**: Added defensive `removeListener` before `addListener` in `startRecording()` to prevent listener accumulation on rapid start/stop cycles.

### Improvements

- **FFI panic safety**: Wrapped all 164 `extern "C"` FFI functions in `catch_unwind` to prevent Rust panics from crossing the C boundary (which is undefined behavior). Added `ffi_catch` helper with per-function default values.
- **VST3 block processing**: Added `process_block` method to Effect trait with default per-sample fallback. VST3Effect overrides with batched lock acquisition and buffer-level processing, reducing lock contention from per-sample to per-buffer.
- **Audio thread allocation**: Pre-allocated `Vec<TrackSnapshot>` and `HashMap` buffers outside the audio callback, reusing them each frame instead of allocating on every callback invocation.
- **Project load dedup**: Extracted shared post-load logic (`_loadAndApplyProject`) from `openProject()` and `openRecentProject()`, eliminating ~80% code duplication. Also deduplicated matching private methods in `daw_screen.dart`.
- **Engine version sync**: Updated engine `Cargo.toml` version from 0.1.0 to 0.1.5 to match Flutter app version.
- **AudioGraph safety comment**: Updated `unsafe impl Send` comment to accurately describe the thread-safety invariant.

- **Divider redesign**: Continuous full-height dividers spanning top bar through content area. 1px gray line at rest, 4px accent bar on hover with synchronized highlighting (both segments activate together). Transport bar restructured to 3-column grid layout with draggable left/right handles.
- **Surface color simplification**: Reduced from 5 surface color levels (dark/standard/elevated/surface/divider) to 3 clean levels: `dark` for all chrome, `darkest` for content areas, `editor` for timeline. Unified visual hierarchy matching Boojy Notes.
- **Mixer header simplified**: Removed collapse chevron, tune icon, and "TRACK MIXER" label — header now shows only the (+) add track button, right-aligned.
- **Transport bar layout**: Sidebar toggle aligned to right edge near divider, help button pushed to far right corner.
- **Centralized logging**: Replaced 161 `print`/`debugPrint` calls across 31 files with `Log` utility (silent in release builds). Categories: `Log.e()` for errors, `Log.d()` for debug, `Log.i()` for info.
- **Magic numbers extracted**: MIDI constants (defaultVelocity, noteOffVelocity, maxMidiNote) and scroll thresholds moved to `UIConstants`. Removed 93 lines of dead code.
- **Performance: automation preview**: Converted from setState (full DAWScreen rebuild at 60fps) to ValueNotifier (only mixer panel rebuilds during drag).
- **Performance: status message**: Removed 35 wasteful setState calls for unused statusMessage field.
- **Code decomposition**: Extracted DAWScreen build method into 4 named methods, timeline keyboard handler into separate method, piano roll content into 4 focused builders.
- **Dev tool: Palette Editor**: Live color palette editor (Cmd+Shift+P in debug builds) with preset switching (Current/Neutral/Warm), hex input, and code export.

### Features

- **UI redesign — Boojy Design System alignment**: Migrated entire colour palette from neutral greys to blue-tinted Boojy Design System colours (matching Boojy Notes). New deep blue-black editor background (#040412) for timeline and piano roll content areas. Chrome (sidebar, top bar, mixer) uses #2C2C32. All painters (grid, nav bar, rulers, automation) updated to design system colours.
- **Top bar redesign**: Restructured transport bar from single row to 3-group layout (Left: logo/project/undo/redo/sidebar toggle | Centre: transport controls | Right: mixer toggle/status/help). Reduced height from 60px to 48px. Text-based "Audi●" logo with accent-coloured circle replaces image logo. SVG icons for undo/redo and panel toggles via flutter_svg. Engine status dot in top bar replaces bottom status bar.
- **Star field background**: Animated star field renders behind the timeline content area, matching the Boojy visual identity from Notes. ~70 stars with gentle glow/fade pulsing at individual speeds. Uses CustomPainter with RepaintBoundary for performance isolation.
- **Floating UI restyled**: Global popup menu theme updated with design system colours (#292B36 bg, #3A3D4A border, 8px radius, shadow). Tooltips restyled with dark bg and 200ms delay. Settings modal redesigned with accent-coloured section header lines (uppercase + accent line extending right), "Audi●" logo + version in sidebar bottom, and dark overlay with 12px border radius.

### Improvements

- **Timeline performance optimization**: Decouple playhead from full timeline rebuild (60fps → only playhead line repaints), add viewport culling for off-screen clips, skip unnecessary 2-second timer rebuilds when tracks haven't changed, add RepaintBoundary isolation for grid/tracks/playhead, remove playbackController from generic DAW screen listener
- **Start screen visual refresh**: Use original-color logo images instead of monochrome text, move "Recent Projects" header outside grid box, style "Check for updates" as a button, increase bottom bar text size, reduce bottom gap so grid aligns flush with footer

### Bug Fixes

- **Fix clip resize not affecting audio playback**: `ResizeAudioClipCommand` only updated clip start time in the engine but never called `setClipDuration()` or `setClipOffset()` — trimmed clips visually shortened but kept playing the full original audio. Now syncs duration and offset to the engine on both execute and undo.
- **Fix playhead not following during playback**: `Positioned` widget inside `RepaintBoundary` broke parent data chain to `Stack` — playhead line stayed at x=0. Restructured so `Positioned` is the direct VLB child.
- **Fix file drop not registering on correct track**: `handleFileDrop` used legacy `loadAudioFile` which added clips to the first available track in the engine, not the drop target. Replaced with `loadAudioFileToTrack` so clips are placed on the correct track at the correct position, fixing overlap resolution.
- **Fix duplicated audio clips losing warp/stretch settings**: `duplicate_audio_clip()` in Rust only copied offset and duration — warp, gain, transpose, and stretched cache were lost. Dart side also didn't preserve `editData` in the `copyWith()` call. Both layers now copy all clip properties.
- **Fix clip overlap prevention not working**: Overlap handling existed in mixin methods but was never called — `daw_screen.dart` had duplicate private methods without overlap logic that shadowed the mixin versions. Rewired all 4 TimelineView callbacks (`onAudioFileDroppedOnTrack`, `onMidiFileDroppedOnTrack`, `onMidiClipCopied`, `onAudioClipCopied`) to use the mixin methods with proper overlap resolution. Also fixed drag-move handler where a separate `setState` overwrote overlap-resolved clip positions.
- **Fix clip overlap during Alt+drag duplication**: Overlap resolution now correctly trims existing clips (including the source) when placing a duplicated clip — standard DAW behavior where the new copy always wins.
- **Fix undo leaving ghost audio**: `AddAudioClipCommand.undo()` only removed clip from UI but not from engine — undone clips kept playing invisibly. Now calls `engine.removeAudioClip()` before UI removal.
- **Fix unnecessary "New Project" confirmation**: No longer shows the "Any unsaved changes will be lost" dialog when there is no active project (e.g., clicking New Project from the start screen on fresh launch)
- **Fix sampler stereo bug**: Sampler was outputting mono to both channels. All 4 call sites in `audio_graph.rs` now use `process_sample_stereo()` for proper L/R separation.
- **Fix sampler waveform rendering**: Waveform only showed top half and appeared offset. Root cause: `get_waveform_peaks()` returned single positive values (`.abs()`) instead of min/max pairs. Now returns `[min, max, ...]` matching Audio Editor format.

### Features

- **Clip overlap prevention**: Clips on the same track can no longer overlap — "new clip always wins." When placing, copying, moving, or recording a clip over existing clips, overlapped clips are automatically trimmed, split, or deleted. Handles 4 overlap scenarios: complete cover (delete), end overlap (trim end), start overlap (trim start), and inside (split into two). Extracted shared `ClipOverlapHandler` utility from recording mixin and applied to all clip placement points (file drop, MIDI import, copy/duplicate, move, drag-to-create).
- **Start screen modal**: Modal overlay on app launch showing recent projects as a responsive card grid with arrangement thumbnails. Two-column layout with branding, New Project/Open/Settings buttons on left and scrollable project cards on right. Cards show arrangement thumbnail preview, project name, and relative time. Hover reveals path metadata. Right-click context menu (Open, Show in Finder, Remove from Recent). Drag-and-drop .audio folders to open. Bottom bar with version and Sparkle update checker. Accessible via File > Start Screen menu. Thumbnail PNG auto-generated on every project save.
- **Sampler**: Added volume, pitch transpose, fine cents, reverse, warp mode, BPM, and time signature parameters to engine with full FFI support and serialization
- **Punch In/Out recording**: Re-record specific sections without affecting the rest. Reuses the loop bar for punch boundaries with 4 modes — free recording, loop, loop+punch, and single-pass punch. Transport bar gains →| (Punch In) and |→ (Punch Out) toggle buttons flanking the Loop button. Bar color changes to red when punch is active. Keyboard shortcuts: I (toggle punch in), O (toggle punch out). Engine auto-stops recording at punch-out boundary while playback continues.
- **Scale/key snapping**: Add Lock toggle to piano roll controls bar — when active, note creation and movement snap to the selected scale. Works with all 11 scale types (Major, Minor, Dorian, Pentatonic, Blues, etc.) and 12 root notes. Combines with existing Highlight (dims out-of-scale rows) and Fold (hides non-scale keys) features.
- **Sampler one-shot mode**: Default mode — note-off is ignored, sample plays to completion. Toggle loop ON for sustain-loop playback between draggable loop markers.
- **Sampler loop playback**: Loop markers visible in both modes (greyed when off, accent when on). Draggable loop start/end constrained within sample duration. Voice wraps from loop-end back to loop-start while held.
- **Sampler Editor overhaul**: Two-row controls bar — Row 1 functional (Loop, Attack, Release, Root Note, Load), Row 2 greyed-out layout placeholder (Warp, Pitch, Volume, Reverse). Real waveform peaks from engine. Seconds-based ruler. Envelope overlay (attack→sustain→release). File picker to load new samples.
- **[Sampler] button in Audio Editor**: Creates a new sampler track with the current audio clip loaded as the sample. One-click workflow from audio editing to sampler sound design.

### Improvements

- **Sampler Editor**: Full controls bar matching Audio Editor layout — sampler identity controls on left (Loop, Attack/Release capsule sliders, Root Note), audio manipulation on right (Start/Length in bar.beat.sub, Signature, Warp split button with BPM/÷2/×2, Reverse, Pitch transpose+cents, Volume with capsule slider). All controls use shared widgets extracted from Audio Editor (CapsuleSlider, BpmDisplay).
- **Sampler Editor redesign**: Unified visual style with Audio Editor — single-row controls bar (removed greyed-out placeholder row), 24px navigation bar matching UnifiedNavBar style with hierarchical tick marks and dark background, improved waveform rendering with LOD downsampling and dynamic stroke. Scroll wheel/trackpad support for horizontal scrolling. Zoom controls overlaid via shared NavBarWithZoom component.
- **Sampler waveform matches Audio Editor**: Removed envelope overlay and triangle loop markers from waveform area. Paint order now matches Audio Editor (Grid → Waveform → Loop dimming). Loop dragging moved from waveform to nav bar with hover edge highlighting (orange glow on loop boundaries). Nav bar now supports drag-to-scroll (horizontal) and drag-to-zoom (vertical), scroll wheel, and grab/grabbing cursors matching Audio Editor. Auto-zoom-to-fit on sample load. Fixed nav bar rendering at 0px height (StackFit.loose issue).
- **Sampler as instrument**: Sampler tracks are now MIDI tracks with a sampler instrument attached, gaining full MIDI capabilities (create clips on timeline, drag-to-create, record MIDI). Default 1-bar MIDI clip auto-created on sampler creation. Sampler state (sample path, root note, envelope, loop settings) now persists in project save/load. Fixes input routing bug where sampler tracks incorrectly received audio input.
- **CI pipeline**: Add GitHub Actions workflow (`ci.yml`) with Flutter analyze, dart format, flutter test, and Rust clippy/test on every push and PR
- **Comprehensive command test coverage**: Add 76 new tests across effect, mixer, track, and project commands with shared MockAudioEngine test infrastructure
- **Remove dead aliases from DAW screen**: Remove ~112 lines of backward-compatibility aliases left from the mixin migration in `daw_screen.dart`
- **Extract UI constants**: Centralize magic numbers (clip heights, zoom limits, gesture thresholds, etc.) into `UIConstants` class, referenced from timeline, piano roll, and mixer strip
- **Rust clippy auto-fixes**: Fix ~650 clippy warnings (format strings, doc backticks, infallible casts)
- **Fix AudioEngineInterface return type mismatches**: Correct 5 method signatures (`setClipStartTime`, `deleteTrack`, `removeAudioClip`, `removeEffectFromTrack`, `setVst3ParameterValue`) and add missing `@override` annotations in native implementation
- **Add controller and service tests**: 231 new tests — TrackController (105), AutomationController (99), ClipNamingService (9), ToolModeResolver (18) — bringing total to 770
- **Split timeline_view.dart into focused mixins**: Extract ~1000 lines into 3 new mixin files (TimelineSelectionMixin, TimelineFileHandlersMixin, TimelineContextMenusMixin), reducing the main file from ~4800 to ~3780 lines
- **Complete AudioEngineInterface**: Add ~18 missing method signatures (init, VST3 editor, export, audio device) so all platforms share the same interface contract; update stub, web, and mock implementations
- **Dead code cleanup**: Remove unused fields, imports, and fix unnecessary null comparisons across 4 files
- **Split audio_engine_native.dart into focused part files**: Refactor 3826-line monolith into 7 files using base class + mixins pattern — `_AudioEngineBase` (fields/constructor), `_TransportMixin`, `_RecordingMixin`, `_TracksMixin`, `_PluginsMixin`, plus typedefs; no file exceeds ~1050 lines

### Known Issues

- Project restore after crash can cause deleted audio tracks to reappear and existing tracks to be lost
- Delay between renaming a track and the visual update propagating (e.g., mixer strip color update lags behind clip color change)
- Audio sliced with the slice tool in Audio Editor still plays back even though sliced parts don't appear in arrangement view

## v0.1.5 - 2026-02-04

### Bug Fixes

- **Fix file drops on empty area ignoring cursor position**: Dropping audio or MIDI files on the empty area below tracks always placed the clip at bar 1. Now the clip is placed at the snapped beat position where the cursor was when the file was dropped.
- **Fix drag preview not visible in full empty area**: The empty-area drop target was only 100px tall, so dragging files to the lower part of the empty space showed no preview. The drop target now fills the entire remaining viewport height.
- **Fix engine stuck in initializing**: Defer MIDI device enumeration from engine init to first use. CoreMIDI can block indefinitely when scanning for devices, preventing the engine from ever reaching the ready state.
- **Fix MIDI notes lost at recording boundary**: Notes held during count-in that extend past the recording start are now "caught" and included at the start of the recording (timestamp 0), instead of being silently discarded.
- **Fix duplicate MIDI events**: Deduplicate identical MIDI events in the recorder to handle controllers that send on multiple channels simultaneously (e.g. SL STUDIO sending on channel 0 and 1).
- **Fixed: Recorded audio clips not appearing on timeline**: Engine stored recorded audio data correctly but the Dart UI never created a `ClipData` object or added it to the timeline state. Audio recordings now properly appear as clips after recording stops.
- **Fixed: MIDI notes lost when recording at non-zero position**: Recording MIDI at any position other than Bar 1 (e.g., Bar 4) silently discarded the first `count_in_duration` seconds of notes. The MIDI recorder's event filtering threshold double-counted the count-in offset — it added count-in samples to the original playhead position instead of the seekback position, causing notes at the recording start to be incorrectly treated as count-in events.
- **Fixed: Recording overlap trimming not syncing to engine**: Overlap handling (trim, split, delete) only updated the UI — the Rust engine still played original untrimmed clips. Added engine-level `setClipOffset` and `setClipDuration` APIs for audio clip trimming, and MIDI clip rescheduling after overlap modifications. All four overlap scenarios (delete, trim end, trim start, split) now properly sync to the engine for both audio and MIDI clips.
- **Fixed: Recorded MIDI clips not removable by overlap handling**: `addRecordedClip()` never populated the Dart→Rust clip ID mapping, so `deleteClip()` and `rescheduleClip()` couldn't find the engine clip. Overlap trimming appeared to work visually but old untrimmed clips kept playing in the engine.
- **Fixed: Old clips audible during recording**: Existing audio and MIDI clips on armed tracks now silenced while recording, so the user only hears their live input — not old clips being overwritten.

### Improvements

- **Visual masking of overwritten clips during recording**: When recording over existing clips, the overwritten portions are now visually hidden in real-time. Only the non-overlapping parts of existing clips remain visible, giving clear feedback of what will be replaced.

### Features

- **Drag preview for MIDI files on tracks**: Dragging a `.mid` file from the library onto a MIDI track now shows a semi-transparent clip preview with MIDI note bars at the snapped grid position, matching the existing audio file drag preview behavior.
- **Clip preview for empty area drops**: Dragging audio or MIDI files to the empty area below tracks now shows an actual clip preview (waveform or note bars) instead of the plain green border rectangle, with a small label pill at the bottom.
- **MIDI File Import/Export**: Export MIDI clips as Standard MIDI Files (.mid) via right-click context menu, and import .mid files by dragging from the library panel or Finder onto the timeline. Library panel now shows .mid files alongside audio files in user folders.
- **Input monitoring (auto mode)**: Armed tracks now automatically monitor input — arm a track and hear yourself through the DAW's effects chain. Unarming stops monitoring with a smooth 20ms fade-out to prevent audio clicks. No new UI needed; the existing R (arm) button controls monitoring. Works for audio tracks (MIDI monitoring was already implicit via the synth).
- **Redesigned recording workflow** with improved transport controls:
  - **Count-in with song context**: During count-in, playback starts from (record position - count-in bars) so you hear the actual song, not just metronome clicks
  - **Three-button behavior during recording**:
    - Pause: Stops recording and stays at current position (save clip, pause transport)
    - Stop: Stops recording and returns to recording start position (save clip, seek back)
    - Record: Saves current take and immediately starts new recording with count-in (multi-take recording)
  - **Simplified Stop button**: Single press always returns to start position (no more double-stop). When idle (not playing/recording), Stop returns to bar 1
  - **Play → Record**: Pressing Record while already playing starts recording immediately with no count-in (already in time)
  - **Record button visual**: Subtle pulsing glow during recording (0.8-1.0 opacity, 2-second cycle)
  - **Position tracking**: Stop button returns to appropriate position (playStartPosition during playback, recordStartPosition during recording)
  - **Recording overlap trimming**: New recordings automatically trim, split, or delete existing clips on the same track ("new recording always wins"). Handles all overlap scenarios: complete cover (delete), overlaps end (trim), overlaps start (trim), and recording inside existing (split into two). Clips trimmed below 0.25 beats are auto-deleted. Works for both MIDI and audio clips
  - **Undo support for recording**: Entire recording operation (new clip + all overlap trim/split/delete actions) is undoable as a single Cmd+Z. Uses snapshot-based command pattern with engine-level clip re-add support
  - **Manual resize overlap blocking**: Clip edge drags are clamped at adjacent clip boundaries on the same track, preventing manual creation of overlapping clips (both audio and MIDI)
- Multi-track audio recording with per-track input routing:
  - Per-track input device and channel assignment (stored on Track struct)
  - Input selector dropdown on mixer strip Row 1 with live animated level meters (~50ms poll)
  - Input monitoring: hear live input on armed tracks mixed into track output
  - Input level overlay on capsule fader (faded green at 25% opacity behind output meters)
  - Multi-channel recording: each armed audio track records its assigned input channel independently
  - Recorded clips placed at playhead position (after count-in) instead of always at 0.0
  - Auto-assign input channels on audio track creation (alternates L/R)
  - Record button disabled when no tracks are armed
  - Input selector locked during recording (greyed out, no arrow)
  - Preview playback blocked during recording
- Track icon/color popup: click track emoji to open picker with 16 emoji icons and 16 track colors
- Multi-note resize: when multiple notes are selected, resizing one resizes all by the same delta
- Ableton-style audio clip drag preview: when dragging audio from library over audio tracks, shows faded preview clip matching real clip style with live waveform (snaps to grid)
- Smart MIDI track tab switching:
  - Tab order: Instrument → Piano Roll → Effects
  - Dropping instrument shows Instrument tab (clip created but not selected)
  - Clicking track header shows Instrument tab (clips not auto-selected)
  - Clicking MIDI clip switches to Piano Roll (no placeholder flash)
  - Switching tracks resets to Instrument tab
  - Manual tab selection is respected until track changes
- Real-time MIDI note drawing during recording:
  - Notes appear live on both timeline and piano roll as they are played (~33ms latency)
  - Held notes extend in real-time as the playhead advances
  - Recording clip grows rightward with the playhead
  - Red visual styling on recording clip (header, border, and note colors)
  - Piano roll becomes read-only during recording (no editing, zoom/scroll still work)
  - Auto-scroll on timeline and piano roll keeps playhead visible during recording
  - Clean transition: live preview seamlessly replaced by final clip when recording stops
  - Works with both virtual piano and external MIDI controllers

### Bug Fixes

- **Fixed: MIDI recording timing issue — notes no longer appear 125ms (1/16 bar) early**
  - Root cause: `start_midi_recording()` was reading current playhead after audio callback had already advanced it by ~6000 samples (125ms), instead of using the original recording start position captured before playback started
  - This race condition caused `recording_start` to be calculated 125ms too high, making all recorded notes appear 1/16 bar early at 120 BPM
  - Fix: Use stable `recording_start_seconds` value that was captured before the seek-back for count-in
  - Audio latency is now queried from CoreAudio device properties (input latency, output latency, safety offset) instead of being estimated from buffer size alone
  - NO latency compensation is applied during recording (entire system has consistent latency). Latency compensation only applies during live monitoring to provide instant playback feedback
- Fixed: Deleted MIDI clips continue playing — DeleteMidiClipFromArrangementCommand now calls engine.removeMidiClip() to stop playback, not just UI removal. Added removeMidiClip() to AudioEngineInterface for proper command pattern support
- Fixed: MIDI devices plugged in after app launch not detected — refresh_midi_devices() now actually rescans OS MIDI system instead of being a no-op. Newly connected MIDI controllers (like StudioLogic) can be detected by clicking "Refresh MIDI Devices" without restarting the app
- Improved: MIDI device selection now validates device index and provides clear error messages when selecting invalid or unplugged devices
- Improved: MIDI device enumeration logging helps diagnose device detection issues — detailed console output shows available devices and troubleshooting steps when no devices are found
- Fixed: MIDI recording notes not appearing live and playhead freezing — Display offset was calculated from user settings instead of actual count-in duration used by engine. This caused wrong offset when recording while already playing (Play→Record with no count-in)
- Fixed: Transport position going negative and freezing during recording — recordStartPosition was set to position AFTER count-in (e.g., 4s) instead of BEFORE (e.g., 0s), causing wrong Stop button behavior and display calculations (playhead showed negative bars like -1.1.1)
- Fixed: Recorded MIDI clip disappearing after stopping recording — Captured live notes weren't being passed through from _completeRecording() to handleRecordingComplete(), resulting in empty clips that appeared during recording but vanished when stopped
- Fixed: Stop button not returning to bar 1 when idle — Removed unconditional playhead reset from engine's stop() method that was overriding position set by Dart layer's transportSeek()
- Fixed: Visual playhead not moving when Stop button pressed — PlaybackController's playheadNotifier wasn't being updated in stop() and seek() methods, only in the playback timer
- Fixed: Playhead not moving during MIDI recording — PlaybackController's playhead polling timer was never started when recording began (engine transport runs but UI didn't poll it)
- Fixed: Live MIDI notes not appearing on timeline/piano roll during recording — consequence of playhead not updating (ValueListenableBuilder never rebuilt)
- Fixed: Spurious audio track created when stopping MIDI-only recording — Rust engine no longer auto-creates audio tracks when no audio tracks are armed; Dart side also filters audio clip results
- Fixed: Transport bar record button bypassed mixin recording methods — playhead polling, live MIDI note display, and library preview blocking were never triggered during recording
- Fixed: MIDI recording timestamps from external MIDI controllers were in wrong unit (midir microseconds vs engine samples), causing garbled note positions
- Fixed: MIDI notes played during count-in were incorrectly captured — now discarded (matching Ableton behavior)
- Fixed: Recorded MIDI clips placed at wrong timeline position (used stop-time playhead instead of recording start position after count-in)
- Fixed: Recorded MIDI clip disappeared from arrangement view after recording stopped — clip ID 0 was treated as invalid (`> 0` check instead of `>= 0`)
- Fixed: Playhead moved during count-in — now stays frozen at the recording start position; playhead polling starts only when count-in finishes, with a display offset to compensate for elapsed count-in time
- Fixed: MIDI clip placed at bar 2 instead of bar 1 when recording with count-in — engine now sets `recording_start` to the pre-count-in playhead position (count-in is a pre-roll, not a timeline advance)
- Fixed: `handleRecordingComplete` called twice on stop (via callback AND explicit call), causing duplicate MIDI clips and "Duplicate keys" crash — callback is now cleared before calling `stopRecording()`
- Fixed: Count-in bars mismatch between engine (hardcoded 1) and Dart side (persisted user setting) — removed hardcoded `setCountInBars(1)` from RecordingController; engine now uses the user's saved setting consistently
- Fixed: Second MIDI recording caused "Duplicate keys" crash — engine reuses clip ID 0; `addRecordedClip()` now deduplicates by removing existing clip with same ID before adding
- Fixed: Live recording clip extended ~1 bar ahead of playhead during count-in recording — `currentBeat` for live clip now subtracts the actual count-in duration (measured from engine time at transition)
- Fixed: Recorded MIDI clip notes disappeared visually after second recording — live notes were cleared before being stored in the permanent clip; now captured from LiveRecordingNotifier before stop and embedded in MidiClipData
- Fixed: Piano Roll no longer shows placeholder briefly when switching from Instrument tab
- Fixed: Clip header overflow on very short clips - wrapped header Rows in ClipRect to prevent "RenderFlex overflowed" errors

### Improvements

- Count-in default changed from 2 bars to 1 bar (aligns widget default with persisted user setting)
- Count-in ring timer on record button:
  - During count-in: depleting orange ring (clockwise from 12 o'clock) + beat number inside button
  - Recording start: brief white flash transition, then solid red fill with glow
  - Removed separate `[● REC 00:03.42]` recording indicator from transport bar
  - Position display no longer changes color during recording/count-in (stays neutral)
  - Count-in beat/progress polled from engine at ~30fps for smooth animation
  - Works with all count-in lengths (Off/1/2/4 bars) and time signatures

- **Build system improvements**:
  - Added `build.sh` script — single command for debug (`./build.sh`) or release (`./build.sh release`) builds with automatic dylib installation
  - Integrated sccache for Rust compilation caching (caches compiled crates across builds)
  - Added Xcode "Build Rust Engine" run script phase — `flutter run` now auto-builds the engine (no manual `./build.sh` needed)
  - Optimized third-party crates in debug builds (`opt-level = 2`) for better audio performance without sacrificing own-code compile speed
  - Explicit Apple linker configuration in `engine/.cargo/config.toml`
  - Fixed all 11 Rust compiler warnings (elided lifetimes, unused qualifications, ambiguous glob re-exports, dead code)

- Piano roll note interactions:
  - Select mode now shows grab cursor (not resize cursor) - resize isn't possible in select mode
  - Small notes (<18px) can now be moved - dynamic edge threshold ensures a middle zone always exists
  - Drag action now matches cursor intent - if cursor shows "move", dragging will move (not resize)
  - More reliable edge detection using distance-to-closest-edge logic
  - Auto-select note on drag: dragging unselected note selects it, Shift+drag adds to selection
  - Fixed: resizing a note no longer accidentally moves other notes (cleared stale move state)
  - Fixed: newly created note no longer moves when click+dragging a different note

## v0.1.4 - 2025-01-27

### Improvements

- Library panel UI polish:
  - Consistent 12px font size across both columns (was 11px in categories, 12px in contents)
  - Combined header row with inline search field (saves vertical space)
  - Standard resizable divider with hover feedback and double-click to toggle width
  - Middle truncation for long filenames that preserves file extension (e.g., "Cymatics...Clap 1.wav")
  - Category names truncate with ellipsis when narrow (no two-line wrapping)
  - Simplified divider behavior: middle divider controls left column (100-250px), outer divider controls right column (100-400px)
  - Panel width computed from left + right columns (max ~658px)

### Features

- Library audio preview! Click audio files in the library to audition them before adding to your project
  - Preview bar at bottom of library with audition toggle, play/stop button, and waveform visualization
  - Waveform shows playhead progress (played portion bright, unplayed dimmer)
  - Speaker icon appears on currently previewing item in library list
  - Files < 3 seconds loop automatically, longer files play once
  - Preview stops on drag start, selection change, or audition toggle off
  - Audition state persists between sessions
  - Note: Synth preset preview (playing MIDI note) is stubbed but not yet implemented

- Clip-based automation! Automation now lives inside clips (like MIDI notes) instead of on the track timeline
  - Automation moves with clips when dragged
  - Automation loops with ghost copies when clips are looped (edits to first loop sync to all copies)
  - Automation slices when clips are cut (auto-creates edge node at cut point)
  - Automation copies when clips are duplicated (deep copy with new point IDs)
  - All 5 tools work for automation: draw, select, delete (via Delete/Backspace), duplicate, slice
  - Piano Roll now has an "Automation" toggle button to show/hide clip automation lane
  - Supports volume and pan parameters with live value display during drag
  - Note: Per-clip automation playback requires additional engine work (UI complete, data persists)

- Volume automation now affects playback! Automation curves are sent to the Rust engine and applied per-frame
  - Engine interpolates volume at sample-accurate resolution using binary search
  - Works with both real-time playback and offline export
  - Automation syncs to engine whenever points are added, updated, or deleted
  - Project save/load correctly restores automation to engine

### Bug Fixes

- Add tool mode support to track automation lane in arrangement view (eraser, select, duplicate, slice tools now work via toolbar, plus modifier key shortcuts: Alt=Eraser, Shift=Select, Cmd=Duplicate)
- Add drag-to-erase for track automation lane (eraser tool now deletes points as you drag over them, not just on click)
- Fix instant visual feedback when drawing new automation points in track automation lane (new points now appear immediately instead of after parent state update)
- Fix clip automation lane selection/eraser modes not working in piano roll (CustomPaint was in AnimatedBuilder's child param which prevented setState from rebuilding the painter with updated selection state)
- Fix automation point hit detection not working (eraser, select, hover) in piano roll automation lane (previous fix added scroll offset but that caused double-transformation; Flutter's Transform.translate already adjusts localPosition to content space)
- Fix selection rectangle not rendering in clip automation lane (cyan box now appears during drag-select in both piano roll and arrangement view)
- Fix automation points not appearing visually selected after box selection or click selection (points now properly highlight with larger size and track color)
- Fix eraser mode in automation lane now deletes points on click (previously only worked via Delete/Backspace key)
- Fix box selection in automation lane when clicking on unselected points (now selects and prepares for drag instead of starting box selection)
- Add Shift+drag for box selection in automation lane in any tool mode (matches piano roll behavior)
- Fix volume automation max being +1.6 dB instead of +6 dB (now uses Boojy curve matching CapsuleFader)
- Fix reset button in automation lane not updating UI (missing setState)
- Revert automation lane resize from 16px footer to invisible 6px top handle
- Fix automation lane real-time updates when dragging points (uses local preview state like velocity lane, persists until parent updates)
- Remove right-click delete from track automation lane (points should only be deleted via Delete/Backspace key, not right-click)
- Add mutual exclusion for note and automation point selection in piano roll (selecting an automation point now deselects all notes)

### Improvements

- Row 2 volume slider and dB display now update live during automation drag
- Automation lane value display now updates live when dragging points (e.g., "0.0 dB" → "3.5 dB" → "6.0 dB")
- Automation value display now matches volume display styling (larger font, same width)
- Dragged automation value persists when paused; clears when playback starts to show actual values
- Piano roll velocity now affects note brightness instead of transparency (vel 100 = standard cyan, lower = darker, higher = brighter)
- Removed darker border from piano roll notes (cleaner look)
- Selected notes now have 2px white interior border (same shape as unselected notes)
- Removed resize handles from selected notes (cleaner selection appearance)
- Velocity lane redesigned: vertical line + horizontal line + circle at corner (matches note start/duration/velocity more clearly)
- Velocity lane indicators now use per-note brightness matching the piano roll notes
- Removed [Rand] button from velocity lane header
- Velocity lane uses FL Studio-style "nearest circle" editing with pixel threshold (45px left, 55px right)
- Velocity circles now show white highlight when note is selected or being dragged

## v0.1.3 - 2025-01-22

### Features

- Audio clip looping in arrangement view (like MIDI clips):
  - When Loop is enabled in Audio Editor, audio clips can be extended beyond their loop region
  - Waveform tiles/repeats when clip duration exceeds loop length
  - Visual notches on clip border show loop boundaries (matching MIDI clip style)
  - When Loop is disabled, right edge is locked to content length (no stretching)
  - Tooltip shows "Enable Loop in Audio Editor to extend" when at limit
  - Loop region (Start/Length from Audio Editor) is what loops, not entire clip
  - Works with or without Warp enabled (unlike Ableton which requires Warp)

- Audio Editor toolbar improvements:
  - Added time Signature dropdown (2/4, 3/4, 4/4, 5/4, 6/8, 7/8) for clip time signature
  - Added ÷2 and ×2 tempo buttons to quickly halve/double BPM
  - Added Reverse toggle button with visual waveform flip when enabled
  - BPM and tempo buttons are greyed out and disabled when Warp is OFF

- Added audio clip Warp feature: sync audio clips to project tempo via time-stretching
  - Warp toggle in Audio Editor controls bar enables/disables tempo sync
  - Original BPM field to set clip's source tempo (auto-detect coming in future)
  - Project BPM display shows current project tempo
  - Stretch factor calculated as project_bpm / clip_bpm (e.g., 110 BPM loop in 120 BPM project = 1.09x)
  - Works in real-time playback and offline export
  - Warp ON: clip visual width stays fixed (beat-based) regardless of tempo changes
  - Warp OFF: clip visual width stretches/squishes with tempo (time-based), consistent between Audio Editor and Arrangement View
- Added Warp Mode selection to Audio Editor: Warp (time-stretch with pitch preserved) vs Re-Pitch (speed changes pitch like vinyl/tape)
  - Split button UI: click icon/text to toggle warp on/off, click dropdown arrow to select mode
  - Warp mode (default): Time-stretching preserves pitch while changing tempo using signalsmith-stretch algorithm
  - Re-Pitch mode: Speed change affects pitch (classic varispeed behavior)
  - Warp mode now actually works: pitch-preserved time-stretching using pre-computed cached audio
- Added Sampler track type with pitch-shifted sample playback triggered by MIDI notes
- Added Sampler Editor with Attack/Release envelope controls and Root Note selection
- Added "Open in Sampler" context menu option in Library panel for audio files
- Added "Convert to Sampler" context menu option on Audio tracks (creates Sampler track with MIDI notes at original clip positions)
- Added "Rename Project..." menu item in File menu (only shown for saved projects)
- Added "Save New Version..." to create versioned copies with symlinked samples (e.g., My Song_v2.audio)
- Rename now updates recent projects list (removes old path, adds new path)

### Bug Fixes

- Fixed waveform squishing when trimming audio clip right edge (waveform now properly truncates instead of compressing all peaks into smaller width)
- Fixed right edge drag cursor showing forbidden incorrectly (now always shows resize cursor since you can always reduce clip duration)
- Fixed potential crash when widget disposes during VST3 MIDI note-off delay (added mounted check)
- Audio clip selection now clears previous MIDI/audio selections (consistent behavior)

### Improvements

- Audio Editor pitch control now shows combined `[0 st. 0 ct]` display with separate semitones (-48 to +48) and cents (-50 to +50) segments, each draggable/scrollable/editable (double-click to type exact value)
- Audio clip pitch shifting now actually works: transpose affects playback pitch in real-time (note: changes playback speed like Re-Pitch mode)
- Auto-select audio clip after drag-and-drop creation (matches MIDI track behavior, opens Audio Editor immediately)
- Added error logging for previously silent catch blocks (helps debugging)
- Codebase cleanup: removed debug logging from Rust engine (Warp implementation) and Flutter UI
- Extracted timeline painters to separate files (WaveformPainter, MidiClipPainter, ClipBorderPainter, GridPatternPainter) reducing timeline_view.dart from 5,166 to 4,692 lines
- Added documentation to web_bindings.rs noting incomplete/experimental status of web support
- Audio Editor controls bar simplified: removed duplicate "Project BPM" display (already shown in transport bar), removed stretch factor display ("→ 1.09x"), original BPM now shows as draggable "[120 BPM]" display matching transport bar style
- Audio Editor waveform now stretches/squeezes when adjusting original BPM (warp ON), matching the behavior in arrangement view
- BPM controls now snap to whole values while dragging; double-click to enter precise decimal values (e.g., 110.50 BPM). Display shows "120 BPM" for whole numbers, "120.50 BPM" for decimals. Applies to both transport bar tempo and Audio Editor original BPM
- Dragging Sampler from Library now correctly creates a Sampler track (was incorrectly creating Synthesizer track)
- Changed MIDI track editor tabs order to [Synthesizer] [Piano Roll] [Effects] (instrument first for quicker access)
- Audio Editor now has Loop toggle button matching Piano Roll (click to enable/disable loop region dimming)
- Audio Editor Start/Length now work like Piano Roll: Start controls loop region start, Length controls loop region length (waveform stays full size)
- Audio Editor waveform now visually scales with Volume slider in real-time (like Ableton): louder = larger waveform, quieter = smaller
- Arrangement view waveforms now also scale with clip gain (matching Audio Editor visual feedback)
- Audio clip gain now affects actual audio playback (per-clip volume control works end-to-end)
- Added Sampler to Library panel under Instruments category (alongside Synthesizer)
- Audio Editor now uses UnifiedNavBar matching Piano Roll exactly: single 24px nav bar with loop region, bar numbers, and zoom controls overlaid at right
- Audio Editor removed all margins (no piano keys needed) for full-width waveform display
- Audio Editor total beats calculation now shows 16 bars buffer beyond clip content (matches Piano Roll)
- Audio Editor loop region now initializes to actual clip duration in beats (was always 4 beats)
- Audio Editor auto-zooms to fit clip content when first opened
- Simplified Audio Editor controls to 5 essentials: Start, Length, Pitch, Volume, BPM. Styled to match Piano Roll layout with consistent button/input styling and orange loop bar for start/length visualization.
- Audio Editor Pitch control is now a draggable knob (-48 to +48 semitones, double-tap to reset to 0)
- Audio Editor Volume control now uses a piecewise dB curve slider (0 dB default, +24 dB max, -∞ min) matching track mixer behavior
- Simplified default project name from "Untitled Project" to "Untitled"
- Replaced "Make a Copy..." with "Save New Version..." in File menu
- Save As now shows keyboard shortcut ⇧⌘S in menu
- Library folders now use accordion behavior (Ableton-style): clicking a folder closes siblings, but remembers nested folder states for when parent reopens
- Nav bar shows progressive subdivision labels: half-beat (1.2.3) at pixelsPerBeat >= 100, all quarter-beats (1.2.2, 1.2.3, 1.2.4) at >= 200. Beat labels (1.2, 1.3) become primary style when subdivisions are visible.

### Bug Fixes

- Fixed Warp mode not actually preserving pitch: was using signalsmith-stretch's streaming `process()` method which doesn't work correctly for batch offline processing. Now uses `exact()` for complete buffer processing with fallback to `process()` for edge cases
- Fixed audio playback not following project tempo: audio now plays at the correct speed relative to the visual timeline at any tempo (was always playing at 120 BPM regardless of tempo setting). Applies to real-time playback and export
- Fixed audio clip warp playback timing: warped clips now end at the correct time matching visual representation (was using original duration instead of stretched duration)
- Fixed multi-track drag state sync: dragging mixed MIDI+audio selections now updates all clip positions in real-time during drag (previously only updated on drag end)
- Fixed library panel scroll jumping to top when expanding/collapsing folders (cached folder contents to avoid FutureBuilder rebuild issues)
- Fixed scroll in nav bar (loop/bar numbers section) bubbling up to parent tabs (was scrolling to Effects section instead of scrolling the timeline)
- Fixed Audio Editor waveform scaling: now correctly uses clip's timeline duration for both waveform display and loop region initialization

---

## v0.1.2 — 2026-01-19

### Improvements

- Multi-type clip dragging: dragging/duplicating now moves ALL selected clips (both audio and MIDI) together, regardless of which clip type you drag from
- Cross-type ghost previews: when duplicating mixed selections, ghost previews now show for both audio and MIDI clips during drag
- Cross-type shift+click selection: shift+click now adds to selection across clip types (audio + MIDI together)

### Bug Fixes

- Fixed audio clip batch delete (eraser tool) not actually deleting clips (they disappeared during drag but reappeared on release)
- Fixed audio clip duplicate not working (Cmd+drag and duplicate tool now work like MIDI clips)
- Fixed eraser tool not detecting clips correctly on multiple audio tracks (Y coordinate calculation excluded non-Master tracks)
- Fixed selection rectangle selecting clips on all tracks instead of only tracks within the rectangle bounds
- Fixed selection rectangle Y offset on lower tracks (cumulative ~20px offset per track due to inconsistent default track height values)
- Fixed modifier-key box selection (Shift+drag) not deselecting clips when rectangle no longer touches them
- Fixed library folder expand/collapse resetting scroll position to top
- Fixed keyboard shortcuts (L, M, Q, Space) triggering when typing in text fields (e.g., renaming tracks)
- Fixed multi-track drag only updating one clip type (MIDI updates now trigger UI refresh)
- Fixed audio clip stretch/trim not registering in undo history
- Fixed editor panel toggle hiding toolbar row (toolbar now always visible in collapsed bar)
- Fixed audio clips not persisting on project save/load (now saved to ui_layout.json)

---

## v0.1.1 — 2026-01-19

### Improvements

- Draw tool: single click on empty space now deselects all clips instead of creating a new MIDI clip (use click+drag or double-click to create clips)
- Simplified duplicate tool: drag to create a single copy at drop position (removed stamp-copy behavior)
- Ghost preview now follows cursor during duplicate drag, showing notes/waveform content
- Duplicated clips become selected after drop (not the originals)
- Loop region auto-follows longest clip until user manually adjusts it
- Eraser tool now supports FL Studio-style drag-to-delete (hold left click + drag over clips/notes)
- Eraser tool deletions are now batched into a single undo action (delete 3 clips = 1 undo, not 3)
- Simplified arrangement playhead: single circle in nav bar, draggable for seeking (no snap to grid)
- Playhead line now spans full arrangement height including master track
- Loop playback now resumes from current position instead of jumping to loop start
- Multi-track selection with Shift+click in mixer panel (Ableton-style)

### Bug Fixes

- Fixed duplicate ghost preview showing empty content instead of notes/waveform
- Fixed duplicated clips not being properly selected after creation
- Fixed selection state getting out of sync after duplicate operations
- Fixed Cmd+drag duplicate shortcut not working when timeline doesn't have keyboard focus
- Fixed modifier key state not being checked correctly on click (could cause wrong tool behavior)
- Fixed MIDI clip content overflowing when zoomed out (icon now hides when clip is narrow)
- Fixed playhead not updating visually when dragged while paused
- Fixed duplicate key error when dragging clips (ghost previews now have unique keys)
- Fixed clip ID collision when duplicating multiple clips in rapid succession
- Fixed Cmd+drag duplicate incorrectly triggering eraser mode on clips dragged over
- Fixed eraser drag-over-clips not detecting clips (incorrect Y coordinate calculation)
- Fixed multi-clip duplicate only selecting one clip after drop
- Fixed eraser tool allowing move/resize on clips instead of only erasing
- Fixed toolbar eraser tool not working on empty timeline space

- Fixed audio engine not loading on release builds (stuck on "Initializing...")
- Fixed window starting too small (~720x480 → now 1280x800, centered)
- App is now code-signed and notarized (no more Gatekeeper warning)
- Fixed library/mixer panels staying hidden after window resize (auto-expand when space available)
- Panels now scale proportionally on first launch based on window size
- Fixed mixer tracks not aligning vertically with arrangement view tracks
- Fixed MIDI clip looping: notes now visually repeat when clip is stretched beyond loop length
- Fixed slight note stretching in looped MIDI clips (was ~1% off due to pixel rounding)
- Added faint vertical line at loop boundaries for clearer visual indication
- Fixed MIDI drone sound when loops repeat (note-off now fires before next note-on)
- Fixed intermittent drone on loop wrap (now silences all notes when seeking/looping)
- Fixed piano roll edits resetting arrangement length on looped clips
- Fixed built-in effects not appearing in library until manual refresh
- Fixed audio files not appearing after loading a saved project
- Fixed audio clips playing at bar 1 even after being moved or deleted (engine/UI position mismatch)
- Fixed duplicated audio clips not being saved correctly to projects
- Fixed audio clips shifting position when tempo changes (now maintain beat position like MIDI clips)

---

## v0.1.0 — 2026-01-16

> Initial public alpha. Early test build for validating the build and release pipeline.

### Features

**Audio Engine**
- Multi-track audio recording and playback
- Built-in effects: EQ, Compressor, Reverb, Delay
- WAV file export
- Configurable audio latency (buffer size)

**MIDI & Instruments**
- Piano roll editor with note preview
- Built-in polyphonic synthesizer (8 voices, sine/saw/square/triangle)
- ADSR envelope and lowpass filter
- MIDI clip editing with bar-snapping

**VST3 Support**
- Plugin scanning and loading
- Plugin UI hosting (docked and floating windows)
- Plugin state persistence with projects

**User Interface**
- 3-panel layout: Library, Timeline, Mixer
- Mixer with stereo level meters
- Resizable panels and track heights
- Native macOS menu bar integration
- Keyboard shortcuts

**Project Management**
- Project save/load
- Track duplication
- Inline track renaming

### Known Issues

- ~~Duplicate button can behave unexpectedly~~ → Fixed in v0.1.1
- ~~Window may not start at correct resolution~~ → Fixed in v0.1.1
- ~~Audio engine fails to load in release builds~~ → Fixed in v0.1.1
- ~~App is not code-signed (macOS Gatekeeper warning)~~ → Fixed in v0.1.1
- ~~Library panel hidden if window is too narrow~~ → Fixed in v0.1.1
- Virtual piano keyboard is disabled (planned for v0.2)
- ~~Built-in effects require refresh before appearing~~ → Fixed in v0.1.1
- ~~Clip names can overflow in arrangement view~~ → Fixed in v0.1.1
- Windows build not yet tested
- ~~Undo/redo can be unreliable~~ → Fixed in v0.1.1
- Audio clip context menu items (cut/copy/paste, split, mute, rename, color) not yet functional (planned for v0.2)
- ~~Duplicate and delete tools may behave unexpectedly in some cases~~ → Fixed in v0.1.2
- ~~Multi-track drag: dragging selection with both MIDI and audio clips may only update one type until refresh~~ → Fixed in v0.1.2
- ~~Undo not working for audio clip stretch/trim operations~~ → Fixed in v0.1.2
- ~~Keyboard shortcuts override text input when renaming tracks in mixer (e.g., "L" triggers loop toggle)~~ → Fixed in v0.1.2
- ~~Editor panel toggle hides toolbar row (Piano Roll/Effects/Synthesizer tabs, tools, virtual piano toggle)~~ → Fixed in v0.1.2
- ~~Audio clips not persisting on project save/load~~ → Fixed in v0.1.2
- ~~Library folder expand/collapse resets scroll position to top~~ → Fixed in v0.1.2

---

[View all releases](https://github.com/tyrbujac/boojy-audio/releases)
