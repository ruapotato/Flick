#!/bin/bash
# Flick Terminal - First-party terminal for Flick shell
# Reads text_scale from Flick settings

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Support running from any user - default to droidian
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/terminal.log"

mkdir -p "$STATE_DIR"

echo "=== Flick Terminal started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
# Enable text input protocol for virtual keyboard
export QT_IM_MODULE=textinputv3

# Force software rendering for hwcomposer compatibility
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Run the terminal
exec /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
