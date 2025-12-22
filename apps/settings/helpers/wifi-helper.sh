#!/bin/bash
# WiFi helper script for Flick settings
# Uses nmcli to interact with NetworkManager

ACTION="$1"
shift

case "$ACTION" in
    status)
        # Get WiFi radio status
        nmcli radio wifi
        ;;

    enable)
        nmcli radio wifi on
        echo "enabled"
        ;;

    disable)
        nmcli radio wifi off
        echo "disabled"
        ;;

    connected)
        # Get current connection info as JSON
        CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep wlan | head -1)
        if [ -n "$CONN" ]; then
            SSID=$(echo "$CONN" | cut -d: -f1)
            DEVICE=$(echo "$CONN" | cut -d: -f2)
            IP=$(nmcli -t -f IP4.ADDRESS dev show "$DEVICE" 2>/dev/null | head -1 | cut -d: -f2 | cut -d/ -f1)
            SIGNAL=$(nmcli -t -f IN-USE,SIGNAL dev wifi list 2>/dev/null | grep '^\*' | cut -d: -f2)
            echo "{\"connected\": true, \"ssid\": \"$SSID\", \"ip\": \"$IP\", \"signal\": $SIGNAL}"
        else
            echo "{\"connected\": false}"
        fi
        ;;

    scan)
        # Rescan and list available networks as JSON array
        nmcli dev wifi rescan 2>/dev/null
        sleep 1

        # Build JSON output
        OUTPUT="["
        FIRST=true

        # Read networks into a temp file to avoid subshell issues
        TMPFILE=$(mktemp)
        nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null > "$TMPFILE"

        while IFS=: read -r SSID SIGNAL SECURITY; do
            # Skip empty SSIDs
            if [ -n "$SSID" ]; then
                SECURED="false"
                if [ -n "$SECURITY" ] && [ "$SECURITY" != "--" ] && [ "$SECURITY" != "" ]; then
                    SECURED="true"
                fi

                # Default signal to 50 if not a number
                if ! echo "$SIGNAL" | grep -qE '^[0-9]+$'; then
                    SIGNAL=50
                fi

                # Escape quotes and special chars in SSID
                SSID_ESCAPED=$(echo "$SSID" | sed 's/\\/\\\\/g; s/"/\\"/g')

                if [ "$FIRST" = true ]; then
                    FIRST=false
                else
                    OUTPUT="$OUTPUT,"
                fi
                OUTPUT="$OUTPUT{\"ssid\": \"$SSID_ESCAPED\", \"signal\": $SIGNAL, \"secured\": $SECURED}"
            fi
        done < "$TMPFILE"

        rm -f "$TMPFILE"
        echo "$OUTPUT]"
        ;;

    connect)
        # Connect to a network
        SSID="$1"
        PASSWORD="$2"
        if [ -n "$PASSWORD" ]; then
            nmcli dev wifi connect "$SSID" password "$PASSWORD" 2>&1
        else
            nmcli dev wifi connect "$SSID" 2>&1
        fi
        ;;

    disconnect)
        nmcli dev disconnect wlan0 2>&1
        ;;

    forget)
        # Forget a saved network
        SSID="$1"
        nmcli connection delete "$SSID" 2>&1
        ;;

    saved)
        # List saved networks
        echo "["
        FIRST=true
        nmcli -t -f NAME,TYPE connection show | grep wireless | cut -d: -f1 | while read -r NAME; do
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo ","
            fi
            echo "  \"$NAME\""
        done
        echo "]"
        ;;

    *)
        echo "Usage: $0 {status|enable|disable|connected|scan|connect|disconnect|forget|saved}"
        exit 1
        ;;
esac
