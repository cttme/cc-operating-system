---
name: triz
description: Frame a non-trivial problem before planning — surface the real contradiction, the Ideal Final Result, and 2-3 evidence-cited options. Use at the frame stage, before /plan, whenever a trade-off looks "accepted" rather than examined. Not for trivial/two-way work.
allowed-tools: Read, Grep, Glob
---

# /triz — Frame + Generate

Dissolve trade-offs, don't accept them. Most "we have to choose between A and B"
framings hide a contradiction that can be resolved rather than traded — TRIZ's
core move applied to software framing instead of mechanical engineering.

## When

Frame stage, before `/plan`, for non-trivial work — see the selector in
`.claude/rules/thinking-pipeline.md`. Skip for trivial/two-way tasks (just do it).

## Primitives (only these five — see Kurallar for what's excluded)

1. **Contradiction** — state it precisely: improving A worsens B, or the
   requirement is "must be X and must be ¬X." Naming the contradiction sharply is
   usually the actual unlock; a vague contradiction produces a vague IFR.
2. **Ideal Final Result (IFR)** — describe the function delivered with zero added
   cost/harm/complexity, as if a perfect mechanism already existed. Don't ask "how"
   yet — ask "what would 'just having it' look like."
3. **Resources** — can the system solve this with what it already has (an existing
   field, an existing service, an existing index) before reaching for something new?
4. **9-windows** — scan sub-system / system / super-system × past / present / future.
   Used to find context gaps: a constraint that lives one level up or down from
   where you're currently looking (e.g. the real constraint is in the caller, not
   the function; or it was a deliberate past decision, not an oversight).
5. **Size-Time-Cost extremes** — thought experiment: what if this had to handle
   1000x the scale? Zero budget? Had to ship in an hour? Extremes shake loose
   assumptions that look load-bearing but aren't.

Optional, software-specific 8-principle prompt list (use only if a primitive above
stalls): segmentation, the-other-way-round, prior-action/precompute, nesting,
dynamization, intermediary, self-service, copying.

## Output (the shared contract — see `.claude/rules/thinking-pipeline.md`)

1. **Decision** — the contradiction, stated as one sentence, + the IFR.
2. **Evidence per claim** — `file:line` / command output / commit, or an explicit
   `⚠assumption` tag. Don't assert a constraint you haven't checked.
3. **Done-gates** — what "framed enough to plan" looks like (not a step list).
4. **2–3 options**, each evidence-cited, ranked by how close they get to the IFR
   without trading away the thing the contradiction protects.
5. **Model tier** used + recommended for the next stage (`/plan` or `/hats`).

Hand the output to `/plan` (if the path is now obvious) or `/hats` (if it still
needs multi-role judgment).

## Kurallar

- **Reject the 40×39 contradiction matrix and ARIZ.** Both are over-built for
  software framing and domain-mismatched (mechanical-engineering heuristics don't
  transfer cleanly). Use the five primitives above; they cover the framing value
  without the ceremony.
- **Frame, don't solve.** `/triz` produces options and the sharpened question, not
  the implementation. Implementation is `/plan`'s job.
- **A trade-off you can't dissolve is still a valid output** — say so explicitly
  rather than forcing a fake resolution. Recorded as one of the 2-3 options.

## İlgili

- `.claude/rules/thinking-pipeline.md` — lifecycle + selector + shared contract.
- `/hats` — multi-role evaluation of the options this produces.
- `/council` — adversarial decide for one-way doors.
- `/plan` — turns a framed option into a step plan.
