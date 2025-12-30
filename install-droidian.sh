#!/bin/bash
# Install Flick as a systemd service on Droidian
# This replaces Phosh as the display shell
#
# Usage: sudo ./install-droidian.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$SCRIPT_DIR/config/systemd"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

# Get the droidian user's UID (usually 32011 on Droidian)
DROIDIAN_UID=$(id -u droidian 2>/dev/null || echo "32011")
DROIDIAN_HOME=$(getent passwd droidian | cut -d: -f6)

echo "=== Installing Flick on Droidian ==="
echo "User: droidian (UID: $DROIDIAN_UID)"
echo "Home: $DROIDIAN_HOME"
echo ""

# Check that flick binary exists
if [ ! -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
    echo "ERROR: Flick binary not found!"
    echo "Build it first: cd $SCRIPT_DIR/shell && cargo build --release"
    exit 1
fi

# Fix any root-owned files in the state directory
echo "Fixing state directory permissions..."
STATE_DIR="$DROIDIAN_HOME/.local/state/flick"
if [ -d "$STATE_DIR" ]; then
    chown -R droidian:droidian "$STATE_DIR"
fi
mkdir -p "$STATE_DIR"
chown droidian:droidian "$STATE_DIR"

# Update service files with correct UID
echo "Installing systemd services..."
sed "s/32011/$DROIDIAN_UID/g" "$SERVICE_DIR/flick.service" > /etc/systemd/system/flick.service
sed "s/32011/$DROIDIAN_UID/g" "$SERVICE_DIR/flick-messaging.service" > /etc/systemd/system/flick-messaging.service
cp "$SERVICE_DIR/flick-phone-helper.service" /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

echo ""
echo "=== Flick services installed ==="
echo ""
echo "Services created:"
echo "  - flick.service (main compositor)"
echo "  - flick-phone-helper.service (phone/oFono daemon)"
echo "  - flick-messaging.service (SMS daemon)"
echo ""
echo "To start Flick (this will stop Phosh):"
echo "  sudo systemctl stop phosh"
echo "  sudo systemctl start flick flick-phone-helper flick-messaging"
echo ""
echo "To make Flick start on boot instead of Phosh:"
echo "  sudo systemctl disable phosh"
echo "  sudo systemctl enable flick flick-phone-helper flick-messaging"
echo ""
echo "To switch back to Phosh:"
echo "  sudo systemctl stop flick flick-phone-helper flick-messaging"
echo "  sudo systemctl disable flick flick-phone-helper flick-messaging"
echo "  sudo systemctl enable phosh"
echo "  sudo systemctl start phosh"
echo ""
echo "View logs with:"
echo "  journalctl -u flick -f"
echo "  journalctl -u flick-phone-helper -f"
echo "  journalctl -u flick-messaging -f"
echo ""
