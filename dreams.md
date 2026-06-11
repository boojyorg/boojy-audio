# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **release v0.6.0, then scope v0.6.1.** v0.6 "Sound" shipped: spec archived at
`docs/archive/plans/v0.6-plan.md`; all six bug-hunt fix batches + the dogfood round-2 wordmark
batch (#92) merged; dogfood round 2 PASSED (Tyr, 2026-06-11) → tag approved.

**Status (2026-06-11):** **v0.6.0 RELEASED** (PR #93 merged, tagged, draft built + published
by Tyr; README hero updated to a v0.6.0 capture, #94). Appcast verified: bare base64
edSignature in the published appcast.xml — the double-wrap bug is fixed in the wild.

Remaining:

- [ ] **Sparkle spot-check** (Tyr, 1 min): open the installed v0.5.4 — it should offer the
  v0.6.0 update. This is the last live test of the appcast-signature fix.
- [ ] v0.6.1 scoping: dogfood backlog (hover/press animation sweep in BACKLOG.md, §6.B strip
  mockup still parked) — run the milestone-review step before opening a plan doc.
- [ ] Housekeeping: delete the staged `docs/reviews/_screenshots/*.png` (staging-only, per
  that folder's README); prune now-unused brand-source PNGs from `ui/assets/images/`
  (boojy-logo, boojy_audio_app_udio, boojy_audio_app_triangle_A, boojy_audio_text,
  boojy_audio_text_Audio — the app uses the derived `*_text_black/white.png`; keep
  boojy_audio_audi.svg per the standing note).


**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
