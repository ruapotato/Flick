#!/bin/bash
# Sound helper script for Flick settings
# Uses pactl (PulseAudio/PipeWire) for audio control

ACTION="$1"
shift

# Get default sink
get_default_sink() {
    pactl get-default-sink 2>/dev/null
}

# Get default source (microphone)
get_default_source() {
    pactl get-default-source 2>/dev/null
}

case "$ACTION" in
    get-volume)
        # Get current volume as percentage
        SINK=$(get_default_sink)
        if [ -n "$SINK" ]; then
            VOL=$(pactl get-sink-volume "$SINK" 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
            MUTED=$(pactl get-sink-mute "$SINK" 2>/dev/null | grep -o 'yes\|no')
            if [ -n "$VOL" ]; then
                # Cap at 100%
                if [ "$VOL" -gt 100 ]; then
                    VOL=100
                fi
                MUTE_BOOL="false"
                if [ "$MUTED" = "yes" ]; then
                    MUTE_BOOL="true"
                fi
                echo "{\"volume\": $VOL, \"muted\": $MUTE_BOOL}"
            else
                echo "{\"volume\": 70, \"muted\": false}"
            fi
        else
            echo "{\"volume\": 70, \"muted\": false}"
        fi
        ;;

    set-volume)
        # Set volume as percentage
        PERCENT="$1"
        SINK=$(get_default_sink)
        if [ -n "$SINK" ]; then
            # Clamp to 0-100
            if [ "$PERCENT" -lt 0 ]; then
                PERCENT=0
            fi
            if [ "$PERCENT" -gt 100 ]; then
                PERCENT=100
            fi
            pactl set-sink-volume "$SINK" "${PERCENT}%" 2>/dev/null
            echo "ok"
        else
            echo "error: no audio sink"
        fi
        ;;

    mute)
        # Mute audio
        SINK=$(get_default_sink)
        if [ -n "$SINK" ]; then
            pactl set-sink-mute "$SINK" 1 2>/dev/null
            echo "ok"
        else
            echo "error"
        fi
        ;;

    unmute)
        # Unmute audio
        SINK=$(get_default_sink)
        if [ -n "$SINK" ]; then
            pactl set-sink-mute "$SINK" 0 2>/dev/null
            echo "ok"
        else
            echo "error"
        fi
        ;;

    toggle-mute)
        # Toggle mute
        SINK=$(get_default_sink)
        if [ -n "$SINK" ]; then
            pactl set-sink-mute "$SINK" toggle 2>/dev/null
            echo "ok"
        else
            echo "error"
        fi
        ;;

    get-mic-volume)
        # Get microphone volume
        SOURCE=$(get_default_source)
        if [ -n "$SOURCE" ]; then
            VOL=$(pactl get-source-volume "$SOURCE" 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
            MUTED=$(pactl get-source-mute "$SOURCE" 2>/dev/null | grep -o 'yes\|no')
            if [ -n "$VOL" ]; then
                if [ "$VOL" -gt 100 ]; then
                    VOL=100
                fi
                MUTE_BOOL="false"
                if [ "$MUTED" = "yes" ]; then
                    MUTE_BOOL="true"
                fi
                echo "{\"volume\": $VOL, \"muted\": $MUTE_BOOL}"
            else
                echo "{\"volume\": 70, \"muted\": false}"
            fi
        else
            echo "{\"volume\": 70, \"muted\": false}"
        fi
        ;;

    set-mic-volume)
        # Set microphone volume
        PERCENT="$1"
        SOURCE=$(get_default_source)
        if [ -n "$SOURCE" ]; then
            if [ "$PERCENT" -lt 0 ]; then
                PERCENT=0
            fi
            if [ "$PERCENT" -gt 100 ]; then
                PERCENT=100
            fi
            pactl set-source-volume "$SOURCE" "${PERCENT}%" 2>/dev/null
            echo "ok"
        else
            echo "error: no audio source"
        fi
        ;;

    mic-mute)
        # Mute microphone
        SOURCE=$(get_default_source)
        if [ -n "$SOURCE" ]; then
            pactl set-source-mute "$SOURCE" 1 2>/dev/null
            echo "ok"
        else
            echo "error"
        fi
        ;;

    mic-unmute)
        # Unmute microphone
        SOURCE=$(get_default_source)
        if [ -n "$SOURCE" ]; then
            pactl set-source-mute "$SOURCE" 0 2>/dev/null
            echo "ok"
        else
            echo "error"
        fi
        ;;

    list-sinks)
        # List available audio outputs
        echo "["
        FIRST=true
        pactl list sinks short 2>/dev/null | while read -r ID NAME DRIVER STATE; do
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo ","
            fi
            # Get friendly name
            DESC=$(pactl list sinks 2>/dev/null | grep -A 20 "Name: $NAME" | grep "Description:" | head -1 | cut -d: -f2- | xargs)
            if [ -z "$DESC" ]; then
                DESC="$NAME"
            fi
            DEFAULT_SINK=$(get_default_sink)
            IS_DEFAULT="false"
            if [ "$NAME" = "$DEFAULT_SINK" ]; then
                IS_DEFAULT="true"
            fi
            echo "  {\"name\": \"$NAME\", \"description\": \"$DESC\", \"state\": \"$STATE\", \"default\": $IS_DEFAULT}"
        done
        echo "]"
        ;;

    set-default-sink)
        # Set default audio output
        SINK="$1"
        pactl set-default-sink "$SINK" 2>/dev/null
        echo "ok"
        ;;

    info)
        # Get comprehensive audio info
        SINK=$(get_default_sink)
        SOURCE=$(get_default_source)
        VOL=$(pactl get-sink-volume "$SINK" 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
        MUTED=$(pactl get-sink-mute "$SINK" 2>/dev/null | grep -o 'yes\|no')
        MIC_VOL=$(pactl get-source-volume "$SOURCE" 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
        MIC_MUTED=$(pactl get-source-mute "$SOURCE" 2>/dev/null | grep -o 'yes\|no')

        MUTE_BOOL="false"
        [ "$MUTED" = "yes" ] && MUTE_BOOL="true"
        MIC_MUTE_BOOL="false"
        [ "$MIC_MUTED" = "yes" ] && MIC_MUTE_BOOL="true"

        [ -z "$VOL" ] && VOL=70
        [ -z "$MIC_VOL" ] && MIC_VOL=70
        [ "$VOL" -gt 100 ] && VOL=100
        [ "$MIC_VOL" -gt 100 ] && MIC_VOL=100

        echo "{\"volume\": $VOL, \"muted\": $MUTE_BOOL, \"mic_volume\": $MIC_VOL, \"mic_muted\": $MIC_MUTE_BOOL, \"sink\": \"$SINK\", \"source\": \"$SOURCE\"}"
        ;;

    play-feedback)
        # Play a short click/feedback sound for volume change
        # Try various methods - XDG sound theme, canberra, paplay, or generate a beep
        if command -v canberra-gtk-play >/dev/null 2>&1; then
            canberra-gtk-play -i audio-volume-change 2>/dev/null &
        elif command -v paplay >/dev/null 2>&1; then
            # Try to play from common sound locations
            for SOUND in /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga \
                         /usr/share/sounds/ubuntu/stereo/message.ogg \
                         /usr/share/sounds/Yaru/stereo/audio-volume-change.oga \
                         /usr/share/sounds/alsa/Front_Center.wav; do
                if [ -f "$SOUND" ]; then
                    paplay "$SOUND" 2>/dev/null &
                    break
                fi
            done
        fi
        echo "ok"
        ;;

    *)
        echo "Usage: $0 {get-volume|set-volume|mute|unmute|toggle-mute|get-mic-volume|set-mic-volume|mic-mute|mic-unmute|list-sinks|set-default-sink|info|play-feedback}"
        exit 1
        ;;
esac
