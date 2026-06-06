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

**Status (2026-06-06, session end):** the **drum-kit stack is DONE and on master** — engine (#44),
editor (#65 — rescued: #45 had "merged" into its stacked base branch, never reaching master; see
the stacked-PR rule in the suite `CLAUDE.md`), and starter kit + Library Samples content (#66,
CI green, Tyr verified the one-click beat + Samples browsing in-app). Bundled content lives in
`ui/assets/samples/drums/` (23 CC0/in-house one-shots, licences in `LICENSES.md`), copied to
app-support by `bundled_content_service.dart`. Settled today: starter kit = electronic, the 8
"01" picks; Samples → Drums → six type folders showing all 23; High Contrast hidden in v0.6;
small mixer fixes in, §6.B strip mockup still parked pending a design conversation.

### Milestones

- [ ] **Publish v0.5.4 draft release** (Tyr) — notes are paste-ready on the draft (verify it
  actually went out: `gh release list` should show v0.5.4 as Latest, not Draft).
- [ ] **Windows smoke test, round 2** (Tyr, parallel to dev): 5 CLAUDE.md steps + Save As
  (native dialog → `Documents\Boojy\Audio\Projects`), Open round-trip, Export WAV. Failures →
  small v0.5.5 before any v0.6 tag; suspects = Rust `save_project` / `project_manager_native`
  path handling.
- [ ] **macOS regression spot-check** (Tyr, 2 min): dialogs unchanged; Sparkle offers the update
  (live appcast-signature test).
- [x] **PR3 — starter kit** (#66 merged): 23 CC0/in-house WAVs bundled + first-use copy-out +
  8 pads pre-loaded on create (GM notes 36/38/42/46/39/41/47/49) + Samples category wired
  (+ fixed: top-level category items never rendered; + Windows `p.basename` fix in scanFolder).
- [ ] **Sound quick wins** (NEXT): automation flag-flip + QA · reverse-audio FFI · input
  monitoring UI.
- [ ] **Join clips as Commands** (fixes C37/C50) → **normalize** → **UI batches 5–8** per plan.

**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
