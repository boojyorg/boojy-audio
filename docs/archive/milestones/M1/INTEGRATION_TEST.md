# M1 Integration Test Guide

## Setup

### 1. Create a Test WAV File

You need a WAV file at `~/Downloads/test.wav` for testing.

**Option A: Use an existing WAV file**
- Copy any WAV file to `~/Downloads/test.wav`

**Option B: Generate a test tone (using macOS)**
```bash
# Generate a 5-second 440Hz sine wave test file
sox -n -r 48000 -c 2 ~/Downloads/test.wav synth 5 sine 440
```

**Option C: Use Python to generate a test file**
```python
import wave
import struct
import math

# Generate 3-second test tone at 440Hz
sample_rate = 48000
duration = 3
frequency = 440

with wave.open('/Users/tyrbujac/Downloads/test.wav', 'w') as wav_file:
    wav_file.setnchannels(2)  # Stereo
    wav_file.setsampwidth(2)  # 16-bit
    wav_file.setframerate(sample_rate)
    
    for i in range(sample_rate * duration):
        value = int(32767 * 0.3 * math.sin(2 * math.pi * frequency * i / sample_rate))
        packed_value = struct.pack('h', value)
        wav_file.writeframes(packed_value + packed_value)  # Write to both channels

print("Test file created: ~/Downloads/test.wav")
```

## Testing Steps

1. **Launch the App**
   ```bash
   cd ui
   flutter run -d macos
   ```

2. **Test M0 (Verification)**
   - Click "Play Beep" button
   - You should hear a 1-second 440Hz tone
   - Status should show "Playing 440.0 Hz sine wave for 1000 ms"

3. **Test M1 Integration**
   
   **Step 1: Initialize Audio Graph**
   - Click "1. Initialize Audio Graph" button
   - Button should turn green with checkmark
   - Status should show "M1: Audio graph initialized"
   
   **Step 2: Load Test File**
   - Make sure `~/Downloads/test.wav` exists
   - Click "2. Load Test File" button
   - Button should turn green with checkmark
   - Status should show clip ID and duration (e.g., "Loaded clip 0 (3.00s)")
   
   **Step 3: Playback Controls**
   - Click the **Play** button (green)
     - You should hear the audio file playing
     - Playhead position should update in real-time
     - Status shows "Playing"
   
   - Click the **Pause** button (yellow)
     - Audio should pause
     - Playhead position should freeze
     - Status shows "Paused"
   
   - Click **Play** again
     - Audio should resume from paused position
   
   - Click the **Stop** button (red)
     - Audio should stop
     - Playhead should reset to 0.000s
     - Status shows "Stopped"

## Expected Behavior

### Console Output
You should see logs like:
```
🔍 [AudioEngine] Attempting to load library...
✅ [AudioEngine] Library loaded successfully
🔗 [AudioEngine] Binding FFI functions...
✅ [AudioEngine] All functions bound successfully
🎵 [AudioEngine] Initializing audio graph...
✅ [AudioEngine] Audio graph initialized
📂 [AudioEngine] Loading audio file: /Users/tyrbujac/Downloads/test.wav
✅ [AudioEngine] Audio file loaded, clip ID: 0
▶️  [AudioEngine] Starting playback...
✅ [AudioEngine] Playing
```

### Visual Feedback
- Buttons change color based on state (green = success, disabled = gray)
- Playhead position updates smoothly (50ms interval)
- Status messages update for each action

## Troubleshooting

### "Library file NOT found"
- Rebuild the Rust engine in release mode:
  ```bash
  cd engine
  cargo build --release
  ```

### "Failed to load file"
- Check file exists: `ls -lh ~/Downloads/test.wav`
- Verify it's a valid WAV file: `file ~/Downloads/test.wav`
- Check file is readable: `chmod 644 ~/Downloads/test.wav`

### "Audio graph not initialized"
- Click "1. Initialize Audio Graph" first
- Check console for error messages

### No sound during playback
- Check system volume
- Check macOS Sound settings (System Preferences → Sound)
- Verify the WAV file plays in other apps (QuickTime, etc.)
- Check console for Rust audio errors

### Playhead not updating
- This is expected if no file is loaded or not playing
- During playback, it should update every 50ms
- If frozen during playback, check console for errors

## Success Criteria

✅ All steps complete without errors
✅ Can hear M0 beep test
✅ Can initialize audio graph
✅ Can load WAV file
✅ Can play/pause/stop audio
✅ Playhead position updates during playback
✅ Audio quality is good (no crackling, pops, or glitches)

## Next Steps

Once this integration test passes:
1. Build Timeline UI widget
2. Add waveform rendering
3. Implement drag & drop file import
4. Add proper transport controls to timeline

---

**Test completed:** [  ]  
**Date:** ________________  
**Issues found:** ________________

