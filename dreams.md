# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **release v0.6.0, then scope v0.6.1.** v0.6 "Sound" shipped: spec archived at
`docs/archive/plans/v0.6-plan.md`; all six bug-hunt fix batches + the dogfood round-2 wordmark
batch (#92) merged; dogfood round 2 PASSED (Tyr, 2026-06-11) → tag approved.

**Status (2026-06-11):** Release in flight. Remaining:

- [ ] Release-prep PR (`release/v0.6.0`): Version Sync done (CHANGELOG v0.6.0, ROADMAP,
  README, pubspec 0.6.0+10, plan archived, FEATURE_TRACKER sampler note) → CI → merge.
- [ ] Tag `v0.6.0` on master → CI builds draft DMG/EXE.
- [ ] **Windows smoke test** (Tyr, 5-step CLAUDE.md checklist) BEFORE publishing the draft.
- [ ] Publish release → then **Sparkle spot-check** (installed v0.5.4 should offer v0.6.0;
  verify published appcast.xml edSignature is bare base64 before announcing auto-update fixed).
- [ ] v0.6.1 scoping: dogfood backlog (hover/press animation sweep in BACKLOG.md, §6.B strip
  mockup still parked) — run the milestone-review step before opening a plan doc.


**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
