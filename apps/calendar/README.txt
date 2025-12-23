Flick Calendar App
==================

A first-party calendar application for Flick shell.

Files:
------
- main.qml              : Calendar UI (Qt Quick 2.15)
- run_calendar.sh       : Launch script
- flick-calendar.desktop: Desktop entry file

Features:
---------
- Month view with calendar grid
- Swipe left/right to navigate months
- Tap day to view/add events
- Simple event model: title, date, time
- Events stored in ~/.local/state/flick/calendar.json
- Matches Flick dark theme (#0a0a0f background, #e94560 accent)
- Loads text_scale from display_config.json
- Floating back button (bottom-right)
- Home indicator bar at bottom

Usage:
------
Run directly:
  ./run_calendar.sh

Or use the desktop file for app launcher integration.

Data Storage:
-------------
Events: /home/droidian/.local/state/flick/calendar.json
Logs:   /home/droidian/.local/state/flick/calendar.log

The events file uses JSON format:
{
  "2025-12-23": [
    {"title": "Meeting", "time": "10:00", "date": "2025-12-23"}
  ]
}
