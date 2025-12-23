#!/bin/bash
# Flick Audiobooks - First-party audiobook player for Flick shell
# Reads text_scale from Flick settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support running from any user - default to droidian
STATE_DIR="/home/droidian/.local/state/flick"
LOG_FILE="${STATE_DIR}/audiobooks.log"

mkdir -p "$STATE_DIR"

echo "=== Flick Audiobooks started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

# Allow QML to read local files
export QML_XHR_ALLOW_FILE_READ=1

# Settings file
SETTINGS_FILE="${STATE_DIR}/audiobooks_settings.json"

# Run the audiobooks app and handle commands
qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *CREATE_DIR:* ]]; then
        # Extract directory path after CREATE_DIR: prefix
        dir="${line#*CREATE_DIR:}"
        mkdir -p "$dir" 2>/dev/null
        echo "Created directory: $dir" >> "$LOG_FILE"
    elif [[ "$line" == *SAVE_SETTINGS:* ]]; then
        # Extract JSON settings after SAVE_SETTINGS: prefix
        settings="${line#*SAVE_SETTINGS:}"
        echo "$settings" > "$SETTINGS_FILE"
        echo "Saved settings: $settings" >> "$LOG_FILE"
    else
        echo "$line" >> "$LOG_FILE"
    fi
done
