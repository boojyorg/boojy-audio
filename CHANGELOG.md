# Changelog

All notable changes to Boojy Audio will be documented in this file.

## Unreleased

### Features

- **You see your audio while you record it.** Each armed audio track shows a clip that grows
  from the record point with its waveform drawing in as you play, under the same red recording
  header as MIDI takes. Each track shows its own input ("In 1" / "In 2"), and the clips it
  records over are hidden until you stop, as they are for MIDI. Audio takes no longer show an
  empty MIDI box on the selected track.

- **Arming an audio track opens your input.** The track's meter moves and you hear yourself
  straight away, before you press record, and the input stays open between takes while the
  track is armed. Disarming closes it. If Boojy gets no sound, a notice says "Boojy can't hear
  your input" with *Open Settings*. This happens when the input is off, the device won't open,
  or the input gives only digital silence (a closed laptop lid or a blocked microphone). The
  notice clears itself once sound arrives. With the computer's own mic and speakers, arming
  leaves monitoring off so it can't howl, and suggests headphones; the I button turns it on.
  Tracks created by dropping a file start unarmed, so they don't open the microphone.

- **Boojy notices replace the plain message bar.** Messages now appear as a small rounded pill
  at the bottom-centre of the arrangement, clear of the transport, ruler and panels. There are
  two kinds. A grey hint ("Select a clip to quantize") fades after three seconds, and hovering
  it holds it. A problem ("Couldn't save the project") is marked by a small amber ⚠, stays
  until you close it, and some carry a button such as *Open Settings*. Success messages are gone: saving, renaming,
  adding an effect or picking a device just works, quietly. Problems now use plain words, and
  the technical detail goes to the log. Shortcuts that used to do nothing silently (quantize,
  duplicate, join or bounce with no clip selected) now say what they need, and a recording that
  captured nothing now says so.

- **The library is one tree.** The two-column browser (categories on the left, contents on the
  right) is replaced by a single full-width tree. Favorites, Sounds, Samples, Instruments, Effects,
  Plugins and each added folder are root rows: click one to open it in place, click again to
  close it, and keep as many open as you like. Subfolders open with a chevron in place of a
  folder icon, so every level indents by the same small step and long sample names get the whole
  panel width. Names that still truncate show in full on hover. Opening a root or clicking into
  it scopes the search box to that section (the placeholder and a chip say so; the chip's × goes
  back to searching everything). Arrow keys walk the tree: Up/Down move, Right opens or steps
  in, Left closes or steps out, Enter loads, Space previews. Preview, drag to the arrangement,
  favourites and the folder and item context menus work as before. The panel also opens
  narrower now that it has no second column: 240px by default (was 308) and it can be dragged
  down to 160px (was 208).

- **Capture MIDI button in the transport bar.** A button immediately right of Record captures the
  phrase you just played unarmed into a new clip at the playhead. Press it once — it flashes to
  confirm it fired. (Backend existed since v0.2; button re-added in v0.7.)

- **A simpler toolbar.** The top of the window is one bar again: the separate title row is
  gone (macOS keeps its traffic lights on the bar, nudged a touch down and right to sit with
  the controls; the bar still drags the window and the lights' space closes up in full screen),
  the ▲udio
  wordmark now opens the app menu (Settings, Keyboard Shortcuts, Start Screen; its triangle
  still turns red when the audio engine didn't start), and the project name beside it opens
  the project menu as before. The permanent ? button and the two add-track buttons leave the bar: the
  shortcuts sheet is under Audio and on the ? key, and **+ MIDI / + Audio now sit at the top of
  the mixer panel**, which is the track list. Library and Mixer get glyphs that name the panel
  (books, sliders), a lighter grey while the panel is open and darker while it is closed. The centre reads Snap · Loop ·
  Metronome · Count-in · Play · Stop · Record · Capture, then the position, tempo and time
  signature.

- **Snap remembers its grid.** The grid glyph turns snapping on and off; the value beside it
  ("Bar ▾") picks the resolution. Turning snap off dims the value instead of hiding it, so the
  layout never shifts and you can see what grid comes back. Piano-roll snap is untouched.

- **Count-in is a labelled toggle** beside Metronome: Off or one bar, on by default. The lead-in
  bar always clicks, even with the metronome off, so a silent count never looks like a stuck
  Record button; the metronome toggle governs the click during playback and recording only.
  Two- and four-bar count-ins are gone (an old preference or project value loads as one bar),
  and the count-in stored in a project file no longer overrides your preference when the
  project opens.

- **Punch in/out is removed for now.** The Loop dropdown, the I and O keys and the red punch
  colouring on the ruler are gone; Loop and Metronome are plain toggles. Nothing in a saved
  project depended on punch, and the engine can no longer be put into punch mode from the UI.

- **Audio Cmd+D now duplicates audio clips.** Previously Cmd+D only worked when a MIDI clip was
  open for editing. Now it also duplicates the selected audio clip in the arrangement.

- **Legato operation in the piano roll.** A Legato button in the controls bar extends each note
  to the start of the next note in time. With no selection it applies to the whole clip. Flashes
  accent on press to confirm it fired (same cue as Quantize).

- **Velocity lane toggle in the piano-roll controls bar.** The Velocity button opens and closes
  the velocity lane directly from the controls bar.

### Bug Fixes

- **Mixes are 3 dB louder: the master's pan is a balance control.** A centred track lost 3 dB
  to its own pan and another 3 dB to the master's, so everything played 6 dB under its source.
  Tracks keep the usual −3 dB at centre; the master's pan now only turns one side down. Existing
  projects play 3 dB louder.

- **Audio clips play back clean.** Playback picked each sample's position by truncating a float,
  so about 1 sample in 17 replayed its neighbour: a fine grit or crackle on every audio clip,
  most audible on recordings. Playback and export now play every sample in order (a rendered
  take matches the file sample for sample).

- **Dragging a number keeps the pointer still.** Dragging the tempo, time signature, a knob, the
  volume readout, or the audio editor's BPM, pitch or loop length now hides the pointer and leaves
  it where you pressed; it reappears there when you let go, and a long drag no longer runs into
  the top of the screen (macOS and Windows; touch is unchanged). Dragging the audio editor's BPM
  re-stretches the clip once when you let go, with one undo step, instead of on every step.

- **Warped clips stay in time when you change the project tempo.** Warp worked out how much to
  stretch a clip once, from the tempo at that moment, and kept that number. After a tempo change
  the clip moved and resized on the timeline but played at its old speed, and reopening the
  project brought the old speed back. The stretch now always comes from the clip's BPM and the
  current tempo; every warped clip re-stretches when a tempo change is finished (on release when
  dragging). Re-stretching no longer holds up playback while it works.
- **Warped clips draw their waveform at the right length.** The timeline measured a warped clip's
  loop in project beats but its audio in its own, so at 120 BPM a 150 BPM loop showed only its
  first 80%, stretched across the clip. Projects saved this way are corrected when opened.
- **Undo in the audio editor changes the sound back.** Undoing a warp, gain, pitch or reverse
  edit updated the editor but the clip kept playing with the edit.

- **Warped and reversed clips export clean, and MIDI lands on its sample.** A full-mix export
  kept an old copy of the clip-playback maths, so a warped clip still had the grit in exports
  (about 2 samples in 3 played one step late). It now uses the same code as playback. Reversed
  clips started with a silent sample, played every sample one step late and never reached
  their first sample. Every clip played one sample past its end. Notes in a MIDI clip could
  start one sample early. Engine tests now check rendered audio sample by sample.

- **A take recorded straight after Record → New Audio Track is kept.** The UI decided whether a
  take had audio from its own track list, which hadn't yet seen the new track armed, and
  discarded the clip. The finished clip is now placed where the engine recorded it.
- **Waveforms no longer flicker, pump or throw while drawing.** On a growing clip the detail
  level flipped every frame, and a half-filled last group respaced the whole waveform, so audio
  already recorded looked like it changed volume. Clips under 100 waveform points raised an
  error.

- **Recorded audio no longer crackles, sits on the left, or drops clicks.** The input opened at
  the device's own rate (a Scarlett at 44.1 kHz) while Boojy runs at 48 kHz, leaving about 170
  tiny gaps a second in the take and in what you hear; it now opens at Boojy's rate. With one
  armed track the take kept the raw stereo pair, so a mic in input 1 played left only; takes
  now record the track's input channel in the centre. And the audio thread no longer waits on
  the input meters, which could drop a sample each time they were read.
- **Record no longer offers "New MIDI Track / New Audio Track" with a track armed.** It checked
  for armed tracks only when the toolbar last redrew, and arming in the mixer doesn't redraw it.
  It now checks when you press Record.

- **Reopening a project brings everything back.** Audio clips no longer vanish from the
  arrangement, tracks keep their colours, MIDI clips keep their names, mute and loop settings,
  and colour overrides, automation and the selected track stay on the right track. Tracks and
  clips now keep their numbers when a project opens, and the arrangement rebuilds its audio
  clips from the engine's copy of the song, so projects already affected get their audio back
  too (clip gain, warp and pitch from those older saves come back as defaults). Saving no longer
  re-copies audio into the project's `audio` folder under ever-longer names
  (`014-010-007-…wav`); files already there are reused, and nothing is deleted. Waveforms are
  redrawn when a project opens instead of being stored, so the layout file shrinks from about
  2 MB to a few KB. Opening a project now fully clears the previous one first, and New Project
  numbers tracks from 1 again.
- **macOS menus no longer flicker shut.** A menu you opened closed within half a second, because
  a background MIDI check redrew the whole screen twice a second; menus now only refresh when
  something in them changes.
- **One audio input, chosen in Settings.** Settings → Audio → Input now offers System default
  (follows macOS, so plugging in an interface just works), each connected device, or Off, and
  the choice applies at launch and the moment you change it. Before, the engine grabbed the macOS
  default once at launch and ignored the Settings choice after a restart. A chosen device that
  isn't plugged in falls back to the system default, and recording says so. Each audio track
  now picks only a channel ("Input 1", "Input 2") of that input; its device choice never did
  anything. With input off, or when the input can't open, recording no longer leaves an empty
  audio clip.

- **The computer-keyboard piano plays wherever you click.** Its keys only worked while the
  piano itself had focus, so after clicking a track or a button every note key went unhandled
  and macOS played its error sound. The piano now listens app-wide while it is open (never while
  you type in a text field or hold Cmd, Ctrl or Alt), and L plays its note instead of toggling
  the loop. Notes go to the armed MIDI track, or the selected track when none is armed, so you
  hear the track you are recording onto.

- **Audio recordings show up again.** Recording on an armed audio track left an empty box
  instead of a clip with a waveform: the engine names track types "Audio" and "MIDI", the
  recording code looked for "audio" and "midi", so it never found the armed track and dropped
  the take (the engine still kept it, so the saved project and the screen disagreed). MIDI
  recording had the same mismatch and fell back to the selected track instead of the armed one.
  Track types now compare case-insensitively, with a test against the real engine.

- **Ruler drag zoom now holds the bar under the pointer.** Dragging vertically on the arrangement
  ruler used to zoom around bar 1, so whatever you were looking at slid off screen; the piano roll
  corrected its scroll a frame late, which wobbled; and the audio editor re-centred the anchor on
  every move. All three now share one implementation: the beat you press on stays under the
  pointer for the whole gesture, horizontal travel scrolls and vertical travel zooms as one
  continuous motion, and the zoom is exponential, so equal travel is an equal ratio in both
  directions and a round trip lands back where it started. Drag down zooms in (matching
  Ableton's beat-time ruler; it was up = in). The piano roll's middle-mouse grid drag follows the
  same direction and feel.

- **Clicking the ruler once scrolled past bar 1 set the playhead at the wrong bar.** The ruler
  counted its scroll offset twice, so a click, a hover highlight or a loop-edge grab landed
  `offset` beats too far right whenever the view was scrolled. Fixed in the same change; the
  regression test covers a scrolled click.

- **Transport controls no longer shrink at narrow window widths.** The loop, snap, metronome
  and readout buttons in the centre of the transport bar were scaled down whenever the bar got
  tight (to about half size at the 960 px minimum window, and already visibly at 1400 px), while
  the wordmark, undo/redo and Add-track buttons stayed full size. The centre cluster now keeps
  its glyph size at every width: it sheds labels, then gaps, then the tempo and signature
  readouts, and below ~1110 px windows the side rails give up the room instead (the Add MIDI /
  Add Audio labels drop and the project name truncates sooner). The transport stays on the window
  midpoint throughout.

- **Dragging an audio clip partly over a neighbour no longer deletes it.** Overlap resolution
  deleted any neighbour left shorter than 0.25 seconds after a trim, and snapping at the default
  zoom moves clips in 0.25 second steps, so nudging a clip onto a short sample (most of the
  bundled drum hits) wiped it instead of trimming it. A partial overlap now always trims: the
  neighbour keeps whatever remains, however short, and only a full cover deletes. The same rule
  applies to MIDI clips, splits, file drops and recordings, which share the resolver. Undo
  restores the trimmed clip exactly, in the engine as well as on screen.

- **MIDI keyboard plugged in after launch now works automatically.** A background poll detects
  newly connected keyboards and opens the MIDI port — no Settings visit needed. Also fixes the
  Refresh button which re-enumerated devices but never re-opened the port.

### Improvements

- **Tracks stop changing themselves.** Colour and icon no longer follow the track's name or
  instrument (new tracks take the next palette colour; one icon per type), and new clips take
  the track's name. Dropping an instrument renames a track only while its name is still
  automatic ("MIDI 2", "Synthesizer", a plugin's name), never one you typed, even after reopening.
- **Controls that did nothing are gone**: Add Marker, dead clip-menu items, Bounce to Audio, the
  toolbar Snap, the C-major Scale toggle, the empty Sounds root, Copy Path, Open GUI and menu
  placeholders. Split at Playhead now works on audio clips; ⌘E splits, ⇧⌘E toggles the editor.
- **Minimum macOS is now 12 (Monterey).** Xcode 27 no longer builds for older versions, so
  Macs that can't run macOS 12 or later won't get this or future updates.

- **The ruler's [-] [+] zoom buttons are gone.** Every ruler (arrangement, piano roll, audio
  editor, sampler) zooms by dragging vertically or with the scroll wheel, so the pinned buttons
  at the right edge only covered the last bar numbers. Removing them frees that strip.

- **Automation lanes open per track.** The global Automation button at the top of the mixer
  panel is gone. Right-click a track and choose Show Automation to open that track's lane under
  its clips (Hide Automation closes it); other tracks stay as they were. The lane's parameter
  picker and clear button still appear on the track strip while the lane is open.

- **Dead-code pass.** Removed about 10,000 lines that no user could reach: the Dart-side fake
  web target and the engine's WASM modules, the legacy Snapshot and half-built project-version
  features, the superseded VST3 parameter panel and plugin browser, an old track header, a
  horizontal meter, a file drop zone, a standalone clip-automation lane, the unused View menu,
  seven barrel files, unrendered piano-roll controls (ghost notes, scale root/type pickers and
  lock, swing, humanize, stretch, reverse), an "Export MIDI coming soon" placeholder, two engine
  functions no UI called, and two unused images. Per the "inert controls work or are hidden"
  decision: the cosmetic project sample-rate picker is gone (the engine always runs at 48 kHz),
  the disabled Zoom items left the View menu, and the Updates section in Settings is hidden on
  Windows until a native updater exists.
- **Platform plan recorded** (`docs/PLATFORMS.md`). Beta ships on macOS and Windows; Linux, web
  and iPad are v1.0 candidates. The doc records why the stack stays Flutter + Rust, the
  alternatives assessed, a quality ceiling per platform, and the work each platform needs. The
  backlog's platform decisions and v1.0 prep items were updated to match.
- **README rewritten for musicians first.** Opens with what Boojy is for, then downloads for
  macOS and Windows, an alpha note, five capabilities checked against v0.6.0, and a
  developer-only "Build from source" section. Removes claims the build doesn't back (pan
  automation lanes, a Cmd+K command palette, "WASM-ready") and fixes the shortcut table
  (library/mixer are Cmd+L/Cmd+M; M is the metronome). All GitHub links now point at the
  `boojyorg` organisation instead of relying on the rename redirect.
- Docs cleanup, pass 3 of 3 — `docs/BACKLOG.md` rewritten against the code. Every item is
  self-describing (no review IDs), sorted into Now / Next / Parked / Decisions, and each "verify
  before claiming" note was checked on 2026-09-13: swing has no control, the CC lane and ghost
  notes are unreachable, the scale toggle has no picker, the project sample-rate dropdown is
  cosmetic, menu zoom items are disabled placeholders, master has no branch protection. The June
  triage moved to `docs/archive/reviews/`.
- Docs cleanup, pass 2 of 3 — one home per fact. `AGENTS.md` is now a ~100-line index that
  points at `.claude/rules/` instead of repeating them; release process, version sync, the
  Windows smoke test and review cadence moved to `docs/RELEASING.md`; `ARCHITECTURE.md`
  rewritten to describe the current system without tutorials or stale inventories;
  `target_audience.md` became `docs/PRODUCT.md` with the scope anchors; `state.md` folded into
  `flutter-ui.md`; the README dropped its duplicate directory tree.
- Docs cleanup, pass 1 of 3: deleted the stale `engine/VST3_TESTING.md` (described VST3 hosting
  as unfinished), trimmed `engine/vst3_host/README.md` to current build steps, removed a
  duplicated v0.2.1 changelog block, and dropped "collaboration" from the README tagline.

- **Contribution policy simplified** (`CONTRIBUTING.md`, `README.md`): personal project, no
  external code contributions, feedback and bug reports by email to tyr@boojy.org.

- Restored CI compatibility by pinning Rust and the Windows runner/toolchain, updating
  fixed-size sample iteration for strict Clippy, and using overflow-safe stereo midpoints.

- Consolidated planning into `docs/BACKLOG.md`; paused the v0.7 feature theme while
  documentation health is the active priority. Retired duplicate planning documents and
  preserved the previous plan as historical reference.

- **All right-click menus now use the shared rounded surface.** Device chain (effect headers,
  instrument header, swap dropdown), library panel (user folder, item, VST3), timeline ruler,
  empty-track area, drag-create track-type picker, track header, and record menus (count-in,
  new-track) have all been migrated from the default grey Material `showMenu` to the Boojy
  rounded overlay — consistent hover fill, icons, keyboard-shortcut hints, destructive Delete
  styling (red), and rounded corners throughout. Also fixes a silent debug-mode no-op in the
  library folder menu (listen:false footgun in the right-click handler).

- **Project Settings dialog redesigned.** Slimmed to the essentials: project name, time signature,
  sample rate, and read-only created/modified dates. BPM (already in the transport bar), key/scale,
  style tag, and the versions panel have all been removed. Dialog chrome now matches the App
  Settings dialog (rounded border, elevation, barrier tint).

- **All remaining Material `DropdownButton` sites migrated to `BoojyDropdown`.** Project Settings
  (time signature, root note, scale, sample rate), Export (MP3 bitrate, WAV bit depth, sample
  rate), Capture MIDI duration, Synth waveform type, and Mixer automation parameter now all use
  the shared rounded chip + themed menu surface.

- **Piano-roll Snap and Quantize menus now match every other dropdown.** The two value menus
  (which grid division and quantize resolution to use) have been migrated from hand-rolled
  `OverlayEntry` popups to the shared `showBoojyMenu` surface — same rounded card, hover fill,
  and trailing check on the current value. Triplet variants (`1/8T`, `1/16T`, etc.) are now
  first-class items in the list rather than a separate checkbox modifier, matching how the
  transport Snap menu already presents them. The split-button chrome (one-tap snap toggle on the
  left, one-tap quantize action on the left) is unchanged.

### Bug Fixes

- **Deselecting a track no longer slams the editor shut.** Clicking an empty area of the mixer
  to deselect used to collapse the whole bottom editor panel (a 250px→40px reflow on every
  click). The panel now stays open at its height: the toolbar (Draw/Select tools + the collapse
  chevron) stays put and the content area shows a "No track selected" hint. Pick a track and its
  instrument/notes return. Manual collapse via the panel chevron still works.

- **The position and tempo readouts respond instantly.** Both readouts carried a double-click
  gesture that made every single click (cycle the position mode, start a tempo drag) wait
  ~300 ms for a possible second click. Double-click still works (jump to bar / type a tempo) —
  it's just detected manually now, so the first click lands immediately.
- **A single click on a mixer fader no longer teleports the volume.** Clicking the fader body
  used to jump the volume straight to the click point — one misclick and your level was gone.
  Volume now only changes by dragging (or double-click to reset to 0 dB).
- **The Light theme renders correctly in more places.** The audio-file drop zone, the selected
  device border, the piano-roll Snap/Quantize menus, the loop-region dimming, and the virtual
  piano's resize handle all hardcoded dark-theme colours; they now follow the active theme — as
  does the arrangement canvas, which stayed dark grey on Light. A new Cmd+Shift+T shortcut
  cycles Dark ↔ Light (persisted like the Settings picker).
- **Changing the tempo during loop playback keeps the loop in time.** The loop kept wrapping at
  the old tempo's wall-clock bounds — speed up and the playhead sailed past the loop end, slow
  down and it cut back early, until you stopped and replayed. The loop bounds, playhead, and
  stop-return positions now re-anchor to the same beat on every tempo change.
- **Saving or loading a project can no longer freeze the app.** The save/load path took the
  engine's internal locks in the opposite order to the audio callback, so a save landing in a
  microsecond-wide window deadlocked the engine silently — no crash, no error, the app just
  hung. Rare on fast machines, but it froze CI twice in a row. Both paths now follow the
  callback's lock order.
- **Resizing a freshly drawn note no longer moves it.** After drawing a note, dragging its edge
  showed the resize cursor but moved the note instead — the "just created" drag-to-move tracking
  survived past the creating click and hijacked the next gesture. It's now cleared when the
  click ends, so create-then-drag in one gesture still moves, and a new drag on the edge resizes.
- **The add-effect [+] menu opens at the button.** It used to appear at the far-right edge of
  the editor panel because the popup anchored to the whole chain view instead of the [+] itself.
- **New tracks only get colours you can pick.** Auto-detected track colours came from a separate
  9-colour map (plus a legacy 8-colour list) that didn't match the 16-colour picker — every
  default now uses a picker colour, guarded by a test. Two swatches were tuned along the way:
  the vibrant red is now a true red (the old coral read pink), and the vibrant blue is now the
  Boojy accent blue, so the Master track's colour is a pickable swatch too.
- **Clicking the ▲udio wordmark opens the Start screen** (it used to open Settings — Settings
  lives on the menu and the Start screen's gear). The triangle still turns red if the audio
  engine fails to start.
- **Library polish:** clickable folders and section headers show a pointer cursor, and
  "+ Add Folder" has proper hover and press states.
- **In-app updates now actually offer new versions.** Sparkle compares build numbers, but the
  appcast advertised the semver string — so every install compared e.g. `9` against `0.6.0`,
  decided it was newer, and reported "You're up to date." The appcast now carries the build
  number (the published v0.6.0 entry is hot-fixed too, so v0.5.4 installs get the offer), each
  entry's download link is pinned to its own release instead of `latest`, and the app's feed URL
  points at the current repo name instead of relying on GitHub's rename redirect.

### Improvements

- **Settings dropdowns and switches share one clean style.** Every dropdown in Settings is now a
  compact pill that opens a rounded menu — each row highlights on hover and the current value gets
  a tick on the right (the same language as the Library list). Boolean settings (auto-save,
  "continue where I left off", and the rest) are now on/off toggles instead of tick boxes, since
  they take effect immediately.
- **Settings explain what each option does.** Audio and appearance rows now carry a one-line
  description under the label — e.g. Input reads "Where Boojy records from — your mic or
  interface", Buffer Size reads "Lower = less delay but more load on your computer" — so you don't
  need to already know the jargon.
- **The piano-roll keyboard lanes are readable again.** Row separators were drawn in the same
  colour as the white-key background, so you couldn't tell where one note ended and the next
  began; the black-key lanes were barely a shade darker. Separators are now a visible hairline
  and the black-key shading is deeper, so the lanes read as a keyboard at a glance.
- **A "Scale" toggle in the piano-roll toolbar highlights the scale.** Turning it on marks the
  root-note rows and dims out-of-scale notes (the scale-highlight rendering existed but had no
  on-screen control). With it off, the root-row tint no longer appears — previously every C
  showed an unexplained cyan band whether or not you wanted scale highlighting.
- **Note labels keep their sharps when zoomed out.** At intermediate zoom a note like C♯ showed
  just "C", making chromatic runs look diatonic; the label now keeps the accidental and only
  drops the octave number.
- **The "drag an instrument" prompt shows for return-only projects too.** A project containing
  only the Master and return tracks (no user tracks) now shows the empty-state prompt instead of
  floating it over what looked like a populated arrangement.
- Transport Pause/Stop colours, the timeline/piano-roll grid painters, and the note painter now
  come from theme tokens instead of hardcoded values, and the transport's play/stop/record
  buttons and readout gestures gained regression tests.

## Earlier releases

Short highlights. The full notes for every release up to v0.6.0 are in the
[CHANGELOG at the v0.6.0 tag](https://github.com/boojyorg/boojy-audio/blob/v0.6.0/CHANGELOG.md).

## v0.6.0 — 2026-06-11

- **Drum Kit:** make your first beat with a step sequencer and a pre-loaded starter kit (six
  bundled one-shots); steps paint with a drag, and pad volume, mute and solo undo.
- **The Sampler is a one-screen instrument**, and its edits (including loading a sample) undo.
- **Volume automation lanes are on**, and **Join clips (Cmd+J)** is a real, undoable edit for
  MIDI and audio.
- **Input monitoring toggle** on armed audio tracks; arming is exclusive for every track type.
- **Piano roll** gains vertical zoom and a live playhead; **Reverse** actually reverses audio.
- **Timing:** audio clips play at the right time and speed at every tempo, and tempo changes no
  longer corrupt playback or knock the metronome off the beat.
- **Responsiveness:** Mute, Solo, Arm and Monitor respond instantly; Space keeps working after
  clicking a button; timeline gestures work when scrolled past bar 1.
- **One calmer look:** a unified "selected" style, one header for every device card, solid panel
  dividers, the real ▲udio wordmark, and a top bar that degrades gracefully when narrow.
- About 40 more fixes, including saving projects with recorded audio, working Favourites, and
  "Show in Finder" on Windows.

## v0.5.4 — 2026-06-06

- Save As, Open Project and Export work on Windows; the first-launch tutorial no longer starts
  by itself.

## v0.5.3 — 2026-06-06

- The Windows installer ships the audio engine; new app icon on macOS and Windows.

## v0.5.2 — 2026-06-06

- **Reliability pass:** correct speed, pitch and effect timing on non-48 kHz devices;
  unplugging the interface stops playback with a message; hot-plugged MIDI keyboards work.
- **Saving and reloading** no longer lose held notes or audio clips or falsely report success.
- **Export:** starts from silence, respects the range and loudness targets, and stems sound
  like the mix.
- **No more clicks** on staccato notes or big chords; the Sampler is usable; auto-update works
  again.

## v0.5.1 — 2026-06-05

- Right-click → Delete deletes the track; add-track buttons move to the top bar; the Master strip
  is selectable.

## v0.5.0 — 2026-06-04

- **The built-in EQ is a graph you draw on**, and mixer dB readouts are editable.
- **Undo you can trust:** split, consolidate, note deletion and track deletion all undo fully,
  and a failing action no longer disappears silently.
- **Export and projects:** mono exports are mono, automation survives export, broken projects
  say so, and non-default tempos reopen on the grid.
- **VST3** follows the activation protocol; preset changes are heard.
- **Look:** UI Scale scales the whole app, one set of colours, a refined dark-grey canvas.

## v0.4.0 — 2026-06-01

- **MIDI keyboards just work:** a plugged-in keyboard is picked up automatically.
- **UI Scale** in Settings → Appearance (Compact to Large).
- **A calmer, centred top bar:** the ▲udio wordmark doubles as the engine-health light,
  tap-tempo lives in the BPM box, and the app ships Inter and JetBrains Mono with one cooler
  dark palette.
- **Recording** resumes on the beat with a visible count-in; Play turns into Pause while
  recording.
- **Sentry crash reporting removed** until beta.
- About 20 fixes, including VST3 instruments reloading with sound, the top bar overflowing in
  narrow windows, and the app reporting the wrong version.

## v0.3.2 — 2026-05-30

- **Audio-thread safety:** VST3s no longer glitch under load, runaway plugins can't blast noise,
  reverb and delay tails no longer spike CPU, and plugin editors can open during playback.
- Clip drags onto occupied spots no longer overlap or destroy clips.

## v0.3.1 — 2026-05-30

- **Data-loss fixes:** stereo exports, correct redo, time signatures and MIDI CC survive
  reload, and a multi-clip drag is one undo step.

## v0.3.0 — 2026-05-25

- **Send/return buses** with editable return effects; reverb sends are audible and survive
  reopening; audio clips no longer drop on reload.

## v0.2.4 — 2026-05-22

- Windows CI; undo gaps closed; MIDI clip moves sync to the engine.

## v0.2.3 — 2026-05-22

- Project saving centralised; first golden-path integration tests.

## v0.2.2 — 2026-05-22

- Piano-roll redesign: clearer keyboard and rows, notes in the track colour, simpler controls.

## v0.2.1 — 2026-04-07

- Track colours and the loop region persist; mixer overflow fixes.

## v0.2.0 — 2026-04-02

- Sustain pedal support, VST3 instruments as first-class instruments (presets, float or embed),
  an audio editor tab for audio tracks, and a first-run tour.

## v0.1.7 — 2026-03-27

- Top bar redesign: loop split button, position display, tempo scroll, snap and time-signature
  menus, responsive density.

## v0.1.6 — 2026-03-25

- **The Sampler**, punch in/out, scale snapping and clip-overlap prevention; a design-system
  pass; engine safety fixes (FFI panics, audio-thread allocation).

## v0.1.5 — 2026-02-04

- MIDI file import and export, a redesigned recording workflow with automatic input monitoring,
  and recording timing fixes.

## v0.1.4 — 2025-01-27

- Library audio preview, and clip-based volume automation that affects playback.

## v0.1.3 — 2025-01-22

- Audio clip looping, warp (time-stretch to tempo) and pitch, the first Sampler track, and
  Save New Version.

## v0.1.2 — 2026-01-19

- Multi-clip editing: drag, duplicate and select across audio and MIDI clips; audio clips
  persist in projects.

## v0.1.1 — 2026-01-19

- Tool and selection fixes: batched eraser undo, a simpler duplicate tool, a draggable playhead.

## v0.1.0 — 2026-01-16

- First release: MIDI and audio tracks, a built-in synth, recording, a piano roll, a mixer
  with effects, and VST3 hosting.
