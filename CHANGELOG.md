# Changelog

All notable changes to Boojy Audio will be documented in this file.

## Unreleased

### Features

- Multi-note resize: when multiple notes are selected, resizing one resizes all by the same delta

### Bug Fixes

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
