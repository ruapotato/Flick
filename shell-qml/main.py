#!/usr/bin/env python3
"""
Flick Shell - A touch-first QML shell for Flick compositor
"""

import sys
import os
import signal
import subprocess
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot, Property, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterType


class GestureHandler(QObject):
    """Handles gesture events from the compositor via IPC file"""

    gestureStarted = Signal(str, float, float)  # edge, progress, velocity
    gestureUpdated = Signal(str, float, float)  # edge, progress, velocity
    gestureEnded = Signal(str, bool, float)     # edge, completed, velocity

    def __init__(self, parent=None):
        super().__init__(parent)
        self._last_timestamp = None
        self._runtime_dir = os.environ.get('XDG_RUNTIME_DIR', '/run/user/1000')
        self._gesture_file = Path(self._runtime_dir) / 'flick-gesture'

        # Poll for gesture updates
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._check_gesture_file)
        self._timer.start(16)  # ~60fps

    def _check_gesture_file(self):
        try:
            if not self._gesture_file.exists():
                return

            content = self._gesture_file.read_text().strip()
            if not content:
                return

            # Format: timestamp|edge|state|progress|velocity
            parts = content.split('|')
            if len(parts) != 5:
                return

            timestamp, edge, state, progress, velocity = parts

            if timestamp == self._last_timestamp:
                return
            self._last_timestamp = timestamp

            progress = float(progress)
            velocity = float(velocity)

            if state == 'start':
                self.gestureStarted.emit(edge, progress, velocity)
            elif state == 'update':
                self.gestureUpdated.emit(edge, progress, velocity)
            elif state == 'end_complete':
                self.gestureEnded.emit(edge, True, velocity)
            elif state == 'end_cancel':
                self.gestureEnded.emit(edge, False, velocity)

        except Exception as e:
            pass  # Ignore errors during file read


class WindowManager(QObject):
    """Manages window list from compositor"""

    windowsChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._windows = []
        self._last_timestamp = None
        self._runtime_dir = os.environ.get('XDG_RUNTIME_DIR', '/run/user/1000')
        self._windows_file = Path(self._runtime_dir) / 'flick-windows'
        self._focus_file = Path(self._runtime_dir) / 'flick-focus'

        # Poll for window updates
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._check_windows_file)
        self._timer.start(100)

    def _check_windows_file(self):
        try:
            if not self._windows_file.exists():
                return

            content = self._windows_file.read_text().strip()
            if not content:
                return

            lines = content.split('\n')
            if not lines:
                return

            timestamp = lines[0]
            if timestamp == self._last_timestamp:
                return
            self._last_timestamp = timestamp

            # Parse window list
            new_windows = []
            for line in lines[1:]:
                parts = line.split('|')
                if len(parts) >= 3:
                    new_windows.append({
                        'id': int(parts[0]),
                        'title': parts[1],
                        'appClass': parts[2]
                    })

            if new_windows != self._windows:
                self._windows = new_windows
                self.windowsChanged.emit()

        except Exception as e:
            pass

    @Property('QVariantList', notify=windowsChanged)
    def windows(self):
        return self._windows

    @Slot(int)
    def focusWindow(self, window_id):
        try:
            self._focus_file.write_text(str(window_id))
        except Exception as e:
            print(f"Failed to focus window: {e}")


class AppLauncher(QObject):
    """Handles launching applications"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._runtime_dir = os.environ.get('XDG_RUNTIME_DIR', '/run/user/1000')

    def _get_xwayland_display(self):
        display_file = Path(self._runtime_dir) / 'flick-xwayland-display'
        try:
            if display_file.exists():
                return display_file.read_text().strip()
        except:
            pass
        return ':1'

    @Slot(str)
    def launch(self, command):
        display = self._get_xwayland_display()
        env = os.environ.copy()
        env['DISPLAY'] = display

        full_cmd = f'export DISPLAY={display}; {command}'

        try:
            subprocess.Popen(
                ['/bin/sh', '-c', full_cmd],
                env=env,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            print(f"Launched: {command}")
        except Exception as e:
            print(f"Failed to launch {command}: {e}")


def main():
    # Handle Ctrl+C gracefully
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Flick Shell")

    # Create backend objects
    gesture_handler = GestureHandler()
    window_manager = WindowManager()
    app_launcher = AppLauncher()

    # Create QML engine
    engine = QQmlApplicationEngine()

    # Expose Python objects to QML
    engine.rootContext().setContextProperty("gestureHandler", gesture_handler)
    engine.rootContext().setContextProperty("windowManager", window_manager)
    engine.rootContext().setContextProperty("appLauncher", app_launcher)

    # Load QML
    qml_file = Path(__file__).parent / "main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_file)))

    if not engine.rootObjects():
        print("Failed to load QML")
        return 1

    return app.exec()


if __name__ == '__main__':
    sys.exit(main())
