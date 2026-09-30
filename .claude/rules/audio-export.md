---
paths:
  - engine/src/export/**
---

# Audio export (WAV / MP3)

- **WAV** (`wav.rs`): pure Rust via `hound`; 16/24-bit and 32-bit float, optional dither. The
  dependency-free path.
- **MP3** (`mp3.rs`): pipes PCM to the `ffmpeg` CLI, an external runtime dependency. Missing
  ffmpeg is an error, not a WAV fallback. Planned: replace with the `mp3lame-encoder` crate.

## Processing order is load-bearing

`export_wav` and `export_mp3` (and stems, which route through them) run in this order:

1. **Range slice** (`slice_export_range`) on the raw 48 kHz stereo render. The whole project is
   still rendered from 0 so effects are warmed up; slice after render, never render mid-timeline.
2. **Platform LUFS target** (`apply_platform_lufs`) before mixdown/resample. When a target is set,
   peak normalisation is skipped.
3. Mono mixdown → resample.
4. **Peak normalise last** (resampling shifts peaks).

## Offline-render invariants (tests in `engine/src/api/tests.rs`)

- **Built-in FX are pinned to `TARGET_SAMPLE_RATE`** during `render_offline` and
  `render_track_offline`, then restored to the live rate. VST3 is excluded (a rate change is a
  full reinit).
- **Offline renders start from silence:** `reset_builtin_fx_offline` first, so no leftover
  envelopes or tails from playback. VST3 is not reset.
- **Stems use the mix's gain order** (clips/synth → FX → fader/pan), but the **mix has a master
  stage stems don't** (master volume → constant-power pan → master FX → limiter). Don't "fix"
  stem ≠ mix by touching the master stage.
