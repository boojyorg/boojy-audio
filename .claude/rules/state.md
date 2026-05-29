---
paths:
  - ui/lib/**/*.dart
---

# UI state management

UI state is **`provider`** today — used lightly, in ~9 files (`main.dart`, `daw_screen.dart`,
`theme_extension.dart`, a handful of widgets/dialogs). Most state is passed via services/controllers
rather than a deep provider tree.

**Riverpod** (same author, supersedes `provider`) is the scalable target **if** state management
starts to hurt. Because ~9 files already lean on `provider` patterns, this is a deliberate future
migration, not a drop-in swap — don't start it casually. (Mirrors the web stack's
Zustand-over-context choice: pick the scalable tool deliberately, migrate when the pain is real.)

For logging in UI code use `Log.d()` / `Log.e()` / `Log.i()` (from `utils/logger.dart`), not
`print()`.
