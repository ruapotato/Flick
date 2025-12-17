#!/bin/bash
# Start Flick compositor on Droidian with hwcomposer backend
# Usage: ./start_hwcomposer.sh [--timeout N]
# Ctrl+C to stop

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLICK_BIN="$SCRIPT_DIR/flick-wlroots/build/flick"
TIMEOUT="${2:-0}"

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

echo "Stopping phosh..."
sudo systemctl stop phosh || true
sleep 1

echo "Stopping hwcomposer completely..."
sudo pkill -9 -f 'graphics.composer' || true
sudo pkill -9 -f 'hwcomposer' || true
sudo killall -9 android.hardware.graphics.composer 2>/dev/null || true
sudo killall -9 composer 2>/dev/null || true

if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop || true
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
echo "hwcomposer restarted"

# Unblank display
echo "Unblanking display..."
sudo sh -c 'echo 0 > /sys/class/backlight/panel0-backlight/bl_power' 2>/dev/null || true
BRIGHTNESS=$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || echo "0")
if [ "$BRIGHTNESS" = "0" ]; then
    sudo sh -c 'echo 255 > /sys/class/backlight/panel0-backlight/brightness' 2>/dev/null || true
fi
sudo sh -c 'echo 0 > /sys/class/graphics/fb0/blank' 2>/dev/null || true

# Environment
export XDG_RUNTIME_DIR="/run/user/32011"
export EGL_PLATFORM=hwcomposer
export WLR_BACKENDS='hwcomposer,libinput'
export WLR_HWC_SKIP_VERSION_CHECK=1

echo ""
echo "Environment:"
echo "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "  EGL_PLATFORM=$EGL_PLATFORM"
echo "  WLR_BACKENDS=$WLR_BACKENDS"
echo ""
echo "Starting flick (Ctrl+C to stop)..."
echo ""

# Run flick - with or without timeout
if [ "$TIMEOUT" -gt 0 ]; then
    sudo -u droidian -E timeout --signal=TERM "$TIMEOUT" "$FLICK_BIN" -v
else
    sudo -u droidian -E "$FLICK_BIN" -v
fi

echo ""
echo "Flick exited. Run 'sudo systemctl start phosh' to restore UI."
