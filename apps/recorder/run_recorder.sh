#!/bin/bash
# Flick Recorder - Audio recording app for Flick shell

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/home/droidian/.local/state/flick"
RECORDINGS_DIR="/home/droidian/Recordings"
LOG_FILE="${STATE_DIR}/recorder.log"
CMD_FILE="/tmp/flick_recorder_cmd"
STATUS_FILE="/tmp/flick_recorder_status"

mkdir -p "$STATE_DIR"
mkdir -p "$RECORDINGS_DIR"

log() {
    echo "$(date '+%H:%M:%S') $1" >> "$LOG_FILE"
}

log "=== Flick Recorder started ==="

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

# Clean up any stale files
rm -f "$CMD_FILE" "$STATUS_FILE"
echo "idle" > "$STATUS_FILE"

# Background command processor
(
    recording_pid=""
    playback_pid=""

    while true; do
        if [ -f "$CMD_FILE" ]; then
            cmd=$(cat "$CMD_FILE")
            rm -f "$CMD_FILE"
            log "Processing command: $cmd"

            case "$cmd" in
                START:*)
                    file="${cmd#START:}"
                    log "Starting recording to: $file"

                    # Kill any existing recording
                    [ -n "$recording_pid" ] && kill $recording_pid 2>/dev/null

                    # Start recording
                    echo "recording" > "$STATUS_FILE"
                    if command -v pw-record &> /dev/null; then
                        pw-record --format=s16 --rate=44100 --channels=1 "$file" &
                        recording_pid=$!
                    elif command -v parecord &> /dev/null; then
                        parecord --format=s16le --rate=44100 --channels=1 "$file" &
                        recording_pid=$!
                    else
                        arecord -f S16_LE -r 44100 -c 1 "$file" &
                        recording_pid=$!
                    fi
                    log "Recording PID: $recording_pid"
                    ;;

                STOP)
                    log "Stopping recording"
                    if [ -n "$recording_pid" ]; then
                        kill -INT $recording_pid 2>/dev/null
                        wait $recording_pid 2>/dev/null
                        recording_pid=""
                        log "Recording stopped"
                    fi
                    echo "idle" > "$STATUS_FILE"
                    ;;

                PLAY:*)
                    file="${cmd#PLAY:}"
                    log "Playing: $file"

                    # Kill any existing playback
                    [ -n "$playback_pid" ] && kill $playback_pid 2>/dev/null

                    echo "playing" > "$STATUS_FILE"
                    (
                        if command -v pw-play &> /dev/null; then
                            pw-play "$file"
                        elif command -v paplay &> /dev/null; then
                            paplay "$file"
                        else
                            aplay "$file"
                        fi
                        echo "idle" > "$STATUS_FILE"
                    ) &
                    playback_pid=$!
                    log "Playback PID: $playback_pid"
                    ;;

                STOPPLAY)
                    log "Stopping playback"
                    [ -n "$playback_pid" ] && kill $playback_pid 2>/dev/null
                    playback_pid=""
                    echo "idle" > "$STATUS_FILE"
                    ;;

                DELETE:*)
                    file="${cmd#DELETE:}"
                    log "Deleting: $file"
                    rm -f "$file"
                    ;;
            esac
        fi
        sleep 0.1
    done
) &
CMD_PID=$!

log "Command processor started: $CMD_PID"

# Run QML
qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE"

# Cleanup
log "Cleaning up..."
kill $CMD_PID 2>/dev/null
rm -f "$CMD_FILE" "$STATUS_FILE"
log "=== Flick Recorder stopped ==="
