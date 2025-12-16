#!/bin/bash
# Start Flick compositor on Droidian phone
# Usage: ./start_flick.sh [--bg]

set -e

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
    sudo -E "$FLICK_BIN" > /tmp/flick.log 2>&1 &
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
else
    sudo -E "$FLICK_BIN"
fi
