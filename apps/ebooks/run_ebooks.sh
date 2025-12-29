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

# Pre-extract all EPUBs on launch for faster opening
for dir in ~/Books ~/Documents ~/Downloads; do
    if [ -d "$dir" ]; then
        for epub in "$dir"/*.epub "$dir"/*.EPUB 2>/dev/null; do
            if [ -f "$epub" ]; then
                BOOK_HASH=$(echo "$epub" | md5sum | cut -d' ' -f1)
                JSON_FILE="/tmp/flick_epub_${BOOK_HASH}.json"
                if [ ! -f "$JSON_FILE" ]; then
                    echo "Pre-extracting: $(basename "$epub")"
                    "$SCRIPT_DIR/epub_helper.sh" extract "$epub" > "$JSON_FILE" 2>/dev/null
                fi
            fi
        done
    fi
done

qmlscene "$SCRIPT_DIR/main.qml"
