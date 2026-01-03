#!/usr/bin/env python3
"""
Flick Messages Daemon - ModemManager D-Bus integration for SMS
Handles:
- Sending SMS via ModemManager
- Receiving incoming SMS
- Managing conversation history
- Providing JSON interface for QML app
"""

import sys
import os
import json
import time
from datetime import datetime
from pathlib import Path

# D-Bus imports
try:
    from gi.repository import Gio, GLib
    HAS_DBUS = True
except ImportError:
    HAS_DBUS = False
    print("Warning: gi.repository not available, using mock mode")

# Device configuration
DEVICE_CONFIG_PATH = "/etc/flick/device.conf"

def load_device_config():
    """Load device configuration from /etc/flick/device.conf."""
    config = {}
    if os.path.exists(DEVICE_CONFIG_PATH):
        try:
            with open(DEVICE_CONFIG_PATH) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        value = value.strip().strip('"').strip("'")
                        config[key.strip()] = value
        except Exception as e:
            print(f"Warning: Could not load device config: {e}")
    return config

def get_user_home():
    """Get the user's home directory from config or environment."""
    # Check environment first (set by systemd service)
    if os.environ.get('FLICK_HOME'):
        return os.environ['FLICK_HOME']

    # Check device config
    config = load_device_config()
    if config.get('DEVICE_HOME'):
        return config['DEVICE_HOME']
    if config.get('DEVICE_USER'):
        return f"/home/{config['DEVICE_USER']}"

    # Default to expanding ~
    return os.path.expanduser("~")

# Paths
USER_HOME = get_user_home()
STATE_DIR = os.path.join(USER_HOME, ".local/state/flick")
MESSAGES_FILE = os.path.join(STATE_DIR, "messages.json")
APP_NOTIFICATIONS_FILE = os.path.join(STATE_DIR, "app_notifications.json")
CMD_FILE = "/tmp/flick_messages_cmd"

os.makedirs(STATE_DIR, exist_ok=True)


def normalize_phone_number(number):
    """Normalize phone number for consistent matching.

    Handles formats like:
    - +15417999824 -> 5417999824
    - 15417999824 -> 5417999824  (if 11 digits starting with 1)
    - 5417999824 -> 5417999824
    - (541) 799-9824 -> 5417999824
    """
    if not number:
        return ""

    # Remove all non-digit characters
    digits = ''.join(c for c in number if c.isdigit())

    # If it's 11 digits and starts with 1 (US country code), remove the 1
    if len(digits) == 11 and digits.startswith('1'):
        digits = digits[1:]

    return digits


def trigger_haptic():
    """Trigger haptic feedback for new SMS"""
    try:
        with open("/tmp/flick_haptic", "w") as f:
            f.write("click")
        print("Triggered haptic feedback")
    except Exception as e:
        print(f"Failed to trigger haptic: {e}")


def play_notification_sound():
    """Play notification sound for new SMS"""
    import subprocess
    sound_file = os.path.join(USER_HOME, "Flick/sounds/notification_ding.wav")
    if os.path.exists(sound_file):
        try:
            # Try paplay first (PulseAudio), fall back to aplay
            try:
                subprocess.Popen(["paplay", sound_file],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            except FileNotFoundError:
                subprocess.Popen(["aplay", "-q", sound_file],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            print("Playing notification sound")
        except Exception as e:
            print(f"Failed to play sound: {e}")


def create_notification(phone_number, text, contact_name=None):
    """Create a notification for incoming SMS via shell's app notification system"""
    try:
        # Format for shell's app_notifications.json
        # Shell reads this, adds to its store, then deletes the file
        notif = {
            "app_name": "Messages",
            "summary": contact_name or phone_number,
            "body": text[:100] + ("..." if len(text) > 100 else ""),
            "urgency": "normal"
        }

        # Write notification request for shell to pick up
        with open(APP_NOTIFICATIONS_FILE, 'w') as f:
            json.dump({
                "notifications": [notif]
            }, f, indent=2)

        print(f"Created notification for SMS from {phone_number}")

        # Trigger haptic feedback
        trigger_haptic()

        # Play notification sound
        play_notification_sound()

    except Exception as e:
        print(f"Failed to create notification: {e}")


class ModemManagerSMS:
    """Manages ModemManager D-Bus connection for SMS"""

    def __init__(self):
        self.bus = None
        self.modem_path = None
        self.messaging_proxy = None
        self.connected = False

        if HAS_DBUS:
            self._connect()

    def _connect(self):
        """Connect to ModemManager via D-Bus"""
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

            # Get ModemManager object manager
            mm_manager = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.freedesktop.ModemManager1",
                "/org/freedesktop/ModemManager1",
                "org.freedesktop.DBus.ObjectManager", None
            )

            # Get all managed objects (modems)
            try:
                result = mm_manager.call_sync(
                    "GetManagedObjects", None,
                    Gio.DBusCallFlags.NONE, -1, None
                )
                modems = result.unpack()[0]
            except Exception as e:
                print(f"Failed to get modems: {e}")
                modems = {}

            # Find first modem with messaging capability
            for path, interfaces in modems.items():
                if "org.freedesktop.ModemManager1.Modem" in interfaces:
                    self.modem_path = path
                    print(f"Found modem: {self.modem_path}")

                    # Get Messaging interface
                    try:
                        self.messaging_proxy = Gio.DBusProxy.new_sync(
                            self.bus, Gio.DBusProxyFlags.NONE, None,
                            "org.freedesktop.ModemManager1", self.modem_path,
                            "org.freedesktop.ModemManager1.Modem.Messaging", None
                        )
                        self.connected = True
                        print("Connected to ModemManager Messaging interface")

                        # Subscribe to signal for incoming SMS
                        self.bus.signal_subscribe(
                            "org.freedesktop.ModemManager1",
                            "org.freedesktop.ModemManager1.Modem.Messaging",
                            "Added",
                            self.modem_path,
                            None,
                            Gio.DBusSignalFlags.NONE,
                            self._on_sms_added,
                            None
                        )
                        print("Subscribed to SMS Added signals")
                        break
                    except Exception as e:
                        print(f"Failed to get Messaging interface: {e}")

            if not self.connected:
                print("No modem with messaging capability found")

        except Exception as e:
            print(f"ModemManager connection failed: {e}")

    def _on_sms_added(self, connection, sender, path, interface, signal, parameters, user_data):
        """Callback for incoming SMS"""
        try:
            sms_path = parameters.unpack()[0]
            print(f"New SMS received: {sms_path}")

            # Get SMS properties
            sms_proxy = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.freedesktop.ModemManager1", sms_path,
                "org.freedesktop.ModemManager1.Sms", None
            )

            # Get all properties
            props_proxy = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.freedesktop.ModemManager1", sms_path,
                "org.freedesktop.DBus.Properties", None
            )

            # Get text, number, and timestamp
            text_variant = props_proxy.call_sync(
                "Get",
                GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "Text")),
                Gio.DBusCallFlags.NONE, -1, None
            )
            text = text_variant.unpack()[0]

            number_variant = props_proxy.call_sync(
                "Get",
                GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "Number")),
                Gio.DBusCallFlags.NONE, -1, None
            )
            number = number_variant.unpack()[0]

            timestamp_variant = props_proxy.call_sync(
                "Get",
                GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "Timestamp")),
                Gio.DBusCallFlags.NONE, -1, None
            )
            timestamp = timestamp_variant.unpack()[0]

            print(f"SMS from {number}: {text}")

            # Create notification for lock screen / quick settings
            create_notification(number, text)

            # Add to messages
            self.add_message(number, text, "incoming", timestamp)

            # Delete from modem storage
            try:
                sms_proxy.call_sync(
                    "Delete", None,
                    Gio.DBusCallFlags.NONE, -1, None
                )
                print(f"Deleted SMS from modem storage")
            except Exception as e:
                print(f"Failed to delete SMS: {e}")

        except Exception as e:
            print(f"Error processing incoming SMS: {e}")

    def send_sms(self, phone_number, text):
        """Send an SMS message"""
        if not self.connected or not self.messaging_proxy:
            print("Not connected to ModemManager")
            return False

        try:
            # Create SMS
            properties = {
                "number": GLib.Variant("s", phone_number),
                "text": GLib.Variant("s", text)
            }

            result = self.messaging_proxy.call_sync(
                "Create",
                GLib.Variant("(a{sv})", (properties,)),
                Gio.DBusCallFlags.NONE, -1, None
            )
            sms_path = result.unpack()[0]
            print(f"Created SMS: {sms_path}")

            # Get SMS proxy and send
            sms_proxy = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.freedesktop.ModemManager1", sms_path,
                "org.freedesktop.ModemManager1.Sms", None
            )

            sms_proxy.call_sync(
                "Send", None,
                Gio.DBusCallFlags.NONE, -1, None
            )
            print(f"SMS sent to {phone_number}")

            # Add to messages with sent status
            self.add_message(phone_number, text, "outgoing", datetime.now().isoformat(), status="sent")

            return True

        except Exception as e:
            print(f"Failed to send SMS: {e}")
            # Still add to messages with failed status
            self.add_message(phone_number, text, "outgoing", datetime.now().isoformat(), status="failed")
            return False

    def add_message(self, phone_number, text, direction, timestamp=None, status="delivered"):
        """Add a message to the conversation history"""
        if timestamp is None:
            timestamp = datetime.now().isoformat()

        data = load_messages()

        # Normalize phone number for matching
        normalized_input = normalize_phone_number(phone_number)

        # Find or create conversation (match by normalized phone number)
        conversation = None
        for conv in data["conversations"]:
            if normalize_phone_number(conv["phone_number"]) == normalized_input:
                conversation = conv
                break

        if conversation is None:
            # Store the normalized version for consistency
            conversation = {
                "phone_number": normalized_input,
                "contact_name": normalized_input,  # TODO: lookup from contacts
                "messages": [],
                "last_message": "",
                "last_message_time": "",
                "unread_count": 0
            }
            data["conversations"].append(conversation)

        # Check for duplicate message (same text and similar timestamp, ignore direction)
        for existing in conversation["messages"]:
            if existing["text"] == text:
                # If timestamps match exactly, skip
                if existing.get("timestamp") == timestamp:
                    print(f"Skipping duplicate message: {text[:30]}...")
                    return
                # Also check if timestamps are within 120 seconds of each other
                try:
                    from dateutil import parser as dateparser
                    existing_time = dateparser.parse(existing.get("timestamp", ""))
                    new_time = dateparser.parse(timestamp) if timestamp else datetime.now()
                    if abs((new_time - existing_time).total_seconds()) < 120:
                        print(f"Skipping near-duplicate message: {text[:30]}...")
                        return
                except:
                    # If timestamps are empty or can't parse, check for exact text match within last 5 messages
                    if not timestamp or not existing.get("timestamp"):
                        print(f"Skipping duplicate (no timestamp): {text[:30]}...")
                        return

        # Add message
        message = {
            "text": text,
            "direction": direction,
            "timestamp": timestamp,
            "status": status
        }
        conversation["messages"].append(message)

        # Update conversation metadata
        conversation["last_message"] = text
        conversation["last_message_time"] = timestamp
        if direction == "incoming":
            conversation["unread_count"] = conversation.get("unread_count", 0) + 1

        # Sort conversations by last message time
        data["conversations"].sort(
            key=lambda c: c.get("last_message_time", ""),
            reverse=True
        )

        save_messages(data)

    def list_existing_sms(self):
        """List existing SMS messages in modem storage"""
        if not self.connected or not self.messaging_proxy:
            return []

        try:
            result = self.messaging_proxy.call_sync(
                "List", None,
                Gio.DBusCallFlags.NONE, -1, None
            )
            sms_paths = result.unpack()[0]
            print(f"Found {len(sms_paths)} existing SMS in modem storage")

            # Process each SMS
            for sms_path in sms_paths:
                try:
                    props_proxy = Gio.DBusProxy.new_sync(
                        self.bus, Gio.DBusProxyFlags.NONE, None,
                        "org.freedesktop.ModemManager1", sms_path,
                        "org.freedesktop.DBus.Properties", None
                    )

                    # Get SMS properties
                    text_variant = props_proxy.call_sync(
                        "Get",
                        GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "Text")),
                        Gio.DBusCallFlags.NONE, -1, None
                    )
                    text = text_variant.unpack()[0]

                    number_variant = props_proxy.call_sync(
                        "Get",
                        GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "Number")),
                        Gio.DBusCallFlags.NONE, -1, None
                    )
                    number = number_variant.unpack()[0]

                    timestamp_variant = props_proxy.call_sync(
                        "Get",
                        GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "Timestamp")),
                        Gio.DBusCallFlags.NONE, -1, None
                    )
                    timestamp = timestamp_variant.unpack()[0]

                    # Check PduType/Direction to determine if incoming or outgoing
                    # Direction: 1=unknown, 2=mobile-originated (outgoing), 3=mobile-terminated (incoming)
                    try:
                        pdu_variant = props_proxy.call_sync(
                            "Get",
                            GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "PduType")),
                            Gio.DBusCallFlags.NONE, -1, None
                        )
                        pdu_type = pdu_variant.unpack()[0]
                        # PduType: 0=unknown, 1=deliver (incoming), 2=submit (outgoing), 3=status-report
                        direction = "incoming" if pdu_type == 1 else "outgoing"
                    except:
                        # Fallback to State if PduType not available
                        state_variant = props_proxy.call_sync(
                            "Get",
                            GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "State")),
                            Gio.DBusCallFlags.NONE, -1, None
                        )
                        state = state_variant.unpack()[0]
                        # State: 1=received, 2=sending, 3=sent
                        direction = "incoming" if state == 1 else "outgoing"

                    print(f"Importing SMS from {number}: {text[:30]}...")

                    # Note: Don't create notifications for imported messages
                    # These are old messages from modem storage, not new ones
                    # Notifications are only created in _on_sms_added for truly new messages

                    self.add_message(number, text, direction, timestamp)

                    # Delete from modem
                    sms_proxy = Gio.DBusProxy.new_sync(
                        self.bus, Gio.DBusProxyFlags.NONE, None,
                        "org.freedesktop.ModemManager1", sms_path,
                        "org.freedesktop.ModemManager1.Sms", None
                    )
                    sms_proxy.call_sync(
                        "Delete", None,
                        Gio.DBusCallFlags.NONE, -1, None
                    )

                except Exception as e:
                    print(f"Failed to import SMS {sms_path}: {e}")

        except Exception as e:
            print(f"Failed to list SMS: {e}")


def load_messages():
    """Load messages from JSON file"""
    try:
        if os.path.exists(MESSAGES_FILE):
            with open(MESSAGES_FILE, 'r') as f:
                return json.load(f)
    except Exception as e:
        print(f"Failed to load messages: {e}")

    return {
        "conversations": []
    }


def save_messages(data):
    """Save messages to JSON file"""
    try:
        with open(MESSAGES_FILE, 'w') as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"Failed to save messages: {e}")


def daemon_mode():
    """Run as background daemon monitoring SMS"""
    print("Starting messaging daemon...")
    mm = ModemManagerSMS()

    if not mm.connected:
        print("WARNING: Not connected to ModemManager - running in mock mode")

    # Import existing SMS from modem storage
    if mm.connected:
        print("Importing existing SMS from modem...")
        mm.list_existing_sms()

    # Create GLib main loop for signal processing
    loop = GLib.MainLoop()

    # Command processing timer
    def check_commands():
        try:
            if os.path.exists(CMD_FILE):
                try:
                    with open(CMD_FILE, 'r') as f:
                        cmd = json.load(f)
                    os.remove(CMD_FILE)

                    action = cmd.get("action", "")
                    if action == "send":
                        data = cmd.get("data", {})
                        phone_number = data.get("phone_number", "")
                        message = data.get("message", "")
                        if phone_number and message:
                            print(f"Sending SMS to {phone_number}: {message}")
                            mm.send_sms(phone_number, message)

                except Exception as e:
                    print(f"Command error: {e}")

        except KeyboardInterrupt:
            loop.quit()
        except Exception as e:
            print(f"Command check error: {e}")

        return True  # Keep timer running

    # Add command check timer (500ms)
    GLib.timeout_add(500, check_commands)

    print("Daemon ready, waiting for SMS and commands...")

    # Run main loop
    try:
        loop.run()
    except KeyboardInterrupt:
        print("Shutting down daemon...")


def main():
    if len(sys.argv) < 2:
        print("Usage: messaging_daemon.py <command> [args]")
        print("Commands: send <number> <text>, list, daemon")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "send" and len(sys.argv) >= 4:
        number = sys.argv[2]
        text = " ".join(sys.argv[3:])
        mm = ModemManagerSMS()
        success = mm.send_sms(number, text)
        sys.exit(0 if success else 1)

    elif cmd == "list":
        data = load_messages()
        print(json.dumps(data, indent=2))

    elif cmd == "import":
        mm = ModemManagerSMS()
        mm.list_existing_sms()

    elif cmd == "daemon":
        daemon_mode()

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
