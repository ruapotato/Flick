#!/bin/bash
# Wrapper script for Flick-Phosh Settings QML app
# Simplified: only handles Effects and App Manager settings

SCRIPT_DIR="$(dirname "$0")"
QML_FILE="${SCRIPT_DIR}/main.qml"
LOG_FILE="${HOME}/.local/state/flick/qml_settings.log"

# Ensure state directories exist
mkdir -p "${HOME}/.local/state/flick"
mkdir -p "${HOME}/.local/state/flick-phosh"

# Clear old log
> "$LOG_FILE"

# Clean up deep link page file on exit
trap 'rm -f /tmp/flick_settings_page' EXIT

echo "Starting Flick-Phosh Settings" >> "$LOG_FILE"

# Scan installed apps for the app manager
SCANNER="${HOME}/flick-phosh/scripts/scan-apps"
if [ -x "$SCANNER" ]; then
    echo "Scanning installed apps..." >> "$LOG_FILE"
    python3 "$SCANNER" >> "$LOG_FILE" 2>&1
fi

# Suppress Qt debug output but keep qml messages
export QT_LOGGING_RULES="qt.qpa.*=false;qt.accessibility.*=false;qml=true"
export QT_MESSAGE_PATTERN=""
# Allow QML to read local files (for config loading)
export QML_XHR_ALLOW_FILE_READ=1
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# Apply text scale if configured
DISPLAY_CONFIG="${HOME}/.local/state/flick/display_config.json"
TEXT_SCALE="2.0"
if [ -f "$DISPLAY_CONFIG" ]; then
    SAVED_SCALE=$(cat "$DISPLAY_CONFIG" | grep -o '"text_scale"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
    if [ -n "$SAVED_SCALE" ]; then
        TEXT_SCALE="$SAVED_SCALE"
    fi
fi
export QT_SCALE_FACTOR="$TEXT_SCALE"
export QT_FONT_DPI=$(echo "$TEXT_SCALE * 96" | bc)

echo "Using text scale: $TEXT_SCALE" >> "$LOG_FILE"

# State directories
STATE_DIR="${HOME}/.local/state/flick-phosh"
EFFECTS_STATE_DIR="${HOME}/.local/state/flick"

# Function to process QML output commands
process_qml_output() {
    while IFS= read -r line; do
        echo "$line" >> "$LOG_FILE"

        # Check for save commands
        if [[ "$line" == *"SAVE_EXCLUDED:"* ]]; then
            json="${line#*SAVE_EXCLUDED:}"
            echo "$json" > "${STATE_DIR}/excluded_apps.json"
            echo "Saved excluded apps" >> "$LOG_FILE"
        elif [[ "$line" == *"SAVE_OTHER_APPS:"* ]]; then
            json="${line#*SAVE_OTHER_APPS:}"
            echo "$json" > "${STATE_DIR}/curated_other_apps.json"
            echo "Saved other apps" >> "$LOG_FILE"
        elif [[ "$line" == *"SAVE_EFFECTS:"* ]]; then
            json="${line#*SAVE_EFFECTS:}"
            echo "$json" > "${EFFECTS_STATE_DIR}/effects_config.json"
            echo "Saved effects config" >> "$LOG_FILE"
        elif [[ "$line" == *"HAPTIC:"* ]]; then
            cmd="${line#*HAPTIC:}"
            echo "$cmd" > /tmp/flick_haptic 2>/dev/null || true
        fi
    done
}

# Run qmlscene and process output
/usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | process_qml_output

echo "Settings exited" >> "$LOG_FILE"
