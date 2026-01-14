#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/calculator.log"

mkdir -p "$STATE_DIR"
echo "=== Flick Calculator started at $(date) ===" >> "$LOG_FILE"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1

exec /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
