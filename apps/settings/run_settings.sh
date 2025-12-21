#!/bin/bash
# Wrapper script for QML settings app

SCRIPT_DIR="$(dirname "$0")"
QML_FILE="${SCRIPT_DIR}/main.qml"
LOG_FILE="${HOME}/.local/state/flick/qml_settings.log"
LOCK_CONFIG="${HOME}/.local/state/flick/lock_config.json"
PENDING_FILE="/tmp/flick-lock-config-pending"

# Ensure state directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$LOCK_CONFIG")"

# Clear old log and pending file
> "$LOG_FILE"
rm -f "$PENDING_FILE"

echo "Starting QML settings, QML_FILE=$QML_FILE" >> "$LOG_FILE"

# Suppress Qt debug output (can corrupt terminal)
export QT_LOGGING_RULES="*.debug=false;qt.qpa.*=false;qt.accessibility.*=false"
export QT_MESSAGE_PATTERN=""
# Force software rendering completely
export QT_QUICK_BACKEND=software
export QT_OPENGL=software
export QMLSCENE_DEVICE=softwarecontext
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export LIBGL_ALWAYS_SOFTWARE=1
# Try wayland-egl integration
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl

# Run qmlscene and capture output
/usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | tee -a "$LOG_FILE" | while read line; do
    # Check for lock config save messages
    if [[ "$line" == *"Saving lock method:"* ]]; then
        METHOD=$(echo "$line" | sed 's/.*Saving lock method: //')
        echo "Detected lock method change: $METHOD" >> "$LOG_FILE"
        echo "$METHOD" > "$PENDING_FILE"
    fi
done
EXIT_CODE=${PIPESTATUS[0]}

echo "QML settings exited with code $EXIT_CODE" >> "$LOG_FILE"

# Process any pending lock config
if [ -f "$PENDING_FILE" ]; then
    METHOD=$(cat "$PENDING_FILE")
    if [ -n "$METHOD" ]; then
        echo "Applying pending lock method: $METHOD" >> "$LOG_FILE"
        echo "{\"method\": \"$METHOD\"}" > "$LOCK_CONFIG"
        echo "Lock config saved to $LOCK_CONFIG" >> "$LOG_FILE"
    fi
    rm -f "$PENDING_FILE"
fi
