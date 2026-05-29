# Development Preferences

## Git Commits

**DO NOT** include "Generated with Claude Code" or similar attributions in commit messages.

Write professional commit messages that describe the changes without mentioning AI assistance.

## Building & Running

**DO NOT** run `flutter build` after making changes.

### Important: Rust Engine Build Mode

The Flutter app uses a **symlink** at `ui/macos/Runner/libengine.dylib` that points to:
```
engine/target/release/libengine.dylib
```

**After making Rust changes, you MUST build in release mode:**
```bash
cd engine
cargo build --release
```

Then the user will run:
```bash
cd ../ui
flutter clean
flutter run -d macos
```

**Note:** `cargo build` (debug mode) builds to `target/debug/` which Flutter won't pick up!

## Design Philosophy

Prefer simple, minimal implementations initially. Complexity can be added later when explicitly requested.

**Example:** The built-in synth uses:
- Single oscillator (sine/saw/square/triangle)
- One-pole lowpass filter
- ADSR envelope
- 8-voice polyphony

NOT: 3 oscillators + resonant filter + LFO + modulation matrix

## Documentation

- Update CHANGELOG.md under the "Unreleased" section for bug fixes and features
- Update README.md and ROADMAP.md for significant changes

## Testing

- Run `cargo build --release` after Rust changes (required for Flutter to pick up)
- No automatic test runs required unless explicitly asked

## Code Style

- Rust: use `println!` for debug logging during development
- Dart/Flutter: follow existing patterns in codebase
- Avoid over-engineering - only add features that are explicitly requested
