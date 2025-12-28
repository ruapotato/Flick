#!/bin/bash
# Flick Files - File browser for Flick shell
# Reads text_scale from Flick settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support running from any user - default to droidian
STATE_DIR="/home/droidian/.local/state/flick"
LOG_FILE="${STATE_DIR}/files.log"

mkdir -p "$STATE_DIR"

echo "=== Flick Files started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel
export QT_OPENGL=software

# Allow QML to read local files
export QML_XHR_ALLOW_FILE_READ=1

# Run qmlscene and capture output for file commands
stdbuf -oL -eL qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Check for file open commands
    if [[ "$line" == *"FILE_OPEN:"* ]]; then
        FILE_PATH="${line#*FILE_OPEN:}"
        echo "Opening file: $FILE_PATH" >> "$LOG_FILE"
        xdg-open "$FILE_PATH" >> "$LOG_FILE" 2>&1 &

    # Copy file to clipboard (just log - paste does actual work)
    elif [[ "$line" == *"FILE_COPY:"* ]]; then
        FILE_PATH="${line#*FILE_COPY:}"
        echo "Copied to clipboard: $FILE_PATH" >> "$LOG_FILE"

    # Cut file to clipboard (just log - paste does actual work)
    elif [[ "$line" == *"FILE_CUT:"* ]]; then
        FILE_PATH="${line#*FILE_CUT:}"
        echo "Cut to clipboard: $FILE_PATH" >> "$LOG_FILE"

    # Paste (copy) - format: FILE_PASTE_COPY:source:dest_dir
    elif [[ "$line" == *"FILE_PASTE_COPY:"* ]]; then
        ARGS="${line#*FILE_PASTE_COPY:}"
        SOURCE="${ARGS%%:*}"
        DEST_DIR="${ARGS#*:}"
        echo "Copying $SOURCE to $DEST_DIR" >> "$LOG_FILE"
        cp -r "$SOURCE" "$DEST_DIR/" >> "$LOG_FILE" 2>&1

    # Paste (move) - format: FILE_PASTE_MOVE:source:dest_dir
    elif [[ "$line" == *"FILE_PASTE_MOVE:"* ]]; then
        ARGS="${line#*FILE_PASTE_MOVE:}"
        SOURCE="${ARGS%%:*}"
        DEST_DIR="${ARGS#*:}"
        echo "Moving $SOURCE to $DEST_DIR" >> "$LOG_FILE"
        mv "$SOURCE" "$DEST_DIR/" >> "$LOG_FILE" 2>&1

    # Rename - format: FILE_RENAME:old_path:new_path
    elif [[ "$line" == *"FILE_RENAME:"* ]]; then
        ARGS="${line#*FILE_RENAME:}"
        OLD_PATH="${ARGS%%:*}"
        NEW_PATH="${ARGS#*:}"
        echo "Renaming $OLD_PATH to $NEW_PATH" >> "$LOG_FILE"
        mv "$OLD_PATH" "$NEW_PATH" >> "$LOG_FILE" 2>&1

    # Delete
    elif [[ "$line" == *"FILE_DELETE:"* ]]; then
        FILE_PATH="${line#*FILE_DELETE:}"
        echo "Deleting: $FILE_PATH" >> "$LOG_FILE"
        rm -rf "$FILE_PATH" >> "$LOG_FILE" 2>&1
    fi
done
