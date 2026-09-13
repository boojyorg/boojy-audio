# Releasing Boojy Audio

The suite-wide skeleton (changelog workflow, branch discipline, tag-and-push) is in the suite
root `AGENTS.md`. This file is the boojy-audio specifics.

## Version sync

`ui/pubspec.yaml` is the version source; it drives the in-app label via `PackageInfo` and is
the easiest step to forget. On every release:

1. Bump `ui/pubspec.yaml`.
2. `CHANGELOG.md`: rename `## Unreleased` to `## vX.Y.Z — YYYY-MM-DD`; add a fresh `## Unreleased`.
3. `README.md`: update the released version line.
4. `docs/BACKLOG.md`: remove shipped work and explicitly choose the next priority. A paused
   theme does not reactivate itself.
5. Suite root `README.md`: update the Audio row. Check the suite `VISION.md` for stale
   version references. (Both live outside this repository.)
6. Tag `vX.Y.Z` and push. GitHub Actions builds the draft release (DMG + EXE); edit and publish it.

Documentation cleanup never implies a release or a version bump.

## Windows smoke test (every release, before publishing the draft)

Development happens on macOS, so the installed Windows build is the one artifact nobody has run.
Install the freshly built `Boojy-Audio-win.exe` on the Windows machine (~5 min):

1. App launches; taskbar and title bar show the Boojy icon, not the Flutter default.
2. Audio devices are listed in Settings; the default output works (metronome or a clip plays).
3. Record a short MIDI clip with the built-in synth; it plays back.
4. A project saves and loads round-trip.
5. The in-app version label matches the tag.

v0.5.2 and earlier shipped without `engine.dll` because nothing exercised the installer. This
checklist exists so that class of bug is caught on day one. The Windows machine is a release
test rig, not a development machine.

## Milestone reviews

Each version's theme comes from a deliberate review, not guesswork. Reviews are human-triggered,
never scheduled: their value is in Tyr reading and triaging the output.

| Review | When | How |
| --- | --- | --- |
| UI/UX | every minor version | Stage current screenshots in `docs/reviews/_screenshots/` (see its README), then `Workflow({ name: 'ui-ux-review' })` |
| Codebase audit | major boundaries only (pre-1.0, once per minor family), gates green first | `Workflow({ name: 'codebase-review' })` (~$30–50 tiered) |
| Feature gap | when choosing a new feature theme, alongside the other two | `Workflow({ name: 'feature-gap-review' })` |

**Triage, then retire.** A review's durable output is the triage, not the report.

1. Run the review; save the report to `docs/reviews/` with a date-first name (`YYYY_MM_DD_topic.md`).
2. Triage it: accepted work and open items go to `docs/BACKLOG.md`; the triage doc records the
   per-item decisions and stays in `docs/reviews/`.
3. In the same PR, move the raw reports to `docs/archive/reviews/` and add a row to that
   folder's README saying where the cycle's decisions landed.

`docs/reviews/` normally holds just the current cycle. Never re-open an item from an archived
report without re-verifying it against today's code; those reports describe builds that no
longer exist.
