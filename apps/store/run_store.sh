#!/bin/bash
# Flick Store - App store for Flick shell
# Browse, download and install .flick packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support running from any user - default to droidian
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/store.log"

mkdir -p "$STATE_DIR"
mkdir -p "$STATE_DIR/store_cache"

echo "=== Flick Store started at $(date) ===" >> "$LOG_FILE"

# Start install server if not already running
if ! pgrep -f "install_server.py" > /dev/null; then
    python3 "$SCRIPT_DIR/install_server.py" >> "$LOG_FILE" 2>&1 &
    sleep 0.5
fi

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Allow file read/write for local config
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Uncomment for software rendering

# Run the store app
exec qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
