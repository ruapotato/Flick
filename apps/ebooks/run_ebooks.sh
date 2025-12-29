#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

mkdir -p ~/.local/state/flick

# Pre-extract any epub files to txt for reading
for dir in ~/Books ~/Documents ~/Downloads; do
    if [ -d "$dir" ]; then
        for epub in "$dir"/*.epub "$dir"/*.EPUB; do
            if [ -f "$epub" ]; then
                txt_file="${epub%.*}.txt"
                # Only extract if txt doesn't exist or epub is newer
                if [ ! -f "$txt_file" ] || [ "$epub" -nt "$txt_file" ]; then
                    echo "Extracting: $epub"
                    "$SCRIPT_DIR/extract_epub.sh" "$epub" > /dev/null 2>&1
                fi
            fi
        done
    fi
done

qmlscene "$SCRIPT_DIR/main.qml"
