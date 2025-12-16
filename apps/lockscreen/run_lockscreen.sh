#!/bin/bash
# Wrapper script for QML lockscreen that handles unlock signal file creation

STATE_DIR="${FLICK_STATE_DIR:-$HOME/.local/state/flick}"
LOG_FILE="$STATE_DIR/qml_lockscreen.log"
# Use main.qml for production
QML_FILE="$(dirname "$0")/main.qml"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Clear old log
> "$LOG_FILE"

echo "Starting QML lockscreen, state_dir=$STATE_DIR" >> "$LOG_FILE"
echo "QML_FILE=$QML_FILE" >> "$LOG_FILE"

# Write state dir to a file that QML can read (Qt5 doesn't have Qt.getenv)
echo "$STATE_DIR" > "$STATE_DIR/state_dir.txt"

# Run qmlscene - state dir is passed via FLICK_STATE_DIR env var
# Note: qmlscene only takes the QML file as argument, no extras
export FLICK_STATE_DIR="$STATE_DIR"
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
# Try wayland-egl integration (shm not available as client)
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
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
