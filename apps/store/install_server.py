#!/usr/bin/env python3
# Flick Store Install Server
# Copyright (C) 2025 Flick Project
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

"""
Simple HTTP server for handling app install/uninstall requests from the Store.
Runs on localhost:7654 and calls flick-pkg for package operations.
"""

import http.server
import json
import os
import subprocess
import sys
import urllib.parse
from pathlib import Path

PORT = 7654
RESCAN_SIGNAL = "/tmp/flick_rescan_apps"

def find_flick_pkg():
    """Find the flick-pkg script."""
    candidates = [
        os.environ.get("FLICK_PKG"),
        "/home/droidian/Flick/flick-pkg",
        str(Path.home() / "Flick" / "flick-pkg"),
        "/home/david/Flick/flick-pkg",
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    return None

FLICK_PKG = find_flick_pkg()

class InstallHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        """Log to stdout with timestamp."""
        print(f"[{self.log_date_time_string()}] {format % args}")

    def send_cors_headers(self):
        """Send CORS headers for QML XMLHttpRequest."""
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_cors_headers()
        self.end_headers()

    def do_GET(self):
        """Handle status check and log requests."""
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/status":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()
            response = {"status": "ok", "flick_pkg": FLICK_PKG is not None}
            self.wfile.write(json.dumps(response).encode())

        elif parsed.path == "/installed":
            # Return the installed apps list
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()

            installed_file = Path.home() / ".local" / "state" / "flick" / "store_installed.json"
            apps = []
            if installed_file.exists():
                try:
                    with open(installed_file) as f:
                        data = json.load(f)
                        apps = data.get("apps", [])
                except:
                    pass
            self.wfile.write(json.dumps({"apps": apps}).encode())

        elif parsed.path.startswith("/logs/"):
            # Return logs for an app
            app_id = parsed.path[6:]  # Remove "/logs/"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()

            logs_dir = Path.home() / ".local" / "share" / "flick" / "logs" / app_id
            logs = []

            if logs_dir.exists():
                # Read all log files
                for log_file in sorted(logs_dir.glob("app.log*")):
                    try:
                        with open(log_file) as f:
                            for line in f:
                                line = line.rstrip()
                                if not line:
                                    continue
                                # Parse log line format: [timestamp] [LEVEL] message
                                level = "INFO"
                                if "[ERROR]" in line:
                                    level = "ERROR"
                                elif "[WARN]" in line:
                                    level = "WARN"
                                logs.append({"text": line, "level": level})
                    except Exception as e:
                        logs.append({"text": f"Error reading {log_file.name}: {e}", "level": "ERROR"})

            self.wfile.write(json.dumps({"logs": logs[-200:]}).encode())  # Last 200 lines

        else:
            self.send_response(404)
            self.send_cors_headers()
            self.end_headers()

    def do_POST(self):
        """Handle install/uninstall requests."""
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path not in ["/install", "/uninstall"]:
            self.send_response(404)
            self.send_cors_headers()
            self.end_headers()
            return

        # Read request body
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode() if content_length else ""

        # Parse app ID from body or query string
        app_id = None
        if body:
            try:
                data = json.loads(body)
                app_id = data.get("app") or data.get("id") or data.get("slug")
            except:
                app_id = body.strip()

        if not app_id:
            query = urllib.parse.parse_qs(parsed.query)
            app_id = query.get("app", [None])[0]

        if not app_id:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": "No app ID provided"}).encode())
            return

        if not FLICK_PKG:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": "flick-pkg not found"}).encode())
            return

        # Determine action
        action = "install" if parsed.path == "/install" else "uninstall"

        print(f"Processing: {action} {app_id}")

        # Run flick-pkg
        try:
            result = subprocess.run(
                [FLICK_PKG, action, app_id],
                capture_output=True,
                text=True,
                timeout=60
            )

            success = result.returncode == 0
            output = result.stdout + result.stderr

            # Trigger app rescan for shell
            Path(RESCAN_SIGNAL).touch()

            self.send_response(200 if success else 500)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()

            response = {
                "success": success,
                "action": action,
                "app": app_id,
                "output": output.strip()
            }
            self.wfile.write(json.dumps(response).encode())

            print(f"Result: {'success' if success else 'failed'} - {output.strip()}")

        except subprocess.TimeoutExpired:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Timeout"}).encode())
        except Exception as e:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

def main():
    if not FLICK_PKG:
        print("Error: flick-pkg not found", file=sys.stderr)
        sys.exit(1)

    print(f"Flick Store Install Server")
    print(f"Using: {FLICK_PKG}")
    print(f"Listening on: http://localhost:{PORT}")

    server = http.server.HTTPServer(("127.0.0.1", PORT), InstallHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

if __name__ == "__main__":
    main()
