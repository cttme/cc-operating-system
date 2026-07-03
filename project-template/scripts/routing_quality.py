#!/usr/bin/env python
"""routing_quality — passive routing-quality scorecard, emitted at session-end.

R6: replays tasks/audit.md (the R4 trajectory log) and answers "did the model
tier chosen match the work?" — never a gate. Reuses
trajectory_review._parse_lines() (don't re-parse the log twice) and
model_routing_hint.MECHANICAL_SKILLS (SSOT for "which skills are bookkeeping"
— scorer and UserPromptSubmit nudge must never drift apart).

CLI:
  python scripts/routing_quality.py                 # score the latest session
  python scripts/routing_quality.py --session <id>   # score one named session
  python scripts/routing_quality.py --all            # per-session report, every sess=
As a Stop hook (no --session/--all given), a session_id in the hook's stdin
JSON payload is preferred over the "latest session" fallback. One-block
scorecard, exit 0 always. A parse/IO error is noted to trajectory_review's
sidecar log; still exits 0.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Bare script run (not a module import), so sys.path[0] is scripts/, not the
# repo root — add it explicitly before importing (same fix as trajectory_log.py).
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from scripts.model_routing_hint import MECHANICAL_SKILLS  # noqa: E402
from scripts.trajectory_review import (  # noqa: E402
    SUPPORTED_SCHEMA_VERSION,
    _audit_path,
    _log_error,
    _parse_lines,
    check_schema,
)

# NOTE: this scorer can only score the latest/targeted session in ONE
# audit.md (score() / score_all() below) — it does not roll up multiple
# sessions or multiple audit.md files into one report. A `--session <id>`
# rollup across sessions/files is R5's future job; this is a placeholder
# comment only, do NOT build that here.

# Schema field list is documented ONCE in scripts/trajectory_log.py (the
# writer's module docstring "Schema" section) — this module does not keep
# its own copy. Version compatibility is asserted via
# trajectory_review.check_schema()/SUPPORTED_SCHEMA_VERSION (imported above),
# not re-implemented here.

# === Section: Classifiers ===

# Reasoning-heavy skills — never mechanical regardless of MECHANICAL_SKILLS.
REASONING_SKILLS = {"/plan", "/triz", "/council", "/hats", "/spec", "/retro"}

# Bookkeeping Bash commands — read-only / test-run / VCS hygiene, not "real work".
_MECHANICAL_BASH_RE = re.compile(
    r"^(echo|grep|ls|cat|wc|find|head|tail|sed|awk"
    r"|git\s+(status|log|diff|add|commit)"
    r"|python\s+-m\s+pytest|python\s+-c)\b",
    re.IGNORECASE,
)

# Matches trajectory_log.py's _summarize_args() output so we can recover the
# skill/agent/cmd value from the raw line (the parsed row dict only carries
# ts/sess/model/stage/tool — see trajectory_review.LINE_RE).
_SKILL_ARG_RE = re.compile(r"\bskill=(\S+)")
_CMD_ARG_RE = re.compile(r"\bcmd=(.*)$")


def _is_mechanical(tool: str, args_tail: str) -> tuple[bool, bool]:
    """Classify one tool call. Returns (is_mechanical, is_delegated).

    is_delegated marks Agent/Task dispatch — well-routed regardless of tier,
    reported separately rather than folded into either bucket.
    """
    if tool == "Skill":
        m = _SKILL_ARG_RE.search(args_tail)
        name = m.group(1) if m else ""
        if not name.startswith("/"):
            name = f"/{name}"
        if name in REASONING_SKILLS:
            return False, False
        if name in MECHANICAL_SKILLS:
            return True, False
        return False, False
    if tool == "Bash":
        m = _CMD_ARG_RE.search(args_tail)
        cmd = (m.group(1) if m else "").strip()
        return bool(_MECHANICAL_BASH_RE.match(cmd)), False
    if tool in ("Read", "Grep", "Glob"):
        return True, False
    if tool in ("Edit", "Write", "NotebookEdit"):
        return False, False
    if tool in ("Agent", "Task"):
        return False, True
    return False, False  # conservative: don't over-flag unknown tools


# Cheap-tier and top-tier model-name substrings for the *dispatch* classifier
# (Agent rows' model= token) and for the session-model three-way classifier
# below. Kept local (not model_routing_hint._is_opus) because that helper is
# binary opus-or-not by design (a nudge fallback); this scorer must not let an
# unrecognized model masquerade as a positive "opus" observation — see
# _classify_model.
_CHEAP_TIER_HINTS = ("sonnet", "haiku")
_TOP_TIER_HINTS = ("opus", "fable")


def _classify_model(model: str | None) -> str:
    """Three-way session/dispatch-model classifier: 'cheap', 'opus', or 'unknown'.

    Unlike model_routing_hint._is_opus (a nudge fallback that treats unknown as
    Opus so the nudge never silently drops), this scorer must not let a
    detection failure inflate the "mechanical on Opus" indictment — an
    unparseable/absent model is its own bucket, counted in neither.
    """
    if not model or model == "?":
        return "unknown"
    low = model.casefold()
    if any(h in low for h in _CHEAP_TIER_HINTS):
        return "cheap"
    if any(h in low for h in _TOP_TIER_HINTS):
        return "opus"
    return "unknown"


def _is_opus(model: str) -> bool:
    """Back-compat wrapper: True only for a positively-classified Opus model.

    Deliberately NOT "unknown = True" here (that's model_routing_hint's nudge
    policy, not this scorecard's) — see _classify_model docstring.
    """
    return _classify_model(model) == "opus"


_AGENT_MODEL_RE = re.compile(r"\bmodel=(\S+)")


def _classify_dispatch(args_tail: str) -> str:
    """Classify an Agent/Task row's dispatch tier from its model= token.

    Returns 'cheap', 'top', 'inherit', or 'unknown' (no model= token found —
    an older log line predating this field, not a real "inherit" signal).
    """
    m = _AGENT_MODEL_RE.search(args_tail)
    if not m:
        return "unknown"
    token = m.group(1).strip()
    if token == "inherit":
        return "inherit"
    low = token.casefold()
    if any(h in low for h in _CHEAP_TIER_HINTS):
        return "cheap"
    if any(h in low for h in _TOP_TIER_HINTS):
        return "top"
    return "unknown"


# === Section: Core API ===


def _empty_result(session: str | None) -> dict:
    return {
        "session": session,
        "total_calls": 0,
        "opus_calls": 0,
        "opus_mechanical": 0,
        "waste_pct": 0.0,
        "delegated_calls": 0,
        "cheap_tier_calls": 0,
        "unknown_model_calls": 0,
        "dispatch_cheap": 0,
        "dispatch_top": 0,
        "dispatch_inherit": 0,
        "dispatch_unknown": 0,
    }


def score(audit_path: str | None = None, session: str | None = None) -> dict:
    """Replay audit.md and score routing quality for one session.

    Returns:
        {session, total_calls, opus_calls, opus_mechanical, waste_pct,
         delegated_calls, cheap_tier_calls, unknown_model_calls,
         dispatch_cheap, dispatch_top, dispatch_inherit, dispatch_unknown}

    A row's session-level model (model=... on the row itself) drives the
    opus/cheap/unknown split. An Agent/Task row's dispatch tier (its own
    model=<tier> arg, added by trajectory_log.py) is scored separately via
    dispatch_* — the two are independent signals: the parent call may run on
    Opus while dispatching a Sonnet subagent, and that dispatch is exactly
    the well-routed behavior this scorecard exists to detect and credit.
    """
    path = _audit_path(audit_path)
    rows = _parse_lines(path)

    if not rows:
        return _empty_result(session)

    target_session = session or rows[-1]["sess"]
    session_rows = [r for r in rows if r["sess"] == target_session]

    if not session_rows:
        return _empty_result(target_session)

    total_calls = len(session_rows)
    opus_calls = 0
    opus_mechanical = 0
    delegated_calls = 0
    cheap_tier_calls = 0
    unknown_model_calls = 0
    dispatch_cheap = 0
    dispatch_top = 0
    dispatch_inherit = 0
    dispatch_unknown = 0

    for row in session_rows:
        tool = row["tool"]
        model = row["model"]
        args_tail = row.get("args") or ""
        mechanical, delegated = _is_mechanical(tool, args_tail)

        if delegated:
            delegated_calls += 1
            dispatch_tier = _classify_dispatch(args_tail)
            if dispatch_tier == "cheap":
                dispatch_cheap += 1
            elif dispatch_tier == "top":
                dispatch_top += 1
            elif dispatch_tier == "inherit":
                dispatch_inherit += 1
            else:
                dispatch_unknown += 1

        tier = _classify_model(model)
        if tier == "opus":
            opus_calls += 1
            if mechanical:
                opus_mechanical += 1
        elif tier == "cheap":
            cheap_tier_calls += 1
        else:
            unknown_model_calls += 1

    waste_pct = (opus_mechanical / opus_calls) if opus_calls else 0.0

    return {
        "session": target_session,
        "total_calls": total_calls,
        "opus_calls": opus_calls,
        "opus_mechanical": opus_mechanical,
        "waste_pct": waste_pct,
        "delegated_calls": delegated_calls,
        "cheap_tier_calls": cheap_tier_calls,
        "unknown_model_calls": unknown_model_calls,
        "dispatch_cheap": dispatch_cheap,
        "dispatch_top": dispatch_top,
        "dispatch_inherit": dispatch_inherit,
        "dispatch_unknown": dispatch_unknown,
    }


def score_all(audit_path: str | None = None) -> list[dict]:
    """Score every distinct session found in the audit log, in first-seen order."""
    path = _audit_path(audit_path)
    rows = _parse_lines(path)
    seen: list[str] = []
    for r in rows:
        if r["sess"] not in seen:
            seen.append(r["sess"])
    return [score(audit_path=audit_path, session=sess) for sess in seen]


# === Section: CLI ===


def _format_scorecard(result: dict) -> str:
    if result["session"] is None or result["total_calls"] == 0:
        return "Routing quality — (no trajectory entries found; nothing to score)"
    pct = round(result["waste_pct"] * 100)
    verdict = (
        "Route more mechanical work to Sonnet subagents."
        if result["opus_mechanical"] > 0
        else "Routing looks healthy."
    )
    dispatch_bits = []
    if result.get("dispatch_cheap"):
        dispatch_bits.append(f"{result['dispatch_cheap']} cheap-tier")
    if result.get("dispatch_top"):
        dispatch_bits.append(f"{result['dispatch_top']} top-tier")
    if result.get("dispatch_inherit"):
        dispatch_bits.append(f"{result['dispatch_inherit']} inherit")
    if result.get("dispatch_unknown"):
        dispatch_bits.append(f"{result['dispatch_unknown']} unknown")
    dispatch_str = f" ({', '.join(dispatch_bits)})" if dispatch_bits else ""
    unknown_str = (
        f", {result['unknown_model_calls']} unknown-model" if result.get("unknown_model_calls") else ""
    )
    return (
        f"Routing quality — sess {result['session']}: {result['total_calls']} calls, "
        f"{result['opus_calls']} on Opus, {result['opus_mechanical']} mechanical-on-Opus "
        f"({pct}%). {result['delegated_calls']} delegated{dispatch_str}, "
        f"{result['cheap_tier_calls']} on cheap tier{unknown_str}. → {verdict}"
    )


def _format_all(results: list[dict]) -> str:
    if not results:
        return "Routing quality — (no trajectory entries found; nothing to score)"
    lines = [_format_scorecard(r) for r in results]
    return "\n".join(lines)


def _stdin_session_id() -> str | None:
    """Best-effort: read a Stop-hook JSON payload from stdin and pull session_id.

    Same payload shape trajectory_log.py parses (tool_name/tool_input/session_id
    or sessionId — see its main()). Only consulted when stdin is NOT a TTY (a
    hook invocation pipes JSON in; an interactive CLI run has nothing to read
    and must not block waiting on it). Any failure returns None — the caller
    falls back to --session or the latest session, never raises.
    """
    if sys.stdin is None or sys.stdin.isatty():
        return None
    try:
        raw = sys.stdin.read()
        if not raw or not raw.strip():
            return None
        data = json.loads(raw)
        session_id = data.get("session_id") or data.get("sessionId")
        if not session_id:
            return None
        return _session_short(str(session_id))
    except Exception:
        return None


def _session_short(session_id: str) -> str:
    """Mirror trajectory_log._session_short (8-char alnum prefix) so a raw
    session_id from the hook payload matches the sess= token already written
    to audit.md."""
    alnum = re.sub(r"[^A-Za-z0-9]", "", session_id)
    return alnum[:8] if alnum else "anon"


def _parse_argv(argv: list[str]) -> dict:
    """Minimal argv parser — no argparse dependency for a hook-invoked script.

    Supports: --session <id>, --all (mutually exclusive with --session).
    Unknown args are ignored (a hook may pass args this script doesn't use).
    """
    session = None
    all_sessions = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--session" and i + 1 < len(argv):
            session = argv[i + 1]
            i += 2
            continue
        if arg == "--all":
            all_sessions = True
            i += 1
            continue
        i += 1
    return {"session": session, "all": all_sessions}


def _safe_print(text: str) -> None:
    """Print, tolerating a non-UTF-8 console (Windows cp1252 can't encode →/em-dash).

    Falls back to an ASCII-safe transliteration rather than crashing — a
    scorecard must never break session-end just because the terminal codepage
    can't render an arrow.
    """
    try:
        print(text)
    except UnicodeEncodeError:
        encoding = sys.stdout.encoding or "ascii"
        print(text.encode(encoding, errors="replace").decode(encoding))


def main() -> int:
    try:
        audit_path = _audit_path()
        schema = check_schema(audit_path)
        if schema["notice"]:
            _safe_print(schema["notice"])
        if not schema["ok"]:
            _log_error(
                f"routing_quality schema mismatch: found={schema['found']!r} "
                f"supported={SUPPORTED_SCHEMA_VERSION!r}"
            )
            # A hook invocation (stdin piped, e.g. a Stop hook) must never
            # break the session — notice only, still exit 0. A manual/CLI
            # run (interactive stdin, or --session/--all given explicitly)
            # fails loud: a scorecard must not silently replay rows under an
            # unsupported schema and report numbers as if they were valid.
            is_manual_cli = (sys.stdin is None or sys.stdin.isatty()) or bool(
                sys.argv[1:]
            )
            if is_manual_cli:
                return 1

        opts = _parse_argv(sys.argv[1:])

        if opts["all"]:
            results = score_all()
            _safe_print(_format_all(results))
            return 0

        session = opts["session"]
        if session is None:
            # Stop-hook path: prefer session_id from the hook's stdin JSON
            # payload over the "latest session in the file" fallback — a hook
            # firing mid-session (or a slow flush) can otherwise score the
            # wrong (previous) session. --session on the CLI always wins;
            # this is only consulted when neither was given.
            session = _stdin_session_id()

        result = score(session=session)
        _safe_print(_format_scorecard(result))
        return 0
    except Exception as exc:  # a scorecard must never break session-end
        _log_error(f"routing_quality error: {exc!r}")
        _safe_print("Routing quality - (scorer error; see tasks/.trajectory_errors.log)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
