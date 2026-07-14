# Debugging — Root Cause Before Fix

> The diagnosis method. `/verify` answers *"is the repo mechanically healthy?"*; the
> QIPT+S battery ([thinking-pipeline.md](thinking-pipeline.md)) answers *"is my
> **claim** sound?"*. Neither answers **"why is this broken?"** — that gap is this
> file. Adapted from `obra/superpowers` `skills/systematic-debugging/`; quotes below
> are verbatim from its `SKILL.md`. Its TDD "iron law" is deliberately **not** adopted
> — rigor scales with reversibility, not dogma. PORTABLE.

## The rule

> "ALWAYS find root cause before attempting fixes. Symptom fixes are failure."
> — `SKILL.md:12`

A fix proposed before investigation is a **guess**. "If you haven't completed Phase 1,
you cannot propose fixes." (`SKILL.md:22`)

## The four phases

Complete each before the next ("You MUST complete each phase before proceeding to the
next." — `SKILL.md:48`). **Proportionality:** a trivial/two-way bug may run all four in
a minute in your head; a one-way / data-integrity / production bug runs them in writing.

1. **Root cause investigation** — read the ACTUAL error text (not your memory of it);
   reproduce it consistently; check recent changes (`git log -- <path>`); gather
   evidence at each component boundary; trace the data flow. Do not theorize before
   reading.
2. **Pattern analysis** — find a WORKING example of the same thing, compare against it,
   name the differences. Most bugs are "we do X everywhere else and Y here".
3. **Hypothesis + minimal test** — ONE hypothesis at a time, tested by the smallest
   change that could disprove it. If you don't know, say so and gather more evidence —
   don't shotgun.
4. **Implementation** — reproduce with a failing test where practical, then ONE change
   addressing the cause. `No "while I'm here" improvements` (`SKILL.md:184`) — unrelated
   cleanup is a separate commit (see [foundation.md](foundation.md): surgical changes).

## Stop signals — return to Phase 1

- You are proposing a fix before tracing the data flow.
- "One more fix attempt" after 2+ failures.
- Each fix reveals a new problem somewhere else.
- **3+ failed fixes = architectural problem.** Question the pattern; don't fix again.
- You are about to conclude "no root cause / it's just flaky":
  `**But:** 95% of "no root cause" cases are incomplete investigation.` (`SKILL.md:276`)
  Environmental / timing / external IS a valid conclusion — but only after a COMPLETE
  Phase 1, and then you document what you investigated and add real handling, not a retry.

## Three techniques worth naming

- **Trace back, don't patch the surface** — `**NEVER fix just where the error appears.**`
  (`root-cause-tracing.md:154`). Walk symptom → immediate cause → caller → caller's
  caller → original trigger.
- **Defense in depth (only AFTER the cause is known)** — validate at every layer the data
  crosses so the bug becomes structurally impossible. Pairs with the project's
  no-silent-failure rule and any fail-closed startup guard.
- **Condition-based waiting** — never `sleep(n)` to paper over a race; wait for the
  actual condition you care about. An arbitrary sleep is a symptom fix that will flake
  under load. Audit your own rules for prescribed sleeps — they are known debt, not a
  pattern to copy into new code.

## When this applies

"Use for ANY technical issue" (`SKILL.md:26`). "**Use this ESPECIALLY when:**"
(`SKILL.md:34`) you are under time pressure or a "quick fix" looks obvious.
"**Don't skip when:**" (`SKILL.md:41`) the issue *seems* simple or you're in a hurry —
simple bugs have root causes too.

It does **not** replace `/verify` (mechanical health) or the QIPT+S doublecheck (claim
soundness). It feeds them a *diagnosed cause* instead of a guess.
