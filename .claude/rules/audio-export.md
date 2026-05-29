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
