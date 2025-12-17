#!/bin/bash
# Start Flick compositor on Droidian phone with hwcomposer backend
# Usage: ./start_hwcomposer.sh [--timeout N]
#
# This script can survive SSH disconnection - check logs after

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLICK_BIN="$SCRIPT_DIR/flick-wlroots/build/flick"
TIMEOUT=30

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

# Build if needed
cd "$SCRIPT_DIR/flick-wlroots"
if [ ! -f build/flick ] || [ Makefile -nt build/flick ]; then
    echo "Building flick..."
    make || exit 1
fi
cd "$SCRIPT_DIR"

if [ ! -f "$FLICK_BIN" ]; then
    echo "Error: flick binary not found at $FLICK_BIN"
    exit 1
fi

# Get the real user's UID
REAL_UID=$(id -u "${SUDO_USER:-$USER}")

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/flick-hwc-$(date +%Y%m%d-%H%M%S).log"

echo "=== Flick HWComposer Test ===" | tee "$LOG_FILE"
echo "Timeout: ${TIMEOUT}s" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Create a wrapper script that will run in the background
WRAPPER="/tmp/flick_wrapper_$$.sh"
cat > "$WRAPPER" << EOFWRAPPER
#!/bin/bash
LOG_FILE="$LOG_FILE"
FLICK_BIN="$FLICK_BIN"
TIMEOUT="$TIMEOUT"
REAL_UID="$REAL_UID"

exec >> "\$LOG_FILE" 2>&1

echo "Stopping phosh..."
systemctl stop phosh || true
sleep 2

echo "Resetting hwcomposer..."
pkill -9 -f 'graphics.composer' || true
pkill -9 -f 'hwcomposer' || true
sleep 1

# Restart hwcomposer service
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    echo "Using halium wrapper to restart hwcomposer..."
    ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop || true
    sleep 1
    ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start || true
else
    systemctl restart hwcomposer || true
fi
sleep 3
echo "hwcomposer ready"

# Set up environment - CRITICAL for hwcomposer
export XDG_RUNTIME_DIR="/run/user/\$REAL_UID"
export EGL_PLATFORM=hwcomposer
export WLR_BACKENDS=hwcomposer

# Ensure runtime dir exists
mkdir -p "\$XDG_RUNTIME_DIR" 2>/dev/null || true

echo ""
echo "Starting Flick compositor..."
echo ""

# Run flick with timeout
timeout --signal=TERM "\$TIMEOUT" "\$FLICK_BIN" -v || true

echo ""
echo "Flick exited, restarting phosh..."
systemctl start phosh || true
echo "Done at \$(date)"
EOFWRAPPER

chmod +x "$WRAPPER"

echo "Starting background process..." | tee -a "$LOG_FILE"
echo "SSH may disconnect - check $LOG_FILE for results" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run as root in background, detached from terminal
sudo nohup bash "$WRAPPER" &
WRAPPER_PID=$!

echo "Wrapper started (PID: $WRAPPER_PID)"
echo "Waiting 5 seconds for initial output..."
sleep 5

# Show what's in the log so far
echo ""
echo "=== Log so far ==="
cat "$LOG_FILE"
echo ""
echo "=== Check full log later with: cat $LOG_FILE ==="
