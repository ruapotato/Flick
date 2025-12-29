#!/bin/bash
# Flick Web - Mobile web browser for Flick shell

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/home/droidian/.local/state/flick"
LOG_FILE="${STATE_DIR}/web.log"

mkdir -p "$STATE_DIR"
mkdir -p "/home/droidian/Downloads"

echo "=== Flick Web started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# QtWebEngine settings for Droidian/hwcomposer
export QTWEBENGINE_DISABLE_SANDBOX=1
# Enable GPU acceleration for web content
export QTWEBENGINE_CHROMIUM_FLAGS="--enable-gpu-rasterization --enable-native-gpu-memory-buffers --enable-features=OverlayScrollbar --force-dark-mode --use-gl=egl"

# Hardware acceleration enabled for both Qt Quick and WebEngine
# export QT_QUICK_BACKEND=software  # Commented out = hardware accel

# Allow XHR file reads for config loading
export QML_XHR_ALLOW_FILE_READ=1

# WebEngine cache and data directories
export QTWEBENGINE_DICTIONARIES_PATH="$STATE_DIR/webengine/dictionaries"
mkdir -p "$STATE_DIR/webengine"

# Run the browser (pass any URL argument)
exec qmlscene "$SCRIPT_DIR/main.qml" "$@" 2>> "$LOG_FILE"
