#!/bin/bash
# Install Flick as a systemd service
# This replaces greetd/phosh as the display manager

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

# Get the actual user
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    ACTUAL_UID=$(id -u "$SUDO_USER")
else
    echo "Could not determine user. Run with sudo."
    exit 1
fi

echo "=== Installing Flick systemd service ==="

# Check that flick binary exists
if [ ! -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
    echo "ERROR: Flick binary not found!"
    echo "Build it first: cd $SCRIPT_DIR && ./install-mobian.sh"
    exit 1
fi

# Ensure seatd is installed and enabled
if ! command -v seatd &> /dev/null; then
    echo "Installing seatd..."
    apt install -y seatd
fi
systemctl enable seatd
systemctl start seatd

# Add user to video group if needed
if ! groups "$ACTUAL_USER" | grep -q video; then
    echo "Adding $ACTUAL_USER to video group..."
    usermod -aG video "$ACTUAL_USER"
fi

# Create service file with correct paths
cat > /etc/systemd/system/flick.service << EOF
[Unit]
Description=Flick Mobile Shell
After=systemd-user-sessions.service seatd.service
Requires=seatd.service
Conflicts=greetd.service phosh.service

[Service]
Type=simple

# Switch VT as root before starting
ExecStartPre=+/usr/bin/chvt 2

# Run Flick directly - it will connect to the existing seatd
ExecStart=$SCRIPT_DIR/shell/target/release/flick
User=$ACTUAL_USER
StandardOutput=journal
StandardError=journal

# Environment for DRM/Wayland
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Flick
Environment=XDG_SEAT=seat0
Environment=XDG_VTNR=2
Environment=HOME=$ACTUAL_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$ACTUAL_UID
Environment=LIBSEAT_BACKEND=seatd

Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
Alias=display-manager.service
EOF

# Reload systemd
systemctl daemon-reload

echo ""
echo "=== Flick service installed ==="
echo ""
echo "To start Flick (this will stop greetd/phosh):"
echo "  sudo systemctl stop greetd"
echo "  sudo systemctl start flick"
echo ""
echo "To make Flick start on boot:"
echo "  sudo systemctl disable greetd"
echo "  sudo systemctl enable flick"
echo ""
echo "To switch back to Phosh:"
echo "  sudo systemctl stop flick"
echo "  sudo systemctl disable flick"
echo "  sudo systemctl enable greetd"
echo "  sudo systemctl start greetd"
echo ""
