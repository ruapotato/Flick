#!/bin/bash
# System helper script for Flick settings
# Gets battery, storage, system info, date/time

ACTION="$1"
shift

case "$ACTION" in
    battery)
        # Get battery information
        BATTERY_PATH=""
        for path in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1 /sys/class/power_supply/battery /sys/class/power_supply/Battery; do
            if [ -d "$path" ]; then
                BATTERY_PATH="$path"
                break
            fi
        done

        if [ -n "$BATTERY_PATH" ]; then
            CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
            STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
            HEALTH=$(cat "$BATTERY_PATH/health" 2>/dev/null || echo "Unknown")
            VOLTAGE=$(cat "$BATTERY_PATH/voltage_now" 2>/dev/null || echo "0")
            CURRENT=$(cat "$BATTERY_PATH/current_now" 2>/dev/null || echo "0")
            TEMP=$(cat "$BATTERY_PATH/temp" 2>/dev/null || echo "0")

            # Convert voltage from microvolts to volts
            if [ "$VOLTAGE" -gt 0 ]; then
                VOLTAGE_V=$(echo "scale=2; $VOLTAGE / 1000000" | bc 2>/dev/null || echo "0")
            else
                VOLTAGE_V="0"
            fi

            # Convert temp from decidegrees to degrees
            if [ "$TEMP" -gt 0 ]; then
                TEMP_C=$(echo "scale=1; $TEMP / 10" | bc 2>/dev/null || echo "0")
            else
                TEMP_C="0"
            fi

            CHARGING="false"
            [ "$STATUS" = "Charging" ] && CHARGING="true"

            echo "{\"level\": $CAPACITY, \"status\": \"$STATUS\", \"charging\": $CHARGING, \"health\": \"$HEALTH\", \"voltage\": $VOLTAGE_V, \"temperature\": $TEMP_C}"
        else
            # No battery found (desktop/plugged in device)
            echo "{\"level\": 100, \"status\": \"AC Power\", \"charging\": false, \"health\": \"Good\", \"voltage\": 0, \"temperature\": 0, \"no_battery\": true}"
        fi
        ;;

    storage)
        # Get storage information
        ROOT_TOTAL=$(df -B1 / 2>/dev/null | tail -1 | awk '{print $2}')
        ROOT_USED=$(df -B1 / 2>/dev/null | tail -1 | awk '{print $3}')
        ROOT_FREE=$(df -B1 / 2>/dev/null | tail -1 | awk '{print $4}')
        ROOT_PERCENT=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')

        # Convert to GB
        TOTAL_GB=$(echo "scale=1; $ROOT_TOTAL / 1073741824" | bc 2>/dev/null || echo "0")
        USED_GB=$(echo "scale=1; $ROOT_USED / 1073741824" | bc 2>/dev/null || echo "0")
        FREE_GB=$(echo "scale=1; $ROOT_FREE / 1073741824" | bc 2>/dev/null || echo "0")

        # Get home directory usage
        HOME_USED=$(du -sb "$HOME" 2>/dev/null | awk '{print $1}')
        HOME_GB=$(echo "scale=2; $HOME_USED / 1073741824" | bc 2>/dev/null || echo "0")

        echo "{\"total_gb\": $TOTAL_GB, \"used_gb\": $USED_GB, \"free_gb\": $FREE_GB, \"percent_used\": $ROOT_PERCENT, \"home_gb\": $HOME_GB}"
        ;;

    memory)
        # Get RAM information
        MEM_TOTAL=$(free -b | grep Mem | awk '{print $2}')
        MEM_USED=$(free -b | grep Mem | awk '{print $3}')
        MEM_FREE=$(free -b | grep Mem | awk '{print $4}')
        MEM_AVAIL=$(free -b | grep Mem | awk '{print $7}')

        TOTAL_GB=$(echo "scale=2; $MEM_TOTAL / 1073741824" | bc 2>/dev/null || echo "0")
        USED_GB=$(echo "scale=2; $MEM_USED / 1073741824" | bc 2>/dev/null || echo "0")
        AVAIL_GB=$(echo "scale=2; $MEM_AVAIL / 1073741824" | bc 2>/dev/null || echo "0")
        PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

        echo "{\"total_gb\": $TOTAL_GB, \"used_gb\": $USED_GB, \"available_gb\": $AVAIL_GB, \"percent_used\": $PERCENT}"
        ;;

    system)
        # Get system information
        HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
        KERNEL=$(uname -r 2>/dev/null || echo "unknown")
        ARCH=$(uname -m 2>/dev/null || echo "unknown")
        UPTIME_SECS=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')

        # Calculate uptime
        DAYS=$((UPTIME_SECS / 86400))
        HOURS=$(((UPTIME_SECS % 86400) / 3600))
        MINS=$(((UPTIME_SECS % 3600) / 60))

        if [ "$DAYS" -gt 0 ]; then
            UPTIME_STR="${DAYS}d ${HOURS}h ${MINS}m"
        elif [ "$HOURS" -gt 0 ]; then
            UPTIME_STR="${HOURS}h ${MINS}m"
        else
            UPTIME_STR="${MINS}m"
        fi

        # Get OS info
        if [ -f /etc/os-release ]; then
            OS_NAME=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
        else
            OS_NAME="Linux"
        fi

        # Get CPU info
        CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "Unknown")
        CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")

        # Escape quotes in strings
        OS_NAME=$(echo "$OS_NAME" | sed 's/"/\\"/g')
        CPU_MODEL=$(echo "$CPU_MODEL" | sed 's/"/\\"/g')

        echo "{\"hostname\": \"$HOSTNAME\", \"kernel\": \"$KERNEL\", \"arch\": \"$ARCH\", \"uptime\": \"$UPTIME_STR\", \"os\": \"$OS_NAME\", \"cpu\": \"$CPU_MODEL\", \"cores\": $CPU_CORES}"
        ;;

    datetime)
        # Get current date/time settings
        TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")
        NTP_ENABLED=$(timedatectl show --property=NTP --value 2>/dev/null || echo "no")
        CURRENT_TIME=$(date "+%H:%M")
        CURRENT_DATE=$(date "+%Y-%m-%d")
        CURRENT_DAY=$(date "+%A")

        NTP_BOOL="false"
        [ "$NTP_ENABLED" = "yes" ] && NTP_BOOL="true"

        echo "{\"timezone\": \"$TIMEZONE\", \"ntp_enabled\": $NTP_BOOL, \"time\": \"$CURRENT_TIME\", \"date\": \"$CURRENT_DATE\", \"day\": \"$CURRENT_DAY\"}"
        ;;

    set-timezone)
        # Set timezone
        TZ="$1"
        if [ -n "$TZ" ]; then
            sudo timedatectl set-timezone "$TZ" 2>&1
            echo "ok"
        else
            echo "error: no timezone specified"
        fi
        ;;

    set-ntp)
        # Enable/disable NTP
        ENABLED="$1"
        if [ "$ENABLED" = "on" ] || [ "$ENABLED" = "true" ]; then
            sudo timedatectl set-ntp true 2>&1
        else
            sudo timedatectl set-ntp false 2>&1
        fi
        echo "ok"
        ;;

    list-timezones)
        # List available timezones
        timedatectl list-timezones 2>/dev/null | head -100
        ;;

    reboot)
        sudo reboot
        ;;

    poweroff)
        sudo poweroff
        ;;

    *)
        echo "Usage: $0 {battery|storage|memory|system|datetime|set-timezone|set-ntp|list-timezones|reboot|poweroff}"
        exit 1
        ;;
esac
