#!/bin/bash
# Flick Email - Mobile email client for Flick shell

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/home/droidian/.local/state/flick/email"
LOG_FILE="${STATE_DIR}/email.log"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

echo "=== Flick Email started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Allow XHR file reads for config and backend communication
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

# Start the Python backend in background
python3 "$SCRIPT_DIR/email_backend.py" >> "$LOG_FILE" 2>&1 &
BACKEND_PID=$!
echo "Backend started with PID: $BACKEND_PID" >> "$LOG_FILE"

# Give backend time to start
sleep 0.3

# Run the QML frontend
qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
QML_EXIT=$?

# Stop the backend when QML exits
echo "QML exited with code: $QML_EXIT, stopping backend" >> "$LOG_FILE"
kill $BACKEND_PID 2>/dev/null

echo "=== Flick Email stopped at $(date) ===" >> "$LOG_FILE"
exit $QML_EXIT
