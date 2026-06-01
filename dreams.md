# Boojy Audio — Dreams

## §1 Active Engineering Target

**Target:** v0.4.0 — **Visual & UX polish**. The first dedicated UI/UX pass, scoped from the
2026-05-30 review (`docs/reviews/ui_ux_review_2026_05_30.md`); spec in `docs/archive/plans/v0.4-plan.md`.
Sequenced **foundation → contained re-treats → top-bar A/B last**, so the A/B happens on the
finished look. The earlier v0.3.3 quick-win bug batch folds into this release — **no separate
v0.3.3 tag** (we skipped it and went straight to v0.4.0).

### Milestones
- [x] **Quick-win bug batch** — version label, About box, start-screen Settings, zoom icon, tempo
  clamp (20–300), velocity-lane colour, clip-colour palette, loop-hint contrast (was PR #21).
- [x] **Phase 1 — Foundation:** bundle Inter + JetBrains Mono; unify the dark ramp to one
  near-neutral **"gunmetal"** dark-grey family (chrome joins content; Graphite/Slate/Indigo are
  live `Cmd+Shift+P` dev presets to A/B); UI Scale setting
  (Compact/Default/Comfortable/Large via `MediaQuery.textScaler`, persisted); elevation tokens +
  `BT.scaled()` helper for painters.
- [x] **Phase 2 — Contained re-treats:** piano-roll keyboard-contrast lanes + accent-blue root band
  + hover active lane (lane *colours* to be refined post-Phase-3); time-readout *behaviour*
  (Bars → Time → Both, persisted) + a pinned arrangement orientation chip (bar at the left edge).
  *(`polish/v0.4-phase2`.)*
- [x] **Phase 3 — Top-bar A/B (last):** macOS title fix (native bar hidden via `window_manager`
  `TitleBarStyle.hidden`, traffic lights kept → transport bar runs edge-to-edge) + dev "UI Labs"
  switcher (`Cmd+Shift+L`) with **all four variants live** — A inline · B LCD panel · C two-row
  (88px) · D arrangement-pinned (52px bar + a non-scrolling LCD readout pinned to the timeline's
  top-left). Chosen variant persists (`UserSettings`). **Centred title decided:** intrinsic to C's
  row 1, global toggle retired. _(PR #26 = title + A/B; C & D + title on `polish/v0.4-phase3-cd`.)_
  **A/B decided 2026-05-31: Variant A (inline) wins** — stays the default; B/C/D kept behind the
  debug switcher (pruning them is a deferred cleanup call).
- [x] **Dogfood polish pass** (`polish/v0.4-chrome-titlestrip`, PR #29, merged 2026-05-31): the
  top-bar/chrome polish (title strip, tool-tidy, always-live record, uniform readouts + BPM split
  button, red-on-failure ▲ logo, one-band bar + Add-Track in the mixer header) **plus** a
  visual/UX dogfood batch — shared `BoojyWordmark` (start screen + settings footer), centred
  transport, piano-roll Loop/Snap restyle, note-colour legibility floor, **note resize in Select
  mode**, type-coloured + icon'd Add-Track buttons, larger/centred macOS title, dB-readout no-wrap,
  and the intermittent **Delete-does-nothing** focus fix. ⚠ two items still want a live eyeball:
  the rebuilt "Boojy" lockup font/kerning, and the transport-centre offset when sidebar≠mixer width.
  Dogfood log: `docs/dogfood/2026-05-31-v0.4-polish.md` (gitignored, local).
- [x] **Fix-before-tag (shipped in v0.4.0):** narrow-window top-bar overflow (ui B-TB1) fixed, and
  **VST3 instrument-reload-silent (C32/B-2) fixed** (root C++ subcategory detection in
  `vst3_get_plugin_info` + universal arm64/Intel lib rebuild). The piano-roll lane-*colour*
  refinement was **deferred to v0.5**.
- [ ] Deferred to later sessions: the ~390 hardcoded-colour tokenisation (B15/B16) + light/
  high-contrast ramp; effects/device overhaul (universal MIX knob, GR meter, EQ dot-curve);
  Serum/VST3 load bug; scaling the 9 painter text sizes. **(Most of these are now the v0.5 theme — see below.)**

### Pre-release review outcome (2026-06-01)

Ran a 3-workflow pre-release review chain before tagging v0.4.0 — reports in `docs/reviews/*_2026_06_01.md`
(`codebase_review`, `ui_ux_review`, `feature_gap_review`) + the consolidated
`v0.4.0_pre_release_triage_2026_06_01.md`. **Verdict: v0.4.0 is safe to tag** — every critical/high
defect is *pre-existing* (already in v0.3.2); the v0.4 polish cycle introduced none, so tagging
regresses nothing. The two fix-before-tag items above are the only genuinely v0.4-era cleanups.

**Next themes decided (all three reviews converged independently):**
- **v0.5 "Trust & Legibility"** — correctness/hardening (VST3 lifecycle C30/C32/C34/C35, DeleteTrack
  content-loss undo C62/68/76/97, recorder audio-thread blocking C1–C3, round-trip tempo C72,
  command/undo holes) **+** the legibility pass (tokenise the ~390 hardcoded colours; painters
  theme + scale). **Do FIRST:** fix CI/test trust — integration tests skip when the dylib is absent
  (C92) and clippy is non-fatal (C95) — plus the `FEATURE_TRACKER.md` accuracy sweep.
- **v0.6 "Sound"** (after hardening) — stock instruments (a new MIDI track is currently *silent*),
  drum sequencer, starter loop pack, effect presets, swing-to-engine.

Fixes are **not yet applied** — awaiting Tyr's approval on the fix-before-tag shortlist, then a fresh
branch off `origin/master`.

**macOS title-bar gotcha:** no native `NSToolbar` style gives "centred + compact" — `.expanded`
centres the title but adds an empty, taller toolbar row; `.unifiedCompact` is compact but
left-aligned. Phase 3 hid the native title (`window_manager` `TitleBarStyle.hidden`, keep the
traffic lights) so the transport bar is the only top chrome. A centred Flutter title is *wired but
off by default* — it collides with the transport controls in single-row variants, so its final form
is being settled live during the A/B (cleanest in the C two-row variant).

**Trap (still live):** `daw_screen.dart` wires PRIVATE `_` copies of its mixins — the mixins are
dead/diverged, so edit the wired private methods, *not* the mixins (review §4).

### How we work here
- Plan **one milestone at a time** — only one active `docs/plans/vX.Y-plan.md`.
- After each release: **dogfood** on a real project, then pick the next theme from friction.
  `docs/ROADMAP.md` + `docs/FEATURE_TRACKER.md` are backlog, not a pre-scheduled ladder.
- **Design decisions (UI/UX)** before locking implementation:
  1. Brainstorm with Tyr — tradeoffs first (UX, then implementation). Ask; don't dictate.
  2. ASCII mockups — 3–4 variants when layout is ambiguous; Tyr picks before code.
  3. Defer on taste, push back on architecture — one clear preference, then collaborate.

<!-- §1 only by design. git log is the history; Claude Code auto memory holds incidental learnings.
     No incident log, no backlog, no session ledger. -->
