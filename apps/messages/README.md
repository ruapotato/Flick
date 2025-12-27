# Flick Messages App

A native SMS messaging application for Flick shell with ModemManager integration.

## Features

### Current Implementation (v1.0 - SMS)
- **Conversation List View**: Shows all SMS conversations with contact names, last message preview, timestamps, and unread badges
- **Conversation Detail View**: Full message thread with message bubbles, timestamps, and delivery status
- **Send SMS**: Text input with send button, supports Enter key to send
- **Receive SMS**: Real-time SMS reception via ModemManager D-Bus signals
- **Message Persistence**: All conversations saved to `~/.local/state/flick/messages.json`
- **Dark Theme**: Consistent with Flick's dark theme (#0a0a0f background, #e94560 accent)
- **Touch-Friendly UI**: Large touch targets optimized for phone use
- **Auto-import**: Imports existing SMS from modem storage on first run

### Architecture

```
┌─────────────────────────────────────────────────┐
│              main.qml (UI Layer)                │
│  - Conversation list with avatars              │
│  - Message bubbles (incoming/outgoing)         │
│  - Text input and send button                  │
│  - Real-time updates (2s polling)              │
└──────────────────┬──────────────────────────────┘
                   │ JSON files
                   │ /tmp/flick_messages_cmd (commands)
                   │ ~/.local/state/flick/messages.json (data)
                   ▼
┌─────────────────────────────────────────────────┐
│       messaging_daemon.py (Backend)             │
│  - ModemManager D-Bus integration              │
│  - SMS send/receive via D-Bus                  │
│  - Signal subscription for incoming SMS        │
│  - Conversation management                     │
│  - Message persistence to JSON                 │
└──────────────────┬──────────────────────────────┘
                   │ D-Bus
                   ▼
┌─────────────────────────────────────────────────┐
│           ModemManager (System)                 │
│  - org.freedesktop.ModemManager1               │
│  - Modem.Messaging interface                   │
│  - SMS creation, sending, receiving            │
└─────────────────────────────────────────────────┘
```

## Files

- **main.qml**: QML UI with conversation list and detail views
- **messaging_daemon.py**: Python daemon for ModemManager D-Bus integration
- **run_messages.sh**: Launcher script that starts daemon and QML app
- **flick-messages.desktop**: Desktop entry for app launcher
- **README.md**: This file

## Data Storage

### messages.json Format
```json
{
  "conversations": [
    {
      "phone_number": "+1234567890",
      "contact_name": "John Doe",
      "last_message": "Hey, how are you?",
      "last_message_time": "2025-12-27T10:30:00",
      "unread_count": 2,
      "messages": [
        {
          "text": "Hello!",
          "direction": "outgoing",
          "timestamp": "2025-12-27T10:25:00",
          "status": "sent"
        },
        {
          "text": "Hey, how are you?",
          "direction": "incoming",
          "timestamp": "2025-12-27T10:30:00",
          "status": "delivered"
        }
      ]
    }
  ]
}
```

## Usage

### Running the App
```bash
./run_messages.sh
```

The launcher will:
1. Start the messaging daemon in the background
2. Import any existing SMS from modem storage
3. Launch the QML UI
4. Clean up daemon on exit

### Sending SMS via CLI
```bash
python3 messaging_daemon.py send +1234567890 "Hello from command line"
```

### Listing Messages
```bash
python3 messaging_daemon.py list
```

### Importing Existing SMS
```bash
python3 messaging_daemon.py import
```

## ModemManager Integration

The daemon uses the ModemManager D-Bus API:
- **Interface**: `org.freedesktop.ModemManager1.Modem.Messaging`
- **Methods**:
  - `Create(properties)` - Create SMS
  - `Send()` - Send SMS
  - `List()` - List stored SMS
  - `Delete()` - Remove SMS from modem
- **Signals**:
  - `Added(path)` - Emitted when new SMS arrives

### Permissions
ModemManager typically allows user access via PolicyKit. If you encounter permission issues:
```bash
# Check if user is in required groups
groups
# Should include: droidian, plugdev, or similar

# Check ModemManager status
systemctl status ModemManager
```

## UI Design

### Conversation List
- Avatar circle with first letter of contact name
- Contact name or phone number
- Last message preview
- Timestamp (Today shows time, older shows date)
- Unread count badge
- Touch to open conversation

### Conversation Detail
- Header with back button and contact info
- Message bubbles (incoming: gray, outgoing: accent color)
- Message timestamps
- Delivery status indicators (sending: ..., sent: ✓, delivered: ✓✓)
- Text input with placeholder
- Send button (disabled when empty)
- Auto-scroll to newest message

### Theme
- Background: `#0a0a0f` (near black)
- Accent: `#e94560` (pink/red)
- Dark cards: `#1a1a2e`
- Borders: `#2a2a4e`
- Text scale: Follows Flick's display_config.json

## Future Enhancements

### Planned Features (Phase 2)
- [ ] MMS support (images, videos)
- [ ] Contact integration (lookup names from contacts app)
- [ ] Delivery reports
- [ ] Read receipts
- [ ] Group messaging
- [ ] Search conversations
- [ ] Delete messages/conversations
- [ ] Message drafts
- [ ] Notifications for new messages
- [ ] Message timestamps with date separators
- [ ] Copy/select message text
- [ ] Forward messages
- [ ] Emoji picker

### Planned Features (Phase 3 - Matrix)
- [ ] Matrix protocol support
- [ ] End-to-end encryption
- [ ] Multi-device sync
- [ ] Rich media support
- [ ] Reactions
- [ ] Typing indicators
- [ ] Online/offline status

## Dependencies

### System
- ModemManager (for SMS/MMS)
- Qt 5.15+ with QtQuick
- Python 3.8+
- GLib/GObject introspection

### Python Packages
- gi (PyGObject)

## Troubleshooting

### No SMS Sending/Receiving
1. Check ModemManager status: `mmcli -L`
2. Check modem messaging capability: `mmcli -m 0 --messaging-status`
3. Check daemon logs: `tail -f ~/.local/state/flick/messages.log`
4. Verify D-Bus connection in logs

### Permission Denied
- Add user to appropriate groups (plugdev, etc.)
- Check PolicyKit rules for ModemManager

### UI Not Updating
- Check if messages.json is being written: `ls -l ~/.local/state/flick/messages.json`
- Verify daemon is running: `ps aux | grep messaging_daemon`
- Check command file is being processed: `tail -f ~/.local/state/flick/messages.log`

## Development

### Testing Without Modem
The daemon includes a mock mode if D-Bus is not available. For testing:
```bash
# Create test messages file
mkdir -p ~/.local/state/flick
cat > ~/.local/state/flick/messages.json << 'EOF'
{
  "conversations": [
    {
      "phone_number": "+1234567890",
      "contact_name": "Test Contact",
      "last_message": "Test message",
      "last_message_time": "2025-12-27T10:00:00",
      "unread_count": 1,
      "messages": [
        {
          "text": "Hello!",
          "direction": "outgoing",
          "timestamp": "2025-12-27T09:55:00",
          "status": "sent"
        },
        {
          "text": "Test message",
          "direction": "incoming",
          "timestamp": "2025-12-27T10:00:00",
          "status": "delivered"
        }
      ]
    }
  ]
}
EOF

# Run UI only
qmlscene main.qml
```

## Credits

Based on patterns from Flick Phone app (oFono integration) and adapted for ModemManager.
