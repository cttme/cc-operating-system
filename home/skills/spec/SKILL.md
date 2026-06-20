---
name: spec
description: Spec-first ritual for ONE-WAY-DOOR features only (schema, public API, data migration, published URLs). Scaffolds specs/NNN-feature/ with spec.md (EARS notation) → plan.md → tasks.md. The spec becomes the acceptance contract /verify checks. Reversible work skips this and stays fast.
allowed-tools: Read, Glob, Grep, Write, AskUserQuestion
---

# /spec — Spec-First for One-Way Doors

A written spec is worth its overhead **only** when the thing being built is expensive to
undo — a schema, a public/affiliate API contract, a data migration, a published URL
scheme. For reversible work (internal refactor, UI tweak, config) the spec *is* the
cost; skip it and just build.

## Gate (refuse otherwise)

Run only when the feature is a 🟥 **one-way door** (see `.claude/rules/change-protocol.md`
reversibility axis). If it's two-way, decline:
> "This looks two-way (cheaply revertable). Spec-first is reserved for one-way doors —
> schema, public API, data migration, published URLs. Build it directly + `/verify`;
> run `/spec` only if a wrong shape here would be expensive to undo."

## Akış

### Adım 1 — Confirm one-way + pick the number
```bash
ls -d specs/*/ 2>/dev/null | sed 's#.*/specs/##; s#/##' | sort | tail -3   # last NNN
```
Next number = max + 1, zero-padded 3 digits. Slug from the feature name.
`specs/NNN-<slug>/`.

### Adım 2 — Write `spec.md` (EARS notation)
**EARS** = Easy Approach to Requirements Syntax. Every requirement is one of:
- **Ubiquitous:** "THE <system> SHALL <response>."
- **Event:** "WHEN <trigger> THE <system> SHALL <response>."
- **State:** "WHILE <state> THE <system> SHALL <response>."
- **Unwanted:** "IF <condition> THEN THE <system> SHALL <response>."
- **Optional:** "WHERE <feature> THE <system> SHALL <response>."

```markdown
# Spec NNN — <feature>

## Why (one-way door)
<what becomes irreversible once shipped; who depends on it>

## Requirements (EARS — testable, numbered)
- R1. WHEN <trigger> THE <system> SHALL <response>.
- R2. IF <bad input> THEN THE <system> SHALL <safe response>.
- R3. THE <system> SHALL <invariant>.

## Out of scope
- <explicitly not building>

## Acceptance (what /verify checks)
- [ ] R1 covered by <test / observable>
- [ ] R2 covered by <test>
- [ ] back-compat: <existing contract still honored>
```
Each requirement must be **testable** — if you can't name the check, it's not a spec
requirement, it's a wish.

### Adım 3 — Write `plan.md`
Translate requirements → approach: files to touch, the migration/back-compat strategy,
the order of operations, the rollback. Reference R-numbers so plan ↔ spec stay linked.

### Adım 4 — Write `tasks.md`
Ordered, checkbox tasks, each tagged with the R-number(s) it satisfies. This is the
build checklist. Keep tasks small enough to verify individually (per the verify-each-
discrete-action habit).

### Adım 5 — Build, checking off tasks.md
Implement task by task. After each, verify against its R-number. One-way-door work also
warrants a `/council` pass on the core design decision before the first irreversible
commit.

### Adım 6 — `/verify` against the spec
The spec's **Acceptance** block is the contract. `/verify` (or the relevant tests)
confirms every acceptance item before the feature is "done". Update `Status` of the
decision entry to `Accepted` once green.

### Adım 7 — Record decision
Append a `decisions.md` entry: link `specs/NNN-<slug>/`, `Reversibility: one-way`,
`Status: Accepted`, Outcome = which acceptance items passed.

## Kurallar

- **One-way doors only.** The gate is the value — spec-everything is the ceremony this
  is meant to avoid.
- **Testable requirements or it's not a requirement.** EARS forces a trigger + response;
  if you can't write the check, refine until you can.
- **Spec is the contract `/verify` checks** — not decoration. Keep spec ↔ plan ↔ tasks
  linked by R-number.

## İlgili

- `.claude/rules/change-protocol.md` — reversibility axis (the gate).
- `/council` — design review for the core one-way decision (Adım 5).
- `/verify` — checks the Acceptance block (Adım 6).
- `tasks/decisions.md` — decision entry (Adım 7).
- `/kickoff` — project-zero constitution; `/spec` is per-feature, `/kickoff` is per-project.
