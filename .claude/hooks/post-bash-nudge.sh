#!/usr/bin/env bash
# post-bash-nudge.sh — PostToolUse hook (Bash matcher), advisory only.
#
# After a build/test command, reminds Claude to keep the docs honest: update
# CLAUDE.md / the relevant .claude/rules/ file / README.md if structure or
# architecture shifted. Never blocks — always exits 0.
set -uo pipefail

input="$(cat)"

# Pull the command string out of the tool input (python3, then grep fallback).
cmd=""
if command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | python3 -c 'import sys, json
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    print("")' 2>/dev/null)"
fi
if [ -z "$cmd" ]; then
  cmd="$(printf '%s' "$input" \
    | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"$//')"
fi

# Only nudge after build/test commands.
case "$cmd" in
  *build.sh*|*"cargo build"*|*"cargo test"*|*"cargo check"*|*"flutter build"*|*"flutter test"*|*"flutter run"*)
    msg="If this build/test revealed that structure or architecture shifted, update CLAUDE.md, the relevant .claude/rules/ file, and/or README.md to match."
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' "$msg"
    else
      echo "$msg"
    fi
    ;;
esac
exit 0
