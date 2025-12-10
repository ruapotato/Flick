#!/usr/bin/env python3
"""
Flick Settings - Lock Screen Configuration
A Kivy-based settings app for Flick shell
"""

import os
import json
import hashlib
import logging
from pathlib import Path

# Set up logging FIRST before any Kivy imports
LOG_PATH = Path.home() / ".local" / "state" / "flick" / "flick_settings.log"
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("flick_settings")
logger.info("=" * 50)
logger.info("Flick Settings starting...")

# Kivy configuration - must be before kivy imports
os.environ.setdefault('KIVY_LOG_LEVEL', 'debug')

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.uix.scrollview import ScrollView
from kivy.uix.gridlayout import GridLayout
from kivy.core.window import Window
from kivy.metrics import dp
from kivy.clock import Clock

# Config path
CONFIG_PATH = Path.home() / ".local" / "state" / "flick" / "lock_config.json"

class LockConfig:
    """Lock screen configuration"""
    def __init__(self):
        self.method = "pin"  # none, pin, pattern, password
        self.pin_hash = ""
        self.pattern_hash = ""
        self.timeout_seconds = 0
        self.failed_attempts = 0
        self.lockout_until = 0

    def to_dict(self):
        return {
            "method": self.method,
            "pin_hash": self.pin_hash,
            "pattern_hash": self.pattern_hash,
            "timeout_seconds": self.timeout_seconds,
            "failed_attempts": self.failed_attempts,
            "lockout_until": self.lockout_until,
        }

    @classmethod
    def from_dict(cls, data):
        config = cls()
        config.method = data.get("method", "pin")
        config.pin_hash = data.get("pin_hash", "")
        config.pattern_hash = data.get("pattern_hash", "")
        config.timeout_seconds = data.get("timeout_seconds", 0)
        config.failed_attempts = data.get("failed_attempts", 0)
        config.lockout_until = data.get("lockout_until", 0)
        return config


def hash_pin(pin: str) -> str:
    """Hash a PIN for storage"""
    return hashlib.sha256(pin.encode()).hexdigest()


def hash_pattern(pattern: list) -> str:
    """Hash a pattern for storage"""
    pattern_str = "-".join(str(p) for p in pattern)
    return hashlib.sha256(pattern_str.encode()).hexdigest()


def load_config() -> LockConfig:
    """Load config from file"""
    logger.info(f"Loading config from {CONFIG_PATH}")
    try:
        if CONFIG_PATH.exists():
            with open(CONFIG_PATH) as f:
                data = json.load(f)
                logger.debug(f"Loaded config data: {data}")
                return LockConfig.from_dict(data)
    except Exception as e:
        logger.error(f"Error loading config: {e}")
    logger.info("Using default config")
    return LockConfig()


def save_config(config: LockConfig):
    """Save config to file"""
    logger.info(f"Saving config to {CONFIG_PATH}")
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        data = config.to_dict()
        logger.debug(f"Saving config data: {data}")
        with open(CONFIG_PATH, "w") as f:
            json.dump(data, f, indent=2)
        logger.info("Config saved successfully")
    except Exception as e:
        logger.error(f"Error saving config: {e}")


class SettingsRow(BoxLayout):
    """A single settings row with label and value"""
    def __init__(self, label_text, value_text, on_tap=None, **kwargs):
        super().__init__(**kwargs)
        self.orientation = 'horizontal'
        self.size_hint_y = None
        self.height = dp(60)
        self.padding = [dp(16), dp(8)]
        self.spacing = dp(8)

        left_box = BoxLayout(orientation='vertical', size_hint_x=0.7)
        self.label = Label(
            text=label_text,
            font_size=dp(18),
            halign='left',
            valign='center',
            color=(1, 1, 1, 1)
        )
        self.label.bind(size=self.label.setter('text_size'))

        self.value_label = Label(
            text=value_text,
            font_size=dp(14),
            halign='left',
            valign='center',
            color=(0.7, 0.7, 0.7, 1)
        )
        self.value_label.bind(size=self.value_label.setter('text_size'))

        left_box.add_widget(self.label)
        left_box.add_widget(self.value_label)

        self.add_widget(left_box)

        arrow = Label(
            text='>',
            font_size=dp(24),
            size_hint_x=0.1,
            color=(0.5, 0.5, 0.5, 1)
        )
        self.add_widget(arrow)

        if on_tap:
            self.bind(on_touch_down=lambda w, t: self._handle_touch(t, on_tap))

    def _handle_touch(self, touch, callback):
        if self.collide_point(*touch.pos):
            logger.debug(f"SettingsRow tapped: {self.label.text}")
            callback()
            return True
        return False

    def set_value(self, text):
        self.value_label.text = text


class MethodPickerPopup(Popup):
    """Popup for selecting lock method"""
    def __init__(self, current_method, on_select, **kwargs):
        super().__init__(**kwargs)
        self.title = "Choose Lock Method"
        self.size_hint = (0.9, 0.6)
        self.on_select = on_select

        logger.info(f"MethodPickerPopup opened, current method: {current_method}")

        layout = BoxLayout(orientation='vertical', spacing=dp(8), padding=dp(16))

        methods = [
            ("none", "None", "No lock screen"),
            ("pin", "PIN", "4-6 digit code"),
            ("pattern", "Pattern", "Draw a pattern"),
            ("password", "Password", "Use system password"),
        ]

        for method_id, title, subtitle in methods:
            btn = Button(
                text=f"{title}\n[size=12]{subtitle}[/size]",
                markup=True,
                size_hint_y=None,
                height=dp(60),
                background_color=(0.3, 0.5, 0.8, 1) if method_id == current_method else (0.3, 0.3, 0.3, 1)
            )
            btn.method_id = method_id
            btn.bind(on_release=self._on_method_selected)
            layout.add_widget(btn)

        cancel_btn = Button(
            text="Cancel",
            size_hint_y=None,
            height=dp(50),
            background_color=(0.5, 0.3, 0.3, 1)
        )
        cancel_btn.bind(on_release=lambda x: self.dismiss())
        layout.add_widget(cancel_btn)

        self.content = layout

    def _on_method_selected(self, button):
        method = button.method_id
        logger.info(f"Method selected: {method}")
        self.dismiss()
        logger.debug(f"Popup dismissed, calling on_select callback")
        # Use Clock.schedule_once to ensure popup is fully dismissed
        Clock.schedule_once(lambda dt: self.on_select(method), 0.1)


class PinSetupPopup(Popup):
    """Popup for setting up a PIN"""
    def __init__(self, on_complete, **kwargs):
        super().__init__(**kwargs)
        self.title = "Set PIN"
        self.size_hint = (0.9, 0.7)
        self.on_complete = on_complete
        self.first_pin = None
        self.auto_dismiss = False

        logger.info("PinSetupPopup opened")

        layout = BoxLayout(orientation='vertical', spacing=dp(16), padding=dp(16))

        self.instruction = Label(
            text="Enter a 4-6 digit PIN",
            font_size=dp(16),
            size_hint_y=None,
            height=dp(40)
        )
        layout.add_widget(self.instruction)

        self.pin_display = Label(
            text="",
            font_size=dp(32),
            size_hint_y=None,
            height=dp(50)
        )
        layout.add_widget(self.pin_display)

        self.current_pin = ""

        # Number pad
        numpad = GridLayout(cols=3, spacing=dp(8), size_hint_y=0.6)
        for digit in "123456789":
            btn = Button(text=digit, font_size=dp(24))
            btn.bind(on_release=lambda b: self._add_digit(b.text))
            numpad.add_widget(btn)

        clear_btn = Button(text="C", font_size=dp(24), background_color=(0.8, 0.3, 0.3, 1))
        clear_btn.bind(on_release=lambda x: self._clear())
        numpad.add_widget(clear_btn)

        zero_btn = Button(text="0", font_size=dp(24))
        zero_btn.bind(on_release=lambda b: self._add_digit("0"))
        numpad.add_widget(zero_btn)

        backspace_btn = Button(text="<", font_size=dp(24))
        backspace_btn.bind(on_release=lambda x: self._backspace())
        numpad.add_widget(backspace_btn)

        layout.add_widget(numpad)

        # Buttons
        btn_layout = BoxLayout(size_hint_y=None, height=dp(50), spacing=dp(8))

        cancel_btn = Button(text="Cancel", background_color=(0.5, 0.3, 0.3, 1))
        cancel_btn.bind(on_release=lambda x: self._cancel())
        btn_layout.add_widget(cancel_btn)

        self.ok_btn = Button(text="OK", background_color=(0.3, 0.5, 0.3, 1))
        self.ok_btn.bind(on_release=lambda x: self._confirm())
        self.ok_btn.disabled = True
        btn_layout.add_widget(self.ok_btn)

        layout.add_widget(btn_layout)

        self.content = layout

    def _add_digit(self, digit):
        if len(self.current_pin) < 6:
            self.current_pin += digit
            self.pin_display.text = "*" * len(self.current_pin)
            self.ok_btn.disabled = len(self.current_pin) < 4
            logger.debug(f"PIN digit added, length: {len(self.current_pin)}")

    def _backspace(self):
        if self.current_pin:
            self.current_pin = self.current_pin[:-1]
            self.pin_display.text = "*" * len(self.current_pin)
            self.ok_btn.disabled = len(self.current_pin) < 4

    def _clear(self):
        self.current_pin = ""
        self.pin_display.text = ""
        self.ok_btn.disabled = True

    def _cancel(self):
        logger.info("PIN setup cancelled")
        self.dismiss()

    def _confirm(self):
        if self.first_pin is None:
            self.first_pin = self.current_pin
            self.current_pin = ""
            self.pin_display.text = ""
            self.instruction.text = "Confirm your PIN"
            self.ok_btn.disabled = True
            logger.info("First PIN entered, waiting for confirmation")
        else:
            if self.current_pin == self.first_pin:
                logger.info("PIN confirmed successfully")
                self.dismiss()
                Clock.schedule_once(lambda dt: self.on_complete(self.current_pin), 0.1)
            else:
                logger.warning("PIN mismatch")
                self.instruction.text = "PINs don't match! Try again"
                self.first_pin = None
                self.current_pin = ""
                self.pin_display.text = ""
                self.ok_btn.disabled = True


class PatternSetupPopup(Popup):
    """Popup for setting up a pattern lock (3x3 grid)"""
    def __init__(self, on_complete, **kwargs):
        super().__init__(**kwargs)
        self.title = "Set Pattern"
        self.size_hint = (0.95, 0.85)
        self.on_complete = on_complete
        self.first_pattern = None
        self.auto_dismiss = False
        self.current_pattern = []
        self.dot_widgets = []
        self.line_points = []

        logger.info("PatternSetupPopup opened")

        layout = BoxLayout(orientation='vertical', spacing=dp(16), padding=dp(16))

        self.instruction = Label(
            text="Draw a pattern connecting at least 4 dots",
            font_size=dp(16),
            size_hint_y=None,
            height=dp(40)
        )
        layout.add_widget(self.instruction)

        # Pattern display (shows dots as they're selected)
        self.pattern_display = Label(
            text="",
            font_size=dp(24),
            size_hint_y=None,
            height=dp(30)
        )
        layout.add_widget(self.pattern_display)

        # Pattern grid container
        from kivy.uix.widget import Widget
        from kivy.graphics import Color, Ellipse, Line

        class PatternGrid(Widget):
            def __init__(self, parent_popup, **kwargs):
                super().__init__(**kwargs)
                self.parent_popup = parent_popup
                self.size_hint = (1, 1)
                self.dots = []  # (x, y, index) positions
                self.selected = []  # indices of selected dots
                self.bind(size=self._redraw, pos=self._redraw)

            def _redraw(self, *args):
                self.canvas.clear()
                self._draw_grid()

            def _draw_grid(self):
                self.dots = []
                w, h = self.size
                x0, y0 = self.pos

                # Calculate grid dimensions
                grid_size = min(w, h) * 0.9
                cell_size = grid_size / 3
                dot_radius = cell_size * 0.15

                # Center the grid
                start_x = x0 + (w - grid_size) / 2 + cell_size / 2
                start_y = y0 + (h - grid_size) / 2 + cell_size / 2

                with self.canvas:
                    # Draw connecting lines first (behind dots)
                    if len(self.selected) > 1:
                        Color(0.3, 0.6, 1.0, 0.8)
                        points = []
                        for idx in self.selected:
                            dx, dy, _ = self.dots[idx] if idx < len(self.dots) else (0, 0, 0)
                            if idx < len(self.dots):
                                points.extend([self.dots[idx][0], self.dots[idx][1]])
                        if points:
                            Line(points=points, width=dp(4))

                    # Draw dots
                    for row in range(3):
                        for col in range(3):
                            idx = row * 3 + col
                            cx = start_x + col * cell_size
                            cy = start_y + (2 - row) * cell_size  # Invert Y for top-to-bottom

                            self.dots.append((cx, cy, idx))

                            # Outer ring
                            if idx in self.selected:
                                Color(0.3, 0.6, 1.0, 1.0)  # Blue for selected
                            else:
                                Color(0.5, 0.5, 0.5, 1.0)  # Gray for unselected

                            Ellipse(pos=(cx - dot_radius, cy - dot_radius),
                                   size=(dot_radius * 2, dot_radius * 2))

                            # Inner dot
                            inner_radius = dot_radius * 0.5
                            if idx in self.selected:
                                Color(0.5, 0.8, 1.0, 1.0)
                            else:
                                Color(0.3, 0.3, 0.3, 1.0)
                            Ellipse(pos=(cx - inner_radius, cy - inner_radius),
                                   size=(inner_radius * 2, inner_radius * 2))

                    # Redraw lines on top if needed
                    if len(self.selected) > 1:
                        Color(0.3, 0.6, 1.0, 0.8)
                        points = []
                        for idx in self.selected:
                            if idx < len(self.dots):
                                points.extend([self.dots[idx][0], self.dots[idx][1]])
                        if points:
                            Line(points=points, width=dp(4))

            def _hit_test_dot(self, touch_x, touch_y):
                """Return dot index if touch is near a dot"""
                w, h = self.size
                grid_size = min(w, h) * 0.9
                cell_size = grid_size / 3
                hit_radius = cell_size * 0.35  # Generous hit area

                for cx, cy, idx in self.dots:
                    dist = ((touch_x - cx) ** 2 + (touch_y - cy) ** 2) ** 0.5
                    if dist < hit_radius:
                        return idx
                return None

            def on_touch_down(self, touch):
                if not self.collide_point(*touch.pos):
                    return False

                touch.grab(self)
                self.selected = []
                dot_idx = self._hit_test_dot(*touch.pos)
                if dot_idx is not None:
                    self.selected.append(dot_idx)
                    self.parent_popup._update_pattern_display(self.selected)
                self._redraw()
                return True

            def on_touch_move(self, touch):
                if touch.grab_current != self:
                    return False

                dot_idx = self._hit_test_dot(*touch.pos)
                if dot_idx is not None and dot_idx not in self.selected:
                    self.selected.append(dot_idx)
                    self.parent_popup._update_pattern_display(self.selected)
                    self._redraw()
                return True

            def on_touch_up(self, touch):
                if touch.grab_current != self:
                    return False

                touch.ungrab(self)
                self.parent_popup._on_pattern_drawn(self.selected)
                return True

            def clear_selection(self):
                self.selected = []
                self._redraw()

        self.pattern_grid = PatternGrid(self)
        layout.add_widget(self.pattern_grid)

        # Buttons
        btn_layout = BoxLayout(size_hint_y=None, height=dp(50), spacing=dp(8))

        cancel_btn = Button(text="Cancel", background_color=(0.5, 0.3, 0.3, 1))
        cancel_btn.bind(on_release=lambda x: self._cancel())
        btn_layout.add_widget(cancel_btn)

        clear_btn = Button(text="Clear", background_color=(0.5, 0.5, 0.3, 1))
        clear_btn.bind(on_release=lambda x: self._clear())
        btn_layout.add_widget(clear_btn)

        self.ok_btn = Button(text="OK", background_color=(0.3, 0.5, 0.3, 1))
        self.ok_btn.bind(on_release=lambda x: self._confirm())
        self.ok_btn.disabled = True
        btn_layout.add_widget(self.ok_btn)

        layout.add_widget(btn_layout)

        self.content = layout

    def _update_pattern_display(self, pattern):
        self.current_pattern = list(pattern)
        # Show dots as numbers (1-9 for user-friendly display)
        display = " → ".join(str(p + 1) for p in pattern)
        self.pattern_display.text = display
        self.ok_btn.disabled = len(pattern) < 4

    def _on_pattern_drawn(self, pattern):
        """Called when user lifts finger after drawing"""
        self.current_pattern = list(pattern)
        self.ok_btn.disabled = len(pattern) < 4
        logger.debug(f"Pattern drawn: {pattern}, length: {len(pattern)}")

    def _clear(self):
        self.current_pattern = []
        self.pattern_display.text = ""
        self.pattern_grid.clear_selection()
        self.ok_btn.disabled = True

    def _cancel(self):
        logger.info("Pattern setup cancelled")
        self.dismiss()

    def _confirm(self):
        if len(self.current_pattern) < 4:
            return

        if self.first_pattern is None:
            self.first_pattern = list(self.current_pattern)
            self._clear()
            self.instruction.text = "Draw pattern again to confirm"
            logger.info("First pattern entered, waiting for confirmation")
        else:
            if self.current_pattern == self.first_pattern:
                logger.info("Pattern confirmed successfully")
                self.dismiss()
                Clock.schedule_once(lambda dt: self.on_complete(self.current_pattern), 0.1)
            else:
                logger.warning("Pattern mismatch")
                self.instruction.text = "Patterns don't match! Try again"
                self.first_pattern = None
                self._clear()


class TimeoutPickerPopup(Popup):
    """Popup for selecting lock timeout"""
    def __init__(self, current_timeout, on_select, **kwargs):
        super().__init__(**kwargs)
        self.title = "Lock Timeout"
        self.size_hint = (0.9, 0.6)
        self.on_select = on_select

        logger.info(f"TimeoutPickerPopup opened, current timeout: {current_timeout}")

        layout = BoxLayout(orientation='vertical', spacing=dp(8), padding=dp(16))

        timeouts = [
            (0, "Immediately"),
            (60, "1 minute"),
            (300, "5 minutes"),
            (900, "15 minutes"),
            (-1, "Never"),
        ]

        for timeout_val, label in timeouts:
            btn = Button(
                text=label,
                size_hint_y=None,
                height=dp(50),
                background_color=(0.3, 0.5, 0.8, 1) if timeout_val == current_timeout else (0.3, 0.3, 0.3, 1)
            )
            btn.timeout_val = timeout_val
            btn.bind(on_release=self._on_timeout_selected)
            layout.add_widget(btn)

        cancel_btn = Button(
            text="Cancel",
            size_hint_y=None,
            height=dp(50),
            background_color=(0.5, 0.3, 0.3, 1)
        )
        cancel_btn.bind(on_release=lambda x: self.dismiss())
        layout.add_widget(cancel_btn)

        self.content = layout

    def _on_timeout_selected(self, button):
        timeout = button.timeout_val
        logger.info(f"Timeout selected: {timeout}")
        self.dismiss()
        Clock.schedule_once(lambda dt: self.on_select(timeout), 0.1)


class FlickSettingsApp(App):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.config_data = load_config()
        logger.info(f"App initialized with method: {self.config_data.method}")

    def build(self):
        logger.info("Building UI")

        Window.clearcolor = (0.1, 0.1, 0.15, 1)

        root = BoxLayout(orientation='vertical')

        # Header
        header = BoxLayout(size_hint_y=None, height=dp(60), padding=[dp(16), dp(8)])
        header_label = Label(
            text="Lock Screen Settings",
            font_size=dp(22),
            halign='left',
            valign='center'
        )
        header_label.bind(size=header_label.setter('text_size'))
        header.add_widget(header_label)
        root.add_widget(header)

        # Settings list
        scroll = ScrollView()
        settings_list = BoxLayout(
            orientation='vertical',
            size_hint_y=None,
            spacing=dp(2)
        )
        settings_list.bind(minimum_height=settings_list.setter('height'))

        # Lock method row
        self.method_row = SettingsRow(
            "Lock method",
            self._method_label(self.config_data.method),
            on_tap=self._show_method_picker
        )
        settings_list.add_widget(self.method_row)

        # Timeout row
        self.timeout_row = SettingsRow(
            "Lock timeout",
            self._timeout_label(self.config_data.timeout_seconds),
            on_tap=self._show_timeout_picker
        )
        settings_list.add_widget(self.timeout_row)

        # Change PIN/Pattern row (conditional)
        self.change_row = SettingsRow(
            "Change PIN",
            "Tap to change",
            on_tap=self._change_credential
        )
        self._update_change_row()
        settings_list.add_widget(self.change_row)

        scroll.add_widget(settings_list)
        root.add_widget(scroll)

        # Footer note
        footer = Label(
            text="Note: You can always use your system\npassword to unlock.",
            font_size=dp(12),
            color=(0.5, 0.5, 0.5, 1),
            size_hint_y=None,
            height=dp(60)
        )
        root.add_widget(footer)

        logger.info("UI built successfully")
        return root

    def _method_label(self, method):
        labels = {
            "none": "None",
            "pin": "PIN",
            "pattern": "Pattern",
            "password": "Password"
        }
        return labels.get(method, method)

    def _timeout_label(self, seconds):
        if seconds == 0:
            return "Immediately"
        elif seconds == 60:
            return "1 minute"
        elif seconds == 300:
            return "5 minutes"
        elif seconds == 900:
            return "15 minutes"
        elif seconds < 0:
            return "Never"
        return f"{seconds} seconds"

    def _update_change_row(self):
        if self.config_data.method == "pin":
            self.change_row.label.text = "Change PIN"
            self.change_row.value_label.text = "Tap to change"
            self.change_row.opacity = 1
            self.change_row.disabled = False
        elif self.config_data.method == "pattern":
            self.change_row.label.text = "Change pattern"
            self.change_row.value_label.text = "Tap to change"
            self.change_row.opacity = 1
            self.change_row.disabled = False
        else:
            self.change_row.opacity = 0
            self.change_row.disabled = True

    def _show_method_picker(self):
        logger.info("Opening method picker")
        popup = MethodPickerPopup(
            current_method=self.config_data.method,
            on_select=self._on_method_selected
        )
        popup.open()

    def _on_method_selected(self, method):
        logger.info(f"Method selected callback: {method}")

        if method == self.config_data.method:
            logger.info("Same method selected, no change needed")
            return

        if method == "pin":
            logger.info("Showing PIN setup")
            popup = PinSetupPopup(on_complete=self._on_pin_set)
            popup.open()
        elif method == "pattern":
            logger.info("Showing pattern setup")
            popup = PatternSetupPopup(on_complete=self._on_pattern_set)
            popup.open()
        else:
            # none or password - no setup needed
            logger.info(f"Setting method to {method} (no setup needed)")
            self.config_data.method = method
            save_config(self.config_data)
            self.method_row.set_value(self._method_label(method))
            self._update_change_row()

    def _on_pin_set(self, pin):
        logger.info("PIN set callback")
        self.config_data.method = "pin"
        self.config_data.pin_hash = hash_pin(pin)
        save_config(self.config_data)
        self.method_row.set_value(self._method_label("pin"))
        self._update_change_row()
        logger.info("PIN saved successfully")

    def _on_pattern_set(self, pattern):
        logger.info("Pattern set callback")
        self.config_data.method = "pattern"
        self.config_data.pattern_hash = hash_pattern(pattern)
        save_config(self.config_data)
        self.method_row.set_value(self._method_label("pattern"))
        self._update_change_row()
        logger.info("Pattern saved successfully")

    def _show_timeout_picker(self):
        logger.info("Opening timeout picker")
        popup = TimeoutPickerPopup(
            current_timeout=self.config_data.timeout_seconds,
            on_select=self._on_timeout_selected
        )
        popup.open()

    def _on_timeout_selected(self, timeout):
        logger.info(f"Timeout selected callback: {timeout}")
        self.config_data.timeout_seconds = timeout
        save_config(self.config_data)
        self.timeout_row.set_value(self._timeout_label(timeout))

    def _change_credential(self):
        logger.info(f"Change credential tapped for method: {self.config_data.method}")
        if self.config_data.method == "pin":
            popup = PinSetupPopup(on_complete=self._on_pin_set)
            popup.open()
        elif self.config_data.method == "pattern":
            popup = PatternSetupPopup(on_complete=self._on_pattern_set)
            popup.open()


if __name__ == "__main__":
    logger.info("Starting FlickSettingsApp")
    try:
        FlickSettingsApp().run()
    except Exception as e:
        logger.exception(f"App crashed: {e}")
        raise
