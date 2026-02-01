#!/usr/bin/env python3
"""
Recite-then-Solve helper for Context Optimizer skill.
Reads core rules from CLAUDE.md hierarchy and outputs them for Claude to recite.
Based on Du et al. (EMNLP 2025) - recitation refreshes model attention on instructions.

Usage: python3 recite.py [--check-canary]
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
        if candidate.exists():
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

    # Look for safety-related lines
    safety_patterns = [
        r"(?i).*\bNEVER\b.*",
        r"(?i).*\bALWAYS\b.*",
        r"(?i).*\bsafety\b.*",
        r"(?i).*\brm\b.*\brmdir\b.*",
        r"(?i).*\btrash\b.*",
        r"(?i).*\bconfirm\b.*\bbefore\b.*",
        r"(?i).*\bGolden Rule\b.*",
    ]

    for line in content.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for pattern in safety_patterns:
            if re.match(pattern, line):
                rules.append(line.lstrip("- "))
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
        r".*///.*",
        r".*\[.*\].*每次.*",
        r"(?i).*emoji.*",
        r"(?i).*concise.*professional.*",
        r"(?i).*Elon.*",
        r".*先说.*",
    ]

    for line in content.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for pattern in style_patterns:
            if re.match(pattern, line):
                rules.append(line.lstrip("- "))
                break

    return rules


def check_canary():
    """Check if canary directory exists in workspace."""
    cwd = Path.cwd()
    # Look for canary directories
    for parent in [cwd] + list(cwd.parents):
        canary_dir = parent / "claude-context-canary"
        if canary_dir.exists():
            canary_files = list(canary_dir.glob("*"))
            return True, [str(f.name) for f in canary_files]
        if parent == Path.home() or parent == Path("/"):
            break
    return False, []


def main():
    check_canary_flag = "--check-canary" in sys.argv

    print("=" * 50)
    print("[RECITE-THEN-SOLVE] Context Health Recitation")
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

    # Deduplicate
    all_safety = list(dict.fromkeys(all_safety))
    all_style = list(dict.fromkeys(all_style))

    print()
    print("--- SAFETY RULES (recite these) ---")
    for i, rule in enumerate(all_safety, 1):
        print(f"  {i}. {rule}")

    print()
    print("--- STYLE RULES (recite these) ---")
    for i, rule in enumerate(all_style, 1):
        print(f"  {i}. {rule}")

    if check_canary_flag:
        print()
        print("--- CANARY CHECK ---")
        exists, files = check_canary()
        if exists:
            status = "ALIVE"
            print(f"  Canary: {status} (files: {', '.join(files)})")
        else:
            status = "NOT FOUND"
            print(f"  Canary: {status} (no canary directory in workspace)")

    print()
    print("--- ACTION ---")
    print("Claude: Please recite the above rules in your next response.")
    print("This refreshes attention on critical instructions (Du et al. 2025).")
    print("=" * 50)


if __name__ == "__main__":
    main()
