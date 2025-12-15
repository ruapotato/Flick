#!/bin/bash
# Start Flick on Droidian phone
# Usage: ./start_phone.sh

PHONE_IP="10.15.19.82"
PHONE_USER="droidian"

echo "Starting Flick on phone ($PHONE_IP)..."

# Kill any existing flick process
ssh $PHONE_USER@$PHONE_IP "pkill -9 flick" 2>/dev/null

# Start hwcomposer service if not running
echo "Ensuring hwcomposer service is running..."
ssh $PHONE_USER@$PHONE_IP "pgrep -f 'android.hardware.graphics.composer' > /dev/null || sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' /usr/lib/halium-wrappers/android-service.sh hwcomposer start"

sleep 1

# Run flick
echo "Starting Flick..."
ssh -t $PHONE_USER@$PHONE_IP "sudo XDG_RUNTIME_DIR=/run/user/\$(id -u $PHONE_USER) EGL_PLATFORM=hwcomposer ~/Flick/shell/target/release/flick --hwcomposer"
