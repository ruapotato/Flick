#!/usr/bin/env python3
"""
Flick Phone Helper - oFono D-Bus integration for Flick Phone app
Based on phofono by Alaraajavamma

This script handles:
- Dialing numbers via oFono
- Answering/hanging up calls
- Monitoring call state
- Managing call history
"""

import sys
import os
import json
import time
import subprocess
from datetime import datetime

# D-Bus imports
try:
    from gi.repository import Gio, GLib
    HAS_DBUS = True
except ImportError:
    HAS_DBUS = False
    print("Warning: gi.repository not available, using mock mode")

# Paths
STATE_DIR = os.path.expanduser("~/.local/state/flick")
HISTORY_FILE = os.path.join(STATE_DIR, "call_history.json")
STATUS_FILE = "/tmp/flick_phone_status"
CMD_FILE = "/tmp/flick_phone_cmd"

os.makedirs(STATE_DIR, exist_ok=True)


def trigger_haptic():
    """Trigger haptic feedback"""
    try:
        with open("/tmp/flick_haptic", "w") as f:
            f.write("click")
    except:
        pass


def play_ringtone():
    """Play ringtone for incoming call"""
    sound_file = os.path.expanduser("~/Flick/sounds/ringtone_gentle.wav")
    if os.path.exists(sound_file):
        try:
            # Play ringtone in loop (will be killed when call is answered/rejected)
            global ringtone_process
            try:
                ringtone_process = subprocess.Popen(
                    ["paplay", "--volume=65536", sound_file],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
            except FileNotFoundError:
                ringtone_process = subprocess.Popen(
                    ["aplay", sound_file],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
            print("Playing ringtone")
        except Exception as e:
            print(f"Failed to play ringtone: {e}")


def stop_ringtone():
    """Stop playing ringtone"""
    global ringtone_process
    try:
        if 'ringtone_process' in globals() and ringtone_process:
            ringtone_process.terminate()
            ringtone_process = None
            print("Stopped ringtone")
    except:
        pass


ringtone_process = None


def setup_call_audio():
    """Setup audio routing for voice call on Droidian/Android devices"""
    try:
        print("Setting up voice call audio...")

        # Switch to voicecall profile on the droid card
        # This is CRITICAL for audio to work on Android-based devices
        cmds = [
            # Switch card to voicecall profile
            ["pactl", "set-card-profile", "droid_card.primary", "voicecall"],
            # Set earpiece port for output (for non-speaker mode)
            ["pactl", "set-sink-port", "sink.primary_output", "output-earpiece"],
            # Set voice call input
            ["pactl", "set-source-port", "source.droid", "input-voice_call"],
            # Unmute and set volumes
            ["pactl", "set-sink-mute", "sink.primary_output", "0"],
            ["pactl", "set-sink-volume", "sink.primary_output", "80%"],
            ["pactl", "set-source-mute", "source.droid", "0"],
            ["pactl", "set-source-volume", "source.droid", "100%"],
        ]

        for cmd in cmds:
            result = subprocess.run(cmd, capture_output=True, timeout=5)
            if result.returncode != 0:
                print(f"Audio cmd failed: {' '.join(cmd)} - {result.stderr.decode()}")
            else:
                print(f"Audio cmd OK: {' '.join(cmd)}")

        print("Voice call audio configured")
    except Exception as e:
        print(f"Audio setup error: {e}")


def set_speaker_mode(enabled):
    """Toggle speakerphone during call"""
    try:
        if enabled:
            print("Enabling speakerphone...")
            subprocess.run(["pactl", "set-sink-port", "sink.primary_output", "output-speaker"],
                          capture_output=True, timeout=5)
        else:
            print("Disabling speakerphone (earpiece)...")
            subprocess.run(["pactl", "set-sink-port", "sink.primary_output", "output-earpiece"],
                          capture_output=True, timeout=5)
    except Exception as e:
        print(f"Speaker mode error: {e}")


def teardown_call_audio():
    """Reset audio routing after call"""
    try:
        print("Resetting audio after call...")

        # Switch back to default profile
        cmds = [
            ["pactl", "set-card-profile", "droid_card.primary", "default"],
            # Reset to speaker output for media
            ["pactl", "set-sink-port", "sink.primary_output", "output-speaker"],
            # Reset to builtin mic
            ["pactl", "set-source-port", "source.droid", "input-builtin_mic"],
        ]

        for cmd in cmds:
            result = subprocess.run(cmd, capture_output=True, timeout=5)
            if result.returncode != 0:
                print(f"Audio reset cmd failed: {' '.join(cmd)}")
            else:
                print(f"Audio reset cmd OK: {' '.join(cmd)}")

        print("Audio routing reset to default")
    except Exception as e:
        print(f"Audio teardown error: {e}")


class OfonoManager:
    """Manages oFono D-Bus connection for telephony"""

    def __init__(self):
        self.bus = None
        self.modem_path = None
        self.vcm_proxy = None  # VoiceCallManager
        self.connected = False
        self.active_call_path = None

        if HAS_DBUS:
            self._connect()

    def _connect(self):
        """Connect to oFono via D-Bus"""
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

            # Get oFono manager
            manager = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.ofono", "/", "org.ofono.Manager", None
            )

            # Get modems
            try:
                result = manager.call_sync(
                    "GetModems", None,
                    Gio.DBusCallFlags.NONE, -1, None
                )
                modems = result.unpack()[0]
            except Exception as e:
                print(f"Failed to get modems: {e}")
                modems = []

            if modems:
                self.modem_path = modems[0][0]
                print(f"Found modem: {self.modem_path}")

                # Get VoiceCallManager interface
                self.vcm_proxy = Gio.DBusProxy.new_sync(
                    self.bus, Gio.DBusProxyFlags.NONE, None,
                    "org.ofono", self.modem_path,
                    "org.ofono.VoiceCallManager", None
                )
                self.connected = True
            else:
                print("No modems found")

        except Exception as e:
            print(f"oFono connection failed: {e}")

    def dial(self, number, hide_caller_id=False):
        """Dial a phone number"""
        if not self.connected or not self.vcm_proxy:
            print("Not connected to oFono")
            return False

        try:
            clir = "enabled" if hide_caller_id else "default"
            result = self.vcm_proxy.call_sync(
                "Dial",
                GLib.Variant("(ss)", (number, clir)),
                Gio.DBusCallFlags.NONE, -1, None
            )
            call_path = result.unpack()[0]
            self.active_call_path = call_path
            print(f"Dialing {number}, call path: {call_path}")
            return True
        except Exception as e:
            print(f"Dial failed: {e}")
            return False

    def hangup(self):
        """Hang up all active calls"""
        if not self.connected or not self.vcm_proxy:
            return False

        try:
            self.vcm_proxy.call_sync(
                "HangupAll", None,
                Gio.DBusCallFlags.NONE, -1, None
            )
            self.active_call_path = None
            print("Hung up all calls")
            return True
        except Exception as e:
            print(f"Hangup failed: {e}")
            return False

    def answer(self):
        """Answer incoming call"""
        if not self.active_call_path:
            # Find incoming call
            calls = self.get_calls()
            for path, props in calls:
                if props.get("State") == "incoming":
                    self.active_call_path = path
                    break

        if not self.active_call_path:
            print("No incoming call to answer")
            return False

        try:
            call_proxy = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.ofono", self.active_call_path,
                "org.ofono.VoiceCall", None
            )
            call_proxy.call_sync(
                "Answer", None,
                Gio.DBusCallFlags.NONE, -1, None
            )
            print(f"Answered call: {self.active_call_path}")
            return True
        except Exception as e:
            print(f"Answer failed: {e}")
            return False

    def get_calls(self):
        """Get list of current calls"""
        if not self.connected or not self.vcm_proxy:
            return []

        try:
            result = self.vcm_proxy.call_sync(
                "GetCalls", None,
                Gio.DBusCallFlags.NONE, -1, None
            )
            return result.unpack()[0]
        except Exception as e:
            print(f"GetCalls failed: {e}")
            return []

    def get_status(self):
        """Get current call status"""
        calls = self.get_calls()

        if not calls:
            return {"state": "idle", "number": ""}

        for path, props in calls:
            state = props.get("State", "unknown")
            number = props.get("LineIdentification", "Unknown")
            self.active_call_path = path

            return {
                "state": state,
                "number": number,
                "path": path
            }

        return {"state": "idle", "number": ""}


def load_history():
    """Load call history from file"""
    try:
        if os.path.exists(HISTORY_FILE):
            with open(HISTORY_FILE, 'r') as f:
                return json.load(f)
    except Exception as e:
        print(f"Failed to load history: {e}")
    return []


def save_history(history):
    """Save call history to file"""
    try:
        with open(HISTORY_FILE, 'w') as f:
            json.dump(history[:100], f, indent=2)  # Keep last 100 calls
        print(f"Saved {len(history)} history entries")
    except Exception as e:
        print(f"Failed to save history: {e}")


def add_to_history(number, direction, duration=0):
    """Add a call to history"""
    history = load_history()
    entry = {
        "number": number,
        "direction": direction,
        "duration": duration,
        "timestamp": datetime.now().isoformat()
    }
    history.insert(0, entry)
    save_history(history)


def write_status(status_dict):
    """Write status to file for QML to read"""
    try:
        with open(STATUS_FILE, 'w') as f:
            json.dump(status_dict, f)
    except Exception as e:
        print(f"Failed to write status: {e}")


def daemon_mode():
    """Run as background daemon monitoring calls"""
    print("Starting phone helper daemon...")
    ofono = OfonoManager()

    last_state = "idle"
    call_start = None
    call_number = ""

    while True:
        try:
            # Check for commands
            if os.path.exists(CMD_FILE):
                try:
                    with open(CMD_FILE, 'r') as f:
                        cmd = json.load(f)
                    os.remove(CMD_FILE)

                    action = cmd.get("action", "")
                    if action == "dial":
                        number = cmd.get("number", "")
                        if number:
                            ofono.dial(number)
                            call_number = number
                            call_start = time.time()
                    elif action == "hangup":
                        ofono.hangup()
                    elif action == "answer":
                        ofono.answer()
                        call_start = time.time()
                    elif action == "speaker":
                        # Toggle speakerphone
                        speaker_on = cmd.get("enabled", False)
                        set_speaker_mode(speaker_on)
                except Exception as e:
                    print(f"Command error: {e}")

            # Get current status
            status = ofono.get_status()
            current_state = status.get("state", "idle")

            # Detect call becoming active - setup audio, stop ringtone
            if current_state == "active" and last_state != "active":
                print("Call became active - setting up audio")
                stop_ringtone()
                setup_call_audio()

            # Detect call end
            if last_state in ["active", "alerting", "dialing", "incoming"] and current_state == "idle":
                duration = int(time.time() - call_start) if call_start else 0
                direction = "outgoing" if last_state == "dialing" else "incoming"
                add_to_history(call_number, direction, duration)
                call_start = None
                call_number = ""
                stop_ringtone()
                teardown_call_audio()

            # Detect incoming call - play ringtone
            if current_state == "incoming" and last_state == "idle":
                call_number = status.get("number", "Unknown")
                print(f"Incoming call from {call_number}")
                trigger_haptic()
                play_ringtone()

            # Update status file
            status["duration"] = int(time.time() - call_start) if call_start else 0
            write_status(status)

            last_state = current_state
            time.sleep(1)

        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Daemon error: {e}")
            time.sleep(2)


def main():
    if len(sys.argv) < 2:
        print("Usage: phone_helper.py <command> [args]")
        print("Commands: dial <number>, hangup, answer, status, history, save_history <json>, daemon")
        sys.exit(1)

    cmd = sys.argv[1]
    ofono = OfonoManager()

    if cmd == "dial" and len(sys.argv) >= 3:
        number = sys.argv[2]
        # Write command for daemon
        with open(CMD_FILE, 'w') as f:
            json.dump({"action": "dial", "number": number}, f)
        # Also try direct dial
        success = ofono.dial(number)
        if success:
            add_to_history(number, "outgoing", 0)
        sys.exit(0 if success else 1)

    elif cmd == "hangup":
        with open(CMD_FILE, 'w') as f:
            json.dump({"action": "hangup"}, f)
        success = ofono.hangup()
        sys.exit(0 if success else 1)

    elif cmd == "answer":
        with open(CMD_FILE, 'w') as f:
            json.dump({"action": "answer"}, f)
        success = ofono.answer()
        sys.exit(0 if success else 1)

    elif cmd == "status":
        status = ofono.get_status()
        state = status.get("state", "idle")
        number = status.get("number", "")

        if state == "incoming":
            print(f"incoming:{number}")
        elif state == "active":
            print(f"active:{number}")
        elif state in ["alerting", "dialing"]:
            print(f"dialing:{number}")
        else:
            print("idle")

    elif cmd == "history":
        history = load_history()
        print(json.dumps(history, indent=2))

    elif cmd == "save_history" and len(sys.argv) >= 3:
        try:
            history = json.loads(sys.argv[2])
            save_history(history)
        except Exception as e:
            print(f"Failed to save history: {e}")
            sys.exit(1)

    elif cmd == "daemon":
        daemon_mode()

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
