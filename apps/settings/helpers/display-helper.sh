#!/bin/bash
# Display helper script for Flick settings
# Controls screen brightness via sysfs

ACTION="$1"
shift

# Find the backlight device
find_backlight() {
    # Try common backlight paths
    for path in \
        /sys/class/backlight/panel0-backlight \
        /sys/class/backlight/backlight \
        /sys/class/backlight/intel_backlight \
        /sys/class/backlight/amdgpu_bl0 \
        /sys/class/backlight/acpi_video0 \
        /sys/class/backlight/*; do
        if [ -d "$path" ] && [ -f "$path/brightness" ]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

BACKLIGHT_PATH=$(find_backlight)

case "$ACTION" in
    get)
        # Get current brightness as percentage (0-100)
        if [ -n "$BACKLIGHT_PATH" ]; then
            CURRENT=$(cat "$BACKLIGHT_PATH/brightness" 2>/dev/null)
            MAX=$(cat "$BACKLIGHT_PATH/max_brightness" 2>/dev/null)
            if [ -n "$CURRENT" ] && [ -n "$MAX" ] && [ "$MAX" -gt 0 ]; then
                PERCENT=$((CURRENT * 100 / MAX))
                echo "{\"brightness\": $PERCENT, \"path\": \"$BACKLIGHT_PATH\"}"
            else
                echo "{\"brightness\": 75, \"error\": \"Could not read brightness\"}"
            fi
        else
            echo "{\"brightness\": 75, \"error\": \"No backlight found\"}"
        fi
        ;;

    set)
        # Set brightness as percentage (0-100)
        PERCENT="$1"
        if [ -n "$BACKLIGHT_PATH" ]; then
            MAX=$(cat "$BACKLIGHT_PATH/max_brightness" 2>/dev/null)
            if [ -n "$MAX" ] && [ "$MAX" -gt 0 ]; then
                # Ensure minimum brightness of 5%
                if [ "$PERCENT" -lt 5 ]; then
                    PERCENT=5
                fi
                if [ "$PERCENT" -gt 100 ]; then
                    PERCENT=100
                fi
                VALUE=$((PERCENT * MAX / 100))
                echo "$VALUE" > "$BACKLIGHT_PATH/brightness" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "ok"
                else
                    # Try with sudo/pkexec if direct write fails
                    echo "$VALUE" | sudo tee "$BACKLIGHT_PATH/brightness" > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        echo "ok"
                    else
                        echo "error: permission denied"
                    fi
                fi
            else
                echo "error: could not read max brightness"
            fi
        else
            echo "error: no backlight found"
        fi
        ;;

    info)
        # Get detailed backlight info
        if [ -n "$BACKLIGHT_PATH" ]; then
            CURRENT=$(cat "$BACKLIGHT_PATH/brightness" 2>/dev/null)
            MAX=$(cat "$BACKLIGHT_PATH/max_brightness" 2>/dev/null)
            TYPE=$(cat "$BACKLIGHT_PATH/type" 2>/dev/null)
            echo "{\"path\": \"$BACKLIGHT_PATH\", \"current\": $CURRENT, \"max\": $MAX, \"type\": \"$TYPE\"}"
        else
            echo "{\"error\": \"No backlight found\"}"
        fi
        ;;

    auto-get)
        # Check if auto-brightness is enabled (ambient light sensor)
        # This is device-specific, check common paths
        if [ -f /sys/class/backlight/*/auto ]; then
            AUTO=$(cat /sys/class/backlight/*/auto 2>/dev/null | head -1)
            if [ "$AUTO" = "1" ]; then
                echo "enabled"
            else
                echo "disabled"
            fi
        else
            echo "unsupported"
        fi
        ;;

    auto-set)
        # Enable/disable auto-brightness
        ENABLED="$1"
        if [ -f /sys/class/backlight/*/auto ]; then
            if [ "$ENABLED" = "on" ] || [ "$ENABLED" = "1" ]; then
                echo "1" > /sys/class/backlight/*/auto 2>/dev/null
            else
                echo "0" > /sys/class/backlight/*/auto 2>/dev/null
            fi
            echo "ok"
        else
            echo "unsupported"
        fi
        ;;

    *)
        echo "Usage: $0 {get|set|info|auto-get|auto-set}"
        exit 1
        ;;
esac
