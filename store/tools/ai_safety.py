#!/usr/bin/env python3
"""
AI Safety Verification Pipeline for Flick Store

Multi-level AI verification system for app prompts and generated code.
Integrates with Claude Code for building apps.

SPDX-License-Identifier: AGPL-3.0-or-later
Copyright (C) 2026 Flick Project
"""

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional

VERSION = "1.0.0"


class SafetyLevel(Enum):
    """Safety check levels."""
    SAFE = "safe"
    NEEDS_REVIEW = "needs_review"
    REJECTED = "rejected"


class CheckType(Enum):
    """Types of safety checks."""
    PROMPT = "prompt"          # Initial prompt review
    GENERATED = "generated"    # Generated code review
    PACKAGE = "package"        # Final package review


@dataclass
class SafetyResult:
    """Result of a safety check."""
    level: SafetyLevel
    check_type: CheckType
    score: float  # 0.0 to 1.0
    passed: bool
    issues: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    notes: str = ""
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())


# ============ Blocklists and Patterns ============

BLOCKED_KEYWORDS = [
    # Harmful content
    "malware", "ransomware", "keylogger", "spyware", "trojan",
    "virus", "rootkit", "backdoor", "exploit", "payload",

    # Dangerous operations
    "rm -rf /", "format c:", ":(){ :|:& };:", "dd if=/dev/zero",
    "chmod -R 777 /", "sudo rm", "> /dev/sda",

    # Crypto mining
    "cryptominer", "mining pool", "xmrig", "nicehash",

    # Data exfiltration
    "exfiltrate", "steal credentials", "keylog", "screen capture secretly",

    # System manipulation
    "disable security", "bypass authentication", "privilege escalation",
    "disable firewall", "hide process",
]

BLOCKED_PATTERNS = [
    r"curl.*\|.*sh",           # Piping curl to shell
    r"wget.*\|.*sh",           # Piping wget to shell
    r"eval\s*\(",              # Dangerous eval
    r"exec\s*\(",              # Dangerous exec
    r"subprocess\.call.*shell=True",  # Shell injection risk
    r"os\.system\s*\(",        # Shell injection risk
    r"__import__\s*\(",        # Dynamic import (potential code injection)
    r"open\s*\([^)]*['\"][/]etc[/]passwd",  # Password file access
    r"open\s*\([^)]*['\"][/]etc[/]shadow",  # Shadow file access
    r"socket\.socket",         # Raw socket access (needs review)
    r"ctypes\.CDLL",           # Native library loading
    r"base64\.b64decode.*exec",  # Encoded execution
]

SUSPICIOUS_PACKAGES = [
    # Known malicious or problematic packages
    "evil-package",
    "malware-lib",
]

ALLOWED_PERMISSIONS = [
    "audio", "camera", "network:local", "network:internet",
    "files:read", "files:write", "location", "notifications",
    "background",
]

RESTRICTED_PERMISSIONS = [
    "phone", "sms", "contacts",  # Require explicit approval
]


# ============ Prompt Safety Check ============

def check_prompt_safety(prompt: str) -> SafetyResult:
    """
    Level 1: Check if the app prompt is safe.

    This runs before any code is generated.
    """
    issues = []
    warnings = []
    score = 1.0

    prompt_lower = prompt.lower()

    # Check for blocked keywords
    for keyword in BLOCKED_KEYWORDS:
        if keyword.lower() in prompt_lower:
            issues.append(f"Blocked keyword detected: '{keyword}'")
            score -= 0.3

    # Check for suspicious patterns
    for pattern in BLOCKED_PATTERNS:
        if re.search(pattern, prompt, re.IGNORECASE):
            issues.append(f"Suspicious pattern detected: {pattern}")
            score -= 0.2

    # Check for requests that might generate harmful apps
    harmful_requests = [
        (r"steal|exfiltrate|harvest", "Data theft request"),
        (r"spy on|monitor secretly|track without", "Surveillance request"),
        (r"fake|phishing|impersonate", "Deception request"),
        (r"ddos|denial of service|flood", "DoS request"),
        (r"bypass|crack|pirate", "Security bypass request"),
        (r"adult|explicit|nsfw", "Inappropriate content"),
        (r"gambling|casino|betting", "Gambling content"),
        (r"weapon|explosive|harm", "Dangerous content"),
    ]

    for pattern, description in harmful_requests:
        if re.search(pattern, prompt_lower):
            issues.append(f"Harmful request type: {description}")
            score -= 0.25

    # Check prompt length and quality
    if len(prompt) < 10:
        warnings.append("Prompt is very short - may not generate useful app")
        score -= 0.1

    if len(prompt) > 5000:
        warnings.append("Prompt is very long - may need simplification")
        score -= 0.05

    # Determine result
    score = max(0.0, min(1.0, score))

    if score < 0.5:
        level = SafetyLevel.REJECTED
        passed = False
    elif score < 0.8:
        level = SafetyLevel.NEEDS_REVIEW
        passed = False
    else:
        level = SafetyLevel.SAFE
        passed = True

    return SafetyResult(
        level=level,
        check_type=CheckType.PROMPT,
        score=score,
        passed=passed,
        issues=issues,
        warnings=warnings,
        notes=f"Prompt safety check: {len(issues)} issues, {len(warnings)} warnings"
    )


# ============ Generated Code Safety Check ============

def check_code_safety(code_path: str) -> SafetyResult:
    """
    Level 2: Check if generated code is safe.

    This runs after code generation but before packaging.
    """
    issues = []
    warnings = []
    score = 1.0

    path = Path(code_path)

    if not path.exists():
        return SafetyResult(
            level=SafetyLevel.REJECTED,
            check_type=CheckType.GENERATED,
            score=0.0,
            passed=False,
            issues=["Code path does not exist"],
            notes="Failed to check code - path not found"
        )

    # Collect all source files
    source_files = []
    for ext in ["*.qml", "*.py", "*.js", "*.rs", "*.sh"]:
        source_files.extend(path.rglob(ext))

    for source_file in source_files:
        try:
            content = source_file.read_text()
            file_issues, file_warnings, file_score = _check_source_file(
                content, source_file.suffix, source_file.name
            )
            issues.extend(file_issues)
            warnings.extend(file_warnings)
            score = min(score, file_score)
        except Exception as e:
            warnings.append(f"Could not read {source_file}: {e}")

    # Check for suspicious file types
    for suspicious in path.rglob("*.exe"):
        issues.append(f"Windows executable found: {suspicious}")
        score -= 0.5

    for suspicious in path.rglob("*.dll"):
        issues.append(f"Windows DLL found: {suspicious}")
        score -= 0.3

    # Determine result
    score = max(0.0, min(1.0, score))

    if score < 0.5:
        level = SafetyLevel.REJECTED
        passed = False
    elif score < 0.8:
        level = SafetyLevel.NEEDS_REVIEW
        passed = False
    else:
        level = SafetyLevel.SAFE
        passed = True

    return SafetyResult(
        level=level,
        check_type=CheckType.GENERATED,
        score=score,
        passed=passed,
        issues=issues,
        warnings=warnings,
        notes=f"Code safety check: {len(source_files)} files scanned"
    )


def _check_source_file(content: str, extension: str, filename: str) -> tuple:
    """Check a single source file for issues."""
    issues = []
    warnings = []
    score = 1.0

    # Check for blocked patterns
    for pattern in BLOCKED_PATTERNS:
        matches = re.findall(pattern, content, re.IGNORECASE)
        if matches:
            issues.append(f"{filename}: Dangerous pattern '{pattern}' found")
            score -= 0.2

    # Language-specific checks
    if extension == ".py":
        score = min(score, _check_python_code(content, filename, issues, warnings))
    elif extension == ".qml":
        score = min(score, _check_qml_code(content, filename, issues, warnings))
    elif extension == ".sh":
        score = min(score, _check_shell_code(content, filename, issues, warnings))
    elif extension == ".rs":
        score = min(score, _check_rust_code(content, filename, issues, warnings))

    return issues, warnings, score


def _check_python_code(content: str, filename: str, issues: list, warnings: list) -> float:
    """Python-specific safety checks."""
    score = 1.0

    # Check imports
    dangerous_imports = ["ctypes", "subprocess", "os.system", "pickle", "marshal"]
    for imp in dangerous_imports:
        if f"import {imp}" in content or f"from {imp}" in content:
            warnings.append(f"{filename}: Potentially dangerous import: {imp}")
            score -= 0.1

    # Check for network access
    if "requests" in content or "urllib" in content or "socket" in content:
        warnings.append(f"{filename}: Network access detected - verify API endpoints")

    return score


def _check_qml_code(content: str, filename: str, issues: list, warnings: list) -> float:
    """QML-specific safety checks."""
    score = 1.0

    # Check for external process execution
    if "Process {" in content or "Qt.createQmlObject" in content:
        warnings.append(f"{filename}: Dynamic code execution detected")
        score -= 0.15

    # Check for file access patterns
    file_patterns = [
        r'open\s*\([^)]*["\'][/]',
        r'XMLHttpRequest.*file://',
    ]
    for pattern in file_patterns:
        if re.search(pattern, content):
            warnings.append(f"{filename}: File access detected - verify paths")

    return score


def _check_shell_code(content: str, filename: str, issues: list, warnings: list) -> float:
    """Shell script safety checks."""
    score = 1.0

    # Very dangerous patterns in shell
    dangerous = [
        (r"rm\s+-rf\s+[/~]", "Dangerous recursive delete"),
        (r">\s*/dev/sd", "Writing to disk device"),
        (r"mkfs\.", "Formatting filesystem"),
        (r"dd\s+if=", "Low-level disk operations"),
    ]

    for pattern, desc in dangerous:
        if re.search(pattern, content):
            issues.append(f"{filename}: {desc}")
            score -= 0.3

    return score


def _check_rust_code(content: str, filename: str, issues: list, warnings: list) -> float:
    """Rust-specific safety checks."""
    score = 1.0

    # Check for unsafe blocks
    unsafe_count = content.count("unsafe {")
    if unsafe_count > 0:
        warnings.append(f"{filename}: {unsafe_count} unsafe blocks detected")
        score -= 0.05 * unsafe_count

    return score


# ============ Package Safety Check ============

def check_package_safety(package_path: str) -> SafetyResult:
    """
    Level 3: Final check on the complete package.

    This runs on the finished .flick package.
    """
    import zipfile

    issues = []
    warnings = []
    score = 1.0

    path = Path(package_path)

    if not path.exists() or not path.suffix == ".flick":
        return SafetyResult(
            level=SafetyLevel.REJECTED,
            check_type=CheckType.PACKAGE,
            score=0.0,
            passed=False,
            issues=["Invalid package path"],
            notes="Package not found or invalid format"
        )

    try:
        with zipfile.ZipFile(path, 'r') as zf:
            # Check manifest
            try:
                manifest_data = zf.read("manifest.json")
                manifest = json.loads(manifest_data)
                manifest_score = _check_manifest(manifest, issues, warnings)
                score = min(score, manifest_score)
            except (KeyError, json.JSONDecodeError) as e:
                issues.append(f"Invalid manifest: {e}")
                score -= 0.3

            # Check file sizes
            for info in zf.infolist():
                if info.file_size > 50 * 1024 * 1024:  # 50MB
                    warnings.append(f"Large file: {info.filename} ({info.file_size / 1024 / 1024:.1f}MB)")

                # Check for suspicious filenames
                if info.filename.startswith("/") or ".." in info.filename:
                    issues.append(f"Path traversal attempt: {info.filename}")
                    score -= 0.5

    except zipfile.BadZipFile:
        issues.append("Corrupted ZIP file")
        score = 0.0

    # Determine result
    score = max(0.0, min(1.0, score))

    if score < 0.5:
        level = SafetyLevel.REJECTED
        passed = False
    elif score < 0.8:
        level = SafetyLevel.NEEDS_REVIEW
        passed = False
    else:
        level = SafetyLevel.SAFE
        passed = True

    return SafetyResult(
        level=level,
        check_type=CheckType.PACKAGE,
        score=score,
        passed=passed,
        issues=issues,
        warnings=warnings,
        notes="Final package safety verification"
    )


def _check_manifest(manifest: dict, issues: list, warnings: list) -> float:
    """Check manifest for safety issues."""
    score = 1.0

    # Check permissions
    permissions = manifest.get("permissions", [])
    for perm in permissions:
        base_perm = perm.split(":")[0]
        if base_perm in RESTRICTED_PERMISSIONS:
            warnings.append(f"Restricted permission requested: {perm}")
            score -= 0.1
        elif base_perm not in ALLOWED_PERMISSIONS:
            issues.append(f"Unknown permission: {perm}")
            score -= 0.2

    # Check dependencies
    deps = manifest.get("dependencies", {})

    # Check APT packages
    apt_deps = deps.get("apt", [])
    for pkg in apt_deps:
        if pkg in SUSPICIOUS_PACKAGES:
            issues.append(f"Suspicious APT package: {pkg}")
            score -= 0.3

    # Check pip packages
    pip_config = deps.get("pip", {})
    pip_packages = pip_config.get("packages", [])
    for pkg in pip_packages:
        pkg_name = pkg.split("==")[0].split(">=")[0].split("<=")[0]
        if pkg_name in SUSPICIOUS_PACKAGES:
            issues.append(f"Suspicious pip package: {pkg_name}")
            score -= 0.3

    # Check build commands
    build = manifest.get("build", {})
    build_commands = build.get("commands", [])
    for cmd in build_commands:
        for pattern in BLOCKED_PATTERNS[:5]:  # Check dangerous command patterns
            if re.search(pattern, cmd):
                issues.append(f"Dangerous build command: {cmd[:50]}...")
                score -= 0.3

    return score


# ============ Claude Code Integration ============

def build_app_with_claude(prompt: str, output_dir: str, app_name: str) -> dict:
    """
    Build an app using Claude Code.

    This is a stub that can be connected to actual Claude Code CLI.
    """
    result = {
        "success": False,
        "output_path": None,
        "build_log": "",
        "error": None
    }

    # Safety check the prompt first
    safety_result = check_prompt_safety(prompt)
    if not safety_result.passed:
        result["error"] = f"Prompt rejected: {', '.join(safety_result.issues)}"
        result["build_log"] = f"Safety check failed with score {safety_result.score}"
        return result

    output_path = Path(output_dir) / app_name
    output_path.mkdir(parents=True, exist_ok=True)

    # System prompt for Claude Code
    system_prompt = f"""You are building a Flick app. Flick is a mobile shell for Linux phones.

REQUIREMENTS:
1. Create a QML-based app that follows Flick design patterns
2. Use dark theme (#0a0a0f background, accent color from Theme.accentColor)
3. Support textScale for accessibility
4. Include proper navigation and back button
5. All apps are AGPL-3.0 licensed
6. Do NOT include any harmful, malicious, or inappropriate content

OUTPUT:
- Create main.qml in the app/ directory
- Create manifest.json with proper metadata
- Import "../shared" for Theme and Haptic

The app should be: {prompt}
"""

    # Check if claude_code CLI is available
    claude_code_path = os.environ.get("CLAUDE_CODE_PATH", "claude")

    try:
        # This would actually call Claude Code CLI
        # For now, create a stub response
        result["build_log"] = f"""
[INFO] Building app: {app_name}
[INFO] Prompt safety score: {safety_result.score}
[INFO] Output directory: {output_path}
[STUB] Claude Code integration not yet connected
[STUB] Would run: {claude_code_path} --prompt "{prompt[:100]}..."
"""

        # Create a basic template as placeholder
        template_qml = f'''import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {{
    id: root
    visible: true
    visibility: Window.FullScreen
    width: 1080
    height: 2400
    title: "{app_name}"
    color: "#0a0a0f"

    property real textScale: 1.0
    property color accentColor: Theme.accentColor

    Component.onCompleted: loadConfig()

    function loadConfig() {{
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {{
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {{
                var config = JSON.parse(xhr.responseText)
                textScale = config.text_scale || 1.0
            }}
        }} catch (e) {{}}
    }}

    // TODO: Claude Code would generate the actual UI here
    // Based on prompt: {prompt[:200]}

    Text {{
        anchors.centerIn: parent
        text: "AI-Generated App Placeholder\\n\\nPrompt: {prompt[:50]}..."
        font.pixelSize: 24 * textScale
        color: "#ffffff"
        horizontalAlignment: Text.AlignHCenter
    }}

    Rectangle {{
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.bottomMargin: 120
        width: 72; height: 72; radius: 36
        color: backMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

        Text {{
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            color: "#ffffff"
        }}

        MouseArea {{
            id: backMouse
            anchors.fill: parent
            onClicked: Qt.quit()
        }}
    }}
}}
'''

        # Write template
        app_dir = output_path / "app"
        app_dir.mkdir(exist_ok=True)
        (app_dir / "main.qml").write_text(template_qml)

        # Create manifest
        manifest = {
            "format_version": 1,
            "id": f"com.flick.ai.{app_name.lower().replace(' ', '')}",
            "name": app_name,
            "version": "0.1.0",
            "description": f"AI-generated app: {prompt[:100]}",
            "author": {"name": "Flick AI", "email": "ai@flick.local"},
            "license": "AGPL-3.0",
            "categories": ["Utility"],
            "app": {"type": "qml", "entry": "main.qml"},
            "dependencies": {"apt": [], "pip": {"enabled": False}},
            "permissions": [],
            "ai_generated": {
                "is_ai_generated": True,
                "generator_version": f"ai_safety/{VERSION}",
                "original_prompt": prompt,
                "generation_date": datetime.now().isoformat()
            },
            "store": {
                "maturity_rating": "everyone",
                "price": "free",
                "testing_status": "wild_west"
            }
        }
        (output_path / "manifest.json").write_text(json.dumps(manifest, indent=2))

        result["success"] = True
        result["output_path"] = str(output_path)
        result["build_log"] += "[SUCCESS] Template app created (Claude Code integration pending)\n"

    except Exception as e:
        result["error"] = str(e)
        result["build_log"] += f"[ERROR] {e}\n"

    return result


# ============ CLI Interface ============

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Flick AI Safety Verification Pipeline"
    )
    parser.add_argument("--version", action="version", version=f"ai_safety {VERSION}")

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # check-prompt command
    prompt_parser = subparsers.add_parser("check-prompt", help="Check prompt safety")
    prompt_parser.add_argument("prompt", help="The prompt to check")

    # check-code command
    code_parser = subparsers.add_parser("check-code", help="Check generated code safety")
    code_parser.add_argument("path", help="Path to code directory")

    # check-package command
    pkg_parser = subparsers.add_parser("check-package", help="Check package safety")
    pkg_parser.add_argument("package", help="Path to .flick package")

    # build command
    build_parser = subparsers.add_parser("build", help="Build app with Claude Code")
    build_parser.add_argument("--prompt", "-p", required=True, help="App description prompt")
    build_parser.add_argument("--output", "-o", required=True, help="Output directory")
    build_parser.add_argument("--name", "-n", required=True, help="App name")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    if args.command == "check-prompt":
        result = check_prompt_safety(args.prompt)
    elif args.command == "check-code":
        result = check_code_safety(args.path)
    elif args.command == "check-package":
        result = check_package_safety(args.package)
    elif args.command == "build":
        build_result = build_app_with_claude(args.prompt, args.output, args.name)
        print(json.dumps(build_result, indent=2))
        return

    # Print result
    print(f"\n{'=' * 60}")
    print(f"Safety Check Result: {result.level.value.upper()}")
    print(f"{'=' * 60}")
    print(f"Check Type: {result.check_type.value}")
    print(f"Score: {result.score:.2f}")
    print(f"Passed: {result.passed}")

    if result.issues:
        print(f"\nIssues ({len(result.issues)}):")
        for issue in result.issues:
            print(f"  - {issue}")

    if result.warnings:
        print(f"\nWarnings ({len(result.warnings)}):")
        for warning in result.warnings:
            print(f"  ! {warning}")

    print(f"\nNotes: {result.notes}")
    print(f"Timestamp: {result.timestamp}")

    sys.exit(0 if result.passed else 1)


if __name__ == "__main__":
    main()
