# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

<!-- ⚠️ DRAFT (2026-06-03): rewritten from the old v0.4 dreams during the docs standardisation.
     v0.4.0 shipped; v0.5 work has begun. Sanity-check the target framing below and adjust. -->

## §1 Active Engineering Target

**Status:** **v0.4.0 shipped** — the visual/UX polish cycle (type + gunmetal palette + UI Scale →
piano-roll re-treats → top-bar A/B, Variant A won → chrome/dogfood polish). The 2026-06-01
pre-release review chain confirmed it was taggable (critical defects are all pre-existing, not v0.4
regressions). Reports in `docs/reviews/*_2026_06_01.md`.

**Target — v0.5.0 "Trust & Legibility":** correctness/hardening for when a session leaves the happy
path (VST3 lifecycle, DeleteTrack undo content-loss, recorder audio-thread blocking, round-trip
tempo, command/undo holes) **+** make the design tokens load-bearing (tokenise the ~390 hardcoded
colours; theme + scale the painters). Full theme writeup → `docs/ROADMAP.md`; defect IDs → the
2026-06-01 review reports.

**Do first (CI/test trust):**
- [ ] C92 — integration tests silently *skip* when the dylib is absent → make absence a **failing**
  test under CI (already partly handled in `build-and-test.md` — confirm/finish).
- [ ] C95 — clippy is non-fatal in CI → make warnings fail the build.
- [ ] `docs/FEATURE_TRACKER.md` accuracy sweep (only tick items reachable end-to-end).

**In flight:** mixer fader affordances (branch `feat/v0.5-mixer-fader-affordances`).

**Pending decision:** the larger v0.5 correctness/hardening fix set is *scoped from the reviews but
not yet started* — confirm the shortlist with Tyr before opening `docs/plans/v0.5-plan.md` and
branching the hardening work off `master`.
