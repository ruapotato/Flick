#!/bin/bash
# Start Flick compositor on Droidian with hwcomposer backend
# Usage: ./start_hwcomposer.sh [--timeout N]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLICK_BIN="$SCRIPT_DIR/flick-wlroots/build/flick"
TIMEOUT="${1:-0}"

if [[ "$1" == "--timeout" ]]; then
    TIMEOUT="${2:-30}"
fi

echo "=== Flick HWComposer Launcher ==="

# Build if needed
cd "$SCRIPT_DIR/flick-wlroots"
if [ ! -f build/flick ] || [ Makefile -nt build/flick ]; then
    echo "Building flick..."
    make || exit 1
fi

if [ ! -f "$FLICK_BIN" ]; then
    echo "Error: $FLICK_BIN not found"
    exit 1
fi

echo "Resetting hwcomposer..."
sudo pkill -9 -f 'graphics.composer' 2>/dev/null || true
sudo pkill -9 -f 'hwcomposer' 2>/dev/null || true
sleep 1

# Restart hwcomposer
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop 2>/dev/null || true
    sleep 1
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi

echo "Waiting for hwcomposer..."
sleep 3

# Environment for hwcomposer
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export EGL_PLATFORM=hwcomposer
export WLR_BACKENDS=hwcomposer

echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "EGL_PLATFORM=$EGL_PLATFORM"
echo "WLR_BACKENDS=$WLR_BACKENDS"
echo ""

# Run flick
if [ "$TIMEOUT" -gt 0 ] 2>/dev/null; then
    echo "Running flick for ${TIMEOUT}s..."
    sudo -E timeout --signal=TERM "$TIMEOUT" "$FLICK_BIN" -v || true
else
    echo "Running flick (Ctrl+C to stop)..."
    sudo -E "$FLICK_BIN" -v || true
fi

echo ""
echo "Flick exited."
