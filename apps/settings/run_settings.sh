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
WIFI_HELPER="${SCRIPT_DIR}/helpers/wifi-helper.sh"
BT_HELPER="${SCRIPT_DIR}/helpers/bluetooth-helper.sh"
DISPLAY_HELPER="${SCRIPT_DIR}/helpers/display-helper.sh"
SOUND_HELPER="${SCRIPT_DIR}/helpers/sound-helper.sh"
SYSTEM_HELPER="${SCRIPT_DIR}/helpers/system-helper.sh"

# WiFi data files
WIFI_STATUS_FILE="/tmp/flick-wifi-status.json"
WIFI_CONNECTED_FILE="/tmp/flick-wifi-connected.json"
WIFI_NETWORKS_FILE="/tmp/flick-wifi-networks.json"

# Bluetooth data files
BT_STATUS_FILE="/tmp/flick-bt-status.json"
BT_PAIRED_FILE="/tmp/flick-bt-paired.json"
BT_AVAILABLE_FILE="/tmp/flick-bt-available.json"

# Brightness data file
BRIGHTNESS_FILE="/tmp/flick-brightness.json"

# Sound data file
SOUND_FILE="/tmp/flick-sound.json"

# System data files
BATTERY_FILE="/tmp/flick-battery.json"
STORAGE_FILE="/tmp/flick-storage.json"
MEMORY_FILE="/tmp/flick-memory.json"
SYSTEM_FILE="/tmp/flick-system.json"
DATETIME_FILE="/tmp/flick-datetime.json"
NOTIFICATIONS_FILE="/tmp/flick-notifications.json"

# Ensure state directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$LOCK_CONFIG")"

# Clear old log and pending files
> "$LOG_FILE"
rm -f "$PENDING_FILE" "$PATTERN_FILE" "$DISPLAY_PENDING"

# Clean up deep link page file on exit
trap 'rm -f /tmp/flick_settings_page' EXIT

# Function to update WiFi status
update_wifi_status() {
    if [ -x "$WIFI_HELPER" ]; then
        STATUS=$("$WIFI_HELPER" status 2>/dev/null)
        if [ "$STATUS" = "enabled" ]; then
            echo '{"enabled": true}' > "$WIFI_STATUS_FILE"
        else
            echo '{"enabled": false}' > "$WIFI_STATUS_FILE"
        fi
    else
        echo '{"enabled": true}' > "$WIFI_STATUS_FILE"
    fi
}

# Function to update connected network info
update_wifi_connected() {
    if [ -x "$WIFI_HELPER" ]; then
        "$WIFI_HELPER" connected > "$WIFI_CONNECTED_FILE" 2>/dev/null
    else
        echo '{"connected": false}' > "$WIFI_CONNECTED_FILE"
    fi
}

# Function to scan and update available networks
update_wifi_networks() {
    if [ -x "$WIFI_HELPER" ]; then
        "$WIFI_HELPER" scan > "$WIFI_NETWORKS_FILE" 2>/dev/null
    else
        echo '[]' > "$WIFI_NETWORKS_FILE"
    fi
}

# Function to update Bluetooth status
update_bt_status() {
    if [ -x "$BT_HELPER" ]; then
        STATUS=$("$BT_HELPER" status 2>/dev/null)
        if [ "$STATUS" = "enabled" ]; then
            echo '{"enabled": true}' > "$BT_STATUS_FILE"
        else
            echo '{"enabled": false}' > "$BT_STATUS_FILE"
        fi
    else
        echo '{"enabled": true}' > "$BT_STATUS_FILE"
    fi
}

# Function to update paired devices
update_bt_paired() {
    if [ -x "$BT_HELPER" ]; then
        "$BT_HELPER" paired > "$BT_PAIRED_FILE" 2>/dev/null
    else
        echo '[]' > "$BT_PAIRED_FILE"
    fi
}

# Function to update available devices
update_bt_available() {
    if [ -x "$BT_HELPER" ]; then
        "$BT_HELPER" available > "$BT_AVAILABLE_FILE" 2>/dev/null
    else
        echo '[]' > "$BT_AVAILABLE_FILE"
    fi
}

# Function to update brightness data
update_brightness() {
    if [ -x "$DISPLAY_HELPER" ]; then
        BRIGHTNESS_DATA=$("$DISPLAY_HELPER" get 2>/dev/null)
        AUTO_STATUS=$("$DISPLAY_HELPER" auto-get 2>/dev/null)
        # Parse brightness from JSON
        BRIGHTNESS=$(echo "$BRIGHTNESS_DATA" | grep -o '"brightness"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
        if [ -n "$BRIGHTNESS" ]; then
            AUTO_SUPPORTED="false"
            AUTO_ENABLED="false"
            if [ "$AUTO_STATUS" = "enabled" ]; then
                AUTO_SUPPORTED="true"
                AUTO_ENABLED="true"
            elif [ "$AUTO_STATUS" = "disabled" ]; then
                AUTO_SUPPORTED="true"
                AUTO_ENABLED="false"
            fi
            echo "{\"brightness\": $BRIGHTNESS, \"auto_supported\": $AUTO_SUPPORTED, \"auto_enabled\": $AUTO_ENABLED}" > "$BRIGHTNESS_FILE"
        else
            echo '{"brightness": 75, "auto_supported": false, "auto_enabled": false}' > "$BRIGHTNESS_FILE"
        fi
    else
        echo '{"brightness": 75, "auto_supported": false, "auto_enabled": false}' > "$BRIGHTNESS_FILE"
    fi
}

# Function to update sound data
update_sound() {
    if [ -x "$SOUND_HELPER" ]; then
        "$SOUND_HELPER" info > "$SOUND_FILE" 2>/dev/null
    else
        echo '{"volume": 70, "muted": false, "mic_volume": 70, "mic_muted": false}' > "$SOUND_FILE"
    fi
}

# Function to update battery data
update_battery() {
    if [ -x "$SYSTEM_HELPER" ]; then
        "$SYSTEM_HELPER" battery > "$BATTERY_FILE" 2>/dev/null
    else
        echo '{"level": 100, "status": "Unknown", "charging": false, "health": "Good"}' > "$BATTERY_FILE"
    fi
}

# Function to update storage data
update_storage() {
    if [ -x "$SYSTEM_HELPER" ]; then
        "$SYSTEM_HELPER" storage > "$STORAGE_FILE" 2>/dev/null
    else
        echo '{"total_gb": 64, "used_gb": 32, "free_gb": 32, "percent_used": 50}' > "$STORAGE_FILE"
    fi
}

# Function to update memory data
update_memory() {
    if [ -x "$SYSTEM_HELPER" ]; then
        "$SYSTEM_HELPER" memory > "$MEMORY_FILE" 2>/dev/null
    else
        echo '{"total_gb": 4, "used_gb": 2, "percent_used": 50}' > "$MEMORY_FILE"
    fi
}

# Function to update system data
update_system() {
    if [ -x "$SYSTEM_HELPER" ]; then
        "$SYSTEM_HELPER" system > "$SYSTEM_FILE" 2>/dev/null
    else
        echo '{"hostname": "flick", "kernel": "unknown", "arch": "unknown", "uptime": "0m"}' > "$SYSTEM_FILE"
    fi
}

# Function to update datetime data
update_datetime() {
    if [ -x "$SYSTEM_HELPER" ]; then
        "$SYSTEM_HELPER" datetime > "$DATETIME_FILE" 2>/dev/null
    else
        echo '{"timezone": "UTC", "ntp_enabled": true, "time": "00:00", "date": "2024-01-01"}' > "$DATETIME_FILE"
    fi
}

# Initialize notifications config
init_notifications() {
    if [ ! -f "$NOTIFICATIONS_FILE" ]; then
        echo '{"dnd": false, "previews": true, "sound": true, "vibration": true}' > "$NOTIFICATIONS_FILE"
    fi
}

# Create default data files immediately (so QML has something to read)
echo '{"enabled": true}' > "$WIFI_STATUS_FILE"
echo '{"connected": false}' > "$WIFI_CONNECTED_FILE"
echo '[]' > "$WIFI_NETWORKS_FILE"
echo '{"enabled": false}' > "$BT_STATUS_FILE"
echo '[]' > "$BT_PAIRED_FILE"
echo '[]' > "$BT_AVAILABLE_FILE"
echo '{"brightness": 75, "auto_supported": false, "auto_enabled": false}' > "$BRIGHTNESS_FILE"
echo '{"volume": 70, "muted": false, "mic_volume": 70, "mic_muted": false}' > "$SOUND_FILE"
echo '{"level": 100, "status": "Unknown", "charging": false, "health": "Good"}' > "$BATTERY_FILE"
echo '{"total_gb": 64, "used_gb": 32, "free_gb": 32, "percent_used": 50}' > "$STORAGE_FILE"
echo '{"total_gb": 4, "used_gb": 2, "percent_used": 50}' > "$MEMORY_FILE"
echo '{"hostname": "flick", "kernel": "unknown", "arch": "unknown", "uptime": "0m"}' > "$SYSTEM_FILE"
echo '{"date": "", "time": "", "timezone": "UTC", "use_24h": true}' > "$DATETIME_FILE"
echo '{"dnd": false, "previews": true, "sound": true, "vibration": true}' > "$NOTIFICATIONS_FILE"

# Run all data updates in background (QML will see updates when they complete)
echo "Starting background data initialization..." >> "$LOG_FILE"
(
    update_wifi_status
    update_wifi_connected
    update_wifi_networks
    update_bt_status
    update_bt_paired
    update_bt_available
    update_brightness
    update_sound
    update_battery
    update_storage
    update_memory
    update_system
    update_datetime
    init_notifications
) &

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

# Suppress Qt debug output but keep qml messages for config capture
export QT_LOGGING_RULES="qt.qpa.*=false;qt.accessibility.*=false;qml=true"
export QT_MESSAGE_PATTERN=""
# Allow QML to read local files (for config loading)
export QML_XHR_ALLOW_FILE_READ=1
# Force software rendering completely
# export QT_QUICK_BACKEND=software  # Using hardware accel
export QT_OPENGL=software
export QMLSCENE_DEVICE=softwarecontext
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
# Hardware acceleration enabled
# Try wayland-egl integration
export QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=wayland-egl
# Apply text scale factor (default 2.0x if no config)
export QT_SCALE_FACTOR="$TEXT_SCALE"
# Also set font DPI for better text scaling (96 * scale)
export QT_FONT_DPI=$(echo "$TEXT_SCALE * 96" | bc)
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# Run qmlscene and capture output (use stdbuf to prevent buffering)
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$QML_FILE" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
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
    # Helper function to save display config (preserves all fields)
    save_display_config() {
        local new_scale="$1"
        local new_timeout="$2"
        local new_wallpaper="$3"
        local new_accent="$4"

        # Read existing values
        local scale="${new_scale:-2.0}"
        local timeout="${new_timeout:-30}"
        local wallpaper=""
        local accent=""

        # Handle wallpaper: "CLEAR" means explicitly remove, empty means keep existing
        if [ "$new_wallpaper" = "CLEAR" ]; then
            wallpaper=""  # Explicitly clear
        elif [ -n "$new_wallpaper" ]; then
            wallpaper="$new_wallpaper"  # Set new wallpaper
        elif [ -f "$DISPLAY_CONFIG" ]; then
            # Keep existing wallpaper
            wallpaper=$(cat "$DISPLAY_CONFIG" | grep -o '"wallpaper"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
        fi

        # Handle accent color
        if [ -n "$new_accent" ]; then
            accent="$new_accent"
        elif [ -f "$DISPLAY_CONFIG" ]; then
            accent=$(cat "$DISPLAY_CONFIG" | grep -o '"accent_color"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
        fi

        if [ -f "$DISPLAY_CONFIG" ]; then
            [ -z "$new_scale" ] && scale=$(cat "$DISPLAY_CONFIG" | grep -o '"text_scale"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
            [ -z "$new_timeout" ] && timeout=$(cat "$DISPLAY_CONFIG" | grep -o '"screen_timeout"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
        fi

        # Set defaults if empty
        [ -z "$scale" ] && scale="2.0"
        [ -z "$timeout" ] && timeout="30"

        # Build JSON
        local json="{\"text_scale\": $scale, \"screen_timeout\": $timeout"
        [ -n "$wallpaper" ] && json="$json, \"wallpaper\": \"$wallpaper\""
        [ -n "$accent" ] && json="$json, \"accent_color\": \"$accent\""
        json="$json}"
        echo "$json" > "$DISPLAY_CONFIG"
        echo "Display config saved to $DISPLAY_CONFIG" >> "$LOG_FILE"
    }

    # Check for text scale save messages - save immediately
    if [[ "$line" == *"SCALE_SAVE:"* ]]; then
        SCALE=$(echo "$line" | sed 's/.*SCALE_SAVE://')
        echo "Detected text scale change: $SCALE" >> "$LOG_FILE"
        save_display_config "$SCALE" "" ""
    fi
    # Check for timeout save messages - save immediately
    if [[ "$line" == *"TIMEOUT_SAVE:"* ]]; then
        TIMEOUT=$(echo "$line" | sed 's/.*TIMEOUT_SAVE://')
        echo "Detected timeout change: $TIMEOUT" >> "$LOG_FILE"
        save_display_config "" "$TIMEOUT" ""
    fi
    # Check for wallpaper save messages - save immediately
    if [[ "$line" == *"WALLPAPER_SAVE:"* ]]; then
        WALLPAPER=$(echo "$line" | sed 's/.*WALLPAPER_SAVE://')
        echo "Detected wallpaper change: $WALLPAPER" >> "$LOG_FILE"
        save_display_config "" "" "$WALLPAPER" ""
    fi
    # Check for accent color save messages
    if [[ "$line" == *"ACCENT_SAVE:"* ]]; then
        ACCENT=$(echo "$line" | sed 's/.*ACCENT_SAVE://')
        echo "Detected accent color change: $ACCENT" >> "$LOG_FILE"
        save_display_config "" "" "" "$ACCENT"
    fi
    # Check for picker clear command
    if [[ "$line" == *"PICKER_CLEAR:"* ]]; then
        RESULT_FILE=$(echo "$line" | sed 's/.*PICKER_CLEAR://')
        echo "Clearing picker result file: $RESULT_FILE" >> "$LOG_FILE"
        rm -f "$RESULT_FILE"
    fi
    # Check for picker launch command - format: PICKER_LAUNCH:filter:startdir:resultfile
    if [[ "$line" == *"PICKER_LAUNCH:"* ]]; then
        PICKER_ARGS=$(echo "$line" | sed 's/.*PICKER_LAUNCH://')
        FILTER=$(echo "$PICKER_ARGS" | cut -d: -f1)
        START_DIR=$(echo "$PICKER_ARGS" | cut -d: -f2)
        RESULT_FILE=$(echo "$PICKER_ARGS" | cut -d: -f3)
        echo "Launching file picker: filter=$FILTER, start=$START_DIR, result=$RESULT_FILE" >> "$LOG_FILE"
        # Launch the file app in picker mode
        "$SCRIPT_DIR/../files/run_files.sh" --pick --filter="$FILTER" --start-dir="$START_DIR" --result-file="$RESULT_FILE" &
    fi
    # Check for WiFi commands
    if [[ "$line" == *"WIFI_CMD:"* ]]; then
        WIFI_CMD=$(echo "$line" | sed 's/.*WIFI_CMD://')
        echo "Detected WiFi command: $WIFI_CMD" >> "$LOG_FILE"
        case "$WIFI_CMD" in
            enable)
                "$WIFI_HELPER" enable >> "$LOG_FILE" 2>&1
                update_wifi_status
                sleep 1
                update_wifi_connected
                update_wifi_networks &
                ;;
            disable)
                "$WIFI_HELPER" disable >> "$LOG_FILE" 2>&1
                update_wifi_status
                echo '{"connected": false}' > "$WIFI_CONNECTED_FILE"
                echo '[]' > "$WIFI_NETWORKS_FILE"
                ;;
            scan)
                update_wifi_networks &
                ;;
            disconnect)
                "$WIFI_HELPER" disconnect >> "$LOG_FILE" 2>&1
                sleep 1
                update_wifi_connected
                update_wifi_networks &
                ;;
            connect:*)
                # Parse connect:SSID or connect:SSID:PASSWORD
                CONNECT_ARGS="${WIFI_CMD#connect:}"
                SSID="${CONNECT_ARGS%%:*}"
                PASSWORD="${CONNECT_ARGS#*:}"
                if [ "$PASSWORD" = "$SSID" ]; then
                    PASSWORD=""
                fi
                echo "Connecting to '$SSID'" >> "$LOG_FILE"
                if [ -n "$PASSWORD" ]; then
                    "$WIFI_HELPER" connect "$SSID" "$PASSWORD" >> "$LOG_FILE" 2>&1
                else
                    "$WIFI_HELPER" connect "$SSID" >> "$LOG_FILE" 2>&1
                fi
                sleep 2
                update_wifi_connected
                update_wifi_networks &
                ;;
        esac
    fi
    # Check for Bluetooth commands
    if [[ "$line" == *"BT_CMD:"* ]]; then
        BT_CMD=$(echo "$line" | sed 's/.*BT_CMD://')
        echo "Detected Bluetooth command: $BT_CMD" >> "$LOG_FILE"
        case "$BT_CMD" in
            enable)
                "$BT_HELPER" enable >> "$LOG_FILE" 2>&1
                update_bt_status
                sleep 1
                update_bt_paired
                ;;
            disable)
                "$BT_HELPER" disable >> "$LOG_FILE" 2>&1
                update_bt_status
                echo '[]' > "$BT_PAIRED_FILE"
                echo '[]' > "$BT_AVAILABLE_FILE"
                ;;
            scan-start)
                "$BT_HELPER" scan-start >> "$LOG_FILE" 2>&1
                ;;
            scan-stop)
                "$BT_HELPER" scan-stop >> "$LOG_FILE" 2>&1
                update_bt_available
                ;;
            connect:*)
                MAC="${BT_CMD#connect:}"
                echo "Connecting to BT device: $MAC" >> "$LOG_FILE"
                "$BT_HELPER" connect "$MAC" >> "$LOG_FILE" 2>&1
                sleep 2
                update_bt_paired
                ;;
            disconnect:*)
                MAC="${BT_CMD#disconnect:}"
                echo "Disconnecting BT device: $MAC" >> "$LOG_FILE"
                "$BT_HELPER" disconnect "$MAC" >> "$LOG_FILE" 2>&1
                sleep 1
                update_bt_paired
                ;;
            pair:*)
                MAC="${BT_CMD#pair:}"
                echo "Pairing with BT device: $MAC" >> "$LOG_FILE"
                "$BT_HELPER" pair "$MAC" >> "$LOG_FILE" 2>&1
                "$BT_HELPER" trust "$MAC" >> "$LOG_FILE" 2>&1
                sleep 2
                update_bt_paired
                update_bt_available
                ;;
            remove:*)
                MAC="${BT_CMD#remove:}"
                echo "Removing BT device: $MAC" >> "$LOG_FILE"
                "$BT_HELPER" remove "$MAC" >> "$LOG_FILE" 2>&1
                sleep 1
                update_bt_paired
                ;;
        esac
    fi
    # Check for brightness commands
    if [[ "$line" == *"BRIGHTNESS_CMD:"* ]]; then
        BRIGHT_CMD=$(echo "$line" | sed 's/.*BRIGHTNESS_CMD://')
        echo "Detected brightness command: $BRIGHT_CMD" >> "$LOG_FILE"
        case "$BRIGHT_CMD" in
            set:*)
                PERCENT="${BRIGHT_CMD#set:}"
                echo "Setting brightness to $PERCENT%" >> "$LOG_FILE"
                "$DISPLAY_HELPER" set "$PERCENT" >> "$LOG_FILE" 2>&1
                update_brightness
                ;;
            auto:*)
                STATE="${BRIGHT_CMD#auto:}"
                echo "Setting auto-brightness to $STATE" >> "$LOG_FILE"
                "$DISPLAY_HELPER" auto-set "$STATE" >> "$LOG_FILE" 2>&1
                update_brightness
                ;;
        esac
    fi
    # Check for sound commands
    if [[ "$line" == *"SOUND_CMD:"* ]]; then
        SOUND_CMD=$(echo "$line" | sed 's/.*SOUND_CMD://')
        echo "Detected sound command: $SOUND_CMD" >> "$LOG_FILE"
        case "$SOUND_CMD" in
            set-volume:*)
                PERCENT="${SOUND_CMD#set-volume:}"
                echo "Setting volume to $PERCENT%" >> "$LOG_FILE"
                "$SOUND_HELPER" set-volume "$PERCENT" >> "$LOG_FILE" 2>&1
                "$SOUND_HELPER" play-feedback >> "$LOG_FILE" 2>&1
                update_sound
                ;;
            set-mic-volume:*)
                PERCENT="${SOUND_CMD#set-mic-volume:}"
                echo "Setting mic volume to $PERCENT%" >> "$LOG_FILE"
                "$SOUND_HELPER" set-mic-volume "$PERCENT" >> "$LOG_FILE" 2>&1
                update_sound
                ;;
            mute)
                "$SOUND_HELPER" mute >> "$LOG_FILE" 2>&1
                update_sound
                ;;
            unmute)
                "$SOUND_HELPER" unmute >> "$LOG_FILE" 2>&1
                update_sound
                ;;
            mic-mute)
                "$SOUND_HELPER" mic-mute >> "$LOG_FILE" 2>&1
                update_sound
                ;;
            mic-unmute)
                "$SOUND_HELPER" mic-unmute >> "$LOG_FILE" 2>&1
                update_sound
                ;;
        esac
    fi
    # Check for wallpaper color analysis command
    if [[ "$line" == *"ANALYZE_WALLPAPER:"* ]]; then
        WALLPAPER_PATH=$(echo "$line" | sed 's/.*ANALYZE_WALLPAPER://')
        echo "Analyzing wallpaper for accent color: $WALLPAPER_PATH" >> "$LOG_FILE"
        # Run color analysis in background and write result to file
        (
            rm -f /tmp/flick_accent_color.txt
            # Use Python to extract vibrant color
            python3 -c "
import sys
try:
    from PIL import Image
    import colorsys

    img = Image.open('$WALLPAPER_PATH')
    img = img.resize((50, 50))
    img = img.convert('RGB')

    # Count colors with saturation weighting
    color_scores = {}
    for y in range(50):
        for x in range(50):
            r, g, b = img.getpixel((x, y))
            # Convert to HSV
            h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
            # Only consider saturated, mid-brightness colors
            if s > 0.25 and 0.2 < v < 0.95:
                # Quantize to reduce color space
                qr = (r // 32) * 32 + 16
                qg = (g // 32) * 32 + 16
                qb = (b // 32) * 32 + 16
                key = (qr, qg, qb)
                if key not in color_scores:
                    color_scores[key] = {'count': 0, 'sat': 0}
                color_scores[key]['count'] += 1
                color_scores[key]['sat'] = max(color_scores[key]['sat'], s)

    # Find best color
    best_color = None
    best_score = 0
    for color, data in color_scores.items():
        score = data['count'] * data['sat']
        if score > best_score:
            best_score = score
            best_color = color

    if best_color:
        # Boost brightness slightly
        r = min(255, int(best_color[0] * 1.15))
        g = min(255, int(best_color[1] * 1.15))
        b = min(255, int(best_color[2] * 1.15))
        print(f'{r},{g},{b}')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
" > /tmp/flick_accent_color.txt 2>> "$LOG_FILE"
        ) &
    fi
    # Check for security commands (PIN/pattern setup)
    if [[ "$line" == *"SECURITY_CMD:"* ]]; then
        SECURITY_CMD=$(echo "$line" | sed 's/.*SECURITY_CMD://')
        echo "Detected security command: $SECURITY_CMD" >> "$LOG_FILE"
        case "$SECURITY_CMD" in
            set-pin:*)
                PIN="${SECURITY_CMD#set-pin:}"
                echo "Setting PIN (length: ${#PIN})" >> "$LOG_FILE"
                "$SETTINGS_CTL" lock set-pin "$PIN" >> "$LOG_FILE" 2>&1
                ;;
            set-pattern:*)
                PATTERN="${SECURITY_CMD#set-pattern:}"
                echo "Setting pattern: $PATTERN" >> "$LOG_FILE"
                "$SETTINGS_CTL" lock set-pattern "$PATTERN" >> "$LOG_FILE" 2>&1
                ;;
        esac
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

# Display config is saved immediately when changed (no pending file needed)
