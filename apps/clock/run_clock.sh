#!/bin/bash
SCRIPT_DIR="/home/furios/flick-phosh/Flick/apps/clock"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

mkdir -p ~/.local/state/flick

/usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml"
