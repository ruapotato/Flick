#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1

mkdir -p ~/.local/state/flick

qmlscene "$SCRIPT_DIR/main.qml"
