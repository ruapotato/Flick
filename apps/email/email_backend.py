#!/usr/bin/env python3
"""
Flick Email Backend
Handles IMAP/SMTP operations for the email app
Supports OAuth2 authentication for Gmail, Outlook, etc.
"""

import os
import sys
import json
import imaplib
import smtplib
import email
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from email.header import decode_header
from email.utils import parseaddr, formataddr, parsedate_to_datetime
import ssl
import threading
import time
import hashlib
import re
import base64
import subprocess
import webbrowser
from datetime import datetime
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlencode, parse_qs, urlparse
import urllib.request
import urllib.error

# State directory
STATE_DIR = Path.home() / ".local" / "state" / "flick" / "email"
FLICK_STATE_DIR = Path.home() / ".local" / "state" / "flick"
ACCOUNTS_FILE = STATE_DIR / "accounts.json"
CACHE_DIR = STATE_DIR / "cache"
COMMANDS_FILE = STATE_DIR / "commands.json"
RESPONSE_FILE = STATE_DIR / "response.json"
SEEN_EMAILS_FILE = STATE_DIR / "seen_emails.json"
APP_NOTIFICATIONS_FILE = FLICK_STATE_DIR / "app_notifications.json"

# Ensure directories exist
STATE_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# OAuth2 Configuration
OAUTH_TOKENS_FILE = STATE_DIR / "oauth_tokens.json"

# OAuth2 providers configuration
# Users need to create their own OAuth app credentials
OAUTH_PROVIDERS = {
    "gmail": {
        "name": "Google",
        "auth_url": "https://accounts.google.com/o/oauth2/v2/auth",
        "token_url": "https://oauth2.googleapis.com/token",
        "scopes": ["https://mail.google.com/"],
        "imap_server": "imap.gmail.com",
        "imap_port": 993,
        "smtp_server": "smtp.gmail.com",
        "smtp_port": 587,
    },
    "outlook": {
        "name": "Microsoft",
        "auth_url": "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        "token_url": "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        "scopes": ["https://outlook.office.com/IMAP.AccessAsUser.All",
                   "https://outlook.office.com/SMTP.Send", "offline_access"],
        "imap_server": "outlook.office365.com",
        "imap_port": 993,
        "smtp_server": "smtp.office365.com",
        "smtp_port": 587,
    }
}

# Default OAuth client IDs (users should replace with their own for production)
# These are placeholder values - real OAuth requires registered app credentials
OAUTH_CREDENTIALS_FILE = STATE_DIR / "oauth_credentials.json"


class OAuthCallbackHandler(BaseHTTPRequestHandler):
    """HTTP handler to receive OAuth callback"""

    auth_code = None
    error = None

    def do_GET(self):
        """Handle the OAuth redirect callback"""
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if 'code' in params:
            OAuthCallbackHandler.auth_code = params['code'][0]
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b"""
                <html><body style="font-family: sans-serif; text-align: center; padding: 50px;">
                <h1 style="color: #4CAF50;">Authentication Successful!</h1>
                <p>You can close this window and return to the Flick Email app.</p>
                </body></html>
            """)
        elif 'error' in params:
            OAuthCallbackHandler.error = params.get('error_description', params['error'])[0]
            self.send_response(400)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(f"""
                <html><body style="font-family: sans-serif; text-align: center; padding: 50px;">
                <h1 style="color: #f44336;">Authentication Failed</h1>
                <p>{OAuthCallbackHandler.error}</p>
                <p>Please close this window and try again.</p>
                </body></html>
            """.encode())
        else:
            self.send_response(400)
            self.end_headers()

    def log_message(self, format, *args):
        """Suppress HTTP server logs"""
        pass


class OAuth2Manager:
    """Manages OAuth2 authentication flow"""

    def __init__(self):
        self.credentials = self.load_credentials()
        self.tokens = self.load_tokens()

    def load_credentials(self):
        """Load OAuth client credentials"""
        if OAUTH_CREDENTIALS_FILE.exists():
            try:
                with open(OAUTH_CREDENTIALS_FILE) as f:
                    return json.load(f)
            except:
                pass
        return {}

    def save_credentials(self, provider, client_id, client_secret=""):
        """Save OAuth client credentials for a provider"""
        self.credentials[provider] = {
            "client_id": client_id,
            "client_secret": client_secret
        }
        with open(OAUTH_CREDENTIALS_FILE, 'w') as f:
            json.dump(self.credentials, f, indent=2)

    def load_tokens(self):
        """Load saved OAuth tokens"""
        if OAUTH_TOKENS_FILE.exists():
            try:
                with open(OAUTH_TOKENS_FILE) as f:
                    return json.load(f)
            except:
                pass
        return {}

    def save_tokens(self):
        """Save OAuth tokens"""
        with open(OAUTH_TOKENS_FILE, 'w') as f:
            json.dump(self.tokens, f, indent=2)

    def get_auth_url(self, provider, redirect_uri):
        """Generate OAuth authorization URL"""
        if provider not in OAUTH_PROVIDERS:
            return None
        if provider not in self.credentials:
            return None

        config = OAUTH_PROVIDERS[provider]
        creds = self.credentials[provider]

        params = {
            "client_id": creds["client_id"],
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": " ".join(config["scopes"]),
            "access_type": "offline",
            "prompt": "consent"
        }

        return f"{config['auth_url']}?{urlencode(params)}"

    def exchange_code(self, provider, code, redirect_uri):
        """Exchange authorization code for tokens"""
        if provider not in OAUTH_PROVIDERS:
            return None
        if provider not in self.credentials:
            return None

        config = OAUTH_PROVIDERS[provider]
        creds = self.credentials[provider]

        data = {
            "client_id": creds["client_id"],
            "client_secret": creds.get("client_secret", ""),
            "code": code,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code"
        }

        try:
            req = urllib.request.Request(
                config["token_url"],
                data=urlencode(data).encode(),
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )
            with urllib.request.urlopen(req) as resp:
                tokens = json.loads(resp.read().decode())
                return tokens
        except urllib.error.HTTPError as e:
            log(f"Token exchange failed: {e.read().decode()}")
            return None

    def refresh_token(self, provider, email_addr):
        """Refresh an expired access token"""
        key = f"{provider}:{email_addr}"
        if key not in self.tokens:
            return None

        token_data = self.tokens[key]
        if "refresh_token" not in token_data:
            return None

        if provider not in self.credentials:
            return None

        config = OAUTH_PROVIDERS[provider]
        creds = self.credentials[provider]

        data = {
            "client_id": creds["client_id"],
            "client_secret": creds.get("client_secret", ""),
            "refresh_token": token_data["refresh_token"],
            "grant_type": "refresh_token"
        }

        try:
            req = urllib.request.Request(
                config["token_url"],
                data=urlencode(data).encode(),
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )
            with urllib.request.urlopen(req) as resp:
                new_tokens = json.loads(resp.read().decode())
                # Update stored tokens (keep refresh_token if not returned)
                token_data["access_token"] = new_tokens["access_token"]
                if "refresh_token" in new_tokens:
                    token_data["refresh_token"] = new_tokens["refresh_token"]
                token_data["expires_at"] = time.time() + new_tokens.get("expires_in", 3600)
                self.save_tokens()
                return token_data["access_token"]
        except urllib.error.HTTPError as e:
            log(f"Token refresh failed: {e.read().decode()}")
            return None

    def get_access_token(self, provider, email_addr):
        """Get a valid access token, refreshing if needed"""
        key = f"{provider}:{email_addr}"
        if key not in self.tokens:
            return None

        token_data = self.tokens[key]

        # Check if token is expired (with 5 min buffer)
        if token_data.get("expires_at", 0) < time.time() + 300:
            return self.refresh_token(provider, email_addr)

        return token_data.get("access_token")

    def store_tokens(self, provider, email_addr, tokens):
        """Store tokens for an account"""
        key = f"{provider}:{email_addr}"
        self.tokens[key] = {
            "access_token": tokens["access_token"],
            "refresh_token": tokens.get("refresh_token"),
            "expires_at": time.time() + tokens.get("expires_in", 3600)
        }
        self.save_tokens()

    def start_auth_flow(self, provider):
        """Start OAuth flow - returns auth URL and starts local server"""
        redirect_port = 8089
        redirect_uri = f"http://localhost:{redirect_port}/callback"

        auth_url = self.get_auth_url(provider, redirect_uri)
        if not auth_url:
            return {"error": "OAuth not configured for this provider"}

        # Reset handler state
        OAuthCallbackHandler.auth_code = None
        OAuthCallbackHandler.error = None

        # Start local server in background thread
        server = HTTPServer(('localhost', redirect_port), OAuthCallbackHandler)
        server.timeout = 120  # 2 minute timeout

        def run_server():
            while OAuthCallbackHandler.auth_code is None and OAuthCallbackHandler.error is None:
                server.handle_request()

        server_thread = threading.Thread(target=run_server, daemon=True)
        server_thread.start()

        # Open browser
        try:
            subprocess.run(['xdg-open', auth_url], check=True)
        except:
            webbrowser.open(auth_url)

        # Wait for callback (up to 2 minutes)
        server_thread.join(timeout=120)
        server.server_close()

        if OAuthCallbackHandler.error:
            return {"error": OAuthCallbackHandler.error}

        if not OAuthCallbackHandler.auth_code:
            return {"error": "Authentication timed out"}

        # Exchange code for tokens
        tokens = self.exchange_code(provider, OAuthCallbackHandler.auth_code, redirect_uri)
        if not tokens:
            return {"error": "Failed to get access token"}

        return {"tokens": tokens, "redirect_uri": redirect_uri}


# Global OAuth manager
oauth_manager = OAuth2Manager()


def log(msg):
    """Log to stderr for debugging"""
    print(f"[EmailBackend] {msg}", file=sys.stderr)
    sys.stderr.flush()


def send_notification(app_name, summary, body, urgency="normal"):
    """Send a notification via the Flick notification system"""
    try:
        notification = {
            "app_name": app_name,
            "summary": summary,
            "body": body,
            "urgency": urgency
        }
        data = {"notifications": [notification]}
        with open(APP_NOTIFICATIONS_FILE, 'w') as f:
            json.dump(data, f)
        log(f"Notification sent: {summary}")
    except Exception as e:
        log(f"Failed to send notification: {e}")


def load_seen_emails():
    """Load set of seen email IDs"""
    try:
        if SEEN_EMAILS_FILE.exists():
            with open(SEEN_EMAILS_FILE) as f:
                data = json.load(f)
                return set(data.get("seen", []))
    except:
        pass
    return set()


def save_seen_emails(seen_set):
    """Save set of seen email IDs"""
    try:
        # Keep only last 1000 to prevent file from growing too large
        seen_list = list(seen_set)[-1000:]
        with open(SEEN_EMAILS_FILE, 'w') as f:
            json.dump({"seen": seen_list}, f)
    except Exception as e:
        log(f"Failed to save seen emails: {e}")


def decode_mime_words(s):
    """Decode MIME encoded words in headers"""
    if s is None:
        return ""
    decoded_parts = []
    for part, encoding in decode_header(s):
        if isinstance(part, bytes):
            try:
                decoded_parts.append(part.decode(encoding or 'utf-8', errors='replace'))
            except:
                decoded_parts.append(part.decode('utf-8', errors='replace'))
        else:
            decoded_parts.append(part)
    return ''.join(decoded_parts)


def get_email_body(msg):
    """Extract plain text and HTML body from email message"""
    plain_body = ""
    html_body = ""

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition", ""))

            if "attachment" in content_disposition:
                continue

            if content_type == "text/plain":
                try:
                    charset = part.get_content_charset() or 'utf-8'
                    payload = part.get_payload(decode=True)
                    if payload:
                        plain_body = payload.decode(charset, errors='replace')
                except:
                    pass
            elif content_type == "text/html":
                try:
                    charset = part.get_content_charset() or 'utf-8'
                    payload = part.get_payload(decode=True)
                    if payload:
                        html_body = payload.decode(charset, errors='replace')
                except:
                    pass
    else:
        content_type = msg.get_content_type()
        try:
            charset = msg.get_content_charset() or 'utf-8'
            payload = msg.get_payload(decode=True)
            if payload:
                if content_type == "text/html":
                    html_body = payload.decode(charset, errors='replace')
                else:
                    plain_body = payload.decode(charset, errors='replace')
        except:
            pass

    return plain_body, html_body


def get_attachments(msg):
    """Extract attachment info from email"""
    attachments = []
    if msg.is_multipart():
        for part in msg.walk():
            content_disposition = str(part.get("Content-Disposition", ""))
            if "attachment" in content_disposition:
                filename = part.get_filename()
                if filename:
                    filename = decode_mime_words(filename)
                    size = len(part.get_payload(decode=True) or b'')
                    attachments.append({
                        "filename": filename,
                        "size": size,
                        "content_type": part.get_content_type()
                    })
    return attachments


def generate_oauth2_string(username, access_token):
    """Generate XOAUTH2 authentication string"""
    auth_string = f"user={username}\x01auth=Bearer {access_token}\x01\x01"
    return base64.b64encode(auth_string.encode()).decode()


class EmailAccount:
    """Represents an email account with IMAP/SMTP settings"""

    def __init__(self, data):
        self.id = data.get("id", "")
        self.email = data.get("email", "")
        self.name = data.get("name", "")
        self.imap_server = data.get("imap_server", "")
        self.imap_port = data.get("imap_port", 993)
        self.smtp_server = data.get("smtp_server", "")
        self.smtp_port = data.get("smtp_port", 587)
        self.username = data.get("username", "")
        self.password = data.get("password", "")
        self.use_ssl = data.get("use_ssl", True)
        self.auth_type = data.get("auth_type", "password")  # "password" or "oauth2"
        self.oauth_provider = data.get("oauth_provider", "")  # "gmail", "outlook", etc.
        self.imap_conn = None

    def to_dict(self):
        return {
            "id": self.id,
            "email": self.email,
            "name": self.name,
            "imap_server": self.imap_server,
            "imap_port": self.imap_port,
            "smtp_server": self.smtp_server,
            "smtp_port": self.smtp_port,
            "username": self.username,
            "password": self.password,
            "use_ssl": self.use_ssl,
            "auth_type": self.auth_type,
            "oauth_provider": self.oauth_provider
        }

    def connect_imap(self):
        """Connect to IMAP server (supports both password and OAuth2)"""
        try:
            if self.use_ssl:
                self.imap_conn = imaplib.IMAP4_SSL(self.imap_server, self.imap_port)
            else:
                self.imap_conn = imaplib.IMAP4(self.imap_server, self.imap_port)

            if self.auth_type == "oauth2" and self.oauth_provider:
                # OAuth2 authentication using XOAUTH2
                access_token = oauth_manager.get_access_token(self.oauth_provider, self.email)
                if not access_token:
                    log(f"Failed to get OAuth access token for {self.email}")
                    self.imap_conn = None
                    return False

                auth_string = generate_oauth2_string(self.email, access_token)
                self.imap_conn.authenticate('XOAUTH2', lambda x: auth_string.encode())
                log(f"Connected to IMAP with OAuth2: {self.imap_server}")
            else:
                # Password authentication
                self.imap_conn.login(self.username, self.password)
                log(f"Connected to IMAP: {self.imap_server}")

            return True
        except Exception as e:
            log(f"IMAP connection failed: {e}")
            self.imap_conn = None
            return False

    def disconnect_imap(self):
        """Disconnect from IMAP server"""
        if self.imap_conn:
            try:
                self.imap_conn.logout()
            except:
                pass
            self.imap_conn = None

    def get_folders(self):
        """Get list of folders"""
        if not self.imap_conn:
            if not self.connect_imap():
                return []

        try:
            status, folders = self.imap_conn.list()
            if status != 'OK':
                return []

            folder_list = []
            for folder in folders:
                if isinstance(folder, bytes):
                    # Parse folder name
                    match = re.search(rb'"([^"]*)" "?([^"]*)"?$', folder)
                    if match:
                        delimiter = match.group(1).decode('utf-8')
                        name = match.group(2).decode('utf-8')
                        # Handle IMAP modified UTF-7 encoding
                        try:
                            name = name.encode('utf-8').decode('utf-7')
                        except:
                            pass
                        folder_list.append({
                            "name": name,
                            "delimiter": delimiter
                        })

            return folder_list
        except Exception as e:
            log(f"Failed to get folders: {e}")
            return []

    def get_emails(self, folder="INBOX", limit=50, offset=0):
        """Get emails from a folder"""
        if not self.imap_conn:
            if not self.connect_imap():
                return []

        try:
            status, _ = self.imap_conn.select(folder, readonly=True)
            if status != 'OK':
                return []

            # Search for all messages
            status, messages = self.imap_conn.search(None, 'ALL')
            if status != 'OK':
                return []

            message_ids = messages[0].split()
            # Reverse to get newest first
            message_ids = message_ids[::-1]

            # Apply pagination
            message_ids = message_ids[offset:offset + limit]

            emails = []
            for msg_id in message_ids:
                try:
                    # Fetch headers only for list view
                    status, data = self.imap_conn.fetch(msg_id, '(FLAGS RFC822.HEADER)')
                    if status != 'OK':
                        continue

                    flags = []
                    header_data = None

                    for item in data:
                        if isinstance(item, tuple):
                            if b'FLAGS' in item[0]:
                                flags_match = re.search(rb'FLAGS \(([^)]*)\)', item[0])
                                if flags_match:
                                    flags = flags_match.group(1).decode('utf-8').split()
                            if b'RFC822.HEADER' in item[0]:
                                header_data = item[1]

                    if not header_data:
                        continue

                    msg = email.message_from_bytes(header_data)

                    # Parse date
                    date_str = msg.get('Date', '')
                    try:
                        date_obj = parsedate_to_datetime(date_str)
                        date_formatted = date_obj.strftime('%Y-%m-%d %H:%M')
                        timestamp = date_obj.timestamp()
                    except:
                        date_formatted = date_str[:20] if date_str else 'Unknown'
                        timestamp = 0

                    # Parse from
                    from_name, from_email = parseaddr(msg.get('From', ''))
                    from_name = decode_mime_words(from_name) or from_email

                    # Parse subject
                    subject = decode_mime_words(msg.get('Subject', '(No Subject)'))

                    emails.append({
                        "id": msg_id.decode('utf-8'),
                        "from_name": from_name,
                        "from_email": from_email,
                        "subject": subject,
                        "date": date_formatted,
                        "timestamp": timestamp,
                        "read": '\\Seen' in flags,
                        "flagged": '\\Flagged' in flags,
                        "has_attachment": False  # Would need full fetch to determine
                    })
                except Exception as e:
                    log(f"Failed to parse email {msg_id}: {e}")
                    continue

            return emails
        except Exception as e:
            log(f"Failed to get emails: {e}")
            return []

    def get_email(self, folder, msg_id):
        """Get full email content"""
        if not self.imap_conn:
            if not self.connect_imap():
                return None

        try:
            status, _ = self.imap_conn.select(folder, readonly=True)
            if status != 'OK':
                return None

            status, data = self.imap_conn.fetch(msg_id.encode(), '(FLAGS RFC822)')
            if status != 'OK':
                return None

            raw_email = None
            flags = []

            for item in data:
                if isinstance(item, tuple):
                    if b'FLAGS' in item[0]:
                        flags_match = re.search(rb'FLAGS \(([^)]*)\)', item[0])
                        if flags_match:
                            flags = flags_match.group(1).decode('utf-8').split()
                    if b'RFC822' in item[0]:
                        raw_email = item[1]

            if not raw_email:
                return None

            msg = email.message_from_bytes(raw_email)

            # Parse headers
            from_name, from_email = parseaddr(msg.get('From', ''))
            from_name = decode_mime_words(from_name) or from_email

            to_list = []
            for addr in msg.get_all('To', []):
                name, email_addr = parseaddr(addr)
                to_list.append({
                    "name": decode_mime_words(name) or email_addr,
                    "email": email_addr
                })

            cc_list = []
            for addr in msg.get_all('Cc', []):
                name, email_addr = parseaddr(addr)
                cc_list.append({
                    "name": decode_mime_words(name) or email_addr,
                    "email": email_addr
                })

            subject = decode_mime_words(msg.get('Subject', '(No Subject)'))

            date_str = msg.get('Date', '')
            try:
                date_obj = parsedate_to_datetime(date_str)
                date_formatted = date_obj.strftime('%A, %B %d, %Y at %H:%M')
            except:
                date_formatted = date_str

            # Get body
            plain_body, html_body = get_email_body(msg)

            # Get attachments
            attachments = get_attachments(msg)

            return {
                "id": msg_id,
                "from_name": from_name,
                "from_email": from_email,
                "to": to_list,
                "cc": cc_list,
                "subject": subject,
                "date": date_formatted,
                "plain_body": plain_body,
                "html_body": html_body,
                "attachments": attachments,
                "read": '\\Seen' in flags,
                "flagged": '\\Flagged' in flags
            }
        except Exception as e:
            log(f"Failed to get email: {e}")
            return None

    def mark_read(self, folder, msg_id, read=True):
        """Mark email as read/unread"""
        if not self.imap_conn:
            if not self.connect_imap():
                return False

        try:
            status, _ = self.imap_conn.select(folder)
            if status != 'OK':
                return False

            if read:
                self.imap_conn.store(msg_id.encode(), '+FLAGS', '\\Seen')
            else:
                self.imap_conn.store(msg_id.encode(), '-FLAGS', '\\Seen')
            return True
        except Exception as e:
            log(f"Failed to mark email: {e}")
            return False

    def delete_email(self, folder, msg_id):
        """Delete email (move to Trash)"""
        if not self.imap_conn:
            if not self.connect_imap():
                return False

        try:
            status, _ = self.imap_conn.select(folder)
            if status != 'OK':
                return False

            # Mark as deleted
            self.imap_conn.store(msg_id.encode(), '+FLAGS', '\\Deleted')
            self.imap_conn.expunge()
            return True
        except Exception as e:
            log(f"Failed to delete email: {e}")
            return False

    def move_email(self, folder, msg_id, dest_folder):
        """Move email to another folder"""
        if not self.imap_conn:
            if not self.connect_imap():
                return False

        try:
            status, _ = self.imap_conn.select(folder)
            if status != 'OK':
                return False

            # Copy to destination
            self.imap_conn.copy(msg_id.encode(), dest_folder)
            # Delete from source
            self.imap_conn.store(msg_id.encode(), '+FLAGS', '\\Deleted')
            self.imap_conn.expunge()
            return True
        except Exception as e:
            log(f"Failed to move email: {e}")
            return False

    def send_email(self, to, cc, bcc, subject, body, html_body=None, attachments=None):
        """Send email via SMTP"""
        try:
            msg = MIMEMultipart('alternative')
            msg['From'] = formataddr((self.name, self.email))
            msg['To'] = ', '.join(to)
            if cc:
                msg['Cc'] = ', '.join(cc)
            msg['Subject'] = subject

            # Add plain text body
            msg.attach(MIMEText(body, 'plain', 'utf-8'))

            # Add HTML body if provided
            if html_body:
                msg.attach(MIMEText(html_body, 'html', 'utf-8'))

            # Add attachments
            if attachments:
                for att in attachments:
                    if os.path.exists(att):
                        with open(att, 'rb') as f:
                            part = MIMEBase('application', 'octet-stream')
                            part.set_payload(f.read())
                            encoders.encode_base64(part)
                            part.add_header('Content-Disposition', f'attachment; filename="{os.path.basename(att)}"')
                            msg.attach(part)

            # Connect and send
            all_recipients = to + (cc or []) + (bcc or [])

            context = ssl.create_default_context()

            if self.smtp_port == 465:
                # SSL
                with smtplib.SMTP_SSL(self.smtp_server, self.smtp_port, context=context) as server:
                    if self.auth_type == "oauth2" and self.oauth_provider:
                        access_token = oauth_manager.get_access_token(self.oauth_provider, self.email)
                        if access_token:
                            auth_string = generate_oauth2_string(self.email, access_token)
                            server.docmd('AUTH', 'XOAUTH2 ' + auth_string)
                        else:
                            raise Exception("Failed to get OAuth access token")
                    else:
                        server.login(self.username, self.password)
                    server.sendmail(self.email, all_recipients, msg.as_string())
            else:
                # STARTTLS
                with smtplib.SMTP(self.smtp_server, self.smtp_port) as server:
                    server.starttls(context=context)
                    if self.auth_type == "oauth2" and self.oauth_provider:
                        access_token = oauth_manager.get_access_token(self.oauth_provider, self.email)
                        if access_token:
                            auth_string = generate_oauth2_string(self.email, access_token)
                            server.docmd('AUTH', 'XOAUTH2 ' + auth_string)
                        else:
                            raise Exception("Failed to get OAuth access token")
                    else:
                        server.login(self.username, self.password)
                    server.sendmail(self.email, all_recipients, msg.as_string())

            log(f"Email sent to {to}")
            return True
        except Exception as e:
            log(f"Failed to send email: {e}")
            return False


class EmailBackend:
    """Main backend class for email operations"""

    def __init__(self):
        self.accounts = []
        self.load_accounts()

    def load_accounts(self):
        """Load accounts from file"""
        self.accounts = []
        if ACCOUNTS_FILE.exists():
            try:
                with open(ACCOUNTS_FILE) as f:
                    data = json.load(f)
                    for acc_data in data.get("accounts", []):
                        self.accounts.append(EmailAccount(acc_data))
                log(f"Loaded {len(self.accounts)} accounts")
            except Exception as e:
                log(f"Failed to load accounts: {e}")

    def save_accounts(self):
        """Save accounts to file"""
        try:
            data = {"accounts": [acc.to_dict() for acc in self.accounts]}
            with open(ACCOUNTS_FILE, 'w') as f:
                json.dump(data, f, indent=2)
            log("Accounts saved")
        except Exception as e:
            log(f"Failed to save accounts: {e}")

    def add_account(self, account_data):
        """Add a new account"""
        account_data["id"] = hashlib.md5(account_data["email"].encode()).hexdigest()[:8]
        account = EmailAccount(account_data)

        # Test connection
        if account.connect_imap():
            account.disconnect_imap()
            self.accounts.append(account)
            self.save_accounts()
            return {"success": True, "id": account.id}
        else:
            return {"success": False, "error": "Failed to connect to IMAP server"}

    def remove_account(self, account_id):
        """Remove an account"""
        self.accounts = [acc for acc in self.accounts if acc.id != account_id]
        self.save_accounts()
        return {"success": True}

    def get_accounts(self):
        """Get list of accounts (without passwords)"""
        return [{
            "id": acc.id,
            "email": acc.email,
            "name": acc.name
        } for acc in self.accounts]

    def get_account(self, account_id):
        """Get account by ID"""
        for acc in self.accounts:
            if acc.id == account_id:
                return acc
        return None

    def process_command(self, cmd):
        """Process a command from the QML frontend"""
        action = cmd.get("action", "")

        if action == "get_accounts":
            return {"accounts": self.get_accounts()}

        elif action == "add_account":
            return self.add_account(cmd.get("account", {}))

        elif action == "remove_account":
            return self.remove_account(cmd.get("account_id", ""))

        elif action == "get_folders":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                folders = account.get_folders()
                return {"folders": folders}
            return {"error": "Account not found"}

        elif action == "get_emails":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                emails = account.get_emails(
                    cmd.get("folder", "INBOX"),
                    cmd.get("limit", 50),
                    cmd.get("offset", 0)
                )
                return {"emails": emails}
            return {"error": "Account not found"}

        elif action == "get_email":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                email_data = account.get_email(
                    cmd.get("folder", "INBOX"),
                    cmd.get("msg_id", "")
                )
                if email_data:
                    return {"email": email_data}
                return {"error": "Email not found"}
            return {"error": "Account not found"}

        elif action == "mark_read":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                success = account.mark_read(
                    cmd.get("folder", "INBOX"),
                    cmd.get("msg_id", ""),
                    cmd.get("read", True)
                )
                return {"success": success}
            return {"error": "Account not found"}

        elif action == "delete_email":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                success = account.delete_email(
                    cmd.get("folder", "INBOX"),
                    cmd.get("msg_id", "")
                )
                return {"success": success}
            return {"error": "Account not found"}

        elif action == "move_email":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                success = account.move_email(
                    cmd.get("folder", "INBOX"),
                    cmd.get("msg_id", ""),
                    cmd.get("dest_folder", "")
                )
                return {"success": success}
            return {"error": "Account not found"}

        elif action == "send_email":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                success = account.send_email(
                    cmd.get("to", []),
                    cmd.get("cc", []),
                    cmd.get("bcc", []),
                    cmd.get("subject", ""),
                    cmd.get("body", ""),
                    cmd.get("html_body"),
                    cmd.get("attachments", [])
                )
                return {"success": success}
            return {"error": "Account not found"}

        elif action == "test_connection":
            account_data = cmd.get("account", {})
            account = EmailAccount(account_data)
            if account.connect_imap():
                account.disconnect_imap()
                return {"success": True}
            return {"success": False, "error": "Connection failed"}

        elif action == "check_new_emails":
            return self.check_new_emails()

        # OAuth2 commands
        elif action == "oauth_set_credentials":
            provider = cmd.get("provider", "")
            client_id = cmd.get("client_id", "")
            client_secret = cmd.get("client_secret", "")
            if provider and client_id:
                oauth_manager.save_credentials(provider, client_id, client_secret)
                return {"success": True}
            return {"error": "Provider and client_id required"}

        elif action == "oauth_get_providers":
            # Return list of configured OAuth providers
            providers = []
            for key, config in OAUTH_PROVIDERS.items():
                providers.append({
                    "id": key,
                    "name": config["name"],
                    "configured": key in oauth_manager.credentials
                })
            return {"providers": providers}

        elif action == "oauth_start_auth":
            provider = cmd.get("provider", "")
            if provider not in OAUTH_PROVIDERS:
                return {"error": f"Unknown provider: {provider}"}
            if provider not in oauth_manager.credentials:
                return {"error": f"OAuth not configured for {provider}. Please set client credentials first."}

            result = oauth_manager.start_auth_flow(provider)
            return result

        elif action == "oauth_add_account":
            # Add an OAuth-authenticated account
            provider = cmd.get("provider", "")
            email_addr = cmd.get("email", "")
            name = cmd.get("name", "")
            tokens = cmd.get("tokens", {})

            if not provider or not email_addr or not tokens:
                return {"error": "Provider, email and tokens required"}

            if provider not in OAUTH_PROVIDERS:
                return {"error": f"Unknown provider: {provider}"}

            # Store tokens
            oauth_manager.store_tokens(provider, email_addr, tokens)

            # Create account with OAuth settings
            config = OAUTH_PROVIDERS[provider]
            account_data = {
                "id": hashlib.md5(email_addr.encode()).hexdigest()[:8],
                "email": email_addr,
                "name": name or email_addr.split("@")[0],
                "imap_server": config["imap_server"],
                "imap_port": config["imap_port"],
                "smtp_server": config["smtp_server"],
                "smtp_port": config["smtp_port"],
                "username": email_addr,
                "password": "",  # No password needed for OAuth
                "use_ssl": True,
                "auth_type": "oauth2",
                "oauth_provider": provider
            }

            account = EmailAccount(account_data)
            if account.connect_imap():
                account.disconnect_imap()
                self.accounts.append(account)
                self.save_accounts()
                return {"success": True, "id": account.id}
            else:
                return {"success": False, "error": "Failed to connect with OAuth"}

        return {"error": f"Unknown action: {action}"}

    def check_new_emails(self):
        """Check all accounts for new emails and send notifications"""
        if not self.accounts:
            return {"new_count": 0}

        seen = load_seen_emails()
        new_count = 0
        new_emails = []

        for account in self.accounts:
            try:
                # Get recent emails from INBOX
                emails = account.get_emails("INBOX", limit=20, offset=0)

                for email_info in emails:
                    # Create unique ID for this email
                    email_id = f"{account.id}:{email_info['id']}"

                    if email_id not in seen and not email_info.get('read', True):
                        # New unread email!
                        seen.add(email_id)
                        new_count += 1
                        new_emails.append({
                            "account": account.email,
                            "from": email_info.get("from_name", email_info.get("from_email", "Unknown")),
                            "subject": email_info.get("subject", "(No Subject)")
                        })

            except Exception as e:
                log(f"Failed to check new emails for {account.email}: {e}")

        # Save updated seen list
        save_seen_emails(seen)

        # Send notification for new emails
        if new_count > 0:
            if new_count == 1:
                email = new_emails[0]
                send_notification(
                    "Email",
                    email["from"],
                    email["subject"],
                    "normal"
                )
            else:
                # Multiple new emails
                send_notification(
                    "Email",
                    f"{new_count} new emails",
                    f"From {new_emails[0]['from']} and others",
                    "normal"
                )

        return {"new_count": new_count, "emails": new_emails}

    def run(self):
        """Main loop - watch for commands"""
        log("Email backend started")

        last_mtime = 0
        last_check = 0
        CHECK_INTERVAL = 60  # Check for new emails every 60 seconds

        while True:
            try:
                # Check for new commands
                if COMMANDS_FILE.exists():
                    mtime = COMMANDS_FILE.stat().st_mtime
                    if mtime > last_mtime:
                        last_mtime = mtime

                        with open(COMMANDS_FILE) as f:
                            cmd = json.load(f)

                        log(f"Processing command: {cmd.get('action', 'unknown')}")
                        response = self.process_command(cmd)

                        with open(RESPONSE_FILE, 'w') as f:
                            json.dump(response, f, indent=2)

                        log(f"Response written")

                # Periodic check for new emails (background notifications)
                now = time.time()
                if now - last_check >= CHECK_INTERVAL and self.accounts:
                    last_check = now
                    log("Background check for new emails...")
                    try:
                        result = self.check_new_emails()
                        if result.get("new_count", 0) > 0:
                            log(f"Found {result['new_count']} new email(s)")
                    except Exception as e:
                        log(f"Background email check failed: {e}")

                time.sleep(0.1)
            except KeyboardInterrupt:
                break
            except Exception as e:
                log(f"Error in main loop: {e}")
                time.sleep(1)

        # Cleanup
        for acc in self.accounts:
            acc.disconnect_imap()

        log("Email backend stopped")


if __name__ == "__main__":
    backend = EmailBackend()
    backend.run()
