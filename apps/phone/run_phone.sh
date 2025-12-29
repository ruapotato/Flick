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
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Kill any existing phone helper daemon
sudo pkill -f "phone_helper.py daemon" 2>/dev/null
sleep 0.5

# Clear old status/cmd files
rm -f /tmp/flick_phone_cmd /tmp/flick_phone_status 2>/dev/null

# Start the helper daemon in background AS ROOT (needed for oFono D-Bus access)
# The default oFono D-Bus policy denies access to non-root users
sudo python3 "$SCRIPT_DIR/phone_helper.py" daemon >> "$LOG_FILE" 2>&1 &
HELPER_PID=$!
echo "Started phone helper daemon (PID: $HELPER_PID)" >> "$LOG_FILE"

# Wait a moment for daemon to initialize
sleep 1

# Cleanup on exit
cleanup() {
    echo "Cleaning up..." >> "$LOG_FILE"
    sudo kill $HELPER_PID 2>/dev/null
    sudo pkill -f "phone_helper.py daemon" 2>/dev/null
    rm -f "$CMD_FILE" /tmp/flick_phone_status
}
trap cleanup EXIT

# Run QML and capture CMD: lines to write to command file
# Note: QML prefixes output with "qml: " so we look for *CMD:*
stdbuf -oL -eL qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    if [[ "$line" == *CMD:* ]]; then
        # Extract JSON after CMD: prefix (handles "qml: CMD:" prefix)
        json="${line#*CMD:}"
        echo "$json" > "$CMD_FILE"
        echo "Command: $json" >> "$LOG_FILE"
    fi
done
