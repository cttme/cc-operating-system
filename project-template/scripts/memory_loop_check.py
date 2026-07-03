#!/usr/bin/env python
"""memory_loop_check — Stop hook.

Reminds (never auto-acts) when a session did real work but never closed the
memory loop with /session-end or /retro. Reads the existing R4 trajectory
log (tasks/audit.md, written by scripts/trajectory_log.py) to decide — it
adds zero autonomy, only a nudge.

CLI:
  python scripts/memory_loop_check.py

Session scoping (O4, os-remap SF3): as a Stop hook this used to resolve
"current session" as rows[-1]'s sess — the LAST writer across ALL
concurrent sessions in audit.md, which under concurrency is frequently a
DIFFERENT session than the one whose Stop event fired this hook. main() now
reads the hook JSON payload from stdin (Claude Code supplies `session_id`
on every Stop event) and passes it to loop_status(session=...) to scope the
replay correctly. No stdin payload / unparseable / no session_id -> falls
back to the old rows[-1] behavior (manual CLI runs must not break).

The REMINDER print is latched once-per-session via scripts/hook_latch.py:
Stop fires per assistant TURN, not per session, so without latching the
same reminder would repeat on every turn of a long-running open session.
did_work/closed/remind are unaffected — only the repeated PRINT is gated.

Never raises on the hook path — any internal error is noted to the same
sidecar log trajectory_log.py / trajectory_review.py use, and the process
still exits 0.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# scripts/ is a package (scripts/__init__.py), but this file is invoked as
# `python scripts/memory_loop_check.py` — a bare script run, not a module
# import — so sys.path[0] is scripts/, not the repo root, and
# `from scripts.X import Y` would fail. Add the repo root explicitly before
# importing (mirrors scripts/trajectory_log.py).
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from scripts.trajectory_review import _audit_path, _parse_lines, _session_short  # noqa: E402

try:
    from scripts.trajectory_review import _log_error
except Exception:  # pragma: no cover - defensive: import must never break the hook
    _log_error = None  # type: ignore[assignment]

try:
    from scripts.hook_latch import fired_before
except Exception:  # pragma: no cover - defensive: import must never break the hook
    fired_before = None  # type: ignore[assignment]

LATCH_KEY = "memory_loop_check-warn"

REMINDER = (
    "[memory-loop] Session did work but no /session-end or /retro recorded — "
    "run /session-end to write the handoff Next-Task-Brief + consolidate-memory "
    "before /clear (else the next session starts cold)."
)


# === Section: Core API ===


def loop_status(audit_path: str | None = None, session: str | None = None) -> dict:
    """Replay audit.md and decide whether to remind for the current session.

    `session` (already-shortened 8-char form, matching audit.md's sess=
    field) scopes the replay to that session when given — pass the raw
    hook payload session_id through trajectory_review._session_short()
    first. None -> falls back to rows[-1]'s sess (pre-existing behavior).

    Returns:
        {session, did_work: bool, closed: bool, remind: bool}
    """
    rows = _parse_lines(_audit_path(audit_path))

    if not rows:
        return {"session": None, "did_work": False, "closed": False, "remind": False}

    current_session = session or rows[-1]["sess"]
    session_rows = [r for r in rows if r["sess"] == current_session]

    did_work = any(r["stage"] in ("execute", "commit") for r in session_rows)
    closed = any(r["stage"] == "reflect" for r in session_rows)
    remind = did_work and not closed

    return {
        "session": current_session,
        "did_work": did_work,
        "closed": closed,
        "remind": remind,
    }


# === Section: CLI ===


def _read_hook_payload() -> dict:
    """Best-effort stdin JSON read. Never raises.

    Returns {} on empty/unparseable stdin or when stdin isn't piped (e.g. a
    manual `python scripts/memory_loop_check.py` run from an interactive
    terminal) — caller falls back to rows[-1]-based session resolution.
    """
    try:
        if sys.stdin.isatty():
            return {}
        raw = sys.stdin.read()
        if not raw or not raw.strip():
            return {}
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def main() -> int:
    try:
        payload = _read_hook_payload()
        raw_session_id = payload.get("session_id") or payload.get("sessionId")
        session_id = _session_short(raw_session_id)

        status = loop_status(session=session_id)
        if status["remind"]:
            # Latch: without this, the same reminder reprints on every
            # assistant turn's Stop event for the whole session. No
            # session_id / import failure -> print every time (fail-open).
            if fired_before is not None and session_id and fired_before(session_id, LATCH_KEY):
                return 0
            print(REMINDER)
        return 0
    except Exception as exc:  # no-silent-failure: note it, but a Stop hook must never break
        if _log_error is not None:
            try:
                _log_error(f"memory_loop_check error: {exc!r}")
            except Exception:
                pass
        return 0


if __name__ == "__main__":
    sys.exit(main())
