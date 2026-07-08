---
name: ask-codex
description: Delegate a well-specified, self-contained coding/edit task to the OpenAI Codex CLI (gpt-5.5 agent), treating it as a subagent — Claude plans, Codex edits, Claude doublechecks the diff and tells Codex what to fix. Use with a crisp spec and a verifiable done-state. Never for ambiguous, architectural, or one-way-door decisions — those stay with Claude.
allowed-tools: Bash, Read, Write
---

# /ask-codex — Delegate implementation to OpenAI Codex (gpt-5.5 · treat as a subagent)

The OpenAI Codex CLI is wired in as an autonomous coding agent. It **edits files and
runs commands** to carry out a task, then hands back a diff. This skill is the division
of labor: **Claude plans and does the extensive thinking; Codex does the editing.**
Claude treats Codex exactly like a subagent — delegate a crisp task, doublecheck the
result, hunt for gaps, and either tell Codex what to fix (`-Resume`) or finish the job
in-repo if Codex was cut off.

**Why this saves tokens:** Codex's read/edit/iterate loop never enters Claude's context
window — only the summary + change list + last message come back. It saves **Claude
context tokens**, not money: spend shifts to your OpenAI quota. So route work here for
*context hygiene and execution*, not to make a task cheaper overall.

**This is the opposite tier from `/ask-local`.** ask-local routes cheap, single-shot,
**non-code** work to a free local model and forbids code/tool-use. ask-codex is for
exactly the code/tool-use work ask-local refuses — but only once Claude has decided
*what* to build. Codex executes decisions; it does not make them.

## The subagent loop

```
Claude writes a SELF-CONTAINED spec  ─►  ask-codex (workspace-write, direct edit)
        ▲                                          │
        │                              returns: status, session, diff-stat, last msg
   gaps found?                                     │
        │                                          ▼
   YES ─┤◄── Claude doublechecks diff + hunts gaps ◄─ status=completed
        │                                          │
        │                              status=truncated / error
        └─► -Resume <session> "fix X, Y"           │
                                                    ▼
                                    Claude finishes the job in-repo
                                    (Codex's partial edits already on disk)
```

## When to delegate — the routing gate

**Delegate only when the design is already decided and the done-state is verifiable.**
The value of a delegation equals the quality of the spec you hand over (see *Context
boundary* — Codex starts cold). If you cannot write the task down completely and name how
you'll know it's done, it is not ready to delegate — keep it in Claude.

### 🟢 GREEN — delegate freely (spec-driven, mechanical)

The design is fixed; the work is typing. Claude reviews the diff after.

| Intent | Examples | Doublecheck by |
|---|---|---|
| Implement to a written signature/spec | fill a function body to a given signature + docstring · implement an interface Claude defined | read diff · run tests |
| Mechanical refactor across files | rename/move a symbol repo-wide · apply a documented pattern to N files · extract helper | read diff · build |
| Boilerplate / scaffolding | new module skeleton · CRUD wiring of an existing pattern · config/fixture files | read diff |
| Bulk find-and-fix | apply a lint rule · migrate a deprecated call site-wide · add null-checks per a list | read diff · lint |

### 🟡 YELLOW — delegate with a tight spec + mandatory close review

Codex *can* do these, but the blast radius is larger — the design must be **fully fixed
by Claude first**, and the diff review is not optional.

| Intent | Examples | Guardrail |
|---|---|---|
| Multi-file feature, design decided | wire a feature whose shape/contract Claude already specified | review every hunk · run tests |
| Test authoring from named cases | implement tests for a case list Claude wrote | Claude confirms cases match intent |
| Perf/cleanup pass with a target | apply a specific optimization Claude identified | benchmark / verify behavior unchanged |

### 🔴 RED — never delegate, always Claude (the line does NOT move)

Codex is a capable agent, which makes a confident-wrong edit *more* expensive, not less.

- **Architecture / design decisions** — anything where *what to build* is still open
- **One-way doors** — schema, public API, data migration, published URLs → use `/spec`
- **Ambiguous requirements** — if the spec isn't self-contained, delegating exports the
  ambiguity to an agent that can't ask you; it will guess
- **Anything where a wrong edit is expensive or invisible to catch** — security/auth,
  money/pricing, legal/compliance, data-integrity decisions
- The **plan itself** — planning, sequencing, and trade-off reasoning stay with Claude;
  Codex receives the conclusion, not the deliberation

## Context boundary — how deep is Codex's context?

- **Codex starts a COLD session.** It does **not** see Claude's conversation, the plan,
  or Claude's reasoning. It has only its own `~/.codex` config + `AGENTS.md`, and the repo
  files it reads itself. → **The spec must be fully self-contained.** Serialize every
  decision, constraint, file path, and done-condition into the `-PromptFile`.
- **Depth across turns comes from `-Resume`.** Codex retains its own working context
  between fix-iterations, so you don't re-explain what it already did.
- **The return trip stays shallow on purpose.** You get back the summary, a change list
  (`git status --short`), and Codex's last message — then read only the hunks you need.
  Never pull a full diff into context reflexively; that defeats the token goal.

## How to call

From Claude Code (Bash tool). Prefer `-PromptFile` — the spec is multi-line and
self-contained, and a file avoids all CLI-escaping issues.

### CMD (Windows native)
```cmd
scripts\ask-codex.bat -Intent "impl rate limiter" -PromptFile C:\path\to\spec.txt
```

### PowerShell
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ask-codex.ps1 `
  -Intent "impl rate limiter" -PromptFile C:\path\to\spec.txt
```

### Required parameters
- `-Intent` — short free-text label, used for logging and audit. Always set this.
- `-Prompt` / `-PromptFile` — the **self-contained** task spec (use the file form).

### Optional parameters
- `-Resume <thread_id>` / `-ResumeLast` — continue a prior Codex session with fix
  instructions (the iterate path). Use the explicit `session=` value from the summary —
  prefer it over `-ResumeLast`, which grabs the globally most-recent session (fragile when
  runs across projects interleave). Pass the **same `-ProjectRoot`** as the original run:
  a resumed session runs in the working directory the wrapper sets, not a remembered one.
- `-Sandbox read-only|workspace-write|danger-full-access` — default `workspace-write`
  (edits confined to the workspace). Use `read-only` for "analyze/explain, don't touch."
  `danger-full-access` only on explicit user request.
- `-NoNetwork` — disable sandbox network access (default: **on**, so installs/fetch work).
- `-ProjectRoot <path>` — working root passed to `codex --cd` (default: current dir).
- `-Model <name>` — override the model (default: inherits `~/.codex/config.toml`, gpt-5.5).
- `-TimeoutSec <n>` — kill a runaway run (default 900). On expiry → `status=truncated`.
- `-NoLog` — do not write the call to `.codex-log` (privacy-sensitive specs).

## Output contract

```
---CODEX-CALL-SUMMARY---
intent=.. | model=.. | sandbox=workspace-write | status=completed | session=<thread_id> |
  files_changed=3 | ~<in>/<out> tok | <dur>s | exit=0 | ckpt=<sha>
---CODEX-DIFF-STAT---
<git status --short — the change list, non-mutating>
---CODEX-OUTPUT---
<Codex's last message / blockers>
```

**Always read the summary line first.** `status` drives what you do next:
- `completed` — Codex finished a turn. Doublecheck the diff, then accept or `-Resume` fixes.
- `truncated` — cut off (timeout / token limit) before finishing. Codex's partial edits
  are already on disk → **Claude takes over and finishes in-repo** (or `-Resume` if close).
- `error` — codex exec failed (exit ≠ 0); read the message, fix the setup, retry.

On any non-`completed` status the wrapper also prints a `---CODEX-RECOVERY---` block with
the ready `-Resume` command and a destructive `git reset --hard <ckpt>` discard option.

## Decision rules (binding)

1. **Never delegate a decision — only an execution.** If *what to build* is unsettled,
   plan in Claude first (`/plan`, or `/spec` for one-way doors). Codex gets the conclusion.
2. **Write the spec self-contained.** Codex is cold (see *Context boundary*). Include file
   paths, constraints, the exact done-condition, and "don't do X" guardrails. Vague spec →
   Codex guesses.
3. **The diff review is mandatory.** Codex is write-capable; treat every run's output like
   a subagent's PR — read the change list, hunt for gaps, verify the done-condition. Reach
   for `/code-review` when a deeper pass is warranted.
4. **Iterate with `-Resume <session>`, don't cold-restart.** When review finds gaps, resume
   the same `session` id (from the summary) with a focused fix list so Codex keeps its
   context. Pass the same `-ProjectRoot`; avoid `-ResumeLast` when projects interleave.
5. **On `truncated`, decide fast: resume or take over.** If Codex was close, `-Resume`.
   If it's thrashing or the remaining work needs Claude's reasoning, finish in-repo — the
   partial edits are already on disk and the change list shows exactly where it stopped.
6. **Keep secret-bearing dirs out.** Codex sends workspace code to OpenAI (see *Data
   egress*). Point `-ProjectRoot` at the code that needs editing, nothing more.

## Common patterns

### Spec-driven implementation (the core pattern)
```
1. Claude plans + writes spec.txt: signature, constraints, files, done-condition.
2. ask-codex -Intent "impl X" -PromptFile spec.txt
3. Read ---CODEX-DIFF-STAT---; read the changed hunks; run tests.
4. Gaps? -> ask-codex -Intent "impl X (fix)" -Resume <session> -PromptFile fixes.txt
   Clean? -> accept.
```

### Read-only analysis (no edits)
```
ask-codex -Intent "explain auth module" -Sandbox read-only `
  -PromptFile question.txt
# Codex reads the repo and answers; nothing is written. Claude finalizes.
```

## Failure modes to watch

- **`status=completed` but the job isn't done.** Codex ends a turn even if it under-did
  the work. The mandatory diff review catches this — never trust `completed` alone.
- **`status=truncated` with `files_changed>0`.** Half-applied edits on disk. Review the
  change list; resume or finish in-repo. Never assume the tree is consistent.
- **`session=` empty on a truncated run.** Very early kill before `thread.started`. Can't
  resume — re-run fresh or take over.
- **Codex edited outside the intended scope.** Compare the change list to the spec; use the
  `git reset --hard <ckpt>` recovery hint to discard and re-spec with tighter guardrails.
- **Codex CLI not found (exit 2).** Set `$env:CODEX_BIN`, add codex to PATH, or reinstall.
  Fall back to Claude for the task and flag in handoff.

## Related

- `scripts/ask-codex.ps1` — primary worker (dynamic codex resolution, status detection)
- `scripts/ask-codex.bat` — CMD wrapper
- `scripts/fixtures/codex-exec-sample.jsonl` — the real `codex exec --json` event shape
- `.codex-log/<session>/calls.jsonl` — per-session audit trail (tokens, status, ckpt)
- `ask-local` — sibling: free local model for cheap, single-shot, **non-code** work
- `/code-review` — deeper review pass over Codex's diff when warranted
- `/plan`, `/spec` — where the decisions Codex executes get made (RED work stays here)
