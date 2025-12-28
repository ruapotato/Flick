#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p ~/.local/state/flick

# Use QML version (Rust/SDL2 has Wayland issues on this platform)
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
exec qmlscene "$SCRIPT_DIR/main.qml"
