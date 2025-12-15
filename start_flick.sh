#!/bin/bash
# Start Flick on Droidian phone
# Run this script ON the phone after SSHing in
# Usage: ./start_flick.sh [--bg]  (--bg runs in background)

set -e

# Kill any existing flick process
sudo pkill -9 flick 2>/dev/null || true

# Always restart hwcomposer service for clean state
echo "Restarting hwcomposer service for clean state..."
sudo pkill -9 composer 2>/dev/null || true
sleep 1
sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' /usr/lib/halium-wrappers/android-service.sh hwcomposer start
sleep 2
echo "hwcomposer service started"

echo "Starting Flick..."
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export EGL_PLATFORM=hwcomposer

if [ "$1" = "--bg" ]; then
    echo "Running in background, logs at /tmp/flick.log"
    sudo -E ~/Flick/shell/target/release/flick --hwcomposer > /tmp/flick.log 2>&1 &
    sleep 2
    echo "Flick PID: $(pgrep -f 'flick --hwcomposer')"
else
    sudo -E ~/Flick/shell/target/release/flick --hwcomposer
fi
