#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software

mkdir -p ~/.local/state/flick

qmlscene "$SCRIPT_DIR/main.qml"
