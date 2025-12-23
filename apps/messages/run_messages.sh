#!/bin/bash
# Flick Messages - Messages app placeholder for Flick shell

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/home/droidian/.local/state/flick"
LOG_FILE="${STATE_DIR}/messages.log"

mkdir -p "$STATE_DIR"

echo "=== Flick Messages started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

# Run the app
exec qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
