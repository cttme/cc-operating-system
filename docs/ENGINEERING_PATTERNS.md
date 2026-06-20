# Engineering Patterns — Cross-Project Playbook

> Universal truths distilled from `tasks/lessons.md` across projects. **These are not
> project rules** (those live in `.claude/rules/`) — they're stack-agnostic engineering
> habits that earned their place by recurring.
>
> **Promotion gate:** a pattern lands here only after it has shown up in **2+ projects**
> (or recurred `Count ≥ 2` within one and is clearly not a quirk of that domain). This
> guards against over-generalizing a single project's accident into a "law". `/retro`
> §5 sorts each lesson project-specific vs universal; only the universal ones graduate.

---

## Process

### Instrument before you optimize
"Improve X" is blind until X is measured. Build the smallest honest meter first, then
let the data pick the lever. *(düzhesap Phase A: "improve tokens" → measured → found 97%
is model-mix, not the assumed resume-tax; the real fix followed the number.)*

### Rigor scales with irreversibility, not file importance
Classify each change as a **one-way** (hard-to-undo: schema, public API, data migration,
published URLs) or **two-way** door (refactor, UI, reversible config). Spend the
expensive ceremony (spec, council, backups) on one-way doors; keep two-way work fast.
When unsure, treat as one-way — over-rigor costs minutes, an un-undoable mistake doesn't.

### Honest reporting > optimization theater
A session that legitimately needs no routing/triage/audit should report zero, not
manufacture activity to look busy. Forcing a tool to fire because "the trigger exists"
is theater. The same applies to a retro/audit that "changes nothing" — look harder or
say so plainly.

### 2-pass gap analysis for medium+ stakes
For any multi-file, security-touching, or 60+ minute plan: (1) write → find gaps → fix;
(2) re-read the *updated* plan → find more gaps → fix; (3) verify each fix landed. The
second read catches what the first one's momentum hid.

### Verify after each discrete action, not in a batch at the end
Each edit / commit / migration / backup → confirm immediately before the next. ~3 s per
item; the payoff is catching a plan gap the moment it surfaces instead of unwinding a
batch. Batched end-verification reliably misses one.

---

## Correctness

### No silent failure
`except: pass`, `EXCEPTION WHEN OTHERS`, `.catch(() => {})`, swallowed migration errors —
all banned. A failure that doesn't surface is rediscovered weeks later at higher cost.
Conditional skips must be **explicit** (`IF NOT EXISTS … THEN RETURN`), never a swallowed
catch-all.

### Grep the consumers before changing a contract
Before collapsing a schema field, renaming a key, or changing what a function emits,
grep every consumer outside the producer (`*.py`, `*.ts`, `*.tsx`, **and** `tests/`).
Zero hits → safe to change. One+ hits → keep + adapt. Don't pre-judge by the field's
name; the grep is cheap and decisive. *(Recurred across multiple düzhesap sessions.)*

### Eyeball before you delete (dead-code)
A reference count of 2 is not proof of "dead". Look at each occurrence — `console.error("x")`,
`@see x` in a docstring, a deprecation comment all inflate the count without being real
callers. Count ≥ 3 usually means real callers; count = 2 → read them.

---

## Environment / Ops

### "Healthy" ≠ "correct"
A container reporting healthy means a port is open, not that behavior is right. The
canonical signal is an app-level smoke test (`curl /health` → 200, a real query), not a
port check. Verify behavior, not liveness.

### Test fixtures must be tracked in version control
Local-only data state means a fresh clone fails. Commit fixtures; a `skip-if-missing`
guard is graceful degradation, not a substitute for the file being in git.

### Don't comment what you deleted
When removing code, remove the comments describing it too. If the "why" matters, it goes
in the commit message (`git blame`/`git log` preserve it) — not a comment block that goes
stale and lies.

---

_Seeded 2026-06-14 from düzhesap (Workflow OS Phase D3). Add a pattern only when it
clears the 2+-project promotion gate; cite the projects/lessons in the entry._
