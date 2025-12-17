#!/bin/bash
# Test the drm-hwcomposer-shim with Weston compositor
# This proves the shim works with ANY standard Linux compositor

set -e

echo "=== Testing drm-hwcomposer-shim with Weston ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHIM_LIB="$SCRIPT_DIR/target/release/libdrm_hwcomposer_shim.so"

if [ ! -f "$SHIM_LIB" ]; then
    echo "Error: shim library not found at $SHIM_LIB"
    echo "Build it first: cargo build --release"
    exit 1
fi

if ! command -v weston &> /dev/null; then
    echo "Error: weston not installed. Install with: sudo apt install weston"
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

# Set up environment
REAL_UID=$(id -u "${SUDO_USER:-$USER}")
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export EGL_PLATFORM=hwcomposer

echo ""
echo "Environment:"
echo "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "  EGL_PLATFORM=$EGL_PLATFORM"
echo "  LD_PRELOAD=$SHIM_LIB"
echo ""
echo "Starting Weston with drm-hwcomposer-shim..."
echo "Press Ctrl+C to stop"
echo ""

# Run Weston with the shim
# --backend=drm-backend.so tells Weston to use DRM/KMS which we intercept
# Use LIBSEAT_BACKEND=noop to avoid libseat child process issues
# EGL_PLATFORM=hwcomposer is needed for libhybris EGL to work
sudo -E LD_PRELOAD="$SHIM_LIB" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    EGL_PLATFORM=hwcomposer \
    LIBSEAT_BACKEND=noop \
    weston --backend=drm-backend.so --tty=1 2>&1

echo ""
echo "Weston exited"
