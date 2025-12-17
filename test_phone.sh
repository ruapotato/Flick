#!/bin/bash
# Test Flick on phone - stops phosh, runs flick, restarts phosh
# Usage: ./test_phone.sh [timeout_seconds]

set -e

TIMEOUT="${1:-30}"
SCRIPT_DIR="$(dirname "$0")"

echo "=== Flick Phone Test ==="
echo "This will stop phosh, run Flick for ${TIMEOUT}s, then restart phosh"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Need sudo to stop/start phosh..."
    SUDO="sudo"
else
    SUDO=""
fi

# Build flick if needed
cd "$SCRIPT_DIR/flick-wlroots"
if [ ! -f build/flick ] || [ Makefile -nt build/flick ]; then
    echo "Building flick..."
    make
fi
cd "$SCRIPT_DIR"

# Create logs directory
mkdir -p logs
LOG_FILE="logs/flick-phone-$(date +%Y%m%d-%H%M%S).log"

echo "Stopping phosh..."
$SUDO systemctl stop phosh

# Give it a moment to release resources
sleep 2

echo "Starting Flick (timeout: ${TIMEOUT}s)..."
echo "Log: $LOG_FILE"

# Run flick with timeout, capturing output
# Use XDG_RUNTIME_DIR for the current user
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

timeout --signal=TERM "$TIMEOUT" ./flick-wlroots/build/flick -v 2>&1 | tee "$LOG_FILE" || true

echo ""
echo "Restarting phosh..."
$SUDO systemctl start phosh

echo ""
echo "=== Test complete ==="
echo "Log saved to: $LOG_FILE"
