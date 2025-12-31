#!/usr/bin/env python3
"""
Flick Password Safe - Secure KDBX password manager
Single Python process with GTK3 - no HTTP server, no sensitive data written to disk
"""

import sys
import os
from pathlib import Path
import json
import subprocess
import secrets
import string

# Set up environment before importing GTK
os.environ['GDK_BACKEND'] = 'wayland'
# Flick uses /run/flick as runtime dir with wayland-1 socket
if os.path.exists('/run/flick/wayland-1'):
    os.environ['XDG_RUNTIME_DIR'] = '/run/flick'
    os.environ['WAYLAND_DISPLAY'] = 'wayland-1'
    # Use home dir for dconf to avoid permission issues
    os.environ['DCONF_PATH'] = str(Path.home() / '.config/dconf')

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, Pango

try:
    from pykeepass import PyKeePass
    from pykeepass.exceptions import CredentialsError
    from pykeepass import create_database
except ImportError:
    print("ERROR: pykeepass not installed. Run: pip install pykeepass")
    sys.exit(1)

# Config paths
STATE_DIR = Path.home() / ".local/state/flick/passwordsafe"
VAULTS_FILE = STATE_DIR / "vaults.json"
LAST_VAULT_FILE = STATE_DIR / "last_vault.json"

# Colors
BG_COLOR = "#1a1a2e"
CARD_COLOR = "#252542"
ACCENT_COLOR = "#6c63ff"
TEXT_COLOR = "#ffffff"
SUBTEXT_COLOR = "#888888"


class PasswordSafe(Gtk.Window):
    def __init__(self):
        super().__init__(title="Password Safe")
        self.set_default_size(360, 640)

        # Apply dark theme
        self._setup_css()

        # State
        self._current_db = None
        self._current_db_path = None
        self._current_group_uuid = None
        self._navigation_stack = []  # For back navigation

        # Init state dir
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        if not VAULTS_FILE.exists():
            VAULTS_FILE.write_text("[]")

        # Main container
        self.main_stack = Gtk.Stack()
        self.main_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.add(self.main_stack)

        # Create pages
        self._create_vault_list_page()
        self._create_unlock_page()
        self._create_entries_page()
        self._create_entry_detail_page()
        self._create_add_entry_page()
        self._create_create_vault_page()

        # Auto-lock on focus loss
        self.connect("focus-out-event", self._on_focus_lost)

        # Check for last vault
        self._check_last_vault()

        self.show_all()

    def _setup_css(self):
        css = f"""
        window {{
            background-color: {BG_COLOR};
        }}
        .card {{
            background-color: {CARD_COLOR};
            border-radius: 12px;
            padding: 12px;
        }}
        .title {{
            font-size: 24px;
            font-weight: bold;
            color: {TEXT_COLOR};
        }}
        .subtitle {{
            font-size: 14px;
            color: {SUBTEXT_COLOR};
        }}
        .entry-title {{
            font-size: 16px;
            font-weight: bold;
            color: {TEXT_COLOR};
        }}
        .accent-button {{
            background-color: {ACCENT_COLOR};
            color: white;
            border-radius: 8px;
            padding: 12px 24px;
            border: none;
        }}
        .accent-button:hover {{
            background-color: #5a52d5;
        }}
        .icon-button {{
            background: transparent;
            border: none;
            padding: 8px;
            min-width: 44px;
            min-height: 44px;
        }}
        entry {{
            background-color: {CARD_COLOR};
            color: {TEXT_COLOR};
            border: 1px solid #444;
            border-radius: 8px;
            padding: 12px;
        }}
        .search-entry {{
            background-color: {CARD_COLOR};
            color: {TEXT_COLOR};
            border-radius: 20px;
            padding: 8px 16px;
        }}
        label {{
            color: {TEXT_COLOR};
        }}
        .error {{
            color: #ff6b6b;
        }}
        .password-field {{
            font-family: monospace;
        }}
        scrolledwindow {{
            background-color: transparent;
        }}
        """
        style_provider = Gtk.CssProvider()
        style_provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            style_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def _on_focus_lost(self, widget, event):
        if self._current_db:
            self._lock()
        return False

    def _check_last_vault(self):
        try:
            if LAST_VAULT_FILE.exists():
                data = json.loads(LAST_VAULT_FILE.read_text())
                path = data.get("path")
                if path and Path(path).exists():
                    self._pending_vault_path = path
                    self.main_stack.set_visible_child_name("unlock")
                    self.unlock_title.set_text(Path(path).stem)
                    return
        except:
            pass
        self.main_stack.set_visible_child_name("vault_list")

    def _load_vaults(self):
        try:
            paths = json.loads(VAULTS_FILE.read_text())
            return [{"path": p, "name": Path(p).stem, "exists": Path(p).exists()} for p in paths]
        except:
            return []

    def _save_vaults(self, vaults):
        paths = [v["path"] for v in vaults]
        VAULTS_FILE.write_text(json.dumps(paths, indent=2))

    def _save_last_vault(self, path):
        LAST_VAULT_FILE.write_text(json.dumps({"path": path}))

    # ==================== VAULT LIST PAGE ====================
    def _create_vault_list_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_margin_top(20)
        page.set_margin_bottom(20)
        page.set_margin_start(16)
        page.set_margin_end(16)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        title = Gtk.Label(label="🔐 Password Safe")
        title.get_style_context().add_class("title")
        title.set_halign(Gtk.Align.START)
        header.pack_start(title, True, True, 0)

        add_btn = Gtk.Button(label="＋")
        add_btn.get_style_context().add_class("icon-button")
        add_btn.connect("clicked", lambda w: self.main_stack.set_visible_child_name("create_vault"))
        header.pack_end(add_btn, False, False, 0)

        page.pack_start(header, False, False, 0)

        # Vault list
        self.vault_list_box = Gtk.ListBox()
        self.vault_list_box.set_selection_mode(Gtk.SelectionMode.NONE)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.vault_list_box)
        page.pack_start(scroll, True, True, 0)

        # Import button
        import_btn = Gtk.Button(label="📁 Import Existing Vault")
        import_btn.get_style_context().add_class("accent-button")
        import_btn.connect("clicked", self._on_import_vault)
        page.pack_end(import_btn, False, False, 0)

        self.main_stack.add_named(page, "vault_list")
        self._refresh_vault_list()

    def _refresh_vault_list(self):
        for child in self.vault_list_box.get_children():
            self.vault_list_box.remove(child)

        vaults = self._load_vaults()
        if not vaults:
            empty = Gtk.Label(label="No vaults yet\nCreate or import one to get started")
            empty.get_style_context().add_class("subtitle")
            empty.set_justify(Gtk.Justification.CENTER)
            self.vault_list_box.add(empty)
        else:
            for vault in vaults:
                row = self._create_vault_row(vault)
                self.vault_list_box.add(row)

        self.vault_list_box.show_all()

    def _create_vault_row(self, vault):
        row = Gtk.ListBoxRow()
        row.set_margin_top(4)
        row.set_margin_bottom(4)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.get_style_context().add_class("card")

        icon = Gtk.Label(label="🔒")
        box.pack_start(icon, False, False, 8)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        name = Gtk.Label(label=vault["name"])
        name.get_style_context().add_class("entry-title")
        name.set_halign(Gtk.Align.START)
        info.pack_start(name, False, False, 0)

        path = Gtk.Label(label=vault["path"])
        path.get_style_context().add_class("subtitle")
        path.set_halign(Gtk.Align.START)
        path.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        info.pack_start(path, False, False, 0)

        box.pack_start(info, True, True, 0)

        # Unlock button
        unlock_btn = Gtk.Button(label="→")
        unlock_btn.get_style_context().add_class("icon-button")
        unlock_btn.connect("clicked", lambda w, v=vault: self._show_unlock(v["path"]))
        box.pack_end(unlock_btn, False, False, 0)

        row.add(box)
        return row

    def _on_import_vault(self, widget):
        dialog = Gtk.FileChooserDialog(
            title="Select KDBX File",
            parent=self,
            action=Gtk.FileChooserAction.OPEN
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK
        )

        filter_kdbx = Gtk.FileFilter()
        filter_kdbx.set_name("KeePass files")
        filter_kdbx.add_pattern("*.kdbx")
        dialog.add_filter(filter_kdbx)

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            vaults = self._load_vaults()
            if not any(v["path"] == path for v in vaults):
                vaults.append({"path": path, "name": Path(path).stem, "exists": True})
                self._save_vaults(vaults)
                self._refresh_vault_list()
            self._show_unlock(path)
        dialog.destroy()

    # ==================== UNLOCK PAGE ====================
    def _create_unlock_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        page.set_margin_top(40)
        page.set_margin_bottom(40)
        page.set_margin_start(24)
        page.set_margin_end(24)
        page.set_valign(Gtk.Align.CENTER)

        # Back button
        back_btn = Gtk.Button(label="← Back")
        back_btn.get_style_context().add_class("icon-button")
        back_btn.set_halign(Gtk.Align.START)
        back_btn.connect("clicked", lambda w: self.main_stack.set_visible_child_name("vault_list"))
        page.pack_start(back_btn, False, False, 0)

        # Icon
        icon = Gtk.Label(label="🔐")
        icon.set_markup("<span size='72000'>🔐</span>")
        page.pack_start(icon, False, False, 20)

        # Title
        self.unlock_title = Gtk.Label(label="Vault")
        self.unlock_title.get_style_context().add_class("title")
        page.pack_start(self.unlock_title, False, False, 0)

        # Password entry
        self.unlock_password = Gtk.Entry()
        self.unlock_password.set_placeholder_text("Master Password")
        self.unlock_password.set_visibility(False)
        self.unlock_password.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        self.unlock_password.connect("activate", self._on_unlock)
        page.pack_start(self.unlock_password, False, False, 20)

        # Error label
        self.unlock_error = Gtk.Label()
        self.unlock_error.get_style_context().add_class("error")
        page.pack_start(self.unlock_error, False, False, 0)

        # Unlock button
        unlock_btn = Gtk.Button(label="Unlock")
        unlock_btn.get_style_context().add_class("accent-button")
        unlock_btn.connect("clicked", self._on_unlock)
        page.pack_start(unlock_btn, False, False, 0)

        self.main_stack.add_named(page, "unlock")
        self._pending_vault_path = None

    def _show_unlock(self, path):
        self._pending_vault_path = path
        self.unlock_title.set_text(Path(path).stem)
        self.unlock_password.set_text("")
        self.unlock_error.set_text("")
        self.main_stack.set_visible_child_name("unlock")

    def _on_unlock(self, widget):
        path = self._pending_vault_path
        password = self.unlock_password.get_text()

        if not path or not password:
            self.unlock_error.set_text("Please enter password")
            return

        try:
            kp = PyKeePass(path, password=password)
            self._current_db = kp
            self._current_db_path = path
            self._current_group_uuid = None
            self._navigation_stack = []

            # Add to known vaults
            vaults = self._load_vaults()
            if not any(v["path"] == path for v in vaults):
                vaults.append({"path": path, "name": Path(path).stem, "exists": True})
                self._save_vaults(vaults)

            self._save_last_vault(path)
            self._load_entries()
            self.main_stack.set_visible_child_name("entries")

        except CredentialsError:
            self.unlock_error.set_text("Wrong password")
        except Exception as e:
            self.unlock_error.set_text(str(e))

    def _lock(self):
        self._current_db = None
        self._current_db_path = None
        self._current_group_uuid = None
        self._navigation_stack = []
        self.unlock_password.set_text("")
        self._check_last_vault()

    # ==================== ENTRIES PAGE ====================
    def _create_entries_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.set_margin_top(16)
        header.set_margin_bottom(8)
        header.set_margin_start(16)
        header.set_margin_end(16)

        self.entries_back_btn = Gtk.Button(label="←")
        self.entries_back_btn.get_style_context().add_class("icon-button")
        self.entries_back_btn.connect("clicked", self._on_entries_back)
        header.pack_start(self.entries_back_btn, False, False, 0)

        self.entries_title = Gtk.Label(label="Passwords")
        self.entries_title.get_style_context().add_class("title")
        self.entries_title.set_halign(Gtk.Align.START)
        header.pack_start(self.entries_title, True, True, 8)

        lock_btn = Gtk.Button(label="🔓")
        lock_btn.get_style_context().add_class("icon-button")
        lock_btn.connect("clicked", lambda w: self._lock())
        header.pack_end(lock_btn, False, False, 0)

        add_btn = Gtk.Button(label="＋")
        add_btn.get_style_context().add_class("icon-button")
        add_btn.connect("clicked", self._show_add_entry)
        header.pack_end(add_btn, False, False, 0)

        page.pack_start(header, False, False, 0)

        # Search
        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text("🔍 Search...")
        self.search_entry.get_style_context().add_class("search-entry")
        self.search_entry.set_margin_start(16)
        self.search_entry.set_margin_end(16)
        self.search_entry.set_margin_bottom(8)
        self.search_entry.connect("changed", self._on_search)
        page.pack_start(self.search_entry, False, False, 0)

        # Entries list
        self.entries_list = Gtk.ListBox()
        self.entries_list.set_selection_mode(Gtk.SelectionMode.NONE)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.entries_list)
        page.pack_start(scroll, True, True, 0)

        self.main_stack.add_named(page, "entries")

    def _on_entries_back(self, widget):
        if self._navigation_stack:
            self._current_group_uuid = self._navigation_stack.pop()
            self._load_entries()
        else:
            self._lock()

    def _load_entries(self, search_query=None):
        for child in self.entries_list.get_children():
            self.entries_list.remove(child)

        if not self._current_db:
            return

        # Update title and back button
        if self._current_group_uuid:
            for group in self._current_db.groups:
                if str(group.uuid) == self._current_group_uuid:
                    self.entries_title.set_text(group.name or "Group")
                    break
            self.entries_back_btn.set_label("←")
        else:
            self.entries_title.set_text(Path(self._current_db_path).stem)
            self.entries_back_btn.set_label("🔓")

        # Find target group
        target_group = self._current_db.root_group
        if self._current_group_uuid:
            for group in self._current_db.groups:
                if str(group.uuid) == self._current_group_uuid:
                    target_group = group
                    break

        # Add subgroups first
        if not search_query:
            for group in sorted(target_group.subgroups, key=lambda g: (g.name or "").lower()):
                if "Recycle" in (group.name or ""):
                    continue
                row = self._create_group_row(group)
                self.entries_list.add(row)

        # Add entries
        entries = []
        if search_query:
            query = search_query.lower()
            for entry in self._current_db.entries:
                if entry.group and "Recycle" in (entry.group.name or ""):
                    continue
                if (query in (entry.title or "").lower() or
                    query in (entry.username or "").lower() or
                    query in (entry.url or "").lower()):
                    entries.append(entry)
        else:
            entries = [e for e in target_group.entries if not (e.group and "Recycle" in (e.group.name or ""))]

        for entry in sorted(entries, key=lambda e: (e.title or "").lower()):
            row = self._create_entry_row(entry)
            self.entries_list.add(row)

        self.entries_list.show_all()

    def _create_group_row(self, group):
        row = Gtk.ListBoxRow()
        row.set_margin_top(4)
        row.set_margin_bottom(4)
        row.set_margin_start(16)
        row.set_margin_end(16)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.get_style_context().add_class("card")

        icon = Gtk.Label(label="📁")
        box.pack_start(icon, False, False, 8)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        name = Gtk.Label(label=group.name or "(unnamed)")
        name.get_style_context().add_class("entry-title")
        name.set_halign(Gtk.Align.START)
        info.pack_start(name, False, False, 0)

        count = len([e for e in group.entries if not (e.group and "Recycle" in (e.group.name or ""))])
        subcount = len([g for g in group.subgroups if "Recycle" not in (g.name or "")])
        subtitle = f"{count} items"
        if subcount:
            subtitle += f", {subcount} folders"
        sub = Gtk.Label(label=subtitle)
        sub.get_style_context().add_class("subtitle")
        sub.set_halign(Gtk.Align.START)
        info.pack_start(sub, False, False, 0)

        box.pack_start(info, True, True, 0)

        arrow = Gtk.Label(label="→")
        box.pack_end(arrow, False, False, 8)

        event_box = Gtk.EventBox()
        event_box.add(box)
        event_box.connect("button-press-event", lambda w, e, g=group: self._open_group(g))

        row.add(event_box)
        return row

    def _open_group(self, group):
        self._navigation_stack.append(self._current_group_uuid)
        self._current_group_uuid = str(group.uuid)
        self.search_entry.set_text("")
        self._load_entries()

    def _create_entry_row(self, entry):
        row = Gtk.ListBoxRow()
        row.set_margin_top(4)
        row.set_margin_bottom(4)
        row.set_margin_start(16)
        row.set_margin_end(16)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.get_style_context().add_class("card")

        icon = Gtk.Label(label="🔑")
        box.pack_start(icon, False, False, 8)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        title = Gtk.Label(label=entry.title or "(no title)")
        title.get_style_context().add_class("entry-title")
        title.set_halign(Gtk.Align.START)
        info.pack_start(title, False, False, 0)

        user = Gtk.Label(label=entry.username or "")
        user.get_style_context().add_class("subtitle")
        user.set_halign(Gtk.Align.START)
        info.pack_start(user, False, False, 0)

        box.pack_start(info, True, True, 0)

        # Copy password button
        copy_btn = Gtk.Button(label="📋")
        copy_btn.get_style_context().add_class("icon-button")
        copy_btn.connect("clicked", lambda w, e=entry: self._copy_password(e))
        box.pack_end(copy_btn, False, False, 0)

        event_box = Gtk.EventBox()
        event_box.add(box)
        event_box.connect("button-press-event", lambda w, e, ent=entry: self._show_entry_detail(ent))

        row.add(event_box)
        return row

    def _on_search(self, widget):
        query = widget.get_text().strip()
        self._load_entries(query if query else None)

    def _copy_password(self, entry):
        try:
            subprocess.run(["wl-copy", entry.password or ""], check=True, timeout=5)
        except:
            try:
                subprocess.run(["xclip", "-selection", "clipboard"],
                             input=(entry.password or "").encode(), check=True, timeout=5)
            except:
                pass

    # ==================== ENTRY DETAIL PAGE ====================
    def _create_entry_detail_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_margin_top(16)
        page.set_margin_bottom(16)
        page.set_margin_start(16)
        page.set_margin_end(16)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)

        back_btn = Gtk.Button(label="← Back")
        back_btn.get_style_context().add_class("icon-button")
        back_btn.connect("clicked", lambda w: self.main_stack.set_visible_child_name("entries"))
        header.pack_start(back_btn, False, False, 0)

        self.detail_title = Gtk.Label()
        self.detail_title.get_style_context().add_class("title")
        header.pack_start(self.detail_title, True, True, 0)

        delete_btn = Gtk.Button(label="🗑")
        delete_btn.get_style_context().add_class("icon-button")
        delete_btn.connect("clicked", self._on_delete_entry)
        header.pack_end(delete_btn, False, False, 0)

        page.pack_start(header, False, False, 0)

        # Content scroll
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        # Username field
        self.detail_username_label = Gtk.Label(label="Username")
        self.detail_username_label.get_style_context().add_class("subtitle")
        self.detail_username_label.set_halign(Gtk.Align.START)
        content.pack_start(self.detail_username_label, False, False, 0)

        user_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.detail_username = Gtk.Label()
        self.detail_username.set_halign(Gtk.Align.START)
        self.detail_username.set_selectable(True)
        user_box.pack_start(self.detail_username, True, True, 0)

        copy_user_btn = Gtk.Button(label="📋")
        copy_user_btn.get_style_context().add_class("icon-button")
        copy_user_btn.connect("clicked", self._copy_detail_username)
        user_box.pack_end(copy_user_btn, False, False, 0)
        content.pack_start(user_box, False, False, 0)

        # Password field
        pw_label = Gtk.Label(label="Password")
        pw_label.get_style_context().add_class("subtitle")
        pw_label.set_halign(Gtk.Align.START)
        content.pack_start(pw_label, False, False, 8)

        pw_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.detail_password = Gtk.Label(label="••••••••")
        self.detail_password.get_style_context().add_class("password-field")
        self.detail_password.set_halign(Gtk.Align.START)
        pw_box.pack_start(self.detail_password, True, True, 0)

        self.show_pw_btn = Gtk.Button(label="👁")
        self.show_pw_btn.get_style_context().add_class("icon-button")
        self.show_pw_btn.connect("clicked", self._toggle_password_visibility)
        pw_box.pack_end(self.show_pw_btn, False, False, 0)

        copy_pw_btn = Gtk.Button(label="📋")
        copy_pw_btn.get_style_context().add_class("icon-button")
        copy_pw_btn.connect("clicked", self._copy_detail_password)
        pw_box.pack_end(copy_pw_btn, False, False, 0)
        content.pack_start(pw_box, False, False, 0)

        # URL field
        url_label = Gtk.Label(label="URL")
        url_label.get_style_context().add_class("subtitle")
        url_label.set_halign(Gtk.Align.START)
        content.pack_start(url_label, False, False, 8)

        self.detail_url = Gtk.Label()
        self.detail_url.set_halign(Gtk.Align.START)
        self.detail_url.set_selectable(True)
        self.detail_url.set_line_wrap(True)
        content.pack_start(self.detail_url, False, False, 0)

        # Notes field
        notes_label = Gtk.Label(label="Notes")
        notes_label.get_style_context().add_class("subtitle")
        notes_label.set_halign(Gtk.Align.START)
        content.pack_start(notes_label, False, False, 8)

        self.detail_notes = Gtk.Label()
        self.detail_notes.set_halign(Gtk.Align.START)
        self.detail_notes.set_selectable(True)
        self.detail_notes.set_line_wrap(True)
        content.pack_start(self.detail_notes, False, False, 0)

        scroll.add(content)
        page.pack_start(scroll, True, True, 0)

        # Edit button
        edit_btn = Gtk.Button(label="Edit")
        edit_btn.get_style_context().add_class("accent-button")
        edit_btn.connect("clicked", self._edit_current_entry)
        page.pack_end(edit_btn, False, False, 0)

        self.main_stack.add_named(page, "entry_detail")
        self._current_entry = None
        self._password_visible = False

    def _show_entry_detail(self, entry):
        self._current_entry = entry
        self._password_visible = False

        self.detail_title.set_text(entry.title or "(no title)")
        self.detail_username.set_text(entry.username or "")
        self.detail_password.set_text("••••••••")
        self.detail_url.set_text(entry.url or "")
        self.detail_notes.set_text(entry.notes or "")

        self.main_stack.set_visible_child_name("entry_detail")
        return True

    def _toggle_password_visibility(self, widget):
        if not self._current_entry:
            return
        self._password_visible = not self._password_visible
        if self._password_visible:
            self.detail_password.set_text(self._current_entry.password or "")
            self.show_pw_btn.set_label("🙈")
        else:
            self.detail_password.set_text("••••••••")
            self.show_pw_btn.set_label("👁")

    def _copy_detail_username(self, widget):
        if self._current_entry:
            self._copy_to_clipboard(self._current_entry.username or "")

    def _copy_detail_password(self, widget):
        if self._current_entry:
            self._copy_to_clipboard(self._current_entry.password or "")

    def _copy_to_clipboard(self, text):
        try:
            subprocess.run(["wl-copy", text], check=True, timeout=5)
        except:
            try:
                subprocess.run(["xclip", "-selection", "clipboard"],
                             input=text.encode(), check=True, timeout=5)
            except:
                pass

    def _on_delete_entry(self, widget):
        if not self._current_entry or not self._current_db:
            return

        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Delete '{self._current_entry.title}'?"
        )
        dialog.format_secondary_text("This cannot be undone.")
        response = dialog.run()
        dialog.destroy()

        if response == Gtk.ResponseType.YES:
            self._current_db.delete_entry(self._current_entry)
            self._current_db.save()
            self._current_entry = None
            self._load_entries()
            self.main_stack.set_visible_child_name("entries")

    def _edit_current_entry(self, widget):
        if not self._current_entry:
            return
        self._editing_entry = self._current_entry
        self.add_entry_title.set_text("Edit Entry")
        self.add_title_entry.set_text(self._current_entry.title or "")
        self.add_username_entry.set_text(self._current_entry.username or "")
        self.add_password_entry.set_text(self._current_entry.password or "")
        self.add_url_entry.set_text(self._current_entry.url or "")
        self.add_notes_entry.get_buffer().set_text(self._current_entry.notes or "")
        self.main_stack.set_visible_child_name("add_entry")

    # ==================== ADD/EDIT ENTRY PAGE ====================
    def _create_add_entry_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_margin_top(16)
        page.set_margin_bottom(16)
        page.set_margin_start(16)
        page.set_margin_end(16)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)

        back_btn = Gtk.Button(label="← Cancel")
        back_btn.get_style_context().add_class("icon-button")
        back_btn.connect("clicked", self._cancel_add_entry)
        header.pack_start(back_btn, False, False, 0)

        self.add_entry_title = Gtk.Label(label="New Entry")
        self.add_entry_title.get_style_context().add_class("title")
        header.pack_start(self.add_entry_title, True, True, 0)

        page.pack_start(header, False, False, 0)

        # Form
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

        # Title
        title_label = Gtk.Label(label="Title")
        title_label.get_style_context().add_class("subtitle")
        title_label.set_halign(Gtk.Align.START)
        form.pack_start(title_label, False, False, 0)

        self.add_title_entry = Gtk.Entry()
        self.add_title_entry.set_placeholder_text("e.g., Gmail")
        form.pack_start(self.add_title_entry, False, False, 0)

        # Username
        user_label = Gtk.Label(label="Username")
        user_label.get_style_context().add_class("subtitle")
        user_label.set_halign(Gtk.Align.START)
        form.pack_start(user_label, False, False, 8)

        self.add_username_entry = Gtk.Entry()
        self.add_username_entry.set_placeholder_text("e.g., user@email.com")
        form.pack_start(self.add_username_entry, False, False, 0)

        # Password
        pw_label = Gtk.Label(label="Password")
        pw_label.get_style_context().add_class("subtitle")
        pw_label.set_halign(Gtk.Align.START)
        form.pack_start(pw_label, False, False, 8)

        pw_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.add_password_entry = Gtk.Entry()
        self.add_password_entry.set_visibility(False)
        pw_box.pack_start(self.add_password_entry, True, True, 0)

        show_btn = Gtk.Button(label="👁")
        show_btn.get_style_context().add_class("icon-button")
        show_btn.connect("clicked", lambda w: self.add_password_entry.set_visibility(
            not self.add_password_entry.get_visibility()))
        pw_box.pack_end(show_btn, False, False, 0)

        gen_btn = Gtk.Button(label="🎲")
        gen_btn.get_style_context().add_class("icon-button")
        gen_btn.connect("clicked", self._generate_password)
        pw_box.pack_end(gen_btn, False, False, 0)
        form.pack_start(pw_box, False, False, 0)

        # URL
        url_label = Gtk.Label(label="URL")
        url_label.get_style_context().add_class("subtitle")
        url_label.set_halign(Gtk.Align.START)
        form.pack_start(url_label, False, False, 8)

        self.add_url_entry = Gtk.Entry()
        self.add_url_entry.set_placeholder_text("https://...")
        form.pack_start(self.add_url_entry, False, False, 0)

        # Notes
        notes_label = Gtk.Label(label="Notes")
        notes_label.get_style_context().add_class("subtitle")
        notes_label.set_halign(Gtk.Align.START)
        form.pack_start(notes_label, False, False, 8)

        self.add_notes_entry = Gtk.TextView()
        self.add_notes_entry.set_wrap_mode(Gtk.WrapMode.WORD)
        notes_frame = Gtk.Frame()
        notes_frame.add(self.add_notes_entry)
        notes_frame.set_size_request(-1, 100)
        form.pack_start(notes_frame, False, False, 0)

        scroll.add(form)
        page.pack_start(scroll, True, True, 0)

        # Save button
        save_btn = Gtk.Button(label="Save")
        save_btn.get_style_context().add_class("accent-button")
        save_btn.connect("clicked", self._save_entry)
        page.pack_end(save_btn, False, False, 0)

        self.main_stack.add_named(page, "add_entry")
        self._editing_entry = None

    def _show_add_entry(self, widget):
        self._editing_entry = None
        self.add_entry_title.set_text("New Entry")
        self.add_title_entry.set_text("")
        self.add_username_entry.set_text("")
        self.add_password_entry.set_text("")
        self.add_url_entry.set_text("")
        self.add_notes_entry.get_buffer().set_text("")
        self.main_stack.set_visible_child_name("add_entry")

    def _cancel_add_entry(self, widget):
        if self._editing_entry:
            self.main_stack.set_visible_child_name("entry_detail")
        else:
            self.main_stack.set_visible_child_name("entries")

    def _generate_password(self, widget):
        chars = string.ascii_letters + string.digits + "!@#$%^&*()_+-=[]{}|;:,.<>?"
        password = ''.join(secrets.choice(chars) for _ in range(20))
        self.add_password_entry.set_text(password)
        self.add_password_entry.set_visibility(True)

    def _save_entry(self, widget):
        if not self._current_db:
            return

        title = self.add_title_entry.get_text()
        username = self.add_username_entry.get_text()
        password = self.add_password_entry.get_text()
        url = self.add_url_entry.get_text()

        buf = self.add_notes_entry.get_buffer()
        notes = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)

        try:
            if self._editing_entry:
                # Update existing
                self._editing_entry.title = title
                self._editing_entry.username = username
                self._editing_entry.password = password
                self._editing_entry.url = url
                self._editing_entry.notes = notes
            else:
                # Create new
                target_group = self._current_db.root_group
                if self._current_group_uuid:
                    for group in self._current_db.groups:
                        if str(group.uuid) == self._current_group_uuid:
                            target_group = group
                            break

                self._current_db.add_entry(target_group, title, username, password, url=url, notes=notes)

            self._current_db.save()
            self._load_entries()
            self.main_stack.set_visible_child_name("entries")

        except Exception as e:
            dialog = Gtk.MessageDialog(
                transient_for=self,
                flags=0,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                text="Error saving entry"
            )
            dialog.format_secondary_text(str(e))
            dialog.run()
            dialog.destroy()

    # ==================== CREATE VAULT PAGE ====================
    def _create_create_vault_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        page.set_margin_top(40)
        page.set_margin_bottom(40)
        page.set_margin_start(24)
        page.set_margin_end(24)
        page.set_valign(Gtk.Align.CENTER)

        # Back button
        back_btn = Gtk.Button(label="← Back")
        back_btn.get_style_context().add_class("icon-button")
        back_btn.set_halign(Gtk.Align.START)
        back_btn.connect("clicked", lambda w: self.main_stack.set_visible_child_name("vault_list"))
        page.pack_start(back_btn, False, False, 0)

        # Title
        title = Gtk.Label(label="Create New Vault")
        title.get_style_context().add_class("title")
        page.pack_start(title, False, False, 20)

        # Name entry
        name_label = Gtk.Label(label="Vault Name")
        name_label.get_style_context().add_class("subtitle")
        name_label.set_halign(Gtk.Align.START)
        page.pack_start(name_label, False, False, 0)

        self.create_name_entry = Gtk.Entry()
        self.create_name_entry.set_placeholder_text("My Passwords")
        page.pack_start(self.create_name_entry, False, False, 0)

        # Password entry
        pw_label = Gtk.Label(label="Master Password")
        pw_label.get_style_context().add_class("subtitle")
        pw_label.set_halign(Gtk.Align.START)
        page.pack_start(pw_label, False, False, 8)

        self.create_password_entry = Gtk.Entry()
        self.create_password_entry.set_placeholder_text("Strong password")
        self.create_password_entry.set_visibility(False)
        page.pack_start(self.create_password_entry, False, False, 0)

        # Confirm password
        confirm_label = Gtk.Label(label="Confirm Password")
        confirm_label.get_style_context().add_class("subtitle")
        confirm_label.set_halign(Gtk.Align.START)
        page.pack_start(confirm_label, False, False, 8)

        self.create_confirm_entry = Gtk.Entry()
        self.create_confirm_entry.set_visibility(False)
        page.pack_start(self.create_confirm_entry, False, False, 0)

        # Error label
        self.create_error = Gtk.Label()
        self.create_error.get_style_context().add_class("error")
        page.pack_start(self.create_error, False, False, 0)

        # Create button
        create_btn = Gtk.Button(label="Create Vault")
        create_btn.get_style_context().add_class("accent-button")
        create_btn.connect("clicked", self._on_create_vault)
        page.pack_start(create_btn, False, False, 20)

        self.main_stack.add_named(page, "create_vault")

    def _on_create_vault(self, widget):
        name = self.create_name_entry.get_text().strip()
        password = self.create_password_entry.get_text()
        confirm = self.create_confirm_entry.get_text()

        if not name:
            self.create_error.set_text("Please enter a vault name")
            return

        if not password:
            self.create_error.set_text("Please enter a password")
            return

        if password != confirm:
            self.create_error.set_text("Passwords don't match")
            return

        if len(password) < 4:
            self.create_error.set_text("Password too short")
            return

        path = str(STATE_DIR / f"{name}.kdbx")

        try:
            kp = create_database(path, password=password)
            kp.save()

            self._current_db = kp
            self._current_db_path = path
            self._current_group_uuid = None
            self._navigation_stack = []

            vaults = self._load_vaults()
            vaults.append({"path": path, "name": name, "exists": True})
            self._save_vaults(vaults)
            self._save_last_vault(path)

            # Clear form
            self.create_name_entry.set_text("")
            self.create_password_entry.set_text("")
            self.create_confirm_entry.set_text("")
            self.create_error.set_text("")

            self._load_entries()
            self.main_stack.set_visible_child_name("entries")

        except Exception as e:
            self.create_error.set_text(str(e))


def main():
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    app = PasswordSafe()
    app.connect("destroy", Gtk.main_quit)

    Gtk.main()


if __name__ == "__main__":
    main()
