#!/bin/bash
# Start Flick compositor on Droidian phone
# Can be run as normal user - uses sudo internally where needed
# Usage: ./start_flick.sh [--bg]  (--bg runs in background)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we can use sudo
if ! sudo -n true 2>/dev/null; then
    log_warn "This script needs sudo access. You may be prompted for your password."
fi

# Find the flick binary
FLICK_BIN=""
if [ -f "$HOME/Flick/shell/target/release/flick" ]; then
    FLICK_BIN="$HOME/Flick/shell/target/release/flick"
elif [ -f "$HOME/Flick/target/release/flick" ]; then
    FLICK_BIN="$HOME/Flick/target/release/flick"
elif [ -f "/usr/local/bin/flick" ]; then
    FLICK_BIN="/usr/local/bin/flick"
elif command -v flick &> /dev/null; then
    FLICK_BIN=$(command -v flick)
fi

if [ -z "$FLICK_BIN" ]; then
    log_error "Could not find flick binary!"
    log_error "Please build it first: cd ~/Flick/shell && cargo build --release"
    exit 1
fi

log_info "Using flick binary: $FLICK_BIN"

# Kill any existing flick process
log_info "Stopping any existing Flick processes..."
sudo pkill -9 flick 2>/dev/null || true
sleep 0.5

# Restart hwcomposer service for clean state
log_info "Restarting hwcomposer service..."
sudo pkill -9 composer 2>/dev/null || true
sleep 1

# Start hwcomposer service
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    log_warn "android-service.sh not found, trying systemctl..."
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 2
log_info "hwcomposer service started"

# Set up environment
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export EGL_PLATFORM=hwcomposer
export WAYLAND_DISPLAY=wayland-1

# Ensure XDG_RUNTIME_DIR exists
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    log_warn "XDG_RUNTIME_DIR doesn't exist, creating..."
    sudo mkdir -p "$XDG_RUNTIME_DIR"
    sudo chown $(id -u):$(id -g) "$XDG_RUNTIME_DIR"
    sudo chmod 700 "$XDG_RUNTIME_DIR"
fi

log_info "Starting Flick compositor..."
log_info "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
log_info "  EGL_PLATFORM=$EGL_PLATFORM"

if [ "$1" = "--bg" ]; then
    log_info "Running in background, logs at /tmp/flick.log"
    sudo -E "$FLICK_BIN" --hwcomposer > /tmp/flick.log 2>&1 &
    sleep 2
    PID=$(pgrep -f 'flick.*--hwcomposer' || echo "")
    if [ -n "$PID" ]; then
        log_info "Flick started with PID: $PID"
        log_info "View logs with: tail -f /tmp/flick.log"
    else
        log_error "Flick failed to start! Check /tmp/flick.log"
        exit 1
    fi
else
    # Run in foreground
    sudo -E "$FLICK_BIN" --hwcomposer
fi
