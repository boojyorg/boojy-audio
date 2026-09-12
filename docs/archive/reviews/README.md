# Archived reviews

Dated evidence from past review cycles. **Not current instructions, schedules, or open work.**
Every accepted decision and still-open item from these reports was carried into
[`docs/BACKLOG.md`](../../BACKLOG.md) before archiving; read that first.

A review's durable output is the triage that followed it. Once a triage exists, the raw reports
it consumed belong here — see the retire rule in `AGENTS.md` → **Milestone Reviews**.

## What each cycle produced

| Cycle | Reports | Where its decisions landed |
| --- | --- | --- |
| 2026-03-26 / 03-29 | `2026_03_26_ui_review`, `2026_03_29_ui_review` | Early UI/UX reads of v0.1.6 / v0.1.8 against Ableton, Logic, GarageBand. Fed the v0.2.x polish work. |
| 2026-05-22 / 05-24 | `2026_05_22_codebase_review`, `2026_05_24_codebase_review` (delta) | Pre-v0.3 scoped audits → the v0.2.3 "Foundation & consolidation" plan and v0.3.0 send/return. |
| 2026-05-29 | `2026_05_29_codebase_review` | Whole-app audit of v0.3.0 → set the **v0.3.x trust/correctness** theme. |
| 2026-05-30 | `2026_05_30_ui_ux_review` | 48-bug ledger + 4-DAW read of v0.3.2 → set the **v0.4 visual-polish** theme. |
| 2026-06-01 | `2026_06_01_codebase_review`, `2026_06_01_ui_ux_review`, `2026_06_01_feature_gap_review` | Triaged by `2026_06_01_v0.4.0_pre_release_triage` → cleared the v0.4.0 tag and chose the v0.5 theme. |
| 2026-06-05 | `2026_06_05_codebase_review`, `2026_06_05_ui_ux_review`, `2026_06_05_feature_gap_review`, `2026_06_05_dogfood_notes` | Triaged by `2026_06_05_triage` → the v0.5.2 correctness cycle and the v0.6 "Sound" theme. |
| 2026-06-07 | `2026_06_07_tool_state_research` | Seven-DAW survey of arrangement tool state. Outcome: no extra canvas tool badge — toolbar selection and cursor carry the mode (recorded in BACKLOG's preserved decisions). |
| 2026-06-09 / 06-10 | `2026_06_09_dogfood`, `2026_06_10_bug_hunt`, `2026_06_10_design_recs` | The v0.6 pre-tag pass. Dogfood items all fixed in-session; the bug hunt's six must-fix items were fixed before v0.6.0 shipped 2026-06-11. **Its lower-tier ledger was never itemised in a triage** — treat as unverified candidates, not open bugs. |
| 2026-06-11 / 06-12 | `2026_06_11_dogfood_notes`, `2026_06_12_ui_ux_review`, `2026_06_12_feature_gap_review`, `2026_06_12_eng_health_review` | Triaged by [`docs/reviews/2026_06_12_triage.md`](../../reviews/2026_06_12_triage.md), which is still live — it preserves the T/N/X/P/L/M/E/C, EH and A–D item IDs the backlog refers to. |
| 2026-06-16 | `2026_06_16_dropdown_menu_audit` | 83-site migration plan for one shared filled-chip dropdown + context-menu surface. Shipped (see Unreleased); residual `showMenu`/`PopupMenuButton` sites are tracked in BACKLOG. |

## Reading these

- They describe builds that no longer exist. A finding here is **not** evidence of a current bug.
- Where a report and its triage disagree, the triage won — that was the point of the triage.
- Several contain known errors their own triage corrected (mislabelled IDs, a failed
  screenshot-grounding pass, stale brief wording). The triage notes these; the reports do not.
- Some internal links point at planning docs that were retired in the 2026-09 consolidation.
  They are left as written rather than rewritten, because these are dated records.
