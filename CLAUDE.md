# Claude Code Instructions

## Changelog Workflow

When making bug fixes or feature changes:
1. Update `CHANGELOG.md` immediately after each fix
2. Add entries under the "Unreleased" section at the top
3. Use categories: `### Bug Fixes`, `### Features`, `### Improvements`
4. When releasing, change "Unreleased" to the version number and date

## Project Structure

- `engine/` - Rust audio engine (builds to libengine.dylib)
- `ui/` - Flutter frontend
- `ui/macos/` - macOS-specific native code (Swift)
- `ui/lib/` - Dart application code

## Release Process

1. Update CHANGELOG.md with release date
2. Commit all changes
3. Tag with version: `git tag v0.x.x && git push origin v0.x.x`
4. GitHub Actions builds and creates draft release
5. Edit release notes in GitHub, then publish

## Code Signing Secrets (GitHub)

- `MACOS_CERTIFICATE` - Base64-encoded .p12 file (use `-legacy` flag when exporting)
- `MACOS_CERTIFICATE_PWD` - Password for the .p12
- `DEVELOPER_ID` - Full signing identity name
- `APPLE_APP_PASSWORD` - App-specific password from appleid.apple.com
