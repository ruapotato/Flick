#!/bin/bash
# Flick Phone - Native phone dialer for Flick shell
# Uses oFono D-Bus for telephony

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# Check if phone daemon is already running (started by start.sh)
if ! pgrep -f "phone_helper.py daemon" > /dev/null; then
    echo "Starting phone helper daemon..." >> "$LOG_FILE"
    # Start the helper daemon in background AS ROOT (needed for oFono D-Bus access)
    sudo python3 "$SCRIPT_DIR/phone_helper.py" daemon >> "$LOG_FILE" 2>&1 &
    HELPER_PID=$!
    echo "Started phone helper daemon (PID: $HELPER_PID)" >> "$LOG_FILE"
    # Wait a moment for daemon to initialize
    sleep 1
else
    echo "Phone helper daemon already running" >> "$LOG_FILE"
fi

# Clear old command file (but keep status file for daemon communication)
rm -f /tmp/flick_phone_cmd 2>/dev/null

# Note: We don't kill the daemon on exit - it should keep running for incoming calls
# The daemon is managed by start.sh

# Run QML and capture CMD: lines to write to command file
# Note: QML prefixes output with "qml: " so we look for *CMD:*
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    if [[ "$line" == *CMD:* ]]; then
        # Extract JSON after CMD: prefix (handles "qml: CMD:" prefix)
        json="${line#*CMD:}"
        echo "$json" > "$CMD_FILE"
        echo "Command: $json" >> "$LOG_FILE"
    fi
done
