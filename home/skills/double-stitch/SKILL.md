---
name: double-stitch
description: Validate output produced by a lower-tier model (Ollama or Haiku) before trusting it for downstream use. Apply only on T1+ outputs, structured checklist, sampling-based to keep review cost low. Never on T0 (trivial) outputs.
allowed-tools: Read, Bash, Write
---

# /double-stitch — Validate lower-tier model output

When Claude (current session) receives output from a lower-tier producer
(Ollama via `ask-local`, or a Haiku-class model), this skill governs whether
and how to validate that output before using it for downstream work.

The cost of validation is real. Reviewing everything destroys the token
optimization. So the rules below are deliberately conservative — review
only what the data says is worth reviewing.

## Tier model (recap)

| Tier | Producer example | Reviewer | Default review rate |
|---|---|---|---|
| **T0** | Ollama log summary, short translation | **none** | 0% — output is recoverable if wrong |
| **T1** | Ollama commit classification, JSON extraction | **Claude** (you, inline) | sample 20% + 100% if length > 1K tokens |
| **T2** | Sonnet bulk/script-generated edits, contract/naming/cosmetic changes, migration / prod-bound code | **Opus** (escalate) | diff-only, once per batch, focus on what gates can't see |
| **T3** | Opus output | none (top of stack) | 0% |

This skill mainly covers **T1**. T2 is rarer and follows the same checklist
mechanism with a stricter reviewer.

## When you (Claude) should trigger review

Read each ask-local output's `---OLLAMA-CALL-SUMMARY---` line. Apply this
decision in order:

1. **tier=T0** → never review.
2. **tier=T1, output length > 1000 tokens** → always review.
3. **tier=T1, contains JSON or code block** → always review (format risk).
4. **tier=T1, user_marked_critical = true** → always review.
5. **tier=T1, sampling** → flip a 1-in-5 coin (mod 5 on call hash, or by
   session-call-count). Review if sampled.
6. Otherwise → use as-is, log the skip.

The 20% sampling protects against silent quality drift: even if 80% of
outputs are used unreviewed, the sampled 20% gives a quality signal.

### T2 — Sonnet output (Opus diff-review)

A separate, cheaper gate from the T1 sampling above. Opus reviewing is **not**
cheaper than Opus *doing* for small items, so this is triggered by failure-mode,
not by "Sonnet touched it," and runs **once per batch** (read the cluster of
diffs at the end), **diff-only** — never a re-derivation or a re-run. The whole
point of routing mechanical work to Sonnet is token economics; a blanket
per-item Opus review erodes exactly the saving it's meant to protect.

**Always review (cheap diff pass):**
- script-/bulk-generated edits — a mechanical script produces locally-correct
  but globally-cluttered output that the test suite passes straight through
  (e.g. a bulk anchor pass that stacked dividers instead of converting them)
- changes to a contract / naming / public surface (the consumer-grep category)
- anything where automated gates structurally can't see the failure —
  cosmetics, naming, doc accuracy, architecture

**Skip** (green gates + Sonnet's own per-item doublecheck suffice):
- trivial one-liners, dependency bumps
- anything a passing gate fully covers

Sonnet self-doublechecks each item first; this Opus pass is the second layer,
not the only one. Review the **batch diff at the end**, like a senior reviewing
a PR — not every line as it is typed.

## How to review (structured, not narrative)

Reviewer never reads "is this good?" — it reads a checklist and emits
structured JSON.

### Step 1: Read the producer output and the original input
The Ollama call's `-Prompt` text plus the `---OLLAMA-OUTPUT---` block.

### Step 2: Pick the matching review template
- Pure factual content (summary, translation) → `templates/review-prompts/factual-accuracy.md`
- Structured output (JSON, list, classification) → `templates/review-prompts/format-compliance.md`
- Both apply → run both, merge results

### Step 3: Apply the checklist
The review template is a fixed checklist (Y/N or short list per item).
Do not freelance. Do not add comments unless the template asks.

### Step 4: Emit a structured review record
```json
{
  "review_id": "<short hash of producer output>",
  "reviewer": "claude",
  "template": "factual-accuracy",
  "pass": true,
  "issues": [],
  "action": "use_as_is"
}
```

Possible `action` values:
- `use_as_is` — output passed, proceed normally
- `use_with_caveat` — output mostly OK but has noted issues; surface to user
- `regenerate` — output is bad, retry the original ask-local call with
  improved prompt (typically more constrained)
- `escalate_to_claude` — Ollama can't produce a reliable answer; fall back
  to running the task yourself
- `escalate_to_opus` — uncertainty even after Claude review; user attention needed

### Step 5: Log the review
Append the JSON record to `.ollama-log/<session>/reviews.jsonl`.

## Hard rules (binding)

1. **Reviewer never refines content. Only judges.** If you find a problem,
   recommend `regenerate` with a tighter prompt — do not silently fix and
   pass off as Ollama's output.
2. **Sampling is randomized at decision time, not chosen.** Otherwise you
   bias the sample by skipping the ones you suspect are fine.
3. **Review of a cached output is allowed but cheaper signal.** If output
   was already reviewed once and passed, skip re-review on cache hit.
4. **A reviewer's verdict is not infallible.** If you disagree with a prior
   review (e.g. reviewing a cache hit), log the disagreement and escalate.
5. **Review cost has a ceiling.** If review tokens exceed 20% of total
   Ollama-input tokens for the session, stop sampling new calls and
   surface the imbalance to the user at session end.

## Failure modes to expect

- **Reviewer over-corrects** — Sonnet-class models tend to find nits where
  none exist. Watch the false-positive rate after first ~30 reviews.
- **Reviewer rubber-stamps** — if pass rate is 100% over 30+ reviews, the
  checklist is too lax. Tighten the template.
- **Cache poisoning** — bad output got cached. If review catches it, the
  user should manually `-NoCache` rerun, then delete the bad cache file.

## Output to user (at session end)

`/session-end` should append a block like:

```markdown
## Double-stitch summary
- T1 calls reviewed: 4 of 18 sampled (22%)
- Pass rate: 3/4 (75%)
- Caught issues: 1 (format drift, regenerated successfully)
- Review token cost: ~600 tokens (~$0.01)
- Net win this session: +$0.42 saved by Ollama, -$0.01 review = +$0.41
```

This is the single number that proves the optimization is paying off.

## Related

- `scripts/ask-local.ps1` — producer (emits summary block read by this skill)
- `scripts/ollama-stats.ps1` — feeds `cache_rate` signal used for "skip
  re-review on cache hit" decision
- `templates/review-prompts/` — the checklists
- `.ollama-log/<session>/reviews.jsonl` — review audit trail
