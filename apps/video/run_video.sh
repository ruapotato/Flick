#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Enable hardware video decoding via GStreamer/VA-API
export GST_VAAPI_ALL_DRIVERS=1
export LIBVA_DRIVER_NAME=msm
export GST_GL_API=gles2
export GST_GL_PLATFORM=egl

# Create video directories if they don't exist
mkdir -p ~/Videos ~/Movies

/usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml"
