#!/bin/bash
# Wrapper script for QML settings app

SCRIPT_DIR="$(dirname "$0")"
QML_FILE="${SCRIPT_DIR}/main.qml"
LOG_FILE="${HOME}/.local/state/flick/qml_settings.log"
LOCK_CONFIG="${HOME}/.local/state/flick/lock_config.json"
DISPLAY_CONFIG="${HOME}/.local/state/flick/display_config.json"
PENDING_FILE="/tmp/flick-lock-config-pending"
PATTERN_FILE="/tmp/flick-pattern-pending"
DISPLAY_PENDING="/tmp/flick-display-config-pending"
SETTINGS_CTL="${SCRIPT_DIR}/flick-settings-ctl"

# Ensure state directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$LOCK_CONFIG")"

# Clear old log and pending files
> "$LOG_FILE"
rm -f "$PENDING_FILE" "$PATTERN_FILE" "$DISPLAY_PENDING"

echo "Starting QML settings, QML_FILE=$QML_FILE" >> "$LOG_FILE"

# Read text scale from display config (default 2.0)
TEXT_SCALE="2.0"
if [ -f "$DISPLAY_CONFIG" ]; then
    SAVED_SCALE=$(cat "$DISPLAY_CONFIG" | grep -o '"text_scale"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
    if [ -n "$SAVED_SCALE" ]; then
        TEXT_SCALE="$SAVED_SCALE"
    fi
fi
echo "Using text scale: $TEXT_SCALE" >> "$LOG_FILE"

# Suppress Qt debug output (can corrupt terminal)
export QT_LOGGING_RULES="*.debug=false;qt.qpa.*=false;qt.accessibility.*=false"
export QT_MESSAGE_PATTERN=""
# Force software rendering completely
export QT_QUICK_BACKEND=software
export QT_OPENGL=software
export QMLSCENE_DEVICE=softwarecontext
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export LIBGL_ALWAYS_SOFTWARE=1
# Try wayland-egl integration
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
# Apply text scale factor (default 2.0x if no config)
export QT_SCALE_FACTOR="$TEXT_SCALE"
# Also set font DPI for better text scaling (96 * scale)
export QT_FONT_DPI=$(echo "$TEXT_SCALE * 96" | bc)
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# Run qmlscene and capture output
/usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | tee -a "$LOG_FILE" | while read line; do
    # Check for lock config save messages
    if [[ "$line" == *"Saving lock method:"* ]]; then
        METHOD=$(echo "$line" | sed 's/.*Saving lock method: //')
        echo "Detected lock method change: $METHOD" >> "$LOG_FILE"
        echo "$METHOD" > "$PENDING_FILE"
    fi
    # Check for pattern save messages
    if [[ "$line" == *"Saving pattern:"* ]]; then
        PATTERN=$(echo "$line" | sed 's/.*Saving pattern: //')
        echo "Detected pattern save: $PATTERN" >> "$LOG_FILE"
        echo "$PATTERN" > "$PATTERN_FILE"
    fi
    # Check for text scale save messages
    if [[ "$line" == *"Saving text scale:"* ]]; then
        SCALE=$(echo "$line" | sed 's/.*Saving text scale: //')
        echo "Detected text scale change: $SCALE" >> "$LOG_FILE"
        echo "$SCALE" > "$DISPLAY_PENDING"
    fi
done
EXIT_CODE=${PIPESTATUS[0]}

echo "QML settings exited with code $EXIT_CODE" >> "$LOG_FILE"

# Process any pending pattern config first (has higher priority)
if [ -f "$PATTERN_FILE" ]; then
    PATTERN=$(cat "$PATTERN_FILE")
    if [ -n "$PATTERN" ]; then
        echo "Applying pending pattern: $PATTERN" >> "$LOG_FILE"
        if [ -x "$SETTINGS_CTL" ]; then
            "$SETTINGS_CTL" lock set-pattern "$PATTERN" >> "$LOG_FILE" 2>&1
            echo "Pattern saved via flick-settings-ctl" >> "$LOG_FILE"
        else
            echo "ERROR: flick-settings-ctl not found or not executable" >> "$LOG_FILE"
        fi
    fi
    rm -f "$PATTERN_FILE" "$PENDING_FILE"
# Process any pending lock config (non-pattern methods)
elif [ -f "$PENDING_FILE" ]; then
    METHOD=$(cat "$PENDING_FILE")
    if [ -n "$METHOD" ]; then
        echo "Applying pending lock method: $METHOD" >> "$LOG_FILE"
        echo "{\"method\": \"$METHOD\"}" > "$LOCK_CONFIG"
        echo "Lock config saved to $LOCK_CONFIG" >> "$LOG_FILE"
    fi
    rm -f "$PENDING_FILE"
fi

# Process any pending display config
if [ -f "$DISPLAY_PENDING" ]; then
    SCALE=$(cat "$DISPLAY_PENDING")
    if [ -n "$SCALE" ]; then
        echo "Applying pending text scale: $SCALE" >> "$LOG_FILE"
        echo "{\"text_scale\": $SCALE}" > "$DISPLAY_CONFIG"
        echo "Display config saved to $DISPLAY_CONFIG" >> "$LOG_FILE"
    fi
    rm -f "$DISPLAY_PENDING"
fi
