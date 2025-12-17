#!/bin/bash
# Start Flick compositor on Droidian with hwcomposer backend
# Usage: ./start_hwcomposer.sh [--timeout N]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLICK_BIN="$SCRIPT_DIR/flick-wlroots/build/flick"
LOG_FILE="$SCRIPT_DIR/logs/flick-hwc-$(date +%Y%m%d-%H%M%S).log"
TIMEOUT=30

if [[ "$1" == "--timeout" ]]; then
    TIMEOUT="${2:-30}"
fi

mkdir -p "$SCRIPT_DIR/logs"

echo "=== Flick HWComposer Launcher ==="
echo "Log: $LOG_FILE"
echo "Timeout: ${TIMEOUT}s"

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

# Create runner script that will execute detached
RUNNER="/tmp/flick_runner_$$.sh"
cat > "$RUNNER" << EOF
#!/bin/bash
exec > "$LOG_FILE" 2>&1

echo "=== Flick HWComposer Test ==="
echo "Started: \$(date)"
echo ""

# Stop phosh first - it holds the hwcomposer display
echo "Stopping phosh..."
systemctl stop phosh || true
sleep 1

echo "Stopping hwcomposer completely..."
# Kill all hwcomposer-related processes aggressively
pkill -9 -f 'graphics.composer' || true
pkill -9 -f 'hwcomposer' || true
killall -9 android.hardware.graphics.composer 2>/dev/null || true
killall -9 composer 2>/dev/null || true

# Stop the service if running
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer stop || true
fi
sleep 2

echo "Restarting hwcomposer..."
if [ -f /usr/lib/halium-wrappers/android-service.sh ]; then
    ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
        /usr/lib/halium-wrappers/android-service.sh hwcomposer start
else
    systemctl restart hwcomposer 2>/dev/null || true
fi
sleep 3
echo "hwcomposer restarted"

# Match phosh's environment setup exactly
export XDG_RUNTIME_DIR="/run/user/32011"
export EGL_PLATFORM=hwcomposer
export WLR_BACKENDS='hwcomposer,libinput'
export WLR_HWC_SKIP_VERSION_CHECK=1

echo "Environment:"
echo "  XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR"
echo "  EGL_PLATFORM=\$EGL_PLATFORM"
echo "  WLR_BACKENDS=\$WLR_BACKENDS"
echo "  WLR_HWC_SKIP_VERSION_CHECK=\$WLR_HWC_SKIP_VERSION_CHECK"
echo ""
echo "Running flick as droidian user for ${TIMEOUT}s..."
echo ""

# Run as droidian user (like phosh does) instead of root
sudo -u droidian -E timeout --signal=TERM $TIMEOUT "$FLICK_BIN" -v || true

echo ""
echo "Flick exited at \$(date)"

# Note: phosh stays stopped - manually run 'systemctl start phosh' to restore it
EOF

chmod +x "$RUNNER"

echo ""
echo "Launching detached (SSH may disconnect)..."
echo "Check log after ~${TIMEOUT}s: cat $LOG_FILE"
echo ""

# Run as root, fully detached
sudo nohup "$RUNNER" &>/dev/null &

echo "Started. Wait ${TIMEOUT}s then check: cat $LOG_FILE"
