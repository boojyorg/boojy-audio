# Boojy Audio — Dreams

## §1 Active Engineering Target

**Target:** v0.3.x — **trust/correctness hardening**. The 2026-05-29 whole-app review
(`docs/reviews/codebase_review_2026_05_29.md`) picked this theme from real friction in code, so the
dogfood beat isn't a prerequisite. Implement the ranked backlog there, leading with the
**"don't lose my work, don't corrupt my edits"** cluster. v0.3.0 shipped 2026-05-25. The full
22-item backlog + the secondary "plugins & the audio thread" cluster live in the review doc.

### Milestones — primary cluster first (review §8); all are *fixes, no new features*
- [x] #2 Fix offline-export pan matrix — every bounce currently folds to mono (`offline.rs:380-386`) — **S** — shipped v0.3.1 (PR #11)
- [x] #3 Fix stale-id-on-redo across all Remove commands — effects/returns/clips (`effect_commands.dart`, `send_commands.dart`, `clip_commands.dart`) — **M** — shipped v0.3.1 (PR #11)
- [x] #4 Persist time signature + recorded MIDI CC on save/reload (`project.rs`) — **M** — shipped v0.3.1 (PR #11)
- [x] #5 Persist MIDI clip metadata via `ui_layout.json` — name/colour/offset/loop/automation (`midi_playback_manager.dart`, `project_persistence.dart`) — **M** — shipped v0.3.1 (PR #11)
- [x] #9 Group multi-clip moves into one undo + make overlap-move undoable (`timeline_gesture_layer.dart`) — **M** — group-move v0.3.1 (PR #11); overlap-move undo (H-11) v0.3.2 (PR #15)
- [x] #19 Add the regression tests that protect the above — save/reload fidelity, `send_commands`, execute→undo→execute — **L** — shipped v0.3.1 (PR #11)
- [ ] Write `docs/plans/v0.3.x-plan.md` once the slice is locked (one active plan at a time) — *skipped by design: work ran straight off the review doc*

Secondary cluster: #1 VST3 per-buffer processing **shipped v0.3.2 (PR #14)**; #10/#11/#20 still open.
With the primary cluster + #1 merged, the v0.3.x trust/correctness target is essentially delivered —
**next session: pick a fresh target** (dogfood for friction, or take #10/#11/#20).
**Trap for the UI items (#3/#5/#9):** `daw_screen.dart` wires PRIVATE `_` copies of its mixins — the
mixins are dead/diverged, so edit the wired private methods, *not* the mixins (review §4, backlog #7/#8).

### How we work here
- Plan **one milestone at a time** — only one active `docs/plans/vX.Y-plan.md`.
- After each release: **dogfood** on a real project, then pick the next theme from friction.
  `docs/ROADMAP.md` + `docs/FEATURE_TRACKER.md` are backlog, not a pre-scheduled ladder.
- **Design decisions (UI/UX)** before locking implementation:
  1. Brainstorm with Tyr — tradeoffs first (UX, then implementation). Ask; don't dictate.
  2. ASCII mockups — 3–4 variants when layout is ambiguous; Tyr picks before code.
  3. Defer on taste, push back on architecture — one clear preference, then collaborate.

<!-- §1 only by design. git log is the history; Claude Code auto memory holds incidental learnings.
     No incident log, no backlog, no session ledger. -->
