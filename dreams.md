# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **ship v0.6.1 (patch), then v0.7 "Devices & Feel".** Triage DONE 2026-06-12 →
**`docs/reviews/2026_06_12_triage.md`** is the canonical per-item disposition of the three
06-12 reviews + dogfood notes; **`docs/plans/v0.7-plan.md`** is the active plan. Updater fix
(PR #98) live-verified: v0.5.4 offered 0.6.0 and updated — Sparkle works end-to-end.

Sequence:

- [ ] **v0.6.1 bug-fix patch** (branch off origin/master): A4 piano-roll resize-vs-move ·
  A5 add-FX [+] popup position (repro first; punt to v0.7 if deep) · A8 default track colors
  only from the 16 `manualPalette` · A9 wordmark click → Start screen (Settings via gear; keep
  red-triangle health) · A10 library cursor/hover. Release = the first live auto-update
  delivery test (v0.6.0 installs should be OFFERED 0.6.1).
- [ ] **EH-12 repo purge** — standalone session right after v0.6.1 ships (Tyr's call at
  triage): `git rm --cached` iOS `.a` libs + `build_win/` tree, gitignore, git-filter-repo,
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
