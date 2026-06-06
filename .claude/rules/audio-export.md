---
paths:
  - engine/src/export/**
---

# Audio export (WAV / MP3)

`engine/src/export/` renders offline audio to disk. Two formats:

- **WAV** — pure Rust via the `hound` crate (`wav.rs`): 16-/24-bit and 32-bit float, optional
  dithering. No external dependency. This is the reliable path.
- **MP3** — **shells out to the `ffmpeg` CLI** (`mp3.rs`): pipes PCM to `ffmpeg` over stdin. This is
  an external *runtime* dependency, which is off-pattern for a self-contained native app.

## Processing order is load-bearing (v0.5.2 / C16+C18)

Both `export_wav` and `export_mp3` process in this fixed order — don't reorder casually:

1. **Range slice** (`slice_export_range`, in `wav.rs`) — trims to `options.start_time/end_time`
   first, on the raw 48 kHz stereo render. Empty/inverted/past-the-end ranges are hard errors. The
   full project is still *rendered* from 0 so FX (reverb tails, compressors) are warmed up at the
   range start — slice after render, never render from mid-timeline.
2. **Platform LUFS target** (`apply_platform_lufs`) — must run **before mono mixdown/resample**
   (the LUFS measurement assumes stereo interleave at the engine rate). When a target is set, peak
   normalization is **skipped** — re-scaling to a peak afterwards would break the loudness target.
3. Mono mixdown → resample.
4. **Peak normalize** — must run **last** (post-resample; resampling can shift peaks).

Stems route through the same two functions, so range/LUFS apply to stems automatically. The
gain-stage order in `render_track_offline` (stems) is clips/synth → FX → fader/pan, deliberately
matching `render_offline` (C68) — a stem's compressor must see the same pre-fader signal as the mix.
Note the UI does not yet expose range/platform-target controls — the options work engine-side and
arrive via the `ExportOptions` JSON.

Three more offline-render invariants (locked by the v0.5.2 P7/P8 tests in
`engine/src/api/tests.rs`):

- **Offline renders pin built-in FX to `TARGET_SAMPLE_RATE`.** Effect coefficients follow the
  *live* stream rate (the renderer fans it out via `EffectManager::set_sample_rate` when the
  stream opens — C12/P8), but offline renders are written as 48 kHz files. Both `render_offline`
  and `render_track_offline` call `set_builtin_sample_rate(TARGET_SAMPLE_RATE)` first and restore
  the live rate at the end. VST3 is excluded from the pin (a VST3 rate change is a full
  deactivate/reinit cycle — C26/C27–C30).

- **Offline renders start from silence.** Effect instances are shared with live playback, so both
  `render_offline` and `render_track_offline` call `reset_builtin_fx_offline` first — otherwise an
  export made after playback (or a stem bounced after the mix) starts with leftover compressor
  envelopes / delay / reverb tails. VST3 is deliberately *not* reset (its `reset()` is a full
  deactivate/reinit cycle — VST3 fidelity is its own later cycle, C27–C30).
- **The full mix has a master stage that stems don't:** master volume → constant-power master pan
  (≈0.707 per channel at centre) → master FX → master limiter. A single-track stem equals the mix
  only after factoring that stage out — don't "fix" stem≠mix by touching the master stage.

## Reality of the ffmpeg fallback (don't trust the comment)

- The doc-comment at the top of `mp3.rs` says it "falls back to WAV if ffmpeg is not available" —
  that is **stale**. The code does **not** auto-fall-back: if `is_ffmpeg_available()` is false,
  `export_mp3` returns an `Err`. WAV is a *separate user-selectable format*, not an automatic
  substitute.
- The missing-ffmpeg error message covers **macOS (`brew install ffmpeg`) and Linux
  (`apt install ffmpeg`)** but **not Windows**. Small fix worth doing: add a Windows line to that
  message so the guidance is genuinely cross-platform.

## Planned fix

Replace the `ffmpeg` CLI shell-out with the **`mp3lame-encoder`** crate so MP3 export is in-process
and has no external runtime dependency. Until that lands: keep WAV as the dependency-free format and
keep the missing-ffmpeg message cross-platform.
