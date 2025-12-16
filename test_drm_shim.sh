#!/bin/bash
# Test script for running Flick with the DRM shim backend
# This uses the drm-hwcomposer-shim to provide DRM/GBM interface over hwcomposer

set -e

echo "=== Flick DRM Shim Backend Test ==="
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

echo ""
echo "Starting Flick with DRM shim backend..."
echo "Press Ctrl+C to stop"
echo ""

# Run Flick with the drm-shim backend
# Use SEATD_SOCK to communicate with seatd daemon if available
cd ~/Flick/shell

# Try running without sudo first (as user, with proper session)
# Fall back to sudo if needed for hwcomposer
if [ -S "/run/seatd.sock" ] || [ -n "$SEATD_SOCK" ]; then
    echo "Running with seatd..."
    ./target/release/flick --drm-shim
else
    echo "Running with sudo (seatd not available)..."
    # Run with sudo but preserve environment for input/session
    sudo -E ./target/release/flick --drm-shim
fi
