# Ideas — future, not scheduled

A lightweight parking lot for design/feature ideas that came up mid-work but
aren't part of the current version's plan. Nothing here is committed to a
milestone — promote an entry into `docs/ROADMAP.md` / a version plan when it's
ready to be built. Keep entries short: what, why, and why it's deferred.

## Mixer

- **M / S / R buttons → visual icons.** The mute / solo / record-arm buttons are
  single letters (M)(S)(R), which aren't obvious to a non-technical / beginner
  user — the exact audience Boojy targets. Explore replacing the letters with
  recognisable glyphs (e.g. a speaker-with-slash for mute, headphone/star for
  solo, a record dot for arm) and/or adding tooltips.
  *Deferred from v0.5 #11 (mixer affordances):* it's a higher-risk change than it
  looks — it touches button semantics, established muscle memory (M/S/R is a DAW
  convention pros expect), and needs its own icon-language pass to stay
  consistent with the `BI` icon facade. Worth a small A/B against the lettered
  version before shipping.
