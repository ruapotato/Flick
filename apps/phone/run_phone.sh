#!/bin/bash
# Flick Phone - Native phone dialer for Flick shell
# Uses oFono D-Bus for telephony

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/phone.log"
CMD_FILE="/tmp/flick_phone_cmd"

mkdir -p "$STATE_DIR"

echo "=== Flick Phone started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

# Kill any existing phone helper daemon
pkill -f "phone_helper.py daemon" 2>/dev/null

# Start the helper daemon in background
python3 "$SCRIPT_DIR/phone_helper.py" daemon >> "$LOG_FILE" 2>&1 &
HELPER_PID=$!
echo "Started phone helper daemon (PID: $HELPER_PID)" >> "$LOG_FILE"

# Cleanup on exit
cleanup() {
    echo "Cleaning up..." >> "$LOG_FILE"
    kill $HELPER_PID 2>/dev/null
    rm -f "$CMD_FILE" /tmp/flick_phone_status
}
trap cleanup EXIT

# Run QML and capture CMD: lines to write to command file
# Note: QML prefixes output with "qml: " so we look for *CMD:*
qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *CMD:* ]]; then
        # Extract JSON after CMD: prefix (handles "qml: CMD:" prefix)
        json="${line#*CMD:}"
        echo "$json" > "$CMD_FILE"
        echo "Command: $json" >> "$LOG_FILE"
    else
        echo "$line" >> "$LOG_FILE"
    fi
done
