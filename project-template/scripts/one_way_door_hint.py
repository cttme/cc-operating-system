#!/usr/bin/env python
"""one-way-door hint — PreToolUse hook for Edit/Write.

Soft nudge when an edit touches a one-way-door path (schema migration, API
contract, published URLs / data policy) — the hard-to-undo changes where the
reversibility axis (change-protocol.md) says rigor is earned. Surfaces a
"⚠ one-way door — /spec + /council?" reminder so the discipline fires on the edit
instead of relying on memory.

Never blocks. Advisory only — additionalContext on stdout, exit 0. Tightly scoped
on purpose: a PreToolUse(Edit) hook fires constantly, so only high-signal one-way
paths trigger it — a noisy nudge becomes wallpaper.

Customize ONE_WAY_PATTERNS per project (add your schema/contract/published-URL
paths). Çağrı: stdin'den tool_input JSON gelir (PreToolUse protokolü).
"""
from __future__ import annotations

import json
import re
import sys

# === Section: One-way-door paths ===
# (regex on normalized path, short reason). Keep SMALL and high-signal — every
# false positive trains the operator to ignore the nudge.
ONE_WAY_PATTERNS = (
    (r"(alembic|migrations)/.*\.py$", "DB schema / data migration"),
    (r"(schema|schemas)\.py$", "API / data contract"),
    (r"/schemas/.*\.py$", "API / data contract"),
    (r"\bPOLICY\.md$", "data policy (legal/compliance)"),
    (r"sitemap", "published URLs (SEO-indexed)"),
    (r"openapi|\.proto$", "public API contract"),
)


def _match(path: str) -> str | None:
    norm = path.replace("\\", "/")
    for pat, reason in ONE_WAY_PATTERNS:
        if re.search(pat, norm):
            return reason
    return None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    ti = data.get("tool_input", {})
    path = ti.get("file_path", "") or ti.get("path", "")
    if not path:
        return 0

    reason = _match(path)
    if not reason:
        return 0

    hint = (
        f"⚠ One-way door — this edit touches {reason}, which is hard/expensive to undo "
        f"once shipped. Per the reversibility axis (change-protocol.md), one-way doors "
        f"earn rigor: consider `/spec` and `/council` before committing, plus a "
        f"`decisions.md` entry with `Reversibility: one-way`. Two-way edits ignore this. "
        f"(Advisory — never blocks.)"
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": hint,
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
