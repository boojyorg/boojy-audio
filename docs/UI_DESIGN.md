# Boojy Audio - UI Design Notes

**Last Updated:** March 2026
**Current Version:** v0.1.5 (Alpha)

**Related Documentation:**

- [ROADMAP.md](ROADMAP.md) — Features, versions, and development progress
- [ARCHITECTURE.md](ARCHITECTURE.md) — System design and code organization

---

## Current UI State

### Layout Overview

Boojy Audio has a professional 3-panel DAW interface:

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

---

## Boojy Design System (Color Scheme)

The app uses the `BoojyColors` class with four theme variants. Colors are accessed via `context.colors.propertyName`.

**Files:**
- `ui/lib/theme/app_colors.dart` — Main BoojyColors class (theme palettes)
- `ui/lib/theme/theme_provider.dart` — Theme state management
- `ui/lib/theme/theme_extension.dart` — BuildContext extensions
- `ui/lib/utils/track_colors.dart` — Track-specific colors and palettes

### Themes

Four available themes: `dark` (default), `highContrastDark`, `light`, `highContrastLight`.

### Dark Theme (Default)

**Backgrounds:**
- `editor`: `#040412` — deep content area (star field)
- `darkest`: `#13151C` — text inputs
- `dark`: `#2C2C32` — chrome (sidebar, top bar)
- `standard`: `#272A38` — forms, secondary surfaces
- `elevated`: `#292B36` — floating UI
- `surface`: `#353845` — hover, cards
- `divider`: `#3A3D4A` — borders
- `hover`: `#4A4D5A` — hover states

**Text:**
- `textPrimary`: `#E8EAF0`
- `textSecondary`: `#9B9EB0`
- `textMuted`: `#646880`

**Accent:**
- `accent`: `#40B3E8` — Boojy Audio Blue (primary)
- `accentHover`: `#5CC3F0`

### Light Theme

**Backgrounds:**
- `editor`: `#F8FAFC`
- `darkest`: `#FFFFFF`
- `dark`: `#F5F5F5`
- `standard`: `#EBEBEB`
- `elevated`: `#E0E0E0`
- `surface`: `#D5D5D5`
- `divider`: `#C0C0C0`
- `hover`: `#B0B0B0`

**Text:**
- `textPrimary`: `#1A1A1A`
- `textSecondary`: `#4A4A4A`
- `textMuted`: `#707070`

**Accent:**
- `accent`: `#0284C7`
- `accentHover`: `#0369A1`

### Semantic Colors (All Themes)

- `success`: `#4CAF50` (green)
- `warning`: `#FFC107` (yellow/amber)
- `error`: `#FF5722` (red/orange)

### Component Colors (All Themes)

**Level Meters:** `meterGreen` (#4CAF50), `meterYellow` (#FFC107), `meterRed` (#FF5722)
**Button States:** `soloActive` (#3B82F6), `muteActive` (#FACC15), `recordActive` (#EF4444), `buttonInactive` (#909090)
**Timeline:** `playhead` (#FF5252), `selection` (accent @ 30% opacity), `gridLine` (divider @ 50% opacity), `waveform` (accent)
**Piano:** `pianoWhiteKey` (#F5F5F5), `pianoBlackKey` (#2A2A2A)

### Track Colors

**Auto-detection by category:**
- drums: `#EF4444` (red), bass: `#F97316` (orange), synth: `#22C55E` (green)
- guitar: `#3B82F6` (blue), vocals: `#9775FA` (purple), fx: `#EC4899` (pink)
- audio: `#9CA3AF` (grey), master: `#3B82F6` (blue)

**Manual palette (16 colors):**
- Soft: #FFA8A8, #FFC078, #FFF3BF, #96F2D7, #74C0FC, #B197FC, #FCC2D7, #CED4DA
- Vibrant: #FF6B6B, #FF922B, #FFD43B, #69DB7C, #4DABF7, #9775FA, #F06595, #868E96

---

## UI Components

### 1. Transport Bar (Top)
**File:** `ui/lib/widgets/transport_bar.dart`

- Logo (left side)
- Transport controls: ⏮ ⏺ ▶ ⏹ ⏭
- Metronome toggle, Virtual Piano toggle
- Tempo display (♩120 BPM), Time display (00:00.000)
- Position display (bar.beat.subdivision)
- CPU usage indicator (with color coding)
- File menu button, Mixer toggle button
- 60px height

### 2. Library Panel (Left)
**File:** `ui/lib/widgets/library_panel.dart`

- 200px width (collapsible to 40px)
- 4 categories: Sounds, Instruments, Effects, Plug-Ins
- Collapsible categories
- Audio preview with waveform visualization
- Drag instruments to timeline

### 3. Timeline (Center)
**File:** `ui/lib/widgets/timeline_view.dart`

- Time ruler (bars/beats)
- Multi-track display with track headers
- Horizontal scroll and zoom
- Grid lines, playhead indicator
- Loop region markers
- Context menus on clips, empty area, ruler

### 4. Mixer Panel (Right)
**File:** `ui/lib/widgets/mixer_panel.dart`

- 300px width, always visible (toggleable)
- Track strips: name, volume fader, pan, M/S/R buttons, FX button
- Master track strip at bottom
- Add Track buttons (Audio | MIDI)
- Input selector per track with live level meters

### 5. Bottom Panel (Tabs)
**File:** `ui/lib/widgets/bottom_panel.dart`

- 250px height (resizable)
- Tabs: Piano Roll, FX Chain, Virtual Piano
- Auto-switches to relevant tab

### 6. Status Bar (Bottom)

- 24px height
- Audio engine status, project name, system messages

---

## Panel Behavior

### Resizable Dividers
- 1px lines that expand to 3px on hover
- Drag to resize, double-click to collapse/expand
- Sizes saved in `ui_layout.json` per project
- Constraints: Library 40-400px, Mixer 200-600px, Bottom 100-500px

### Panel Proportions
- **Balanced (default):** Library 12% | Timeline 63% | Mixer 25%
- **Pro mode:** Library 0% | Timeline 75% | Mixer 25%
- **Mix mode:** Library 0% | Timeline 50% | Mixer 50%
- **Edit mode:** Library 12% | Timeline 88% | Mixer 0%

---

## Remaining UI Tasks

### High Priority
- [ ] Track colors (auto-assign from palette, show in header/clips/mixer)
- [ ] Library search/filter bar
- [ ] Tooltips with keyboard shortcut hints

### Medium Priority
- [ ] Tempo click-to-edit
- [ ] Undo/redo buttons in transport
- [ ] Narrow mixer view mode
- [ ] Track input routing display

### Low Priority (Polish)
- [ ] Context menus (right-click actions)
- [ ] First-launch onboarding tour
- [ ] Accessibility: larger text, keyboard navigation
