# Boojy Audio Beta Roadmap

## Overview

**Goal:** Feature parity with GarageBand — beginners can do everything GarageBand does.

**Platforms:** macOS + Windows

**Timeline:** 2 weeks (50 hours) — 4 Feb → 18 Feb 2026

**Target:** Beta release ready for early users and feedback.

---

## Beta Scope

### What's In Beta

| # | Feature | Size | Hours | Status |
|---|---------|------|-------|--------|
| 1 | Input monitoring (auto mode) | Small | 1-2 | ✅ Done |
| 2 | Sampler fixes (stereo + editor + ADSR + root note) | Large | 12-15 | 🟡 Implemented, needs testing |
| 3 | MIDI CC recording (sustain + pitch bend) | Medium | 6-8 | 🔴 Not started |
| 4 | Punch in/out recording | Medium | 4-6 | ✅ Done |
| 5 | MIDI file import/export | Medium | 6-8 | ✅ Done |
| 6 | Scale/key snapping in piano roll | Small | 3-4 | ✅ Done |
| 7 | Windows build testing | Medium | 4-6 | 🟡 Build exists, needs testing |
| 8 | Recording workflow (count-in, restart, etc.) | Medium | — | ✅ Done |
| 9 | Start screen (new, open recent) | Medium | 4-6 | 🔴 Not started |
| 10 | Tooltips on all buttons | Small | 3-4 | 🔴 Not started |
| | **Total** | | **44-59** | |

### What's Not In Beta (Deferred to v1.0)

| Feature | Why Deferred |
|---------|--------------|
| Boojy Drums (pad grid + step sequencer) | Sampler covers basics |
| Synth polish | Basic but functional |
| Send/return effects | Direct effects work for beta |
| Fades on audio clips | Basics first |
| Crossfades | Related to fades |
| Linux build | macOS + Windows first |
| Stock sounds/instruments | Get DAW to 8-9/10 first, then add sounds |
| Templates | Simple start screen is enough |
| Tempo automation | Niche use case |
| Track grouping/folders | Organisational, not blocking |
| Plugin presets | Plugins manage their own |
| Built-in tutorial | Videos/docs can substitute |

---

## Feature Details

### 1. Input Monitoring (Auto Mode)

**Behaviour:** Armed = Monitoring. No separate toggle needed.

| State | Hear Input? |
|-------|-------------|
| Not armed | No |
| Armed | Yes (always) |

**Why this approach:**
- Simple mental model: "Armed = I hear myself"
- GarageBand does this — proven for beginners
- No Auto/In/Off modes to explain
- One rule, not context-dependent

**Implementation:**
- When track is armed, route input to output (with track effects)
- When track is unarmed, stop routing input
- Add tiny fade out (10-20ms) when unarming to avoid audio click
- Works for both audio and MIDI tracks

**User workflow:**
```
Practice with effects:
1. Arm track
2. Play instrument — hear yourself with reverb, etc.
3. Unarm when done practising

Listen back to recording:
1. Unarm track
2. Press Play
3. Hear recorded audio only (no live input)

Recording:
1. Arm track
2. Press Record
3. Hear yourself while recording
```

**Edge case — doubled audio:**
If user plays back recorded audio while armed, they'll hear both the recording AND their live input. Solution: unarm the track when listening back. Users learn this quickly.

**No UI changes needed:**
The R (arm) button already exists. Arming now implies monitoring. No new buttons.

**Current state:** Engine supports monitoring during armed+recording. Need to ensure monitoring also works when armed+stopped.

---

### 2. Sampler Fixes (BLOCKER)

**Current issues:**
- Stereo output bug (plays mono only)
- Basic editor (needs real waveform display)
- Missing features that Audio Editor has

**Requirements:**
- Fix stereo output
- Waveform display in sampler editor
- Loop points (start/end)
- One-shot mode (vs looping)
- Attack / Release envelope
- Root note setting
- Match feature set of Audio Editor

**Priority:** Highest — without this, users can't make beats.

---

### 3. MIDI CC Recording

**Requirements:**
- Record sustain pedal (CC 64)
- Record pitch bend
- Store CC data in MIDI clips
- Play back CC data during playback
- Display CC data in piano roll (optional for beta, nice to have)

**Why important:** Anyone with a MIDI keyboard expects sustain pedal to work.

---

### 4. Punch In/Out Recording

**Requirements:**
- Set punch in point (where recording starts)
- Set punch out point (where recording stops)
- Playback continues before/after punch region
- Only the punch region is recorded
- Visual indication of punch region on timeline

**Use case:** Re-record just bars 5-8 without affecting the rest.

---

### 5. MIDI File Import/Export

**Import requirements:**
- Drag .mid file onto timeline or track
- Parse MIDI file
- Create MIDI clip(s) with notes
- Handle multiple tracks in MIDI file

**Export requirements:**
- Export MIDI clip as .mid file
- Export all MIDI tracks as single .mid file
- Right-click clip → Export as MIDI

---

### 6. Scale/Key Snapping

**Requirements:**
- Select key (C, C#, D, etc.)
- Select scale (Major, Minor, Pentatonic, etc.)
- Notes snap to scale when drawing/moving in piano roll
- Visual indication of scale notes on piano roll (highlight valid notes)
- Toggle on/off

**Current state:** Models exist, needs wiring to UI.

---

### 7. Windows Build Testing

**Requirements:**
- Test all existing features on Windows
- Fix Windows-specific bugs
- Test audio engine (WASAPI/ASIO)
- Test MIDI input
- Test file save/load
- Test plugin loading (VST3)

**Current state:** Build exists, needs systematic testing.

---

### 8. Recording Workflow

**Status:** ✅ Complete

**Implemented:**
- Three-button transport (Play/Pause, Stop, Record)
- Count-in with ring timer + beat numbers
- Count-in plays song context (previous bars)
- Pause = stop, stay at current position
- Stop = stop, return to record start (double-press = bar 1)
- Record during recording = save, restart with count-in
- No count-in when pressing Record while already playing

---

### 9. Start Screen

**Requirements:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│                        🅱️ Boojy Audio                           │
│                                                                  │
│    ┌─────────────────┐         ┌─────────────────────────────┐  │
│    │                 │         │  Recent Projects             │  │
│    │   + New Project │         │                              │  │
│    │                 │         │  📁 My Song.boojy            │  │
│    └─────────────────┘         │     Yesterday                │  │
│                                │                              │  │
│    ┌─────────────────┐         │  📁 Beat Idea.boojy         │  │
│    │                 │         │     2 days ago               │  │
│    │   📂 Open...    │         │                              │  │
│    │                 │         │  📁 Piano Practice.boojy    │  │
│    └─────────────────┘         │     Last week                │  │
│                                │                              │  │
│                                └─────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- New Project button (creates blank project)
- Open button (file picker)
- Recent Projects list (name + last modified)
- Click recent project to open
- Shows on app launch
- Shows when closing last project

**Not in beta (v1):**
- Templates
- Demo projects

---

### 10. Tooltips

**Requirements:**
- Tooltip on hover for all transport buttons
- Tooltip on hover for all track buttons (M, S, R, etc.)
- Tooltip on hover for all toolbar buttons
- Tooltip on hover for piano roll tools
- Consistent style (dark background, white text)
- Short delay before showing (~500ms)
- Include keyboard shortcut in tooltip where applicable

**Example tooltips:**
| Button | Tooltip |
|--------|---------|
| Play | "Play (Space)" |
| Stop | "Stop (Enter)" |
| Record | "Record (R)" |
| M | "Mute" |
| S | "Solo" |
| R | "Arm for Recording" |

---

## Schedule

### Week 1: 4–7 Feb (25 hours)

| Day | Task | Hours |
|-----|------|-------|
| Mon | Input monitoring (auto mode) | 2 |
| Mon-Tue | Sampler fixes (stereo, waveform) | 6 |
| Wed | Sampler fixes (ADSR, root note, one-shot) | 6 |
| Thu | MIDI CC recording | 6 |
| Fri | MIDI file import/export | 5 |
| | **Week 1 Total** | **25** |

### Week 2: 10–14 Feb (25 hours)

| Day | Task | Hours |
|-----|------|-------|
| Mon | MIDI file import/export (finish) | 3 |
| Mon-Tue | Punch in/out recording | 5 |
| Wed | Scale/key snapping | 4 |
| Thu | Start screen | 5 |
| Fri | Tooltips + Windows testing | 8 |
| | **Week 2 Total** | **25** |

### Buffer: 17–18 Feb

Final testing, bug fixes, and polish before beta release.

---

## Definition of Done

Beta is ready when:

- [ ] All 10 features implemented
- [ ] Windows build tested and working
- [ ] macOS build tested and working
- [ ] No crash bugs
- [ ] Core workflow works: create project → record MIDI → record audio → add effects → export
- [ ] Sampler works properly (stereo, one-shot, ADSR)
- [ ] Can complete a simple song start to finish

---

## Post-Beta (v1.0 Roadmap)

After beta feedback, prioritise for v1.0:

| Feature | Priority |
|---------|----------|
| Stock sounds/instruments | High — once DAW is solid |
| Boojy Drums | High — beat making |
| Linux build | Medium |
| Send/return effects | Medium |
| Fades/crossfades | Medium |
| Templates | Low |
| Tempo automation | Low |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sampler takes longer than expected | Blocks beta | Start with this, allocate buffer |
| Windows-specific bugs | Beta quality | Test early, not just at end |
| Scope creep | Delays beta | Stick to the 10 features, everything else is v1 |
| Burnout from 50hr sprint | Quality suffers | Take breaks, don't crunch |

---

## Success Metrics

Beta is successful if:

- [ ] 10+ users try it and give feedback
- [ ] Users can complete a song without hitting a wall
- [ ] No critical bugs reported
- [ ] Feedback informs v1.0 priorities

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-03 | 1.0 | Initial beta roadmap |