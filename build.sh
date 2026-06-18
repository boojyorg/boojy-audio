#!/bin/bash
# Usage:
#   ./build.sh          # Debug build (fast incremental)
#   ./build.sh release  # Release build (optimized)

set -e

# This script builds a macOS dylib — abort early on other platforms.
if [ "$(uname)" != "Darwin" ]; then
  echo "build.sh: macOS only (got $(uname)). Use the Xcode run script on macOS or CI on other platforms." >&2
  exit 1
fi

cd "$(dirname "$0")/engine"

# Use sccache if available (speeds up rebuilds)
if command -v sccache &> /dev/null; then
  export RUSTC_WRAPPER=sccache
fi

MODE="${1:-debug}"

if [ "$MODE" = "release" ]; then
  echo "Building engine (release)..."
  cargo build --release
  SRC="target/release/libengine.dylib"
else
  echo "Building engine (debug)..."
  cargo build
  SRC="target/debug/libengine.dylib"
fi

# Update symlink to point to correct build
ln -sf "../../../engine/$SRC" ../ui/macos/Runner/libengine.dylib

# Copy to locations that need actual files
cp "$SRC" ../ui/macos/libengine.dylib
cp "$SRC" ../ui/macos/Frameworks/libengine.dylib

echo "Done. Dylib installed from $SRC"
