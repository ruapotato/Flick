#!/bin/bash
# Start Flick compositor and services on Droidian (hwcomposer backend)
# Usage: ./start.sh [--bg]
#   --bg  Run in background, log to /tmp/flick.log

set -e

# Get the real user's home and info, even if running via sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="${SUDO_USER:+$(eval echo ~$SUDO_USER)}"
REAL_HOME="${REAL_HOME:-$HOME}"
REAL_UID=$(id -u "$REAL_USER")
FLICK_BIN="$REAL_HOME/Flick/shell/target/release/flick"
FLICK_DIR="$REAL_HOME/Flick"

if [ ! -f "$FLICK_BIN" ]; then
    echo "Error: flick binary not found at $FLICK_BIN"
    echo "Build it first: cd ~/Flick/shell && cargo build --release"
    exit 1
fi

start_daemons() {
    echo "Starting background services..."

    # Kill any existing daemons
    sudo -u "$REAL_USER" pkill -f "messaging_daemon.py" 2>/dev/null || true
    sudo pkill -f "phone_helper.py daemon" 2>/dev/null || true

    # Start messaging daemon as the real user
    if [ -f "$FLICK_DIR/apps/messages/messaging_daemon.py" ]; then
        echo "  Starting messaging daemon..."
        sudo -u "$REAL_USER" \
            XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
            python3 "$FLICK_DIR/apps/messages/messaging_daemon.py" daemon \
            > /tmp/flick_messages.log 2>&1 &
    fi

    # Start phone helper daemon as root (needed for oFono D-Bus access)
    if [ -f "$FLICK_DIR/apps/phone/phone_helper.py" ]; then
        echo "  Starting phone daemon..."
        # Clean up old status files to avoid permission issues
        rm -f /tmp/flick_phone_status /tmp/flick_phone_cmd 2>/dev/null
        python3 "$FLICK_DIR/apps/phone/phone_helper.py" daemon \
            > /tmp/flick_phone.log 2>&1 &
    fi
}

echo "Stopping existing processes..."
sudo killall -9 flick 2>/dev/null || true
sudo systemctl stop phosh 2>/dev/null || true
sudo -u "$REAL_USER" pkill -f "messaging_daemon.py" 2>/dev/null || true
sudo pkill -f "phone_helper.py daemon" 2>/dev/null || true
sleep 1

echo "Restarting hwcomposer..."
# Use killall with exact names to avoid killing this script
sudo killall -9 android.hardware.graphics.composer 2>/dev/null || true
sudo killall -9 composer 2>/dev/null || true
sleep 1

# Stop the service if running
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop 2>/dev/null || true
fi
sleep 2

if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 2

# Set up environment
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export EGL_PLATFORM=hwcomposer
# Save the real user for flick (the nested sudo will overwrite SUDO_USER)
export FLICK_USER="$REAL_USER"

mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Start background daemons
start_daemons

echo "Starting Flick..."
if [ "$1" = "--bg" ]; then
    sudo -E "$FLICK_BIN" > /tmp/flick.log 2>&1 &
    sleep 2
    # Fix Wayland socket permissions so apps running as user can connect
    REAL_USER="${SUDO_USER:-$USER}"
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -e "$sock" ]; then
            sudo chown "$REAL_USER:$REAL_USER" "$sock"
            sudo chmod 0770 "$sock"
        fi
    done
    echo "Flick running in background."
    echo "  Compositor log: /tmp/flick.log"
    echo "  Messages log: /tmp/flick_messages.log"
    echo "  Phone log: /tmp/flick_phone.log"
else
    sudo -E "$FLICK_BIN"
fi
