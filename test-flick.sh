#!/bin/bash
# Flick Test Script for Mobian (PinePhone/PinePhone Pro)
# Run this after installation to test Flick

set -e

FLICK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Flick Test Script ==="
echo ""

# Check if Flick is built
if [ ! -f "$FLICK_DIR/shell/target/release/flick_shell" ]; then
    echo "ERROR: Flick shell binary not found!"
    echo "Please run install-mobian.sh first to build Flick"
    exit 1
fi

echo "Flick binary found: $FLICK_DIR/shell/target/release/flick_shell"
echo ""

# Check if we're in a TTY
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    echo "WARNING: You appear to be running in a graphical session."
    echo "Flick needs to run from a TTY, not from within Phosh."
    echo ""
    echo "To test Flick:"
    echo "  1. Open a terminal and run: sudo systemctl stop phosh"
    echo "  2. Or switch to TTY2: Ctrl+Alt+F2"
    echo "  3. Then run: $FLICK_DIR/start.sh"
    echo ""
    read -p "Do you want to stop Phosh now and start Flick? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping Phosh..."
        sudo systemctl stop phosh
        sleep 2
        echo "Starting Flick..."
        exec "$FLICK_DIR/start.sh"
    fi
    exit 0
fi

# We're in a TTY, can run directly
echo "Running from TTY - good!"
echo ""

# Check for running display servers
if systemctl is-active --quiet phosh; then
    echo "Phosh is running. Stopping it..."
    sudo systemctl stop phosh
    sleep 2
fi

echo "Starting Flick..."
exec "$FLICK_DIR/start.sh"
