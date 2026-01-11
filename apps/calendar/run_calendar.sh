#!/bin/bash
# Flick Calendar - First-party calendar app for Flick shell
# Reads text_scale from Flick settings

SCRIPT_DIR="/home/furios/flick-phosh/Flick/apps/calendar"
# Support running from any user - default to droidian
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/calendar.log"
EVENTS_FILE="${STATE_DIR}/calendar.json"

mkdir -p "$STATE_DIR"

echo "=== Flick Calendar started at $(date) ===" >> "$LOG_FILE"

# Initialize events file if it doesn't exist
if [ ! -f "$EVENTS_FILE" ]; then
    echo '{}' > "$EVENTS_FILE"
    echo "Created events file at $EVENTS_FILE" >> "$LOG_FILE"
fi

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Allow QML to read local files (for config and events loading)
export QML_XHR_ALLOW_FILE_READ=1

# Run the calendar and capture save events
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE" | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Check for event save messages
    if [[ "$line" == *"SAVE_EVENTS:"* ]]; then
        EVENTS_JSON=$(echo "$line" | sed 's/.*SAVE_EVENTS://')
        echo "Saving events to $EVENTS_FILE" >> "$LOG_FILE"
        echo "$EVENTS_JSON" > "$EVENTS_FILE"
        echo "Events saved successfully" >> "$LOG_FILE"
    fi
done
EXIT_CODE=${PIPESTATUS[0]}

echo "Flick Calendar exited with code $EXIT_CODE" >> "$LOG_FILE"
