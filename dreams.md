# Boojy Audio — Dreams

## §1 Active Engineering Target

**Target:** v0.4.0 — **Visual & UX polish**. The first dedicated UI/UX pass, scoped from the
2026-05-30 review (`docs/reviews/ui_ux_review_2026_05_30.md`); spec in `docs/plans/v0.4-plan.md`.
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
- [ ] **Phase 3 — Top-bar A/B (last):** _partially shipped (PR #26, `polish/v0.4-phase3`)._ macOS
  title fix (native bar hidden via `window_manager` `TitleBarStyle.hidden`, traffic lights kept →
  the transport bar runs edge-to-edge) + dev "UI Labs" switcher (`Cmd+Shift+L`) + **Variants A
  (inline) & B (LCD panel, taller bar)** done; chosen variant persists (`UserSettings`), centred-
  title slot wired but **off by default**. **Remaining:** Variants C (two-row) & D (arrangement-
  pinned LCD), settle the centred title live, then refine the piano-roll lane *colours*.
- [ ] Deferred to later sessions: the ~390 hardcoded-colour tokenisation (B15/B16) + light/
  high-contrast ramp; effects/device overhaul (universal MIX knob, GR meter, EQ dot-curve);
  Serum/VST3 load bug; scaling the 9 painter text sizes.

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
