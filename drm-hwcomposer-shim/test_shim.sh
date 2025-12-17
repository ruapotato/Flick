#!/bin/bash
# Test the drm-hwcomposer-shim
# Usage: ./test_shim.sh
#
# This script properly initializes hwcomposer and runs the color cycling test.
# You should see RED -> GREEN -> BLUE -> YELLOW -> MAGENTA -> CYAN cycling.

set -e

echo "=== DRM-HWComposer Shim Test Script ==="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_BIN="$SCRIPT_DIR/target/release/test_hwc"

if [ ! -f "$TEST_BIN" ]; then
    echo "Error: test binary not found at $TEST_BIN"
    echo "Build it first: cd $SCRIPT_DIR && cargo build --release"
    exit 1
fi

echo "Stopping phosh..."
sudo systemctl stop phosh 2>/dev/null || true

echo "Killing all hwcomposer processes..."
sudo pkill -9 -f 'graphics.composer' 2>/dev/null || true
sudo pkill -9 -f 'hwcomposer' 2>/dev/null || true
sudo killall -9 android.hardware.graphics.composer 2>/dev/null || true
sudo killall -9 composer 2>/dev/null || true

echo "Stopping hwcomposer service..."
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
    sudo systemctl restart android-service@hwcomposer.service 2>/dev/null || true
fi
sleep 3
echo "hwcomposer started"

echo ""
echo "Running test... You should see colors cycling on the display!"
echo ""

# Use the real user's runtime directory, not root's
REAL_UID=$(id -u "${SUDO_USER:-$USER}")
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export EGL_PLATFORM=hwcomposer

echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "EGL_PLATFORM=$EGL_PLATFORM"

sudo -E XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" EGL_PLATFORM=hwcomposer "$TEST_BIN"

echo ""
echo "Test complete!"
