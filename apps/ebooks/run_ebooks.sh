#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

mkdir -p ~/.local/state/flick ~/Books

# Extract all EPUBs to txt on launch
for dir in ~/Books ~/Documents ~/Downloads; do
    if [ -d "$dir" ]; then
        shopt -s nullglob
        for epub in "$dir"/*.epub "$dir"/*.EPUB; do
            "$SCRIPT_DIR/extract_epub.sh" "$epub"
        done
        shopt -u nullglob
    fi
done

qmlscene "$SCRIPT_DIR/main.qml"
