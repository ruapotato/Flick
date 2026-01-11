#!/bin/bash
# Flick Files - File browser for Flick shell
# Reads text_scale from Flick settings
# Supports picker mode: --pick [--filter=images] [--start-dir=/path] [--result-file=/tmp/result]

SCRIPT_DIR="/home/furios/flick-phosh/Flick/apps/files"
# Support running from any user - default to droidian
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/files.log"

mkdir -p "$STATE_DIR"

echo "=== Flick Files started at $(date) ===" >> "$LOG_FILE"

# Parse arguments
PICKER_MODE=""
FILTER_TYPE=""
START_DIR=""
RESULT_FILE=""

for arg in "$@"; do
    case $arg in
        --pick)
            PICKER_MODE="true"
            ;;
        --filter=*)
            FILTER_TYPE="${arg#*=}"
            ;;
        --start-dir=*)
            START_DIR="${arg#*=}"
            ;;
        --result-file=*)
            RESULT_FILE="${arg#*=}"
            ;;
    esac
done

echo "Picker mode: $PICKER_MODE, Filter: $FILTER_TYPE, Start: $START_DIR, Result: $RESULT_FILE" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Allow QML to read local files
export QML_XHR_ALLOW_FILE_READ=1

# Pass picker options as environment variables for QML
export FLICK_PICKER_MODE="$PICKER_MODE"
export FLICK_PICKER_FILTER="$FILTER_TYPE"
export FLICK_PICKER_START_DIR="$START_DIR"
export FLICK_PICKER_RESULT_FILE="$RESULT_FILE"

# Run /usr/lib/qt5/bin/qmlscene and capture output for file commands
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Check for picker result
    if [[ "$line" == *"PICKER_RESULT:"* ]]; then
        PICKED_PATH="${line#*PICKER_RESULT:}"
        echo "Picker result: $PICKED_PATH" >> "$LOG_FILE"
        if [ -n "$RESULT_FILE" ]; then
            echo "$PICKED_PATH" > "$RESULT_FILE"
            echo "Wrote result to $RESULT_FILE" >> "$LOG_FILE"
        fi

    # Check for file open commands
    elif [[ "$line" == *"FILE_OPEN:"* ]]; then
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
