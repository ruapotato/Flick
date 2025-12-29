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

# Paths
STATE_DIR = os.path.expanduser("~/.local/state/flick")
MESSAGES_FILE = os.path.join(STATE_DIR, "messages.json")
NOTIFICATIONS_FILE = os.path.join(STATE_DIR, "notifications_display.json")
CMD_FILE = "/tmp/flick_messages_cmd"

os.makedirs(STATE_DIR, exist_ok=True)


def create_notification(phone_number, text, contact_name=None):
    """Create a notification for incoming SMS"""
    try:
        # Load existing notifications
        notifications = []
        if os.path.exists(NOTIFICATIONS_FILE):
            try:
                with open(NOTIFICATIONS_FILE, 'r') as f:
                    data = json.load(f)
                    notifications = data.get("notifications", [])
            except:
                pass

        # Generate unique ID
        notif_id = int(time.time() * 1000) % 1000000

        # Create notification
        notif = {
            "id": notif_id,
            "app_name": "Messages",
            "app_icon": "💬",
            "title": contact_name or phone_number,
            "body": text[:100] + ("..." if len(text) > 100 else ""),
            "time": datetime.now().strftime("%H:%M"),
            "urgency": 1,
            "phone_number": phone_number  # For opening the right conversation
        }

        # Add to front of list
        notifications.insert(0, notif)

        # Keep only last 20 notifications
        notifications = notifications[:20]

        # Save
        with open(NOTIFICATIONS_FILE, 'w') as f:
            json.dump({
                "notifications": notifications,
                "count": len(notifications)
            }, f, indent=2)

        print(f"Created notification for SMS from {phone_number}")

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

        # Find or create conversation
        conversation = None
        for conv in data["conversations"]:
            if conv["phone_number"] == phone_number:
                conversation = conv
                break

        if conversation is None:
            conversation = {
                "phone_number": phone_number,
                "contact_name": phone_number,  # TODO: lookup from contacts
                "messages": [],
                "last_message": "",
                "last_message_time": "",
                "unread_count": 0
            }
            data["conversations"].append(conversation)

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

                    # Check state to determine if incoming or outgoing
                    state_variant = props_proxy.call_sync(
                        "Get",
                        GLib.Variant("(ss)", ("org.freedesktop.ModemManager1.Sms", "State")),
                        Gio.DBusCallFlags.NONE, -1, None
                    )
                    state = state_variant.unpack()[0]

                    # State: 1=received, 2=sending, 3=sent
                    direction = "incoming" if state == 1 else "outgoing"

                    print(f"Importing SMS from {number}: {text[:30]}...")

                    # Create notification for incoming messages
                    if direction == "incoming":
                        create_notification(number, text)

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
