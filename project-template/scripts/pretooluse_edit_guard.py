#!/usr/bin/env python
"""PreToolUse(Edit|Write) guard — single stdin consumer.

Composes the two PreToolUse Edit|Write concerns into ONE hook so neither can
be starved of stdin by the other:

  1. **Secret-path block** (security gate): editing .env / secrets/ /
     proxies.json is refused with exit 2.
  2. **One-way-door advisory** (reuses scripts/one_way_door_hint policy):
     editing a hard-to-undo path surfaces a /spec + /council nudge.

Why this exists: the two checks used to be two separate hooks in the same
matcher array. The harness may feed the matcher's hooks from a single stdin
stream, so the 2nd hook (the door advisory) received empty stdin and silently
no-opped — its enforcement vanished (docs/WORKFLOW_OS.md). Worse, had the
ordering ever flipped, the SECRET BLOCKER would get empty stdin, crash, and
fail OPEN. A single consumer removes the ordering dependency for good.

Exit codes (Claude Code PreToolUse protocol):
  2 → block the tool call (secret path, OR stdin/parse failure).
  0 → allow; may carry an advisory via stdout JSON additionalContext.

stdin read/JSON-parse failure (including empty stdin) → exit 2 (fail CLOSED).
This is the one hard security gate in the hook layer — a payload we can't even
parse must never silently disable it. Once the payload parses successfully,
the two halves below split again: the secret-path block stays a hard gate
(exit 2), and the one-way-door advisory stays fail-open (its own errors must
never block the tool call).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# scripts/ is a package; this runs as a bare script (sys.path[0] == scripts/),
# but pytest imports it as scripts.pretooluse_edit_guard. Add repo root so the
# `from scripts.one_way_door_hint import ...` works in both contexts.
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

try:
    from scripts.one_way_door_hint import _match as _one_way_match
    from scripts.one_way_door_hint import hint_text as _hint_text
except Exception:  # pragma: no cover - defensive: never break the hook on import
    _one_way_match = None  # type: ignore[assignment]
    _hint_text = None  # type: ignore[assignment]

# Paths whose edit must be blocked outright (mirror of the old inline check).
_BLOCKED_PATTERNS = (r"\.env\b", r"secrets/", r"proxies\.json")

_SETTINGS_PATH = _REPO_ROOT / ".claude" / "settings.json"


def _blocked_reason(path: str) -> list[str]:
    norm = path.replace("\\", "/")
    return [p for p in _BLOCKED_PATTERNS if re.search(p, norm)]


def _hook_body_advisory(path: str, settings_path: Path = _SETTINGS_PATH) -> str | None:
    """SEC-P6: editing a hook body wired in .claude/settings.json is high-risk —
    it executes silently on every matching tool call (change-protocol.md table).
    Checked dynamically against settings.json so the advisory only fires for
    genuinely wired scripts (a static scripts/*.py pattern would nag on every
    script edit and train the operator to ignore it). Advisory half — fail-open."""
    norm = path.replace("\\", "/")
    m = re.search(r"scripts/([A-Za-z0-9_]+\.py)$", norm)
    if not m:
        return None
    try:
        wired = settings_path.read_text(encoding="utf-8")
    except Exception:
        return None  # advisory must never block on its own errors
    if f"scripts/{m.group(1)}" not in wired:
        return None
    return (
        f"⚠ High-risk edit — scripts/{m.group(1)} is a hook body wired in "
        f".claude/settings.json: it runs silently on every matching tool call, and "
        f"a bad edit is silent breakage (or a weakened security gate, if it's the "
        f"secret-gate script). change-protocol.md applies: backup + /verify. "
        f"(Advisory — never blocks.)"
    )


def main() -> int:
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            raise ValueError("empty stdin")
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError("payload is not a JSON object")
    except Exception as exc:
        print(f"edit guard could not parse hook input — retry ({exc})", file=sys.stderr)
        return 2

    ti = data.get("tool_input", {}) or {}
    path = ti.get("file_path", "") or ti.get("path", "")
    if not path:
        return 0

    # 1. Secret-path block — hard gate, exit 2.
    matched = _blocked_reason(path)
    if matched:
        print(f"BLOCKED: {path} matches {matched}", file=sys.stderr)
        return 2

    # 2. Advisories — soft nudges, exit 0 with additionalContext (combined if
    #    more than one fires; a second JSON document on stdout would be ignored).
    hints: list[str] = []
    reason = _one_way_match(path) if _one_way_match is not None else None
    if reason and _hint_text is not None:
        hints.append(_hint_text(reason))
    hook_body_hint = _hook_body_advisory(path)
    if hook_body_hint:
        hints.append(hook_body_hint)
    if hints:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "additionalContext": "\n\n".join(hints),
                    }
                }
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
