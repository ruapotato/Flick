#!/bin/bash
# Flick Store - App store for Flick shell
# Browse, download and install .flick packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support running from any user - default to droidian
STATE_DIR=Theme.stateDir + ""
LOG_FILE="${STATE_DIR}/store.log"

mkdir -p "$STATE_DIR"
mkdir -p "$STATE_DIR/store_cache"

echo "=== Flick Store started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Uncomment for software rendering

# Run the store app
exec qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
