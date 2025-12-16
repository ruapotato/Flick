#!/bin/bash
# Wrapper script for QML settings app

QML_FILE="$(dirname "$0")/main.qml"
LOG_FILE="${HOME}/.local/state/flick/qml_settings.log"

# Ensure state directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Clear old log
> "$LOG_FILE"

echo "Starting QML settings, QML_FILE=$QML_FILE" >> "$LOG_FILE"

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
# Try wayland-egl integration
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl

# Run qmlscene
/usr/lib/qt5/bin/qmlscene "$QML_FILE" >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

echo "QML settings exited with code $EXIT_CODE" >> "$LOG_FILE"
