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
# Allow QML to read local files via XMLHttpRequest
export QML_XHR_ALLOW_FILE_READ=1
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

# Run qmlscene directly (pipe buffering issues prevent console.log detection)
/usr/lib/qt5/bin/qmlscene "$QML_FILE" >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

echo "QML lockscreen exited with code $EXIT_CODE" >> "$LOG_FILE"

# If qmlscene exited normally (code 0), create unlock signal
# Qt.quit() exits with 0, crashes/errors exit with non-zero
if [ "$EXIT_CODE" -eq 0 ]; then
    SIGNAL_FILE="$STATE_DIR/unlock_signal"
    echo "Creating unlock signal: $SIGNAL_FILE" >> "$LOG_FILE"
    touch "$SIGNAL_FILE"
fi
