# M4 Integration Test Plan

**Milestone:** M4 - Mixing & Effects (Core)
**Test Date:** ___________
**Tester:** ___________
**Duration:** ~20-30 minutes

---

## Test Scope

This integration test validates the **M4 Core** backend functionality:
- Track system (create, volume, pan, mute, solo)
- Master limiter (active on output)
- Track management APIs
- FFI bindings
- Track info retrieval

**Note:** This test focuses on backend APIs. UI components (mixer panel, track headers, effect UIs) are deferred to M7.

---

## Prerequisites

Before starting:
- [ ] Engine compiled successfully (`cargo build --release`)
- [ ] Flutter app running (`flutter run -d macos`)
- [ ] At least 1 audio file loaded in the project
- [ ] M1/M2/M3 features working (audio playback, recording, virtual piano)

---

## Test Scenarios

### ✅ Scenario 1: Track Creation & Basic Info

**Goal:** Verify track creation API and track manager initialization

**Steps:**
1. Launch the app
2. Check console output for M4 initialization message:
   ```
   🎚️ [AudioGraph] M4 initialized: TrackManager, EffectManager, Master Limiter
   ```
3. Verify master track exists (ID 0) by default

**Expected Result:**
- [ ] M4 initialization message appears in console
- [ ] No errors during startup
- [ ] TrackManager created with master track

**Actual Result:**
```
[Record console output here]
```

---

### ✅ Scenario 2: Master Limiter Active

**Goal:** Verify master limiter is preventing clipping

**Steps:**
1. Load a loud audio file (or play virtual piano with high velocity)
2. Play the audio
3. Check console for limiter debug output (if any)
4. Listen for clean audio output (no distortion/crackling)

**Expected Result:**
- [ ] Audio plays without clipping/distortion
- [ ] Peaks stay under 0 dBFS (no red clipping indicator if meters exist)
- [ ] Master limiter is processing frames

**Actual Result:**
```
[Note: Does audio sound clean? Any distortion?]
```

**Audio Quality:** _____ / 10 (10 = perfect, no clipping)

---

### ✅ Scenario 3: Track Count API

**Goal:** Test `get_track_count()` API

**Test Method:** Call FFI function via Flutter/console

**Expected Result:**
- [ ] Returns 1 (master track exists by default)
- [ ] No errors

**FFI Call:**
```
get_track_count_ffi() → should return 1
```

**Actual Result:**
```
[Record result]
```

---

### ✅ Scenario 4: Create Audio Track

**Goal:** Test `create_track()` API

**Test Method:** Call FFI function to create an audio track

**FFI Call:**
```
create_track_ffi("audio", "Audio 1") → should return track ID (1)
```

**Expected Result:**
- [ ] Returns track ID 1 (or next available ID)
- [ ] Console shows: `🎚️ [TrackManager] Created Audio track 'Audio 1' (ID: 1)`
- [ ] No errors

**Actual Result:**
```
[Record console output]
```

---

### ✅ Scenario 5: Create Multiple Tracks

**Goal:** Test creating multiple tracks of different types

**Test Method:** Create 4 tracks sequentially

**FFI Calls:**
```
create_track_ffi("audio", "Audio 1")   → ID 1
create_track_ffi("audio", "Audio 2")   → ID 2
create_track_ffi("midi", "MIDI 1")     → ID 3
create_track_ffi("return", "Reverb")   → ID 4
```

**Expected Result:**
- [ ] All tracks created successfully
- [ ] Sequential IDs (1, 2, 3, 4)
- [ ] Console shows creation messages for each track
- [ ] `get_track_count_ffi()` returns 5 (master + 4 new tracks)

**Actual Result:**
```
Track 1: _____
Track 2: _____
Track 3: _____
Track 4: _____
Total count: _____
```

---

### ✅ Scenario 6: Get Track Info

**Goal:** Test `get_track_info()` API

**Test Method:** Query track 0 (master) and track 1 (audio)

**FFI Calls:**
```
get_track_info_ffi(0) → master track info
get_track_info_ffi(1) → audio track 1 info
```

**Expected Format:** `"track_id,name,type,volume_db,pan,mute,solo"`

**Expected Results:**
- [ ] Master track (ID 0): `"0,Master,Master,0.00,0.00,0,0"`
- [ ] Audio track (ID 1): `"1,Audio 1,Audio,0.00,0.00,0,0"`
- [ ] All fields parsed correctly

**Actual Result:**
```
Master (ID 0): _____________________________
Audio 1 (ID 1): _____________________________
```

---

### ✅ Scenario 7: Set Track Volume

**Goal:** Test `set_track_volume()` API

**Test Method:** Set various volume levels on master track

**FFI Calls:**
```
set_track_volume_ffi(0, -6.0)  → Master at -6 dB
set_track_volume_ffi(0, 0.0)   → Master at 0 dB (unity)
set_track_volume_ffi(0, 3.0)   → Master at +3 dB
set_track_volume_ffi(0, -96.0) → Master at -∞ dB (silent)
```

**Expected Result:**
- [ ] Each call returns success message
- [ ] `get_track_info_ffi(0)` shows updated volume_db
- [ ] Volume clamped to -96.0 to +6.0 dB range

**Actual Results:**
```
-6 dB: _____________________________
0 dB:  _____________________________
+3 dB: _____________________________
-96 dB: _____________________________
```

**Note:** Audio volume changes not testable until per-track mixing is implemented.

---

### ✅ Scenario 8: Set Track Pan

**Goal:** Test `set_track_pan()` API

**Test Method:** Set pan positions on a track

**FFI Calls:**
```
set_track_pan_ffi(1, -1.0)  → Full left
set_track_pan_ffi(1, 0.0)   → Center
set_track_pan_ffi(1, 1.0)   → Full right
set_track_pan_ffi(1, -0.5)  → Half left
```

**Expected Result:**
- [ ] Each call returns success message
- [ ] `get_track_info_ffi(1)` shows updated pan value
- [ ] Pan clamped to -1.0 to +1.0 range

**Actual Results:**
```
Left (-1.0):  _____________________________
Center (0.0): _____________________________
Right (1.0):  _____________________________
Half left:    _____________________________
```

---

### ✅ Scenario 9: Mute Track

**Goal:** Test `set_track_mute()` API

**Test Method:** Mute/unmute a track

**FFI Calls:**
```
set_track_mute_ffi(1, true)   → Mute track 1
get_track_info_ffi(1)         → Check mute status
set_track_mute_ffi(1, false)  → Unmute track 1
get_track_info_ffi(1)         → Check mute status
```

**Expected Result:**
- [ ] Mute call returns success message
- [ ] Track info shows mute=1 when muted
- [ ] Track info shows mute=0 when unmuted

**Actual Results:**
```
Mute ON:  mute field = _____
Mute OFF: mute field = _____
```

---

### ✅ Scenario 10: Solo Track

**Goal:** Test `set_track_solo()` API

**Test Method:** Solo/unsolo a track

**FFI Calls:**
```
set_track_solo_ffi(1, true)   → Solo track 1
get_track_info_ffi(1)         → Check solo status
set_track_solo_ffi(1, false)  → Unsolo track 1
get_track_info_ffi(1)         → Check solo status
```

**Expected Result:**
- [ ] Solo call returns success message
- [ ] Track info shows solo=1 when soloed
- [ ] Track info shows solo=0 when unsoloed

**Actual Results:**
```
Solo ON:  solo field = _____
Solo OFF: solo field = _____
```

---

### ✅ Scenario 11: Invalid Track Operations

**Goal:** Test error handling for invalid track IDs

**Test Method:** Try operations on non-existent track

**FFI Calls:**
```
get_track_info_ffi(999)        → Should return error
set_track_volume_ffi(999, 0.0) → Should return error
set_track_mute_ffi(999, true)  → Should return error
```

**Expected Result:**
- [ ] All calls return error messages (not crash)
- [ ] Error message contains "Track 999 not found"

**Actual Results:**
```
get_track_info:    _____________________________
set_track_volume:  _____________________________
set_track_mute:    _____________________________
```

---

### ✅ Scenario 12: Cannot Create Master Track

**Goal:** Verify only one master track allowed

**Test Method:** Try to create additional master track

**FFI Call:**
```
create_track_ffi("master", "Master 2") → Should fail
```

**Expected Result:**
- [ ] Returns error: "Cannot create additional master tracks"
- [ ] Track count unchanged

**Actual Result:**
```
[Record error message]
```

---

### ✅ Scenario 13: Volume/Pan Calculations (Unit Test)

**Goal:** Verify dB to linear conversion and pan law math

**Test Method:** Check calculated values (via code inspection or debug print)

**Test Cases:**
```
Volume:
  -96 dB → 0.0 (silent)
  -6 dB  → ~0.5
  0 dB   → 1.0 (unity)
  +6 dB  → ~2.0

Pan (equal-power):
  -1.0 (full left)  → (1.0, 0.0)
  0.0 (center)      → (0.707, 0.707)
  +1.0 (full right) → (0.0, 1.0)
```

**Expected Result:**
- [ ] Volume calculations correct
- [ ] Pan calculations use equal-power law
- [ ] No NaN or infinite values

**Verification Method:**
```
[Add debug prints to Track::get_gain() and Track::get_pan_gains() if needed]
```

---

### ✅ Scenario 14: Move Clip to Track (Migration API)

**Goal:** Test `move_clip_to_track()` API

**Prerequisites:** Load an audio file (creates clip on global timeline)

**Test Method:** Move clip from global timeline to a track

**Steps:**
1. Load audio file → creates clip ID 0 on global timeline
2. Create audio track → ID 1
3. Call `move_clip_to_track_ffi(1, 0)` → move clip 0 to track 1

**Expected Result:**
- [ ] Returns success message: "Moved clip 0 to track 1"
- [ ] Clip removed from global timeline
- [ ] Clip added to track 1's audio_clips list

**Actual Result:**
```
[Record result]
```

**Note:** Clip won't play from track yet (per-track mixing not implemented).

---

### ✅ Scenario 15: Regression Test - M0/M1/M2/M3 Still Work

**Goal:** Ensure M4 changes didn't break existing features

**Quick Checks:**
- [ ] **M0:** Play beep button works (if exists)
- [ ] **M1:** Load audio file, play/pause/stop works
- [ ] **M1:** Waveform rendering works
- [ ] **M2:** Record audio button works
- [ ] **M2:** Metronome works
- [ ] **M3:** Virtual piano works (keyboard input)
- [ ] **M3:** MIDI playback with synthesizer works

**Actual Results:**
```
M0: _____
M1 Playback: _____
M1 Waveform: _____
M2 Recording: _____
M2 Metronome: _____
M3 Piano: _____
M3 MIDI: _____
```

---

## Performance Tests

### ⚡ Scenario 16: CPU Usage with Master Limiter

**Goal:** Measure CPU impact of master limiter

**Test Method:** Monitor CPU usage in Activity Monitor

**Steps:**
1. Note CPU usage at idle (no playback): _____%
2. Start playback (audio file or MIDI): _____%
3. Compare to M3 CPU usage (if recorded): _____%

**Expected Result:**
- [ ] Master limiter adds <1% CPU overhead
- [ ] No audio glitches or dropouts

**Actual Results:**
```
Idle:       _____%
Playback:   _____%
Difference: _____%
```

---

### ⚡ Scenario 17: Master Limiter Preventing Clipping

**Goal:** Verify limiter catches peaks

**Test Method:** Play very loud audio (or stack multiple audio files)

**Steps:**
1. Load multiple audio files (or play loud sample)
2. Play all simultaneously (if possible with current implementation)
3. Listen for distortion
4. Check output stays below 0 dBFS

**Expected Result:**
- [ ] No clipping/distortion heard
- [ ] Audio is loud but clean
- [ ] Limiter is actively reducing gain on peaks

**Actual Result:**
```
Audio quality: _____
Clipping detected: Yes / No
Limiter working: Yes / No
```

---

## Console Output Validation

### Expected Debug Messages

During testing, you should see these console messages:

**Startup:**
```
✅ Audio graph initialized: M1: Audio graph initialized
🎚️ [AudioGraph] M4 initialized: TrackManager, EffectManager, Master Limiter
```

**Track Creation:**
```
🎚️ [TrackManager] Created Audio track 'Audio 1' (ID: 1)
🎚️ [TrackManager] Created MIDI track 'MIDI 1' (ID: 3)
🎚️ [TrackManager] Created Return track 'Reverb' (ID: 4)
```

**Track Operations:**
```
(No specific debug output, just no errors)
```

### Error Messages (Expected for Invalid Operations)

```
❌ [FFI] create_track error: Cannot create additional master tracks
Track 999 not found
Error: Track 999 not found
```

---

## Known Limitations (Expected Behavior)

These are **NOT bugs**, they are features deferred to later milestones:

1. **Track volume/pan don't affect audio yet** - Per-track mixing not implemented
   - API works, but audio callback still uses global timeline
   - Will be integrated in M7 or when completing M4

2. **Mute/solo don't affect audio yet** - Same reason as above
   - Flags are set correctly, just not processed in audio callback

3. **No mixer panel UI** - Deferred to M7
   - All backend APIs work, UI not built yet

4. **No effect plugin UIs** - Deferred to M7
   - Effects are implemented, just no UI to control them

5. **No peak meters UI** - Deferred to M7
   - Peak calculation in Track struct ready, no UI to display it

6. **No send/return routing** - Deferred to v1.1
   - Return tracks can be created, but no audio routed to them yet

---

## Test Summary

### Core Features Status

| Feature | Test Status | Working? | Notes |
|---------|-------------|----------|-------|
| Track creation | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Track info retrieval | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Set volume API | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Set pan API | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Mute API | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Solo API | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Master limiter | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Error handling | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| Move clip to track | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |
| M0-M3 regression | [ ] Pass / [ ] Fail | [ ] Yes / [ ] No | |

---

## Issues Found

### Critical Issues (Blockers)
```
[None expected - if found, describe here]
```

### Major Issues (Functionality Problems)
```
[None expected - if found, describe here]
```

### Minor Issues (Polish/UX)
```
[List any minor issues]
```

---

## Overall Assessment

**M4 Core Backend Status:** [ ] ✅ Pass  [ ] ❌ Fail  [ ] ⏸️ Partial

**Summary:**
```
[Your assessment of M4 core functionality]
```

**Recommendation:**
- [ ] ✅ Proceed to M5 (Save & Export)
- [ ] ⏸️ Fix issues first
- [ ] ❌ Major problems found, need investigation

---

**Tested By:** ___________
**Date:** ___________
**Test Duration:** ___________
**Next Steps:** See M4_INTEGRATION_TEST_SUMMARY.md for results

---

## Reference: How to Call FFI Functions

**From Dart/Flutter:**
```dart
// Example (pseudo-code - adapt to your FFI bridge)
final DynamicLibrary engine = DynamicLibrary.open('libengine.dylib');

final createTrack = engine.lookupFunction<
  Int64 Function(Pointer<Utf8>, Pointer<Utf8>),
  int Function(Pointer<Utf8>, Pointer<Utf8>)
>('create_track_ffi');

int trackId = createTrack('audio'.toNativeUtf8(), 'Audio 1'.toNativeUtf8());
```

**From Rust/Console (for testing):**
```rust
// Add test in api.rs
#[test]
fn test_track_creation() {
    let result = create_track("audio", "Test Track".to_string());
    assert!(result.is_ok());
    println!("Created track: {:?}", result);
}
```

Then run: `cargo test test_track_creation -- --nocapture`
