#!/bin/bash
# Flick Messages - SMS/MMS messaging for Flick shell
# Uses ModemManager D-Bus for SMS

SCRIPT_DIR="/home/furios/flick-phosh/Flick/apps/messages"
STATE_DIR="$HOME/.local/state/flick"
LOG_FILE="${STATE_DIR}/messages.log"
CMD_FILE="/tmp/flick_messages_cmd"

mkdir -p "$STATE_DIR"

echo "=== Flick Messages started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Kill any existing messaging daemon
pkill -f "messaging_daemon.py daemon" 2>/dev/null

# Start the messaging daemon in background
# ModemManager typically allows user access, so no sudo needed
python3 "$SCRIPT_DIR/messaging_daemon.py" daemon >> "$LOG_FILE" 2>&1 &
DAEMON_PID=$!
echo "Started messaging daemon (PID: $DAEMON_PID)" >> "$LOG_FILE"

# Cleanup on exit
cleanup() {
    echo "Cleaning up..." >> "$LOG_FILE"
    kill $DAEMON_PID 2>/dev/null
    pkill -f "messaging_daemon.py daemon" 2>/dev/null
    rm -f "$CMD_FILE"
}
trap cleanup EXIT

# Run QML and capture CMD: lines to write to command file
# QML prefixes output with "qml: " so we look for *CMD:*
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    if [[ "$line" == *CMD:* ]]; then
        # Extract JSON after CMD: prefix
        json="${line#*CMD:}"
        echo "$json" > "$CMD_FILE"
        echo "Command: $json" >> "$LOG_FILE"
    # Handle app launch commands
    elif [[ "$line" == *"LAUNCH:"* ]]; then
        APP_CMD=$(echo "$line" | sed 's/.*LAUNCH://')
        echo "Launching app: $APP_CMD" >> "$LOG_FILE"
        "$APP_CMD" &
    fi
done
