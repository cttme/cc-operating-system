#!/usr/bin/env python
"""Session budget check — invoked from a Stop hook.

Two measurements:
  1. Context window fill (transcript size proxy)
  2. ccusage daily (account-level limit usage)

Thresholds:
  - 70% → warn
  - 85% → critical

Non-blocking — writes warnings to stderr. Lean engineering: defense in depth.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

# ─────────────────────────────────────────────────────────
# Thresholds (conservative)
# ─────────────────────────────────────────────────────────
CTX_LIMIT_KB = 6500  # Calibration: 3.7MB transcript = 589.6K context tokens
                     # → ~6.4 bytes/token (JSON overhead + tool I/O + cache duplication)
                     # 1M tokens (Opus 4.6+ default) → ~6500 KB transcript
                     # On Sonnet (200K): 1300 KB → time to compact manually
CTX_WARN_PCT = 70
CTX_CRITICAL_PCT = 85

# Daily token budget (baseline ~250M, ~150M target after optimization)
# For Max plan: weekly ~1B, daily ~140M average
DAILY_WARN_TOKENS = 100_000_000   # 100M = moderate-high day
DAILY_CRITICAL_TOKENS = 200_000_000  # 200M = approaching limit

# 5-hour billing block (Anthropic Max plan rate-limit window)
# Calibration (2026-05-18 22:30): 37.1M tokens = 77% in Claude Code UI
# → Anthropic 5h cap estimate ~48M (Max plan, heavy Opus 4.7 use)
# Thresholds: 70% warn = ~33M, 85% critical = ~40M
BLOCK_WARN_TOKENS = 33_000_000      # ~70% — attention
BLOCK_CRITICAL_TOKENS = 40_000_000   # ~85% — approaching limit


# ─────────────────────────────────────────────────────────
# 1. Context window fill (transcript size)
# ─────────────────────────────────────────────────────────
def check_context_fill() -> tuple[float, str | None]:
    """Returns (pct, warning_msg or None)."""
    projects_dir = Path(os.path.expanduser("~/.claude/projects"))
    if not projects_dir.exists():
        return 0.0, None

    transcripts = list(projects_dir.rglob("*.jsonl"))
    if not transcripts:
        return 0.0, None

    # Latest active transcript (modified time)
    current = max(transcripts, key=lambda p: p.stat().st_mtime)
    size_kb = current.stat().st_size / 1024
    pct = (size_kb / CTX_LIMIT_KB) * 100

    if pct > CTX_CRITICAL_PCT:
        return pct, (
            f"🚨 Context {pct:.0f}% full ({size_kb:.0f}KB).\n"
            f"     → NOW: /session-end + /clear. Nothing lost (handoff is updated).\n"
            f"     → Resuming would reload a 4MB transcript with cache_creation tax."
        )
    if pct > CTX_WARN_PCT:
        return pct, (
            f"📊 Context {pct:.0f}% ({size_kb:.0f}KB).\n"
            f"     → Get ready for the /session-end + /clear reflex.\n"
            f"     → Cutting at a natural pause = cheap fresh start."
        )
    return pct, None


# ─────────────────────────────────────────────────────────
# 2. ccusage daily (account-level limit usage)
# ─────────────────────────────────────────────────────────
def check_daily_budget() -> str | None:
    try:
        # shell=True — on Windows ccusage is a .cmd shim; needs PATH lookup
        r = subprocess.run(
            "ccusage daily",
            capture_output=True, text=True, timeout=8, shell=True,
            encoding="utf-8", errors="replace",
        )
    except Exception:
        return None

    # Find today's row (not the Total row)
    import re
    from datetime import date
    output = r.stdout or ""
    today_str = date.today().isoformat()  # 2026-MM-DD

    # Look for today's date row — exclude the Total row
    today_line = None
    for line in output.split("\n"):
        if today_str in line and "Total" not in line:
            today_line = line
            break

    if not today_line:
        return None  # No data for today yet

    # Pull the first large number from the line (token count)
    nums = re.findall(r"(\d{1,3}(?:,\d{3})+)", today_line)
    if not nums:
        return None
    today_tokens = int(nums[0].replace(",", ""))

    if today_tokens > DAILY_CRITICAL_TOKENS:
        return f"🚨 Daily tokens {today_tokens:,} (>{DAILY_CRITICAL_TOKENS:,}). Approaching limit."
    if today_tokens > DAILY_WARN_TOKENS:
        return f"📊 Daily tokens {today_tokens:,}. Work cost-efficiently."
    return None


# ─────────────────────────────────────────────────────────
# 3. 5-hour billing block (Anthropic Max plan rate limit)
# ─────────────────────────────────────────────────────────
def check_block_usage() -> str | None:
    """Track usage within the active 5-hour block.

    Mirrors the UI's "5-hour limit X%" indicator.
    High burnRate + near block end = critical warning.
    """
    try:
        # shell=True — Windows ccusage .cmd shim
        r = subprocess.run(
            "ccusage blocks --json",
            capture_output=True, text=True, timeout=10, shell=True,
            encoding="utf-8", errors="replace",
        )
    except Exception:
        return None

    if r.returncode != 0 or not r.stdout:
        return None

    import json as _json
    from datetime import datetime, timezone

    try:
        data = _json.loads(r.stdout)
    except _json.JSONDecodeError:
        return None

    blocks = data.get("blocks", [])
    active = [b for b in blocks if b.get("isActive")]
    if not active:
        return None

    b = active[0]
    total = b.get("totalTokens", 0)
    burn_rate = b.get("burnRate") or {}
    end_time_str = b.get("endTime") or ""

    # Minutes left until block end
    try:
        end_dt = datetime.fromisoformat(end_time_str.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        minutes_left = max(0, int((end_dt - now).total_seconds() / 60))
    except Exception:
        minutes_left = -1

    # Projection (if any) — what would the block-end total look like at this rate
    projection = b.get("projection") or {}
    projected_total = projection.get("totalTokens") if isinstance(projection, dict) else None

    # Threshold check — action-oriented messages
    if total > BLOCK_CRITICAL_TOKENS:
        msg = (
            f"🚨 5-hour block: {total:,} tokens ({minutes_left} min left). LIMIT VERY CLOSE.\n"
            f"     → NOW run /session-end. handoff.md is updated; NOTHING LOST.\n"
            f"     → Then /clear. Finish before messages get blocked."
        )
        if projected_total and projected_total > BLOCK_CRITICAL_TOKENS:
            msg += f"\n     Projection: {projected_total:,} (exceeds limit at current rate)."
        return msg

    if total > BLOCK_WARN_TOKENS:
        msg = (
            f"📊 5-hour block: {total:,} tokens ({minutes_left} min left) — 70%+ usage.\n"
            f"     → At the next natural pause, ready the /session-end + /clear reflex.\n"
            f"     → Nothing lost (state goes to handoff). Early cut = cheap fresh start."
        )
        if projected_total and projected_total > BLOCK_CRITICAL_TOKENS:
            msg += f"\n     ⚠ At this rate it would reach {projected_total:,} (critical)."
        return msg

    # Projection-only warning when current usage is low
    if projected_total and projected_total > BLOCK_CRITICAL_TOKENS and minutes_left > 30:
        return (
            f"📊 5-hour projection: at this rate, {projected_total:,} tokens. Slow down.\n"
            f"     → If mid-task: at the next natural pause, /session-end + /clear."
        )

    return None


# ─────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────
def main() -> int:
    warnings: list[str] = []

    pct, ctx_msg = check_context_fill()
    if ctx_msg:
        warnings.append(ctx_msg)

    daily_msg = check_daily_budget()
    if daily_msg:
        warnings.append(daily_msg)

    block_msg = check_block_usage()
    if block_msg:
        warnings.append(block_msg)

    if warnings:
        print("─" * 60, file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)
        print("─" * 60, file=sys.stderr)

    return 0  # Never block


if __name__ == "__main__":
    sys.exit(main())
