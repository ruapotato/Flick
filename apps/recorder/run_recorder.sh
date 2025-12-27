#!/bin/bash
# Flick Recorder - Audio recording app for Flick shell
# Handles audio recording, playback, and file management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/home/droidian/.local/state/flick"
RECORDINGS_DIR="/home/droidian/Recordings"
LOG_FILE="${STATE_DIR}/recorder.log"

mkdir -p "$STATE_DIR"
mkdir -p "$RECORDINGS_DIR"

echo "=== Flick Recorder started at $(date) ===" >> "$LOG_FILE"

# Set Wayland environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Force software rendering for hwcomposer compatibility
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

# Background process to handle recording/playback commands
(
    current_recording_pid=""
    current_playback_pid=""

    # Monitor QML console output for commands
    while IFS= read -r line; do
        echo "$line" >> "$LOG_FILE"

        # Check for recording start command
        if [[ "$line" =~ START_RECORDING:(.+) ]]; then
            recording_file="${BASH_REMATCH[1]}"
            echo "Starting recording to: $recording_file" >> "$LOG_FILE"

            # Stop any existing recording
            if [ -n "$current_recording_pid" ]; then
                kill $current_recording_pid 2>/dev/null
            fi

            # Start recording with parecord (PulseAudio) or pw-record (PipeWire)
            if command -v pw-record &> /dev/null; then
                pw-record --format=s16 --rate=44100 --channels=1 "$recording_file" &
                current_recording_pid=$!
            elif command -v parecord &> /dev/null; then
                parecord --format=s16le --rate=44100 --channels=1 "$recording_file" &
                current_recording_pid=$!
            else
                # Fallback to arecord (ALSA)
                arecord -f S16_LE -r 44100 -c 1 "$recording_file" &
                current_recording_pid=$!
            fi
            echo "Recording PID: $current_recording_pid" >> "$LOG_FILE"
        fi

        # Check for recording stop command
        if [[ "$line" =~ STOP_RECORDING ]]; then
            echo "Stopping recording" >> "$LOG_FILE"
            if [ -n "$current_recording_pid" ]; then
                kill -SIGINT $current_recording_pid 2>/dev/null
                wait $current_recording_pid 2>/dev/null
                current_recording_pid=""
            fi
        fi

        # Check for playback command
        if [[ "$line" =~ PLAY_RECORDING:(.+) ]]; then
            playback_file="${BASH_REMATCH[1]}"
            echo "Playing: $playback_file" >> "$LOG_FILE"

            # Stop any existing playback
            if [ -n "$current_playback_pid" ]; then
                kill $current_playback_pid 2>/dev/null
            fi

            # Clear status
            rm -f /tmp/flick_recorder_playback_status

            # Start playback
            if command -v pw-play &> /dev/null; then
                (pw-play "$playback_file"; echo "stopped" > /tmp/flick_recorder_playback_status) &
                current_playback_pid=$!
            elif command -v paplay &> /dev/null; then
                (paplay "$playback_file"; echo "stopped" > /tmp/flick_recorder_playback_status) &
                current_playback_pid=$!
            else
                # Fallback to aplay (ALSA)
                (aplay "$playback_file"; echo "stopped" > /tmp/flick_recorder_playback_status) &
                current_playback_pid=$!
            fi
            echo "Playback PID: $current_playback_pid" >> "$LOG_FILE"
        fi

        # Check for playback stop command
        if [[ "$line" =~ STOP_PLAYBACK ]]; then
            echo "Stopping playback" >> "$LOG_FILE"
            if [ -n "$current_playback_pid" ]; then
                kill $current_playback_pid 2>/dev/null
                current_playback_pid=""
                echo "stopped" > /tmp/flick_recorder_playback_status
            fi
        fi

        # Check for delete command
        if [[ "$line" =~ DELETE_RECORDING:(.+) ]]; then
            delete_file="${BASH_REMATCH[1]}"
            echo "Deleting: $delete_file" >> "$LOG_FILE"
            rm -f "$delete_file"
        fi
    done
) &
MONITOR_PID=$!

# Background process to handle file scanning
(
    while true; do
        if [ -f /tmp/flick_recorder_scan_request ]; then
            scan_dir=$(cat /tmp/flick_recorder_scan_request)
            echo "Scanning: $scan_dir" >> "$LOG_FILE"

            # List recordings (newest first)
            if [ -d "$scan_dir" ]; then
                ls -1t "$scan_dir"/*.wav "$scan_dir"/*.opus 2>/dev/null | xargs -n1 basename 2>/dev/null > /tmp/flick_recorder_files
            else
                echo "" > /tmp/flick_recorder_files
            fi

            rm -f /tmp/flick_recorder_scan_request
        fi
        sleep 0.5
    done
) &
SCANNER_PID=$!

# Run the recorder QML interface and pipe output to monitor
qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | while IFS= read -r line; do
    echo "$line"
    echo "$line" >> "$LOG_FILE"
done &
QML_PID=$!

# Wait for QML to exit
wait $QML_PID

# Cleanup
kill $MONITOR_PID 2>/dev/null
kill $SCANNER_PID 2>/dev/null

echo "=== Flick Recorder stopped at $(date) ===" >> "$LOG_FILE"
