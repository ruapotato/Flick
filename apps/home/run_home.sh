#!/bin/bash
# Wrapper script for QML home screen

# Determine user home
if [ -d "/home/droidian" ]; then
    USER_HOME="/home/droidian"
elif [ -n "$SUDO_USER" ] && [ -d "/home/$SUDO_USER" ]; then
    USER_HOME="/home/$SUDO_USER"
elif [ -n "$FLICK_USER" ] && [ -d "/home/$FLICK_USER" ]; then
    USER_HOME="/home/$FLICK_USER"
else
    USER_HOME="$HOME"
fi

STATE_DIR="$USER_HOME/.local/state/flick"
mkdir -p "$STATE_DIR"

# Write state dir for QML to read
echo "$STATE_DIR" > "$STATE_DIR/state_dir.txt"

LOG_FILE="$STATE_DIR/home.log"
echo "=== Home screen starting at $(date) ===" >> "$LOG_FILE"
echo "USER_HOME: $USER_HOME" >> "$LOG_FILE"
echo "STATE_DIR: $STATE_DIR" >> "$LOG_FILE"

# Find the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QML_FILE="$SCRIPT_DIR/main.qml"

echo "QML_FILE: $QML_FILE" >> "$LOG_FILE"

# Run qmlscene
if [ -x /usr/lib/qt5/bin/qmlscene ]; then
    QMLSCENE=/usr/lib/qt5/bin/qmlscene
else
    QMLSCENE=qmlscene
fi

echo "Running: $QMLSCENE $QML_FILE" >> "$LOG_FILE"

# Function to process output and handle launch signals
process_output() {
    while IFS= read -r line; do
        # Log the line
        echo "$line" >> "$LOG_FILE"

        # Check for launch signal
        if [[ "$line" == *"FLICK_LAUNCH_APP:"* ]]; then
            # Extract path and data: FLICK_LAUNCH_APP:/path/to/file:{"id":"app","exec":"cmd"}
            local rest="${line#*FLICK_LAUNCH_APP:}"
            local path="${rest%%:*}"
            local data="${rest#*:}"
            echo "Writing launch signal to $path: $data" >> "$LOG_FILE"
            echo "$data" > "$path"
        fi
    done
}

# Run QML scene, pipe output through processor
$QMLSCENE "$QML_FILE" 2>&1 | process_output
