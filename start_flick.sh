#!/bin/bash
# Start Flick on Droidian phone
# Run this script ON the phone after SSHing in

# Kill any existing flick process
pkill -9 flick 2>/dev/null

# Start hwcomposer service if not running
if ! pgrep -f 'android.hardware.graphics.composer' > /dev/null; then
    echo "Starting hwcomposer service..."
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' /usr/lib/halium-wrappers/android-service.sh hwcomposer start
    sleep 2
fi

echo "Starting Flick..."
sudo XDG_RUNTIME_DIR=/run/user/$(id -u) EGL_PLATFORM=hwcomposer ~/Flick/shell/target/release/flick --hwcomposer
