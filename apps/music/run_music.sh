#!/bin/bash
# Flick Music - First-party music player for Flick shell
# Reads text_scale from Flick settings

SCRIPT_DIR="$(dirname "$0")"
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/music.log"

# FlickBackend library path
FLICK_LIB_DIR="${SCRIPT_DIR}/../../lib"

mkdir -p "$STATE_DIR"

echo "=== Flick Music started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1

# Add FlickBackend library to QML import path
export QML2_IMPORT_PATH="${FLICK_LIB_DIR}:${QML2_IMPORT_PATH}"

# Run the music player
exec /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
