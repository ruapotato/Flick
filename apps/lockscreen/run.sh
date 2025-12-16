#!/bin/bash
# Run the Flick lockscreen QML app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${HOME}/.local/state/flick"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Run with Qt5 QML scene viewer
export QT_QPA_PLATFORM=wayland
exec /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" "$STATE_DIR"
