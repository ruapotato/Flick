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
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

# Allow QML to read local files
export QML_XHR_ALLOW_FILE_READ=1

# Run qmlscene and capture output for file open commands
stdbuf -oL -eL qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Check for file open commands
    if [[ "$line" == *"FILE_OPEN:"* ]]; then
        FILE_PATH=$(echo "$line" | sed 's/.*FILE_OPEN://')
        echo "Opening file: $FILE_PATH" >> "$LOG_FILE"
        xdg-open "$FILE_PATH" >> "$LOG_FILE" 2>&1 &
    fi
done
