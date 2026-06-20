---
name: council
description: Adversarial decision review for one-way (hard-to-undo) doors and security-sensitive changes only. Spawn FOR / AGAINST / third-path jurors, synthesize into a decisions.md entry. Do NOT use for reversible work — debate costs 2-3× tokens.
allowed-tools: Task, Read, Grep, Glob, Write
---

# /council — Adversarial Review for One-Way Doors

Structured debate before an **irreversible** decision. Research finding: adversarial
council costs 2–3× tokens, so it earns its keep **only** where a wrong call is
expensive to undo.

`/council` is the **one-way-door branch** of the thinking-pipeline selector
(`.claude/rules/thinking-pipeline.md`) — it's where `/triz` (frame) and `/hats`
(evaluate) escalate to when the decision is irreversible or security-sensitive.
Typical full-pipeline order: `/triz` → `/hats` (subagent-per-hat) → `/council`.

## Gate (refuse otherwise)

Run **only** when the decision is:
- a 🟥 **one-way door** (DB schema / data migration, public/affiliate API contract,
  framework or DB swap, deleting price history, a published URL/slug scheme — see
  `.claude/rules/change-protocol.md` reversibility axis), **or**
- **security-sensitive** (`api/auth/*`, secret handling, authz boundary).

If the change is two-way (refactor, UI, reversible config/hook, doc), **decline**:
> "This looks two-way (cheaply revertable). Council is reserved for one-way doors and
> security — proceed with the normal flow + automatic gates. Run `/council` only if you
> believe this is actually irreversible."

## Akış

### Adım 1 — Frame the question
State the decision in one sentence + the irreversibility (what can't be undone, who
depends on it once shipped). Gather the minimal context the jurors need (the file(s),
the constraint, the alternatives already on the table).

### Adım 2 — Spawn jurors (parallel, cheap model)
Spawn **2–3 subagents in one message** (parallel). Use a cheap model (Sonnet) for
jurors — they argue a fixed position, no deep reasoning load:
- **FOR** — strongest case the proposed decision is right. Surface the upside, the
  cost of *not* doing it.
- **AGAINST** — strongest case it's wrong. Hunt the failure mode, the lock-in, the
  cheaper reversible alternative.
- **THIRD-PATH** (optional, for genuinely hard calls) — reframe: is there a two-way
  door that gets 80% of the value? A way to stage/flag it so it stays reversible?

Each juror returns: position, 2–3 concrete points, and the single fact that would
flip them.

### Adım 3 — Synthesize (this model, Opus)
Weigh the arguments. Do **not** just average — name the decisive consideration. Land
on: **proceed / proceed-with-mitigation / don't / defer-pending-X**. If a third-path
keeps the door two-way, prefer it (asymmetric cost favors reversibility).

### Adım 4 — Record in decisions.md
Append a `tasks/decisions.md` entry using the full ADR format, with:
- `**Alternatifler:**` = the juror positions, compressed.
- `**Reversibility:** one-way`
- `**Status:** Proposed` (→ Accepted once shipped & verified)
- `**Neden:**` = the decisive consideration from Adım 3.

### Adım 5 — Summary block (to chat)
```
═══════════════════════════════════════════
   /council — <decision, one line>
───────────────────────────────────────────
  Door:        one-way (<what's irreversible>)
  FOR:         <one line>
  AGAINST:     <one line>
  THIRD-PATH:  <one line or n/a>
  VERDICT:     proceed | mitigate | don't | defer
  Decisive:    <the one consideration>
═══════════════════════════════════════════
```

### Adım 6 — Shared output contract

`/council`'s output also satisfies the pipeline-wide contract
(`.claude/rules/thinking-pipeline.md`), so it composes with `/triz` and `/hats`
output rather than replacing it:

1. **Decision** + chosen option = Adım 3's verdict.
2. **Evidence per claim** — each juror point should be `file:line` / cmd output /
   commit, or tagged `⚠assumption`.
3. **Done-gates** — what "this one-way door is correctly shipped" means,
   deterministic, not a step list.
4. **Recorded dissent** — the losing juror position(s) are kept in the
   `decisions.md` entry, not dropped. On a one-way door, a juror's QA/Security-class
   objection is a **veto**, not just a data point.
5. **Model tier** — jurors = cheap model (Sonnet), synthesis = this model (Opus);
   record both.

## Kurallar

- **Jurors = cheap model, synthesis = this model.** Don't burn Opus on all three roles.
- **Decline reversible work** — the gate is the whole point; council everywhere is theater.
- **The decisive fact, not the vote count** — a 2-1 split can still go the minority way
  if the minority names a fact the majority ignored.
- **Output is a `decisions.md` entry**, append-only, `Status: Proposed`.

## İlgili

- `.claude/rules/thinking-pipeline.md` — lifecycle + selector (this skill is the
  one-way-door branch) + shared output contract.
- `.claude/rules/change-protocol.md` — reversibility axis (the gate).
- `tasks/decisions.md` — output destination (ADR format with Reversibility/Status).
- `/triz` — frames the contradiction/options before this debate.
- `/hats` — multi-role evaluation that often precedes or feeds this.
- `/retro` — surfaces one-way-door findings that escalate here.
