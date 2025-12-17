#!/bin/bash
# Start Flick compositor on Droidian phone
# Usage: ./start_flick.sh [--bg|--log]
#   --bg   Run in background, log to /tmp/flick.log
#   --log  Run with output sanitized (recommended), Ctrl+C to stop
#   (none) Run directly (may corrupt terminal, use reset if needed)

set -e

# Function to restore terminal on exit
cleanup() {
    # Reset terminal to sane state
    stty sane 2>/dev/null || true
    # Clear any partial escape sequences
    printf '\033[0m\033[?25h\033c' 2>/dev/null || true
    echo ""
    echo "Flick stopped."
}

# Trap signals for cleanup
trap cleanup EXIT INT TERM

# Get the actual user's home, even if running via sudo
REAL_HOME="${SUDO_USER:+$(eval echo ~$SUDO_USER)}"
REAL_HOME="${REAL_HOME:-$HOME}"

FLICK_BIN="$REAL_HOME/Flick/shell/target/release/flick"

if [ ! -f "$FLICK_BIN" ]; then
    echo "Error: flick binary not found at $FLICK_BIN"
    echo "Build it first: cd ~/Flick/shell && cargo build --release --features hwcomposer"
    exit 1
fi

echo "Stopping existing processes..."
# Use killall with exact name to avoid killing this script
sudo killall -9 flick 2>/dev/null || true
sleep 1

echo "Stopping hwcomposer completely..."
# Kill all hwcomposer-related processes
sudo pkill -9 -f 'graphics.composer' 2>/dev/null || true
sudo pkill -9 -f 'hwcomposer' 2>/dev/null || true
sudo killall -9 android.hardware.graphics.composer 2>/dev/null || true
sudo killall -9 composer 2>/dev/null || true

# Stop the service if running
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop 2>/dev/null || true
fi
sleep 2

echo "Restarting hwcomposer..."
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 3
echo "hwcomposer started"

# Use the real user's runtime directory, not root's
REAL_UID=$(id -u "${SUDO_USER:-$USER}")
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export EGL_PLATFORM=hwcomposer

# Ensure the runtime dir exists and is accessible
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    echo "Warning: XDG_RUNTIME_DIR $XDG_RUNTIME_DIR does not exist, creating..."
    mkdir -p "$XDG_RUNTIME_DIR"
    chown "$REAL_UID:$REAL_UID" "$XDG_RUNTIME_DIR"
fi

echo "Starting Flick..."

if [ "$1" = "--bg" ]; then
    sudo -E "$FLICK_BIN" --hwcomposer > /tmp/flick.log 2>&1 &
    sleep 2

    # Fix Wayland socket permissions so non-root clients can connect
    SOCKET_PATH="$XDG_RUNTIME_DIR/wayland-"
    for sock in ${SOCKET_PATH}*; do
        if [ -S "$sock" ]; then
            sudo chmod 0777 "$sock"
            echo "Fixed permissions on $sock"
        fi
    done

    echo "Flick running in background. Logs: /tmp/flick.log"
elif [ "$1" = "--log" ]; then
    # Run with logging to file but show tail in terminal
    LOG_FILE="/tmp/flick.log"
    echo "Starting Flick with logging to $LOG_FILE"
    echo "Press Ctrl+C to stop..."

    # Start flick with output to log file
    sudo -E "$FLICK_BIN" --hwcomposer > "$LOG_FILE" 2>&1 &
    SUDO_PID=$!

    # Get the actual flick process PID (child of sudo)
    sleep 1
    FLICK_PID=$(pgrep -P "$SUDO_PID" 2>/dev/null || echo "$SUDO_PID")

    # Tail the log file with sanitization
    tail -f "$LOG_FILE" 2>/dev/null | tr -cd '[:print:]\n\t' &
    TAIL_PID=$!

    # Wait for flick to exit
    stop_all() {
        kill "$TAIL_PID" 2>/dev/null || true
        sudo kill -TERM "$FLICK_PID" 2>/dev/null || true
        sleep 1
        sudo kill -KILL "$FLICK_PID" 2>/dev/null || true
        sudo killall -9 flick 2>/dev/null || true
    }
    trap stop_all INT TERM

    wait "$SUDO_PID" 2>/dev/null || true
    kill "$TAIL_PID" 2>/dev/null || true
else
    # Run directly - output may corrupt terminal, use --log for cleaner output
    # Save terminal state
    TERM_STATE=$(stty -g 2>/dev/null || echo "")

    stop_flick() {
        sudo killall -9 flick 2>/dev/null || true
        # Restore terminal
        if [ -n "$TERM_STATE" ]; then
            stty "$TERM_STATE" 2>/dev/null || true
        fi
        stty sane 2>/dev/null || true
        printf '\033[0m\033[?25h\033c' 2>/dev/null || true
    }
    trap stop_flick INT TERM

    # Run directly
    sudo -E "$FLICK_BIN" --hwcomposer || true

    # Restore terminal state after exit
    if [ -n "$TERM_STATE" ]; then
        stty "$TERM_STATE" 2>/dev/null || true
    fi
fi
