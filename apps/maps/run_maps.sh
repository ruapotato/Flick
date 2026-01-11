#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1

# SSL/network for map tiles
export QT_SSL_USE_TEMPORARY_KEYCHAIN=1

mkdir -p ~/.local/state/flick

# Speech queue file for voice navigation
SPEAK_QUEUE="$HOME/.local/state/flick/speak_queue"
SPEECH_PID=""

# Clean up on exit
cleanup() {
    if [ -n "$SPEECH_PID" ] && kill -0 "$SPEECH_PID" 2>/dev/null; then
        kill "$SPEECH_PID" 2>/dev/null
    fi
    rm -f "$SPEAK_QUEUE"
}
trap cleanup EXIT

# Initialize empty speech queue
> "$SPEAK_QUEUE"

# Speech daemon - watches for text to speak
speech_daemon() {
    while true; do
        if [ -s "$SPEAK_QUEUE" ]; then
            # Read and clear the queue atomically
            TEXT=$(cat "$SPEAK_QUEUE" 2>/dev/null)
            > "$SPEAK_QUEUE"

            if [ -n "$TEXT" ]; then
                # Speak each line (kill any ongoing speech first)
                pkill -9 espeak-ng 2>/dev/null
                echo "$TEXT" | while IFS= read -r line; do
                    [ -n "$line" ] && espeak-ng -v en -s 160 "$line" 2>/dev/null
                done
            fi
        fi
        sleep 0.3
    done
}

# Start speech daemon in background
speech_daemon &
SPEECH_PID=$!

# Run the maps app
/usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml"
