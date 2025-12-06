#!/bin/bash
# Flick hot-swap script
# Stops Phosh and starts Flick shell without restarting the compositor (Phoc)
#
# Usage:
#   ./flick-swap.sh        - Swap to Flick shell
#   ./flick-swap.sh phosh  - Swap back to Phosh
#
# This works because both Phosh and Flick are just layer-shell clients.
# Phoc (the compositor) keeps running throughout.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLICK_ROOT="${FLICK_ROOT:-$(dirname "$SCRIPT_DIR")}"
LOG_DIR="$HOME/.local/share/flick/logs"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/swap.log"
}

stop_phosh() {
    log "Stopping Phosh..."

    # Mask the session shutdown target to prevent gnome-session from
    # killing the seat when phosh dies
    log "Masking gnome-session-shutdown.target..."
    systemctl --user mask --runtime gnome-session-shutdown.target 2>/dev/null || true

    if pgrep -x phosh > /dev/null; then
        # Send SIGTERM to phosh process directly
        # Don't use systemctl stop because RefuseManualStop=on
        pkill -x phosh
        sleep 0.5
        log "Phosh process stopped"
    else
        log "Phosh not running"
    fi
}

stop_flick() {
    log "Stopping Flick..."
    if pgrep -f flick_shell > /dev/null; then
        pkill -f flick_shell
        sleep 0.5
        log "Flick shell stopped"
    fi
    if pgrep -x lisgd > /dev/null; then
        pkill -x lisgd
        log "lisgd stopped"
    fi
}

start_phosh() {
    log "Starting Phosh..."

    # Unmask the session shutdown target so normal session behavior resumes
    log "Unmasking gnome-session-shutdown.target..."
    systemctl --user unmask gnome-session-shutdown.target 2>/dev/null || true

    # Start phosh directly - the systemd service has RefuseManualStart=on
    # so we need to start the binary directly
    if [ -x /usr/libexec/phosh ]; then
        /usr/libexec/phosh &
        log "Phosh started"
    elif command -v phosh &>/dev/null; then
        phosh &
        log "Phosh started"
    else
        log "ERROR: phosh binary not found"
    fi
}

start_flick() {
    log "Starting Flick shell..."

    # Start lisgd for gestures
    "$SCRIPT_DIR/lisgd.sh" >> "$LOG_DIR/lisgd.log" 2>&1 &
    sleep 0.3
    log "lisgd started"

    # Find and start Flick shell
    local shell_bin=""
    if [ -x "$FLICK_ROOT/shell/build/linux/x64/release/bundle/flick_shell" ]; then
        shell_bin="$FLICK_ROOT/shell/build/linux/x64/release/bundle/flick_shell"
    elif [ -x "$FLICK_ROOT/shell/build/linux/x64/debug/bundle/flick_shell" ]; then
        shell_bin="$FLICK_ROOT/shell/build/linux/x64/debug/bundle/flick_shell"
    elif [ -x "$FLICK_ROOT/shell/build/linux/arm64/release/bundle/flick_shell" ]; then
        shell_bin="$FLICK_ROOT/shell/build/linux/arm64/release/bundle/flick_shell"
    fi

    if [ -z "$shell_bin" ]; then
        log "ERROR: Flick shell not found. Build with: cd $FLICK_ROOT/shell && flutter build linux"
        # Restart phosh as fallback
        start_phosh
        exit 1
    fi

    log "Starting: $shell_bin"

    # Use gnome-session-inhibit to prevent screen blanking/lockscreen
    if command -v gnome-session-inhibit &> /dev/null; then
        log "Using gnome-session-inhibit to prevent screen blanking"
        gnome-session-inhibit --inhibit idle:suspend --reason "Flick shell active" \
            "$shell_bin" >> "$LOG_DIR/shell.log" 2>&1 &
    else
        log "WARNING: gnome-session-inhibit not found, screen may blank"
        "$shell_bin" >> "$LOG_DIR/shell.log" 2>&1 &
    fi

    log "Flick shell started (PID: $!)"

    # Re-activate the session - it may become inactive when phosh dies
    sleep 0.5
    local session_id
    session_id=$(loginctl list-sessions --no-legend | grep "seat0" | grep -v "manager" | awk '{print $1}' | head -1)
    if [ -n "$session_id" ]; then
        log "Activating session $session_id..."
        loginctl activate "$session_id" 2>/dev/null || true
    fi
}

case "${1:-flick}" in
    phosh)
        log "=== Swapping to Phosh ==="
        stop_flick
        start_phosh
        log "=== Swap to Phosh complete ==="
        ;;
    flick|*)
        log "=== Swapping to Flick ==="
        stop_phosh
        start_flick
        log "=== Swap to Flick complete ==="
        ;;
esac
