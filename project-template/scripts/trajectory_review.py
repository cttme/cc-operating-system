#!/usr/bin/env python
"""trajectory_review — replay tasks/audit.md vs the thinking-pipeline stages.

Parses the lines appended by scripts/trajectory_log.py and reports which
canonical pipeline stages (.claude/rules/thinking-pipeline.md) were
observed for a session, flagging the "core" stages that are easy to skip
on non-trivial work: frame, plan, decide, verify.

CLI:
  python scripts/trajectory_review.py            # human summary (verbose)
  python scripts/trajectory_review.py --hook     # one terse line, for a Stop hook

Session scoping (O4, os-remap SF3): as a Stop hook, this script used to
resolve "current session" as rows[-1]'s sess — the audit.md row written by
the LAST tool call across ALL concurrent sessions, which under concurrency
is frequently a DIFFERENT session than the one whose Stop event fired this
hook. `--hook` mode now reads the hook JSON payload from stdin (Claude Code
supplies `session_id` on every Stop event) and scopes the replay to that
session. Manual/non-hook CLI runs (no stdin payload, or unparseable stdin)
fall back to the old rows[-1] behavior — this must not change for `python
scripts/trajectory_review.py` run by hand with no stdin.

The `--hook` summary line is also latched once-per-session via
scripts/hook_latch.py: repeat Stop events within the same session (Stop
fires per assistant TURN, not per session) suppress the repeated print,
so the same status line doesn't scroll past 10+ times in one session. The
underlying review() computation and exit code are unaffected — only the
repeated PRINT is gated.

Never raises on the hook path — any internal error is noted to the same
sidecar log trajectory_log.py uses, and the process still exits 0.

=== Schema versioning (A-P4) ===

The row field list (ts/sess/model/stage/tool/args) is documented ONCE, in
scripts/trajectory_log.py (the writer) — see its module docstring "Schema"
section. This reader does not keep its own copy of the field list; it only
asserts the SCHEMA_VERSION marker trajectory_log.py writes matches what this
reader supports (SUPPORTED_SCHEMA_VERSION below).

- Marker missing entirely (predates versioning) → treated as legacy v1, but
  `check_schema()` returns a one-line notice — NOT a hard failure (a hard
  fail on "no marker yet" would break every run until the writer's next
  append adds one).
- Marker present but a DIFFERENT version than SUPPORTED_SCHEMA_VERSION →
  hard failure: `check_schema()` signals a mismatch and the CLI exits
  nonzero, naming found vs. supported.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

try:
    from scripts.hook_latch import fired_before
except Exception:  # pragma: no cover - defensive: import must never break the hook
    fired_before = None  # type: ignore[assignment]

# Schema marker helpers — SSOT is trajectory_log.py (the writer); this reader
# does not keep its own copy of the field list, only the version check.
# Imported defensively (same pattern as hook_latch above): an import failure
# must never break a hook, so fall back to a local, minimally-equivalent
# regex/version rather than raising.
try:
    from scripts.trajectory_log import SCHEMA_MARKER_RE
except Exception:  # pragma: no cover - defensive: import must never break the hook
    SCHEMA_MARKER_RE = re.compile(r"^<!--\s*schema=(?P<version>\S+)\s+fields=\S+\s*-->\s*$")

# The schema version THIS reader knows how to interpret. Deliberately a
# reader-owned literal, NOT imported from the writer: if it aliased the
# writer's SCHEMA_VERSION, bumping the writer to v2 would auto-bump this
# claim while the reader's parsing code stayed v1-shaped — the version gate
# would pass exactly when it must fail. A writer bump and a reader bump are
# two independent, explicit edits.
SUPPORTED_SCHEMA_VERSION = "v1"

AUDIT_PATH_ENV = "TRAJECTORY_AUDIT_PATH"
DEFAULT_AUDIT_PATH = "tasks/audit.md"

# Env-overridable (same pattern as TRAJECTORY_AUDIT_PATH) so tests never
# append to the real sidecar log — see posttooluse_qa_guard.py's identical
# TRAJECTORY_ERRORS_PATH convention.
ERROR_LOG_PATH = os.environ.get("TRAJECTORY_ERRORS_PATH") or "tasks/.trajectory_errors.log"
LATCH_KEY = "trajectory_review-hook"

# Canonical pipeline stages (.claude/rules/thinking-pipeline.md).
CANONICAL_STAGES = ["onboard", "frame", "plan", "decide", "execute", "verify", "commit", "reflect"]
# Core stages worth flagging when missing — skippable-but-shouldn't-be for
# non-trivial / one-way work. execute/commit/onboard/reflect are informational only.
CORE_STAGES = ["frame", "plan", "decide", "verify"]

LINE_RE = re.compile(
    r"^\[(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] "
    r"sess=(?P<sess>\S+) model=(?P<model>\S+) stage=(?P<stage>\S*) tool=(?P<tool>\S+)"
    r"(?: (?P<args>.*))?$"
)


def _audit_path(audit_path: str | None = None) -> Path:
    return Path(audit_path or os.environ.get(AUDIT_PATH_ENV, DEFAULT_AUDIT_PATH))


def _session_short(session_id: str | None) -> str | None:
    """Match trajectory_log.py's _session_short(): audit.md rows store only
    the first 8 alnum chars of session_id, not the full UUID a hook payload
    carries — a raw payload session_id would never match any row without
    this normalization."""
    if not session_id:
        return None
    alnum = re.sub(r"[^A-Za-z0-9]", "", str(session_id))
    return alnum[:8] if alnum else None


def _log_error(message: str) -> None:
    """Best-effort sidecar log for internal errors. Never raises."""
    try:
        path = Path(ERROR_LOG_PATH)
        path.parent.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with path.open("a", encoding="utf-8") as fh:
            fh.write(f"[{ts}] {message}\n")
    except Exception:
        pass


# === Section: Schema check ===


def _find_schema_marker(audit_path: Path) -> str | None:
    """Scan the file's first few lines for a schema marker. None if absent.

    Mirrors trajectory_log._find_schema_marker exactly (bounded head-read,
    same regex) — duplicated rather than imported across the two modules'
    private helpers to avoid a fragile cross-import of an underscore-name;
    the public contract (SCHEMA_MARKER_RE) IS shared via the import above.
    """
    try:
        if not audit_path.is_file():
            return None
        with audit_path.open(encoding="utf-8", errors="replace") as fh:
            for i, raw in enumerate(fh):
                if i >= 15:
                    break
                m = SCHEMA_MARKER_RE.match(raw.strip())
                if m:
                    return m.group("version")
    except Exception:
        return None
    return None


def check_schema(audit_path: Path) -> dict:
    """Assert the audit.md schema marker matches SUPPORTED_SCHEMA_VERSION.

    Returns {"ok": bool, "found": str | None, "notice": str | None}:
      - marker missing            -> ok=True,  notice="legacy (no schema marker...)"
      - marker == supported       -> ok=True,  notice=None
      - marker present, mismatch  -> ok=False, notice="schema mismatch: found=<x> supported=<y>"

    Callers: a missing marker is NOT a hard failure (the real audit.md
    predates versioning until the writer's first post-change append adds the
    marker) — only a VERSION MISMATCH is. This function never raises.
    """
    try:
        found = _find_schema_marker(audit_path)
    except Exception:
        found = None
    if found is None:
        return {
            "ok": True,
            "found": None,
            "notice": (
                f"[trajectory schema] no schema marker found in {audit_path} — "
                f"treating as legacy {SUPPORTED_SCHEMA_VERSION} (predates schema versioning)"
            ),
        }
    if found != SUPPORTED_SCHEMA_VERSION:
        return {
            "ok": False,
            "found": found,
            "notice": (
                f"[trajectory schema] MISMATCH: {audit_path} marker=schema={found} "
                f"but this reader supports schema={SUPPORTED_SCHEMA_VERSION}"
            ),
        }
    return {"ok": True, "found": found, "notice": None}


def _parse_lines(audit_path: Path) -> list[dict]:
    if not audit_path.is_file():
        return []
    rows: list[dict] = []
    with audit_path.open(encoding="utf-8") as fh:
        for raw in fh:
            m = LINE_RE.match(raw)
            if not m:
                continue  # ignore header / non-matching lines
            rows.append(m.groupdict())
    return rows


# === Section: Core API ===


def review(audit_path: str | None = None, session: str | None = None) -> dict:
    """Replay audit.md and return stage-coverage info for one session.

    Returns:
        {session, observed_stages: set, missing_stages: list, tool_count: int, models: set}
    """
    path = _audit_path(audit_path)
    rows = _parse_lines(path)

    if not rows:
        return {
            "session": session,
            "observed_stages": set(),
            "missing_stages": [],
            "tool_count": 0,
            "models": set(),
        }

    target_session = session or rows[-1]["sess"]
    session_rows = [r for r in rows if r["sess"] == target_session]

    observed_stages = {r["stage"] for r in session_rows if r["stage"]}
    missing_stages = [s for s in CORE_STAGES if s not in observed_stages]
    models = {r["model"] for r in session_rows if r["model"]}

    return {
        "session": target_session,
        "observed_stages": observed_stages,
        "missing_stages": missing_stages,
        "tool_count": len(session_rows),
        "models": models,
    }


# === Section: CLI ===


def _print_verbose(result: dict) -> None:
    session = result["session"]
    if session is None:
        print("(no trajectory entries found — audit log is empty)")
        return
    print(f"session: {session}")
    print(f"tool_count: {result['tool_count']}")
    observed = ", ".join(sorted(result["observed_stages"])) or "(none)"
    print(f"observed stages: {observed}")
    if result["missing_stages"]:
        missing = ", ".join(result["missing_stages"])
        print(
            f"⚠ Potentially skipped stages: {missing} "
            f"(advisory — fine for trivial/two-way work; a gap on a one-way door is a real miss)"
        )
    else:
        print(f"✓ All core pipeline stages present for session {session}")


def _print_hook(result: dict, session_id: str | None) -> None:
    if result["tool_count"] == 0:
        return  # no matching lines: print nothing, exit 0
    # Latch: the same summary line would otherwise print on every assistant
    # turn's Stop event within one session. fired_before() records the first
    # print and suppresses the rest — analysis/exit code are unaffected, only
    # this repeated print is gated. No session_id / import failure -> print
    # every time (fail-open toward speaking, per hook_latch's own contract).
    if fired_before is not None and session_id and fired_before(session_id, LATCH_KEY):
        return
    stages_csv = ",".join(sorted(result["observed_stages"])) or "none"
    skipped_csv = ",".join(result["missing_stages"]) or "none"
    print(
        f"[trajectory] sess={result['session']} tools={result['tool_count']} "
        f"stages={stages_csv} skipped={skipped_csv}"
    )


def _read_hook_payload() -> dict:
    """Best-effort stdin JSON read for --hook mode. Never raises.

    Returns {} on empty/unparseable stdin or when stdin isn't piped at all
    (e.g. a manual `python scripts/trajectory_review.py --hook` run from an
    interactive terminal) — callers must treat {} as "no session scoping
    available" and fall back to the pre-existing rows[-1] behavior.
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
    hook_mode = "--hook" in sys.argv[1:]
    session_id = None
    try:
        audit_path = _audit_path()
        schema = check_schema(audit_path)
        if schema["notice"]:
            # Always printed (both modes) — a legacy-marker notice or a
            # mismatch warning must be visible; hook_mode never suppresses it,
            # it only decides whether it's ALSO fatal (see below).
            print(schema["notice"], file=sys.stderr)
        if not schema["ok"]:
            _log_error(
                f"trajectory_review schema mismatch: found={schema['found']!r} "
                f"supported={SUPPORTED_SCHEMA_VERSION!r}"
            )
            if not hook_mode:
                # Manual/CLI invocation: fail loud, per A-P4 done-gates — a
                # reader must not silently replay rows under an unsupported
                # schema. A hook invocation must never break the session, so
                # this branch only fires for a direct `python
                # scripts/trajectory_review.py` run (no --hook).
                return 1

        if hook_mode:
            payload = _read_hook_payload()
            raw_session_id = payload.get("session_id") or payload.get("sessionId")
            session_id = _session_short(raw_session_id)
        result = review(session=session_id)
        if hook_mode:
            _print_hook(result, session_id)
        else:
            _print_verbose(result)
        return 0
    except Exception as exc:
        _log_error(f"trajectory_review error: {exc!r}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
