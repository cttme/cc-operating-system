#!/usr/bin/env python
"""CLAUDE.md / docs reference check — PostToolUse hook.

After CLAUDE.md or docs/*.md is edited, resolve file references within
the content. Broken references produce a stderr warning (non-blocking).

For false positives (filename present but the path is wrong), a fallback
find-by-name search is used.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

# Search root — two levels above the script's location (worktree root)
SEARCH_ROOT = Path(__file__).parent.parent

# Path parts to exclude from the search
EXCLUDE_DIRS = {"node_modules", ".next", "archive", ".pytest_cache", "__pycache__", ".git", ".ruff_cache", ".mypy_cache"}


def find_file_anywhere(filename: str) -> bool:
    """Search the repo for a file with the same name (pathlib instead of subprocess)."""
    for path in SEARCH_ROOT.rglob(filename):
        # Skip excluded dirs and backup folders
        if any(part in EXCLUDE_DIRS or part.startswith(".bak-") or part.endswith(".bak-2026-05-18") for part in path.parts):
            continue
        return True
    return False


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    path = data.get("tool_input", {}).get("file_path", "") or data.get("tool_input", {}).get("path", "")
    if not path:
        return 0

    # Only run when CLAUDE.md or docs/<X>.md is edited
    norm_path = path.replace("\\", "/")
    basename = os.path.basename(path)
    if basename != "CLAUDE.md" and not (norm_path.startswith("docs/") or "/docs/" in norm_path) and not path.endswith(".md"):
        return 0
    if not (basename == "CLAUDE.md" or "/docs/" in norm_path or norm_path.startswith("docs/")):
        return 0

    if not os.path.exists(path):
        return 0

    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return 0

    # Capture references in `path/file.ext` format
    refs = set(re.findall(r"`([\w/.-]+\.(?:md|py|json|yml|yaml|toml))`", text))

    missing = []
    for ref in refs:
        # Skip absolute paths or URLs
        if ref.startswith(("http", "/", "~")):
            continue
        # If the direct path exists, it's fine
        if os.path.exists(ref):
            continue
        # Fallback: a file with the same name elsewhere?
        if not find_file_anywhere(os.path.basename(ref)):
            missing.append(ref)

    if missing:
        print(f"REF CHECK [{basename}] broken references:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
