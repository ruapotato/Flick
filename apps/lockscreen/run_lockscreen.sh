#!/bin/bash
# Wrapper script for QML lockscreen that handles unlock signal file creation

STATE_DIR="${FLICK_STATE_DIR:-$HOME/.local/state/flick}"
LOG_FILE="$STATE_DIR/qml_lockscreen.log"
QML_FILE="$(dirname "$0")/main.qml"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Clear old log
> "$LOG_FILE"

echo "Starting QML lockscreen, state_dir=$STATE_DIR" >> "$LOG_FILE"
echo "QML_FILE=$QML_FILE" >> "$LOG_FILE"

# Run qmlscene - state dir is passed via FLICK_STATE_DIR env var
# Note: qmlscene only takes the QML file as argument, no extras
export FLICK_STATE_DIR="$STATE_DIR"
/usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | while IFS= read -r line; do
    echo "$line" >> "$LOG_FILE"
    # Check for unlock signal marker
    if [[ "$line" == *"FLICK_UNLOCK_SIGNAL:"* ]]; then
        # Extract the signal path and create the file
        signal_path="${line#*FLICK_UNLOCK_SIGNAL:}"
        echo "Creating unlock signal file: $signal_path" >> "$LOG_FILE"
        mkdir -p "$(dirname "$signal_path")"
        touch "$signal_path"
    fi
done

echo "QML lockscreen exited" >> "$LOG_FILE"
