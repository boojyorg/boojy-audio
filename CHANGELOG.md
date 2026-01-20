# Changelog

All notable changes to Boojy Audio will be documented in this file.

## Unreleased

### Features

- Added Sampler track type with pitch-shifted sample playback triggered by MIDI notes
- Added Sampler Editor with Attack/Release envelope controls and Root Note selection
- Added "Open in Sampler" context menu option in Library panel for audio files
- Added "Convert to Sampler" context menu option on Audio tracks (creates Sampler track with MIDI notes at original clip positions)
- Added "Rename Project..." menu item in File menu (only shown for saved projects)
- Added "Save New Version..." to create versioned copies with symlinked samples (e.g., My Song_v2.audio)
- Rename now updates recent projects list (removes old path, adds new path)

### Improvements

- Audio Editor now uses UnifiedNavBar matching Piano Roll exactly: single 24px nav bar with loop region, bar numbers, and zoom controls overlaid at right
- Audio Editor removed all margins (no piano keys needed) for full-width waveform display
- Audio Editor total beats calculation now shows 16 bars buffer beyond clip content (matches Piano Roll)
- Audio Editor loop region now initializes to actual clip duration in beats (was always 4 beats)
- Simplified Audio Editor controls to 5 essentials: Start, Length, Pitch, Volume, BPM. Styled to match Piano Roll layout with consistent button/input styling and orange loop bar for start/length visualization.
- Simplified default project name from "Untitled Project" to "Untitled"
- Replaced "Make a Copy..." with "Save New Version..." in File menu
- Save As now shows keyboard shortcut ⇧⌘S in menu
- Library folders now use accordion behavior (Ableton-style): clicking a folder closes siblings, but remembers nested folder states for when parent reopens

### Bug Fixes

- Fixed multi-track drag state sync: dragging mixed MIDI+audio selections now updates all clip positions in real-time during drag (previously only updated on drag end)
- Fixed library panel scroll jumping to top when expanding/collapsing folders (cached folder contents to avoid FutureBuilder rebuild issues)

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
