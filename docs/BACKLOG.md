# Boojy Audio — Backlog

Unscheduled / someday: loose bugs, QoL, and chores not yet pulled into a version. Pull an item into
`dreams.md` when it becomes the active target. Ordered intentions + version table → `ROADMAP.md`;
per-feature status → `FEATURE_TRACKER.md`; new-feature ideas → `IDEAS.md`.

> Most deferred work already has a home — the v0.5/v0.6 themes are in `ROADMAP.md`, feature gaps in
> `FEATURE_TRACKER.md`, and the "Road to v1.0" tiers there. This file is only for items that fit none
> of those yet.

## Bugs
- [ ] Serum / VST3 instrument load bug — some plugins fail to load/reopen cleanly (track the specific
  repro; part of the broader VST3-lifecycle hardening in v0.5).

## QoL / UX (unscheduled)
- [ ] Hover/press animation sweep (v0.6.1 candidate, Tyr 2026-06-11) — extend the button-role
  language with hover-scale (~1.02) + press-scale (~0.98) tokens on `AnimationConstants`,
  modelled on the recent-projects card grow (first shipped instance, looks good). Apply to
  navigation/creation surfaces only: start-screen action buttons, Add Track, dialog primary
  buttons, maybe drum pads. **Never** on performance surfaces (M/S/R/I, transport, tools,
  faders) — #87 just removed perceived latency there; animation would reintroduce it.
- [ ] ASIO output support on Windows — the engine already has the code path (`cargo build
  --features asio`, enumeration in `device.rs` behind the feature flag) but release builds don't
  enable it: CI would need the Steinberg ASIO SDK (`CPAL_ASIO_DIR`) + LLVM for bindgen, plus SDK
  licence review. Deliberately deferred 2026-06-06: WASAPI shared mode is the right beginner
  default; revisit only if real users with audio interfaces report latency pain.
- [ ] Effects & device overhaul — a universal **MIX** (dry/wet) knob across effects, a gain-reduction
  (GR) meter on the compressor, and an EQ dot-curve display. (Distinct from the v0.6 "effect presets"
  feature — this is the device-UI layer.)
- [ ] Sample-rate selector in audio settings — dropdown next to the device picker (cpal can enumerate
  a device's supported rates and request one, like Ableton via CoreAudio). Today the engine follows
  the device rate (deliberate GarageBand-style default — keep that as the default); the selector is
  for users who'd otherwise have to leave the app for Audio MIDI Setup. Came up during the v0.5.2
  hardware pass: would also make the 44.1↔48 kHz tests runnable in-app.
