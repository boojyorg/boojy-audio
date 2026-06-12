# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** **scope v0.7 via the review chain.** v0.6.0 RELEASED 2026-06-11 (appcast signature
verified bare base64 in the wild). Review-doc rename shipped (PR #97 — date-first
`YYYY_MM_DD_<topic>.md`, convention now in CLAUDE.md).

**Status (2026-06-11):** Tyr's big dogfood pass on v0.6.0 is captured + fact-checked in
**`docs/reviews/2026_06_11_dogfood_notes.md`** (UNCOMMITTED, on disk — Tyr may extend; commit
with the review reports). Read it first — it holds the bug list (MIDI hot-plug index-staleness,
zoom, note-resize, add-FX [+] popup, editor overflow, off-palette default colors, Windows
updater unwired), the design directions (black value chips, device chrome, action-role
Quantize, hover/motion spec awaiting Tyr's approval), v0.7 candidates (Capture MIDI, legato,
EQ spectrum, reverb, sampler fix), and the strategy calls (Linux/web OUT of v0.7, i18n → v1.0).
Mockups shown 2026-06-11; Tyr owes a dropdown-style pick (quiet-text / pill / filled-chip —
recommended filled-chip).

Review chain (2026-06-12) — DONE, three reports in `docs/reviews/2026_06_12_*`:

- [x] Tyr retook the screenshots on installed v0.6.0 (12 staged; archived to
  `docs/screenshots/v0.6.0/` — new per-release convention)
- [x] `ui-ux-review` → **B−**, proposes v0.7 = **"Devices & Feel"** (theme-token finish,
  onDoubleTap footguns, mixer legibility, one device shell)
- [x] `feature-gap-review` → proposes v0.7 = **"First Sound"** (thin synth presets, effect
  patches, Capture-MIDI wiring B4 ~5min, guided first song; "Feel & Fidelity" = right SECOND
  cycle). (codebase-review deliberately SKIPPED — ran 2026-06-05, too recent)
- [x] BONUS: custom `eng-health-review` (CI/testing/release health) → **B**; hardening =
  background track not theme; guardrails EH-2..5/EH-9 = half-day inside v0.7; artifact purge
  EH-12 before v1.0
- [x] **Sparkle spot-check** → FOUND THE REAL BUG: appcast carried semver in `sparkle:version`
  but Sparkle compares build numbers (9 vs "0.6.0" → "up to date"). Fixed + hot-fixed published
  appcast in **PR #98 (merged)**. Awaiting Tyr's retest: v0.5.4 should now offer 0.6.0.
- [ ] **Triage together** → `docs/plans/v0.7-plan.md`. The decision: reconcile "Devices & Feel"
  (ui-ux) vs **"First Sound"** (feature-gap) — they agree on the device-shell/presets overlap;
  feature-gap argues First Sound closes the beginner-acquisition wall first.
- [ ] Housekeeping: staged `_screenshots/*.png` deleted (archived) ✓; still owed: prune unused
  brand-source PNGs from `ui/assets/images/` (boojy-logo, boojy_audio_app_udio,
  boojy_audio_app_triangle_A, boojy_audio_text, boojy_audio_text_Audio — app uses the derived
  `*_text_black/white.png`; keep boojy_audio_audi.svg per the standing note); decide whether
  `docs/screenshots/social-preview.png` gets committed or gitignored (EH-17).


**Carried decisions:** ASIO deferred (WASAPI right for beginners). Windows machine = per-release
test rig, not a dev machine. No stock instruments in v0.6 (triage). Loop region is orange, not
gold.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
