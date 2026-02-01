#!/usr/bin/env python3
"""
Context health check helper for Context Optimizer skill.
Reads core rules from CLAUDE.md hierarchy and checks canary health.

Usage:
    python3 recite.py                 # Extract and display rules
    python3 recite.py --check-canary  # Also check canary health
    python3 recite.py --help          # Show help
"""

import os
import sys
import json
import re
from pathlib import Path


def find_claude_mds():
    """Find all CLAUDE.md files from home dir and workspace."""
    found = []

    # Global user CLAUDE.md
    home_claude = Path.home() / ".claude" / "CLAUDE.md"
    if home_claude.exists():
        found.append(("global", str(home_claude)))

    # Walk up from cwd to find project CLAUDE.md files
    cwd = Path.cwd()
    for parent in [cwd] + list(cwd.parents):
        candidate = parent / "CLAUDE.md"
        if candidate.exists() and str(candidate) != str(home_claude):
            found.append(("project", str(candidate)))
        # Stop at home or root
        if parent == Path.home() or parent == Path("/"):
            break

    return found


def extract_safety_rules(filepath):
    """Extract safety-related rules from a CLAUDE.md file."""
    try:
        content = Path(filepath).read_text(encoding="utf-8")
    except Exception:
        return []

    rules = []

    # Targeted patterns for actual safety rules (not arbitrary mentions)
    safety_patterns = [
        r"^[-*]\s+NEVER\b",                  # "- NEVER use rm..."
        r"^[-*]\s+ALWAYS\b",                 # "- ALWAYS move files..."
        r"^[-*]\s+.*\bconfirm\w*\s+before\b",  # "- confirm before..."
        r"^NEVER\b",                          # "NEVER use rm..." (no bullet)
        r"^ALWAYS\b",                         # "ALWAYS move..." (no bullet)
        r".*Golden Rule.*",                   # Special marker
        r"^[-*]\s+.*\btrash\b.*\bmv\b",      # "- move to trash"
        r"^[-*]\s+.*\bmv\b.*\btrash\b",      # "- mv file to trash"
    ]

    for line in content.split("\n"):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("|"):
            continue
        for pattern in safety_patterns:
            if re.match(pattern, line, re.IGNORECASE):
                rules.append(line.lstrip("- *"))
                break

    return rules


def extract_style_rules(filepath):
    """Extract communication style rules."""
    try:
        content = Path(filepath).read_text(encoding="utf-8")
    except Exception:
        return []

    rules = []
    style_patterns = [
        r"^[-*]\s+.*每次回复.*先说",             # "每次回复先说：[•]"
        r"^Every response must start with",     # Canary instruction
        r"^[-*]\s+.*Every response.*start with",  # Bulleted canary
        r"^[-*]\s+.*NO emoji",                  # "NO emojis except..."
        r"^[-*]\s+.*Concise.*professional",     # "Concise, professional..."
        r"^[-*]\s+Communication:",              # "Communication: ..."
    ]

    for line in content.split("\n"):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("|"):
            continue
        for pattern in style_patterns:
            if re.match(pattern, line, re.IGNORECASE):
                rules.append(line.lstrip("- *"))
                break

    return rules


def check_canary():
    """Check actual canary health via state file and installed scripts."""
    result = {
        "installed": False,
        "hook_installed": False,
        "daemon_installed": False,
        "state": None,
    }

    plugins_dir = Path.home() / ".claude" / "plugins"
    state_file = Path.home() / ".claude" / "canary-state.json"

    # Check installed components
    result["hook_installed"] = (plugins_dir / "canary-check-v2.sh").exists()
    result["daemon_installed"] = (plugins_dir / "canary-daemon-global.sh").exists()
    result["installed"] = result["hook_installed"] or result["daemon_installed"]

    # Check state
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
            result["state"] = state
        except Exception:
            pass

    return result


def main():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        sys.exit(0)

    check_canary_flag = "--check-canary" in sys.argv

    print("=" * 50)
    print("[CONTEXT CHECK] Rule Verification")
    print("=" * 50)
    print()

    # Find and parse CLAUDE.md files
    claude_files = find_claude_mds()

    all_safety = []
    all_style = []

    for level, filepath in claude_files:
        safety = extract_safety_rules(filepath)
        style = extract_style_rules(filepath)
        all_safety.extend(safety)
        all_style.extend(style)
        print(f"[{level}] {filepath} -> {len(safety)} safety, {len(style)} style rules")

    # Deduplicate preserving order
    all_safety = list(dict.fromkeys(all_safety))
    all_style = list(dict.fromkeys(all_style))

    print()
    print("--- SAFETY RULES ---")
    for i, rule in enumerate(all_safety, 1):
        print(f"  {i}. {rule}")

    print()
    print("--- STYLE RULES ---")
    for i, rule in enumerate(all_style, 1):
        print(f"  {i}. {rule}")

    if check_canary_flag:
        print()
        print("--- CANARY CHECK ---")
        info = check_canary()
        if info["installed"]:
            components = []
            if info["hook_installed"]:
                components.append("hook")
            if info["daemon_installed"]:
                components.append("daemon")
            print(f"  Installed: {', '.join(components)}")

            if info["state"]:
                fc = info["state"].get("failure_count", 0)
                status = "HEALTHY" if fc == 0 else f"DEGRADED ({fc} failures)"
                print(f"  Status: {status}")
                if fc > 0:
                    lf = info["state"].get("last_failure", "unknown")
                    print(f"  Last failure: {lf}")
            else:
                print("  Status: NO DATA (no checks recorded yet)")
        else:
            print("  Canary: NOT INSTALLED")
            print("  Install: bash install.sh --canary")

    print()
    print("=" * 50)


if __name__ == "__main__":
    main()
