# VST3 Plugin UI System - Implementation Plan

Build a beginner-friendly plugin UI system with embedded-first approach and optional floating windows.

---

## Current Status

**Phase 1: C++ VST3 Core - COMPLETE**
- VST3 scanning re-enabled and working
- Detects Serum, Serum 2, and Serum 2 FX plugins
- Plugin type detection (instruments vs effects) working

**Phase 2: Plugin Editor UI - COMPLETE**
- Embedded editor in bottom panel (docked mode)
- Floating window support with position persistence
- Native NSView hosting via AppKitView on macOS

**Phase 3: VST3 State Persistence - COMPLETE**
- Plugin state save/load with projects
- Binary state blob (processor + controller) serialized to base64
- Automatic restoration on project load

---

## Design Summary

- **Embedded-first** — Plugins open in bottom panel by default
- **Floating-optional** — Users can pop out to separate window
- **Preset browser** — Header with ◀ ▶ arrows and dropdown
- **FX Chain view** — Visual chain with [Edit] buttons per effect
- **Remember preferences** — Per-plugin embedded vs floating, window positions

---

## Implementation Phases

### Phase 1: C++ VST3 Core (Enable Backend) ✅ COMPLETE

**Goal:** Re-enable VST3 scanning, loading, and audio processing.

**File:** `engine/vst3_host/vst3_host.cpp`

1. ✅ Uncomment `vst3_scan_directory()`
2. ✅ Uncomment `vst3_load_plugin()`
3. ✅ Implement `vst3_process_audio()` — Set up ProcessData, call processor->process()
4. ✅ Implement `vst3_process_midi_event()` — Create Event, add to IEventList

---

### Phase 2: Bottom Panel Plugin View (Embedded)

**Goal:** Display plugin UI in bottom panel "Instrument" tab.

**New Widget:** `ui/lib/widgets/plugin_panel/plugin_embed_view.dart`

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  [Piano Roll]  [FX Chain]  [● Instrument]                                        ✕  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│   Serum                         ◀  Preset: Init  ▶       ▼       [Open in Window]   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                            [Plugin's Native UI via PlatformView]                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

**Components:**

- `PluginHeader` — Name, preset nav (◀ ▶), dropdown, [Open in Window] button
- `PluginEmbedView` — Flutter PlatformView hosting native NSView
- `PresetBrowser` — Dropdown with folder tree, search

**Files to Create/Modify:**

| File | Purpose |
|------|---------|
| `ui/lib/widgets/plugin_panel/plugin_header.dart` | Header with preset controls |
| `ui/lib/widgets/plugin_panel/plugin_embed_view.dart` | PlatformView wrapper |
| `ui/lib/widgets/plugin_panel/preset_browser.dart` | Dropdown preset selector |
| `ui/lib/screens/daw_screen.dart` | Integrate into bottom panel tabs |

---

### Phase 3: Floating Window Support

**Goal:** "Open in Window" pops plugin to native floating window.

**Update:** `ui/macos/Runner/VST3WindowManager.swift`

- Reuse existing floating window code
- Wire Swift → Rust FFI → C++ `vst3_attach_editor()`
- Pass NSView pointer to attach actual plugin view

**Embedded Area When Floating:**

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                      Serum is open in a separate window                             │
│                              [↙ Bring Back]                                         │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

**Files to Modify:**

| File | Changes |
|------|---------|
| `ui/macos/Runner/VST3WindowManager.swift` | Attach real plugin NSView |
| `ui/macos/Runner/VST3PlatformChannel.swift` | Handle embed/float toggle |
| `ui/lib/services/vst3_editor_service.dart` | Add embedInPanel(), openInWindow() |

---

### Phase 4: FX Chain View

**Goal:** Visual effect chain with per-effect [Edit] button.

```
┌─────────┐    ┌─────────┐    ┌─────────┐
│ ◉ EQ    │ ─▶ │ ◉ Comp  │ ─▶ │ ○ Sat   │   (○ = bypassed)
│ [Edit]  │    │ [Edit]  │    │ [Edit]  │
└─────────┘    └─────────┘    └─────────┘
```

**New Widget:** `ui/lib/widgets/fx_chain/fx_chain_view.dart`

- Show effect chain for selected track
- [Edit] opens effect in embed view below
- Drag to reorder
- [+ Add Effect] opens browser

---

### Phase 5: Preferences & Polish

**Goal:** Remember user preferences per-plugin.

**Preferences File:** `~/.boojy/preferences/plugin-ui.json`

```json
{
  "preferences": {
    "Serum": "embedded",
    "Kontakt": "floating"
  },
  "windowPositions": {
    "Kontakt": { "x": 100, "y": 200, "width": 1000, "height": 600 }
  }
}
```

**Additional Polish:**

- Auto-scroll for large plugins
- Floating indicator icon in track mixer
- First-time tooltip on pop-out
- Bottom panel collapse to tabs (not full close)

---

## Files Overview

| Category | Files |
|----------|-------|
| **C++ Backend** | `engine/vst3_host/vst3_host.cpp` |
| **Rust FFI** | `engine/src/vst3_host.rs`, `engine/src/api/vst3.rs` |
| **Swift Native** | `ui/macos/Runner/VST3WindowManager.swift`, `VST3PlatformView.swift`, `VST3PlatformChannel.swift` |
| **Flutter UI** | `ui/lib/widgets/plugin_panel/*.dart`, `ui/lib/widgets/fx_chain/*.dart` |
| **Services** | `ui/lib/services/vst3_editor_service.dart`, `ui/lib/services/vst3_plugin_manager.dart` |
| **State** | `ui/lib/services/plugin_preferences.dart` (new) |

---

## Testing Plan

1. **Scan:** Open VST3 browser, verify plugins listed ✅
2. **Load:** Add plugin to track, verify audio processing
3. **Embed:** Open plugin, verify UI in bottom panel
4. **Presets:** Click ◀ ▶, verify preset changes
5. **Float:** Click "Open in Window", verify native window
6. **Bring Back:** Click "↙ Bring Back", verify returns to embed
7. **FX Chain:** View chain, reorder effects, edit individual effect
8. **Preferences:** Close app, reopen, verify remembered positions

---

## Execution Order

1. **Phase 1** — C++ backend ✅ COMPLETE
2. **Phase 2** — Embedded view ✅ COMPLETE
3. **Phase 3** — Floating windows ✅ COMPLETE
4. **Phase 3.5** — State persistence ✅ COMPLETE
5. **Phase 4** — FX Chain view (effect management)
6. **Phase 5** — Preferences and polish

---

## Remaining Work

### Not Yet Implemented

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| Plugin Bypass | High | Low | Enable/disable effect without removing |
| Preset Management | Medium | Medium | Factory/user presets, browsing, saving |
| Latency Compensation | Medium | Medium | Report & compensate for plugin latency |
| Performance Optimization | Medium | Medium | Batch frame processing instead of single-sample |
| Multi-Output Plugins | Medium | Medium | Currently only uses first stereo pair |
| Sidechain Support | Low | High | For compressors, etc. |
| Parameter Automation | Medium | High | Record/playback parameter changes |
| Windows/Linux Support | High | Very High | Currently macOS only |
