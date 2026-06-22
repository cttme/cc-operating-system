---
name: retro
description: Work-style meta-review — token waste, rework, kill-list, backport candidates, lessons→rules. Run at milestones or quarterly. Generalizes audit-meta (audit-only) to the whole workflow.
allowed-tools: Read, Glob, Grep, Bash, Write
---

# /retro — Work-Style Council

`audit-meta` health-checks the *audit* process. `/retro` does the same for the
**whole work-style** — where tokens went, what got redone, what ceremony never
fired, what deserves promotion. **Every retro must net at least one concrete
removal or promotion** (a retro that changes nothing didn't happen — the
subtraction counterweight against accretion).

Cadence: milestone boundaries or quarterly. Append-only output, never overwrites.

## Window

Default window = since the last retro (or 14 days if none). Accept `$ARGUMENTS`
as `--days N` or `--since YYYY-MM-DD`.

```bash
ls -t tasks/retro/retro-*.md 2>/dev/null | head -1   # last retro = window start
```

## Akış (5 sections → one doc)

### Adım 1 — Token review
```bash
python scripts/cost_breakdown.py --days 14 --detail 2>&1 | head -30
```
Read the per-model split. Flag: **Opus-on-mechanical** spend (top-tier model doing
bookkeeping the `model_routing_hint` hook should have caught), and **resume-tax %**
(cache_creation share). One-line verdict: is the model mix justified by the work mix?

### Adım 1b — Cost per accepted change (outcome, not input)
Token split (§1) is an **input** metric — it says where money went, not whether it
bought anything. Pair it with the **outcome** metric the loop-engineering literature
names as the one almost nobody tracks: **cost per accepted change** + **reject rate**.
```bash
git log --since="<window>" --oneline | wc -l   # changes that shipped (denominator)
# rejected = reverts/redos: cross-ref Adım 2's rework scan
```
- **cost/accepted-change** = in-window spend ÷ commits that *stuck* (not reverted/redone).
  Rising trend = the workflow is spending more to land the same amount of work.
- **reject rate** = (redo+revert) ÷ total. Above ~50% means you're doing review work the
  process should have prevented — that's a rules/gate gap (→ §5), not a model-tier knob.
One-line verdict: is spend-per-landed-change flat or falling? If rising, §2 (rework) and
§5 (lessons→rules) are where the leak is.

### Adım 2 — Rework review
```bash
git log --since="<window>" --oneline | grep -iE "revert|redo|fix.*again|re-|retry" | head
```
Plus scan `tasks/lessons.md` for entries added in-window. Each redo → a
**missing-rule candidate**: would a `.claude/rules/` entry have prevented it?

### Adım 3 — Kill-list (the counterweight)
Which `.claude/rules/` files and ceremony **never fired** in the window?
```bash
for r in .claude/rules/*.md; do
  base=$(basename "$r" .md)
  hits=$(git log --since="<window>" --oneline -- "$r" | wc -l)
  printf "  %-28s edits:%s\n" "$base" "$hits"
done
```
List rules/docs/skills that produced no value in-window → **deletion candidates**
(archive-don't-delete: move to `tasks/archive/`, don't `rm`). Be honest; this is
where bloat dies.

### Adım 4 — Backport candidates
Universal assets created in-window (scripts, rules, hooks) that aren't
domain-locked → promote to `~/.claude/templates` and log in its `BACKPORT.md`.
```bash
git log --since="<window>" --name-only --oneline | grep -E "scripts/|\.claude/rules/|settings" | sort -u | head -20
```
For each: is it generic (universal) or domain-locked (scrapers/matcher/price)?
Only generic ones are candidates.

### Adım 5 — Lessons→rules promotions
```bash
grep -nE "\*\*Count:\*\* [2-9]|\*\*Count:\*\* [0-9]{2}" tasks/lessons.md
```
Any `lessons.md` entry with **Count ≥ 2** has recurred → promote to a stable
`.claude/rules/` entry (or extend an existing one). Recurrence = it's not a
one-off; it's a pattern the automatic gates should enforce.

### Adım 5b — Thinking-method measurement

Ask, for any `/triz`/`/hats`/`/council` runs in-window: **did a thinking-method
change a decision or catch a gap a plain plan would have missed? (y/n + what)**
A "no" across a whole window is a signal the pipeline overhead isn't earning its
keep for the work this project does — note it, don't ignore it. A "yes" is worth
naming concretely (the gap, not just "it helped") so the kill-list (§3) has real
evidence either way.

**Rule kill-quota:** new rules accrete faster than old ones get retired. Pair every
~2 rules added (project-wide, not just this window) with **at least 1 rule
retired** (archived, per §3) — the corpus must stay bounded, not just grow.

### Adım 6 — Write the doc
Write `tasks/retro/retro-YYYY-MM-DD.md` (create `tasks/retro/` if absent). English
output. Structure:

```markdown
# Retro YYYY-MM-DD (window: <start> → today)

## 1. Token review
- Model mix: <Opus %> / <Sonnet %> · cache_creation <X%>
- Opus-on-mechanical waste: <verdict>

## 2. Rework review
- <redo> → missing-rule candidate: <rule or "none">

## 3. Kill-list  (≥1 required across §3+§5)
- [ ] <rule/doc/ceremony> never fired → archive candidate

## 4. Backport candidates
- [ ] <asset> → template (generic) | (domain-locked, skip)

## 5. Lessons→rules promotions
- [ ] <lesson, Count N> → .claude/rules/<file>

## 5b. Thinking-method measurement
- Changed a decision / caught a gap: <y/n + what, per /triz, /hats, /council run>
- Rule kill-quota status: <N added since last check> / <M retired> (target ≥1 per 2)

## Net change (mandatory)
- Removed/promoted this retro: <at least one concrete item>
```

### Adım 7 — Final summary block (to chat)
```
═══════════════════════════════════════════
   /retro <date>  (window: <N> days)
───────────────────────────────────────────
  Token mix:       Opus X% / Sonnet Y%
  Rework events:   N  (→ M rule candidates)
  Kill-list:       N candidates
  Backport:        N candidates
  Promotions:      N (Count≥2)
  Method value:    <y/n — did /triz, /hats, or /council change a call?>
  NET CHANGE:      <removed/promoted item>  ← must be ≥1
═══════════════════════════════════════════
```

## Kurallar

- **Report + propose, don't auto-execute** the kills/promotions — surface them; the
  operator confirms (kills are archive-not-delete; promotions are rule edits).
- **Net ≥ 1 rule:** if §3 and §5 are both empty, the retro failed — look harder.
- **Token-efficient:** every Bash output head/tail-limited; don't full-read lessons.md.
- **One-way doors** discovered mid-retro → route through `/council` per change-protocol.

## İlgili

- `audit-meta` — the audit-only ancestor this generalizes.
- `scripts/cost_breakdown.py` — §1 input.
- `.claude/rules/change-protocol.md` — reversibility axis (kills of HIGH-RISK rules).
- `~/.claude/templates/.../BACKPORT.md` — §4 destination ledger.
- `/council` — escalation for one-way-door findings.
