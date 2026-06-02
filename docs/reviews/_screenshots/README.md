# Review screenshots (staging area)

Drop current-build screenshots here **before** running the `ui-ux-review` workflow.

## Why this folder exists

The `ui-ux-review` workflow grounds its subagents on screenshots of the running app. Two earlier
bugs made that grounding silently fail (review finding, 2026-06-01):

1. **Named-workflow `args` get dropped** — passing `args.screenshots` to a *named* workflow doesn't
   reliably reach the script.
2. **The pasted-image cache is ephemeral** — screenshots pasted into the chat live under
   `~/.claude/image-cache/`, which is **purged mid-run**, so the paths in the prompt point at files
   that no longer exist by the time a subagent tries to read them.

The fix: stage screenshots as **committed repo files** here. The workflow's subagents (which have
`Glob`/`Read`) are told to look in `docs/reviews/_screenshots/` for `*.png` — a stable path that
survives both failure modes, independent of `args`.

## How to use

1. Capture the current UI (whole-window screenshots of the areas under review — top bar, piano roll,
   timeline, mixer, effects, settings, start screen).
2. Save them here as `*.png` with descriptive names (e.g. `piano-roll.png`, `mixer.png`).
3. Run the review: `Workflow({ name: 'ui-ux-review' })`.
4. After the review, you can delete the PNGs (keep this README) — they're staging input, not history.
   Milestone/release screenshots belong in `docs/screenshots/`, not here.
