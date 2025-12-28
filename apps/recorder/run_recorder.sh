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
# Hardware acceleration enabled
# export QT_QUICK_BACKEND=software  # Using hardware accel

# Clean up any stale files
rm -f "$CMD_FILE" "$STATUS_FILE"
echo "idle" > "$STATUS_FILE"

# PID files for tracking processes
REC_PID_FILE="/tmp/flick_recorder_rec_pid"
PLAY_PID_FILE="/tmp/flick_recorder_play_pid"

# Clean up old PID files
rm -f "$REC_PID_FILE" "$PLAY_PID_FILE"

# Background command processor
(
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
                    if [ -f "$REC_PID_FILE" ]; then
                        kill $(cat "$REC_PID_FILE") 2>/dev/null
                        rm -f "$REC_PID_FILE"
                    fi

                    # Start recording
                    echo "recording" > "$STATUS_FILE"
                    if command -v pw-record &> /dev/null; then
                        pw-record --format=s16 --rate=44100 --channels=1 "$file" &
                        echo $! > "$REC_PID_FILE"
                    elif command -v parecord &> /dev/null; then
                        parecord --format=s16le --rate=44100 --channels=1 "$file" &
                        echo $! > "$REC_PID_FILE"
                    else
                        arecord -f S16_LE -r 44100 -c 1 "$file" &
                        echo $! > "$REC_PID_FILE"
                    fi
                    log "Recording PID: $(cat $REC_PID_FILE)"
                    ;;

                STOP)
                    log "Stopping recording"
                    if [ -f "$REC_PID_FILE" ]; then
                        kill -INT $(cat "$REC_PID_FILE") 2>/dev/null
                        wait $(cat "$REC_PID_FILE") 2>/dev/null
                        rm -f "$REC_PID_FILE"
                        log "Recording stopped"
                    fi
                    echo "idle" > "$STATUS_FILE"
                    ;;

                PLAY:*)
                    file="${cmd#PLAY:}"
                    log "Playing: $file"

                    # Kill any existing playback
                    if [ -f "$PLAY_PID_FILE" ]; then
                        old_pid=$(cat "$PLAY_PID_FILE")
                        kill $old_pid 2>/dev/null
                        # Also kill child processes (the actual player)
                        pkill -P $old_pid 2>/dev/null
                        rm -f "$PLAY_PID_FILE"
                    fi

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
                        rm -f "$PLAY_PID_FILE"
                    ) &
                    echo $! > "$PLAY_PID_FILE"
                    log "Playback PID: $(cat $PLAY_PID_FILE)"
                    ;;

                STOPPLAY)
                    log "Stopping playback"
                    if [ -f "$PLAY_PID_FILE" ]; then
                        pid=$(cat "$PLAY_PID_FILE")
                        log "Killing playback PID: $pid"
                        # Kill the subshell and its children
                        pkill -P $pid 2>/dev/null
                        kill $pid 2>/dev/null
                        rm -f "$PLAY_PID_FILE"
                    fi
                    # Also try to kill any stray audio players
                    pkill -f "pw-play.*Recordings" 2>/dev/null
                    pkill -f "paplay.*Recordings" 2>/dev/null
                    pkill -f "aplay.*Recordings" 2>/dev/null
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
# Kill any remaining audio processes
[ -f "$REC_PID_FILE" ] && kill $(cat "$REC_PID_FILE") 2>/dev/null
[ -f "$PLAY_PID_FILE" ] && kill $(cat "$PLAY_PID_FILE") 2>/dev/null
rm -f "$CMD_FILE" "$STATUS_FILE" "$REC_PID_FILE" "$PLAY_PID_FILE"
log "=== Flick Recorder stopped ==="
