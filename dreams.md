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
- [x] **EH-12 repo purge** — DONE 2026-06-12: iOS `.a` libs + `build_win/` tree (+ historical
  `ui/assets/libengine.dylib`) stripped from all history via git-filter-repo; all 50 branches +
  21 tags rewritten & force-pushed; releases/assets intact; fresh clone 31 MB → 15 MB. Backup
  mirror at `../boojy-audio-pre-eh12-backup.git` (delete once confident).
- [x] **Slice 1 Trust** — DONE 2026-06-12 (PR #106, walkthrough ×3): Light-theme tokens
  (T1–T6, T8/L7 full-required, T9, P4, L4, N7 + arrangement canvas on Light) + footguns
  (X1/X2/M1) + EH-11 tests + Cmd+Shift+T wired + loop-tracks-tempo fix (engine set_tempo
  already re-anchors the playhead — rule in `.claude/rules/ffi.md`).
- [x] **v0.7 slices 1–4 Batch 1+2 + Riders + Guardrails — ALL MERGED 2026-06-18.**
  - Riders (PR #120): Capture MIDI button (modifiers well, crop_free glyph, press-flash);
    Audio Cmd+D for audio clips; Legato (next-in-time logic, whole-clip fallback, press-flash);
    Velocity toggle (full label). CC toggle deferred.
  - Guardrails (PR #121): rust-toolchain.toml → stable; 6 truly-unreferenced brand PNGs pruned;
    AGENTS.md lint-count corrected; CI gates EH-1/2b/3a/3b/5 added.
  - MIDI hot-plug (PR #122): 500ms background poll + 800ms debounce; Refresh button now opens port.
- [ ] **v0.7 remaining** (gates the end-of-cycle review):
  - A7/D6 sampler fix package — **gated on Tyr's C2 research**
  - A11/D7 Windows updater toggle
- [ ] **Tyr owes:** EH-9 branch-protection click · sampler research (C2) · zoom spec (C1).
- [ ] **End of cycle:** rerun codebase-review (decided — not before; trigger once remaining items done).


**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
