#!/bin/bash
# Start Flick compositor on Droidian phone with hwcomposer backend
# Usage: ./start_hwcomposer.sh [--timeout N]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLICK_BIN="$SCRIPT_DIR/flick-wlroots/build/flick"
TIMEOUT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--timeout N]"
            exit 1
            ;;
    esac
done

# Function to restore terminal and restart phosh on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    stty sane 2>/dev/null || true
    printf '\033[0m\033[?25h\033c' 2>/dev/null || true

    echo "Restarting phosh..."
    sudo systemctl start phosh 2>/dev/null || true
    echo "Done."
}

trap cleanup EXIT INT TERM

# Build if needed
cd "$SCRIPT_DIR/flick-wlroots"
if [ ! -f build/flick ] || [ Makefile -nt build/flick ]; then
    echo "Building flick..."
    make
fi
cd "$SCRIPT_DIR"

if [ ! -f "$FLICK_BIN" ]; then
    echo "Error: flick binary not found at $FLICK_BIN"
    exit 1
fi

# Get the real user's UID (works with sudo)
REAL_UID=$(id -u "${SUDO_USER:-$USER}")

echo "=== Flick HWComposer Test ==="
echo ""

echo "Stopping phosh..."
sudo systemctl stop phosh 2>/dev/null || true
sleep 2

echo "Resetting hwcomposer..."
# Kill hwcomposer-related processes
sudo pkill -9 -f 'graphics.composer' 2>/dev/null || true
sudo pkill -9 -f 'hwcomposer' 2>/dev/null || true
sleep 1

# Restart hwcomposer service
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    echo "Using halium wrapper to restart hwcomposer..."
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop 2>/dev/null || true
    sleep 1
    sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start 2>/dev/null || true
else
    sudo systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 3
echo "hwcomposer ready"

# Set up environment
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export EGL_PLATFORM=hwcomposer

# Ensure runtime dir exists
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    echo "Creating XDG_RUNTIME_DIR..."
    sudo mkdir -p "$XDG_RUNTIME_DIR"
    sudo chown "$REAL_UID:$REAL_UID" "$XDG_RUNTIME_DIR"
fi

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/flick-hwc-$(date +%Y%m%d-%H%M%S).log"

echo ""
echo "Starting Flick compositor..."
echo "Log: $LOG_FILE"
if [ "$TIMEOUT" -gt 0 ]; then
    echo "Timeout: ${TIMEOUT}s"
fi
echo ""

# Run flick
if [ "$TIMEOUT" -gt 0 ]; then
    timeout --signal=TERM "$TIMEOUT" sudo -E "$FLICK_BIN" -v 2>&1 | tee "$LOG_FILE" || true
else
    sudo -E "$FLICK_BIN" -v 2>&1 | tee "$LOG_FILE" || true
fi

echo ""
echo "Log saved to: $LOG_FILE"
