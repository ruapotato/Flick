#!/bin/bash
# Flick gesture configuration for lisgd
# This script starts lisgd with edge gesture bindings for back/forward navigation

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [lisgd.sh] $*"
}

# Find the touchscreen device
find_touchscreen() {
    # First try udevadm (most reliable)
    for dev in /dev/input/event*; do
        if udevadm info --query=property --name="$dev" 2>/dev/null | grep -q "ID_INPUT_TOUCHSCREEN=1"; then
            echo "$dev"
            return
        fi
    done

    # Try by-path symlink
    local bypath=$(ls /dev/input/by-path/*-event-touchscreen 2>/dev/null | head -1)
    if [ -n "$bypath" ]; then
        echo "$bypath"
        return
    fi

    # Fallback - try to find by name in sysfs
    grep -l "Touchscreen\|touch" /sys/class/input/event*/device/name 2>/dev/null | \
        head -1 | sed 's|.*event|/dev/input/event|;s|/device/name||'
}

# Use provided device or auto-detect
LISGD_DEVICE="${LISGD_DEVICE:-$(find_touchscreen)}"

if [ -z "$LISGD_DEVICE" ]; then
    log_msg "ERROR: No touchscreen device found"
    log_msg "Available input devices:"
    ls -la /dev/input/ 2>&1 | head -20
    exit 1
fi

log_msg "Using touchscreen device: $LISGD_DEVICE"

# Check if device exists
if [ ! -e "$LISGD_DEVICE" ]; then
    log_msg "ERROR: Device $LISGD_DEVICE does not exist"
    exit 1
fi

# Check read permission
if [ ! -r "$LISGD_DEVICE" ]; then
    log_msg "ERROR: Cannot read $LISGD_DEVICE (permission denied)"
    log_msg "Fix: Add user to 'input' group: sudo usermod -aG input \$USER"
    log_msg "Then log out and back in"
    exit 1
fi

# Check for wtype (needed for key injection)
if ! command -v wtype >/dev/null 2>&1; then
    log_msg "WARNING: wtype not found, gestures won't send key events"
fi

log_msg "Starting lisgd..."

exec lisgd -d "$LISGD_DEVICE" \
    -g "1,LR,L,*,R,wtype -k XF86Back" \
    -g "1,RL,R,*,R,wtype -k XF86Forward"
