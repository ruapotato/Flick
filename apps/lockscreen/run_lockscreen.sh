#!/bin/bash
# Wrapper script for QML lockscreen that handles unlock signal file creation
# and pattern/PIN verification

STATE_DIR="${FLICK_STATE_DIR:-$HOME/.local/state/flick}"
LOG_FILE="$STATE_DIR/qml_lockscreen.log"
SETTINGS_CTL="$HOME/Flick/apps/settings/flick-settings-ctl"
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

# Set up environment for QML
export FLICK_STATE_DIR="$STATE_DIR"
export QML_XHR_ALLOW_FILE_READ=1
export QT_LOGGING_RULES="*.debug=false;qt.qpa.*=false;qt.accessibility.*=false"
export QT_MESSAGE_PATTERN=""
export QT_QUICK_BACKEND=software
export QT_OPENGL=software
export QMLSCENE_DEVICE=softwarecontext
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export LIBGL_ALWAYS_SOFTWARE=1
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl

# Create a FIFO for verification results
VERIFY_RESULT="$STATE_DIR/verify_result"
rm -f "$VERIFY_RESULT"

# Function to verify pattern
verify_pattern() {
    local pattern="$1"
    echo "Verifying pattern: $pattern" >> "$LOG_FILE"

    # Clear old result first
    rm -f "$VERIFY_RESULT"

    RESULT=$("$SETTINGS_CTL" lock verify-pattern "$pattern" 2>/dev/null)
    echo "Verification result: $RESULT" >> "$LOG_FILE"

    # Write result to file for QML to read
    echo "$RESULT" > "$VERIFY_RESULT"
}

# Run qmlscene and process its output
/usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | while IFS= read -r line; do
    echo "$line" >> "$LOG_FILE"

    # Check for pattern verification request
    if [[ "$line" == *"VERIFY_PATTERN:"* ]]; then
        PATTERN="${line#*VERIFY_PATTERN:}"
        verify_pattern "$PATTERN"
    fi

    # Check for unlock signal
    if [[ "$line" == *"FLICK_UNLOCK_SIGNAL:"* ]]; then
        SIGNAL_FILE="${line#*FLICK_UNLOCK_SIGNAL:}"
        echo "Creating unlock signal: $SIGNAL_FILE" >> "$LOG_FILE"
        touch "$SIGNAL_FILE"
    fi
done

EXIT_CODE=${PIPESTATUS[0]}
echo "QML lockscreen exited with code $EXIT_CODE" >> "$LOG_FILE"

# Cleanup
rm -f "$VERIFY_RESULT"
