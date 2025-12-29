#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

# QtWebEngine settings
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--enable-gpu-rasterization --enable-native-gpu-memory-buffers --enable-features=OverlayScrollbar --force-dark-mode --use-gl=egl"

mkdir -p ~/.local/state/flick

# Background process to watch for epub extraction requests
(
    while true; do
        for cmd in /tmp/flick_epub_cmd_*.sh; do
            if [ -f "$cmd" ]; then
                chmod +x "$cmd"
                bash "$cmd"
                rm -f "$cmd"
            fi
        done
        sleep 0.1
    done
) &
WATCHER_PID=$!

# Cleanup on exit
trap "kill $WATCHER_PID 2>/dev/null" EXIT

qmlscene "$SCRIPT_DIR/main.qml"
