#!/usr/bin/env python
"""trajectory_log — PostToolUse hook.

Appends one line per logged tool call to `tasks/audit.md` so a session's
work can be replayed against the thinking-pipeline stages (R4 trajectory
observability — see .claude/rules/thinking-pipeline.md). Companion reader:
scripts/trajectory_review.py.

Çağrı: stdin'den {"tool_name", "tool_input", "transcript_path"/"transcriptPath",
"session_id"/"sessionId"} gelir (Claude Code PostToolUse protokolü).

Never blocks, never raises into the hook: any stdin-parse failure exits 0
silently; any other internal error is noted to a sidecar log
(tasks/.trajectory_errors.log) and STILL exits 0 — per the project's
no-silent-failure rule, but a hook must never break the user's flow, so the
sidecar log is the compromise.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# scripts/ is a package (scripts/__init__.py), but this file is invoked as
# `python scripts/trajectory_log.py` — a bare script run, not a module import —
# so sys.path[0] is scripts/, not the repo root, and `from scripts.X import Y`
# would fail. Add the repo root explicitly before importing.
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

try:
    from scripts.model_routing_hint import _active_model
except Exception:  # pragma: no cover - defensive: import must never break the hook
    _active_model = None  # type: ignore[assignment]


# === Section: Config ===

LOGGED_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Bash", "Skill", "Agent", "Task"}

AUDIT_PATH_ENV = "TRAJECTORY_AUDIT_PATH"
DEFAULT_AUDIT_PATH = "tasks/audit.md"
ERROR_LOG_PATH = "tasks/.trajectory_errors.log"

_GIT_COMMIT_RE = re.compile(r"\bgit\s+commit\b")


# === Section: Stage inference ===


def _infer_stage(tool_name: str, tool_input: dict) -> str:
    """Map a tool call to a thinking-pipeline stage (best-effort, advisory)."""
    if tool_name == "Skill":
        name = str(tool_input.get("skill") or tool_input.get("args") or "").casefold()
        if "triz" in name:
            return "frame"
        if "plan" in name or "spec" in name:
            return "plan"
        if "hats" in name or "council" in name:
            return "decide"
        if "verify" in name:
            return "verify"
        if "retro" in name:
            return "reflect"
        if "onboard" in name:
            return "onboard"
        if "session-end" in name:
            return "reflect"
        return ""
    if tool_name == "Bash":
        command = str(tool_input.get("command") or "")
        if _GIT_COMMIT_RE.search(command):
            return "commit"
        return "execute"
    if tool_name in ("Edit", "Write", "MultiEdit", "NotebookEdit", "Agent", "Task"):
        return "execute"
    return ""


# === Section: Args summary ===


def _truncate(s: str, limit: int = 80) -> str:
    s = s.strip()
    return s if len(s) <= limit else s[: limit - 1] + "…"


def _summarize_args(tool_name: str, tool_input: dict) -> str:
    """Build a compact single-line args summary (no newlines, ~80 chars)."""
    if tool_name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        file_path = str(tool_input.get("file_path") or "")
        return _truncate(f"file={file_path}")
    if tool_name == "Bash":
        command = str(tool_input.get("command") or "")
        command = re.sub(r"[\r\n]+", " ", command)[:60]
        return _truncate(f"cmd={command}")
    if tool_name == "Skill":
        name = str(tool_input.get("skill") or tool_input.get("args") or "")
        name = re.sub(r"[\r\n]+", " ", name)
        return _truncate(f"skill={name}")
    if tool_name in ("Agent", "Task"):
        subagent = str(tool_input.get("subagent_type") or "")
        description = str(tool_input.get("description") or "")
        description = re.sub(r"[\r\n]+", " ", description)[:40]
        # Absence of `model` means the subagent inherits the caller's model —
        # that's real information (not "unknown"), so print "inherit", never "?".
        # Appended AFTER truncation (like Bash's pre-truncated cmd) so a long
        # description can never crowd model= out of the line.
        dispatch_model = str(tool_input.get("model") or "").strip() or "inherit"
        return _truncate(f"agent={subagent} ({description}) model={dispatch_model}", limit=100)
    return ""


# === Section: Identifiers ===


def _session_short(session_id: str | None) -> str:
    if not session_id:
        return "anon"
    alnum = re.sub(r"[^A-Za-z0-9]", "", str(session_id))
    return alnum[:8] if alnum else "anon"


def _audit_path() -> Path:
    return Path(os.environ.get(AUDIT_PATH_ENV, DEFAULT_AUDIT_PATH))


# === Section: Error sidecar ===


def _log_error(message: str) -> None:
    """Best-effort sidecar log for internal errors. Never raises."""
    try:
        path = Path(ERROR_LOG_PATH)
        path.parent.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with path.open("a", encoding="utf-8", errors="backslashreplace", newline="\n") as fh:
            fh.write(f"[{ts}] {message}\n")
    except Exception:
        pass  # sidecar logging itself must never break the hook


# === Section: Main ===


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # stdin parse failure: exit silently, never break the user's flow

    try:
        tool_name = str(data.get("tool_name") or "")
        if tool_name not in LOGGED_TOOLS:
            return 0

        tool_input = data.get("tool_input") or {}
        if not isinstance(tool_input, dict):
            tool_input = {}

        transcript_path = data.get("transcript_path") or data.get("transcriptPath")
        model = None
        if _active_model is not None:
            try:
                model = _active_model(transcript_path)
            except Exception:
                model = None
        model = model or "?"

        session_id = data.get("session_id") or data.get("sessionId")
        sess = _session_short(session_id)

        stage = _infer_stage(tool_name, tool_input)
        args_summary = _summarize_args(tool_name, tool_input)

        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{ts}] sess={sess} model={model} stage={stage} tool={tool_name} {args_summary}".rstrip()

        audit_path = _audit_path()
        audit_path.parent.mkdir(parents=True, exist_ok=True)
        # backslashreplace: a surrogate-mangled row is recorded garbled, never dropped
        # (OPS O1); newline="\n" keeps audit.md LF-consistent on Windows (OPS O7)
        with audit_path.open("a", encoding="utf-8", errors="backslashreplace", newline="\n") as fh:
            fh.write(line + "\n")

        return 0
    except Exception as exc:  # no-silent-failure: note it, but never break the hook
        _log_error(f"trajectory_log error: {exc!r}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
