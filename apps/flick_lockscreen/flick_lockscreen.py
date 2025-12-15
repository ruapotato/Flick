#!/usr/bin/env python3
"""
Flick Lock Screen - Full-screen lock with stunning visual effects
A Kivy-based lock screen for Flick shell with smooth animations and glow effects
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
import math

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
# Force SDL2 to use Wayland backend
os.environ['SDL_VIDEODRIVER'] = 'wayland'
# Disable SDL2 touch-to-mouse emulation to prevent double inputs
# When this is enabled (default), SDL2 generates both touch AND synthetic mouse events
# for the same physical touch, causing buttons to register twice
os.environ['SDL_TOUCH_MOUSE_EVENTS'] = '0'

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.relativelayout import RelativeLayout
from kivy.uix.gridlayout import GridLayout
from kivy.uix.widget import Widget
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.core.window import Window
from kivy.graphics import Color, Ellipse, Line, Rectangle, RoundedRectangle
from kivy.graphics import PushMatrix, PopMatrix, Scale, Rotate, Translate
from kivy.graphics.texture import Texture
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.animation import Animation
from kivy.properties import StringProperty, NumericProperty, ListProperty, BooleanProperty

# Config and signal paths
CONFIG_PATH = Path.home() / ".local" / "state" / "flick" / "lock_config.json"
UNLOCK_SIGNAL_PATH = Path.home() / ".local" / "state" / "flick" / "unlock_signal"
KEYBOARD_REQUEST_PATH = Path.home() / ".local" / "state" / "flick" / "keyboard_request"

# Stunning dark theme with accent colors
THEME = {
    'bg_dark': (0.04, 0.04, 0.06, 1),           # Near black
    'bg_gradient_top': (0.08, 0.10, 0.16, 1),   # Slight blue tint
    'bg_gradient_bottom': (0.02, 0.02, 0.04, 1), # Deep black
    'surface': (0.10, 0.10, 0.14, 1),           # Card background
    'surface_light': (0.16, 0.16, 0.20, 1),     # Lighter surface
    'accent': (0.30, 0.60, 1.0, 1),             # Vibrant blue
    'accent_glow': (0.40, 0.70, 1.0, 0.6),      # Blue glow
    'accent_bright': (0.50, 0.80, 1.0, 1),      # Bright blue
    'success': (0.20, 0.85, 0.50, 1),           # Green
    'success_glow': (0.30, 0.95, 0.60, 0.6),    # Green glow
    'error': (1.0, 0.35, 0.35, 1),              # Red
    'error_glow': (1.0, 0.40, 0.40, 0.5),       # Red glow
    'text_primary': (1, 1, 1, 1),               # Pure white
    'text_secondary': (0.65, 0.65, 0.70, 1),    # Light gray
    'text_dim': (0.45, 0.45, 0.50, 1),          # Dim gray
    'dot_unselected': (0.25, 0.25, 0.30, 1),    # Gray dots
    'dot_inner': (0.15, 0.15, 0.18, 1),         # Inner dot
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
        self.background_image = ""  # Path to background image

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
                    config.background_image = data.get("background_image", "")
                    logger.info(f"Loaded config: method={config.method}, bg_image={config.background_image}")
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

    def needs_setup(self) -> bool:
        """Check if a method is set but credentials are missing"""
        if self.method == "pin" and not self.pin_hash:
            return True
        if self.method == "pattern" and not self.pattern_hash:
            return True
        return False


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


def request_keyboard(show: bool):
    """Request compositor to show or hide the on-screen keyboard"""
    logger.info(f"Requesting keyboard: {'show' if show else 'hide'}")
    try:
        KEYBOARD_REQUEST_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(KEYBOARD_REQUEST_PATH, 'w') as f:
            f.write("show" if show else "hide")
        logger.info(f"Wrote keyboard request to {KEYBOARD_REQUEST_PATH}")
    except Exception as e:
        logger.error(f"Failed to write keyboard request: {e}")


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


class GlowingPinButton(Button):
    """Stunning PIN pad button with glow effect"""
    glow_alpha = NumericProperty(0)

    def __init__(self, text, **kwargs):
        super().__init__(**kwargs)
        self.text = text
        self.background_color = (0, 0, 0, 0)
        self.font_size = dp(32)
        self.bold = True
        self.color = THEME['text_primary']
        self.size_hint = (None, None)
        self.size = (dp(85), dp(85))
        self._base_color = THEME['surface_light']
        self.bind(pos=self._update_canvas, size=self._update_canvas)
        self.bind(state=self._on_state)
        self.bind(glow_alpha=self._update_canvas)
        Clock.schedule_once(lambda dt: self._update_canvas())

    def _update_canvas(self, *args):
        self.canvas.before.clear()
        with self.canvas.before:
            # Glow effect (larger, blurred circle behind)
            if self.glow_alpha > 0:
                Color(THEME['accent'][0], THEME['accent'][1], THEME['accent'][2], self.glow_alpha * 0.3)
                glow_size = self.size[0] * 1.3
                glow_offset = (self.size[0] - glow_size) / 2
                Ellipse(pos=(self.pos[0] + glow_offset, self.pos[1] + glow_offset),
                       size=(glow_size, glow_size))

            # Main button circle
            r, g, b, a = self._base_color
            if self.glow_alpha > 0:
                # Blend with accent color when pressed
                r = r + (THEME['accent'][0] - r) * self.glow_alpha
                g = g + (THEME['accent'][1] - g) * self.glow_alpha
                b = b + (THEME['accent'][2] - b) * self.glow_alpha
            Color(r, g, b, a)
            Ellipse(pos=self.pos, size=self.size)

    def _on_state(self, instance, value):
        if value == 'down':
            anim = Animation(glow_alpha=1, duration=0.1)
            anim.start(self)
        else:
            anim = Animation(glow_alpha=0, duration=0.2)
            anim.start(self)


class GlowingPinPad(GridLayout):
    """PIN pad widget with glowing buttons"""
    def __init__(self, on_digit, on_backspace, **kwargs):
        super().__init__(**kwargs)
        self.cols = 3
        self.spacing = dp(16)
        self.size_hint = (None, None)
        self.width = dp(85) * 3 + dp(16) * 2
        self.height = dp(85) * 4 + dp(16) * 3

        self.on_digit = on_digit
        self.on_backspace = on_backspace

        # Create buttons 1-9
        for i in range(1, 10):
            btn = GlowingPinButton(str(i))
            btn.bind(on_release=lambda b: self.on_digit(b.text))
            self.add_widget(btn)

        # Empty, 0, Backspace
        empty = Widget(size_hint=(None, None), size=(dp(85), dp(85)))
        self.add_widget(empty)

        zero = GlowingPinButton("0")
        zero.bind(on_release=lambda b: self.on_digit("0"))
        self.add_widget(zero)

        backspace = GlowingPinButton("<")
        backspace.bind(on_release=lambda b: self.on_backspace())
        self.add_widget(backspace)


class GlowingPatternGrid(Widget):
    """Stunning 3x3 pattern grid with glow effects and smooth animations"""
    pattern = ListProperty([])
    is_drawing = BooleanProperty(False)
    feedback_color = ListProperty([0.3, 0.6, 1.0, 1.0])  # Current accent color

    def __init__(self, on_complete, **kwargs):
        super().__init__(**kwargs)
        self.on_complete = on_complete
        self.dots = []  # [(x, y, index), ...]
        self.selected = []
        self.current_touch = None
        self.size_hint = (None, None)
        self.size = (dp(320), dp(320))
        self.dot_scales = [1.0] * 9  # Animation scale for each dot
        self.pulse_phase = 0
        self.bind(pos=self._redraw, size=self._redraw)
        Clock.schedule_once(lambda dt: self._redraw())
        # Pulse animation for selected dots
        Clock.schedule_interval(self._pulse_tick, 1/30)

    def _pulse_tick(self, dt):
        if self.selected:
            self.pulse_phase += dt * 3
            self._redraw()

    def _redraw(self, *args):
        self.canvas.clear()
        self.dots = []
        w, h = self.size
        x0, y0 = self.pos

        grid_size = min(w, h) * 0.85
        cell_size = grid_size / 3
        base_dot_radius = dp(22)

        start_x = x0 + (w - grid_size) / 2 + cell_size / 2
        start_y = y0 + (h - grid_size) / 2 + cell_size / 2

        with self.canvas:
            # Draw glow behind connecting lines
            if len(self.selected) > 1:
                # Outer glow
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.15)
                points = []
                for idx in self.selected:
                    if idx < 9:
                        col, row = idx % 3, idx // 3
                        cx = start_x + col * cell_size
                        cy = start_y + (2 - row) * cell_size
                        points.extend([cx, cy])
                if self.current_touch and self.is_drawing:
                    points.extend([self.current_touch[0], self.current_touch[1]])
                if len(points) >= 4:
                    Line(points=points, width=dp(16), cap='round', joint='round')

            # Main connecting lines
            if len(self.selected) > 1:
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.9)
                points = []
                for idx in self.selected:
                    if idx < 9:
                        col, row = idx % 3, idx // 3
                        cx = start_x + col * cell_size
                        cy = start_y + (2 - row) * cell_size
                        points.extend([cx, cy])
                if self.current_touch and self.is_drawing:
                    points.extend([self.current_touch[0], self.current_touch[1]])
                if len(points) >= 4:
                    Line(points=points, width=dp(5), cap='round', joint='round')
            elif len(self.selected) == 1 and self.current_touch and self.is_drawing:
                idx = self.selected[0]
                col, row = idx % 3, idx // 3
                cx = start_x + col * cell_size
                cy = start_y + (2 - row) * cell_size
                # Glow
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.15)
                Line(points=[cx, cy, self.current_touch[0], self.current_touch[1]],
                     width=dp(16), cap='round')
                # Main line
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.9)
                Line(points=[cx, cy, self.current_touch[0], self.current_touch[1]],
                     width=dp(5), cap='round')

            # Draw dots
            for row in range(3):
                for col in range(3):
                    idx = row * 3 + col
                    cx = start_x + col * cell_size
                    cy = start_y + (2 - row) * cell_size

                    self.dots.append((cx, cy, idx))

                    is_selected = idx in self.selected
                    scale = self.dot_scales[idx]
                    dot_radius = base_dot_radius * scale

                    # Pulsing for selected dots
                    if is_selected and self.is_drawing:
                        pulse = 1.0 + 0.08 * math.sin(self.pulse_phase + idx * 0.5)
                        dot_radius *= pulse

                    # Outer glow for selected dots
                    if is_selected:
                        glow_radius = dot_radius * 1.8
                        Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.25)
                        Ellipse(pos=(cx - glow_radius, cy - glow_radius),
                               size=(glow_radius * 2, glow_radius * 2))

                    # Outer circle
                    if is_selected:
                        Color(*self.feedback_color)
                    else:
                        Color(*THEME['dot_unselected'])
                    Ellipse(pos=(cx - dot_radius, cy - dot_radius),
                           size=(dot_radius * 2, dot_radius * 2))

                    # Inner dot (creates depth effect)
                    inner = dot_radius * 0.55
                    if is_selected:
                        Color(self.feedback_color[0] * 1.2, self.feedback_color[1] * 1.2,
                              self.feedback_color[2] * 1.2, 1.0)
                    else:
                        Color(*THEME['dot_inner'])
                    Ellipse(pos=(cx - inner, cy - inner),
                           size=(inner * 2, inner * 2))

                    # Bright center highlight for selected
                    if is_selected:
                        center = inner * 0.4
                        Color(1, 1, 1, 0.5)
                        Ellipse(pos=(cx - center, cy - center),
                               size=(center * 2, center * 2))

    def _hit_test(self, x, y):
        hit_radius = dp(45)
        for cx, cy, idx in self.dots:
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if dist < hit_radius:
                return idx
        return None

    def _animate_dot_select(self, idx):
        """Animate dot selection with a quick pulse"""
        self.dot_scales[idx] = 1.3
        def shrink(dt):
            self.dot_scales[idx] = 1.0
            self._redraw()
        Clock.schedule_once(shrink, 0.15)

    def on_touch_down(self, touch):
        if not self.collide_point(*touch.pos):
            return False
        touch.grab(self)
        self.selected = []
        self.is_drawing = True
        self.current_touch = touch.pos
        self.feedback_color = list(THEME['accent'])
        idx = self._hit_test(*touch.pos)
        if idx is not None:
            self.selected.append(idx)
            self._animate_dot_select(idx)
        self._redraw()
        return True

    def on_touch_move(self, touch):
        if touch.grab_current != self:
            return False
        self.current_touch = touch.pos
        idx = self._hit_test(*touch.pos)
        if idx is not None and idx not in self.selected:
            self.selected.append(idx)
            self._animate_dot_select(idx)
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
        else:
            self.show_error_feedback()
        self._redraw()
        return True

    def show_error_feedback(self):
        """Flash red to show error"""
        self.feedback_color = list(THEME['error'])
        self._redraw()
        def clear(dt):
            self.selected = []
            self.feedback_color = list(THEME['accent'])
            self._redraw()
        Clock.schedule_once(clear, 0.4)

    def show_success_feedback(self):
        """Flash green to show success"""
        self.feedback_color = list(THEME['success'])
        self._redraw()

    def clear(self):
        self.selected = []
        self.is_drawing = False
        self.current_touch = None
        self.feedback_color = list(THEME['accent'])
        self._redraw()


class PinDotsDisplay(Widget):
    """Animated PIN dots display with glow effects"""
    filled_count = NumericProperty(0)
    max_dots = NumericProperty(6)
    feedback_color = ListProperty([0.3, 0.6, 1.0, 1.0])

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.size_hint = (None, None)
        self.size = (dp(200), dp(24))
        self.dot_scales = [1.0] * 6
        self.bind(pos=self._redraw, size=self._redraw, filled_count=self._redraw)
        Clock.schedule_once(lambda dt: self._redraw())

    def _redraw(self, *args):
        self.canvas.clear()
        w, h = self.size
        x0, y0 = self.pos

        dot_radius = dp(8)
        spacing = dp(28)
        total_width = (self.max_dots - 1) * spacing
        start_x = x0 + (w - total_width) / 2
        cy = y0 + h / 2

        with self.canvas:
            for i in range(self.max_dots):
                cx = start_x + i * spacing
                is_filled = i < self.filled_count
                scale = self.dot_scales[i]
                radius = dot_radius * scale

                if is_filled:
                    # Glow
                    Color(self.feedback_color[0], self.feedback_color[1],
                          self.feedback_color[2], 0.3)
                    glow_r = radius * 1.8
                    Ellipse(pos=(cx - glow_r, cy - glow_r), size=(glow_r * 2, glow_r * 2))
                    # Filled dot
                    Color(*self.feedback_color)
                else:
                    Color(*THEME['dot_unselected'])

                Ellipse(pos=(cx - radius, cy - radius), size=(radius * 2, radius * 2))

    def animate_fill(self, count):
        """Animate filling a new dot"""
        if count > 0 and count <= self.max_dots:
            self.dot_scales[count - 1] = 1.4
            self.filled_count = count
            def shrink(dt):
                self.dot_scales[count - 1] = 1.0
                self._redraw()
            Clock.schedule_once(shrink, 0.1)
        else:
            self.filled_count = count

    def show_error(self):
        """Flash red"""
        self.feedback_color = list(THEME['error'])
        self._redraw()
        def reset(dt):
            self.feedback_color = list(THEME['accent'])
            self._redraw()
        Clock.schedule_once(reset, 0.4)


class LockScreenApp(App):
    time_text = StringProperty("12:00")
    date_text = StringProperty("Saturday, December 7")
    error_message = StringProperty("")
    lockout_message = StringProperty("")

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.lock_config = LockConfig.load()
        self.entered_pin = ""
        self.entered_password = ""
        self.failed_attempts = 0
        self.lockout_until = 0
        self.in_password_mode = False  # Track when using fallback password mode
        logger.info(f"Lock screen initialized with method: {self.lock_config.method}")

    def build(self):
        Window.clearcolor = THEME['bg_dark']

        # Bind keyboard events for physical/virtual keyboard input
        Window.bind(on_key_down=self._on_key_down)
        logger.info("Keyboard event handler bound")

        # Update time every second
        Clock.schedule_interval(self._update_time, 1)
        self._update_time(0)

        # Check if no lock needed
        if self.lock_config.method == "none":
            logger.info("No lock method configured, unlocking immediately")
            Clock.schedule_once(lambda dt: self._unlock(), 0.1)
            return Label(text="", color=THEME['text_primary'])

        # Check if credentials need setup
        if self.lock_config.needs_setup():
            logger.warning(f"Method {self.lock_config.method} set but no credentials - unlocking")
            Clock.schedule_once(lambda dt: self._unlock(), 0.1)
            return Label(text="Setup required in Settings",
                        color=THEME['text_secondary'], font_size=dp(18))

        root = FloatLayout()

        # Background - either image or solid dark color
        bg_image_path = self.lock_config.background_image
        self._bg_texture = None

        if bg_image_path and os.path.exists(bg_image_path):
            try:
                from kivy.core.image import Image as CoreImage
                self._bg_texture = CoreImage(bg_image_path).texture
                logger.info(f"Loaded background image: {bg_image_path}")
            except Exception as e:
                logger.error(f"Failed to load background image: {e}")
                self._bg_texture = None

        with root.canvas.before:
            if self._bg_texture:
                # Use image as background
                Color(1, 1, 1, 1)
                self._bg_rect = Rectangle(pos=root.pos, size=Window.size, texture=self._bg_texture)
            else:
                # Solid dark background - avoids gradient split issue
                Color(*THEME['bg_dark'])
                self._bg_rect = Rectangle(pos=root.pos, size=Window.size)

            # Semi-transparent overlay for better text readability on images
            if self._bg_texture:
                Color(0, 0, 0, 0.4)
                self._overlay_rect = Rectangle(pos=root.pos, size=Window.size)

        # Update background on window resize
        def update_bg(instance, value):
            self._bg_rect.pos = instance.pos
            self._bg_rect.size = Window.size
            if self._bg_texture and hasattr(self, '_overlay_rect'):
                self._overlay_rect.pos = instance.pos
                self._overlay_rect.size = Window.size
        root.bind(pos=update_bg, size=update_bg)

        # Main content
        content = BoxLayout(orientation='vertical', spacing=dp(8), padding=[dp(32), dp(48)])
        content.pos_hint = {'center_x': 0.5, 'center_y': 0.5}
        content.size_hint = (0.95, 0.95)

        # Top spacer
        content.add_widget(Widget(size_hint_y=0.08))

        # Time display - large and prominent
        self.time_label = Label(
            text=self.time_text,
            font_size=dp(86),
            bold=True,
            color=THEME['text_primary'],
            size_hint_y=None,
            height=dp(100)
        )
        self.bind(time_text=self.time_label.setter('text'))
        content.add_widget(self.time_label)

        # Date display
        self.date_label = Label(
            text=self.date_text,
            font_size=dp(18),
            color=THEME['text_secondary'],
            size_hint_y=None,
            height=dp(28)
        )
        self.bind(date_text=self.date_label.setter('text'))
        content.add_widget(self.date_label)

        content.add_widget(Widget(size_hint_y=None, height=dp(36)))

        # Mode indicator
        mode_icons = {'pin': 'PIN', 'pattern': 'Pattern', 'password': 'Password'}
        mode_label = Label(
            text=f"Enter {mode_icons.get(self.lock_config.method, '')} to unlock",
            font_size=dp(15),
            color=THEME['text_dim'],
            size_hint_y=None,
            height=dp(22)
        )
        content.add_widget(mode_label)

        # Lockout message
        self.lockout_label = Label(
            text="",
            font_size=dp(15),
            color=THEME['error'],
            size_hint_y=None,
            height=dp(22)
        )
        self.bind(lockout_message=self.lockout_label.setter('text'))
        content.add_widget(self.lockout_label)

        content.add_widget(Widget(size_hint_y=None, height=dp(12)))

        # PIN dots display (for PIN mode)
        if self.lock_config.method == "pin":
            dots_container = BoxLayout(size_hint=(None, None), pos_hint={'center_x': 0.5})
            dots_container.size = (dp(200), dp(32))
            self.pin_dots = PinDotsDisplay()
            dots_container.add_widget(self.pin_dots)
            content.add_widget(dots_container)

        # Error message
        self.error_label = Label(
            text="",
            font_size=dp(14),
            color=THEME['error'],
            size_hint_y=None,
            height=dp(22)
        )
        self.bind(error_message=self.error_label.setter('text'))
        content.add_widget(self.error_label)

        content.add_widget(Widget(size_hint_y=None, height=dp(16)))

        # Input area container - allows dynamic switching between modes
        self.input_container = BoxLayout(
            orientation='vertical',
            spacing=dp(16),
            size_hint_y=None,
            height=dp(420)
        )
        self._build_input_area()
        content.add_widget(self.input_container)

        # Spacer
        content.add_widget(Widget(size_hint_y=0.08))

        # Fallback container - holds the "Use System Password" button
        self.fallback_container = BoxLayout(size_hint_y=None, height=dp(40))
        if self.lock_config.method in ['pin', 'pattern']:
            self.fallback_btn = Button(
                text="Use System Password",
                font_size=dp(14),
                size_hint=(None, None),
                size=(dp(200), dp(40)),
                pos_hint={'center_x': 0.5},
                background_color=(0, 0, 0, 0),
                color=THEME['accent']
            )
            self.fallback_btn.bind(on_release=lambda b: self._switch_to_password())
            self.fallback_container.add_widget(self.fallback_btn)
        content.add_widget(self.fallback_container)

        content.add_widget(Widget(size_hint_y=0.04))

        root.add_widget(content)
        return root

    def _update_time(self, dt):
        now = datetime.now()
        self.time_text = now.strftime("%H:%M")
        self.date_text = now.strftime("%A, %B %d")

    def _build_input_area(self, mode=None):
        """Build the input area for the specified mode (or current lock method)"""
        if mode is None:
            mode = self.lock_config.method

        # Clear existing input area
        self.input_container.clear_widgets()

        if mode == "pin":
            pin_container = BoxLayout(size_hint=(None, None), pos_hint={'center_x': 0.5})
            pin_container.size = (dp(300), dp(380))
            self.pin_pad = GlowingPinPad(
                on_digit=self._on_pin_digit,
                on_backspace=self._on_pin_backspace
            )
            pin_container.add_widget(self.pin_pad)
            self.input_container.add_widget(pin_container)

        elif mode == "pattern":
            pattern_container = BoxLayout(size_hint=(None, None), pos_hint={'center_x': 0.5})
            pattern_container.size = (dp(320), dp(320))
            self.pattern_grid = GlowingPatternGrid(on_complete=self._on_pattern_complete)
            pattern_container.add_widget(self.pattern_grid)
            self.input_container.add_widget(pattern_container)

        elif mode == "password":
            # Password input with modern styling
            self.password_input = TextInput(
                password=True,
                multiline=False,
                font_size=dp(20),
                size_hint=(None, None),
                size=(dp(300), dp(56)),
                pos_hint={'center_x': 0.5},
                background_color=THEME['surface'],
                foreground_color=THEME['text_primary'],
                cursor_color=THEME['accent'],
                hint_text="Enter system password",
                hint_text_color=THEME['text_dim'],
                padding=[dp(16), dp(14)]
            )
            # Bind Enter key to submit
            self.password_input.bind(on_text_validate=lambda x: self._on_password_submit())
            # Request keyboard when focus changes (to keep it visible when tapped)
            self.password_input.bind(focus=self._on_password_focus)
            self.input_container.add_widget(self.password_input)
            self.input_container.add_widget(Widget(size_hint_y=None, height=dp(16)))

            # Submit button
            submit_btn = Button(
                text="Unlock",
                font_size=dp(17),
                bold=True,
                size_hint=(None, None),
                size=(dp(300), dp(52)),
                pos_hint={'center_x': 0.5},
                background_color=THEME['accent'],
                color=THEME['text_primary']
            )
            submit_btn.bind(on_release=lambda b: self._on_password_submit())
            self.input_container.add_widget(submit_btn)

            # Focus the password input after a short delay (to allow UI to settle)
            Clock.schedule_once(lambda dt: self._focus_password_input(), 0.3)

    def _focus_password_input(self):
        """Focus the password input to trigger on-screen keyboard"""
        if hasattr(self, 'password_input') and self.password_input:
            self.password_input.focus = True
            # Also request keyboard since we're focusing programmatically
            request_keyboard(True)
            logger.info("Password input focused - on-screen keyboard should appear")

    def _on_password_focus(self, instance, focused):
        """Handle password input focus changes - request keyboard when focused"""
        logger.info(f"Password input focus changed: {focused}")
        if focused:
            # Request keyboard to stay visible when password input is tapped
            request_keyboard(True)

    def _on_pin_digit(self, digit):
        # Ignore PIN input when in password mode
        if self.in_password_mode:
            return
        if self._is_locked_out():
            return
        if len(self.entered_pin) < 6:
            self.entered_pin += digit
            self.pin_dots.animate_fill(len(self.entered_pin))
            logger.debug(f"PIN digit entered, length: {len(self.entered_pin)}")

            # Auto-verify at 4-6 digits
            if len(self.entered_pin) >= 4:
                Clock.schedule_once(lambda dt: self._try_verify_pin(), 0.3)

    def _on_pin_backspace(self):
        # Ignore PIN backspace when in password mode
        if self.in_password_mode:
            return
        if self.entered_pin:
            self.entered_pin = self.entered_pin[:-1]
            self.pin_dots.filled_count = len(self.entered_pin)
            self.error_message = ""

    def _try_verify_pin(self):
        # Ignore PIN verification when in password mode
        if self.in_password_mode:
            return
        if self.lock_config.verify_pin(self.entered_pin):
            logger.info("PIN verified successfully")
            self._unlock()
        elif len(self.entered_pin) == 6:
            self._record_failed_attempt("PIN")
            self.pin_dots.show_error()
            self.entered_pin = ""
            Clock.schedule_once(lambda dt: setattr(self.pin_dots, 'filled_count', 0), 0.4)

    def _on_pattern_complete(self, pattern):
        if self._is_locked_out():
            self.pattern_grid.clear()
            return

        logger.debug(f"Pattern completed: {pattern}")
        if self.lock_config.verify_pattern(pattern):
            logger.info("Pattern verified successfully")
            self.pattern_grid.show_success_feedback()
            Clock.schedule_once(lambda dt: self._unlock(), 0.3)
        else:
            self._record_failed_attempt("pattern")
            self.pattern_grid.show_error_feedback()

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
        """Switch from PIN/Pattern mode to system password mode"""
        logger.info("Switching to password mode")
        self.error_message = ""
        self.in_password_mode = True  # Set flag to indicate we're in password mode
        self.entered_pin = ""  # Clear any entered PIN to prevent verification

        # Hide the fallback button since we're now in password mode
        self.fallback_container.clear_widgets()

        # Hide PIN dots if they exist
        if hasattr(self, 'pin_dots') and self.pin_dots:
            self.pin_dots.opacity = 0

        # Clear PIN pad reference so _on_key_down doesn't use it
        self.pin_pad = None

        # Rebuild input area with password input
        self._build_input_area("password")

        # Request on-screen keyboard to show
        request_keyboard(True)

    def _record_failed_attempt(self, auth_type):
        self.failed_attempts += 1
        remaining = 5 - self.failed_attempts
        if remaining > 0:
            self.error_message = f"Wrong {auth_type}. {remaining} attempts left"
        else:
            self.lockout_until = time() + 30
            self.lockout_message = "Too many attempts. Wait 30s"
            self.error_message = ""
            Clock.schedule_interval(self._update_lockout, 1)
        logger.warning(f"Failed {auth_type} attempt #{self.failed_attempts}")

    def _update_lockout(self, dt):
        remaining = int(self.lockout_until - time())
        if remaining <= 0:
            self.lockout_message = ""
            self.failed_attempts = 0
            return False
        self.lockout_message = f"Too many attempts. Wait {remaining}s"

    def _is_locked_out(self):
        if self.failed_attempts >= 5:
            return time() < self.lockout_until
        return False

    def _unlock(self):
        """Successful unlock - signal compositor and exit"""
        logger.info("UNLOCK SUCCESSFUL")
        signal_unlock()
        # Fade out animation
        if self.root:
            anim = Animation(opacity=0, duration=0.25)
            anim.bind(on_complete=lambda a, w: self._exit_app())
            anim.start(self.root)
        else:
            self._exit_app()

    def _exit_app(self):
        logger.info("Exiting lock screen app")
        App.get_running_app().stop()
        sys.exit(0)

    def _on_key_down(self, window, key, scancode, codepoint, modifiers):
        """Handle keyboard input from physical or virtual keyboard"""
        logger.info(f"KEY DOWN: key={key}, scancode={scancode}, codepoint={codepoint!r}, modifiers={modifiers}, in_password_mode={self.in_password_mode}")

        # Check if we're in password mode (either by flag or config)
        if self.in_password_mode or self.lock_config.method == "password":
            # Handle password mode keyboard input
            if hasattr(self, 'password_input') and self.password_input:
                # Enter key to submit (key==13 is ASCII CR, scancode 28 is evdev KEY_ENTER)
                # NOTE: Do NOT use scancode == 36 - that conflicts with '7' key in Wayland/Kivy
                if key == 13 or scancode == 28:
                    logger.info("Enter from keyboard - attempting password auth")
                    self._on_password_submit()
                    return True

                # Backspace
                if key == 8 or key == 22 or scancode == 22 or scancode == 14:
                    logger.info("Backspace from keyboard in password mode")
                    if self.password_input.text:
                        self.password_input.text = self.password_input.text[:-1]
                    return True

                # Regular character - append to password input
                if codepoint and len(codepoint) == 1:
                    logger.info(f"Password char from keyboard: {codepoint}")
                    self.password_input.text += codepoint
                    return True

            return False

        # Handle PIN mode keyboard input (only when NOT in password mode)
        if self.lock_config.method == "pin" and not self.in_password_mode:
            # Number keys (both main keyboard and numpad)
            if codepoint and codepoint.isdigit():
                logger.info(f"PIN digit from keyboard: {codepoint}")
                self._on_pin_digit(codepoint)
                return True

            # Backspace (key 8 or 22 on some systems)
            if key == 8 or key == 22 or scancode == 22 or scancode == 14:
                logger.info("Backspace from keyboard")
                self._on_pin_backspace()
                return True

            # Enter key to submit (key==13 is ASCII CR, scancode 28 is evdev KEY_ENTER)
            # NOTE: Do NOT use scancode == 36 - that conflicts with '7' key in Wayland/Kivy
            if key == 13 or scancode == 28:
                logger.info("Enter from keyboard - attempting verify")
                self._try_verify_pin()
                return True

        # Pattern mode - only handle numbers for fallback
        if self.lock_config.method == "pattern" and not self.in_password_mode:
            # Could add pattern input via keyboard in future
            pass

        return False


if __name__ == "__main__":
    logger.info("Starting FlickLockScreenApp")
    try:
        LockScreenApp().run()
    except Exception as e:
        logger.exception(f"App crashed: {e}")
        sys.exit(1)
