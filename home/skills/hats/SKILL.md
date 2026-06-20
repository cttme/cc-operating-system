---
name: hats
description: Evaluate a decision or plan from multiple role perspectives (CTO, PM, QA, Designer, Ops, Skeptic), each asking its own distinct question. Use at the decide stage for meaningful work, lightweight inline by default, subagent-per-hat for one-way doors. Not for trivial/two-way work.
allowed-tools: Task, Read, Grep, Glob
---

# /hats — Evaluate from Roles

Multi-perspective review of a plan or decision, each hat asking a question the
others don't. The value is in the **distinct questions**, not in roleplay — a hat
that just repeats "looks good" is a wasted pass.

## When

Decide stage, for meaningful work — see the selector in
`.claude/rules/thinking-pipeline.md`. Skip for trivial/two-way tasks.

## Roles (each asks its own question)

| Hat | Question |
|---|---|
| **CTO** | Is this the right bet? What's the reversibility, the leverage, the debt it creates? |
| **PM** | Is this the priority right now? What's the smallest valuable version? |
| **QA** | How does this break? How do we know it's actually done (done-gates, not vibes)? |
| **Designer** | Is it usable? Copy, accessibility, flow clarity. **Abstains** on backend-only work — say so, don't force an opinion. |
| **Ops** | Is it reliable and affordable to run? Deploy path, cost, recovery if it fails. |
| **Skeptic** | Why is this wrong, or why not do it at all? YAGNI check — what's the cost of doing nothing? |

**Swap-ins** when the default six don't cover the risk surface: User/Customer hat,
Security hat (use the `security-auditor` agent-type for this one, not a generic
persona), Data hat.

## Quorum

- **Default:** CTO + PM + QA + Skeptic.
- **+Designer** when the change touches UI/copy/UX.
- **+Ops** when the change ships or runs something (deploy, cron, new service).

Don't run hats that have nothing to say — an abstention is a valid, recorded
output (see Designer above), not a reason to skip the abstention itself.

## Modes

- **Lightweight inline (default):** one paragraph per hat, single pass, done in
  this same context — no subagent spawn. Use for meaningful/two-way work.
- **Subagent-per-hat:** spawn one subagent per hat in parallel, each with a
  distinct persona prompt (reuse existing auditor agent-types where they map —
  e.g. `security-auditor` for the Security swap-in). Use for **one-way doors**
  per the selector — the cost of a missed objection is asymmetric there.

## Synthesis → output (the shared contract)

After collecting hat responses, synthesize — don't just concatenate:

1. **Decision** — the verdict each hat converges on, or the closest consensus.
2. **Evidence per claim** — `file:line` / command output, or `⚠assumption`.
3. **Done-gates** — QA's "how do we know it's done" becomes the deterministic gate.
4. **Recorded dissent** — every hat's objection is kept even if overruled.
   **Reversibility authority:** a QA or Security objection is a **veto** on a
   one-way door, advisory only on a two-way door (see `change-protocol.md`).
5. **Model tier** used + recommended for execution.

## Kurallar

- **Distinct questions, not distinct voices.** If two hats would say the same
  thing, merge them — don't pad the pass count.
- **Dissent is data.** Do not silently drop a hat's objection because the
  majority disagreed — record it, then apply the reversibility-authority rule.
- **Designer abstaining is a result**, not a skip — note it explicitly so a
  reader knows it was considered, not forgotten.

## İlgili

- `.claude/rules/thinking-pipeline.md` — lifecycle + selector + shared contract.
- `.claude/rules/change-protocol.md` — reversibility axis (dissent authority).
- `/triz` — produces the framed options this evaluates.
- `/council` — escalation for one-way doors needing adversarial debate on top.
