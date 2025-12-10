#!/usr/bin/env python3
"""
Flick Settings - Beautiful Lock Screen Configuration
A stunning Kivy-based settings app for Flick shell with modern design
"""

import os
import json
import hashlib
import logging
from pathlib import Path
import math

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
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.uix.scrollview import ScrollView
from kivy.uix.gridlayout import GridLayout
from kivy.uix.widget import Widget
from kivy.core.window import Window
from kivy.graphics import Color, Ellipse, Line, Rectangle, RoundedRectangle
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.animation import Animation
from kivy.properties import NumericProperty, ListProperty, BooleanProperty

# Config path
CONFIG_PATH = Path.home() / ".local" / "state" / "flick" / "lock_config.json"

# Stunning dark theme
THEME = {
    'bg_dark': (0.04, 0.04, 0.06, 1),
    'bg_gradient': (0.06, 0.07, 0.10, 1),
    'surface': (0.10, 0.10, 0.14, 1),
    'surface_light': (0.14, 0.14, 0.18, 1),
    'surface_elevated': (0.16, 0.16, 0.20, 1),
    'accent': (0.30, 0.60, 1.0, 1),
    'accent_dim': (0.20, 0.45, 0.85, 1),
    'accent_glow': (0.30, 0.60, 1.0, 0.3),
    'success': (0.20, 0.80, 0.45, 1),
    'error': (1.0, 0.35, 0.35, 1),
    'warning': (1.0, 0.70, 0.25, 1),
    'text_primary': (1, 1, 1, 1),
    'text_secondary': (0.70, 0.70, 0.75, 1),
    'text_dim': (0.50, 0.50, 0.55, 1),
    'divider': (0.20, 0.20, 0.25, 1),
}


class LockConfig:
    """Lock screen configuration"""
    def __init__(self):
        self.method = "none"
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
        config.method = data.get("method", "none")
        config.pin_hash = data.get("pin_hash", "")
        config.pattern_hash = data.get("pattern_hash", "")
        config.timeout_seconds = data.get("timeout_seconds", 0)
        config.failed_attempts = data.get("failed_attempts", 0)
        config.lockout_until = data.get("lockout_until", 0)
        return config

    def needs_setup(self) -> bool:
        """Check if method is set but credentials are missing"""
        if self.method == "pin" and not self.pin_hash:
            return True
        if self.method == "pattern" and not self.pattern_hash:
            return True
        return False


def hash_pin(pin: str) -> str:
    return hashlib.sha256(pin.encode()).hexdigest()


def hash_pattern(pattern: list) -> str:
    pattern_str = "-".join(str(p) for p in pattern)
    return hashlib.sha256(pattern_str.encode()).hexdigest()


def load_config() -> LockConfig:
    logger.info(f"Loading config from {CONFIG_PATH}")
    try:
        if CONFIG_PATH.exists():
            with open(CONFIG_PATH) as f:
                data = json.load(f)
                logger.debug(f"Loaded config data: {data}")
                return LockConfig.from_dict(data)
    except Exception as e:
        logger.error(f"Error loading config: {e}")
    return LockConfig()


def save_config(config: LockConfig):
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


class GlowingCard(BoxLayout):
    """A modern card with subtle glow effect"""
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.orientation = 'vertical'
        self.padding = [dp(20), dp(16)]
        self.spacing = dp(8)
        self.bind(pos=self._update_canvas, size=self._update_canvas)
        Clock.schedule_once(lambda dt: self._update_canvas())

    def _update_canvas(self, *args):
        self.canvas.before.clear()
        with self.canvas.before:
            # Card background
            Color(*THEME['surface'])
            RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(16)])


class SettingsRow(BoxLayout):
    """A beautiful settings row with icon space, label, value, and chevron"""
    glow_alpha = NumericProperty(0)

    def __init__(self, label_text, value_text, subtitle=None, on_tap=None,
                 icon_color=None, show_warning=False, **kwargs):
        super().__init__(**kwargs)
        self.orientation = 'horizontal'
        self.size_hint_y = None
        self.height = dp(72) if subtitle else dp(60)
        self.padding = [dp(16), dp(12)]
        self.spacing = dp(16)
        self.on_tap_callback = on_tap
        self.show_warning = show_warning

        # Icon placeholder (colored circle)
        self.icon_widget = Widget(size_hint=(None, None), size=(dp(40), dp(40)))
        self.icon_color = icon_color or THEME['accent']
        self.add_widget(self.icon_widget)

        # Text content
        text_box = BoxLayout(orientation='vertical', spacing=dp(2))

        self.label = Label(
            text=label_text,
            font_size=dp(17),
            halign='left',
            valign='center',
            color=THEME['text_primary'],
            bold=True
        )
        self.label.bind(size=self.label.setter('text_size'))
        text_box.add_widget(self.label)

        if subtitle:
            self.subtitle_label = Label(
                text=subtitle,
                font_size=dp(13),
                halign='left',
                valign='center',
                color=THEME['text_dim']
            )
            self.subtitle_label.bind(size=self.subtitle_label.setter('text_size'))
            text_box.add_widget(self.subtitle_label)

        self.add_widget(text_box)

        # Value on right
        right_box = BoxLayout(orientation='horizontal', size_hint_x=None, width=dp(120), spacing=dp(8))

        self.value_label = Label(
            text=value_text,
            font_size=dp(15),
            halign='right',
            valign='center',
            color=THEME['text_secondary']
        )
        self.value_label.bind(size=self.value_label.setter('text_size'))
        right_box.add_widget(self.value_label)

        # Chevron
        chevron = Label(
            text=">",
            font_size=dp(20),
            size_hint_x=None,
            width=dp(20),
            color=THEME['text_dim']
        )
        right_box.add_widget(chevron)

        self.add_widget(right_box)

        self.bind(pos=self._update_canvas, size=self._update_canvas, glow_alpha=self._update_canvas)
        Clock.schedule_once(lambda dt: self._update_canvas())

    def _update_canvas(self, *args):
        self.canvas.before.clear()
        with self.canvas.before:
            # Background with hover/press effect
            if self.glow_alpha > 0:
                Color(THEME['accent'][0], THEME['accent'][1], THEME['accent'][2], self.glow_alpha * 0.1)
                RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(12)])

            # Icon circle
            icon_x = self.pos[0] + dp(16)
            icon_y = self.pos[1] + (self.height - dp(40)) / 2
            if self.show_warning:
                Color(*THEME['warning'])
            else:
                Color(*self.icon_color)
            Ellipse(pos=(icon_x, icon_y), size=(dp(40), dp(40)))

            # Icon inner (white circle for contrast)
            inner = dp(16)
            Color(1, 1, 1, 0.9)
            Ellipse(pos=(icon_x + (dp(40) - inner) / 2, icon_y + (dp(40) - inner) / 2),
                   size=(inner, inner))

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos) and self.on_tap_callback:
            anim = Animation(glow_alpha=1, duration=0.1)
            anim.start(self)
            return True
        return super().on_touch_down(touch)

    def on_touch_up(self, touch):
        if self.glow_alpha > 0:
            anim = Animation(glow_alpha=0, duration=0.2)
            anim.start(self)
            if self.collide_point(*touch.pos) and self.on_tap_callback:
                Clock.schedule_once(lambda dt: self.on_tap_callback(), 0.05)
                return True
        return super().on_touch_up(touch)

    def set_value(self, text):
        self.value_label.text = text


class SectionHeader(Label):
    """Section header with accent color"""
    def __init__(self, text, **kwargs):
        super().__init__(**kwargs)
        self.text = text
        self.font_size = dp(13)
        self.color = THEME['accent']
        self.halign = 'left'
        self.valign = 'center'
        self.size_hint_y = None
        self.height = dp(40)
        self.padding = [dp(20), dp(8)]
        self.bind(size=self.setter('text_size'))


class ModernPopup(Popup):
    """Modern styled popup with dark theme"""
    def __init__(self, **kwargs):
        kwargs.setdefault('background_color', THEME['surface'])
        kwargs.setdefault('separator_color', THEME['divider'])
        kwargs.setdefault('title_color', THEME['text_primary'])
        kwargs.setdefault('title_size', dp(20))
        super().__init__(**kwargs)


class MethodPickerPopup(ModernPopup):
    """Beautiful method picker with cards"""
    def __init__(self, current_method, on_select, **kwargs):
        super().__init__(**kwargs)
        self.title = "Choose Lock Method"
        self.size_hint = (0.92, 0.72)
        self.on_select = on_select
        self.auto_dismiss = True

        layout = BoxLayout(orientation='vertical', spacing=dp(12), padding=dp(16))

        methods = [
            ("none", "No Lock", "Anyone can access your device", THEME['text_dim']),
            ("pin", "PIN", "4-6 digit numeric code", THEME['accent']),
            ("pattern", "Pattern", "Draw a pattern to unlock", THEME['success']),
            ("password", "System Password", "Use your Linux password", THEME['accent_dim']),
        ]

        for method_id, title, desc, color in methods:
            is_selected = method_id == current_method
            btn = self._create_method_button(method_id, title, desc, color, is_selected)
            layout.add_widget(btn)

        # Cancel button
        cancel_btn = Button(
            text="Cancel",
            font_size=dp(16),
            size_hint_y=None,
            height=dp(50),
            background_color=THEME['surface_light'],
            color=THEME['text_secondary']
        )
        cancel_btn.bind(on_release=lambda x: self.dismiss())
        layout.add_widget(cancel_btn)

        self.content = layout

    def _create_method_button(self, method_id, title, desc, color, is_selected):
        btn = Button(
            text=f"[b]{title}[/b]\n[size=12]{desc}[/size]",
            markup=True,
            size_hint_y=None,
            height=dp(72),
            background_color=color if is_selected else THEME['surface_light'],
            color=THEME['text_primary']
        )
        btn.method_id = method_id
        btn.bind(on_release=self._on_select)
        return btn

    def _on_select(self, button):
        method = button.method_id
        logger.info(f"Method selected: {method}")
        self.dismiss()
        Clock.schedule_once(lambda dt: self.on_select(method), 0.1)


class GlowingPatternSetup(Widget):
    """Beautiful pattern setup widget matching lock screen style"""
    feedback_color = ListProperty([0.3, 0.6, 1.0, 1.0])

    def __init__(self, on_pattern_changed, **kwargs):
        super().__init__(**kwargs)
        self.on_pattern_changed = on_pattern_changed
        self.dots = []
        self.selected = []
        self.current_touch = None
        self.is_drawing = False
        self.size_hint = (1, 1)
        self.dot_scales = [1.0] * 9
        self.pulse_phase = 0
        self.bind(pos=self._redraw, size=self._redraw)
        Clock.schedule_once(lambda dt: self._redraw())
        Clock.schedule_interval(self._pulse_tick, 1/30)

    def _pulse_tick(self, dt):
        if self.selected and self.is_drawing:
            self.pulse_phase += dt * 3
            self._redraw()

    def _redraw(self, *args):
        self.canvas.clear()
        self.dots = []
        w, h = self.size
        x0, y0 = self.pos

        grid_size = min(w, h) * 0.85
        cell_size = grid_size / 3
        base_dot_radius = dp(20)

        start_x = x0 + (w - grid_size) / 2 + cell_size / 2
        start_y = y0 + (h - grid_size) / 2 + cell_size / 2

        with self.canvas:
            # Connecting lines with glow
            if len(self.selected) > 1:
                # Glow
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
                    Line(points=points, width=dp(14), cap='round', joint='round')

                # Main line
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.9)
                if len(points) >= 4:
                    Line(points=points, width=dp(4), cap='round', joint='round')

            elif len(self.selected) == 1 and self.current_touch and self.is_drawing:
                idx = self.selected[0]
                col, row = idx % 3, idx // 3
                cx = start_x + col * cell_size
                cy = start_y + (2 - row) * cell_size
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.15)
                Line(points=[cx, cy, self.current_touch[0], self.current_touch[1]],
                     width=dp(14), cap='round')
                Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.9)
                Line(points=[cx, cy, self.current_touch[0], self.current_touch[1]],
                     width=dp(4), cap='round')

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

                    if is_selected and self.is_drawing:
                        pulse = 1.0 + 0.08 * math.sin(self.pulse_phase + idx * 0.5)
                        dot_radius *= pulse

                    # Glow for selected
                    if is_selected:
                        glow_r = dot_radius * 1.8
                        Color(self.feedback_color[0], self.feedback_color[1], self.feedback_color[2], 0.25)
                        Ellipse(pos=(cx - glow_r, cy - glow_r), size=(glow_r * 2, glow_r * 2))

                    # Outer circle
                    if is_selected:
                        Color(*self.feedback_color)
                    else:
                        Color(0.25, 0.25, 0.30, 1)
                    Ellipse(pos=(cx - dot_radius, cy - dot_radius), size=(dot_radius * 2, dot_radius * 2))

                    # Inner dot
                    inner = dot_radius * 0.55
                    if is_selected:
                        Color(self.feedback_color[0] * 1.2, self.feedback_color[1] * 1.2,
                              self.feedback_color[2] * 1.2, 1.0)
                    else:
                        Color(0.15, 0.15, 0.18, 1)
                    Ellipse(pos=(cx - inner, cy - inner), size=(inner * 2, inner * 2))

                    # Center highlight
                    if is_selected:
                        center = inner * 0.4
                        Color(1, 1, 1, 0.5)
                        Ellipse(pos=(cx - center, cy - center), size=(center * 2, center * 2))

    def _hit_test(self, x, y):
        hit_radius = dp(40)
        for cx, cy, idx in self.dots:
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if dist < hit_radius:
                return idx
        return None

    def _animate_dot(self, idx):
        self.dot_scales[idx] = 1.3
        def shrink(dt):
            self.dot_scales[idx] = 1.0
            self._redraw()
        Clock.schedule_once(shrink, 0.12)

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
            self._animate_dot(idx)
        self._redraw()
        return True

    def on_touch_move(self, touch):
        if touch.grab_current != self:
            return False
        self.current_touch = touch.pos
        idx = self._hit_test(*touch.pos)
        if idx is not None and idx not in self.selected:
            self.selected.append(idx)
            self._animate_dot(idx)
        self._redraw()
        return True

    def on_touch_up(self, touch):
        if touch.grab_current != self:
            return False
        touch.ungrab(self)
        self.is_drawing = False
        self.current_touch = None
        self.on_pattern_changed(list(self.selected))
        self._redraw()
        return True

    def clear(self):
        self.selected = []
        self.is_drawing = False
        self.current_touch = None
        self.feedback_color = list(THEME['accent'])
        self._redraw()

    def show_success(self):
        self.feedback_color = list(THEME['success'])
        self._redraw()

    def show_error(self):
        self.feedback_color = list(THEME['error'])
        self._redraw()
        def reset(dt):
            self.clear()
        Clock.schedule_once(reset, 0.5)


class PatternSetupPopup(ModernPopup):
    """Beautiful pattern setup popup"""
    def __init__(self, on_complete, **kwargs):
        super().__init__(**kwargs)
        self.title = "Set Pattern"
        self.size_hint = (0.95, 0.88)
        self.on_complete = on_complete
        self.first_pattern = None
        self.auto_dismiss = False
        self.current_pattern = []

        layout = BoxLayout(orientation='vertical', spacing=dp(12), padding=dp(16))

        self.instruction = Label(
            text="Draw a pattern connecting at least 4 dots",
            font_size=dp(16),
            color=THEME['text_secondary'],
            size_hint_y=None,
            height=dp(36)
        )
        layout.add_widget(self.instruction)

        self.pattern_display = Label(
            text="",
            font_size=dp(18),
            color=THEME['accent'],
            size_hint_y=None,
            height=dp(28)
        )
        layout.add_widget(self.pattern_display)

        # Pattern grid
        self.pattern_grid = GlowingPatternSetup(on_pattern_changed=self._on_pattern_drawn)
        layout.add_widget(self.pattern_grid)

        # Buttons
        btn_layout = BoxLayout(size_hint_y=None, height=dp(56), spacing=dp(12))

        cancel_btn = Button(
            text="Cancel",
            font_size=dp(16),
            background_color=THEME['surface_light'],
            color=THEME['text_secondary']
        )
        cancel_btn.bind(on_release=lambda x: self._cancel())
        btn_layout.add_widget(cancel_btn)

        clear_btn = Button(
            text="Clear",
            font_size=dp(16),
            background_color=THEME['warning'],
            color=THEME['text_primary']
        )
        clear_btn.bind(on_release=lambda x: self._clear())
        btn_layout.add_widget(clear_btn)

        self.ok_btn = Button(
            text="Confirm",
            font_size=dp(16),
            background_color=THEME['success'],
            color=THEME['text_primary']
        )
        self.ok_btn.bind(on_release=lambda x: self._confirm())
        self.ok_btn.disabled = True
        btn_layout.add_widget(self.ok_btn)

        layout.add_widget(btn_layout)
        self.content = layout

    def _on_pattern_drawn(self, pattern):
        self.current_pattern = pattern
        if len(pattern) >= 4:
            display = " > ".join(str(p + 1) for p in pattern)
            self.pattern_display.text = display
            self.ok_btn.disabled = False
        else:
            self.pattern_display.text = "Need at least 4 dots"
            self.ok_btn.disabled = True

    def _clear(self):
        self.current_pattern = []
        self.pattern_display.text = ""
        self.pattern_grid.clear()
        self.ok_btn.disabled = True

    def _cancel(self):
        self.dismiss()

    def _confirm(self):
        if len(self.current_pattern) < 4:
            return

        if self.first_pattern is None:
            self.first_pattern = list(self.current_pattern)
            self.pattern_grid.show_success()
            self._clear()
            self.instruction.text = "Draw the same pattern again to confirm"
        else:
            if self.current_pattern == self.first_pattern:
                self.pattern_grid.show_success()
                self.dismiss()
                Clock.schedule_once(lambda dt: self.on_complete(self.current_pattern), 0.1)
            else:
                self.pattern_grid.show_error()
                self.instruction.text = "Patterns don't match! Try again"
                self.first_pattern = None


class PinSetupPopup(ModernPopup):
    """Beautiful PIN setup popup"""
    def __init__(self, on_complete, **kwargs):
        super().__init__(**kwargs)
        self.title = "Set PIN"
        self.size_hint = (0.92, 0.78)
        self.on_complete = on_complete
        self.first_pin = None
        self.auto_dismiss = False
        self.current_pin = ""

        layout = BoxLayout(orientation='vertical', spacing=dp(16), padding=dp(16))

        self.instruction = Label(
            text="Enter a 4-6 digit PIN",
            font_size=dp(16),
            color=THEME['text_secondary'],
            size_hint_y=None,
            height=dp(36)
        )
        layout.add_widget(self.instruction)

        self.pin_display = Label(
            text="",
            font_size=dp(36),
            color=THEME['accent'],
            size_hint_y=None,
            height=dp(50)
        )
        layout.add_widget(self.pin_display)

        # Number pad
        numpad = GridLayout(cols=3, spacing=dp(12), size_hint_y=0.55)
        for digit in "123456789":
            btn = self._create_num_button(digit)
            numpad.add_widget(btn)

        clear_btn = Button(text="C", font_size=dp(28), background_color=THEME['error'])
        clear_btn.bind(on_release=lambda x: self._clear())
        numpad.add_widget(clear_btn)

        zero_btn = self._create_num_button("0")
        numpad.add_widget(zero_btn)

        back_btn = Button(text="<", font_size=dp(28), background_color=THEME['surface_light'])
        back_btn.bind(on_release=lambda x: self._backspace())
        numpad.add_widget(back_btn)

        layout.add_widget(numpad)

        # Buttons
        btn_layout = BoxLayout(size_hint_y=None, height=dp(56), spacing=dp(12))

        cancel_btn = Button(
            text="Cancel",
            font_size=dp(16),
            background_color=THEME['surface_light'],
            color=THEME['text_secondary']
        )
        cancel_btn.bind(on_release=lambda x: self._cancel())
        btn_layout.add_widget(cancel_btn)

        self.ok_btn = Button(
            text="Confirm",
            font_size=dp(16),
            background_color=THEME['success'],
            color=THEME['text_primary']
        )
        self.ok_btn.bind(on_release=lambda x: self._confirm())
        self.ok_btn.disabled = True
        btn_layout.add_widget(self.ok_btn)

        layout.add_widget(btn_layout)
        self.content = layout

    def _create_num_button(self, digit):
        btn = Button(text=digit, font_size=dp(28), background_color=THEME['surface_light'])
        btn.bind(on_release=lambda b: self._add_digit(b.text))
        return btn

    def _add_digit(self, digit):
        if len(self.current_pin) < 6:
            self.current_pin += digit
            self.pin_display.text = "*" * len(self.current_pin)
            self.ok_btn.disabled = len(self.current_pin) < 4

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
        self.dismiss()

    def _confirm(self):
        if len(self.current_pin) < 4:
            return

        if self.first_pin is None:
            self.first_pin = self.current_pin
            self._clear()
            self.instruction.text = "Enter the same PIN again to confirm"
        else:
            if self.current_pin == self.first_pin:
                self.dismiss()
                Clock.schedule_once(lambda dt: self.on_complete(self.current_pin), 0.1)
            else:
                self.instruction.text = "PINs don't match! Try again"
                self.instruction.color = THEME['error']
                self.first_pin = None
                self._clear()
                Clock.schedule_once(lambda dt: setattr(self.instruction, 'color', THEME['text_secondary']), 2)


class TimeoutPickerPopup(ModernPopup):
    """Timeout selection popup"""
    def __init__(self, current_timeout, on_select, **kwargs):
        super().__init__(**kwargs)
        self.title = "Lock Timeout"
        self.size_hint = (0.85, 0.55)
        self.on_select = on_select

        layout = BoxLayout(orientation='vertical', spacing=dp(8), padding=dp(16))

        timeouts = [
            (0, "Immediately"),
            (60, "1 minute"),
            (300, "5 minutes"),
            (900, "15 minutes"),
            (-1, "Never"),
        ]

        for val, label in timeouts:
            is_selected = val == current_timeout
            btn = Button(
                text=label,
                font_size=dp(17),
                size_hint_y=None,
                height=dp(52),
                background_color=THEME['accent'] if is_selected else THEME['surface_light'],
                color=THEME['text_primary']
            )
            btn.timeout_val = val
            btn.bind(on_release=self._on_select)
            layout.add_widget(btn)

        cancel_btn = Button(
            text="Cancel",
            font_size=dp(16),
            size_hint_y=None,
            height=dp(52),
            background_color=THEME['surface_light'],
            color=THEME['text_secondary']
        )
        cancel_btn.bind(on_release=lambda x: self.dismiss())
        layout.add_widget(cancel_btn)

        self.content = layout

    def _on_select(self, button):
        self.dismiss()
        Clock.schedule_once(lambda dt: self.on_select(button.timeout_val), 0.1)


class FlickSettingsApp(App):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.config_data = load_config()
        logger.info(f"App initialized with method: {self.config_data.method}")

    def build(self):
        Window.clearcolor = THEME['bg_dark']

        root = BoxLayout(orientation='vertical')

        # Gradient background header
        header = BoxLayout(size_hint_y=None, height=dp(100), padding=[dp(20), dp(24)])
        with header.canvas.before:
            Color(*THEME['bg_gradient'])
            Rectangle(pos=header.pos, size=header.size)

        header_content = BoxLayout(orientation='vertical')
        title = Label(
            text="Settings",
            font_size=dp(28),
            bold=True,
            halign='left',
            valign='bottom',
            color=THEME['text_primary']
        )
        title.bind(size=title.setter('text_size'))
        header_content.add_widget(title)

        subtitle = Label(
            text="Lock Screen & Security",
            font_size=dp(14),
            halign='left',
            valign='top',
            color=THEME['text_dim']
        )
        subtitle.bind(size=subtitle.setter('text_size'))
        header_content.add_widget(subtitle)

        header.add_widget(header_content)
        root.add_widget(header)

        # Warning banner if setup needed
        if self.config_data.needs_setup():
            self._show_setup_required_banner(root)

        # Scrollable content
        scroll = ScrollView()
        content = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(8), padding=[dp(12), dp(16)])
        content.bind(minimum_height=content.setter('height'))

        # Security section
        content.add_widget(SectionHeader("SECURITY"))

        # Lock method row
        needs_setup = self.config_data.needs_setup()
        self.method_row = SettingsRow(
            "Lock Method",
            self._method_label(self.config_data.method),
            subtitle="How to unlock your device",
            on_tap=self._show_method_picker,
            show_warning=needs_setup
        )
        content.add_widget(self.method_row)

        # Change PIN/Pattern row
        self.change_row = SettingsRow(
            "Change Credential",
            "Tap to change",
            subtitle="Update your PIN or pattern",
            on_tap=self._change_credential,
            icon_color=THEME['success']
        )
        self._update_change_row()
        content.add_widget(self.change_row)

        # Timing section
        content.add_widget(SectionHeader("TIMING"))

        self.timeout_row = SettingsRow(
            "Lock Timeout",
            self._timeout_label(self.config_data.timeout_seconds),
            subtitle="When to require unlock",
            on_tap=self._show_timeout_picker,
            icon_color=THEME['accent_dim']
        )
        content.add_widget(self.timeout_row)

        # Info section
        content.add_widget(SectionHeader("INFO"))

        info = Label(
            text="You can always use your system\npassword as a fallback to unlock.",
            font_size=dp(13),
            color=THEME['text_dim'],
            halign='left',
            size_hint_y=None,
            height=dp(50)
        )
        info.bind(size=info.setter('text_size'))
        content.add_widget(info)

        scroll.add_widget(content)
        root.add_widget(scroll)

        # Check if we need to force setup
        if self.config_data.needs_setup():
            Clock.schedule_once(lambda dt: self._force_setup(), 0.5)

        return root

    def _show_setup_required_banner(self, root):
        """Show a warning banner when setup is required"""
        banner = BoxLayout(size_hint_y=None, height=dp(56), padding=[dp(16), dp(8)])
        with banner.canvas.before:
            Color(*THEME['warning'])
            Rectangle(pos=banner.pos, size=banner.size)

        text = Label(
            text=f"Setup your {self.config_data.method} to enable lock screen",
            font_size=dp(14),
            bold=True,
            color=THEME['bg_dark']
        )
        banner.add_widget(text)
        root.add_widget(banner)

    def _force_setup(self):
        """Force user to set up credentials if method is set but hash is empty"""
        if self.config_data.method == "pin":
            logger.info("Forcing PIN setup")
            popup = PinSetupPopup(on_complete=self._on_pin_set)
            popup.open()
        elif self.config_data.method == "pattern":
            logger.info("Forcing pattern setup")
            popup = PatternSetupPopup(on_complete=self._on_pattern_set)
            popup.open()

    def _method_label(self, method):
        return {"none": "None", "pin": "PIN", "pattern": "Pattern", "password": "Password"}.get(method, method)

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
        return f"{seconds}s"

    def _update_change_row(self):
        if self.config_data.method == "pin":
            self.change_row.label.text = "Change PIN"
            self.change_row.opacity = 1
            self.change_row.disabled = False
        elif self.config_data.method == "pattern":
            self.change_row.label.text = "Change Pattern"
            self.change_row.opacity = 1
            self.change_row.disabled = False
        else:
            self.change_row.opacity = 0.3
            self.change_row.disabled = True

    def _show_method_picker(self):
        popup = MethodPickerPopup(
            current_method=self.config_data.method,
            on_select=self._on_method_selected
        )
        popup.open()

    def _on_method_selected(self, method):
        if method == self.config_data.method:
            return

        if method == "pin":
            popup = PinSetupPopup(on_complete=self._on_pin_set)
            popup.open()
        elif method == "pattern":
            popup = PatternSetupPopup(on_complete=self._on_pattern_set)
            popup.open()
        else:
            self.config_data.method = method
            self.config_data.pin_hash = ""
            self.config_data.pattern_hash = ""
            save_config(self.config_data)
            self.method_row.set_value(self._method_label(method))
            self.method_row.show_warning = False
            self._update_change_row()

    def _on_pin_set(self, pin):
        self.config_data.method = "pin"
        self.config_data.pin_hash = hash_pin(pin)
        save_config(self.config_data)
        self.method_row.set_value(self._method_label("pin"))
        self.method_row.show_warning = False
        self._update_change_row()
        logger.info("PIN saved successfully")

    def _on_pattern_set(self, pattern):
        self.config_data.method = "pattern"
        self.config_data.pattern_hash = hash_pattern(pattern)
        save_config(self.config_data)
        self.method_row.set_value(self._method_label("pattern"))
        self.method_row.show_warning = False
        self._update_change_row()
        logger.info("Pattern saved successfully")

    def _show_timeout_picker(self):
        popup = TimeoutPickerPopup(
            current_timeout=self.config_data.timeout_seconds,
            on_select=self._on_timeout_selected
        )
        popup.open()

    def _on_timeout_selected(self, timeout):
        self.config_data.timeout_seconds = timeout
        save_config(self.config_data)
        self.timeout_row.set_value(self._timeout_label(timeout))

    def _change_credential(self):
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
