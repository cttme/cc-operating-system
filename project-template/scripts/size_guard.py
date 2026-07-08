#!/usr/bin/env python
"""Size guard — invoked via a PostToolUse hook; watches file/folder sizes.

Per the hygiene principle (CLAUDE.md §Hygiene Principle):
  - CLAUDE.md     <= 150 lines (target), <= 250 warning threshold
  - lessons.md    <= 500 lines (rotation trigger)
  - decisions.md  <= 500 lines (rotation trigger)
  - audit.md      <= 1000 lines (rotation trigger)
  - tasks/ root   <= 12 files (archive trigger)
  - docs/<X>.md   <= 300 lines (split trigger)

Writes warnings to stderr, exits 0 (non-blocking; visibility only).
Output is visible to both the user and Claude.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Windows console UTF-8 fix -- cp1254 crashes on the emoji/box-drawing output below.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

ROOT = Path(__file__).parent.parent

# (path, soft_limit, hard_limit, message_template)
FILE_LIMITS = [
    ("CLAUDE.md", 150, 250, "{name} {lines} lines (target <{soft}). Move detail into docs/."),
    ("tasks/lessons.md", 500, 800, "{name} {lines} lines (>{soft}). Time to rotate to tasks/archive/."),
    ("tasks/decisions.md", 500, 800, "{name} {lines} lines (>{soft}). Time to rotate to tasks/refs/."),
    ("tasks/audit.md", 1000, 1500, "{name} {lines} lines (>{soft}). Move older audits to archive/."),
    ("tasks/precheck-stats.md", 200, 400, "{name} {lines} lines (>{soft}). Keep the weekly summary; trim older entries."),
]

DOCS_GLOB_LIMIT = 300  # docs/*.md
DOCS_HARD_LIMIT = 500

TASKS_ROOT_LIMIT = 12  # .md file count in tasks/ root

warnings: list[str] = []


def count_lines(path: Path) -> int:
    try:
        with path.open(encoding="utf-8") as f:
            return sum(1 for _ in f)
    except (OSError, UnicodeDecodeError):
        return 0


# ─── File-level checks ───
for rel_path, soft, hard, msg_template in FILE_LIMITS:
    p = ROOT / rel_path
    if not p.exists():
        continue
    lines = count_lines(p)
    if lines > hard:
        warnings.append(
            f"🚨 {msg_template.format(name=rel_path, lines=lines, soft=soft)} (HARD LIMIT {hard})"
        )
    elif lines > soft:
        warnings.append(f"⚠ {msg_template.format(name=rel_path, lines=lines, soft=soft)}")


# ─── docs/*.md checks ───
docs_dir = ROOT / "docs"
if docs_dir.exists():
    for md in docs_dir.glob("*.md"):
        lines = count_lines(md)
        if lines > DOCS_HARD_LIMIT:
            warnings.append(
                f"🚨 docs/{md.name} {lines} lines (>{DOCS_HARD_LIMIT} hard). Split into multiple files."
            )
        elif lines > DOCS_GLOB_LIMIT:
            warnings.append(
                f"⚠ docs/{md.name} {lines} lines (>{DOCS_GLOB_LIMIT} soft). Consider splitting."
            )


# ─── tasks/ root file count ───
tasks_dir = ROOT / "tasks"
if tasks_dir.exists():
    md_files = [f for f in tasks_dir.iterdir() if f.is_file() and f.suffix == ".md"]
    if len(md_files) > TASKS_ROOT_LIMIT:
        names = ", ".join(f.name for f in md_files[:5]) + ("..." if len(md_files) > 5 else "")
        warnings.append(
            f"⚠ {len(md_files)} .md files in tasks/ root (>{TASKS_ROOT_LIMIT}). "
            f"Move older ones to tasks/archive/ or tasks/refs/. ({names})"
        )


# ─── Output ───
if warnings:
    print("─" * 60, file=sys.stderr)
    print("📐 SIZE GUARD — hygiene warnings:", file=sys.stderr)
    for w in warnings:
        print(f"   {w}", file=sys.stderr)
    print("─" * 60, file=sys.stderr)

# Always exit 0 — for visibility, not blocking
sys.exit(0)
