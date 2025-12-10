#!/usr/bin/env python3
"""
Flick On-Screen Keyboard

A Python/Kivy on-screen keyboard for Flick that communicates with the
compositor via file-based IPC. The keyboard writes key events to a file
which the compositor reads and injects into the focused application.

Key features:
- Full QWERTY layout with numbers/symbols
- Shift and caps lock support
- Swipe to dismiss
- Modern dark theme matching Flick shell
- IPC via ~/.local/state/flick/keyboard_input
"""

import os
import sys
import json
import logging
from pathlib import Path

# Kivy configuration - must be before kivy imports
os.environ.setdefault('KIVY_LOG_LEVEL', 'debug')
# Disable SDL2 touch-to-mouse emulation to prevent double inputs
os.environ['SDL_TOUCH_MOUSE_EVENTS'] = '0'
# Set app ID for compositor to recognize this as the keyboard
os.environ['SDL_VIDEO_WAYLAND_WMCLASS'] = 'flick-keyboard'

from kivy.config import Config
Config.set('graphics', 'width', '720')
Config.set('graphics', 'height', '280')  # Keyboard height
Config.set('graphics', 'resizable', '0')
Config.set('graphics', 'borderless', '1')
Config.set('kivy', 'exit_on_escape', '0')

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.gridlayout import GridLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.widget import Widget
from kivy.graphics import Color, Rectangle, RoundedRectangle
from kivy.core.window import Window
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.properties import BooleanProperty, NumericProperty, StringProperty

# Logging setup
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger('flick-keyboard')

# Theme colors matching Flick shell
THEME = {
    'background': (0.04, 0.04, 0.06, 1),      # #0a0a0f
    'surface': (0.10, 0.10, 0.14, 1),         # #1a1a24
    'surface_variant': (0.15, 0.15, 0.20, 1), # #252532
    'primary': (0.29, 0.62, 1.0, 1),          # #4a9eff
    'primary_container': (0.10, 0.23, 0.36, 1), # #1a3a5c
    'text_primary': (1, 1, 1, 1),
    'text_dim': (0.63, 0.63, 0.69, 1),        # #a0a0b0
    'key_bg': (0.16, 0.16, 0.23, 1),          # #2a2a3a
    'key_special': (0.12, 0.12, 0.18, 1),     # #1e1e2e
}

# IPC path
STATE_DIR = Path.home() / '.local' / 'state' / 'flick'
KEYBOARD_INPUT_FILE = STATE_DIR / 'keyboard_input'


class KeyboardKey(Button):
    """A single keyboard key with custom styling"""

    is_special = BooleanProperty(False)
    is_active = BooleanProperty(False)
    width_factor = NumericProperty(1.0)

    def __init__(self, label='', shift_label='', **kwargs):
        self.label_text = label
        self.shift_label_text = shift_label or label.upper() if len(label) == 1 else label
        self.is_special = kwargs.pop('is_special', False)
        self.width_factor = kwargs.pop('width_factor', 1.0)

        super().__init__(**kwargs)
        self.text = label
        self.background_color = (0, 0, 0, 0)  # Transparent, we draw custom bg
        self.color = THEME['text_primary']
        self.font_size = dp(16) if not self.is_special else dp(12)
        self.bold = True

        self.bind(size=self._update_canvas, pos=self._update_canvas)
        self._update_canvas()

    def _update_canvas(self, *args):
        self.canvas.before.clear()
        with self.canvas.before:
            if self.state == 'down':
                Color(*THEME['primary'])
            elif self.is_active:
                Color(*THEME['primary_container'])
            elif self.is_special:
                Color(*THEME['key_special'])
            else:
                Color(*THEME['key_bg'])

            # Inner visual key with padding
            padding = dp(2)
            RoundedRectangle(
                pos=(self.x + padding, self.y + padding),
                size=(self.width - 2*padding, self.height - 2*padding),
                radius=[dp(6)]
            )

    def on_state(self, instance, value):
        self._update_canvas()

    def update_shift(self, shifted):
        """Update key label based on shift state"""
        if len(self.label_text) == 1 and self.label_text.isalpha():
            self.text = self.shift_label_text if shifted else self.label_text
        elif self.shift_label_text and self.shift_label_text != self.label_text:
            self.text = self.shift_label_text if shifted else self.label_text


class KeyboardRow(BoxLayout):
    """A single row of keyboard keys"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.orientation = 'horizontal'
        self.spacing = 0
        self.padding = 0


class FlickKeyboard(BoxLayout):
    """The main on-screen keyboard widget"""

    shifted = BooleanProperty(False)
    caps_lock = BooleanProperty(False)
    layout = NumericProperty(0)  # 0 = letters, 1 = numbers/symbols

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.orientation = 'vertical'
        self.spacing = 0
        self.padding = 0

        # Ensure state directory exists
        STATE_DIR.mkdir(parents=True, exist_ok=True)

        # Build keyboard rows
        self._build_keyboard()

        # Background
        with self.canvas.before:
            Color(*THEME['background'])
            self.bg_rect = Rectangle(pos=self.pos, size=self.size)
        self.bind(pos=self._update_bg, size=self._update_bg)

        # Track all keys for shift updates
        self.all_keys = []
        self._collect_keys(self)

    def _update_bg(self, *args):
        self.bg_rect.pos = self.pos
        self.bg_rect.size = self.size

    def _collect_keys(self, widget):
        """Collect all KeyboardKey widgets for shift updates"""
        if isinstance(widget, KeyboardKey):
            self.all_keys.append(widget)
        for child in widget.children:
            self._collect_keys(child)

    def _build_keyboard(self):
        """Build the keyboard layout"""
        self.clear_widgets()
        self.all_keys = []

        if self.layout == 0:
            self._build_letter_layout()
        else:
            self._build_symbol_layout()

        self._collect_keys(self)
        self._update_shift_display()

    def _build_letter_layout(self):
        """Build QWERTY letter layout"""
        shifted = self.shifted or self.caps_lock

        # Row 1: q w e r t y u i o p
        row1 = KeyboardRow()
        for key in 'qwertyuiop':
            btn = KeyboardKey(label=key)
            btn.bind(on_release=lambda b, k=key: self._on_key(k))
            row1.add_widget(btn)
        self.add_widget(row1)

        # Row 2: a s d f g h j k l
        row2 = KeyboardRow()
        for key in 'asdfghjkl':
            btn = KeyboardKey(label=key)
            btn.bind(on_release=lambda b, k=key: self._on_key(k))
            row2.add_widget(btn)
        self.add_widget(row2)

        # Row 3: SHIFT z x c v b n m DEL
        row3 = KeyboardRow()

        shift_btn = KeyboardKey(label='SHIFT', is_special=True, width_factor=1.5)
        shift_btn.is_active = self.shifted or self.caps_lock
        shift_btn.bind(on_release=lambda b: self._on_shift())
        shift_btn.size_hint_x = 1.5
        row3.add_widget(shift_btn)
        self.shift_btn = shift_btn

        for key in 'zxcvbnm':
            btn = KeyboardKey(label=key)
            btn.bind(on_release=lambda b, k=key: self._on_key(k))
            row3.add_widget(btn)

        del_btn = KeyboardKey(label='DEL', is_special=True, width_factor=1.5)
        del_btn.bind(on_release=lambda b: self._on_backspace())
        del_btn.size_hint_x = 1.5
        row3.add_widget(del_btn)

        self.add_widget(row3)

        # Row 4: 123 , SPACE . ENTER
        row4 = KeyboardRow()

        num_btn = KeyboardKey(label='123', is_special=True, width_factor=1.5)
        num_btn.bind(on_release=lambda b: self._toggle_layout())
        num_btn.size_hint_x = 1.5
        row4.add_widget(num_btn)

        comma_btn = KeyboardKey(label=',')
        comma_btn.bind(on_release=lambda b: self._on_key(','))
        row4.add_widget(comma_btn)

        space_btn = KeyboardKey(label='SPACE', is_special=True, width_factor=5.0)
        space_btn.bind(on_release=lambda b: self._on_space())
        space_btn.size_hint_x = 5.0
        row4.add_widget(space_btn)

        period_btn = KeyboardKey(label='.')
        period_btn.bind(on_release=lambda b: self._on_key('.'))
        row4.add_widget(period_btn)

        enter_btn = KeyboardKey(label='ENTER', is_special=True, width_factor=1.5)
        enter_btn.bind(on_release=lambda b: self._on_enter())
        enter_btn.size_hint_x = 1.5
        row4.add_widget(enter_btn)

        self.add_widget(row4)

    def _build_symbol_layout(self):
        """Build numbers/symbols layout"""
        shifted = self.shifted or self.caps_lock

        # Row 1: 1 2 3 4 5 6 7 8 9 0
        row1_keys = [('1', '!'), ('2', '@'), ('3', '#'), ('4', '$'), ('5', '%'),
                     ('6', '^'), ('7', '&'), ('8', '*'), ('9', '('), ('0', ')')]
        row1 = KeyboardRow()
        for key, shift_key in row1_keys:
            btn = KeyboardKey(label=key, shift_label=shift_key)
            btn.bind(on_release=lambda b, k=key, sk=shift_key: self._on_key(sk if (self.shifted or self.caps_lock) else k))
            row1.add_widget(btn)
        self.add_widget(row1)

        # Row 2: - = [ ] \ ; ' , .
        row2_keys = [('-', '_'), ('=', '+'), ('[', '{'), (']', '}'), ('\\', '|'),
                     (';', ':'), ("'", '"'), (',', '<'), ('.', '>')]
        row2 = KeyboardRow()
        for key, shift_key in row2_keys:
            btn = KeyboardKey(label=key, shift_label=shift_key)
            btn.bind(on_release=lambda b, k=key, sk=shift_key: self._on_key(sk if (self.shifted or self.caps_lock) else k))
            row2.add_widget(btn)
        self.add_widget(row2)

        # Row 3: SHIFT / ` @ # & * ( DEL
        row3 = KeyboardRow()

        shift_btn = KeyboardKey(label='SHIFT', is_special=True, width_factor=1.5)
        shift_btn.is_active = self.shifted or self.caps_lock
        shift_btn.bind(on_release=lambda b: self._on_shift())
        shift_btn.size_hint_x = 1.5
        row3.add_widget(shift_btn)
        self.shift_btn = shift_btn

        for key in ['/', '`', '@', '#', '&', '*', '(']:
            btn = KeyboardKey(label=key)
            btn.bind(on_release=lambda b, k=key: self._on_key(k))
            row3.add_widget(btn)

        del_btn = KeyboardKey(label='DEL', is_special=True, width_factor=1.5)
        del_btn.bind(on_release=lambda b: self._on_backspace())
        del_btn.size_hint_x = 1.5
        row3.add_widget(del_btn)

        self.add_widget(row3)

        # Row 4: ABC , SPACE . ENTER
        row4 = KeyboardRow()

        abc_btn = KeyboardKey(label='ABC', is_special=True, width_factor=1.5)
        abc_btn.bind(on_release=lambda b: self._toggle_layout())
        abc_btn.size_hint_x = 1.5
        row4.add_widget(abc_btn)

        comma_btn = KeyboardKey(label=',')
        comma_btn.bind(on_release=lambda b: self._on_key(','))
        row4.add_widget(comma_btn)

        space_btn = KeyboardKey(label='SPACE', is_special=True, width_factor=5.0)
        space_btn.bind(on_release=lambda b: self._on_space())
        space_btn.size_hint_x = 5.0
        row4.add_widget(space_btn)

        period_btn = KeyboardKey(label='.')
        period_btn.bind(on_release=lambda b: self._on_key('.'))
        row4.add_widget(period_btn)

        enter_btn = KeyboardKey(label='ENTER', is_special=True, width_factor=1.5)
        enter_btn.bind(on_release=lambda b: self._on_enter())
        enter_btn.size_hint_x = 1.5
        row4.add_widget(enter_btn)

        self.add_widget(row4)

    def _update_shift_display(self):
        """Update all keys to reflect shift state"""
        shifted = self.shifted or self.caps_lock
        for key in self.all_keys:
            key.update_shift(shifted)
        if hasattr(self, 'shift_btn'):
            self.shift_btn.is_active = shifted
            self.shift_btn._update_canvas()

    def _on_key(self, key):
        """Handle a regular key press"""
        shifted = self.shifted or self.caps_lock
        if len(key) == 1 and key.isalpha():
            char = key.upper() if shifted else key.lower()
        else:
            char = key

        logger.info(f"Key pressed: {char}")
        self._send_key_event('char', char)

        # Reset shift (but not caps lock) after typing
        if self.shifted and not self.caps_lock:
            self.shifted = False
            self._update_shift_display()

    def _on_shift(self):
        """Handle shift key"""
        # Toggle shift or caps lock on double tap
        self.shifted = not self.shifted
        self._update_shift_display()
        logger.info(f"Shift toggled: {self.shifted}")

    def _on_backspace(self):
        """Handle backspace"""
        logger.info("Backspace pressed")
        self._send_key_event('backspace', '')

    def _on_enter(self):
        """Handle enter"""
        logger.info("Enter pressed")
        self._send_key_event('enter', '')

    def _on_space(self):
        """Handle space"""
        logger.info("Space pressed")
        self._send_key_event('space', '')

    def _toggle_layout(self):
        """Toggle between letter and symbol layouts"""
        self.layout = 1 if self.layout == 0 else 0
        self._build_keyboard()
        logger.info(f"Layout toggled: {self.layout}")

    def _send_key_event(self, event_type, value):
        """Send key event to compositor via IPC file"""
        try:
            event = {'type': event_type, 'value': value}
            # Append to file (compositor reads and truncates)
            with open(KEYBOARD_INPUT_FILE, 'a') as f:
                f.write(json.dumps(event) + '\n')
            logger.debug(f"Sent key event: {event}")
        except Exception as e:
            logger.error(f"Failed to send key event: {e}")


class FlickKeyboardApp(App):
    """Main keyboard application"""

    def build(self):
        # Set window properties
        Window.clearcolor = THEME['background']

        # Create keyboard widget
        self.keyboard = FlickKeyboard()
        return self.keyboard

    def on_start(self):
        logger.info("Flick Keyboard started")
        # Clear any existing keyboard input file
        try:
            KEYBOARD_INPUT_FILE.unlink(missing_ok=True)
        except Exception as e:
            logger.warning(f"Could not clear keyboard input file: {e}")


if __name__ == '__main__':
    FlickKeyboardApp().run()
