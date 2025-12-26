#!/usr/bin/env python3
"""
Flick Email Backend
Handles IMAP/SMTP operations for the email app
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
from datetime import datetime
from pathlib import Path

# State directory
STATE_DIR = Path.home() / ".local" / "state" / "flick" / "email"
ACCOUNTS_FILE = STATE_DIR / "accounts.json"
CACHE_DIR = STATE_DIR / "cache"
COMMANDS_FILE = STATE_DIR / "commands.json"
RESPONSE_FILE = STATE_DIR / "response.json"

# Ensure directories exist
STATE_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)


def log(msg):
    """Log to stderr for debugging"""
    print(f"[EmailBackend] {msg}", file=sys.stderr)
    sys.stderr.flush()


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
            "use_ssl": self.use_ssl
        }

    def connect_imap(self):
        """Connect to IMAP server"""
        try:
            if self.use_ssl:
                self.imap_conn = imaplib.IMAP4_SSL(self.imap_server, self.imap_port)
            else:
                self.imap_conn = imaplib.IMAP4(self.imap_server, self.imap_port)

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
                    server.login(self.username, self.password)
                    server.sendmail(self.email, all_recipients, msg.as_string())
            else:
                # STARTTLS
                with smtplib.SMTP(self.smtp_server, self.smtp_port) as server:
                    server.starttls(context=context)
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

        return {"error": f"Unknown action: {action}"}

    def run(self):
        """Main loop - watch for commands"""
        log("Email backend started")

        last_mtime = 0

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
