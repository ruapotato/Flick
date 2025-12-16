#!/bin/bash
# Test script for running Flick with the DRM shim (LD_PRELOAD approach)
# This uses the drm-hwcomposer-shim to provide DRM/GBM interface over hwcomposer
# The shim is loaded via LD_PRELOAD and intercepts libdrm/libgbm calls

set -e

echo "=== Flick DRM Shim Backend Test (Universal LD_PRELOAD) ==="
echo ""

# Stop any existing compositor
echo "Stopping phosh/existing compositor..."
sudo systemctl stop phosh 2>/dev/null || true
sleep 1

# Kill any lingering hwcomposer processes
echo "Resetting hwcomposer..."
sudo pkill -9 -f 'graphics.composer' 2>/dev/null || true
sleep 1

# Restart hwcomposer service properly
echo "Starting hwcomposer service..."
sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
    /usr/lib/halium-wrappers/android-service.sh hwcomposer start
sleep 3

# Set up environment
export EGL_PLATFORM=hwcomposer
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY=wayland-0

# Ensure runtime dir exists
mkdir -p "$XDG_RUNTIME_DIR"

# Ensure log directory exists
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/flick"
mkdir -p "$LOG_DIR"

# Activate current session to get input device access
echo "Activating user session..."
if [ -n "$XDG_SESSION_ID" ]; then
    loginctl activate "$XDG_SESSION_ID" 2>/dev/null || true
fi

# Make sure we have a VT allocated
# On Droidian this is typically VT7
CURRENT_VT=$(fgconsole 2>/dev/null || echo "7")
echo "Current VT: $CURRENT_VT"

# Check input device permissions
echo ""
echo "Checking input device permissions..."
ls -la /dev/input/event* 2>/dev/null | head -5
echo ""

# Check if user is in input group
if groups | grep -q '\binput\b'; then
    echo "User is in input group"
else
    echo "WARNING: User is not in input group. Adding with sudo..."
    sudo usermod -aG input "$USER"
    echo "Please log out and back in for group changes to take effect."
    echo "Or run: newgrp input"
fi

# Clean up stale wayland sockets
echo "Cleaning up stale sockets..."
rm -f "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null || true

# Path to the shim library
SHIM_LIB="$HOME/Flick/drm-hwcomposer-shim/target/release/libdrm_hwcomposer_shim.so"

if [ ! -f "$SHIM_LIB" ]; then
    echo "ERROR: Shim library not found at $SHIM_LIB"
    echo "Building shim..."
    cd ~/Flick/drm-hwcomposer-shim
    cargo build --release
fi

echo ""
echo "Starting Flick with DRM shim via LD_PRELOAD..."
echo "Shim library: $SHIM_LIB"
echo "Press Ctrl+C to stop"
echo ""

# Run Flick with the shim preloaded
# The udev backend will try to use standard DRM/GBM, but our shim intercepts those calls
cd ~/Flick/shell
sudo -E LD_PRELOAD="$SHIM_LIB" ./target/release/flick
