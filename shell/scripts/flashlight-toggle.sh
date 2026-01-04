#!/bin/bash
# Flashlight toggle helper - runs as user with proper dbus session
# Called by flick shell via: sudo -u furios /path/to/flashlight-toggle.sh [on|off|toggle|status]

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

SERVICE="io.furios.Flashlightd"
PATH_OBJ="/io/furios/Flashlightd"
IFACE="io.furios.Flashlightd"

# Ensure flashlightd is running
if ! busctl --user status "$SERVICE" &>/dev/null; then
    /usr/libexec/flashlightd &
    sleep 0.5
fi

get_brightness() {
    busctl --user get-property "$SERVICE" "$PATH_OBJ" "$IFACE" Brightness 2>/dev/null | awk '{print $2}'
}

get_max() {
    busctl --user get-property "$SERVICE" "$PATH_OBJ" "$IFACE" MaxBrightness 2>/dev/null | awk '{print $2}'
}

set_brightness() {
    busctl --user call "$SERVICE" "$PATH_OBJ" "$IFACE" SetBrightness u "$1" 2>/dev/null
}

case "${1:-toggle}" in
    on)
        max=$(get_max)
        set_brightness "${max:-31}"
        echo "on"
        ;;
    off)
        set_brightness 0
        echo "off"
        ;;
    toggle)
        current=$(get_brightness)
        if [ "${current:-0}" -gt 0 ]; then
            set_brightness 0
            echo "off"
        else
            max=$(get_max)
            set_brightness "${max:-31}"
            echo "on"
        fi
        ;;
    status)
        current=$(get_brightness)
        if [ "${current:-0}" -gt 0 ]; then
            echo "on"
        else
            echo "off"
        fi
        ;;
    *)
        echo "Usage: $0 [on|off|toggle|status]"
        exit 1
        ;;
esac
