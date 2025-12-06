#!/bin/bash
# Flick Compositor Session Installer
# Creates a display manager session entry for Flick compositor
#
# Usage:
#   sudo ./install-session.sh            - Install session
#   sudo ./install-session.sh --uninstall - Remove session

set -e

SESSION_NAME="flick-compositor"
DESKTOP_NAME="Flick (Native)"

# Handle uninstall
if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    echo "Removing Flick compositor session..."
    rm -f /usr/bin/flick-compositor-session
    rm -f /usr/local/bin/flick-compositor
    rm -f /usr/share/wayland-sessions/flick-compositor.desktop
    echo "Flick compositor session removed."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLICK_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[!]${NC} $*"; exit 1; }

# Check for root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo $0"
fi

# Detect the actual user
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    error "Could not determine the actual user. Run with sudo."
fi

log "Installing Flick compositor session for user: $ACTUAL_USER"

# Check if compositor binary exists, build if needed
COMPOSITOR_BIN="$SCRIPT_DIR/target/release/flick"
if [ ! -x "$COMPOSITOR_BIN" ]; then
    log "Building compositor (release mode)..."
    cd "$SCRIPT_DIR"
    sudo -u "$ACTUAL_USER" cargo build --release 2>&1 || error "Failed to build compositor"
fi

if [ ! -x "$COMPOSITOR_BIN" ]; then
    error "Compositor binary not found at $COMPOSITOR_BIN"
fi

log "Found compositor: $COMPOSITOR_BIN"

# Find the Flick shell binary (optional)
SHELL_BIN=""
for path in \
    "$FLICK_ROOT/shell/build/linux/arm64/release/bundle/flick_shell" \
    "$FLICK_ROOT/shell/build/linux/x64/release/bundle/flick_shell" \
    "$FLICK_ROOT/shell/build/linux/arm64/debug/bundle/flick_shell" \
    "$FLICK_ROOT/shell/build/linux/x64/debug/bundle/flick_shell"
do
    if [ -x "$path" ]; then
        SHELL_BIN="$path"
        break
    fi
done

if [ -n "$SHELL_BIN" ]; then
    log "Found Flick shell: $SHELL_BIN"
    SHELL_DIR="$(dirname "$SHELL_BIN")"
else
    warn "Flick shell not found. You can build it with: cd $FLICK_ROOT/shell && flutter build linux"
    warn "The compositor will start without a shell (you can run clients manually)"
fi

# Install compositor binary
log "Installing compositor to /usr/local/bin/..."
cp "$COMPOSITOR_BIN" /usr/local/bin/flick-compositor
chmod +x /usr/local/bin/flick-compositor

# Create session script
log "Creating /usr/bin/flick-compositor-session..."
cat > /usr/bin/flick-compositor-session << 'SESSIONEOF'
#!/bin/sh
# Flick Compositor Session
# Starts the native Flick compositor with optional shell

COMPOSITOR="/usr/local/bin/flick-compositor"
FLICK_SHELL="__SHELL_BIN__"
FLICK_SHELL_DIR="__SHELL_DIR__"
FLICK_ROOT="__FLICK_ROOT__"
LOG_DIR="$HOME/.local/share/flick/logs"
SESSION_LOG="$LOG_DIR/compositor-session.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$SESSION_LOG"
}

log_msg "=== Flick compositor session starting ==="
log_msg "User: $(whoami)"
log_msg "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
log_msg "XDG_SESSION_ID: $XDG_SESSION_ID"

# Export environment
export GTK_THEME="${GTK_THEME:-Adwaita:dark}"
export XDG_CURRENT_DESKTOP="Flick"
export XDG_SESSION_TYPE="wayland"
export XDG_SESSION_DESKTOP="flick"

# Add shell library path if available
if [ -n "$FLICK_SHELL_DIR" ] && [ -d "$FLICK_SHELL_DIR/lib" ]; then
    export LD_LIBRARY_PATH="$FLICK_SHELL_DIR/lib:$LD_LIBRARY_PATH"
fi

# Optional debug file
if [ -f "$HOME/.flickdebug" ]; then
    log_msg "Loading .flickdebug"
    . "$HOME/.flickdebug"
fi

# Track child PIDs for cleanup
LISGD_PID=""

cleanup() {
    log_msg "Cleaning up session..."
    [ -n "$LISGD_PID" ] && kill "$LISGD_PID" 2>/dev/null
    log_msg "=== Flick compositor session ended ==="
    exit 0
}

trap cleanup EXIT INT TERM HUP

# Start lisgd after compositor is ready
start_lisgd_when_ready() {
    # Wait for Wayland socket (up to 10 seconds)
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt 20 ]; do
        for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
            if [ -S "$sock" ]; then
                log_msg "Wayland socket found: $sock"
                break 2
            fi
        done
        sleep 0.5
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    if [ $WAIT_COUNT -ge 20 ]; then
        log_msg "WARNING: Wayland socket not found after 10s"
    fi

    # Find touchscreen device
    LISGD_DEVICE=""
    for dev in /dev/input/event*; do
        if udevadm info --query=property --name="$dev" 2>/dev/null | grep -q "ID_INPUT_TOUCHSCREEN=1"; then
            LISGD_DEVICE="$dev"
            break
        fi
    done

    if [ -z "$LISGD_DEVICE" ]; then
        LISGD_DEVICE=$(ls /dev/input/by-path/*-event-touchscreen 2>/dev/null | head -1)
    fi

    if [ -z "$LISGD_DEVICE" ]; then
        log_msg "No touchscreen device found, skipping lisgd"
        return
    fi

    log_msg "Starting lisgd on $LISGD_DEVICE"

    if [ -x "$FLICK_ROOT/config/lisgd.sh" ]; then
        LISGD_DEVICE="$LISGD_DEVICE" "$FLICK_ROOT/config/lisgd.sh" >> "$LOG_DIR/lisgd.log" 2>&1 &
        LISGD_PID=$!
    elif command -v lisgd >/dev/null 2>&1; then
        lisgd -d "$LISGD_DEVICE" \
            -g "1,LR,L,*,R,wtype -k XF86Back" \
            -g "1,RL,R,*,R,wtype -k XF86Forward" >> "$LOG_DIR/lisgd.log" 2>&1 &
        LISGD_PID=$!
    fi
}

# Activate session once compositor starts
activate_session_once() {
    sleep 2
    if [ -n "$XDG_SESSION_ID" ]; then
        loginctl activate "$XDG_SESSION_ID" 2>/dev/null && \
            log_msg "Activated session $XDG_SESSION_ID"
    fi
}

# Start background helpers
start_lisgd_when_ready &
activate_session_once &

# Determine shell command
SHELL_CMD=""
if [ -n "$FLICK_SHELL" ] && [ -x "$FLICK_SHELL" ]; then
    SHELL_CMD="$FLICK_SHELL"
    log_msg "Will start shell: $SHELL_CMD"
fi

log_msg "Starting Flick compositor..."

# Start compositor
# The compositor will:
# - Use DRM/libinput on real hardware
# - Set WAYLAND_DISPLAY for clients
# - Start the shell if --shell is provided
if [ -n "$SHELL_CMD" ]; then
    "$COMPOSITOR" --shell "$SHELL_CMD" >> "$LOG_DIR/compositor.log" 2>&1
else
    "$COMPOSITOR" >> "$LOG_DIR/compositor.log" 2>&1
fi

EXIT_CODE=$?
log_msg "Compositor exited with code $EXIT_CODE"

# cleanup runs via trap
SESSIONEOF

# Replace placeholders
sed -i "s|__SHELL_BIN__|$SHELL_BIN|g" /usr/bin/flick-compositor-session
sed -i "s|__SHELL_DIR__|$SHELL_DIR|g" /usr/bin/flick-compositor-session
sed -i "s|__FLICK_ROOT__|$FLICK_ROOT|g" /usr/bin/flick-compositor-session
chmod +x /usr/bin/flick-compositor-session

# Create wayland session desktop entry
log "Creating /usr/share/wayland-sessions/flick-compositor.desktop..."
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/flick-compositor.desktop << DESKTOPEOF
[Desktop Entry]
Name=$DESKTOP_NAME
Comment=Flick Mobile Shell (Native Compositor)
Exec=flick-compositor-session
Type=Application
DesktopNames=Flick;
DESKTOPEOF

# Create user log directory
log "Creating log directory..."
sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_HOME/.local/share/flick/logs"

# Add user to input group if not already
if ! groups "$ACTUAL_USER" | grep -q '\binput\b'; then
    log "Adding $ACTUAL_USER to input group..."
    usermod -aG input "$ACTUAL_USER"
    warn "You may need to log out and back in for group changes to take effect"
fi

# Summary
echo ""
log "Installation complete!"
echo ""
echo "Files installed:"
echo "  - /usr/local/bin/flick-compositor"
echo "  - /usr/bin/flick-compositor-session"
echo "  - /usr/share/wayland-sessions/flick-compositor.desktop"
echo ""
echo "You can now select '$DESKTOP_NAME' from your display manager's session menu."
echo ""
echo "To test in windowed mode (requires X11/Wayland):"
echo "  /usr/local/bin/flick-compositor --windowed"
echo ""
echo "Logs will be written to: ~/.local/share/flick/logs/"
echo ""
echo "To uninstall: sudo $SCRIPT_DIR/install-session.sh --uninstall"
