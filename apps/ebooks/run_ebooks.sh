#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

# QtWebEngine settings
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--enable-gpu-rasterization --enable-native-gpu-memory-buffers --enable-features=OverlayScrollbar --force-dark-mode --use-gl=egl"

mkdir -p ~/.local/state/flick ~/Books

# Function to extract an epub
extract_epub() {
    local epub="$1"
    if [ -f "$epub" ]; then
        local BOOK_HASH=$(echo "$epub" | md5sum | cut -d' ' -f1)
        local JSON_FILE="/tmp/flick_epub_${BOOK_HASH}.json"
        # Extract if JSON missing or epub is newer
        if [ ! -f "$JSON_FILE" ] || [ "$epub" -nt "$JSON_FILE" ]; then
            "$SCRIPT_DIR/epub_helper.sh" extract "$epub" > "$JSON_FILE" 2>/dev/null
        fi
    fi
}

# Pre-extract all existing EPUBs
for dir in ~/Books ~/Documents ~/Downloads; do
    if [ -d "$dir" ]; then
        shopt -s nullglob
        for epub in "$dir"/*.epub "$dir"/*.EPUB; do
            extract_epub "$epub"
        done
        shopt -u nullglob
    fi
done

# Background watcher for new EPUBs (polls every 2 seconds)
(
    while true; do
        sleep 2
        for dir in ~/Books ~/Documents ~/Downloads; do
            if [ -d "$dir" ]; then
                shopt -s nullglob
                for epub in "$dir"/*.epub "$dir"/*.EPUB; do
                    extract_epub "$epub"
                done
                shopt -u nullglob
            fi
        done
    done
) &
WATCHER_PID=$!
trap "kill $WATCHER_PID 2>/dev/null" EXIT

qmlscene "$SCRIPT_DIR/main.qml"
