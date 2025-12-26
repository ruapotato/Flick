#!/usr/bin/env python3
"""
Flick Email Backend
Uses GNOME Online Accounts for OAuth authentication
"""

import os
import sys
import json
import imaplib
import smtplib
import email
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import decode_header
from email.utils import parseaddr, formataddr, parsedate_to_datetime
import ssl
import time
import hashlib
import re
import base64
import subprocess
from datetime import datetime
from pathlib import Path

# GOA imports
import gi
gi.require_version('Goa', '1.0')
from gi.repository import Goa, GLib

# State directory
STATE_DIR = Path.home() / ".local" / "state" / "flick" / "email"
FLICK_STATE_DIR = Path.home() / ".local" / "state" / "flick"
COMMANDS_FILE = STATE_DIR / "commands.json"
RESPONSE_FILE = STATE_DIR / "response.json"
SEEN_EMAILS_FILE = STATE_DIR / "seen_emails.json"
APP_NOTIFICATIONS_FILE = FLICK_STATE_DIR / "app_notifications.json"

# Ensure directories exist
STATE_DIR.mkdir(parents=True, exist_ok=True)


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

            if content_type == "text/plain" and not plain_body:
                try:
                    charset = part.get_content_charset() or 'utf-8'
                    payload = part.get_payload(decode=True)
                    if payload:
                        plain_body = payload.decode(charset, errors='replace')
                except:
                    pass
            elif content_type == "text/html" and not html_body:
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
        seen_list = list(seen_set)[-1000:]
        with open(SEEN_EMAILS_FILE, 'w') as f:
            json.dump({"seen": seen_list}, f)
    except Exception as e:
        log(f"Failed to save seen emails: {e}")


class GOAEmailAccount:
    """Email account backed by GNOME Online Accounts"""

    def __init__(self, goa_object):
        self.goa_object = goa_object
        self.account = goa_object.get_account()
        self.mail = goa_object.get_mail()
        self.imap_conn = None

        # Extract account info
        self.id = self.account.get_id()
        self.email = self.mail.get_email_address() if self.mail else ""
        self.name = self.account.get_presentation_identity() or self.email
        self.provider = self.account.get_provider_name()

        # Get server settings from GOA
        if self.mail:
            self.imap_server = self.mail.get_imap_host() or ""
            self.smtp_server = self.mail.get_smtp_host() or ""
            self.imap_use_ssl = self.mail.get_imap_use_ssl()
            self.smtp_use_ssl = self.mail.get_smtp_use_ssl()
        else:
            self.imap_server = ""
            self.smtp_server = ""
            self.imap_use_ssl = True
            self.smtp_use_ssl = True

    def get_access_token(self):
        """Get OAuth2 access token from GOA"""
        try:
            oauth2 = self.goa_object.get_oauth2_based()
            if oauth2:
                # This automatically refreshes if needed
                success, token = oauth2.call_get_access_token_sync(None)
                if success:
                    return token
        except Exception as e:
            log(f"Failed to get access token: {e}")
        return None

    def to_dict(self):
        return {
            "id": self.id,
            "email": self.email,
            "name": self.name,
            "provider": self.provider
        }

    def connect_imap(self):
        """Connect to IMAP server using OAuth2 from GOA"""
        try:
            # Get fresh access token from GOA
            access_token = self.get_access_token()
            if not access_token:
                log(f"No access token available for {self.email}")
                return False

            # Connect to IMAP
            port = 993 if self.imap_use_ssl else 143
            if self.imap_use_ssl:
                self.imap_conn = imaplib.IMAP4_SSL(self.imap_server, port)
            else:
                self.imap_conn = imaplib.IMAP4(self.imap_server, port)
                self.imap_conn.starttls()

            # Authenticate with XOAUTH2
            auth_string = generate_oauth2_string(self.email, access_token)
            self.imap_conn.authenticate('XOAUTH2', lambda x: auth_string.encode())

            log(f"Connected to IMAP: {self.imap_server} as {self.email}")
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
                    match = re.search(rb'"([^"]*)" "?([^"]*)"?$', folder)
                    if match:
                        delimiter = match.group(1).decode('utf-8')
                        name = match.group(2).decode('utf-8')
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

            status, messages = self.imap_conn.search(None, 'ALL')
            if status != 'OK':
                return []

            message_ids = messages[0].split()
            message_ids = message_ids[::-1]  # Newest first
            message_ids = message_ids[offset:offset + limit]

            emails = []
            for msg_id in message_ids:
                try:
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

                    date_str = msg.get('Date', '')
                    try:
                        date_obj = parsedate_to_datetime(date_str)
                        date_formatted = date_obj.strftime('%Y-%m-%d %H:%M')
                    except:
                        date_formatted = date_str[:20] if date_str else 'Unknown'

                    from_name, from_email_addr = parseaddr(msg.get('From', ''))
                    from_name = decode_mime_words(from_name) or from_email_addr
                    subject = decode_mime_words(msg.get('Subject', '(No Subject)'))

                    emails.append({
                        "id": msg_id.decode('utf-8'),
                        "from_name": from_name,
                        "from_email": from_email_addr,
                        "subject": subject,
                        "date": date_formatted,
                        "read": '\\Seen' in flags,
                        "flagged": '\\Flagged' in flags
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

            from_name, from_email_addr = parseaddr(msg.get('From', ''))
            from_name = decode_mime_words(from_name) or from_email_addr

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

            plain_body, html_body = get_email_body(msg)
            attachments = get_attachments(msg)

            return {
                "id": msg_id,
                "from_name": from_name,
                "from_email": from_email_addr,
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
        """Delete email"""
        if not self.imap_conn:
            if not self.connect_imap():
                return False

        try:
            status, _ = self.imap_conn.select(folder)
            if status != 'OK':
                return False

            self.imap_conn.store(msg_id.encode(), '+FLAGS', '\\Deleted')
            self.imap_conn.expunge()
            return True
        except Exception as e:
            log(f"Failed to delete email: {e}")
            return False

    def send_email(self, to, cc, bcc, subject, body):
        """Send email via SMTP with OAuth2"""
        try:
            access_token = self.get_access_token()
            if not access_token:
                log("No access token for sending")
                return False

            msg = MIMEMultipart('alternative')
            msg['From'] = formataddr((self.name, self.email))
            msg['To'] = ', '.join(to)
            if cc:
                msg['Cc'] = ', '.join(cc)
            msg['Subject'] = subject
            msg.attach(MIMEText(body, 'plain', 'utf-8'))

            all_recipients = to + (cc or []) + (bcc or [])
            context = ssl.create_default_context()

            port = 465 if self.smtp_use_ssl else 587
            auth_string = generate_oauth2_string(self.email, access_token)

            if self.smtp_use_ssl:
                with smtplib.SMTP_SSL(self.smtp_server, port, context=context) as server:
                    server.docmd('AUTH', 'XOAUTH2 ' + auth_string)
                    server.sendmail(self.email, all_recipients, msg.as_string())
            else:
                with smtplib.SMTP(self.smtp_server, port) as server:
                    server.starttls(context=context)
                    server.docmd('AUTH', 'XOAUTH2 ' + auth_string)
                    server.sendmail(self.email, all_recipients, msg.as_string())

            log(f"Email sent to {to}")
            return True
        except Exception as e:
            log(f"Failed to send email: {e}")
            return False


class EmailBackend:
    """Email backend using GNOME Online Accounts"""

    def __init__(self):
        self.goa_client = None
        self.accounts = []
        self.init_goa()

    def init_goa(self):
        """Initialize GNOME Online Accounts client"""
        try:
            self.goa_client = Goa.Client.new_sync(None)
            self.refresh_accounts()
            log("GOA client initialized")
        except Exception as e:
            log(f"Failed to initialize GOA: {e}")

    def refresh_accounts(self):
        """Refresh account list from GOA"""
        self.accounts = []
        if not self.goa_client:
            return

        try:
            for goa_obj in self.goa_client.get_accounts():
                # Only include accounts with mail capability
                mail = goa_obj.get_mail()
                if mail and mail.get_imap_host():
                    account = GOAEmailAccount(goa_obj)
                    self.accounts.append(account)
                    log(f"Found mail account: {account.email} ({account.provider})")
        except Exception as e:
            log(f"Failed to refresh accounts: {e}")

    def get_account(self, account_id):
        """Get account by ID"""
        for acc in self.accounts:
            if acc.id == account_id:
                return acc
        return None

    def launch_account_setup(self):
        """Launch GNOME Online Accounts settings"""
        try:
            subprocess.Popen(['gnome-control-center', 'online-accounts'])
            return {"success": True}
        except Exception as e:
            log(f"Failed to launch GOA settings: {e}")
            return {"error": str(e)}

    def process_command(self, cmd):
        """Process a command from the QML frontend"""
        action = cmd.get("action", "")

        if action == "get_accounts":
            self.refresh_accounts()  # Always refresh to catch new accounts
            return {"accounts": [acc.to_dict() for acc in self.accounts]}

        elif action == "add_account":
            # Launch GNOME Online Accounts
            return self.launch_account_setup()

        elif action == "remove_account":
            # Can't remove from here - user must use GNOME Settings
            return {"error": "Please remove accounts in Settings → Online Accounts"}

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

        elif action == "send_email":
            account = self.get_account(cmd.get("account_id", ""))
            if account:
                success = account.send_email(
                    cmd.get("to", []),
                    cmd.get("cc", []),
                    cmd.get("bcc", []),
                    cmd.get("subject", ""),
                    cmd.get("body", "")
                )
                return {"success": success}
            return {"error": "Account not found"}

        elif action == "check_new_emails":
            return self.check_new_emails()

        return {"error": f"Unknown action: {action}"}

    def check_new_emails(self):
        """Check all accounts for new emails"""
        if not self.accounts:
            return {"new_count": 0}

        seen = load_seen_emails()
        new_count = 0
        new_emails = []

        for account in self.accounts:
            try:
                emails = account.get_emails("INBOX", limit=20, offset=0)
                for email_info in emails:
                    email_id = f"{account.id}:{email_info['id']}"
                    if email_id not in seen and not email_info.get('read', True):
                        seen.add(email_id)
                        new_count += 1
                        new_emails.append({
                            "account": account.email,
                            "from": email_info.get("from_name", "Unknown"),
                            "subject": email_info.get("subject", "(No Subject)")
                        })
            except Exception as e:
                log(f"Failed to check {account.email}: {e}")

        save_seen_emails(seen)

        if new_count > 0:
            if new_count == 1:
                em = new_emails[0]
                send_notification("Email", em["from"], em["subject"])
            else:
                send_notification("Email", f"{new_count} new emails",
                                f"From {new_emails[0]['from']} and others")

        return {"new_count": new_count, "emails": new_emails}

    def run(self):
        """Main loop"""
        log("Email backend started (GOA mode)")

        last_mtime = 0
        last_check = 0
        CHECK_INTERVAL = 60

        while True:
            try:
                if COMMANDS_FILE.exists():
                    mtime = COMMANDS_FILE.stat().st_mtime
                    if mtime > last_mtime:
                        last_mtime = mtime

                        with open(COMMANDS_FILE) as f:
                            cmd = json.load(f)

                        log(f"Processing: {cmd.get('action', 'unknown')}")
                        response = self.process_command(cmd)

                        with open(RESPONSE_FILE, 'w') as f:
                            json.dump(response, f, indent=2)

                # Background email check
                now = time.time()
                if now - last_check >= CHECK_INTERVAL and self.accounts:
                    last_check = now
                    try:
                        result = self.check_new_emails()
                        if result.get("new_count", 0) > 0:
                            log(f"Found {result['new_count']} new email(s)")
                    except Exception as e:
                        log(f"Background check failed: {e}")

                time.sleep(0.1)
            except KeyboardInterrupt:
                break
            except Exception as e:
                log(f"Error: {e}")
                time.sleep(1)

        for acc in self.accounts:
            acc.disconnect_imap()
        log("Email backend stopped")


if __name__ == "__main__":
    backend = EmailBackend()
    backend.run()
