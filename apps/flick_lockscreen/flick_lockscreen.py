#!/usr/bin/env python3
"""
Flick Lock Screen - Full-screen lock with PIN, pattern, and password support
A Kivy-based lock screen for Flick shell with smooth animations
"""

import os
import sys
import json
import hashlib
import subprocess
import logging
from datetime import datetime
from pathlib import Path
from time import time

# Set up logging
LOG_PATH = Path.home() / ".local" / "state" / "flick" / "flick_lockscreen.log"
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("flick_lockscreen")
logger.info("=" * 50)
logger.info("Flick Lock Screen starting...")

# Kivy config - must be before kivy imports
os.environ.setdefault('KIVY_LOG_LEVEL', 'debug')

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.gridlayout import GridLayout
from kivy.uix.widget import Widget
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.core.window import Window
from kivy.graphics import Color, Ellipse, Line, Rectangle, RoundedRectangle
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.animation import Animation
from kivy.properties import StringProperty, NumericProperty, ListProperty, BooleanProperty

# Config and signal paths
CONFIG_PATH = Path.home() / ".local" / "state" / "flick" / "lock_config.json"
UNLOCK_SIGNAL_PATH = Path.home() / ".local" / "state" / "flick" / "unlock_signal"

# Theme colors (matching Flick dark theme)
THEME = {
    'background': (0.06, 0.06, 0.08, 1),       # Very dark
    'surface': (0.12, 0.12, 0.14, 1),          # Card background
    'surface_variant': (0.18, 0.18, 0.22, 1),  # Button background
    'primary': (0.4, 0.6, 1.0, 1),             # Blue accent
    'primary_dark': (0.3, 0.5, 0.9, 1),        # Darker blue
    'on_surface': (1, 1, 1, 1),                # White text
    'on_surface_variant': (0.6, 0.6, 0.65, 1), # Gray text
    'error': (0.9, 0.3, 0.3, 1),               # Red for errors
}


class LockConfig:
    """Lock screen configuration - matches Rust LockConfig"""
    def __init__(self):
        self.method = "none"  # none, pin, pattern, password
        self.pin_hash = ""
        self.pattern_hash = ""
        self.timeout_seconds = 300
        self.failed_attempts = 0
        self.lockout_until = 0

    @classmethod
    def load(cls):
        config = cls()
        try:
            if CONFIG_PATH.exists():
                with open(CONFIG_PATH) as f:
                    data = json.load(f)
                    config.method = data.get("method", "none")
                    config.pin_hash = data.get("pin_hash", "")
                    config.pattern_hash = data.get("pattern_hash", "")
                    config.timeout_seconds = data.get("timeout_seconds", 300)
                    config.failed_attempts = data.get("failed_attempts", 0)
                    config.lockout_until = data.get("lockout_until", 0)
                    logger.info(f"Loaded config: method={config.method}")
        except Exception as e:
            logger.error(f"Error loading config: {e}")
        return config

    def verify_pin(self, pin: str) -> bool:
        """Verify PIN against stored hash (SHA256)"""
        if not self.pin_hash:
            return False
        entered_hash = hashlib.sha256(pin.encode()).hexdigest()
        return entered_hash == self.pin_hash

    def verify_pattern(self, pattern: list) -> bool:
        """Verify pattern against stored hash (SHA256)"""
        if not self.pattern_hash:
            return False
        pattern_str = "-".join(str(p) for p in pattern)
        entered_hash = hashlib.sha256(pattern_str.encode()).hexdigest()
        return entered_hash == self.pattern_hash


def signal_unlock():
    """Signal to compositor that unlock was successful"""
    logger.info("Signaling unlock to compositor")
    try:
        UNLOCK_SIGNAL_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(UNLOCK_SIGNAL_PATH, 'w') as f:
            f.write(str(int(time())))
        logger.info(f"Wrote unlock signal to {UNLOCK_SIGNAL_PATH}")
    except Exception as e:
        logger.error(f"Failed to write unlock signal: {e}")


def authenticate_pam(password: str) -> bool:
    """Authenticate using PAM (system password)"""
    try:
        import pam
        p = pam.pam()
        user = os.environ.get('USER', 'root')
        result = p.authenticate(user, password)
        logger.info(f"PAM auth for {user}: {result}")
        return result
    except ImportError:
        logger.warning("python-pam not installed, trying simple auth")
        # Fallback: try su command
        try:
            result = subprocess.run(
                ['su', '-c', 'true', os.environ.get('USER', 'root')],
                input=password.encode(),
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Fallback auth failed: {e}")
            return False
    except Exception as e:
        logger.error(f"PAM auth error: {e}")
        return False


class PinButton(Button):
    """Styled PIN pad button"""
    def __init__(self, text, **kwargs):
        super().__init__(**kwargs)
        self.text = text
        self.background_color = (0, 0, 0, 0)  # Transparent
        self.font_size = dp(28)
        self.color = THEME['on_surface']
        self.size_hint = (None, None)
        self.size = (dp(80), dp(80))
        self._bg_color = THEME['surface_variant']
        self.bind(pos=self._update_canvas, size=self._update_canvas)
        self.bind(state=self._on_state)
        Clock.schedule_once(lambda dt: self._update_canvas())

    def _update_canvas(self, *args):
        self.canvas.before.clear()
        with self.canvas.before:
            Color(*self._bg_color)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(40)])

    def _on_state(self, instance, value):
        if value == 'down':
            self._bg_color = THEME['primary_dark']
        else:
            self._bg_color = THEME['surface_variant']
        self._update_canvas()


class PinPad(GridLayout):
    """PIN pad widget with 3x4 grid"""
    def __init__(self, on_digit, on_backspace, **kwargs):
        super().__init__(**kwargs)
        self.cols = 3
        self.spacing = dp(16)
        self.size_hint = (None, None)
        self.width = dp(80) * 3 + dp(16) * 2
        self.height = dp(80) * 4 + dp(16) * 3

        self.on_digit = on_digit
        self.on_backspace = on_backspace

        # Create buttons 1-9
        for i in range(1, 10):
            btn = PinButton(str(i))
            btn.bind(on_release=lambda b: self.on_digit(b.text))
            self.add_widget(btn)

        # Empty, 0, Backspace
        empty = Widget(size_hint=(None, None), size=(dp(80), dp(80)))
        self.add_widget(empty)

        zero = PinButton("0")
        zero.bind(on_release=lambda b: self.on_digit("0"))
        self.add_widget(zero)

        backspace = PinButton("<")
        backspace.bind(on_release=lambda b: self.on_backspace())
        self.add_widget(backspace)


class PatternGrid(Widget):
    """3x3 pattern grid for pattern unlock"""
    pattern = ListProperty([])
    is_drawing = BooleanProperty(False)

    def __init__(self, on_complete, **kwargs):
        super().__init__(**kwargs)
        self.on_complete = on_complete
        self.dots = []  # [(x, y, index), ...]
        self.selected = []
        self.current_touch = None
        self.size_hint = (None, None)
        self.size = (dp(280), dp(280))
        self.bind(pos=self._redraw, size=self._redraw)
        Clock.schedule_once(lambda dt: self._redraw())

    def _redraw(self, *args):
        self.canvas.clear()
        self.dots = []
        w, h = self.size
        x0, y0 = self.pos

        grid_size = min(w, h) * 0.9
        cell_size = grid_size / 3
        dot_radius = dp(15)

        start_x = x0 + (w - grid_size) / 2 + cell_size / 2
        start_y = y0 + (h - grid_size) / 2 + cell_size / 2

        with self.canvas:
            # Draw connecting lines
            if len(self.selected) > 1:
                Color(*THEME['primary'], 0.8)
                points = []
                for idx in self.selected:
                    if idx < len(self.dots):
                        points.extend([self.dots[idx][0], self.dots[idx][1]])
                # Add current touch position if drawing
                if self.current_touch and self.is_drawing:
                    points.extend([self.current_touch[0], self.current_touch[1]])
                if len(points) >= 4:
                    Line(points=points, width=dp(4))
            elif len(self.selected) == 1 and self.current_touch and self.is_drawing:
                Color(*THEME['primary'], 0.8)
                idx = self.selected[0]
                if idx < len(self.dots):
                    Line(points=[self.dots[idx][0], self.dots[idx][1],
                                self.current_touch[0], self.current_touch[1]], width=dp(4))

            # Draw dots
            for row in range(3):
                for col in range(3):
                    idx = row * 3 + col
                    cx = start_x + col * cell_size
                    cy = start_y + (2 - row) * cell_size

                    self.dots.append((cx, cy, idx))

                    # Outer circle
                    if idx in self.selected:
                        Color(*THEME['primary'])
                    else:
                        Color(*THEME['surface_variant'])
                    Ellipse(pos=(cx - dot_radius, cy - dot_radius),
                           size=(dot_radius * 2, dot_radius * 2))

                    # Inner dot
                    inner = dot_radius * 0.5
                    if idx in self.selected:
                        Color(*THEME['primary'], 1.0)
                    else:
                        Color(0.3, 0.3, 0.35, 1)
                    Ellipse(pos=(cx - inner, cy - inner),
                           size=(inner * 2, inner * 2))

    def _hit_test(self, x, y):
        hit_radius = dp(40)
        for cx, cy, idx in self.dots:
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if dist < hit_radius:
                return idx
        return None

    def on_touch_down(self, touch):
        if not self.collide_point(*touch.pos):
            return False
        touch.grab(self)
        self.selected = []
        self.is_drawing = True
        self.current_touch = touch.pos
        idx = self._hit_test(*touch.pos)
        if idx is not None:
            self.selected.append(idx)
        self._redraw()
        return True

    def on_touch_move(self, touch):
        if touch.grab_current != self:
            return False
        self.current_touch = touch.pos
        idx = self._hit_test(*touch.pos)
        if idx is not None and idx not in self.selected:
            self.selected.append(idx)
        self._redraw()
        return True

    def on_touch_up(self, touch):
        if touch.grab_current != self:
            return False
        touch.ungrab(self)
        self.is_drawing = False
        self.current_touch = None
        if len(self.selected) >= 4:
            self.on_complete(list(self.selected))
        self._redraw()
        return True

    def clear(self):
        self.selected = []
        self.is_drawing = False
        self.current_touch = None
        self._redraw()


class LockScreenApp(App):
    time_text = StringProperty("12:00")
    date_text = StringProperty("Saturday, December 7")
    pin_dots = NumericProperty(0)
    error_message = StringProperty("")
    lockout_message = StringProperty("")

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.lock_config = LockConfig.load()  # Renamed to avoid conflict with Kivy's App.config
        self.entered_pin = ""
        self.entered_password = ""
        self.failed_attempts = 0
        self.lockout_until = 0
        logger.info(f"Lock screen initialized with method: {self.lock_config.method}")

    def build(self):
        Window.clearcolor = THEME['background']

        # Update time every second
        Clock.schedule_interval(self._update_time, 1)
        self._update_time(0)

        # Check if no lock needed
        if self.lock_config.method == "none":
            logger.info("No lock method configured, unlocking immediately")
            Clock.schedule_once(lambda dt: self._unlock(), 0.1)
            return Label(text="Unlocking...", color=THEME['on_surface'])

        root = FloatLayout()

        # Main content
        content = BoxLayout(orientation='vertical', spacing=dp(16), padding=dp(32))
        content.pos_hint = {'center_x': 0.5, 'center_y': 0.5}
        content.size_hint = (0.9, 0.9)

        # Spacer at top
        content.add_widget(Widget(size_hint_y=0.1))

        # Time
        self.time_label = Label(
            text=self.time_text,
            font_size=dp(72),
            color=THEME['on_surface'],
            size_hint_y=None,
            height=dp(90)
        )
        self.bind(time_text=self.time_label.setter('text'))
        content.add_widget(self.time_label)

        # Date
        self.date_label = Label(
            text=self.date_text,
            font_size=dp(18),
            color=THEME['on_surface_variant'],
            size_hint_y=None,
            height=dp(30)
        )
        self.bind(date_text=self.date_label.setter('text'))
        content.add_widget(self.date_label)

        content.add_widget(Widget(size_hint_y=None, height=dp(24)))

        # Mode label
        mode_text = {
            'pin': 'Enter PIN',
            'pattern': 'Draw Pattern',
            'password': 'Enter Password'
        }.get(self.lock_config.method, '')

        mode_label = Label(
            text=mode_text,
            font_size=dp(16),
            color=THEME['on_surface_variant'],
            size_hint_y=None,
            height=dp(24)
        )
        content.add_widget(mode_label)

        content.add_widget(Widget(size_hint_y=None, height=dp(8)))

        # Lockout message
        self.lockout_label = Label(
            text="",
            font_size=dp(16),
            color=THEME['error'],
            size_hint_y=None,
            height=dp(24)
        )
        self.bind(lockout_message=self.lockout_label.setter('text'))
        content.add_widget(self.lockout_label)

        # PIN dots (for PIN mode)
        if self.lock_config.method == "pin":
            dots_container = BoxLayout(
                orientation='horizontal',
                spacing=dp(16),
                size_hint=(None, None),
                size=(dp(16) * 6 + dp(16) * 5, dp(20)),
                pos_hint={'center_x': 0.5}
            )
            self.dot_widgets = []
            for i in range(6):
                dot = Widget(size_hint=(None, None), size=(dp(16), dp(16)))
                self.dot_widgets.append(dot)
                dots_container.add_widget(dot)
            content.add_widget(dots_container)
            self._update_pin_dots()

        # Error message
        self.error_label = Label(
            text="",
            font_size=dp(14),
            color=THEME['error'],
            size_hint_y=None,
            height=dp(24)
        )
        self.bind(error_message=self.error_label.setter('text'))
        content.add_widget(self.error_label)

        content.add_widget(Widget(size_hint_y=None, height=dp(16)))

        # Input area based on mode
        if self.lock_config.method == "pin":
            pin_container = BoxLayout(size_hint=(None, None), pos_hint={'center_x': 0.5})
            pin_container.size = (dp(280), dp(360))
            self.pin_pad = PinPad(
                on_digit=self._on_pin_digit,
                on_backspace=self._on_pin_backspace
            )
            pin_container.add_widget(self.pin_pad)
            content.add_widget(pin_container)

        elif self.lock_config.method == "pattern":
            pattern_container = BoxLayout(size_hint=(None, None), pos_hint={'center_x': 0.5})
            pattern_container.size = (dp(280), dp(280))
            self.pattern_grid = PatternGrid(on_complete=self._on_pattern_complete)
            pattern_container.add_widget(self.pattern_grid)
            content.add_widget(pattern_container)

        elif self.lock_config.method == "password":
            # Password input field
            self.password_input = TextInput(
                password=True,
                multiline=False,
                font_size=dp(18),
                size_hint=(None, None),
                size=(dp(280), dp(56)),
                pos_hint={'center_x': 0.5},
                background_color=THEME['surface_variant'],
                foreground_color=THEME['on_surface'],
                cursor_color=THEME['primary'],
                hint_text="Enter password",
                hint_text_color=THEME['on_surface_variant']
            )
            content.add_widget(self.password_input)

            # Submit button
            submit_btn = Button(
                text="Unlock",
                font_size=dp(16),
                size_hint=(None, None),
                size=(dp(280), dp(48)),
                pos_hint={'center_x': 0.5},
                background_color=THEME['primary'],
                color=THEME['on_surface']
            )
            submit_btn.bind(on_release=lambda b: self._on_password_submit())
            content.add_widget(submit_btn)

        # Spacer
        content.add_widget(Widget(size_hint_y=0.1))

        # "Use Password" fallback (for PIN/Pattern modes)
        if self.lock_config.method in ['pin', 'pattern']:
            fallback_btn = Button(
                text="Use Password",
                font_size=dp(14),
                size_hint=(None, None),
                size=(dp(200), dp(40)),
                pos_hint={'center_x': 0.5},
                background_color=(0, 0, 0, 0),
                color=THEME['primary']
            )
            fallback_btn.bind(on_release=lambda b: self._switch_to_password())
            content.add_widget(fallback_btn)

        content.add_widget(Widget(size_hint_y=0.05))

        root.add_widget(content)
        return root

    def _update_time(self, dt):
        now = datetime.now()
        self.time_text = now.strftime("%H:%M")
        self.date_text = now.strftime("%A, %B %d")

    def _update_pin_dots(self):
        if not hasattr(self, 'dot_widgets'):
            return
        for i, dot in enumerate(self.dot_widgets):
            dot.canvas.clear()
            with dot.canvas:
                if i < len(self.entered_pin):
                    Color(*THEME['primary'])
                else:
                    Color(*THEME['surface_variant'])
                Ellipse(pos=dot.pos, size=dot.size)

    def _on_pin_digit(self, digit):
        if self._is_locked_out():
            return
        if len(self.entered_pin) < 6:
            self.entered_pin += digit
            self._update_pin_dots()
            logger.debug(f"PIN digit entered, length: {len(self.entered_pin)}")

            # Auto-verify at 4-6 digits
            if len(self.entered_pin) >= 4:
                Clock.schedule_once(lambda dt: self._try_verify_pin(), 0.3)

    def _on_pin_backspace(self):
        if self.entered_pin:
            self.entered_pin = self.entered_pin[:-1]
            self._update_pin_dots()
            self.error_message = ""

    def _try_verify_pin(self):
        if self.lock_config.verify_pin(self.entered_pin):
            logger.info("PIN verified successfully")
            self._unlock()
        elif len(self.entered_pin) == 6:
            # Only show error at max length
            self._record_failed_attempt("PIN")
            self.entered_pin = ""
            self._update_pin_dots()

    def _on_pattern_complete(self, pattern):
        if self._is_locked_out():
            self.pattern_grid.clear()
            return

        logger.debug(f"Pattern completed: {pattern}")
        if self.lock_config.verify_pattern(pattern):
            logger.info("Pattern verified successfully")
            self._unlock()
        else:
            self._record_failed_attempt("pattern")
            Clock.schedule_once(lambda dt: self.pattern_grid.clear(), 0.5)

    def _on_password_submit(self):
        if self._is_locked_out():
            return

        password = self.password_input.text
        if not password:
            return

        if authenticate_pam(password):
            logger.info("Password verified successfully")
            self._unlock()
        else:
            self._record_failed_attempt("password")
            self.password_input.text = ""

    def _switch_to_password(self):
        logger.info("Switching to password mode")
        # This would need to rebuild UI - for simplicity, just note it
        self.error_message = "Password mode - restart with password config"

    def _record_failed_attempt(self, auth_type):
        self.failed_attempts += 1
        remaining = 5 - self.failed_attempts
        if remaining > 0:
            self.error_message = f"Wrong {auth_type}. {remaining} attempts remaining."
        else:
            self.lockout_until = time() + 30
            self.lockout_message = "Too many attempts. Try again in 30s."
            self.error_message = ""
            Clock.schedule_interval(self._update_lockout, 1)
        logger.warning(f"Failed {auth_type} attempt #{self.failed_attempts}")

    def _update_lockout(self, dt):
        remaining = int(self.lockout_until - time())
        if remaining <= 0:
            self.lockout_message = ""
            self.failed_attempts = 0
            return False  # Stop the interval
        self.lockout_message = f"Too many attempts. Try again in {remaining}s."

    def _is_locked_out(self):
        if self.failed_attempts >= 5:
            return time() < self.lockout_until
        return False

    def _unlock(self):
        """Successful unlock - signal compositor and exit"""
        logger.info("UNLOCK SUCCESSFUL")
        signal_unlock()
        # Animate out and exit
        anim = Animation(opacity=0, duration=0.3)
        anim.bind(on_complete=lambda a, w: self._exit_app())
        if self.root:
            anim.start(self.root)
        else:
            self._exit_app()

    def _exit_app(self):
        logger.info("Exiting lock screen app")
        App.get_running_app().stop()
        sys.exit(0)  # Exit code 0 = successful unlock


if __name__ == "__main__":
    logger.info("Starting FlickLockScreenApp")
    try:
        LockScreenApp().run()
    except Exception as e:
        logger.exception(f"App crashed: {e}")
        sys.exit(1)
