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

**Task-start reflex (RULE): consider a cheaper-tier subagent BEFORE starting any
user-given task.** At the start of each task, make the routing call *explicit* — state
the item × model tier + a "dispatch / inline" verdict before doing the work, not after.
Default to **dispatching mechanical / bulk / multi-step / two-way work to a
`model: sonnet` subagent** — delegate by default; this is the goal, not the exception.
Keep on Opus (inline) only in one of these **three narrow cases**:

1. **Reasoning-heavy / one-way** — the task needs algorithmic / data-integrity /
   architectural judgment, or is a one-way (hard-to-undo) door.
2. **Trivial edit** — a genuinely trivial 1–2 line / single-token change where a cold
   subagent's file re-read costs *more tokens* than the edit itself. Delegation's
   purpose is token economy; for these it is net-negative.
3. **Context-bound** — work whose inputs live in *this session's* history (open threads,
   a decision just made, a diff under discussion) that a cold subagent would have to
   expensively re-derive and would still likely miss.

The unifying test is **token economy + correctness**, not "delegate everything": if a
fresh-context subagent would cost more than inline OR would lose information that only
lives in this conversation, do it inline — otherwise dispatch. **When in doubt,
dispatch. Do not silently default to inline-on-Opus.**

**The design/execution split governs ALL THREE cases (binding).** The three exceptions
justify doing the *thinking* inline — framing, deriving the discriminator/algorithm, the
decision. **They do NOT license inline *execution*.** Whichever case applies, once the
approach is decided the design output IS a portable brief, so writing the edits + tests
**defaults to a `model: sonnet` dispatch** + an Opus doublecheck of the diff. This is the
loophole that repeatedly eats whole sessions: "reasoning-heavy"/"data-integrity" (case 1)
and "context-bound" (case 3) get stretched to inline the *execution*, not just the design
— so patching only one case leaves the exploit open via relabeling. The split is top-level.

Four anti-exploit clamps (each closes a way the above gets gamed):
- **Per-task, not per-edit.** N individually-trivial edits across one task are ONE
  dispatchable batch — not N case-2 exceptions. Case 2 is a *lone* 1–2 line edit, never
  a mechanical session of them (one subagent amortizes the file re-read across all N).
- **Commit-message test for "context-bound."** If you can write the change's commit
  message + code comments, you can write the subagent brief — it is specifiable, so
  dispatch.
- **Pre-commit the exception.** Before the first execution edit of a task, state in one
  line which case applies and why; no stated case = dispatch. Trip-wire: the first edit
  of a task going to `Edit` not `Agent` = the gate was skipped.
- **Genuine execution-inline is narrow** — only discovery-driven work where each edit
  depends on the *result* of the previous one (a real ping-pong that cannot be
  pre-specified), or a single trivial edit. **If you can list the edits up front, it is
  not execution-inline** — dispatch them.

**Residual gap (honest, not closable by text):** this rests on self-classification —
there is no referee in the moment, and the rule being *loaded in context* is not enough
on its own. The clamps raise the cost of gaming it; they cannot remove it. Treat *"this
classification is convenient"* as the tell to dispatch anyway.

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
6. **Measurement claims name their instrument + its blind spots.** Any usage / absence /
   spend claim states (a) WHICH instrument produced it (a cost CLI, a grep pattern, an
   audit trail, a scorecard) and (b) that instrument's known blind spots (e.g. a grep for
   one field cannot see a different field; a grep for user-typed commands misses
   model-initiated ones). **Absence claims state the exposure denominator** — "0
   recurrences" over ~0 exposure is not a track record. An instrument whose own failure
   mode inflates the bucket it reports is quarantined evidence until fixed.
   **Shell plumbing is an instrument too — exit-code evidence is read UNPIPED**: `$?`
   after `cmd | tail` reports *tail's* status, not cmd's, so the check is structurally
   unable to fail. When the exit code IS the evidence: `cmd > out.log 2>&1; echo $?`, or
   capture `rc=$?` on the immediately following line before anything else runs.
7. **Kill-criterion (pre-registration)** — alongside its done-gates, every plan states
   what would make the task INVALID or not-worth-doing ("kill if X"), written BEFORE
   building — goalposts committed before there's a stake in the outcome. A plan with
   done-gates but no kill-criterion has only registered how to succeed, not how to
   notice it shouldn't.

## === Section: Doublecheck — battery, stance, routing ===

Doublecheck is a first-class step, not an afterthought — it is where this workflow's
value repeatedly comes from (the validated Opus-rechecks-Sonnet pattern, where scope
misses surface at the doublecheck step rather than slipping through execution).

**Battery (QIPT+S)** — ONE pass walks the claim's dependency chain up (serial passes
that each find one link are the failure mode this replaces):
- **Q**uestion — did my framing/prompt filter what could come back?
- **I**nstrument — lossy tool? paraphrase-as-quote? Tag every source's fidelity.
- **P**remise — is the task itself still valid (pending AND strategy-aligned)?
- **T**ransfer — does the pattern hold in THIS context, or only where it came from?
- **S**take — checking to find truth, or to confirm what I hoped? (Catching yourself
  justifying a skip IS the trip-wire.)

**Stance + target** — frame every pass as "break this," aimed at the most CONFIDENT
load-bearing claims (the unmarked "obvious" ones), not the pre-hedged ⚠ ones. A pass
that returns "looks good" without trying to break anything hasn't checked.
**Independence** — a second look is worth its independence from the first (instrument /
framing / checker / time axes). Correlated agreement = false confidence, not verification.
**Stopping rule** — a pass surfacing no NEW failure class = done; cap ~3 passes.

**Routing** (proportionality: battery at meaningful+ selector tiers; trivial/two-way
keeps a shallow self-check):
- two-way / Opus-authored → **self-doublecheck** against the done-gates before commit.
- one-way door OR Sonnet-executed → **Opus doublecheck** pass (the validated
  Opus-rechecks-Sonnet pattern: misses surface at the scope step, not execution).
- **Premise external-routing** — stake in the answer OR a premise resting on an
  instrument you can't independently re-verify → route the premise to an external
  check: the human · a fresh juror subagent · a model-switch doublecheck.
