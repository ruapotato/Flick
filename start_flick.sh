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
sleep 0.5

echo "Restarting hwcomposer..."
sudo killall -9 android.hardware.graphics.composer 2>/dev/null || true
sudo killall -9 composer 2>/dev/null || true
sleep 1

if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 2
echo "hwcomposer started"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export EGL_PLATFORM=hwcomposer

echo "Starting Flick..."

if [ "$1" = "--bg" ]; then
    sudo -E "$FLICK_BIN" --hwcomposer > /tmp/flick.log 2>&1 &
    sleep 2
    echo "Flick running in background. Logs: /tmp/flick.log"
else
    sudo -E "$FLICK_BIN" --hwcomposer
fi
