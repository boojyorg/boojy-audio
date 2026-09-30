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

## The release gate

A release ships when its scorecard rows (`docs/BACKLOG.md`) reach 8 and nothing blocks.

### Severity rule

- **Blocks release:** known data loss, or a core workflow (record, arrange, edit, mix, save and
  reopen, export) that does not complete.
- **Fix before release:** visible and cheap enough to do now, but the release could ship without it.
- **After release:** improvements and polish; they wait for a patch. Noticing something during the
  gate doesn't make it a blocker.

### Process

1. Known bugs go in BACKLOG, classified by the rule above.
2. Each fix is one PR: a failing test that reproduces it, the fix, CI green, Tyr's walkthrough,
   merge. The fix goes under Unreleased in the changelog.
3. Tyr dogfoods builds that already passed the suites; new findings go in BACKLOG.
4. Re-score the release's rows. Release when they're at 8, nothing blocks, and the checks below
   pass.

### Release-day checks

- **Sparkle offers the update:** install the previous release on a Mac, launch, expect the offer.
  (The v0.6.0 appcast fix has never been seen working.)
- **"Check for updates automatically" sticks** on macOS: Sparkle persists it, not the app. Toggle
  it, relaunch, confirm.
- **Windows hides the Updates section** (no native updater yet), plus the smoke test below.
- **EDITING.md's "plan, not current app" box** comes out once the editing model ships.

## What the release workflow does

Pushing a `v*` tag runs `.github/workflows/release.yml`:

- **macOS:** builds the app, signs every framework and dylib and then the app with the Developer
  ID certificate (hardened runtime), builds the DMG, signs and **notarizes** it with `notarytool`,
  and **staples** the ticket, so Gatekeeper opens it without a warning. Each step skips quietly if
  its secrets are missing (`MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`, `KEYCHAIN_PWD`,
  `DEVELOPER_ID`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`), so check the run log for
  "skipped" before publishing. The per-file signing loop ends in `|| true`: a file that fails to
  sign doesn't fail the job, so `codesign --verify` on the app is the real check.
- **Auto-update (macOS only):** the DMG gets a Sparkle EdDSA signature (`SPARKLE_PRIVATE_KEY`),
  and the job writes `appcast.xml` and commits it to `master`. Installed apps read the feed from
  `raw.githubusercontent.com/boojyorg/boojy-audio/master/appcast.xml` (`SUFeedURL` in
  `ui/macos/Runner/Info.plist`), so **an update is only offered once that commit lands**.
  ⚠️ `master` has been protected since 2026-09-13, and the workflow's direct `git push` to it will
  be rejected: fix this before tagging v0.7.0 (see `docs/BACKLOG.md`).
- **Windows:** builds the app, bundles the MSVC runtime DLLs and packs an Inno Setup installer.
  The installer is **not code-signed**, so Windows SmartScreen warns on first run. There is no
  Windows auto-updater.
- **Release:** both builds upload to a **draft** GitHub release with stable names
  (`Boojy-Audio-mac.dmg`, `Boojy-Audio-win.exe`). Publishing the draft is manual; publishing
  fires `site-rebuild.yml`, which rebuilds boojy.org and then checks that the Audio page shows the
  new version, failing the run if it doesn't.

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
3. Delete a report once every ID BACKLOG cites from it is either described in BACKLOG or
   dropped on purpose. Git history keeps it.

`docs/reviews/` holds only reports that BACKLOG still points at. Never reopen an item from an old
report without re-verifying it against today's code.
