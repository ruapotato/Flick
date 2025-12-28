#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

mkdir -p ~/.local/state/flick

# Run qmlscene and watch for commands
qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"LAUNCH_SETTINGS:"* ]]; then
        # Launch settings app
        "$SCRIPT_DIR/../settings/run_settings.sh" &
    fi
done
