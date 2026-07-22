---
name: spend
description: Cross-tool AI-spend view via codeburn — unifies Claude + Codex + Cursor + … session spend from local files into one priced dollar figure, covering cost_breakdown.py's non-Claude blind spot. Reporting-only (never sync / guard / apply). Feeds /retro §1 and §3.
allowed-tools: Bash, Read
---

# /spend — Cross-tool AI-spend view (codeburn, reporting-only)

The OS already meters spend, but in **three siloed instruments** that nothing joins:

| Instrument | Sees | Source |
|---|---|---|
| `cost_breakdown.py` | Claude only (incl. Claude subagents) | `~/.claude/projects/**/*.jsonl` |
| `.codex-log` | ask-codex delegation — raw tokens, **no dollars** | `~/.claude/.codex-log/<date>/calls.jsonl` |
| `.ollama-log` | local Ollama | `~/.ollama-log` |

`/retro` reconciles them **by hand** (`cat` the `.codex-log`), and warns the raw
percentages aren't comparable. There is **no unified cross-tool dollar view** — the OS's
largest measurement blind spot is non-Claude spend (Codex, Cursor, Gemini).

`codeburn` is exactly that join: it reads the session files every tool already writes on
disk (Claude Code + Codex + 34 more), and prices them via LiteLLM (refreshed daily). It is
the same *class* of tool the OS already depends on (`ccusage`) — a local Node CLI reading
session files — but **cross-tool**, so it is effectively a superset of `ccusage`. This skill
wraps it **for reporting only**.

## Reporting only — the three things this skill never does (binding)

codeburn has write and network surfaces the OS must not touch. Verified against source on
2026-07-22 (read-only Codex analysis + direct read):

1. **Never `sync`.** The `sync` feature does OIDC auth and POSTs OTLP usage batches —
   including `sessionId` and `project` — to a configured HTTPS endpoint
   (`codeburn/src/sync/push.ts`, `src/sync/auth.ts`). It is opt-in and needs a configured
   endpoint, but it exists: local telemetry must stay local. This skill runs read/report
   commands only.
2. **Never install `guard`.** `codeburn guard` writes `PreToolUse` / `SessionStart` / `Stop`
   hooks into `.claude/settings.json` and its PreToolUse hook returns
   `permissionDecision: 'deny'` past a hard USD cap (`src/guard/hooks.ts`, `src/guard/settings.ts`).
   That **duplicates `session_budget_check.py`** — keep the OS's own budget gate; never stack two.
   (Same reason: don't wire `codeburn budget --check` into hooks either.)
3. **Never `optimize --apply` on `~/.claude`.** Its "unused skills / agents / commands never
   invoked" archiver moves entries into `.archived` and edits `settings.json` / `~/.claude.json` /
   `CLAUDE.md` / a shell rc (`src/act/plans.ts`). It **will** flag the OS's rare-but-intentional
   skills (`/council`, `/spec`, `/kickoff`) as ghosts. Waste *findings* are useful input to
   `/retro`'s kill-list, but the **human confirms kills** (report-not-execute); this skill never
   passes `--apply`. (codeburn's apply is itself backed-up + journaled + drift-guarded, but the
   false-positive risk against this OS is the reason to keep it human-gated.)

## Install (mirrors the ccusage pattern)

Requires Node ≥ 22 — the same bar as `ccusage` / `ccstatusline`. Either:

```bash
npx codeburn report --help     # zero-install trial
npm install -g codeburn        # persistent, like ccusage
```

## Commands (verified against codeburn `src/main.ts`)

Unified spend for a window, machine-readable — `report` is the JSON-capable command
(`overview` is human tables only, no `--format`):

```bash
codeburn report --from <YYYY-MM-DD> --to <today> --format json                 # ALL tools, priced (the unified view)
codeburn report --from <start> --to <today> --provider codex  --format json    # the delegated tier cost_breakdown.py can't see
codeburn report --from <start> --to <today> --provider claude --format json    # cross-check against cost_breakdown.py
codeburn optimize --format json                                                # waste findings → /retro §3 (NEVER --apply)
```

`today` / `month` / `export` also accept `--format json`. `--period today|week|30days|month|all|lifetime`
is the alternative to an explicit `--from/--to` window.

## How `/retro` uses it (§1 + §3)

- **§1 Token review** — `codeburn report --provider codex --format json` replaces the manual
  `.codex-log` cat with **priced** Codex spend, and `--provider all` gives the unified
  Claude+Codex dollar figure `cost_breakdown.py` structurally cannot produce. Keep
  `cost_breakdown.py` for the Claude Opus/Sonnet split; codeburn adds the non-Claude tier +
  cost-per-accepted-change across all tools.
- **§3 Kill-list** — `codeburn optimize --format json` findings (ghost skills/agents/commands,
  unused MCP, bloated `CLAUDE.md`, junk/duplicate reads, low read:edit) seed the kill-list.
  The operator confirms; nothing is applied.

## Fallback

If codeburn is not installed, `/retro` keeps its existing manual `.codex-log` cross-check —
this skill is an upgrade to that step, not a hard dependency.

## Related

- `home/skills/retro/SKILL.md` — primary consumer (§1 token review, §3 kill-list)
- `project-template/scripts/cost_breakdown.py` — the Claude-only meter this complements
- `project-template/scripts/session_budget_check.py` — the budget gate codeburn must **not** duplicate
- `home/skills/ask-codex/SKILL.md` — the delegation whose spend (`.codex-log`) codeburn prices
