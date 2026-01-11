#!/bin/bash
# Wrapper script for QML notes app

SCRIPT_DIR="$(dirname "$0")"
QML_FILE="${SCRIPT_DIR}/main.qml"
LOG_FILE="${HOME}/.local/state/flick/qml_notes.log"
DISPLAY_CONFIG="${HOME}/.local/state/flick/display_config.json"
NOTES_DIR="${HOME}/.local/state/flick/notes"

# Ensure state directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$NOTES_DIR"

# Clear old log
> "$LOG_FILE"

echo "Starting QML notes app, QML_FILE=$QML_FILE" >> "$LOG_FILE"

# Read text scale from display config (default 2.0)
TEXT_SCALE="2.0"
if [ -f "$DISPLAY_CONFIG" ]; then
    SAVED_SCALE=$(cat "$DISPLAY_CONFIG" | grep -o '"text_scale"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
    if [ -n "$SAVED_SCALE" ]; then
        TEXT_SCALE="$SAVED_SCALE"
    fi
fi
echo "Using text scale: $TEXT_SCALE" >> "$LOG_FILE"

# Suppress Qt debug output but keep qml messages
export QT_LOGGING_RULES="qt.qpa.*=false;qt.accessibility.*=false;qml=true"
export QT_MESSAGE_PATTERN=""
# Allow QML to read local files (for config loading)
export QML_XHR_ALLOW_FILE_READ=1
# Force software rendering completely
# export QT_QUICK_BACKEND=software  # Using hardware accel
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
# Enable text input protocol for virtual keyboard
export QT_IM_MODULE=textinputv3
# Hardware acceleration enabled
# Try wayland-egl integration
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
# Apply text scale factor (default 2.0x if no config)
export QT_SCALE_FACTOR="$TEXT_SCALE"
# Also set font DPI for better text scaling (96 * scale)
export QT_FONT_DPI=$(echo "$TEXT_SCALE * 96" | bc)
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# Run /usr/lib/qt5/bin/qmlscene and capture output (use stdbuf to prevent buffering)
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Check for notes directory initialization
    if [[ "$line" == *"NOTES_INIT:"* ]]; then
        NOTES_PATH=$(echo "$line" | sed 's/.*NOTES_INIT://')
        echo "Ensuring notes directory exists: $NOTES_PATH" >> "$LOG_FILE"
        mkdir -p "$NOTES_PATH"
    fi

    # Check for save note commands
    if [[ "$line" == *"SAVE_NOTE:"* ]]; then
        NOTE_DATA=$(echo "$line" | sed 's/.*SAVE_NOTE://')
        # Split by first colon to get filename and base64 content
        FILENAME=$(echo "$NOTE_DATA" | cut -d':' -f1)
        ENCODED=$(echo "$NOTE_DATA" | cut -d':' -f2-)

        echo "Saving note: $FILENAME" >> "$LOG_FILE"
        # Decode base64 content and save
        echo -n "$ENCODED" | base64 -d > "$NOTES_DIR/$FILENAME"
        echo "Note saved to $NOTES_DIR/$FILENAME" >> "$LOG_FILE"
    fi

    # Check for delete note commands
    if [[ "$line" == *"DELETE_NOTE:"* ]]; then
        FILENAME=$(echo "$line" | sed 's/.*DELETE_NOTE://')
        echo "Deleting note: $FILENAME" >> "$LOG_FILE"
        rm -f "$NOTES_DIR/$FILENAME"
        echo "Note deleted: $NOTES_DIR/$FILENAME" >> "$LOG_FILE"
    fi
done
EXIT_CODE=${PIPESTATUS[0]}

echo "QML notes app exited with code $EXIT_CODE" >> "$LOG_FILE"
