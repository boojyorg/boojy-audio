# Boojy Audio — Who It's For

**Last updated:** 2026-03-29

---

## The Positioning

Boojy Audio sits between GarageBand (too simple) and Ableton/Logic (too complex). It's for musicians who outgrew GarageBand but find professional DAWs intimidating.

**GarageBand** feels like a toy — friendly but limiting.
**Ableton** feels like a cockpit — powerful but intimidating.
**Boojy** should feel like a comfortable studio — everything's within reach, nothing's confusing, and the room sounds good.

---

## Three Core Users

### 1. The Beat Maker

Sits down with an idea in their head. Wants a drum pattern going in 30 seconds, layer a bass, add a melody, hear it loop.

**Cares about:**
- Fast instrument loading
- Good built-in sounds
- Snappy piano roll
- Easy looping
- Export to MP3 to send to mates or post on SoundCloud

**Doesn't care about:**
- Detailed mixing
- Automation curves
- Sidechain routing
- Mastering meters

### 2. The Vocalist / Singer-Songwriter

Plugs in a mic, hits record, sings over a simple chord progression.

**Cares about:**
- Easy audio recording
- A simple way to lay down chords (piano or guitar plugin)
- Basic effects on their voice (reverb, compression)
- Punch-in to fix mistakes

**Doesn't care about:**
- MIDI velocity editing
- Complex plugin chains
- Step sequencers

### 3. The Home Band

Guitarist, bassist, vocalist, maybe a drummer recording at home.

**Cares about:**
- Multi-track audio recording
- Overdubbing (record one instrument at a time over the others)
- Basic mixing (volume balance between instruments)
- Exporting stems to share with bandmates or send to a mixer

**Doesn't care about:**
- MIDI synthesis
- Sample libraries
- Beat-making workflows

---

## What They All Have in Common

### Every musician wants:
- To hear their idea quickly (low friction from "open app" to "making sound")
- Recording that works first try (input selection, levels, count-in)
- The app to not get in the way of creativity
- Simple mixing (just make it sound decent)
- Easy export (send to someone, post online)
- To not feel stupid using it

### Nobody wants:
- To read a manual before making sound
- To configure audio routing before recording
- To see 50 buttons they don't understand
- To feel like the app is judging their skill level

---

## Design Principles (from this thinking)

### 1. Speed of Capture
A musician has an idea that will disappear in 60 seconds. The app needs to get out of the way. The MIDI Capture button is a perfect example — it respects that creativity doesn't wait for you to press record.

### 2. Forgiveness
Musicians make mistakes and want to fix them without starting over. Punch-in recording, unlimited undo, non-destructive editing. The app should feel safe — "I can try anything and undo it."

### 3. Sound Quality Out of the Box
A musician doesn't want to learn mixing to make their recording sound good. Consider preset effect chains — a simple "enhance" on vocal tracks (subtle compression + EQ + reverb) that makes a raw recording sound polished with zero effort. Not auto-tune, just "make my voice not sound like a raw mic recording." GarageBand does this and musicians love it.

### 4. Collaboration-Friendly Export
Musicians work with other people. "Send this to my bandmate" should be easy. Export to MP3 and open in Finder, or a "Share" button that creates an MP3 and opens the system share sheet.

### 5. The Emotional Experience Matters More Than Features
A musician choosing between Boojy and GarageBand isn't comparing feature lists. They're comparing how the app makes them feel. The star field, the clean design, the "everything you need, nothing you don't" philosophy — that's already building the "comfortable studio" feeling.

---

## Concrete Implications for Development

### Auto-arm audio tracks
When a user creates a new audio track and has a mic connected, auto-arm it for recording and show the input level immediately. Don't make them find the record-arm button and the input selector. The app should say "I see your mic, I'm ready when you are."

### Preset effect chains
"Vocal" track preset: auto-applies subtle compression + EQ + reverb. "Guitar" track preset: light compression + cabinet sim. The user gets a good sound without touching any knobs.

### One-click export
Export button that defaults to MP3, names the file after the project, and opens the destination folder. No format dialog, no sample rate selection, no dithering options. Just "Export" → done.

### Smart defaults everywhere
- New project: 120 BPM, 4/4, one empty MIDI track ready to go
- Input monitoring: on by default for armed tracks
- Loop: on by default (musicians think in loops)
- Snap: on by default, to bar (not to tick)
- Metronome: on by default during recording, off during playback

---

## Current Design Lean

Boojy currently leans toward **beat makers** — piano roll, MIDI instruments, sample browser. That's a strong core. But to reach vocalists and bands, the audio recording experience needs equal attention. A vocalist opening Boojy for the first time should be able to:

1. Open app
2. Create project
3. See their mic is detected
4. Hit record
5. Sing, hit stop, hear it back

That's five steps. If any step requires configuration or hunting through menus, you've lost them.
