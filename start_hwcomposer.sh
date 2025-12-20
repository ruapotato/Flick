#!/bin/bash
# Start Flick compositor on Droidian (hwcomposer backend)
# Usage: ./start_hwcomposer.sh [--bg]
#   --bg  Run in background, log to /tmp/flick.log

set -e

# Get the real user's home, even if running via sudo
REAL_HOME="${SUDO_USER:+$(eval echo ~$SUDO_USER)}"
REAL_HOME="${REAL_HOME:-$HOME}"
FLICK_BIN="$REAL_HOME/Flick/shell/target/release/flick"

if [ ! -f "$FLICK_BIN" ]; then
    echo "Error: flick binary not found at $FLICK_BIN"
    echo "Build it first: cd ~/Flick/shell && cargo build --release"
    exit 1
fi

echo "Stopping existing processes..."
sudo killall -9 flick 2>/dev/null || true
sudo systemctl stop phosh 2>/dev/null || true
sleep 1

echo "Restarting hwcomposer..."
# Use killall with exact names to avoid killing this script
sudo killall -9 android.hardware.graphics.composer 2>/dev/null || true
sudo killall -9 composer 2>/dev/null || true
sleep 1

# Stop the service if running
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop 2>/dev/null || true
fi
sleep 2

if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 2

# Set up environment
REAL_UID=$(id -u "${SUDO_USER:-$USER}")
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export EGL_PLATFORM=hwcomposer
# Save the real user for flick (the nested sudo will overwrite SUDO_USER)
export FLICK_USER="${SUDO_USER:-$USER}"

mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

echo "Starting Flick..."
# Run as the real user (not root) to fix SHM buffer access issues
FLICK_CMD="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR EGL_PLATFORM=hwcomposer $FLICK_BIN"
if [ "$1" = "--bg" ]; then
    sudo -u "$FLICK_USER" -E sh -c "$FLICK_CMD" > /tmp/flick.log 2>&1 &
    sleep 2
    echo "Flick running in background. Logs: /tmp/flick.log"
else
    sudo -u "$FLICK_USER" -E sh -c "$FLICK_CMD"
fi
