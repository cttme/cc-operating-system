#!/usr/bin/env python
"""cost_breakdown.py — per-model + cache-creation cost split.

WHY: "improve token consumption" is blind without knowing the Opus/Sonnet mix and
the resume-tax (cache_creation) share. ccusage does NOT expose a per-model split in
its JSON, so we aggregate from the source of truth: Claude Code transcript JSONL.
Every assistant message records `message.model` + `message.usage`
(input/output/cache_creation/cache_read tokens).

Transcripts live in two places and we read BOTH:
  - main sessions:  ~/.claude/projects/<proj>/<session-uuid>.jsonl
  - subagents:      ~/.claude/projects/<proj>/<session-uuid>/subagents/agent-*.jsonl
The nested subagent files hold delegated Sonnet/Haiku spend. Reading only the
top-level files made all subagent cost invisible and systematically over-reported
the Opus share. Entries are deduped by `uuid` so an inlined sidechain (if a future
version writes one) can't be double-counted.

USAGE:
  python scripts/cost_breakdown.py                 # today, one-line summary (stdout)
  python scripts/cost_breakdown.py --days 14       # trailing 14 days
  python scripts/cost_breakdown.py --since 2026-06-01
  python scripts/cost_breakdown.py --detail        # per-model table
  python scripts/cost_breakdown.py --hook          # one line to stderr, silent if no data

NOTE: PRICING below is approximate (USD / million tokens). ccusage stays authoritative
for absolute dollars; the cost-weighted SPLIT is the point here. Update if Anthropic
changes pricing. Feeds the /retro skill (Phase B).
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from datetime import UTC, datetime, timedelta

# ─────────────────────────────────────────────────────────
# Pricing (USD per 1M tokens). Keyed by model-family substring.
# cache_write = cache_creation_input_tokens; cache_read = cache_read_input_tokens.
# ─────────────────────────────────────────────────────────
PRICING = {
    "opus":   {"in": 15.0, "out": 75.0, "cw": 18.75, "cr": 1.50},
    "sonnet": {"in": 3.0,  "out": 15.0, "cw": 3.75,  "cr": 0.30},
    "haiku":  {"in": 1.0,  "out": 5.0,  "cw": 1.25,  "cr": 0.10},
}
UNKNOWN = {"in": 3.0, "out": 15.0, "cw": 3.75, "cr": 0.30}  # fallback ~ Sonnet


def family(model: str) -> str:
    m = (model or "").lower()
    for fam in PRICING:
        if fam in m:
            return fam
    return "other"


def rate(model: str) -> dict[str, float]:
    return PRICING.get(family(model), UNKNOWN)


# ─────────────────────────────────────────────────────────
# Aggregate transcripts within the window
# ─────────────────────────────────────────────────────────
def collect(cutoff: datetime) -> dict[str, dict[str, float]]:
    """Returns {model: {in,out,cc,cr,cost,n}} aggregated across all projects."""
    agg: dict[str, dict[str, float]] = {}
    seen: set[str] = set()  # dedup by entry uuid (defensive vs inlined sidechains)
    # Top-level session transcripts AND nested subagent transcripts. The subagents/
    # glob is what makes delegated Sonnet/Haiku spend visible.
    patterns = [
        os.path.expanduser("~/.claude/projects/*/[0-9a-f]*.jsonl"),
        os.path.expanduser("~/.claude/projects/*/*/subagents/*.jsonl"),
    ]
    for path in sorted({p for pat in patterns for p in glob.glob(pat)}):
        # Skip files whose last write predates the window entirely.
        try:
            if datetime.fromtimestamp(os.path.getmtime(path), UTC) < cutoff:
                continue
        except OSError:
            continue
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                if o.get("type") != "assistant":
                    continue
                uid = o.get("uuid")
                if uid is not None:
                    if uid in seen:
                        continue
                    seen.add(uid)
                _m = (o.get("message") or {}).get("model") or ""
                if _m.startswith("<") or not _m:
                    continue  # skip <synthetic> / placeholder entries
                ts = o.get("timestamp")
                if ts:
                    try:
                        if datetime.fromisoformat(ts.replace("Z", "+00:00")) < cutoff:
                            continue
                    except ValueError:
                        pass
                msg = o.get("message") or {}
                if not isinstance(msg, dict):
                    continue
                model = msg.get("model") or "unknown"
                u = msg.get("usage") or {}
                a = agg.setdefault(
                    model, {"in": 0, "out": 0, "cc": 0, "cr": 0, "cost": 0.0, "n": 0}
                )
                ti = u.get("input_tokens", 0) or 0
                to = u.get("output_tokens", 0) or 0
                tc = u.get("cache_creation_input_tokens", 0) or 0
                tr = u.get("cache_read_input_tokens", 0) or 0
                a["in"] += ti
                a["out"] += to
                a["cc"] += tc
                a["cr"] += tr
                a["n"] += 1
                r = rate(model)
                a["cost"] += (
                    ti * r["in"] + to * r["out"] + tc * r["cw"] + tr * r["cr"]
                ) / 1_000_000
    return agg


def summarize(agg: dict[str, dict[str, float]]) -> str | None:
    if not agg:
        return None
    total_cost = sum(a["cost"] for a in agg.values()) or 1e-9
    total_cc = sum(a["cc"] for a in agg.values())
    total_in_side = sum(a["in"] + a["cc"] + a["cr"] for a in agg.values()) or 1
    # Cost-weighted share by family (collapse model versions).
    fam_cost: dict[str, float] = {}
    for model, a in agg.items():
        fam_cost[family(model)] = fam_cost.get(family(model), 0.0) + a["cost"]
    parts = [
        f"{fam.capitalize()} {100 * c / total_cost:.0f}%"
        for fam, c in sorted(fam_cost.items(), key=lambda kv: -kv[1])
    ]
    cache_pct = 100 * total_cc / total_in_side
    return (
        f"{' / '.join(parts)} | cache_creation {cache_pct:.0f}% of input "
        f"| ~${total_cost:.0f} est"
    )


def detail(agg: dict[str, dict[str, float]]) -> str:
    if not agg:
        return "(no transcript data in window)"
    lines = [f"{'model':<26}{'msgs':>6}{'cost$':>9}{'cc(M)':>8}{'cr(M)':>9}"]
    for model, a in sorted(agg.items(), key=lambda kv: -kv[1]["cost"]):
        lines.append(
            f"{model:<26}{a['n']:>6}{a['cost']:>9.1f}"
            f"{a['cc'] / 1e6:>8.1f}{a['cr'] / 1e6:>9.1f}"
        )
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description="Per-model + cache cost split from transcripts.")
    p.add_argument("--days", type=int, default=1, help="trailing N days (default 1)")
    p.add_argument("--since", help="YYYY-MM-DD (UTC); overrides --days")
    p.add_argument("--detail", action="store_true", help="per-model table")
    p.add_argument("--hook", action="store_true", help="one line to stderr; silent if no data")
    args = p.parse_args()

    if args.since:
        try:
            cutoff = datetime.fromisoformat(args.since).replace(tzinfo=UTC)
        except ValueError:
            print(f"bad --since: {args.since}", file=sys.stderr)
            return 1
    else:
        cutoff = datetime.now(UTC) - timedelta(days=args.days)

    agg = collect(cutoff)
    summary = summarize(agg)

    if args.hook:
        if summary:
            print(f"  [cost] {summary}", file=sys.stderr)
        return 0

    window = args.since or f"last {args.days}d"
    print(f"Cost breakdown ({window}): {summary or '(no data)'}")
    if args.detail:
        print(detail(agg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
