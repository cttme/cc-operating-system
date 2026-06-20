#!/usr/bin/env python
"""model-routing hint — UserPromptSubmit hook.

Nudge toward a cheaper model for mechanical work. If cost telemetry shows the
session spending most of its tokens on the top-tier model, much of that is often
bookkeeping (skill runs, renames, sweeps, dependency bumps) that a mid-tier model
handles just as well. This hook scans the incoming prompt and, when it looks
mechanical, surfaces a one-line advisory.

Never blocks. Advisory only — emits additionalContext on stdout, exit 0.
The operator (or model) decides; reasoning-heavy work that slips through is
harmless because the nudge is a question, not a gate.

Customize MECHANICAL_SKILLS / OPUS_OVERRIDE_PATTERNS per project — the defaults
below are generic. Çağrı: stdin'den {"prompt": "..."} gelir (UserPromptSubmit).
"""
from __future__ import annotations

import json
import re
import sys

# === Section: Mechanical signals ===

# Mechanical slash-commands — bookkeeping / orchestration skills. Add project
# skills here; leave out skills that carry real reasoning load (/plan, /audit-*).
MECHANICAL_SKILLS = (
    "/onboard",
    "/session-end",
    "/verify",
    "/commit",
)

# Mechanical keyword patterns — bulk edits, moves, and dependency hygiene.
MECHANICAL_PATTERNS = (
    r"\brename\b",
    r"\bsweep\b",
    r"\bmove (the |these |all )?files?\b",
    r"\bbatch\b",
    r"\bdependabot\b",
    r"\bbump (the )?(dep|deps|dependency|dependencies|version)\b",
    r"\bfind[- ]and[- ]replace\b",
    r"\bs/.+/.+/\b",  # sed-style substitution
    r"\breformat\b",
    r"\bregenerate (the )?index\b",
)

# Opt-out guard: stay silent when the prompt signals reasoning-heavy / sensitive
# work even if a mechanical keyword also appears. Customize per project (add
# domain-critical module names, security-sensitive paths, etc.).
OPUS_OVERRIDE_PATTERNS = (
    r"\bmigration\b",
    r"\bauth\b",
    r"\bsecurity\b",
    r"\barchitect",
    r"\bdesign\b",
    r"\bdebug\b",
    r"\broot[- ]cause\b",
    r"\balgorithm\b",
)


def _matches(prompt: str) -> str | None:
    """Return a short reason string if the prompt looks mechanical, else None."""
    low = prompt.casefold()

    for pat in OPUS_OVERRIDE_PATTERNS:
        if re.search(pat, low):
            return None

    for skill in MECHANICAL_SKILLS:
        if skill in low:
            return f"`{skill}` is a bookkeeping skill"

    for pat in MECHANICAL_PATTERNS:
        m = re.search(pat, low)
        if m:
            return f"mechanical pattern ({m.group(0).strip()})"

    return None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    prompt = data.get("prompt", "") or ""
    if not prompt.strip():
        return 0

    reason = _matches(prompt)
    if not reason:
        return 0

    hint = (
        f"⚠ Cheaper-model task? This looks mechanical — {reason}. "
        f"Mechanical work (skills, renames, sweeps, dep bumps) usually runs well on "
        f"a mid-tier model at a fraction of the cost. If this needs no algorithmic / "
        f"architectural / security reasoning, consider switching model. "
        f"(Advisory only — proceed if the top-tier model is warranted.)"
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": hint,
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
