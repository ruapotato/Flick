#!/bin/bash
# Flick Session Installer
# Creates a new display manager session entry for Flick shell
#
# Usage:
#   sudo ./install-session.sh            - Install Flick session
#   sudo ./install-session.sh --uninstall - Remove Flick session

set -e

# Handle uninstall
if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    echo "Removing Flick session..."
    rm -f /usr/bin/flick-session
    rm -f /usr/share/wayland-sessions/flick.desktop
    rm -rf /etc/flick
    echo "Flick session removed."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLICK_ROOT="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[!]${NC} $*"; exit 1; }

# Check for root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo $0"
fi

# Detect the actual user (not root)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    error "Could not determine the actual user. Run with sudo."
fi

log "Installing Flick session for user: $ACTUAL_USER"

# Find the Flick shell binary
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

if [ -z "$SHELL_BIN" ]; then
    error "Flick shell binary not found. Build it first with:
    cd $FLICK_ROOT/shell && flutter build linux"
fi

log "Found Flick shell: $SHELL_BIN"
SHELL_DIR="$(dirname "$SHELL_BIN")"

# Check for phoc (compositor)
if ! command -v phoc &>/dev/null; then
    error "phoc compositor not found. Install it first."
fi

# Create flick-session script
log "Creating /usr/bin/flick-session..."
cat > /usr/bin/flick-session << 'SESSIONEOF'
#!/bin/sh
# Flick Session - starts phoc compositor with Flick shell

COMPOSITOR="/usr/bin/phoc"
PHOC_INI="/etc/flick/phoc.ini"
FLICK_SHELL="__SHELL_BIN__"
FLICK_SHELL_DIR="__SHELL_DIR__"
FLICK_ROOT="__FLICK_ROOT__"
LOG_DIR="$HOME/.local/share/flick/logs"
SESSION_LOG="$LOG_DIR/session.log"

# Fallback to system phoc.ini if flick one doesn't exist
if [ ! -f "$PHOC_INI" ]; then
    if [ -f /etc/phosh/phoc.ini ]; then
        PHOC_INI=/etc/phosh/phoc.ini
    elif [ -f /usr/share/phosh/phoc.ini ]; then
        PHOC_INI=/usr/share/phosh/phoc.ini
    fi
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$SESSION_LOG"
}

log_msg "=== Flick session starting ==="
log_msg "FLICK_SHELL: $FLICK_SHELL"
log_msg "PHOC_INI: $PHOC_INI"

# Export environment for Flutter/GTK
export GTK_THEME="${GTK_THEME:-Adwaita:dark}"
export LD_LIBRARY_PATH="$FLICK_SHELL_DIR/lib:$LD_LIBRARY_PATH"

# WLR backend configuration
[ -n "$WLR_BACKENDS" ] || WLR_BACKENDS=drm,libinput
export WLR_BACKENDS

# Optional debug file
if [ -f "$HOME/.flickdebug" ]; then
    log_msg "Loading .flickdebug"
    . "$HOME/.flickdebug"
fi

# Use systemd-cat for logging if available
SYSTEMD_CAT=""
if command -v systemd-cat >/dev/null 2>&1; then
    SYSTEMD_CAT="systemd-cat -t phoc"
fi

# Track child PIDs for cleanup
LISGD_PID=""

cleanup() {
    log_msg "Cleaning up session..."
    [ -n "$LISGD_PID" ] && kill "$LISGD_PID" 2>/dev/null
    log_msg "=== Flick session ended ==="
    exit 0
}

# Trap signals for clean shutdown
trap cleanup EXIT INT TERM HUP

# Start lisgd after compositor is ready
# This runs as a background process that waits for WAYLAND_DISPLAY
start_lisgd_when_ready() {
    # Wait for Wayland socket to exist (up to 10 seconds)
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt 20 ]; do
        if [ -S "$XDG_RUNTIME_DIR/wayland-0" ] || [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
            break
        fi
        sleep 0.5
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    if [ $WAIT_COUNT -ge 20 ]; then
        log_msg "WARNING: Wayland socket not found after 10s, starting lisgd anyway"
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
        # Try by-path symlink
        LISGD_DEVICE=$(ls /dev/input/by-path/*-event-touchscreen 2>/dev/null | head -1)
    fi

    if [ -z "$LISGD_DEVICE" ]; then
        log_msg "WARNING: No touchscreen device found, skipping lisgd"
        return
    fi

    log_msg "Starting lisgd on $LISGD_DEVICE"

    # Use the lisgd.sh script if available, otherwise start directly
    if [ -x "$FLICK_ROOT/config/lisgd.sh" ]; then
        LISGD_DEVICE="$LISGD_DEVICE" "$FLICK_ROOT/config/lisgd.sh" >> "$LOG_DIR/lisgd.log" 2>&1 &
        LISGD_PID=$!
    elif command -v lisgd >/dev/null 2>&1; then
        lisgd -d "$LISGD_DEVICE" \
            -g "1,LR,L,*,R,wtype -k XF86Back" \
            -g "1,RL,R,*,R,wtype -k XF86Forward" >> "$LOG_DIR/lisgd.log" 2>&1 &
        LISGD_PID=$!
    else
        log_msg "WARNING: lisgd not found"
    fi

    log_msg "lisgd started (PID: $LISGD_PID)"
}

# Start lisgd in background (it will wait for Wayland)
start_lisgd_when_ready &

# One-shot session activation after compositor starts
activate_session_once() {
    sleep 2
    if [ -n "$XDG_SESSION_ID" ]; then
        loginctl activate "$XDG_SESSION_ID" 2>/dev/null && \
            log_msg "Activated session $XDG_SESSION_ID"
    fi
}
activate_session_once &

log_msg "Starting phoc compositor..."

# Start phoc with Flick shell
# When phoc exits (crash or normal), the session ends cleanly
if [ -n "$SYSTEMD_CAT" ]; then
    $SYSTEMD_CAT "${COMPOSITOR}" -S -C "${PHOC_INI}" -E "$FLICK_SHELL"
else
    "${COMPOSITOR}" -S -C "${PHOC_INI}" -E "$FLICK_SHELL" 2>&1 | tee -a "$LOG_DIR/phoc.log"
fi

PHOC_EXIT=$?
log_msg "phoc exited with code $PHOC_EXIT"

# cleanup runs via trap
SESSIONEOF

# Replace placeholders with actual paths
sed -i "s|__SHELL_BIN__|$SHELL_BIN|g" /usr/bin/flick-session
sed -i "s|__SHELL_DIR__|$SHELL_DIR|g" /usr/bin/flick-session
sed -i "s|__FLICK_ROOT__|$FLICK_ROOT|g" /usr/bin/flick-session
chmod +x /usr/bin/flick-session

# Create config directory
log "Creating /etc/flick/..."
mkdir -p /etc/flick

# Copy phoc.ini if it doesn't exist
if [ ! -f /etc/flick/phoc.ini ]; then
    if [ -f /etc/phosh/phoc.ini ]; then
        cp /etc/phosh/phoc.ini /etc/flick/phoc.ini
        log "Copied phoc.ini from /etc/phosh/"
    elif [ -f /usr/share/phosh/phoc.ini ]; then
        cp /usr/share/phosh/phoc.ini /etc/flick/phoc.ini
        log "Copied phoc.ini from /usr/share/phosh/"
    else
        warn "No phoc.ini found to copy. You may need to create /etc/flick/phoc.ini"
    fi
fi

# Create wayland session desktop entry
log "Creating /usr/share/wayland-sessions/flick.desktop..."
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/flick.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Flick
Comment=Flick Mobile Shell
Exec=flick-session
Type=Application
DesktopNames=Flick;GNOME;
DESKTOPEOF

# Create user log directory
log "Creating log directory..."
sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_HOME/.local/share/flick/logs"

# Summary
echo ""
log "Installation complete!"
echo ""
echo "Files created:"
echo "  - /usr/bin/flick-session"
echo "  - /usr/share/wayland-sessions/flick.desktop"
echo "  - /etc/flick/phoc.ini"
echo ""
echo "You can now select 'Flick' from your display manager's session menu."
echo ""
echo "To uninstall, run: sudo $FLICK_ROOT/install-session.sh --uninstall"
