# Boojy Audio — Dreams

> Live working memory: the Active Engineering Target only (this week's target). Slow-changing rules
> live in `CLAUDE.md` + `.claude/rules/`; ordered intentions + version table → `docs/ROADMAP.md`;
> unscheduled tasks → `docs/BACKLOG.md`; per-feature status → `docs/FEATURE_TRACKER.md`; history →
> `git log` + auto memory. This file is volatile state only — safe to wipe each milestone.

## §1 Active Engineering Target

**Target:** Make Windows a first-class platform, then resume **v0.6 — "Sound"**.

**Status (2026-06-06):** v0.5.2 → v0.5.4 all shipped the same day. Windows turned out to be
doubly broken since the first release — the installer never bundled `engine.dll` (fixed v0.5.3,
PR #60, + new app icon + VC++ runtime + smoke-test checklist in `CLAUDE.md` Release section) and
every file dialog was macOS AppleScript, so Save As / Open / Export all failed with an OS error
(fixed v0.5.4, PR #62 → `ui/lib/utils/native_dialogs.dart`; `$HOME` → `USERPROFILE` for the
default projects folder). First-launch tour auto-start removed in #62 (kept under Help → Take a
Tour). v0.5.4 release build was in-flight when the session ended.

### Milestones
- [ ] **Publish v0.5.4 draft release** (Tyr) — edit notes from CHANGELOG, publish.
- [ ] **Windows smoke test, round 2** (Tyr, on the Windows machine): the 5 CLAUDE.md steps
  **plus** Save As (native dialog, defaults to `Documents\Boojy\Audio\Projects`), Open Project
  round-trip, Export WAV. If engine-side file copying fails despite the dialog working, next
  suspects are path handling in Rust `save_project` / `project_manager_native` — never exercised
  on Windows before.
- [ ] **macOS regression spot-check** (Tyr, 2 min): Save As / Export dialogs look identical
  (same AppleScript branch); Sparkle auto-update offers v0.5.3/v0.5.4 (live test of the appcast
  signature fix — verified bare base64 on the feed already).
- [ ] **Triage round-2 findings** → either a small v0.5.5 fix list or, if clean, reopen
  **v0.6 "Sound"** (PR3 starter kit: 1 kit / 8 sounds — see `docs/ROADMAP.md` + the v0.6 plan
  memory; drum-kit engine #44 + editor #45 already merged).

**Carried decisions:** ASIO deliberately deferred (`docs/BACKLOG.md` — WASAPI is the right
beginner default). Tyr stays on macOS for development; the Windows machine is a per-release test
rig, not a dev machine.

---

*(v0.5.2 correctness-cycle checklist — complete, all 8 phases + tag shipped — wiped per the
volatile-state rule; full detail in `git log`, `docs/archive/plans/v0.5.2-plan.md`, and the
`v0-5-progress` auto-memory.)*
