#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

mkdir -p ~/.local/state/flick

# Clean up any stale launch request
rm -f /tmp/flick_launch_settings

# Background watcher for settings launch requests
(
    while true; do
        if [ -f /tmp/flick_launch_settings ]; then
            rm -f /tmp/flick_launch_settings
            # Launch settings app
            "$SCRIPT_DIR/../settings/run_settings.sh" &
            break
        fi
        sleep 0.1
    done
) &
WATCHER_PID=$!

# Run the weather app
/usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml"

# Clean up watcher
kill $WATCHER_PID 2>/dev/null
rm -f /tmp/flick_launch_settings
