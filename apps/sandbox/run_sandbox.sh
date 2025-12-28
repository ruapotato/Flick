#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p ~/.local/state/flick

# Use native Rust SDL2 version if available
if [ -f "$SCRIPT_DIR/target/release/flick-sandbox" ]; then
    export SDL_VIDEODRIVER=wayland
    exec "$SCRIPT_DIR/target/release/flick-sandbox"
else
    # Fallback to QML version
    export QT_QPA_PLATFORM=wayland
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    exec qmlscene "$SCRIPT_DIR/main.qml"
fi
