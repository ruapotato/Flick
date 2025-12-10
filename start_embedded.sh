#!/bin/bash
# Start Flick in embedded/windowed mode for development, demos, and recording
# Run this from within an existing X11 or Wayland session

set -e

cd "$(dirname "$0")"

# Default to smaller size that fits most screens
SIZE="${1:-540x1080}"
SCALE="${2:-1.0}"

echo "Building Flick..."
cd shell
cargo build --release 2>&1 | tail -5

echo ""
echo "Starting Flick in windowed mode (size: $SIZE, scale: $SCALE)"
echo "Mouse clicks simulate touch. Click and drag to perform gestures:"
echo "  - Drag from left edge -> Quick Settings"
echo "  - Drag from right edge -> App Switcher"
echo "  - Drag from top edge -> Close app"
echo "  - Drag from bottom edge -> Home / Show keyboard"
echo ""

./target/release/flick --windowed --size "$SIZE" --scale "$SCALE"
