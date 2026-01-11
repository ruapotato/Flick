#!/bin/bash
# Common environment setup for Flick QML apps
# Source this at the top of run scripts: source "$(dirname "$0")/../../lib/flick-env.sh"

# Get the lib directory (where FlickBackend is)
FLICK_LIB_DIR="${FLICK_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}"

# State directory
export FLICK_STATE_DIR="${FLICK_STATE_DIR:-$HOME/.local/state/flick}"
mkdir -p "$FLICK_STATE_DIR"

# QML imports path - add FlickBackend library
export QML2_IMPORT_PATH="${FLICK_LIB_DIR}:${QML2_IMPORT_PATH}"

# Common Qt/QML environment
export QML_XHR_ALLOW_FILE_READ=1
export QT_LOGGING_RULES="qt.qpa.*=false;qt.accessibility.*=false"
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# Load text scale from config
DISPLAY_CONFIG="${FLICK_STATE_DIR}/display_config.json"
TEXT_SCALE="1.0"
if [ -f "$DISPLAY_CONFIG" ]; then
    SAVED_SCALE=$(cat "$DISPLAY_CONFIG" 2>/dev/null | grep -o '"text_scale"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
    if [ -n "$SAVED_SCALE" ]; then
        TEXT_SCALE="$SAVED_SCALE"
    fi
fi
export QT_SCALE_FACTOR="$TEXT_SCALE"

# Function to get screen dimensions (for scaling)
get_screen_size() {
    # Try to get screen size from wlr-randr or similar
    local size=$(wlr-randr 2>/dev/null | grep -oP '\d+x\d+' | head -1)
    if [ -n "$size" ]; then
        echo "$size"
    else
        echo "720x1600"  # Default to reference resolution
    fi
}

# Export screen dimensions
SCREEN_SIZE=$(get_screen_size)
export FLICK_SCREEN_WIDTH="${SCREEN_SIZE%x*}"
export FLICK_SCREEN_HEIGHT="${SCREEN_SIZE#*x}"
