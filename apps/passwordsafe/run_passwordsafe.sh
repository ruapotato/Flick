#!/bin/bash
# Flick Password Safe - KDBX password manager
# Uses pykeepass for KDBX operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local/state/flick/passwordsafe"
LOG_FILE="${STATE_DIR}/passwordsafe.log"
CMD_FILE="/tmp/flick_vault_cmd"
DISPLAY_CONFIG="${HOME}/.local/state/flick/display_config.json"

mkdir -p "$STATE_DIR"

echo "=== Flick Password Safe started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
export QML_XHR_ALLOW_FILE_READ=1

# Read text scale from display config (default 2.0)
TEXT_SCALE="2.0"
if [ -f "$DISPLAY_CONFIG" ]; then
    SAVED_SCALE=$(cat "$DISPLAY_CONFIG" | grep -o '"text_scale"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
    if [ -n "$SAVED_SCALE" ]; then
        TEXT_SCALE="$SAVED_SCALE"
    fi
fi
echo "Using text scale: $TEXT_SCALE" >> "$LOG_FILE"
export QT_SCALE_FACTOR="$TEXT_SCALE"
export QT_FONT_DPI=$(echo "$TEXT_SCALE * 96" | bc)
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# Kill any existing daemon
pkill -f "passwordsafe_helper.py daemon" 2>/dev/null

# Start the helper daemon in background
python3 "$SCRIPT_DIR/passwordsafe_helper.py" daemon >> "$LOG_FILE" 2>&1 &
DAEMON_PID=$!
echo "Started password safe daemon (PID: $DAEMON_PID)" >> "$LOG_FILE"

# Give daemon time to initialize
sleep 0.2

# Cleanup on exit
cleanup() {
    echo "Cleaning up..." >> "$LOG_FILE"
    # Lock vault on exit by sending lock command
    echo '{"action":"lock"}' > "$CMD_FILE"
    sleep 0.1
    kill $DAEMON_PID 2>/dev/null
    pkill -f "passwordsafe_helper.py daemon" 2>/dev/null
    rm -f "$CMD_FILE"
}
trap cleanup EXIT

# Run QML and capture CMD: lines to write to command file
stdbuf -oL -eL qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    if [[ "$line" == *CMD:* ]]; then
        # Extract JSON after CMD: prefix
        json="${line#*CMD:}"
        echo "$json" > "$CMD_FILE"
        echo "Command: $json" >> "$LOG_FILE"
    fi
done
