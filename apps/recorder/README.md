# Flick Recorder

A simple audio recording app for Flick mobile shell.

## Features

- **Record Audio**: Records audio using PulseAudio/PipeWire (pw-record/parecord) or ALSA (arecord) as fallback
- **Real-time Visualization**: Shows animated waveform visualization during recording
- **Recording Timer**: Displays elapsed recording time in MM:SS format
- **Auto-naming**: Recordings are automatically named with timestamps (e.g., `recording_2025-12-27_14-30-45.wav`)
- **Playback**: Tap any recording to play it back
- **Delete**: Long-press or tap the X button to delete recordings
- **Auto-refresh**: Automatically scans for new recordings
- **Dark Theme**: Follows Flick's dark theme (#0a0a0f background, #e94560 accent)

## File Locations

- **Recordings Directory**: `~/Recordings/` (created automatically)
- **QML Interface**: `/home/david/Flick/apps/recorder/main.qml`
- **Launcher Script**: `/home/david/Flick/apps/recorder/run_recorder.sh`
- **Desktop Entry**: `/home/david/Flick/apps/recorder/flick-recorder.desktop`
- **Log File**: `~/.local/state/flick/recorder.log`

## How It Works

### Recording Process
1. User taps the record button
2. QML interface sends `START_RECORDING` console message
3. Shell script captures this and starts `pw-record` (PipeWire) or `parecord` (PulseAudio)
4. Audio is recorded to `~/Recordings/recording_TIMESTAMP.wav` in 16-bit, 44.1kHz, mono format
5. Timer updates every second showing elapsed time
6. User taps stop button
7. QML sends `STOP_RECORDING` message
8. Shell script sends SIGINT to recording process to cleanly stop

### Playback Process
1. User taps a recording from the list
2. QML sends `PLAY_RECORDING:/path/to/file.wav` console message
3. Shell script starts `pw-play` (PipeWire) or `paplay` (PulseAudio)
4. Playback status is written to `/tmp/flick_recorder_playback_status`
5. QML monitors this file to detect when playback ends
6. Icon changes to pause while playing

### File Scanning
1. QML writes scan request to `/tmp/flick_recorder_scan_request`
2. Background shell process detects the request
3. Shell lists all .wav and .opus files in ~/Recordings/
4. Results written to `/tmp/flick_recorder_files`
5. QML reads this file and updates the recordings list

## Audio Format

Recordings are saved as WAV files with the following specifications:
- **Format**: S16_LE (16-bit signed little-endian PCM)
- **Sample Rate**: 44100 Hz
- **Channels**: 1 (mono)

## Dependencies

The app will use whichever audio system is available:
- **PipeWire**: `pw-record` and `pw-play` (preferred)
- **PulseAudio**: `parecord` and `paplay` (fallback)
- **ALSA**: `arecord` and `aplay` (last resort fallback)

## UI Layout

- **Header**: App title with glow effect (pulses while recording)
- **Recording Area**:
  - Waveform visualizer (animated during recording)
  - Recording time display
  - Large record/stop button (red circle with white dot/square)
- **Recordings List**: Scrollable list of previous recordings
  - Play/pause button
  - Recording name and filename
  - Delete button
- **Back Button**: Bottom-right corner to exit app

## Notes

- The app follows Flick's pattern of using console.log() for shell communication
- All file operations are handled by the shell script for security
- Haptic feedback is provided for all user interactions
- The app respects Flick's text_scale setting from display config
