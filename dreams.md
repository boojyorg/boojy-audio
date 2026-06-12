# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **v0.7.0 "Devices & Feel".** Triage DONE 2026-06-12 →
**`docs/reviews/2026_06_12_triage.md`** is the canonical per-item disposition of the three
06-12 reviews + dogfood notes; **`docs/plans/v0.7-plan.md`** is the active plan. Updater fix
(PR #98) live-verified: v0.5.4 offered 0.6.0 and updated — Sparkle works end-to-end.

Sequence:

- [x] **v0.6.1 fixes** (PR #101, walkthrough passed ×2, CI green): A4 resize-vs-move (+
  edge-drag hit-test) · A5 add-FX popup anchor · A8 palette-only defaults (+ red/blue/yellow
  swatch tuning; Master = Boojy Blue, now pickable) · A9 wordmark → Start screen · A10 library
  hover. **The v0.6.1 release itself is SKIPPED** (Tyr, 2026-06-12) — the fixes ride v0.7.0;
  the v0.6.0→next update-offer check happens at the v0.7.0 tag instead.
- [ ] **EH-12 repo purge** — standalone session, do FIRST before v0.7 branches pile up:
  `git rm --cached` iOS `.a` libs + `build_win/` tree, gitignore, git-filter-repo,
  force-push, reclone check. ~68 MB.
- [ ] **v0.7 slices** per the plan: 1 Trust (Light-theme token finish + X1/X2/M1 footguns) →
  2 Legibility (mixer cues + piano-roll lanes + BoojyTooltip) → 3 Feel chrome (filled-chip
  dropdowns/menus, settings unify, overflow) → 4 Devices (shared shell, sampler package, MIDI
  hot-plug by name, Windows updater). Riders: Capture MIDI, audio Cmd+D, Legato, CC-lane
  toggle, swing/ghost-notes keep-or-hide. Guardrails half-day: EH-2..5/EH-15/EH-1-grep/EH-17.
- [ ] **Tyr owes (gates v0.7 slices):** zoom spec session (C1 — then A2/A3) · sampler research
  (C2) · hover/motion spec sign-off (B7) + B9 overflow pick · EH-9 branch-protection click.
- [ ] Housekeeping (in EH-17 batch): prune unused brand-source PNGs from `ui/assets/images/`
  (keep boojy_audio_audi.svg per standing note); `social-preview.png` commit-or-gitignore.
- [ ] **End of cycle:** rerun codebase-review to measure (decided — not before).


**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
