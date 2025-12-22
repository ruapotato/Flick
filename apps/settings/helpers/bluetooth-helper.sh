#!/bin/bash
# Bluetooth helper script for Flick settings
# Uses bluetoothctl to interact with BlueZ

ACTION="$1"
shift

# Get device icon based on class or name
get_device_icon() {
    local NAME="$1"
    local CLASS="$2"
    NAME_LOWER=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')

    if [[ "$NAME_LOWER" == *"airpod"* ]] || [[ "$NAME_LOWER" == *"headphone"* ]] || [[ "$NAME_LOWER" == *"earphone"* ]] || [[ "$NAME_LOWER" == *"earbud"* ]]; then
        echo "headphones"
    elif [[ "$NAME_LOWER" == *"speaker"* ]] || [[ "$NAME_LOWER" == *"stereo"* ]] || [[ "$NAME_LOWER" == *"soundbar"* ]]; then
        echo "speaker"
    elif [[ "$NAME_LOWER" == *"keyboard"* ]]; then
        echo "keyboard"
    elif [[ "$NAME_LOWER" == *"mouse"* ]]; then
        echo "mouse"
    elif [[ "$NAME_LOWER" == *"phone"* ]] || [[ "$NAME_LOWER" == *"iphone"* ]] || [[ "$NAME_LOWER" == *"galaxy"* ]] || [[ "$NAME_LOWER" == *"pixel"* ]]; then
        echo "phone"
    elif [[ "$NAME_LOWER" == *"watch"* ]] || [[ "$NAME_LOWER" == *"band"* ]]; then
        echo "watch"
    elif [[ "$NAME_LOWER" == *"car"* ]] || [[ "$NAME_LOWER" == *"vehicle"* ]]; then
        echo "car"
    elif [[ "$NAME_LOWER" == *"tv"* ]] || [[ "$NAME_LOWER" == *"television"* ]]; then
        echo "tv"
    elif [[ "$NAME_LOWER" == *"laptop"* ]] || [[ "$NAME_LOWER" == *"macbook"* ]]; then
        echo "laptop"
    else
        echo "device"
    fi
}

case "$ACTION" in
    status)
        # Get Bluetooth power status
        STATUS=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
        if [ "$STATUS" = "yes" ]; then
            echo "enabled"
        else
            echo "disabled"
        fi
        ;;

    enable)
        bluetoothctl power on 2>&1
        echo "enabled"
        ;;

    disable)
        bluetoothctl power off 2>&1
        echo "disabled"
        ;;

    paired)
        # List paired devices as JSON array
        OUTPUT="["
        FIRST=true

        # Use temp file to avoid subshell issues
        TMPFILE=$(mktemp)
        bluetoothctl devices Paired 2>/dev/null > "$TMPFILE"

        while read -r LINE; do
            MAC=$(echo "$LINE" | awk '{print $2}')
            NAME=$(echo "$LINE" | cut -d' ' -f3-)
            if [ -n "$MAC" ] && [ -n "$NAME" ]; then
                # Check if connected
                CONNECTED="false"
                INFO=$(bluetoothctl info "$MAC" 2>/dev/null)
                if echo "$INFO" | grep -q "Connected: yes"; then
                    CONNECTED="true"
                fi
                # Get battery if available
                BATTERY=""
                BATT_LINE=$(echo "$INFO" | grep "Battery Percentage")
                if [ -n "$BATT_LINE" ]; then
                    BATTERY=$(echo "$BATT_LINE" | grep -oE '[0-9]+')
                fi
                # Get device type
                ICON=$(get_device_icon "$NAME" "")

                if [ "$FIRST" = true ]; then
                    FIRST=false
                else
                    OUTPUT="$OUTPUT,"
                fi

                NAME_ESCAPED=$(echo "$NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
                if [ -n "$BATTERY" ]; then
                    OUTPUT="$OUTPUT{\"mac\": \"$MAC\", \"name\": \"$NAME_ESCAPED\", \"connected\": $CONNECTED, \"battery\": $BATTERY, \"icon\": \"$ICON\"}"
                else
                    OUTPUT="$OUTPUT{\"mac\": \"$MAC\", \"name\": \"$NAME_ESCAPED\", \"connected\": $CONNECTED, \"icon\": \"$ICON\"}"
                fi
            fi
        done < "$TMPFILE"

        rm -f "$TMPFILE"
        echo "$OUTPUT]"
        ;;

    scan-start)
        # Start scanning for devices
        bluetoothctl --timeout 10 scan on 2>&1 &
        echo "scanning"
        ;;

    scan-stop)
        bluetoothctl scan off 2>&1
        echo "stopped"
        ;;

    available)
        # List available (discovered) devices that aren't paired
        PAIRED=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}')
        OUTPUT="["
        FIRST=true

        # Use temp file to avoid subshell issues
        TMPFILE=$(mktemp)
        bluetoothctl devices 2>/dev/null > "$TMPFILE"

        while read -r LINE; do
            MAC=$(echo "$LINE" | awk '{print $2}')
            NAME=$(echo "$LINE" | cut -d' ' -f3-)
            # Skip if paired or no name
            if [ -n "$MAC" ] && [ -n "$NAME" ] && [ "$NAME" != "$MAC" ]; then
                IS_PAIRED=false
                for P in $PAIRED; do
                    if [ "$P" = "$MAC" ]; then
                        IS_PAIRED=true
                        break
                    fi
                done
                if [ "$IS_PAIRED" = false ]; then
                    ICON=$(get_device_icon "$NAME" "")
                    if [ "$FIRST" = true ]; then
                        FIRST=false
                    else
                        OUTPUT="$OUTPUT,"
                    fi
                    NAME_ESCAPED=$(echo "$NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    OUTPUT="$OUTPUT{\"mac\": \"$MAC\", \"name\": \"$NAME_ESCAPED\", \"icon\": \"$ICON\"}"
                fi
            fi
        done < "$TMPFILE"

        rm -f "$TMPFILE"
        echo "$OUTPUT]"
        ;;

    connect)
        # Connect to a paired device
        MAC="$1"
        bluetoothctl connect "$MAC" 2>&1
        ;;

    disconnect)
        # Disconnect from a device
        MAC="$1"
        bluetoothctl disconnect "$MAC" 2>&1
        ;;

    pair)
        # Pair with a new device
        MAC="$1"
        bluetoothctl pair "$MAC" 2>&1
        ;;

    trust)
        # Trust a device (auto-connect)
        MAC="$1"
        bluetoothctl trust "$MAC" 2>&1
        ;;

    remove)
        # Remove/forget a paired device
        MAC="$1"
        bluetoothctl remove "$MAC" 2>&1
        ;;

    *)
        echo "Usage: $0 {status|enable|disable|paired|scan-start|scan-stop|available|connect|disconnect|pair|trust|remove}"
        exit 1
        ;;
esac
