#!/usr/bin/env python3
"""
Flick Password Safe - KDBX database helper using pykeepass
Runs as a background daemon, communicates via HTTP with QML UI
"""

import os
import sys
import json
import time
import subprocess
import threading
from pathlib import Path
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

try:
    from pykeepass import PyKeePass
    from pykeepass.exceptions import CredentialsError
except ImportError:
    print("ERROR: pykeepass not installed. Run: pip install pykeepass")
    sys.exit(1)

# Config
STATE_DIR = Path.home() / ".local/state/flick/passwordsafe"
STATUS_FILE = Path("/tmp/flick_vault_status")
VAULTS_FILE = STATE_DIR / "vaults.json"
LAST_VAULT_FILE = STATE_DIR / "last_vault.json"
HTTP_PORT = 18943

# Global state
current_db = None
current_db_path = None


def log(msg):
    """Log message with timestamp"""
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


def init_state_dir():
    """Ensure state directory exists"""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not VAULTS_FILE.exists():
        VAULTS_FILE.write_text("[]")


def load_known_vaults():
    """Load list of known vault paths"""
    try:
        return json.loads(VAULTS_FILE.read_text())
    except:
        return []


def save_known_vaults(vaults):
    """Save list of known vault paths"""
    VAULTS_FILE.write_text(json.dumps(vaults, indent=2))


def add_known_vault(path):
    """Add a vault path to known list"""
    vaults = load_known_vaults()
    if path not in vaults:
        vaults.append(path)
        save_known_vaults(vaults)


def remove_known_vault(path):
    """Remove a vault path from known list"""
    vaults = load_known_vaults()
    if path in vaults:
        vaults.remove(path)
        save_known_vaults(vaults)


def get_last_vault():
    """Get the last opened vault path"""
    try:
        if LAST_VAULT_FILE.exists():
            data = json.loads(LAST_VAULT_FILE.read_text())
            return data.get("path")
    except:
        pass
    return None


def save_last_vault(path):
    """Save the last opened vault path for auto-open"""
    try:
        LAST_VAULT_FILE.write_text(json.dumps({"path": path}))
    except Exception as e:
        log(f"Error saving last vault: {e}")


def write_status(status):
    """Write status JSON for QML to read"""
    try:
        STATUS_FILE.write_text(json.dumps(status, indent=2))
    except Exception as e:
        log(f"Error writing status: {e}")


def unlock_vault(path, password):
    """Attempt to unlock a KDBX database"""
    global current_db, current_db_path

    try:
        kp = PyKeePass(path, password=password)
        current_db = kp
        current_db_path = path
        add_known_vault(path)
        save_last_vault(path)  # Remember for auto-open
        log(f"Unlocked vault: {path}")
        return True, None
    except CredentialsError:
        log(f"Wrong password for: {path}")
        return False, "Wrong password"
    except Exception as e:
        log(f"Error opening vault: {e}")
        return False, str(e)


def lock_vault():
    """Lock the current vault"""
    global current_db, current_db_path
    current_db = None
    current_db_path = None
    log("Vault locked")


def create_vault(path, password):
    """Create a new KDBX database"""
    global current_db, current_db_path

    try:
        # Create parent directory if needed
        Path(path).parent.mkdir(parents=True, exist_ok=True)

        # Create new database
        from pykeepass import create_database
        kp = create_database(path, password=password)
        kp.save()

        current_db = kp
        current_db_path = path
        add_known_vault(path)
        save_last_vault(path)  # Remember for auto-open
        log(f"Created vault: {path}")
        return True, None
    except Exception as e:
        log(f"Error creating vault: {e}")
        return False, str(e)


def get_entries():
    """Get all entries from current vault"""
    if not current_db:
        return []

    entries = []
    for entry in current_db.entries:
        # Skip entries in Recycle Bin
        if entry.group and "Recycle" in (entry.group.name or ""):
            continue

        entries.append({
            "uuid": str(entry.uuid),
            "title": entry.title or "(no title)",
            "username": entry.username or "",
            "url": entry.url or "",
            "group": entry.group.name if entry.group else "Root",
        })

    return sorted(entries, key=lambda e: e["title"].lower())


def get_entry(uuid):
    """Get full details of an entry"""
    if not current_db:
        return None

    for entry in current_db.entries:
        if str(entry.uuid) == uuid:
            return {
                "uuid": str(entry.uuid),
                "title": entry.title or "",
                "username": entry.username or "",
                "password": entry.password or "",
                "url": entry.url or "",
                "notes": entry.notes or "",
                "group": entry.group.name if entry.group else "Root",
            }
    return None


def add_entry(title, username, password, url="", notes=""):
    """Add a new entry to the vault"""
    if not current_db:
        return False, "Vault not unlocked"

    try:
        current_db.add_entry(current_db.root_group, title, username, password, url=url, notes=notes)
        current_db.save()
        log(f"Added entry: {title}")
        return True, None
    except Exception as e:
        log(f"Error adding entry: {e}")
        return False, str(e)


def update_entry(uuid, title, username, password, url="", notes=""):
    """Update an existing entry"""
    if not current_db:
        return False, "Vault not unlocked"

    try:
        for entry in current_db.entries:
            if str(entry.uuid) == uuid:
                entry.title = title
                entry.username = username
                entry.password = password
                entry.url = url
                entry.notes = notes
                current_db.save()
                log(f"Updated entry: {title}")
                return True, None
        return False, "Entry not found"
    except Exception as e:
        log(f"Error updating entry: {e}")
        return False, str(e)


def delete_entry(uuid):
    """Delete an entry from the vault"""
    if not current_db:
        return False, "Vault not unlocked"

    try:
        for entry in current_db.entries:
            if str(entry.uuid) == uuid:
                current_db.delete_entry(entry)
                current_db.save()
                log(f"Deleted entry: {entry.title}")
                return True, None
        return False, "Entry not found"
    except Exception as e:
        log(f"Error deleting entry: {e}")
        return False, str(e)


def copy_to_clipboard(text):
    """Copy text to clipboard using wl-copy (Wayland)"""
    try:
        # Try wl-copy first (Wayland)
        subprocess.run(["wl-copy", text], check=True, timeout=5)
        log("Copied to clipboard (wl-copy)")
        return True
    except Exception as e:
        log(f"wl-copy failed: {e}")

    try:
        # Fallback to xclip (X11)
        subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode(), check=True, timeout=5)
        log("Copied to clipboard (xclip)")
        return True
    except Exception as e:
        log(f"xclip failed: {e}")

    return False


def search_entries(query):
    """Search entries by title, username, or URL"""
    if not current_db:
        return []

    query = query.lower()
    results = []

    for entry in current_db.entries:
        # Skip Recycle Bin
        if entry.group and "Recycle" in (entry.group.name or ""):
            continue

        # Check if query matches title, username, or URL
        if (query in (entry.title or "").lower() or
            query in (entry.username or "").lower() or
            query in (entry.url or "").lower()):
            results.append({
                "uuid": str(entry.uuid),
                "title": entry.title or "(no title)",
                "username": entry.username or "",
                "url": entry.url or "",
                "group": entry.group.name if entry.group else "Root",
            })

    return sorted(results, key=lambda e: e["title"].lower())


def process_command(cmd):
    """Process a command from QML"""
    action = cmd.get("action")
    log(f"Processing command: {action}")

    if action == "list_vaults":
        vaults = load_known_vaults()
        # Check which vaults still exist
        valid_vaults = []
        for v in vaults:
            if Path(v).exists():
                valid_vaults.append({
                    "path": v,
                    "name": Path(v).stem,
                    "exists": True
                })
            else:
                valid_vaults.append({
                    "path": v,
                    "name": Path(v).stem,
                    "exists": False
                })
        write_status({
            "action": "list_vaults",
            "vaults": valid_vaults,
            "unlocked": current_db is not None,
            "current_path": current_db_path,
            "last_vault": get_last_vault()
        })

    elif action == "get_last_vault":
        last = get_last_vault()
        write_status({
            "action": "get_last_vault",
            "path": last,
            "exists": Path(last).exists() if last else False
        })

    elif action == "unlock":
        path = cmd.get("path")
        password = cmd.get("password")
        success, error = unlock_vault(path, password)

        status = {
            "action": "unlock",
            "success": success,
            "path": path,
        }
        if success:
            status["entries"] = get_entries()
        else:
            status["error"] = error
        write_status(status)

    elif action == "lock":
        lock_vault()
        write_status({
            "action": "lock",
            "success": True
        })

    elif action == "create":
        path = cmd.get("path")
        password = cmd.get("password")
        success, error = create_vault(path, password)

        status = {
            "action": "create",
            "success": success,
            "path": path,
        }
        if success:
            status["entries"] = []
        else:
            status["error"] = error
        write_status(status)

    elif action == "get_entries":
        write_status({
            "action": "get_entries",
            "entries": get_entries(),
            "unlocked": current_db is not None
        })

    elif action == "get_entry":
        uuid = cmd.get("uuid")
        entry = get_entry(uuid)
        write_status({
            "action": "get_entry",
            "entry": entry
        })

    elif action == "add_entry":
        success, error = add_entry(
            cmd.get("title", ""),
            cmd.get("username", ""),
            cmd.get("password", ""),
            cmd.get("url", ""),
            cmd.get("notes", "")
        )
        status = {"action": "add_entry", "success": success}
        if success:
            status["entries"] = get_entries()
        else:
            status["error"] = error
        write_status(status)

    elif action == "update_entry":
        success, error = update_entry(
            cmd.get("uuid"),
            cmd.get("title", ""),
            cmd.get("username", ""),
            cmd.get("password", ""),
            cmd.get("url", ""),
            cmd.get("notes", "")
        )
        status = {"action": "update_entry", "success": success}
        if success:
            status["entries"] = get_entries()
        else:
            status["error"] = error
        write_status(status)

    elif action == "delete_entry":
        success, error = delete_entry(cmd.get("uuid"))
        status = {"action": "delete_entry", "success": success}
        if success:
            status["entries"] = get_entries()
        else:
            status["error"] = error
        write_status(status)

    elif action == "copy_password":
        uuid = cmd.get("uuid")
        entry = get_entry(uuid)
        if entry:
            success = copy_to_clipboard(entry["password"])
            write_status({
                "action": "copy_password",
                "success": success
            })
        else:
            write_status({
                "action": "copy_password",
                "success": False,
                "error": "Entry not found"
            })

    elif action == "copy_username":
        uuid = cmd.get("uuid")
        entry = get_entry(uuid)
        if entry:
            success = copy_to_clipboard(entry["username"])
            write_status({
                "action": "copy_username",
                "success": success
            })
        else:
            write_status({
                "action": "copy_username",
                "success": False,
                "error": "Entry not found"
            })

    elif action == "search":
        query = cmd.get("query", "")
        results = search_entries(query)
        write_status({
            "action": "search",
            "results": results,
            "query": query
        })

    elif action == "remove_vault":
        path = cmd.get("path")
        remove_known_vault(path)
        write_status({
            "action": "remove_vault",
            "success": True
        })

    else:
        log(f"Unknown action: {action}")
        write_status({
            "action": action,
            "error": "Unknown action"
        })


class CommandHandler(BaseHTTPRequestHandler):
    """HTTP request handler for receiving commands from QML"""

    def log_message(self, format, *args):
        """Suppress default HTTP logging"""
        pass

    def do_POST(self):
        """Handle POST requests with commands"""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            cmd = json.loads(body)
            log(f"HTTP command: {cmd.get('action')}")
            process_command(cmd)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        except Exception as e:
            log(f"HTTP error: {e}")
            self.send_response(500)
            self.end_headers()

    def do_OPTIONS(self):
        """Handle CORS preflight"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()


def daemon_loop():
    """Main daemon loop - HTTP server for QML communication"""
    log("Password safe daemon started")
    init_state_dir()

    # Clean up old status file
    STATUS_FILE.unlink(missing_ok=True)

    # Initial status with last vault info
    last_vault = get_last_vault()
    write_status({
        "action": "ready",
        "unlocked": False,
        "last_vault": last_vault,
        "last_vault_exists": Path(last_vault).exists() if last_vault else False
    })

    # Start HTTP server
    try:
        server = HTTPServer(('127.0.0.1', HTTP_PORT), CommandHandler)
        log(f"HTTP server listening on port {HTTP_PORT}")
        server.serve_forever()
    except KeyboardInterrupt:
        log("Daemon interrupted")
    except Exception as e:
        log(f"Server error: {e}")
    finally:
        lock_vault()
        STATUS_FILE.unlink(missing_ok=True)
        log("Daemon stopped")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        daemon_loop()
    else:
        print("Usage: passwordsafe_helper.py daemon")
        print("  Run as background daemon for QML IPC")
