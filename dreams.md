# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **v0.6 — "Sound"** — spec: `docs/plans/v0.6-plan.md` (opened 2026-06-06 from the
triage). Work order: starter kit (drum-kit PR3) → sound quick wins (automation/reverse/monitoring)
→ join clips → normalize → UI ledger batches → cleanups (chord palette removal, hide High
Contrast).

**Status (2026-06-06):** v0.5.4 draft built + notes filled (Tyr publishing). v0.6 plan written
from `docs/reviews/triage_2026_06_05.md` + the approved drum-kit plan; today's calls: starter kit
= 8 CC0 sounds sourced online, **Tyr approves before commit** (kick, snare, CH, OH, clap, low tom,
mid tom, crash); High Contrast hidden in v0.6; small mixer fixes in, §6.B strip mockup still
parked pending a design conversation.

### Milestones

- [ ] **Publish v0.5.4 draft release** (Tyr) — notes are paste-ready on the draft.
- [ ] **Windows smoke test, round 2** (Tyr, parallel to dev): 5 CLAUDE.md steps + Save As
  (native dialog → `Documents\Boojy\Audio\Projects`), Open round-trip, Export WAV. Failures →
  small v0.5.5 before any v0.6 tag; suspects = Rust `save_project` / `project_manager_native`
  path handling.
- [ ] **macOS regression spot-check** (Tyr, 2 min): dialogs unchanged; Sparkle offers the update
  (live appcast-signature test).
- [ ] **PR3 — starter kit:** source CC0 candidates → Tyr approves → bundle under
  `ui/assets/drumkits/starter/` + first-use copy-out + pre-load on create. LICENSES note.
- [ ] **Sound quick wins:** automation flag-flip + QA · reverse-audio FFI · input monitoring UI.
- [ ] **Join clips as Commands** (fixes C37/C50) → **normalize** → **UI batches 5–8** per plan.

**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
