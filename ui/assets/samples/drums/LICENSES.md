# Bundled drum samples — licences & provenance

All bundled samples are CC0 / public domain or created in-house. Verified 2026-06-06.

## Sonic Pi samples (22 files)

Source: <https://github.com/sonic-pi-net/sonic-pi>, `etc/samples/`. Per its README, the samples
are from freesound.org and "have also been placed in the public domain via the Creative Commons 0
License" (<https://creativecommons.org/publicdomain/zero/1.0/>), with per-sample links to the
original freesound uploads. Converted FLAC → WAV 16-bit/44.1 kHz (lossless transcode).

| Bundled file | Sonic Pi sample |
| --- | --- |
| Kicks/808 Kick.wav | `bd_808` |
| Kicks/House Kick.wav | `bd_haus` |
| Kicks/Techno Kick.wav | `bd_tek` |
| Snares/Electro Snare.wav | `elec_snare` |
| Snares/Bright Snare.wav | `elec_hi_snare` |
| Snares/Fat Snare.wav | `sn_dolf` |
| Hats/Closed Hat.wav | `drum_cymbal_closed` |
| Hats/Tight Hat.wav | `hat_star` |
| Hats/Soft Hat.wav | `hat_tap` |
| Hats/Open Hat.wav | `drum_cymbal_open` |
| Hats/Metal Hat.wav | `hat_metal` |
| Hats/Noise Hat.wav | `hat_noiz` |
| Claps/Snap.wav | `perc_snap` |
| Claps/Snap 2.wav | `perc_snap2` |
| Toms/Low Tom.wav | `drum_tom_lo_hard` |
| Toms/Low Tom Soft.wav | `drum_tom_lo_soft` |
| Toms/Fuzz Tom.wav | `elec_fuzz_tom` |
| Toms/Mid Tom.wav | `drum_tom_mid_hard` |
| Toms/Mid Tom Soft.wav | `drum_tom_mid_soft` |
| Cymbals/Splash.wav | `drum_splash_hard` |
| Cymbals/Crash.wav | `drum_cymbal_hard` |
| Cymbals/Short Cymbal.wav | `elec_cymbal` |

## Created in-house (1 file)

| Bundled file | Origin |
| --- | --- |
| Claps/909 Clap.wav | Synthesized from scratch for Boojy Audio (band-passed noise bursts, 909-style architecture). No sampled material. |

## Synthesised-drums experiment (6 files) — CC0

Rendered one-shots migrated from Boojy's `synthesised-drums` prototype (verdict PASS,
2026-06-14). All output is CC0; the Tier 2 voices degrade CC0 feedstock so the result remains
CC0. See that repo's `ASSET_SOURCES.md` / `AUDIO_LICENSE.md` for the full chain.

| Bundled file | Tier | Origin |
| --- | --- | --- |
| Kicks/Analog Kick.wav | 1 — pure synthesis | Generated entirely by DSP (detuned-sine kick, exponential pitch/amp envelopes). No sampled material. |
| Snares/Analog Snare.wav | 1 — pure synthesis | Generated entirely by DSP (tone body + band-passed noise). No sampled material. |
| Hats/Analog Hat.wav | 1 — pure synthesis | Generated entirely by DSP (summed detuned squares + high-pass). No sampled material. |
| Snares/Lo-Fi Snare.wav | 2 — clean-room PCM | CC0 VCSL "Snare Drum, Modern 1" (<https://github.com/sgossner/VCSL>, CC0 1.0) degraded in-engine (25 kHz / 8-bit + reconstruction filter). Output CC0. |
| Hats/Lo-Fi Hat.wav | 2 — clean-room PCM | CC0 VCSL "Hi-Hat Cymbal" (<https://github.com/sgossner/VCSL>, CC0 1.0) degraded in-engine. Output CC0. |
| Claps/Lo-Fi Clap.wav | 2 — clean-room PCM | In-house `perc_clap` generator (band-passed noise bursts) degraded in-engine. No sampled material. |
