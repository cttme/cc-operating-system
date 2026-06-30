---
name: plan
description: Structured implementation plan for two-way (reversible) 3+ step work — before coding. Explore the code, list affected files, cite evidence per claim, emit deterministic done-gates, and make the model-routing call. One-way doors use /spec instead; trivial work skips planning.
allowed-tools: Read, Write, Grep, Glob
---

# /plan — Structured Implementation Plan (two-way work)

A plan is worth its overhead for **meaningful, multi-step, reversible** work. It is the
`plan` stage of the thinking pipeline (`.claude/rules/thinking-pipeline.md`).

## When to use

- **Use** for 3+ step two-way (cheaply revertable) work — a feature, a refactor, a
  multi-file change.
- **One-way door** (schema, public/affiliate API, data migration, published URL/slug) →
  use `/spec` instead; the written spec becomes the acceptance contract.
- **Trivial / single-edit** → skip planning, just do it (`/triz` first only if a
  trade-off looks "accepted" rather than examined).

## Steps

0. **Verify-before-building** (do this FIRST — `.claude/rules/verify-before-building.md`).
   A backlog/handoff line is a *claim*, not a fact. Before planning to build X, confirm X
   isn't already done: grep the named symbol/string, `git log --oneline -- <path>`, and
   check whether the backend already provides the data. Cite what you found.
1. **Understand the request** — restate the *intent* and the done condition, not just the
   literal ask.
2. **Explore the code** — Glob + Grep + Read. A file >200 lines to read → dispatch
   `Explore`. Read `<dir>/index.md` before the file (token discipline).
3. **List affected + new files** — what changes, what's created.
4. **Implementation steps** — files changed, new files, tests to write, migrations needed.
5. **Risk analysis** — classify each change's reversibility (one-way / two-way per
   `change-protocol.md`); flag breaking changes, data-loss risk, perf budget.
6. **Routing call** — for each chunk of work, state item × model tier + a dispatch/inline
   verdict (thinking-pipeline selector). Default: dispatch mechanical/bulk work to a
   `model: sonnet` subagent; keep reasoning-heavy / one-way / context-bound work inline.

## Output contract (every plan emits)

1. **Decision** + the chosen option (and why over alternatives).
2. **Evidence per claim** — `file:line`, a command's output, or a commit hash — OR an
   explicit `⚠assumption` tag. An unverified claim is a placeholder, not a plan line.
3. **Done-gates** — deterministic: "done = X AND Y", not a restatement of the steps.
4. **Recorded dissent** — keep any objection (a QA/Security concern is a veto on one-way
   doors, advisory on two-way); don't silently drop it.
5. **Model tier** used to plan + recommended for execution.

## Finish

- Append the plan to `tasks/todo.md`.
- Present the plan and **wait for approval — do not start implementing unapproved.**
