# M3 Integration Test Guide

## Overview

This test validates M3 (First Half) functionality:
- Virtual Piano Keyboard
- MIDI Input System
- Built-in Synthesizer (Polyphonic)
- Oscillator Types (Sine, Saw, Square)
- MIDI Event Processing

**Status:** M3 First Half Complete (Piano Roll UI deferred)

---

## Setup

### Prerequisites

1. **Build the Engine**
   ```bash
   cd engine
   cargo build --release
   ```

2. **Launch the App**
   ```bash
   cd ui
   flutter run -d macos
   ```

3. **Verify M0/M1/M2 Still Work**
   - If you haven't tested M1/M2, do those first to ensure audio system is working

---

## Test 1: Virtual Piano Keyboard - Basic Playback

### Step 1: Open Virtual Piano

1. Look for the **🎹 Piano icon** in the transport bar (top)
2. Click the piano icon
3. **Expected:** Virtual piano keyboard slides up from bottom
   - Should see 17 white keys + 12 black keys (C4 to E6)
   - Header shows "Virtual Piano Keyboard"
   - Waveform selector shows "Sine", "Saw", "Square"
   - Default: **Saw** should be highlighted (green)

**✅ Pass Criteria:**
- Piano keyboard appears smoothly
- All keys are visible and properly aligned
- Saw is selected by default

---

### Step 2: Play Notes with Mouse

1. **Click a white key** (e.g., middle C - the leftmost white key marked "Z")
2. **Expected:**
   - Key turns **green** while pressed
   - You **hear a saw wave tone** (buzzy, bright sound)
   - Note name shows at top of key ("C4")

3. **Click a black key** (e.g., C# marked "S")
4. **Expected:**
   - Key turns **purple** while pressed
   - You hear a higher pitched saw wave
   - Note name shows ("C#4" / "Db4")

5. **Click multiple keys simultaneously** (2-3 notes at once)
6. **Expected:**
   - All clicked keys light up
   - You hear a **chord** (polyphonic playback)
   - No audio glitches or dropouts

**✅ Pass Criteria:**
- Mouse clicks trigger notes immediately (<10ms latency)
- Visual feedback is instant
- Polyphony works (can play multiple notes)
- Sound is clear, no crackling

---

### Step 3: Play Notes with Keyboard

1. **Press computer keyboard key** `Z` (C4 - lowest white key)
2. **Expected:**
   - Corresponding piano key lights up green
   - You hear the note

3. **Press multiple keys** at once: `Z`, `C`, `B` (C4, E4, G4 - a C major chord)
4. **Expected:**
   - All three keys light up
   - You hear a chord

4. **Hold a key down** for 2-3 seconds, then release
5. **Expected:**
   - Note sustains while held
   - Note releases smoothly when key is released (no click/pop)

6. **Rapidly press keys** (trill): `Z X Z X Z X` quickly
7. **Expected:**
   - Notes trigger instantly
   - No stuck notes
   - No missed notes

**Computer Keyboard Mapping Reference:**
```
White keys (bottom row):  Z X C V B N M , . /
Black keys (middle row):  S D   G H J   L ;
White keys (top row):     W E R T Y U I O P [
Black keys (top row):     3 4   6 7 8   0 -
```

**✅ Pass Criteria:**
- All mapped keys respond correctly
- Polyphony works (up to 16 simultaneous notes)
- No latency or missed notes
- Smooth note on/off transitions

---

## Test 2: Synthesizer Oscillator Types

### Step 1: Test Sine Wave

1. Click the **"Sine"** button in the waveform selector
2. **Expected:** Sine button turns green, Saw/Square are gray
3. Play a note (click "C4" or press `Z`)
4. **Expected:**
   - Pure, smooth tone (no harmonics)
   - Sounds like a tuning fork or flute

**Sound Characteristics:**
- Very smooth, mellow
- No buzzing or brightness
- Single frequency tone

---

### Step 2: Test Saw Wave

1. Click the **"Saw"** button
2. **Expected:** Saw button turns green
3. Play a note
4. **Expected:**
   - Bright, buzzy tone (rich in harmonics)
   - Sounds like a classic analog synth

**Sound Characteristics:**
- Bright, edgy
- Contains all harmonics
- Sounds "fuller" than sine

---

### Step 3: Test Square Wave

1. Click the **"Square"** button
2. **Expected:** Square button turns green
3. Play a note
4. **Expected:**
   - Hollow, woody tone (odd harmonics only)
   - Sounds like a clarinet or NES game console

**Sound Characteristics:**
- Hollow, nasal quality
- Less bright than saw
- Distinctive "chip tune" sound

---

### Step 4: Switch Oscillators During Playback

1. Select **Saw** wave
2. **Hold down** a piano key (or computer key)
3. While the note is still playing, **click Square**
4. **Expected:**
   - Timbre changes instantly
   - No clicks, pops, or glitches
   - Note continues smoothly

**✅ Pass Criteria:**
- All three waveforms sound distinctly different
- Waveform switching is instant and glitch-free
- Sound quality is consistent across all waveforms

---

## Test 3: Polyphony and Voice Management

### Step 1: Test 4-Voice Polyphony

1. Play a **4-note chord**: Press `Z`, `C`, `B`, `M` simultaneously
2. **Expected:**
   - All 4 notes play simultaneously
   - Chord sounds balanced (no voice louder than others)
   - No distortion or clipping

---

### Step 2: Test Maximum Polyphony (16 voices)

1. Using **both hands**, press as many keys as you can at once
   - Try to press 10+ keys simultaneously
2. **Expected:**
   - All notes play (up to 16 simultaneous voices)
   - No crashes or audio glitches
   - Sound remains clear

**Note:** The synthesizer has a 16-voice limit. If you press more than 16 keys, the oldest notes will be "stolen" to make room for new ones.

---

### Step 3: Test Voice Stealing

1. **Slowly** press and hold keys one by one: `Z`, `X`, `C`, `V`, `B`, etc.
2. Keep holding all keys until you've pressed 17+ keys
3. **Expected:**
   - First 16 notes play normally
   - When you press the 17th note, the **oldest** note (first pressed) stops
   - No audio artifacts or crashes

**✅ Pass Criteria:**
- Can play up to 16 simultaneous notes
- Voice stealing works smoothly
- No audio dropouts or glitches

---

## Test 4: ADSR Envelope Behavior

### Step 1: Test Attack Phase

1. Select **Sine** wave (easiest to hear envelope)
2. **Quickly tap** a key (press and release in <0.1 seconds)
3. **Expected:**
   - Note starts at zero volume
   - Fades in quickly (~10ms attack)
   - Note has a quick "blip" sound

---

### Step 2: Test Sustain Phase

1. **Press and hold** a key for 3+ seconds
2. **Expected:**
   - Note reaches full volume quickly
   - Volume stays consistent while held (sustain level ~70%)
   - No volume drift or wobble

---

### Step 3: Test Release Phase

1. **Hold a key** for 2 seconds
2. **Release the key**
3. **Expected:**
   - Note doesn't stop instantly
   - Fades out smoothly over ~200ms (release time)
   - No click or pop when released

**✅ Pass Criteria:**
- Notes fade in smoothly (attack)
- Notes sustain at consistent volume
- Notes fade out smoothly (release)
- No clicks or pops

---

## Test 5: MIDI Timing and Latency

### Step 1: Test Note-On Latency

1. **Rapidly click** piano keys with mouse
2. **Expected:**
   - Notes trigger within **5-10ms** of click
   - Feels instant, no noticeable delay

---

### Step 2: Test Keyboard Latency

1. **Rapidly press** computer keyboard keys: `Z X C V B N M`
2. **Expected:**
   - Notes trigger immediately
   - No stuttering or lag

---

### Step 3: Test Stuck Notes (Bug Check)

1. **Press and hold** `Z` key for 2 seconds
2. **Release** the key
3. **Wait 1 second**
4. **Expected:**
   - Note stops cleanly after release
   - No "stuck" notes that continue playing forever

5. **Repeat** with multiple keys: press `Z X C`, release all
6. **Expected:**
   - All notes stop
   - Silence after release

**✅ Pass Criteria:**
- Latency is imperceptible (<10ms)
- No stuck notes
- Note-off events work reliably

---

## Test 6: MIDI Input from Hardware (Optional)

**Prerequisites:** You must have a MIDI keyboard/controller connected

### Step 1: Check MIDI Device Detection

1. **Connect your MIDI keyboard** to your Mac via USB
2. **Launch or restart the app**
3. **Check console output** for:
   ```
   🎹 [MIDI] Found X MIDI input devices
     [0] Your MIDI Keyboard Name
   ```

**Expected:**
- App detects your MIDI device
- Device name appears in console

---

### Step 2: Play MIDI Keyboard

1. With virtual piano visible, **play a note on your MIDI keyboard**
2. **Expected:**
   - You hear the synthesizer respond
   - Console shows:
     ```
     🎹 [SYNTH] Note On: 60 (vel: 100)
     ```
   - Virtual piano keys might not light up (hardware MIDI input is separate from virtual piano UI)

3. **Play multiple notes** simultaneously
4. **Expected:**
   - Polyphony works just like virtual piano

---

### Step 3: Test MIDI Velocity

1. **Play a note softly** on your MIDI keyboard
2. **Play the same note hard**
3. **Expected:**
   - Soft notes are quieter
   - Hard notes are louder
   - Velocity sensitivity works

**✅ Pass Criteria (if MIDI hardware available):**
- MIDI device is detected
- Notes trigger synthesizer
- Velocity affects volume

**⏭️ Skip this test if no MIDI hardware available**

---

## Test 7: CPU Usage and Performance

### Step 1: Idle CPU

1. Open **Activity Monitor** (macOS)
2. Find the Boojy Audio / Flutter process
3. **Expected CPU usage:**
   - **<5%** when idle (piano visible but not playing)

---

### Step 2: Playing 1 Note

1. **Hold down one key** continuously
2. Check CPU usage
3. **Expected:**
   - **5-10%** CPU usage

---

### Step 3: Playing 8 Notes (Chord)

1. **Hold down 8 keys** at once (use both hands)
2. Check CPU usage
3. **Expected:**
   - **10-20%** CPU usage
   - No audio dropouts or glitches

---

### Step 4: Playing 16 Notes (Max Polyphony)

1. **Press and hold 16 keys** (all fingers + toes, or use multiple quick presses)
2. Check CPU usage
3. **Expected:**
   - **<30%** CPU usage
   - Audio remains clear

**✅ Pass Criteria:**
- CPU usage scales reasonably with voice count
- No audio glitches even at max polyphony
- App remains responsive

---

## Test 8: Close and Reopen Piano

### Step 1: Close Piano

1. Click the **down arrow** button (top-right of piano header)
2. **Expected:**
   - Piano slides down smoothly
   - Piano disappears
   - Piano icon in transport bar returns

---

### Step 2: Reopen Piano

1. Click the **🎹 piano icon** in transport bar again
2. **Expected:**
   - Piano slides back up
   - Previously selected waveform is still selected
   - Piano is fully functional

**✅ Pass Criteria:**
- Piano can be opened and closed smoothly
- State is preserved (waveform selection)

---

## Test 9: Integration with M1/M2 Features

### Test 1: Play Audio File + Virtual Piano Simultaneously

1. **Load an audio file** (use M1 test: drag `~/Downloads/test.wav` to timeline)
2. **Press Play** (▶️)
3. While audio is playing, **open virtual piano**
4. **Play notes on piano** while audio plays
5. **Expected:**
   - Audio file plays in background
   - Synthesizer notes play on top of audio
   - Both sound sources mix cleanly
   - No audio glitches

**✅ Pass Criteria:**
- Audio and MIDI can play simultaneously
- Mixed audio is clear, no distortion

---

### Test 2: Metronome + Virtual Piano

1. **Enable metronome** (click 🎵 icon in transport bar)
2. **Set tempo** to 120 BPM (should be default)
3. **Press Play**
4. **Open virtual piano** and play along with metronome clicks
5. **Expected:**
   - Metronome clicks play
   - Piano notes play
   - Both sound sources audible

**✅ Pass Criteria:**
- Metronome and piano work together
- No conflicts or audio dropouts

---

## Console Output Reference

### Expected Console Messages

During normal operation, you should see:

**App Launch:**
```
🔍 [AudioEngine] Attempting to load library...
✅ [AudioEngine] Library loaded successfully
🎹 [MIDI] Found 0 MIDI input devices
✅ Audio graph initialized: M1: Audio graph initialized
🎵 Recording settings initialized:
   - Count-in: 2 bars
   - Tempo: 120.0 BPM
   - Metronome: ON
✅ Audio graph initialized: M1: Audio graph initialized
```

**Opening Virtual Piano:**
```
🎹 [AudioEngine] Starting MIDI input...
✅ [MIDI] Capture started
```

**Playing Notes:**
```
🎹 [SYNTH] Note On: 60 (vel: 100)
🎹 [SYNTH] Note Off: 60
🎹 [SYNTH] Note On: 62 (vel: 100)
🎹 [SYNTH] Note Off: 62
```

**Switching Waveforms:**
```
Oscillator type set to: Saw
Oscillator type set to: Square
Oscillator type set to: Sine
```

---

## Troubleshooting

### "No sound when playing piano"

**Check:**
1. System volume is not muted
2. MIDI input is started (should happen automatically when piano opens)
3. Console shows "🎹 [SYNTH] Note On" messages
4. Try clicking the piano icon to close and reopen

**Fix:**
```bash
# Rebuild engine if library is stale
cd engine
cargo build --release
```

---

### "Keys don't light up when clicked"

**Check:**
1. You're clicking on the actual key area (not the label)
2. Virtual piano has focus (click anywhere on piano first)

**Note:** This is a minor visual bug, sound should still work.

---

### "Stuck notes - sound continues after releasing key"

**Check:**
1. Console shows matching Note On and Note Off messages
2. Try clicking the note again to re-trigger

**If persistent:**
```bash
# This is a bug - report it and restart the app
# Close piano, stop playback, reopen piano
```

---

### "Crackling or glitching audio"

**Check:**
1. CPU usage is reasonable (<30%)
2. No other audio-intensive apps running
3. Buffer size is adequate (default should work)

**Fix:**
```bash
# If crackling persists, increase audio buffer size in future release
# For now, reduce polyphony (play fewer simultaneous notes)
```

---

### "Piano doesn't appear when clicking icon"

**Check:**
1. Console for error messages
2. MIDI input manager initialized (should happen on app launch)

**Fix:**
```bash
# Restart the app
cd ui
flutter run -d macos
```

---

### "Keyboard keys don't trigger notes"

**Check:**
1. Virtual piano has **keyboard focus** (click on piano area first)
2. You're not in a text field
3. Caps Lock is off (shouldn't matter but try it)

**Fix:**
- Click anywhere on the piano to give it focus

---

## Success Criteria

### ✅ Core Functionality
- [ ] Virtual piano keyboard appears and closes smoothly
- [ ] Mouse clicks trigger notes instantly
- [ ] Computer keyboard triggers notes instantly
- [ ] All three waveforms (Sine/Saw/Square) work and sound different
- [ ] Polyphony works (can play multiple notes simultaneously)
- [ ] ADSR envelope works (smooth attack and release)
- [ ] No stuck notes or audio glitches

### ✅ Performance
- [ ] Latency is imperceptible (<10ms)
- [ ] CPU usage is reasonable (<30% at max polyphony)
- [ ] Audio quality is clear (no crackling or distortion)

### ✅ Integration
- [ ] Works alongside audio playback (M1)
- [ ] Works with metronome (M2)
- [ ] Can be closed and reopened without issues

### ✅ Optional (MIDI Hardware)
- [ ] MIDI device is detected (if connected)
- [ ] Hardware MIDI keyboard triggers synthesizer
- [ ] Velocity sensitivity works

---

## Known Issues / Limitations

### Expected Behavior (Not Bugs)

1. **Piano roll UI is missing** - Deferred to M3 second half
   - Can't see recorded MIDI notes on timeline yet
   - Workaround: Use virtual piano for immediate playback

2. **Can't record MIDI yet** - UI integration pending
   - Recording backend is ready (Rust)
   - Just needs Flutter UI wiring
   - Workaround: Virtual piano works for live performance

3. **No drum samples** - Drum sampler deferred
   - Only synthesizer sounds available
   - Workaround: Use saw/square wave for percussive sounds

4. **No MIDI file import/export** - Future feature
   - Can't load .mid files yet
   - Workaround: Use virtual piano or hardware MIDI input

5. **Quantization is hard-coded to 120 BPM** - Minor bug
   - If you change project tempo, quantization doesn't adapt yet
   - Easy fix: needs tempo plumbing from UI to backend

---

## Next Steps After Test Passes

Once M3 integration test passes:

### Immediate Next Steps (If Continuing M3)
1. Wire MIDI recording to UI (add "Record MIDI" button)
2. Display MIDI clips on timeline (basic rectangles)
3. Test MIDI recording → playback workflow

### Or Move to M4 (Recommended)
1. Implement multi-track system
2. Add volume/pan controls per track
3. Build mixer panel UI
4. Add basic effects (EQ, reverb, compressor)

Piano roll and step sequencer can be added in v1.1 or after M7.

---

## Test Completion Checklist

**Test completed:** [✅] YES
**Date:** January 26, 2025
**Tester:** User

**Results:**
- Virtual Piano: [✅] Pass  [  ] Fail
- Oscillator Types: [✅] Pass  [  ] Fail
- Polyphony: [✅] Pass  [  ] Fail
- ADSR Envelope: [✅] Pass  [  ] Fail
- Latency: [✅] Pass  [  ] Fail
- CPU Performance: [✅] Pass  [  ] Fail
- Integration (M1/M2): [✅] Pass  [  ] Fail
- MIDI Hardware (optional): [  ] Pass  [  ] Fail  [✅] N/A

**Issues found:**
```
1. Initial keyboard focus issue - FIXED (click piano to get focus)
2. Visual feedback now works with green border when focused
3. All functionality working as expected
```

**Overall Status:** [✅] ✅ PASS  [  ] ❌ FAIL

---

**M3 (First Half) Status:** ✅ **TEST PASSED - All features working!**
