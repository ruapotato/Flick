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

# Verification result file
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

# Use a temp file to capture exit code (pipes lose it in subshells)
EXIT_CODE_FILE=$(mktemp)

# Run qmlscene and process its output using process substitution
# This keeps the main script in the parent shell so we can get exit code
while IFS= read -r line; do
    echo "$line" >> "$LOG_FILE"

    # Check for pattern verification request
    if [[ "$line" == *"VERIFY_PATTERN:"* ]]; then
        PATTERN="${line#*VERIFY_PATTERN:}"
        verify_pattern "$PATTERN"
    fi
done < <(/usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1; echo $? > "$EXIT_CODE_FILE")

EXIT_CODE=$(cat "$EXIT_CODE_FILE")
rm -f "$EXIT_CODE_FILE"

echo "QML lockscreen exited with code $EXIT_CODE" >> "$LOG_FILE"

# If qmlscene exited normally (code 0), create unlock signal
# Qt.quit() exits with 0, crashes/errors exit with non-zero
if [ "$EXIT_CODE" -eq 0 ]; then
    SIGNAL_FILE="$STATE_DIR/unlock_signal"
    echo "Creating unlock signal: $SIGNAL_FILE" >> "$LOG_FILE"
    touch "$SIGNAL_FILE"
fi

# Cleanup
rm -f "$VERIFY_RESULT"
