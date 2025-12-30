# Boojy Audio - UI Design Notes

**Last Updated:** October 27, 2025
**Current Version:** M5.5.1 (UI Redesign + Resizable Panels Complete)

**Related Documentation:**

- [FEATURES.md](FEATURES.md) — Complete feature specification for all versions
- [ROADMAP.md](ROADMAP.md) — Vision, timeline, and development progress
- [IMPLEMENTATION.md](IMPLEMENTATION.md) — Detailed development tasks

---

## Current UI State

### Layout Overview

Boojy Audio now has a professional 3-panel DAW interface similar to Ableton Live:

```
┌─────────────────────────────────────────────────────────────────┐
│  AUDIO    |  Transport Controls  |  Tempo  Time  CPU  |  📁 ⚙️  │ Transport Bar
├──────────┬────────────────────────────────────┬─────────────────┤
│          │                                    │                 │
│ Library  │         Timeline (Multi-track)     │     Mixer       │
│  Panel   │      (with Track Headers)          │     Panel       │
│          │                                    │                 │
│ (200px)  │           (flexible)               │    (300px)      │
├──────────┴────────────────────────────────────┴─────────────────┤
│        Bottom Panel: [Piano Roll | FX Chain | Virtual Piano]    │
└─────────────────────────────────────────────────────────────────┘
```

### Color Scheme (Light Grey Theme)

#### Side Panels
- **Background:** `#707070` (medium grey)
- **Headers:** `#656565` (slightly darker for hierarchy)
- **Borders:** `#909090` (light grey, subtle separation)
- **Use:** Library panel (left), Mixer panel (right), Transport bar (top), Bottom panel

#### Center Timeline (Focus Area)
- **Background:** `#909090` (light grey - **lighter than sides**)
- **Track Rows:** `#9A9A9A` (even lighter for individual tracks)
- **Borders:** `#AAAAAA` (very subtle)
- **Grid Lines:** `#A0A0A0` (subtle grid)
- **Use:** Main timeline area where user works

#### Text Colors (Dark on Light)
- **Primary Text:** `#202020` (very dark grey, almost black)
- **Secondary Text:** `#353535` (dark grey for less important text)
- **Tertiary/Disabled:** `#505050` (medium-dark for disabled elements)
- **Icons:** `#404040` (medium-dark)

#### Special Elements
- **Status Bar:** `#606060` background, `#808080` border (darker to anchor bottom)
- **Master Track:** `#606060` background with `#4CAF50` green border

#### Accent Colors (Unchanged from Dark Theme)
- **Green:** `#4CAF50` (play, success, active)
- **Red:** `#FF5722` (record, error, danger)
- **Yellow:** `#FFC107` (warning, solo active)
- **Blue:** `#2196F3` (metronome, info)

---

## UI Components

### 1. Transport Bar (Top)
**File:** `ui/lib/widgets/transport_bar.dart`

**Features:**
- Logo (left side)
- Transport controls: ⏮ ⏺ ▶ ⏹ ⏭
- Metronome toggle 🎵
- Virtual Piano toggle 🎹
- Tempo display (♩120 BPM)
- Time display (00:00.000)
- Position display (bar.beat.subdivision like "1.1.1")
- CPU usage indicator (with color coding)
- Status indicator (Recording/Playing/Stopped)
- File menu button 📁
- Mixer toggle button ⚙️
- Loading spinner (when saving/loading)

**Layout:** Single 60px height bar with all controls

### 2. Library Panel (Left)
**File:** `ui/lib/widgets/library_panel.dart`

**Features:**
- 200px width (collapsible to 40px)
- 4 categories with expansion:
  - 🎵 **Sounds** - Audio samples, loops, one-shots
  - 🎹 **Instruments** - Piano, Synth, Drums, Bass, Sampler
  - 📊 **Effects** - EQ, Compressor, Reverb, Delay, Chorus, Limiter
  - 🧩 **Plug-Ins** - VST3 plugins (placeholder)
- Collapsible categories (click to expand/collapse)
- Items are clickable (future: drag to timeline)

**Status:** Basic structure complete, no drag-and-drop yet

### 3. Timeline (Center)
**File:** `ui/lib/widgets/timeline_view.dart`

**Features:**
- Time ruler at top (shows bars/beats)
- Multi-track display with track headers on left
- Horizontal scroll for long projects
- Zoom controls at bottom
- Grid lines for bars and beats
- Playhead indicator (red line)
- Track rows with 100px height
- Default: 1 audio track + master track

**Track Header Features:**
- Track emoji/icon
- Track name
- [S] Solo button
- [M] Mute button
- Level meter (vertical bars with color coding)

### 4. Mixer Panel (Right)
**File:** `ui/lib/widgets/mixer_panel.dart`

**Features:**
- 300px width, always visible
- Track strips (100px each) with:
  - Track name and type
  - Volume fader (vertical)
  - Pan knob (horizontal slider)
  - [M] Mute button
  - [S] Solo button
  - [FX] Effects button (opens bottom panel)
  - Delete button (×)
- Master track strip (120px, special styling)
- Add Track buttons at bottom (Audio | MIDI)
- Horizontal scroll if many tracks

### 5. Bottom Panel (Tabs)
**File:** `ui/lib/widgets/bottom_panel.dart`

**Features:**
- 250px height
- 3 tabs:
  1. **Piano Roll** - Placeholder "Coming in M6"
  2. **FX Chain** - Shows effects for selected track
  3. **Virtual Piano** - 2-octave keyboard
- Auto-switches to relevant tab when needed
- Shows when FX button clicked or Virtual Piano enabled

### 6. Status Bar (Bottom)
**Part of:** `ui/lib/screens/daw_screen.dart`

**Features:**
- 24px height
- Shows audio engine status (✓ Ready or ⚠ Initializing)
- Project name display
- System status messages

---

## Completed UI Work (M5.5)

### ✅ Layout Changes
- [x] Removed separate AppBar, consolidated into transport bar
- [x] Created 3-panel layout (Library | Timeline | Mixer)
- [x] Made mixer always visible (300px on right)
- [x] Added library panel (200px on left)
- [x] Added bottom tabbed panel (250px height)
- [x] Moved logo to transport bar
- [x] Moved file menu to transport bar
- [x] Moved mixer toggle to transport bar

### ✅ New Widgets Created
- [x] `LibraryPanel` - 4 categories with expansion
- [x] `TrackHeader` - Timeline track headers with S/M/meters
- [x] `BottomPanel` - Tabbed interface for tools

### ✅ Theme Changes
- [x] Changed from dark theme to light grey theme
- [x] Updated all backgrounds to medium/light grey
- [x] Changed all text from light to dark
- [x] Updated borders to be lighter than backgrounds
- [x] Made timeline lighter than side panels (focus)
- [x] Updated 7+ widget files with new color scheme

### ✅ Transport Bar Enhancements
- [x] Added tempo display (BPM)
- [x] Added position display (bar.beat.subdivision)
- [x] Added CPU usage indicator
- [x] Consolidated logo + controls into single bar

### ✅ Resizable Panels (M5.5.1 - October 27, 2025)
- [x] Created ResizableDivider widget (vertical and horizontal)
- [x] Added draggable divider between Library and Timeline
- [x] Added draggable divider between Timeline and Mixer
- [x] Added draggable divider between Timeline and Bottom Panel
- [x] Double-click dividers to collapse/expand panels
- [x] Subtle hover effects (line highlights, cursor changes)
- [x] Panel sizes saved to ui_layout.json per project
- [x] Panel sizes restored when project reopened
- [x] Min/max constraints (Library: 40-400px, Mixer: 200-600px, Bottom: 100-500px)

### ✅ Master Track Repositioning (M5.5.1 - October 27, 2025)
- [x] Moved master track to bottom of timeline
- [x] Moved master track to bottom of mixer panel
- [x] Used Spacer widget to push master to bottom
- [x] Master stays at bottom even with no other tracks

### ✅ UI Improvements (M5.5.1 - October 27, 2025)
- [x] Moved zoom controls from bottom bar to top-right corner (+40px vertical space)
- [x] Replaced bottom Audio/MIDI buttons with + button in mixer header
- [x] Added dropdown menu for track creation (Audio Track / MIDI Track)
- [x] Improved track creation UX (more discoverable for beginners)

---

## Remaining UI Tasks

### High Priority (Next Session)
- [x] **Panel Collapsibility** ✅ DONE
  - [x] ~~Add keyboard shortcut `B` to toggle library panel~~ (double-click divider works)
  - [x] ~~Add keyboard shortcut `M` to toggle mixer panel~~ (double-click divider works)
  - [x] ~~Add keyboard shortcut `P` to toggle bottom panel~~ (double-click divider works)
  - [x] Save panel visibility state in preferences (saved in ui_layout.json)

- [ ] **Track Colors**
  - [ ] Auto-assign colors to tracks (red, orange, yellow, green, blue, purple)
  - [ ] Show track color in track header
  - [ ] Show track color in timeline clips
  - [ ] Show track color in mixer strip

- [ ] **Timeline Improvements**
  - [x] ~~Add zoom slider (visible, not just +/- buttons)~~ ✅ DONE (compact controls in top-right)
  - [ ] Add loop region markers
  - [ ] Add position ruler labels (clearer bar numbers)
  - [ ] Add snap-to-grid visual feedback

- [ ] **Library Panel**
  - [ ] Add search/filter bar at top
  - [ ] Implement drag-and-drop to timeline
  - [ ] Show waveform preview on hover (for audio)
  - [ ] Add "Recent" and "Favorites" sections

### Medium Priority
- [ ] **Transport Bar**
  - [ ] Make tempo clickable to edit (dialog or inline)
  - [ ] Add loop on/off toggle button
  - [ ] Add undo/redo buttons
  - [ ] Show project name in title area

- [ ] **Mixer Panel**
  - [ ] Add "narrow view" mode (faders only)
  - [ ] Add track input selector (for recording source)
  - [ ] Add track routing display
  - [ ] Add group/folder support

- [ ] **Bottom Panel**
  - [x] ~~Make height adjustable (drag divider)~~ ✅ DONE
  - [ ] Add 4th tab for Automation
  - [ ] Add maximize button (full-screen mode)
  - [ ] Remember tab selection per track

### Low Priority (Polish)
- [ ] **Tooltips**
  - [ ] Add keyboard shortcut hints to all buttons
  - [ ] Add hover tooltips throughout
  - [ ] Add context-sensitive help

- [ ] **Context Menus**
  - [ ] Right-click track header → Duplicate, Delete, Rename, Color
  - [ ] Right-click timeline → Add Marker, Split Clip
  - [ ] Right-click mixer strip → Reset, Copy Settings

- [ ] **Onboarding**
  - [ ] First launch tour overlay
  - [ ] Empty state guidance
  - [ ] Quick start video link

- [ ] **Accessibility**
  - [ ] Larger text option
  - [ ] High contrast mode
  - [ ] Keyboard navigation for all controls

---

## Design Rationale

### Why Light Grey Theme?
- **Better visibility:** Light backgrounds reduce eye strain in well-lit environments
- **Modern aesthetic:** Aligns with Ableton, Logic Pro X, and other modern DAWs
- **Text contrast:** Dark text on light background is easier to read
- **Professional look:** Clean, minimal, focused

### Why Center Timeline is Lighter?
- **Draw attention:** Lighter center focuses user on main workspace
- **Visual hierarchy:** Side panels recede, timeline pops
- **Ableton pattern:** Industry-standard approach for DAWs

### Why Always-Visible Mixer?
- **Quick access:** No need to toggle to adjust levels/pan
- **Context awareness:** Always see what's in your mix
- **Pro workflow:** Matches Logic Pro, Pro Tools convention
- **Note:** Still toggleable for users who want max timeline space

### Panel Proportions
- **Library 12%** (~200px) - Enough for category names and items
- **Timeline 63%** (flexible) - Maximum workspace for editing
- **Mixer 25%** (~300px) - 3-4 track strips visible
- **Flexible:** Users can collapse library or mixer for more space

### Resizable Dividers
- **Dividers:** 1px grey lines that expand to 3px on hover
- **Interaction:** Drag to resize, double-click to collapse/expand
- **Visual feedback:** Green highlight when dragging, hover changes cursor
- **Persistence:** Sizes saved in `ui_layout.json` per project
- **Smart constraints:** Min/max limits prevent broken layouts
  - Library: 40px (collapsed) - 400px (max)
  - Mixer: 200px (min) - 600px (max)
  - Bottom Panel: 100px (min) - 500px (max)
- **UX inspiration:** Ableton Live, Logic Pro X, VS Code

---

## Known Issues / Quirks

### Visual
- ⚠️ Track headers don't sync with actual audio engine tracks yet
- ⚠️ Level meters show static value (not real-time)
- ⚠️ Master track height is different from audio tracks
- ⚠️ Grid lines in timeline don't align with ruler perfectly

### Interaction
- ⚠️ Library items are not draggable yet
- ⚠️ Track headers Solo/Mute don't have callbacks yet
- ⚠️ No keyboard shortcuts for panel toggling yet
- ⚠️ Bottom panel doesn't remember which tab was selected

### Consistency
- ⚠️ Some buttons use different shades of grey (audit needed)
- ⚠️ Icon sizes vary slightly across panels
- ⚠️ Spacing not perfectly uniform everywhere

---

## References

### Color Values Quick Reference
```dart
// Side panels
0xFF707070  // Background (medium grey)
0xFF656565  // Headers (darker)
0xFF909090  // Borders (light grey)

// Center timeline
0xFF909090  // Background (light grey)
0xFF9A9A9A  // Tracks (even lighter)
0xFFAAAAAA  // Borders (very light)

// Text
0xFF202020  // Primary (very dark)
0xFF353535  // Secondary (dark)
0xFF505050  // Tertiary (medium-dark)
0xFF404040  // Icons

// Accents
0xFF4CAF50  // Green
0xFFFF5722  // Red
0xFFFFC107  // Yellow
0xFF2196F3  // Blue
```

### Mockup Reference
ASCII mockup file: `docs/IMPLEMENTATION_PLAN.md` (in UI/UX section)

User's original mockup image:
`/var/folders/rh/7f3gz0ls3fxfxv0jdmdsxn0m0000gn/T/TemporaryItems/NSIRD_screencaptureui_nNmyIP/Captura de pantalla 2025-10-26 a las 19.12.03.png`

---

## Next Steps

When resuming UI work:

1. **Start with keyboard shortcuts** for panel toggling (quick win)
2. **Add track colors** (visual improvement, easy to implement)
3. **Implement drag-and-drop** from library to timeline (major feature)
4. **Add context menus** for right-click actions (pro user workflow)
5. **Polish spacing and alignment** (final visual pass)

**Goal:** By end of next UI session, have fully interactive panels with colors and keyboard shortcuts.
