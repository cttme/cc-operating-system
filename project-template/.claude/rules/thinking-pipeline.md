# Thinking Pipeline — Lifecycle, Selector, Output Contract

> PORTABLE kernel feature — the "how to think before acting" spine.
> Companions: [change-protocol.md](change-protocol.md) (reversibility doors),
> [foundation.md](foundation.md) (twin-gate, verify-first). Tools it routes to:
> `/triz` (frame), `/hats` (evaluate), `/council` (decide).

## === Section: Per-task lifecycle ===

Every non-trivial task flows through these stages. `frame` and `doublecheck` are the
two stages the old workflow silently skipped — they are where most missed-scope and
wrong-problem errors were caught.

```
onboard → frame → plan → decide → execute → verify+doublecheck → commit → reflect
```

| Stage | Tool | Purpose |
|---|---|---|
| onboard | `/onboard` | load state, surface next task |
| **frame** | `/triz` | state the contradiction + Ideal Final Result; don't accept a trade-off you can dissolve |
| plan | `/plan`, `/spec` | step plan; claims evidence-cited (verify-first) |
| decide | `/hats`, `/council` | evaluate from roles / adversarial decide |
| execute | (model-routed) | do the work at the right model tier |
| verify + **doublecheck** | `/verify` | mechanical battery + gap hunt against done-gates |
| commit | (pre-commit gate) | gated; **closing a task edits todo.md in the same commit** |
| reflect | `/retro` | write lessons back to the kernel (rules/memory) |

## === Section: Selector — which rigor for which task ===

Rigor scales with **reversibility × stakes**, not with which file changed. When unsure,
treat as one-way (cost of over-rigor = minutes; cost of an un-undoable mistake is not).

| Situation | Pipeline | Model tier |
|---|---|---|
| trivial / two-way | **skip** — just do it | Sonnet / local |
| meaningful / two-way | **lightweight inline**: `/triz` frame + `/hats` quorum (single pass) | Sonnet (Opus if algo / data-integrity) |
| one-way door OR major bet | **full pipeline**: `/triz` + `/hats` (subagent-per-hat) + `/council` + `tasks/decisions.md` entry (`Reversibility: one-way`) | Opus |

**Executing at a lower tier — dispatch, don't switch.** When work routes to Sonnet
but the main session is on Opus, send it to a **subagent** (`model: sonnet`) rather
than switching the main session's model. A mid-session model switch invalidates the
model-scoped prompt cache (the whole transcript is re-read uncached, twice if you
switch back), and the work's churn bloats the main context. A subagent runs in a
fresh small context, keeps the main cache intact, and returns only a summary. Give
it a self-contained brief (a spec file) so it needs no conversation history.

## === Section: Shared output contract ===

Every thinking tool (`/triz`, `/hats`, `/council`) and every plan emits:

1. **Decision** + chosen option.
2. **Evidence per claim** — `file:line` / command output / commit hash — OR an explicit
   `⚠assumption` tag. An unverified claim is a placeholder, not a plan line.
3. **Done-gates** — deterministic ("done = X AND Y"), not a step list.
4. **Recorded dissent** — any role/juror objection is kept, not dropped. Reversibility
   authority: a QA or Security objection is a **veto on one-way doors**, advisory on two-way.
5. **Model tier** used + recommended for execution.

## === Section: Doublecheck routing ===

Doublecheck is a first-class step, not an afterthought — it is where this workflow's
value repeatedly comes from (the validated Opus-rechecks-Sonnet pattern, where scope
misses surface at the doublecheck step rather than slipping through execution).

- two-way / Opus-authored → **self-doublecheck** against the done-gates before commit.
- one-way door OR Sonnet-executed → **Opus doublecheck** pass (the validated
  Opus-rechecks-Sonnet pattern: misses surface at the scope step, not execution).
