#!/usr/bin/env bash
# post-edit-validation.sh — gate-only PostToolUse hook (Edit|Write|MultiEdit).
#
# Reads the edited file path from stdin JSON and runs a FAST compile/analyze gate
# for that file type:
#   *.rs   under engine/ -> cargo check, then cargo clippy   (from engine/)
#   *.dart under ui/     -> fvm flutter analyze (or flutter analyze)  (from ui/)
#   anything else        -> no-op
#
# It is a GATE ONLY: it never writes into the repo tree and never touches dreams.md.
# Full test suites (cargo test / flutter test) are intentionally NOT run here — too
# slow for the per-edit loop; those stay manual / CI.
#
# Exit codes: 0 = pass or graceful skip (toolchain absent); non-zero = gate failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- extract the edited file path (tool_input.file_path) from stdin JSON ---
input="$(cat)"
file_path=""
if command -v python3 >/dev/null 2>&1; then
  file_path="$(printf '%s' "$input" | python3 -c 'import sys, json
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")' 2>/dev/null)"
fi
if [ -z "$file_path" ]; then
  # grep/sed fallback if python3 is unavailable or parsing failed
  file_path="$(printf '%s' "$input" \
    | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 \
    | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//')"
fi

[ -z "$file_path" ] && exit 0

# Run a gate command in $1 (working dir). Captures output to a temp file (mktemp,
# never inside the repo); on failure prints it to stderr and propagates the code.
run_gate() {
  local dir="$1"; shift
  local tmp rc
  tmp="$(mktemp)"
  ( cd "$dir" && "$@" ) >"$tmp" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "post-edit-validation: gate failed -> $* (in $dir)" >&2
    cat "$tmp" >&2
  fi
  rm -f "$tmp"
  return "$rc"
}

case "$file_path" in
  *engine/*.rs)
    command -v cargo >/dev/null 2>&1 || exit 0   # graceful skip: no Rust toolchain
    run_gate "$ROOT/engine" cargo check || exit 1
    run_gate "$ROOT/engine" cargo clippy || exit 1
    exit 0
    ;;
  *ui/*.dart)
    if command -v fvm >/dev/null 2>&1; then
      run_gate "$ROOT/ui" fvm flutter analyze || exit 1
    elif command -v flutter >/dev/null 2>&1; then
      run_gate "$ROOT/ui" flutter analyze || exit 1
    fi
    exit 0   # graceful skip if neither fvm nor flutter is on PATH
    ;;
  *)
    exit 0   # no gate for other file types
    ;;
esac
