#!/usr/bin/env python
"""ask-local hint — PreToolUse hook for Read.

Soft hint when Claude is about to Read a large context-only file
(archive/audit/refs). Suggests routing through /ask-local for summary
instead of loading the full file into the model's context window.

Never blocks. Emits one-line hint to stderr; Read proceeds normally.

Trigger:
  - path matches one of: tasks/archive/, audit/reports/, audit/findings/, tasks/refs/
  - file length >= 300 lines

Çağrı: stdin'den tool_input JSON gelir (Claude Code hook protokolü).
"""
from __future__ import annotations

import json
import os
import sys

# Paths considered "context-only history" — reading them in full is usually
# wasted tokens; a summary is enough. Edit-intent reads are still allowed
# (hook is non-blocking), the operator just gets the nudge.
HINT_PREFIXES = (
    "tasks/archive/",
    "audit/reports/",
    "audit/findings/",
    "tasks/refs/",
)

MIN_LINES = 300


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    path = data.get("tool_input", {}).get("file_path", "") or ""
    if not path:
        return 0

    norm = path.replace("\\", "/")
    if not any(prefix in norm for prefix in HINT_PREFIXES):
        return 0

    # Use normalized path for filesystem ops too — Windows Python accepts
    # forward slashes natively, but Git Bash's Python treats literal
    # backslashes as part of the filename and isfile() returns False.
    if not os.path.isfile(norm):
        return 0

    try:
        with open(norm, encoding="utf-8", errors="ignore") as f:
            line_count = sum(1 for _ in f)
    except Exception:
        return 0

    if line_count < MIN_LINES:
        return 0

    name = os.path.basename(norm)
    hint = (
        f"[ask-local hint] {name} is {line_count} lines under a context-only path "
        f"({', '.join(HINT_PREFIXES)}). Before loading the whole file, consider "
        f'routing it through /ask-local with -Intent "summarize {name}" — '
        f"the summary usually carries enough context for archive/audit/refs material."
    )
    # JSON response on stdout — Claude Code surfaces additionalContext to the
    # model's tool-use transcript without blocking the Read. exit 0 = approve.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": hint,
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
